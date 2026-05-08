"""
memory_map.py - Parser de los artefactos del último build sjasmplus
y generador de la estructura JSON que consume el HTML del mapa de memoria.

Lee:
  NuevoJuego.sld         - source-level debug (símbolos con bank explícito)
  code/build_stats.json  - used/free por bank (DISPLAY de sjasmplus)

CLI (útil para debug; el flujo normal es el server llamando a build_model()):
  python tools/memory_map.py             # imprime JSON por stdout
  python tools/memory_map.py --pretty    # JSON indentado
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections import defaultdict
from pathlib import Path

REPO_ROOT     = Path(__file__).resolve().parent.parent
DEFAULT_SLD   = REPO_ROOT / "NuevoJuego.sld"
DEFAULT_STATS = REPO_ROOT / "code" / "build_stats.json"

# ----------------------------------------------------------------------
# Topología del Spectrum 128
# ----------------------------------------------------------------------

SLOT_SIZE = 16384

# Cada slot lógico de la CPU. Slot 3 es paginable.
SLOTS = [
    {"slot": 0, "addr": 0x0000, "fixed_bank": "ROM",  "kind": "rom"},
    {"slot": 1, "addr": 0x4000, "fixed_bank": 5,       "kind": "screen+code"},
    {"slot": 2, "addr": 0x8000, "fixed_bank": 2,       "kind": "data"},
    {"slot": 3, "addr": 0xC000, "fixed_bank": None,    "kind": "pageable",
     "pageable_banks": [0, 1, 3, 4, 6, 7]},
]

# Cada bank físico: en qué slot vive y, por tanto, su dirección lógica base.
BANK_SLOT_BASE = {
    5: 0x4000,                                            # siempre slot 1
    2: 0x8000,                                            # siempre slot 2
    0: 0xC000, 1: 0xC000, 3: 0xC000, 4: 0xC000, 6: 0xC000, 7: 0xC000,  # paginables → slot 3
}

# Etiqueta humana grande para cada bank. Sincronizar con BANK_LABELS de
# parse_build_stats.py si se renombra algún include en main.asm.
BANK_LABELS = {
    0: "main code",
    1: "screen_rooms",
    2: "variables + AY thunks",
    3: "bg_gfx (baseline + neutrals)",
    4: "bg_gfx_b (ruins + cemetery)",
    5: "screen + vars_lo + código slot 1",
    6: "screen_gaps + monster_ai_b6 + sprite_data",
    7: "bg_gfx_c + room_routes_b7 + tombs",
}

# Zonas "fijas" del Spectrum y de nuestro proyecto que no aparecen en el
# .sld como labels colocados pero que ocupan memoria de verdad. Cada entrada
# es (start_logical, end_logical_exclusive, system, friendly_name).
# Se inyectan como regiones sintéticas durante build_regions().
HARDCODED_ZONES = {
    5: [
        (0x4000, 0x5800, "_screen_",   "Screen pixels (VRAM)"),
        (0x5800, 0x5B00, "_screen_",   "Screen attrs (VRAM)"),
        (0x5B00, 0x5D00, "_sys128_",   "System area 128K"),
        # $5D00-$5FFF: variables_lo. Lo declaran con EQU encadenados, así
        # que .sld no los marca con page=5; se reservan aquí.
        (0x5D00, 0x6000, "variables",  "variables_lo (RAM hot)"),
    ],
    7: [
        # Tombstones runtime storage. Reservada por convención
        # (ver check_slot_overlap.py BANK7_BODY_ENTRY_POINTS).
        (0xE000, 0xE800, "_reserved_", "Tombstones runtime ($E000-$E7FF)"),
    ],
}

# ----------------------------------------------------------------------
# Marcadores: líneas críticas y entry points dignos de mostrar.
# ----------------------------------------------------------------------

# Marcadores estáticos por bank: (offset_relativo_al_slot_base, label, severity).
# severity ∈ {"danger", "warn", "info"}.
BOUNDARY_MARKERS_BY_BANK = {
    5: [
        # $7FFF = última dirección válida de slot 1. Si una etiqueta
        # esperada en bank 5 cae más allá, ha desbordado al slot 2 (bank 2)
        # — ese es el bug canónico de room_routes que protege check_slot_overlap.
        (0x3FFF, "CANARY slot 1 · cruzar = overflow al bank 2", "danger"),
    ],
    7: [
        # Reserva de tombstones runtime. No es hardware, es convención
        # del proyecto (TombStore escribe ahí en runtime).
        (0x2000, "Tombstones runtime START ($E000) · no code aquí", "warn"),
        (0x2800, "Tombstones runtime END ($E7FF) · libre encima", "warn"),
    ],
}

# Etiquetas notables a buscar en el .sld y marcar como landmarks. Replica los
# SLOT1_ENTRY_POINTS de check_slot_overlap.py para que ambos vayan a la par.
LANDMARK_LABELS = {
    "Inicio":                     "Entry point del juego",
    "MainLoop":                   "Loop principal (IRQ entry)",
    "LoadBgSpriteToBuffer":       "Thunk paginación de gfx",
    "TombStore":                  "Almacena tumba en runtime ($E000+)",
    "AY_PlayPlayerHit":           "SFX hit (AY canal B)",
    "GiveLife":                   "Pickup de vida — entry de slot 1",
    "ApplyMagicCompassBuff":      "Pickup de brújula — entry slot 1",
    "RoomCompGapsTable":          "CANARY · primera entrada del overflow",
    "DrawTombstone2xCentered":    "Thunk paginación bank 7 (Game Over)",
    "StartTownGateCutscene":      "Trigger cutscene M9",
    "UpdateTownGateCutscene":     "Update cutscene M9",
}

# ----------------------------------------------------------------------
# Agrupación automática .asm → "system"
# ----------------------------------------------------------------------

# Reglas explícitas para fusionar ficheros que pertenecen al mismo sistema
# pero cuyo prefijo natural es ambiguo. Lo demás cae a su nombre tal cual
# (sin la extensión .asm).
EXPLICIT_SYSTEMS = {
    "ay_sound":            "audio",
    "ay_sound_thunks":     "audio",
    "sfx_player_hit_ay":   "audio",
    "sound":               "audio",
    "music_irq":           "audio",
    "bg_gfx":              "bg_gfx",
    "bg_gfx_b":            "bg_gfx",
    "bg_gfx_c":            "bg_gfx",
    "monster_ai":          "monster_ai",
    "monster_ai_bank6":    "monster_ai",
    "room_routes":         "room_routes",
    "room_routes_bank7":   "room_routes",
    "screen_data":         "screen_layout",
    "screen_gaps":         "screen_layout",
    "screen_rooms":        "screen_layout",
    "screen_system":       "screen_layout",
    "town_gate_cutscene":  "cutscenes",
    "church_cutscene":     "cutscenes",
    "game_over_tomb":      "game_over",
    "game_over_tomb_thunk":"game_over",
    "variables":           "variables",
    "variables_lo":        "variables",
}


def _system_for_file(asm_file: str) -> str:
    base = asm_file.replace(".asm", "").replace(".inc", "")
    return EXPLICIT_SYSTEMS.get(base, base)


def _color_for(system: str) -> str:
    """Color HSL determinista por nombre, con casos especiales."""
    if system == "_FREE_":
        return "#1a1a1a"
    if system == "_screen_":
        return "#3a5fcd"           # azul VRAM
    if system == "_sys128_":
        return "#5a4a6a"           # morado apagado, zona reservada por SO
    if system == "_reserved_":
        return "#704020"           # ámbar oscuro, tombstones runtime
    if system.startswith("_"):
        return "#666"
    # Hash determinista → hue.
    h = 0
    for c in system:
        h = (h * 33 + ord(c)) & 0xFFFFFF
    hue = h % 360
    return f"hsl({hue},58%,52%)"

# ----------------------------------------------------------------------
# Parsing
# ----------------------------------------------------------------------


def parse_sld(sld_path: Path):
    """
    Devuelve lista de tuplas (file, line, page, addr, parent, sublabel, attrs).
    Filtra a registros L con page real (0..7) y descarta EQUs (no representan
    bytes emitidos por el ensamblador, son sólo aliases simbólicos).
    """
    out = []
    with sld_path.open(encoding="utf-8", errors="replace") as f:
        for raw in f:
            raw = raw.rstrip("\r\n")
            if not raw or raw.startswith("|"):  # cabecera "|SLD.data.version|1"
                continue
            parts = raw.split("|")
            if len(parts) < 8:
                continue
            try:
                page = int(parts[4])
                addr = int(parts[5])
            except ValueError:
                continue
            if page < 0:
                continue
            if parts[6] != "L":
                continue
            name_field = parts[7]
            tokens = name_field.split(",")
            # Formato: ",parent,sublabel,+attr,+attr"
            if len(tokens) < 2:
                continue
            parent = tokens[1]
            sublabel = tokens[2] if len(tokens) > 2 else ""
            attrs = [t for t in tokens[3:] if t.startswith("+")]
            if "+equ" in attrs:
                continue  # constante simbólica, no un placement
            file = parts[0]
            try:
                line = int(parts[1])
            except ValueError:
                line = 0
            out.append((file, line, page, addr, parent, sublabel, attrs))
    return out

# ----------------------------------------------------------------------
# Construcción de regiones (agrupación de símbolos consecutivos por sistema)
# ----------------------------------------------------------------------


def _build_regions_for_bank(bank: int, syms: list, used_bytes: int) -> list[dict]:
    slot_base = BANK_SLOT_BASE.get(bank, 0xC000)
    bank_end_logical = slot_base + SLOT_SIZE

    # Ordenar por dirección y quedarse con top-level (sin sublabels) para
    # definir los límites de cada region; los sublocals se quedan como
    # "labels detallados" del padre más cercano.
    syms_sorted = sorted(syms, key=lambda s: s[3])
    top_level = [s for s in syms_sorted if not s[5]]

    regions: list[dict] = []
    if top_level:
        # Pre-pasada: definir start_addr de cada region por sistema.
        for i, (file, _l, _p, addr, parent, _sub, _attrs) in enumerate(top_level):
            system = _system_for_file(file)
            if regions and regions[-1]["system"] == system:
                regions[-1]["labels"].append(parent)
            else:
                regions.append({
                    "system": system,
                    "color": _color_for(system),
                    "start_addr": addr,
                    "end_addr": addr,   # se rellenará al cerrar la región
                    "size": 0,
                    "labels": [parent],
                    "files": {file},
                })
            regions[-1]["files"].add(file)
        # Cerrar end_addr de cada region usando el start de la siguiente.
        for i, r in enumerate(regions):
            if i + 1 < len(regions):
                r["end_addr"] = regions[i + 1]["start_addr"]
            else:
                # Última region: usar build_stats.used_bytes como tope.
                tail = slot_base + used_bytes
                r["end_addr"] = max(r["start_addr"], tail)
            r["size"] = r["end_addr"] - r["start_addr"]

    # Inyectar zonas hardcoded del bank (screen, attrs, vars_lo, etc.).
    for start, end, system, _name in HARDCODED_ZONES.get(bank, []):
        regions.append({
            "system": system,
            "color": _color_for(system),
            "start_addr": start,
            "end_addr": end,
            "size": end - start,
            "labels": [],
            "files": set(),
            "_synthetic": True,
        })

    # Resolver solapamientos: las regions hardcoded ganan prioridad (ej. en
    # bank 5 las labels emitidas en $6000+ NO solapan con las hardcoded de
    # $4000-$5FFF, pero por seguridad recortamos solapamientos).
    regions.sort(key=lambda r: r["start_addr"])
    cleaned: list[dict] = []
    for r in regions:
        if cleaned and r["start_addr"] < cleaned[-1]["end_addr"]:
            # Solapamiento: el nuevo empieza antes de que termine el anterior.
            # Aceptar el hardcoded si lo hay; si ambos son normales, recortar.
            if r.get("_synthetic"):
                # Recortar el anterior.
                cleaned[-1]["end_addr"] = r["start_addr"]
                cleaned[-1]["size"] = cleaned[-1]["end_addr"] - cleaned[-1]["start_addr"]
            elif cleaned[-1].get("_synthetic"):
                r["start_addr"] = cleaned[-1]["end_addr"]
                r["size"] = max(0, r["end_addr"] - r["start_addr"])
            else:
                # Ambos reales: el actual se desplaza.
                r["start_addr"] = cleaned[-1]["end_addr"]
                r["size"] = max(0, r["end_addr"] - r["start_addr"])
        if r["size"] > 0:
            cleaned.append(r)

    # Rellenar huecos con _FREE_.
    full: list[dict] = []
    cursor = slot_base
    for r in cleaned:
        if r["start_addr"] > cursor:
            full.append({
                "system": "_FREE_",
                "color": _color_for("_FREE_"),
                "start_addr": cursor,
                "end_addr": r["start_addr"],
                "size": r["start_addr"] - cursor,
                "labels": [],
                "files": [],
            })
        full.append(r)
        cursor = r["end_addr"]
    if cursor < bank_end_logical:
        full.append({
            "system": "_FREE_",
            "color": _color_for("_FREE_"),
            "start_addr": cursor,
            "end_addr": bank_end_logical,
            "size": bank_end_logical - cursor,
            "labels": [],
            "files": [],
        })

    # Convertir 'files' set → list para serializar a JSON.
    for r in full:
        if isinstance(r.get("files"), set):
            r["files"] = sorted(r["files"])
        # Clip lista de labels a primeros 50 (para tooltips razonables).
        if len(r.get("labels", [])) > 50:
            r["labels_truncated"] = len(r["labels"]) - 50
            r["labels"] = r["labels"][:50]
    return full

# ----------------------------------------------------------------------
# Modelo top-level
# ----------------------------------------------------------------------


def _markers_for_bank(bank: int, syms: list, slot_base: int) -> list[dict]:
    """Calcula la lista de marcadores para un bank. Combina:
       - boundaries hardcoded de BOUNDARY_MARKERS_BY_BANK,
       - landmarks (entry points) que aparezcan en este bank en el .sld.
    """
    markers: list[dict] = []
    for offset, label, severity in BOUNDARY_MARKERS_BY_BANK.get(bank, []):
        markers.append({
            "offset": offset,
            "addr":   slot_base + offset,
            "label":  label,
            "severity": severity,
            "kind":   "boundary",
        })
    # Landmarks: top-level labels que estén en LANDMARK_LABELS.
    seen_landmarks = set()
    for file, _line, _page, addr, parent, sublabel, _attrs in syms:
        if sublabel:           # ignorar locals
            continue
        if parent in LANDMARK_LABELS and parent not in seen_landmarks:
            seen_landmarks.add(parent)
            markers.append({
                "offset":   addr - slot_base,
                "addr":     addr,
                "label":    parent,
                "tooltip":  LANDMARK_LABELS[parent],
                "severity": "info",
                "kind":     "landmark",
            })
    markers.sort(key=lambda m: m["offset"])
    return markers


def build_model(sld_path: Path = DEFAULT_SLD,
                stats_path: Path = DEFAULT_STATS) -> dict:
    syms = parse_sld(sld_path) if sld_path.exists() else []
    by_bank: dict[int, list] = defaultdict(list)
    for s in syms:
        by_bank[s[2]].append(s)

    if stats_path.exists():
        stats = json.loads(stats_path.read_text(encoding="utf-8"))
        bank_used = {int(k): v["used_bytes"] for k, v in stats["banks"].items()}
        build_ts = stats.get("timestamp")
    else:
        stats = {"banks": {}}
        bank_used = {}
        build_ts = None

    # Bank 5 no aparece en build_stats; estimar su 'used_bytes' como
    # max(addr) - $4000, redondeado al alza en 16 B (decoración).
    if 5 in by_bank and 5 not in bank_used:
        max_addr = max(s[3] for s in by_bank[5])
        bank_used[5] = max_addr - 0x4000
    # Bank 2 idem si no figura.
    if 2 in by_bank and 2 not in bank_used:
        max_addr = max(s[3] for s in by_bank[2])
        bank_used[2] = max_addr - 0x8000

    banks_out = []
    for b in (0, 1, 2, 3, 4, 5, 6, 7):
        used = bank_used.get(b, 0)
        slot_base = BANK_SLOT_BASE.get(b, 0xC000)
        regions = _build_regions_for_bank(b, by_bank.get(b, []), used)
        markers = _markers_for_bank(b, by_bank.get(b, []), slot_base)
        banks_out.append({
            "bank": b,
            "label": BANK_LABELS.get(b, ""),
            "size_bytes": SLOT_SIZE,
            "used_bytes": used,
            "free_bytes": SLOT_SIZE - used,
            "slot_base": slot_base,
            "regions": regions,
            "markers": markers,
        })

    return {
        "timestamp": int(time.time()),
        "build_stats_timestamp": build_ts,
        "topology": {
            "slot_size": SLOT_SIZE,
            "slots": SLOTS,
        },
        "banks": banks_out,
    }


def summarize(model: dict) -> dict:
    """Resumen compacto pensado para snapshots/diff. NO incluye regiones
    completas (sería ruidoso); sólo totales por bank y por sistema.
    """
    by_system: dict[str, dict] = {}
    banks_used: dict[int, int] = {}
    banks_free: dict[int, int] = {}
    total_used = 0
    total_free = 0

    for b in model["banks"]:
        bn = b["bank"]
        banks_used[bn] = b["used_bytes"]
        banks_free[bn] = b["free_bytes"]
        total_used += b["used_bytes"]
        total_free += b["free_bytes"]
        for r in b["regions"]:
            sys = r["system"]
            cur = by_system.setdefault(sys, {"bytes": 0, "regions": 0})
            cur["bytes"] += r["size"]
            cur["regions"] += 1

    return {
        "timestamp": model["timestamp"],
        "build_stats_timestamp": model.get("build_stats_timestamp"),
        "by_system": by_system,
        "banks_used": banks_used,
        "banks_free": banks_free,
        "total_used": total_used,
        "total_free": total_free,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sld",   type=Path, default=DEFAULT_SLD)
    p.add_argument("--stats", type=Path, default=DEFAULT_STATS)
    p.add_argument("--pretty", action="store_true")
    args = p.parse_args(argv)

    if not args.sld.exists():
        print(f"WARN: no existe {args.sld} (¿hace falta build?)", file=sys.stderr)
    model = build_model(args.sld, args.stats)
    if args.pretty:
        print(json.dumps(model, indent=2))
    else:
        print(json.dumps(model))
    return 0


if __name__ == "__main__":
    sys.exit(main())
