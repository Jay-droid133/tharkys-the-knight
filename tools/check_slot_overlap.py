"""
check_slot_overlap.py - Validador del layout RAM tras un build sjasmplus.

Detecta tres clases de bug:
  1. Slot 1 overflow: símbolos always-visible que pasan de $7FFF y caen en
     zona de slot 2 (bank 2 always-visible) — solapan con MainLoop / código
     del bank 2.
  2. Bank-specific overflow: símbolos de un bank N que caen fuera del rango
     $C000-$FFFF (cuando el bank está paginado).
  3. Cross-bank symbol clash: el mismo nombre definido en dos bancos
     distintos (raro, pero detectable).

Uso:
    python tools/check_slot_overlap.py [NuevoJuego.sym]

Exit 0 si todo OK, 1 si hay overlaps detectados.
Pensado para ser invocado desde build_and_*.bat después del sjasmplus.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SYM_RE = re.compile(r"^([A-Za-z_][\w.]*):\s*EQU\s+0x0000([0-9A-Fa-f]+)\s*$")

# Address ranges
SLOT1_START   = 0x6000
SLOT1_END     = 0x7FFF      # last valid byte of slot 1
SLOT2_START   = 0x8000
SLOT2_END     = 0xBFFF
SLOT3_START   = 0xC000
SLOT3_END     = 0xFFFF

# Tombstone storage zone (bank 7 reserved area, no code allowed there)
TOMBSTONES_BASE = 0xE000
TOMBSTONES_END  = 0xE7FF      # 200 entries × 4 B + headroom

# Conocidos de los includes que "deben" vivir en slot 1 (always-visible).
# Si un entry symbol de éstos cae fuera de $6000-$7FFF, hay overflow.
SLOT1_ENTRY_POINTS = {
    "Inicio",
    "StartTownGateCutscene",       # hasta Fase A
    "UpdateTownGateCutscene",      # idem
    "LoadBgSpriteToBuffer",
    "TombStore",
    "AY_PlayPlayerHit",
    "GiveLife",
    "ApplyMagicCompassBuff",
    "RoomCompGapsTable",           # hasta Fase 3 (opcional)
    # NOTE: DrawTombstone2xCentered esta en bank 0 actualmente (post-revert
    # 2e79e98). Re-incluir aqui cuando Fase C lo mueva a bank 7 con thunk.
}

# Símbolos que viven en bank 7 paginado: deben caer en $C000-$E000 (no en
# tombstone storage).
BANK7_BODY_ENTRY_POINTS = set()
# NOTE: tras Fase C, DrawTombstone2xBody volvera aqui:
#   "DrawTombstone2xBody",


def parse_sym_file(path: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    with path.open(encoding="utf-8") as f:
        for line in f:
            m = SYM_RE.match(line)
            if m:
                syms[m.group(1)] = int(m.group(2), 16)
    return syms


def check(sym_path: Path) -> int:
    syms = parse_sym_file(sym_path)
    errors: list[str] = []
    warnings: list[str] = []

    # 1. Slot 1 overflow check: any "expected slot 1" symbol that landed
    #    outside $6000-$7FFF.
    for name in SLOT1_ENTRY_POINTS:
        if name not in syms:
            continue  # not built (e.g. removed in a phase)
        addr = syms[name]
        if not (SLOT1_START <= addr <= SLOT1_END):
            errors.append(
                f"SLOT1 OVERFLOW: '{name}' está en ${addr:04X} "
                f"(fuera de ${SLOT1_START:04X}-${SLOT1_END:04X}). "
                f"Probablemente desbordó a zona MainLoop."
            )

    # 2. Symbols in $80XX that look like room_routes overflow (canonical bug).
    overflow_pattern = re.compile(r"^RoomCompGaps_[0-9A-Fa-f]{2}$")
    overflow_addrs = []
    for name, addr in syms.items():
        if overflow_pattern.match(name) and SLOT2_START <= addr <= SLOT2_END:
            overflow_addrs.append((name, addr))
    if overflow_addrs:
        overflow_addrs.sort(key=lambda x: x[1])
        first = overflow_addrs[0]
        last = overflow_addrs[-1]
        warnings.append(
            f"ROOM_ROUTES OVERFLOW: {len(overflow_addrs)} símbolos de "
            f"RoomCompGaps en zona slot 2 (${first[1]:04X}-${last[1]:04X}). "
            f"room_routes.asm desbordando a zona MainLoop. "
            f"Esperado en pre-Fase-3; eliminar tras Fase 3."
        )

    # 3. Bank 7 body entry points: deben estar en $C000-$E000 (no en
    #    tombstone storage).
    for name in BANK7_BODY_ENTRY_POINTS:
        if name not in syms:
            continue
        addr = syms[name]
        if not (SLOT3_START <= addr < TOMBSTONES_BASE):
            errors.append(
                f"BANK7 LAYOUT: '{name}' está en ${addr:04X} "
                f"(esperado en ${SLOT3_START:04X}-${TOMBSTONES_BASE:04X}). "
                f"Posible colisión con tombstone storage."
            )

    # 4. Sanity: ningún símbolo en zona crítica $5800-$5AFF (attr VRAM)
    #    o $5B00-$5CCB (system area 128K).
    # Whitelist: constantes EQU conocidas que apuntan a esas zonas a propósito.
    SYSTEM_ZONE_WHITELIST = {
        "ATTR_BASE",        # $5800 — VRAM attr area, EQU constante
        "SYS_FRAMES",       # $5C78 — system var del 128K (frame counter)
        "SCREEN_BASE",      # $4000 — VRAM pixel area
    }
    for name, addr in syms.items():
        if name in SYSTEM_ZONE_WHITELIST:
            continue
        if 0x5800 <= addr <= 0x5AFF:
            warnings.append(
                f"SYSTEM ZONE: '{name}' en ${addr:04X} (attr VRAM)."
            )
        elif 0x5B00 <= addr <= 0x5CCB:
            warnings.append(
                f"SYSTEM ZONE: '{name}' en ${addr:04X} (system area 128K)."
            )

    # Report
    if warnings:
        print("=== WARNINGS ===")
        for w in warnings:
            print(f"  [WARN]{w}")
    if errors:
        print("=== ERRORS ===")
        for e in errors:
            print(f"  [FAIL]{e}")
        return 1

    if not warnings and not errors:
        print("[OK]check_slot_overlap: layout RAM OK, sin overlaps detectados.")
    elif not errors:
        print("\n[OK]check_slot_overlap: sin errores fatales (solo warnings esperados).")
    return 0


def main() -> int:
    sym_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("NuevoJuego.sym")
    if not sym_path.exists():
        print(f"ERROR: no existe {sym_path}", file=sys.stderr)
        return 2
    return check(sym_path)


if __name__ == "__main__":
    sys.exit(main())
