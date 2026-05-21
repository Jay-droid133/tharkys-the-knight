#!/usr/bin/env python3
"""
visualize_minimap.py — Render the in-game minimap to SVG for offline verification.

Two views side-by-side:
  A) Walls from closedPassages (editor truth — lo que el build emite hoy).
  B) Walls from BG-geometry gaps (build_screen_gaps logic, lo que pintaba
     la version original `d643176`). Esta es la "verdad por geometria":
     scanea los BG sprites de cada sala y detecta passages reales por
     donde cabe la huella 2x3 de un monstruo.

Discrepancias entre A y B se resaltan en rojo y se listan en stdout.
La diferencia te dice si hay paredes declaradas en el editor donde el
runtime sí permite pasar (o al revés, passages declarados con BG bloqueante).

Reads:
  - code/screen_data.asm    (MapTable)
  - code/screen_rooms.asm   (Room_Txx placements)
  - code/bg_gfx.asm + bg_gfx_b.asm + bg_gfx_c.asm   (BG sprite dims)
  - code/level_data.json    (closedPassages, playerStart)

Writes:
  - tools/minimap_preview.svg
  - stdout: text grid + diff list
"""

import json
import re
import sys
from pathlib import Path

# Reuse parsers/computation from build_screen_gaps.py
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_screen_gaps as bsg

MAP_W = 16
MAP_H = 16
CELL = 40
MARGIN = 16
WALL = 4


def parse_conn_table(path):
    if not path.is_file():
        return None
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = re.search(r'DEFB\s+([0-9A-Fa-fx$,\s]+?)(?:;|$)', line)
            if not m:
                continue
            tokens = [t.strip() for t in m.group(1).split(',') if t.strip()]
            nums = []
            for t in tokens:
                t = t.replace('$', '0x') if t.startswith('$') else t
                nums.append(int(t, 16) if t.lower().startswith('0x') else int(t))
            if len(nums) == MAP_W:
                rows.append(nums)
            if len(rows) == MAP_H:
                break
    return rows if len(rows) == MAP_H else None


def derive_from_passages(map_table, closed_passages):
    """Re-derive MinimapConnTable from closedPassages (current build logic)."""
    def is_closed(rx, ry, dir_letter):
        v = closed_passages.get(f"{rx},{ry},{dir_letter}")
        return v == 'closed' or v is True

    out = [[0] * MAP_W for _ in range(MAP_H)]
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            if map_table[ry][rx] == 0:
                continue
            if ry > 0 and map_table[ry - 1][rx] != 0 \
                    and not is_closed(rx, ry, 'T') \
                    and not is_closed(rx, ry - 1, 'B'):
                out[ry][rx] |= 0x08
            if ry + 1 < MAP_H and map_table[ry + 1][rx] != 0 \
                    and not is_closed(rx, ry, 'B') \
                    and not is_closed(rx, ry + 1, 'T'):
                out[ry][rx] |= 0x04
            if rx > 0 and map_table[ry][rx - 1] != 0 \
                    and not is_closed(rx, ry, 'L') \
                    and not is_closed(rx - 1, ry, 'R'):
                out[ry][rx] |= 0x02
            if rx + 1 < MAP_W and map_table[ry][rx + 1] != 0 \
                    and not is_closed(rx, ry, 'R') \
                    and not is_closed(rx + 1, ry, 'L'):
                out[ry][rx] |= 0x01
    return out


def derive_from_geometry(map_table, room_templates, bg_dims):
    """Compute walls from actual BG-walkable gaps (compute_screen_gaps logic).
    Para cada sala: walkgrid -> components -> filter_gaps. Si hay gap valido
    en el lado N, bit3=1; etc. Esto es la 'ground truth' por geometria."""
    out = [[0] * MAP_W for _ in range(MAP_H)]
    SIDE_BIT = {bsg.SIDE_N: 0x08, bsg.SIDE_S: 0x04,
                bsg.SIDE_W: 0x02, bsg.SIDE_E: 0x01}
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            if map_table[ry][rx] == 0:
                continue
            grid = bsg.screen_walkgrid(rx, ry, map_table, room_templates, bg_dims)
            if grid is None:
                continue
            comps = bsg.connected_components(grid)
            valid, _, _ = bsg.filter_gaps(grid, comps)
            # Forced overrides (rooms con auto-deteccion fallida)
            forced = bsg.FORCED_GAPS.get((rx, ry), [])
            for entry in forced:
                if isinstance(entry, tuple) and len(entry) == 2:
                    entry = (entry[0], entry[1], 0)
                if (entry[0], entry[1]) not in [(s, c) for s, c, _ in valid]:
                    valid.append(entry)
            # Bit set if any valid gap on that side AND neighbor exists
            has_side = {bsg.SIDE_N: False, bsg.SIDE_S: False,
                        bsg.SIDE_W: False, bsg.SIDE_E: False}
            for entry in valid:
                has_side[entry[0]] = True
            if has_side[bsg.SIDE_N] and ry > 0 and map_table[ry - 1][rx] != 0:
                out[ry][rx] |= 0x08
            if has_side[bsg.SIDE_S] and ry + 1 < MAP_H and map_table[ry + 1][rx] != 0:
                out[ry][rx] |= 0x04
            if has_side[bsg.SIDE_W] and rx > 0 and map_table[ry][rx - 1] != 0:
                out[ry][rx] |= 0x02
            if has_side[bsg.SIDE_E] and rx + 1 < MAP_W and map_table[ry][rx + 1] != 0:
                out[ry][rx] |= 0x01
    # Symmetrize: if A says E-open but B says W-closed, force both to closed.
    # Esto evita gaps unidireccionales (que la version original NO emitia tras
    # 8bb75d7). Conserva el resultado simetrico de build_screen_gaps.
    changed = True
    while changed:
        changed = False
        for ry in range(MAP_H):
            for rx in range(MAP_W):
                if map_table[ry][rx] == 0:
                    continue
                # E ↔ neighbor W
                if rx + 1 < MAP_W and map_table[ry][rx + 1] != 0:
                    a = (out[ry][rx] & 0x01) != 0
                    b = (out[ry][rx + 1] & 0x02) != 0
                    if a != b:
                        out[ry][rx] &= ~0x01
                        out[ry][rx + 1] &= ~0x02
                        changed = True
                # S ↔ neighbor N
                if ry + 1 < MAP_H and map_table[ry + 1][rx] != 0:
                    a = (out[ry][rx] & 0x04) != 0
                    b = (out[ry + 1][rx] & 0x08) != 0
                    if a != b:
                        out[ry][rx] &= ~0x04
                        out[ry + 1][rx] &= ~0x08
                        changed = True
    return out


def render_svg(map_table, conn_a, conn_b, player, mismatches, out_path,
               title_a, title_b):
    HDR = 18              # extra space for X/Y headers (top + left)
    w_one = MAP_W * CELL + 2 * MARGIN + HDR
    h_one = MAP_H * CELL + 2 * MARGIN + 40 + HDR
    gap = 24
    total_w = 2 * w_one + gap + 2 * MARGIN
    total_h = h_one + 2 * MARGIN

    def panel(x_off, conn, title, label_letter):
        out = [f'<g transform="translate({x_off},{MARGIN})">']
        out.append(f'<text x="{w_one//2}" y="22" text-anchor="middle" '
                   f'font-family="monospace" font-size="16" font-weight="bold" '
                   f'fill="#e0e0e0">'
                   f'{label_letter}. {title}</text>')
        # X headers (top): "X=0 .. X=15"
        for rx in range(MAP_W):
            x_center = MARGIN + HDR + rx * CELL + CELL // 2
            out.append(f'<text x="{x_center}" y="{MARGIN + 30 + HDR - 5}" '
                       f'text-anchor="middle" font-family="monospace" '
                       f'font-size="11" fill="#8888aa">{rx}</text>')
        # Y headers (left): "Y=0 .. Y=15"
        for ry in range(MAP_H):
            y_center = MARGIN + 30 + HDR + ry * CELL + CELL // 2 + 4
            out.append(f'<text x="{MARGIN + HDR - 4}" y="{y_center}" '
                       f'text-anchor="end" font-family="monospace" '
                       f'font-size="11" fill="#8888aa">{ry}</text>')
        for ry in range(MAP_H):
            for rx in range(MAP_W):
                x = MARGIN + HDR + rx * CELL
                y = MARGIN + 30 + HDR + ry * CELL
                exists = map_table[ry][rx] != 0
                fill = '#0033aa' if exists else '#1a1a1a'
                stroke = '#222'
                if (rx, ry) in mismatches:
                    fill = '#aa0033'
                out.append(f'<rect x="{x}" y="{y}" width="{CELL}" height="{CELL}" '
                           f'fill="{fill}" stroke="{stroke}" stroke-width="0.5"/>')
                if not exists:
                    continue
                flags = conn[ry][rx]
                wall_color = '#ffe066'
                if not (flags & 0x08):
                    out.append(f'<line x1="{x}" y1="{y}" x2="{x+CELL}" y2="{y}" '
                               f'stroke="{wall_color}" stroke-width="{WALL}"/>')
                if not (flags & 0x04):
                    out.append(f'<line x1="{x}" y1="{y+CELL}" x2="{x+CELL}" y2="{y+CELL}" '
                               f'stroke="{wall_color}" stroke-width="{WALL}"/>')
                if not (flags & 0x02):
                    out.append(f'<line x1="{x}" y1="{y}" x2="{x}" y2="{y+CELL}" '
                               f'stroke="{wall_color}" stroke-width="{WALL}"/>')
                if not (flags & 0x01):
                    out.append(f'<line x1="{x+CELL}" y1="{y}" x2="{x+CELL}" y2="{y+CELL}" '
                               f'stroke="{wall_color}" stroke-width="{WALL}"/>')
                # (X,Y) in top-left corner (small, dim)
                out.append(f'<text x="{x+3}" y="{y+10}" '
                           f'font-family="monospace" font-size="8" fill="#99bbff">'
                           f'{rx},{ry}</text>')
                # Hex byte centered
                out.append(f'<text x="{x+CELL//2}" y="{y+CELL//2+6}" text-anchor="middle" '
                           f'font-family="monospace" font-size="11" fill="#ffe066">'
                           f'{flags:X}</text>')
                if player and (rx, ry) == player:
                    cx, cy = x + CELL // 2, y + CELL // 2
                    out.append(f'<circle cx="{cx}" cy="{cy}" r="6" fill="#ffff00" '
                               f'stroke="#000" stroke-width="1" opacity="0.7"/>')
        out.append('</g>')
        return '\n'.join(out)

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" height="{total_h}" '
        f'viewBox="0 0 {total_w} {total_h}">',
        f'<rect width="{total_w}" height="{total_h}" fill="#0a0a0a"/>',
        panel(MARGIN, conn_a, title_a, 'A'),
        panel(MARGIN + w_one + gap, conn_b, title_b, 'B'),
        '</svg>',
    ]
    out_path.write_text('\n'.join(svg), encoding='utf-8')


def print_grid(conn, label):
    print(f"\n=== {label} ===")
    print("    " + " ".join(f"{rx:X}" for rx in range(MAP_W)))
    for ry in range(MAP_H):
        row = " ".join(f"{conn[ry][rx]:X}" for rx in range(MAP_W))
        print(f" {ry:2X} {row}")


SIDE_LETTER = {0x08: 'N', 0x04: 'S', 0x02: 'W', 0x01: 'E'}


def explain_diff(rx, ry, a, b):
    """Return string explaining what bits differ and in which direction."""
    diff = a ^ b
    parts = []
    for bit in (0x08, 0x04, 0x02, 0x01):
        if diff & bit:
            side = SIDE_LETTER[bit]
            in_a = "open" if a & bit else "wall"
            in_b = "open" if b & bit else "wall"
            parts.append(f"{side}: A={in_a} B={in_b}")
    return ", ".join(parts)


def main():
    root = Path(__file__).resolve().parent.parent
    code = root / 'code'

    print("Parsing ASM + JSON...")
    map_table = bsg.parse_map_table(code / 'screen_data.asm')
    room_templates = bsg.parse_rooms(code / 'screen_rooms.asm')
    bg_dims = bsg.parse_bg_dims([code / 'bg_gfx.asm',
                                  code / 'bg_gfx_b.asm',
                                  code / 'bg_gfx_c.asm'])
    with (code / 'level_data.json').open(encoding='utf-8') as f:
        ld = json.load(f)
    closed_passages = ld.get('closedPassages', {})
    ps = ld.get('playerStart') or {}
    player = (ps.get('screenX'), ps.get('screenY')) if 'screenX' in ps else None

    print("Deriving from closedPassages (current build logic)...")
    conn_a = derive_from_passages(map_table, closed_passages)

    print("Deriving from BG geometry (compute_screen_gaps)...")
    conn_b = derive_from_geometry(map_table, room_templates, bg_dims)

    # Mismatches A vs B
    mismatches = set()
    diffs = []
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            if conn_a[ry][rx] != conn_b[ry][rx]:
                mismatches.add((rx, ry))
                diffs.append((rx, ry, conn_a[ry][rx], conn_b[ry][rx]))

    print(f"\nRooms in MapTable: {sum(1 for row in map_table for c in row if c)}/{MAP_W*MAP_H}")
    print(f"closedPassages entries: {len(closed_passages)}")
    print(f"Player start: {player}")
    print(f"Mismatches A (closedPassages) vs B (geometry): {len(mismatches)}")
    if diffs:
        print("\nCelda  A   B   Diferencia")
        print("-----  --  --  ---------------------")
        for rx, ry, a, b in diffs:
            print(f"({rx:2d},{ry:2d})  {a:X}   {b:X}   {explain_diff(rx, ry, a, b)}")

    # Also report against emitted bytes (sanity)
    conn_emitted = parse_conn_table(code / 'minimap_conn.asm')
    if conn_emitted is not None:
        n = sum(1 for ry in range(MAP_H) for rx in range(MAP_W)
                if conn_a[ry][rx] != conn_emitted[ry][rx])
        print(f"\nSanity: closedPassages-derived vs minimap_conn.asm bytes: {n} mismatches")

    out_svg = root / 'tools' / 'minimap_preview.svg'
    render_svg(map_table, conn_a, conn_b, player, mismatches, out_svg,
               title_a="closedPassages (editor)",
               title_b="BG geometry (ground truth)")
    print(f"\nWrote {out_svg}")
    print("Celdas rojas = la celda tiene al menos 1 lado donde A y B difieren.")
    print("Compara los dos paneles; los lados con linea/sin-linea distintos son la causa.")


if __name__ == '__main__':
    main()
