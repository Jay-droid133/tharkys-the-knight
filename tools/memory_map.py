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
import re
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


# ----------------------------------------------------------------------
# v3: Call graph, heat propagation, dead code, move cost, cohesion
# ----------------------------------------------------------------------

# Entry points conocidos del juego. Sirven como raíces para BFS de heat.
# - MainLoop: bucle principal (HALT a 50 Hz).
# - MusicIrqHandler: handler de IM 2 (50 Hz desde el bus IRQ).
# - Inicio: punto de entrada del juego (init, una vez por partida).
ENTRY_POINTS_DEFAULT = ["Inicio", "MainLoop", "MusicIrqHandler"]
RUNTIME_ENTRY_POINTS = ["MainLoop", "MusicIrqHandler"]   # cosas que rulan a 50 Hz
INIT_ENTRY_POINTS    = ["Inicio"]                         # cosas que sólo se ejecutan una vez

# Banks que viven en slot 3 (paginables). Una llamada entre dos banks de
# este conjunto, si NO comparten slot 3 simultáneamente, requiere thunk.
SLOT3_BANKS = frozenset({0, 1, 3, 4, 6, 7})

# Bytes estimados del thunk típico (LD A,bank / OUT $7FFD / CALL body /
# LD A,prev_bank / OUT $7FFD / RET) ~ 12-15 B. Estimación conservadora.
ESTIMATED_THUNK_BYTES = 14
# Ciclos T extra por llamada vía thunk (paging + restore, sin contar
# el push del prev_bank). Estimación grosera: 30 T-states.
ESTIMATED_THUNK_TSTATES = 30

# Regex para detectar CALL/JP/JR con label. El target permite `.foo`
# (locals) y `Foo.bar` (sublabels) — los filtramos después por separado.
_CALL_RE = re.compile(
    r'(?:^|:)\s*(CALL|JP|JR)\b\s+'
    r'(?:([A-Z]{1,2})\s*,\s*)?'
    r'(\.?[A-Za-z_][\w.]*)\b',
    re.IGNORECASE,
)

# Flags de condición Z80. Si una de estas aparece como "target" es porque
# el regex se confundió (ej. `JR Z` sin label, raro pero defensivo).
_CONDITION_FLAGS = frozenset({"Z", "NZ", "NC", "C", "M", "P", "PE", "PO"})


def parse_call_sites(code_dir: Path,
                     included_files: set[str] | None = None) -> list[dict]:
    """Recorre todos los .asm de code_dir buscando call sites estáticos.
    Devuelve list of {file, line, kind, condition, target}.
    Filtra:
      - Comentarios (todo tras `;`).
      - Indirectos `JP (HL)`, `CALL (IX+0)`.
      - Targets que sean locals (`.foo`) o sublabels (`Foo.bar`) — son
        internos, no cruzan banks; el análisis cross-bank no los necesita.
      - Targets que sean flags de condición (Z, NZ, ...) — defensivo.
      - Ficheros NO incluidos por main.asm (si `included_files` se pasa).
        Los .asm orphan WIP no aportan info al análisis.
    """
    sites: list[dict] = []
    for asm in sorted(code_dir.glob("*.asm")):
        if included_files is not None and asm.name not in included_files:
            continue
        try:
            with asm.open(encoding="utf-8", errors="replace") as f:
                for lineno, raw in enumerate(f, 1):
                    code = raw.split(";", 1)[0]
                    if not re.search(r'\b(CALL|JP|JR)\b', code, re.IGNORECASE):
                        continue
                    if re.search(r'\b(CALL|JP|JR)\s*\(', code, re.IGNORECASE):
                        continue
                    m = _CALL_RE.search(code)
                    if not m:
                        continue
                    target = m.group(3)
                    # Skip locals, sublabels y flags.
                    if target.startswith(".") or "." in target:
                        continue
                    if target.upper() in _CONDITION_FLAGS:
                        continue
                    sites.append({
                        "file": asm.name,
                        "line": lineno,
                        "kind": m.group(1).upper(),
                        "condition": m.group(2),
                        "target": target,
                    })
        except Exception:
            continue
    return sites


def _build_label_index(symbols: list) -> dict[str, list[tuple]]:
    """Por fichero, devuelve lista de (line, label_name, page) de los labels
    top-level (sin sublabel), ordenada por línea ascendente. Permite resolver
    en O(log N) qué label engloba un (file, line) dado.
    """
    by_file: dict[str, list[tuple]] = defaultdict(list)
    for (file, line, page, addr, parent, sublabel, attrs) in symbols:
        if sublabel:
            continue
        by_file[file].append((line, parent, page))
    for k in by_file:
        by_file[k].sort(key=lambda x: x[0])
    return dict(by_file)


def _label_containing(label_index: dict, file: str, line: int):
    """Binary search del label top-level más cercano antes de `line` en `file`.
    Devuelve (label_name, page) o (None, None).
    """
    labels = label_index.get(file, [])
    if not labels:
        return None, None
    lo, hi = 0, len(labels) - 1
    best = None
    while lo <= hi:
        mid = (lo + hi) // 2
        if labels[mid][0] <= line:
            best = labels[mid]
            lo = mid + 1
        else:
            hi = mid - 1
    if best is None:
        return None, None
    return best[1], best[2]


def build_call_graph(sld_path: Path = DEFAULT_SLD,
                     code_dir: Path | None = None) -> dict:
    """Construye el grafo de llamadas estático a partir de los .asm + .sld.

    Returns:
        {
          "edges": [{caller_label, caller_bank, target, target_bank,
                     kind, condition, caller_file, caller_line, cross_bank}],
          "total_call_sites": int,
          "resolved_count": int,
          "unresolved_count": int,
          "resolution_rate_pct": float,
        }
    Calls a labels que no aparecen en el .sld (macros, externos,
    typos) cuentan como unresolved y se reportan en el resumen.
    """
    if code_dir is None:
        code_dir = REPO_ROOT / "code"

    symbols = parse_sld(sld_path) if sld_path.exists() else []
    # Sólo ficheros que aparezcan en el .sld (i.e. INCLUDEados en main.asm).
    # Esto descarta WIP/orphan .asm que mete ruido en el análisis.
    included_files = {sym[0] for sym in symbols if not sym[5]}
    sites = parse_call_sites(code_dir, included_files=included_files)
    label_index = _build_label_index(symbols)

    target_by_name: dict[str, dict] = {}
    for (file, line, page, addr, parent, sublabel, attrs) in symbols:
        if sublabel:
            continue
        # Si un mismo label aparece varias veces (raro pero posible), nos
        # quedamos con el primero (página más fiable).
        target_by_name.setdefault(parent, {
            "file": file, "line": line, "page": page, "addr": addr,
        })

    edges: list[dict] = []
    unresolved = 0
    for cs in sites:
        ti = target_by_name.get(cs["target"])
        if ti is None:
            unresolved += 1
            continue
        caller_label, caller_bank = _label_containing(
            label_index, cs["file"], cs["line"])
        edges.append({
            "caller_file":  cs["file"],
            "caller_line":  cs["line"],
            "caller_label": caller_label,
            "caller_bank":  caller_bank,
            "kind":         cs["kind"],
            "condition":    cs["condition"],
            "target":       cs["target"],
            "target_file":  ti["file"],
            "target_line":  ti["line"],
            "target_bank":  ti["page"],
            "cross_bank":   (caller_bank is not None
                             and caller_bank != ti["page"]),
        })

    total = len(sites)
    return {
        "edges": edges,
        "total_call_sites":     total,
        "resolved_count":       len(edges),
        "unresolved_count":     unresolved,
        "resolution_rate_pct":  round(100.0 * len(edges) / max(1, total), 2),
    }


def propagate_heat(graph: dict,
                   entry_points: list[str] | None = None) -> dict[str, dict]:
    """BFS desde cada entry point para dar a cada label una distancia mínima
    en saltos. Clasifica cada label en una categoría según la distancia al
    entry point runtime más cercano:

      - lava  : reachable desde MainLoop o IRQ con depth ≤ 2.
      - warm  : reachable runtime con depth 3-5.
      - cool  : reachable runtime con depth ≥ 6.
      - init  : sólo reachable desde Inicio (boot, una vez por partida).
      - dead  : no reachable desde ningún entry point.
    """
    if entry_points is None:
        entry_points = ENTRY_POINTS_DEFAULT

    adj: dict[str, set[str]] = defaultdict(set)
    for e in graph["edges"]:
        if e["caller_label"]:
            adj[e["caller_label"]].add(e["target"])

    distances: dict[str, dict[str, int]] = {ep: {} for ep in entry_points}
    for ep in entry_points:
        distances[ep][ep] = 0
        queue = [(ep, 0)]
        while queue:
            label, d = queue.pop(0)
            for callee in adj.get(label, ()):
                if callee not in distances[ep]:
                    distances[ep][callee] = d + 1
                    queue.append((callee, d + 1))

    all_labels: set[str] = set()
    for ep_d in distances.values():
        all_labels.update(ep_d.keys())

    INF = float('inf')
    heat: dict[str, dict] = {}
    for label in all_labels:
        runtime_d = INF
        runtime_via = None
        for ep in RUNTIME_ENTRY_POINTS:
            d = distances.get(ep, {}).get(label, INF)
            if d < runtime_d:
                runtime_d = d
                runtime_via = ep
        init_d = INF
        for ep in INIT_ENTRY_POINTS:
            d = distances.get(ep, {}).get(label, INF)
            if d < init_d:
                init_d = d

        if runtime_d <= 2:
            level = "lava"
        elif runtime_d <= 5:
            level = "warm"
        elif runtime_d != INF:
            level = "cool"
        elif init_d != INF:
            level = "init"
        else:
            level = "dead"

        heat[label] = {
            "level":      level,
            "runtime_depth": (runtime_d if runtime_d != INF else None),
            "runtime_via":   runtime_via,
            "init_depth":    (init_d if init_d != INF else None),
        }

    return heat


def find_dead_code(graph: dict,
                   entry_points: list[str] | None = None,
                   code_dir: Path | None = None,
                   sld_path: Path = DEFAULT_SLD) -> list[dict]:
    """Detecta labels NO reachable desde ningún entry point.

    Estrategia:
      1. Universo: TODOS los top-level labels del .sld (con bank real,
         no EQU constantes).
      2. Reachable: BFS desde entry_points sobre las edges del grafo.
      3. Unreachable = Universo \\ Reachable.
      4. Filtro conservador: si un label aparece >1 vez en los .asm
         (i.e. fuera de su propia definición), está referenciado como
         dato (LD HL,X / DEFW X / tabla) → NO se considera muerto.

    Returns: list of {label, addr, bank, file, line, occurrences}.
    """
    if code_dir is None:
        code_dir = REPO_ROOT / "code"
    if entry_points is None:
        entry_points = ENTRY_POINTS_DEFAULT

    # 1. Universo de labels top-level con bank.
    symbols = parse_sld(sld_path) if sld_path.exists() else []
    universe: dict[str, dict] = {}
    for (file, line, page, addr, parent, sublabel, attrs) in symbols:
        if sublabel:
            continue
        # Quedarse con la primera aparición.
        universe.setdefault(parent, {
            "file": file, "line": line, "bank": page, "addr": addr,
        })

    # 2. Reachable via BFS desde entry points sobre el grafo.
    adj: dict[str, set[str]] = defaultdict(set)
    for e in graph["edges"]:
        if e["caller_label"]:
            adj[e["caller_label"]].add(e["target"])
    reachable: set[str] = set(entry_points)
    queue = list(entry_points)
    while queue:
        cur = queue.pop(0)
        for callee in adj.get(cur, ()):
            if callee not in reachable:
                reachable.add(callee)
                queue.append(callee)

    # 3. Candidatos: en universo pero no reachable.
    candidates = [lbl for lbl in universe if lbl not in reachable]
    if not candidates:
        return []

    # 4. Single-pass scan de los .asm para contar ocurrencias.
    blob_parts: list[str] = []
    for asm in code_dir.glob("*.asm"):
        try:
            blob_parts.append(asm.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            pass
    blob = "\n".join(blob_parts)

    out: list[dict] = []
    for label in candidates:
        ref_re = re.compile(r'\b' + re.escape(label) + r'\b')
        n = len(ref_re.findall(blob))
        # n == 1: sólo aparece la línea de definición → muerto seguro.
        # n > 1: referenciado en otro sitio (LD HL,X / DEFW X / etc).
        info = universe[label]
        out.append({
            "label": label,
            "file":  info["file"],
            "line":  info["line"],
            "bank":  info["bank"],
            "addr":  info["addr"],
            "occurrences": n,
            "conservative_safe": (n <= 1),
        })
    # Devolver sólo los conservatively safe (no referenciados como dato).
    out = [x for x in out if x["conservative_safe"]]
    return sorted(out, key=lambda x: (x.get("bank") or 99, x["label"]))


def cohesion_per_system(graph: dict,
                        sld_path: Path = DEFAULT_SLD) -> dict[str, dict]:
    """Para cada sistema, calcula:
      - internal:  calls dentro del propio sistema
      - incoming:  calls desde otros sistemas hacia el nuestro
      - outgoing:  calls desde nosotros hacia otros sistemas
      - cohesion_pct = internal / (internal + incoming) * 100
        (qué % de las llamadas hacia mí vienen de mi propio sistema.
         Alto = self-contained = barato de mover.)
    """
    symbols = parse_sld(sld_path) if sld_path.exists() else []
    label_system: dict[str, str] = {}
    for (file, line, page, addr, parent, sublabel, attrs) in symbols:
        if not sublabel:
            label_system[parent] = _system_for_file(file)

    stats: dict[str, dict] = defaultdict(
        lambda: {"internal": 0, "incoming": 0, "outgoing": 0})
    for e in graph["edges"]:
        cs = label_system.get(e["caller_label"]) if e["caller_label"] else None
        ts = label_system.get(e["target"])
        if not cs or not ts:
            continue
        if cs == ts:
            stats[cs]["internal"] += 1
        else:
            stats[cs]["outgoing"]  += 1
            stats[ts]["incoming"]  += 1

    out: dict[str, dict] = {}
    for sys, s in stats.items():
        total_in = s["internal"] + s["incoming"]
        cohesion = s["internal"] / total_in if total_in else 1.0
        out[sys] = {**s,
                    "total_incoming_or_internal": total_in,
                    "cohesion_pct": round(cohesion * 100, 1)}
    return dict(sorted(out.items(),
                       key=lambda kv: -kv[1]["cohesion_pct"]))


def _needs_thunk(target_bank: int | None, caller_bank: int | None) -> bool:
    """Determina si una llamada caller→target necesita thunk.

    Reglas de paging del Spectrum 128:
      - Target en slot 1 (bank 5) o slot 2 (bank 2): siempre visible
        desde cualquier sitio → NO thunk.
      - Target en slot 3 (banks 0/1/3/4/6/7): visible sólo si está
        paginado AHORA. Si caller está en slot 3 con el MISMO bank,
        comparten visibilidad → NO thunk. En cualquier otro caso
        (caller en slot 1/2 distinto, o slot 3 diferente bank) → SÍ thunk.
    """
    if target_bank is None:
        return False
    if target_bank not in SLOT3_BANKS:
        return False
    if caller_bank is None:
        # Caller desconocido: conservador, asumir thunk necesario.
        return True
    return caller_bank != target_bank


def simulate_move(graph: dict,
                  system: str,
                  from_bank: int,
                  to_bank: int,
                  sld_path: Path = DEFAULT_SLD) -> dict:
    """Simula mover todas las regiones de `system` que están en `from_bank`
    al `to_bank`. Estima delta de thunks (a nivel TARGET LABEL — un thunk
    sirve para cualquier número de callers a un mismo target).

    Devuelve además el desglose por target para razonar caso por caso.
    """
    symbols = parse_sld(sld_path) if sld_path.exists() else []
    moved: set[str] = set()
    for (file, line, page, addr, parent, sublabel, attrs) in symbols:
        if sublabel:
            continue
        if page == from_bank and _system_for_file(file) == system:
            moved.add(parent)

    # Group edges by target.
    by_target: dict[str, list] = defaultdict(list)
    for e in graph["edges"]:
        if e["target"] in moved:
            by_target[e["target"]].append(e)

    new_thunks: dict[str, list] = {}
    obsolete:   dict[str, list] = {}
    persistent: dict[str, list] = {}

    for target, edges in by_target.items():
        was = any(_needs_thunk(from_bank, e["caller_bank"]) for e in edges)
        will = any(_needs_thunk(to_bank,   e["caller_bank"]) for e in edges)
        if (not was) and will:
            new_thunks[target] = edges
        elif was and (not will):
            obsolete[target]   = edges
        elif was and will:
            persistent[target] = edges

    new_call_sites = sum(
        1 for edges in new_thunks.values()
        for e in edges if _needs_thunk(to_bank, e["caller_bank"])
    )
    obs_call_sites = sum(
        1 for edges in obsolete.values()
        for e in edges if _needs_thunk(from_bank, e["caller_bank"])
    )

    return {
        "system": system,
        "from_bank": from_bank,
        "to_bank":   to_bank,
        "moved_labels_count":     len(moved),
        "new_thunks_needed":      len(new_thunks),
        "new_call_sites":         new_call_sites,
        "obsolete_thunks":        len(obsolete),
        "obsolete_call_sites":    obs_call_sites,
        "persistent_thunks":      len(persistent),
        "net_thunks":             len(new_thunks) - len(obsolete),
        "estimated_thunk_bytes_delta":
            (len(new_thunks) - len(obsolete)) * ESTIMATED_THUNK_BYTES,
        "details": {
            "new_thunks_by_target": {
                k: len(v) for k, v in sorted(new_thunks.items(),
                                              key=lambda kv: -len(kv[1]))
            },
            "obsolete_thunks_by_target": {
                k: len(v) for k, v in obsolete.items()
            },
        },
    }


def callers_of(graph: dict, label: str) -> list[dict]:
    """Devuelve los call sites que apuntan a `label`."""
    return [e for e in graph["edges"] if e["target"] == label]


def callees_of(graph: dict, label: str) -> list[dict]:
    """Devuelve los call sites originados desde `label`."""
    return [e for e in graph["edges"] if e["caller_label"] == label]


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


def _print_json(obj, pretty: bool):
    print(json.dumps(obj, indent=2 if pretty else None, default=str))


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sld",   type=Path, default=DEFAULT_SLD)
    p.add_argument("--stats", type=Path, default=DEFAULT_STATS)
    p.add_argument("--pretty", action="store_true")

    g = p.add_argument_group("v3 analysis")
    g.add_argument("--callgraph", action="store_true",
                   help="Dump grafo de llamadas completo (JSON).")
    g.add_argument("--callers", metavar="LABEL",
                   help="Lista los call sites que apuntan al LABEL.")
    g.add_argument("--callees", metavar="LABEL",
                   help="Lista los call sites originados desde el LABEL.")
    g.add_argument("--heat", action="store_true",
                   help="Clasifica cada label en lava/warm/cool/init/dead.")
    g.add_argument("--dead", action="store_true",
                   help="Lista código muerto (no reachable + no referenciado como dato).")
    g.add_argument("--cohesion", action="store_true",
                   help="Tabla de cohesión por sistema (% calls internas).")
    g.add_argument("--movecost", metavar="SYSTEM",
                   help="Simula mover SYSTEM. Usa también --from y --to.")
    g.add_argument("--from", dest="from_bank", type=int,
                   help="Bank origen para --movecost.")
    g.add_argument("--to", dest="to_bank", type=int,
                   help="Bank destino para --movecost.")

    args = p.parse_args(argv)

    if not args.sld.exists():
        print(f"WARN: no existe {args.sld} (¿hace falta build?)", file=sys.stderr)

    # Construir grafo si cualquier flag de v3 lo necesita.
    needs_graph = (
        args.callgraph or args.callers or args.callees or args.heat
        or args.dead or args.cohesion or args.movecost
    )
    graph = build_call_graph(args.sld) if needs_graph else None

    if args.callgraph:
        _print_json(graph, args.pretty)
        return 0
    if args.callers:
        _print_json({
            "label": args.callers,
            "callers": callers_of(graph, args.callers),
            "count": len(callers_of(graph, args.callers)),
        }, args.pretty)
        return 0
    if args.callees:
        _print_json({
            "label": args.callees,
            "callees": callees_of(graph, args.callees),
            "count": len(callees_of(graph, args.callees)),
        }, args.pretty)
        return 0
    if args.heat:
        _print_json({
            "entry_points": ENTRY_POINTS_DEFAULT,
            "heat": propagate_heat(graph),
        }, args.pretty)
        return 0
    if args.dead:
        dead = find_dead_code(graph)
        _print_json({"count": len(dead), "dead": dead}, args.pretty)
        return 0
    if args.cohesion:
        _print_json(cohesion_per_system(graph, args.sld), args.pretty)
        return 0
    if args.movecost:
        if args.from_bank is None or args.to_bank is None:
            print("ERROR: --movecost requiere --from N y --to M",
                  file=sys.stderr)
            return 2
        _print_json(simulate_move(graph, args.movecost,
                                   args.from_bank, args.to_bank,
                                   args.sld), args.pretty)
        return 0

    # Default: dump del modelo entero.
    model = build_model(args.sld, args.stats)
    _print_json(model, args.pretty)
    return 0


if __name__ == "__main__":
    sys.exit(main())
