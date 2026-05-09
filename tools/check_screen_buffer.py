"""
check_screen_buffer.py - Verifica que ningún Room_TXX exceda la capacidad
de CurrentScreenBuffer al copiarse en runtime via LoadRoomToBuffer.

CONTEXTO
--------
LoadRoomToBuffer (paging.asm) copia Room_Txx desde bank 1 al buffer
CurrentScreenBuffer en bank 2, formato fijo 4 B per entry + 1 B terminador
($FF). Si un Room_Txx tiene mas placements de los que caben en el buffer,
LoadRoomToBuffer escribe SILENCIOSAMENTE fuera del buffer y corrompe la
siguiente variable (CleanAttrMap o similar segun layout). Mismo tipo de
bug latente que tenia cabin_house antes del split.

Este script reporta:
  - Cap actual del buffer (calculado del DEFS en variables.asm).
  - Placement count de cada Room_Txx.
  - WARN si algun room esta cerca del cap (default >=75%).
  - FAIL (exit 1) si algun room excede el cap.

USO
---
    python tools/check_screen_buffer.py
    python tools/check_screen_buffer.py --strict   # fail tambien con WARN
    python tools/check_screen_buffer.py --warn-pct 50

Pensado para invocarse tras Export ASM o como ultimo paso del build script.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT     = Path(__file__).resolve().parent.parent
DEFAULT_VARS  = REPO_ROOT / "code" / "variables.asm"
DEFAULT_ROOMS = REPO_ROOT / "code" / "screen_rooms.asm"


def parse_buffer_size(vars_path: Path) -> int:
    """Localiza `CurrentScreenBuffer: DEFS N` en variables.asm y devuelve N.
    Lanza RuntimeError si no encuentra la declaracion."""
    text = vars_path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'CurrentScreenBuffer\s*:\s*DEFS\s+(\d+)', text)
    if not m:
        raise RuntimeError(
            f"No encontre 'CurrentScreenBuffer: DEFS N' en {vars_path}")
    return int(m.group(1))


def count_placements_per_room(rooms_path: Path) -> dict[str, int]:
    """Para cada Room_Txx (o Screen_Xxx) en el fichero, cuenta cuantos
    placements (lineas `DEFB id, x, y[, v]`) tiene. Devuelve dict ordenado.
    """
    text = rooms_path.read_text(encoding="utf-8", errors="replace")
    out: dict[str, int] = {}
    pattern = re.compile(
        r'^(Room_\w+|Screen_\w+)\s*:(.*?)(?=^(?:Room_|Screen_)\w+\s*:|\Z)',
        re.DOTALL | re.MULTILINE,
    )
    placement_re = re.compile(
        r'^\s*DEFB\s+\d+\s*,\s*\d+\s*,\s*\d+', re.MULTILINE,
    )
    for m in pattern.finditer(text):
        name = m.group(1)
        body = m.group(2)
        n = len(placement_re.findall(body))
        out[name] = n
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Verifica que ningun Room_Txx exceda CurrentScreenBuffer.",
    )
    p.add_argument("--vars",  type=Path, default=DEFAULT_VARS,
                   help="Path a variables.asm (default: code/variables.asm)")
    p.add_argument("--rooms", type=Path, default=DEFAULT_ROOMS,
                   help="Path a screen_rooms.asm")
    p.add_argument("--warn-pct", type=float, default=75.0,
                   help="Threshold de WARN como %% del cap (default 75)")
    p.add_argument("--strict",  action="store_true",
                   help="Fail (exit 1) tambien si hay WARNINGs, no solo overflow")
    p.add_argument("--top",     type=int, default=10,
                   help="Cuantos rooms mostrar en la tabla (default 10)")
    args = p.parse_args(argv)

    if not args.vars.exists():
        print(f"ERROR: no existe {args.vars}", file=sys.stderr)
        return 2
    if not args.rooms.exists():
        print(f"ERROR: no existe {args.rooms}", file=sys.stderr)
        return 2

    try:
        buffer_size = parse_buffer_size(args.vars)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    # Cap = (buffer - 1 terminator) // 4 bytes per entry. Conservador.
    cap_entries     = (buffer_size - 1) // 4
    warn_threshold  = int(cap_entries * args.warn_pct / 100)

    rooms = count_placements_per_room(args.rooms)
    if not rooms:
        print(f"ERROR: no encontre rooms en {args.rooms}", file=sys.stderr)
        return 2

    sorted_rooms = sorted(rooms.items(), key=lambda kv: -kv[1])
    rooms_with_data = [(n, c) for n, c in sorted_rooms if c > 0]
    total_rooms = len(rooms_with_data)

    overflows: list[tuple[str, int, int]] = []
    warnings:  list[tuple[str, int, int]] = []

    print(f"=== CurrentScreenBuffer cap check ===")
    print(f"  Buffer DEFS:    {buffer_size} B (de variables.asm)")
    print(f"  Cap entries:    {cap_entries} placements (4 B/entry + 1 B terminator)")
    print(f"  WARN threshold: >={warn_threshold} entries ({args.warn_pct:.0f}% del cap)")
    print(f"  Total rooms:    {total_rooms} (con al menos 1 placement)")
    print()
    print(f"Top {args.top} rooms por densidad de placements:")
    print(f"  {'ROOM':<22} {'ENTRIES':>8} {'BUFFER':>9} {'PCT':>6}  STATUS")
    print(f"  {'-'*22} {'-'*8} {'-'*9} {'-'*6}  {'-'*6}")

    for name, n in rooms_with_data[:args.top]:
        b   = n * 4 + 1
        pct = 100.0 * n / cap_entries
        if n > cap_entries:
            status = "[FAIL]"
            overflows.append((name, n, b))
        elif n >= warn_threshold:
            status = "[WARN]"
            warnings.append((name, n, b))
        else:
            status = "[OK]  "
        print(f"  {name:<22} {n:>8} {b:>9} {pct:>5.1f}%  {status}")

    # Detect overflows/warnings que no esten en el top mostrado.
    extra_overflows = [
        (n, c) for (n, c) in rooms_with_data[args.top:] if c > cap_entries
    ]
    extra_warnings = [
        (n, c) for (n, c) in rooms_with_data[args.top:]
        if c >= warn_threshold and c <= cap_entries
    ]
    for name, n in extra_overflows:
        overflows.append((name, n, n*4+1))
    for name, n in extra_warnings:
        warnings.append((name, n, n*4+1))

    print()
    if overflows:
        print(f"OVERFLOW: {len(overflows)} room(s) exceden el cap de {cap_entries}.")
        for name, n, b in overflows:
            print(f"  - {name}: {n} entries (= {b} B) > cap {cap_entries}")
        print()
        print("  Significado: LoadRoomToBuffer escribira fuera de CurrentScreenBuffer")
        print("  al cargar esos rooms, corrompiendo la variable adyacente en bank 2.")
        print("  Solucion: ampliar buffer en variables.asm O reducir placements del room")
        print("  (a menudo splitear sprites composite reduce autofills indirectamente).")
        return 1

    if warnings:
        print(f"WARN: {len(warnings)} room(s) cerca del cap (>= {warn_threshold} entries).")
        for name, n, b in warnings:
            pct = 100.0 * n / cap_entries
            print(f"  - {name}: {n}/{cap_entries} entries ({pct:.1f}% used)")
        if args.strict:
            print()
            print("  --strict mode: fail.")
            return 1

    if not overflows and not warnings:
        print(f"OK: todos los rooms tienen margen comodo (peak ="
              f" {rooms_with_data[0][1]} entries de {cap_entries} cap,"
              f" {100.0*rooms_with_data[0][1]/cap_entries:.0f}% used).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
