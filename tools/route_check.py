#!/usr/bin/env python3
"""
route_check.py — Compara la ruta del level editor con la conn table del minimap.

Reproduce exactamente el algoritmo del editor (level_editor.html):
  1) buildWorldWalkGrid: 512x352 chars, walkable = no BG sprite encima.
     Despues fusiona columnas/filas compartidas entre salas vecinas
     (si alguno de los dos lados es walkable, ambos se marcan walkable).
  2) buildPlayerWalkGrid: erosion por huella 4x3 chars.
  3) BFS desde (origin_x*32+16-2, origin_y*22+11-1) hasta target.
  4) Suaviza el path y lo dibuja.

Cuando el BFS encuentra ruta, mira por que celdas-frontera entre salas pasa.
Si la conn table del minimap dice "pared" en uno de esos lados, hay bug:
el editor pinta ruta por donde el minimap dice que no se puede pasar.

Uso:
  python tools/route_check.py 8 9 7 15
  (origen 8,9  →  target 7,15  → coincide con savedRoutes 'Route 1')
"""

import json
import re
import sys
from pathlib import Path
from collections import deque

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_screen_gaps as bsg

GRID_W = 32
GRID_H = 22
MAP_W = 16
MAP_H = 16
GW = MAP_W * GRID_W   # 512
GH = MAP_H * GRID_H   # 352
FOOT_W = 4
FOOT_H = 3


def build_world_walkgrid(map_table, room_templates, bg_dims):
    """Mirror level_editor.html buildWorldWalkGrid (lines 3065-3101)."""
    walk = bytearray(GW * GH)
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            grid = bsg.screen_walkgrid(rx, ry, map_table, room_templates, bg_dims)
            if grid is None:
                continue
            bx = rx * GRID_W
            by = ry * GRID_H
            for ty in range(GRID_H):
                for tx in range(GRID_W):
                    if grid[ty][tx]:
                        walk[(by + ty) * GW + (bx + tx)] = 1
    # E/W neighbor merge: last col of A and first col of B fused
    for ry in range(MAP_H):
        for rx in range(MAP_W - 1):
            if map_table[ry][rx] == 0 or map_table[ry][rx + 1] == 0:
                continue
            x1 = (rx + 1) * GRID_W - 1
            x2 = (rx + 1) * GRID_W
            for ty in range(GRID_H):
                g = ry * GRID_H + ty
                if walk[g * GW + x1] or walk[g * GW + x2]:
                    walk[g * GW + x1] = 1
                    walk[g * GW + x2] = 1
    # N/S neighbor merge
    for ry in range(MAP_H - 1):
        for rx in range(MAP_W):
            if map_table[ry][rx] == 0 or map_table[ry + 1][rx] == 0:
                continue
            y1 = (ry + 1) * GRID_H - 1
            y2 = (ry + 1) * GRID_H
            for tx in range(GRID_W):
                col = rx * GRID_W + tx
                if walk[y1 * GW + col] or walk[y2 * GW + col]:
                    walk[y1 * GW + col] = 1
                    walk[y2 * GW + col] = 1
    return walk


def build_player_walkgrid(world):
    """Erode by FOOT_W x FOOT_H. Cell (x,y) walkable iff rectangle is fully free."""
    eroded = bytearray(GW * GH)
    max_x = GW - FOOT_W
    max_y = GH - FOOT_H
    for y in range(max_y + 1):
        for x in range(max_x + 1):
            ok = True
            for dy in range(FOOT_H):
                row = (y + dy) * GW
                for dx in range(FOOT_W):
                    if not world[row + x + dx]:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                eroded[y * GW + x] = 1
    return eroded


def near_walk(walk, cx, cy):
    if 0 <= cx < GW and 0 <= cy < GH and walk[cy * GW + cx]:
        return (cx, cy)
    for r in range(1, 16):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < GW and 0 <= ny < GH and walk[ny * GW + nx]:
                    return (nx, ny)
    return (cx, cy)


def bfs_full(walk, start):
    """BFS from start. Return (visited, prev) flood-fill arrays for the whole grid."""
    visited = bytearray(GW * GH)
    prev = [-1] * (GW * GH)
    s = start[1] * GW + start[0]
    if not walk[s]:
        return visited, prev
    q = deque([s])
    visited[s] = 1
    while q:
        pos = q.popleft()
        gx = pos % GW
        gy = pos // GW
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = gx + dx, gy + dy
            if nx < 0 or nx >= GW or ny < 0 or ny >= GH:
                continue
            ni = ny * GW + nx
            if not walk[ni] or visited[ni]:
                continue
            visited[ni] = 1
            prev[ni] = pos
            q.append(ni)
    return visited, prev


def reachable_rooms(visited):
    s = set()
    for gy in range(GH):
        for gx in range(GW):
            if visited[gy * GW + gx]:
                s.add((gx // GRID_W, gy // GRID_H))
    return s


def reconstruct_path(prev, end_idx):
    raw = []
    ci = end_idx
    while ci != -1:
        raw.append((ci % GW, ci // GW))
        ci = prev[ci]
    raw.reverse()
    return raw


def bfs_path(walk, start, end):
    visited, prev = bfs_full(walk, start)
    e = end[1] * GW + end[0]
    if not visited[e]:
        return None
    return reconstruct_path(prev, e)


def find_rupture(walk, origin_room, target_room):
    """Replica findRouteRupture (level_editor.html line 6425).
    Returns (rupture_a, rupture_b, partial_target_idx, reached_set, target_set)."""
    s0 = origin_room[0] * GRID_W + (GRID_W >> 1) - (FOOT_W >> 1)
    s1 = origin_room[1] * GRID_H + (GRID_H >> 1) - (FOOT_H >> 1)
    start = near_walk(walk, s0, s1)
    visited_o, prev_o = bfs_full(walk, start)
    reached_o = reachable_rooms(visited_o)

    if target_room in reached_o:
        return None, None, -1, reached_o, set()

    e0 = target_room[0] * GRID_W + (GRID_W >> 1) - (FOOT_W >> 1)
    e1 = target_room[1] * GRID_H + (GRID_H >> 1) - (FOOT_H >> 1)
    end = near_walk(walk, e0, e1)
    visited_t, _ = bfs_full(walk, end)
    reached_t = reachable_rooms(visited_t)

    tx, ty = target_room
    best_pair = None
    best_dist = None
    for (xo, yo) in reached_o:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = xo + dx, yo + dy
            if nx < 0 or nx >= MAP_W or ny < 0 or ny >= MAP_H:
                continue
            if (nx, ny) not in reached_t:
                continue
            d = abs(nx - tx) + abs(ny - ty)
            if best_dist is None or d < best_dist:
                best_dist = d
                best_pair = ((xo, yo), (nx, ny))

    partial_target_idx = -1
    if best_pair:
        (ax, ay), (bx, by) = best_pair
        # Closest reached cell in rupture room A to target pixel
        target_px = bx * GRID_W + (GRID_W >> 1)
        target_py = by * GRID_H + (GRID_H >> 1)
        best_ni = -1
        best_d = None
        for gy in range(ay * GRID_H, (ay + 1) * GRID_H):
            for gx in range(ax * GRID_W, (ax + 1) * GRID_W):
                ni = gy * GW + gx
                if not visited_o[ni]:
                    continue
                d = abs(gx - target_px) + abs(gy - target_py)
                if best_d is None or d < best_d:
                    best_d = d
                    best_ni = ni
        partial_target_idx = best_ni
        rupture_a = (ax, ay)
        rupture_b = (bx, by)
    else:
        # fallback: cell in reached_o closest to target room
        best_cell = None
        best_d = None
        for (xo, yo) in reached_o:
            d = abs(xo - tx) + abs(yo - ty)
            if best_d is None or d < best_d:
                best_d = d
                best_cell = (xo, yo)
        rupture_a = best_cell
        rupture_b = None

    partial_path = []
    if partial_target_idx >= 0:
        partial_path = reconstruct_path(prev_o, partial_target_idx)

    return rupture_a, rupture_b, partial_path, reached_o, reached_t


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


def find_boundary_crossings(path, conn):
    """For consecutive path points that span two different rooms,
    record (from_room, to_room, side, allowed)."""
    crossings = []
    prev_room = None
    for (x, y) in path:
        rx = x // GRID_W
        ry = y // GRID_H
        if rx < 0:
            rx = 0
        if rx >= MAP_W:
            rx = MAP_W - 1
        if ry < 0:
            ry = 0
        if ry >= MAP_H:
            ry = MAP_H - 1
        room = (rx, ry)
        if prev_room is not None and room != prev_room:
            px, py = prev_room
            dx = rx - px
            dy = ry - py
            if dx == 1 and dy == 0:
                side_from = 'E'; bit_from = 0x01
                side_to = 'W'; bit_to = 0x02
            elif dx == -1 and dy == 0:
                side_from = 'W'; bit_from = 0x02
                side_to = 'E'; bit_to = 0x01
            elif dy == 1 and dx == 0:
                side_from = 'S'; bit_from = 0x04
                side_to = 'N'; bit_to = 0x08
            elif dy == -1 and dx == 0:
                side_from = 'N'; bit_from = 0x08
                side_to = 'S'; bit_to = 0x04
            else:
                continue  # diagonal jump? ignore
            allowed_from = bool(conn[py][px] & bit_from)
            allowed_to = bool(conn[ry][rx] & bit_to)
            crossings.append({
                'from': prev_room, 'to': room,
                'side_from': side_from, 'side_to': side_to,
                'conn_from': conn[py][px],
                'conn_to': conn[ry][rx],
                'allowed_from': allowed_from,
                'allowed_to': allowed_to,
                'at_char': (x, y),
            })
        prev_room = room
    return crossings


def render_svg(map_table, conn, path, crossings, origin, target, out_path):
    """16x16 room grid. Each room shows minimap walls + the path within it.
    Highlights rooms where the path crosses a 'wall' edge."""
    CELL = 48
    MARGIN = 24
    HDR = 18
    width = MARGIN * 2 + HDR + MAP_W * CELL + 200
    height = MARGIN * 2 + HDR + 30 + MAP_H * CELL

    bad_rooms = set()
    for c in crossings:
        if not (c['allowed_from'] and c['allowed_to']):
            bad_rooms.add(c['from'])
            bad_rooms.add(c['to'])

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
           f'viewBox="0 0 {width} {height}">']
    out.append(f'<rect width="{width}" height="{height}" fill="#0a0a0a"/>')
    out.append(f'<text x="{MARGIN}" y="20" font-family="monospace" font-size="14" '
               f'fill="#e0e0e0" font-weight="bold">'
               f'Editor route ({origin[0]},{origin[1]}) → ({target[0]},{target[1]})  '
               f'vs minimap conn table</text>')

    # Headers
    for rx in range(MAP_W):
        x_center = MARGIN + HDR + rx * CELL + CELL // 2
        out.append(f'<text x="{x_center}" y="{MARGIN + 30 + HDR - 5}" '
                   f'text-anchor="middle" font-family="monospace" font-size="11" '
                   f'fill="#8888aa">{rx}</text>')
    for ry in range(MAP_H):
        y_center = MARGIN + 30 + HDR + ry * CELL + CELL // 2 + 4
        out.append(f'<text x="{MARGIN + HDR - 4}" y="{y_center}" text-anchor="end" '
                   f'font-family="monospace" font-size="11" fill="#8888aa">{ry}</text>')

    # Draw rooms with minimap walls
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            x = MARGIN + HDR + rx * CELL
            y = MARGIN + 30 + HDR + ry * CELL
            exists = map_table[ry][rx] != 0
            fill = '#0033aa' if exists else '#1a1a1a'
            if (rx, ry) in bad_rooms:
                fill = '#aa0033'
            out.append(f'<rect x="{x}" y="{y}" width="{CELL}" height="{CELL}" '
                       f'fill="{fill}" stroke="#222" stroke-width="0.5"/>')
            if not exists:
                continue
            flags = conn[ry][rx]
            wcol = '#ffe066'
            wW = 4
            if not (flags & 0x08):
                out.append(f'<line x1="{x}" y1="{y}" x2="{x+CELL}" y2="{y}" '
                           f'stroke="{wcol}" stroke-width="{wW}"/>')
            if not (flags & 0x04):
                out.append(f'<line x1="{x}" y1="{y+CELL}" x2="{x+CELL}" y2="{y+CELL}" '
                           f'stroke="{wcol}" stroke-width="{wW}"/>')
            if not (flags & 0x02):
                out.append(f'<line x1="{x}" y1="{y}" x2="{x}" y2="{y+CELL}" '
                           f'stroke="{wcol}" stroke-width="{wW}"/>')
            if not (flags & 0x01):
                out.append(f'<line x1="{x+CELL}" y1="{y}" x2="{x+CELL}" y2="{y+CELL}" '
                           f'stroke="{wcol}" stroke-width="{wW}"/>')
            out.append(f'<text x="{x+3}" y="{y+10}" font-family="monospace" '
                       f'font-size="8" fill="#99bbff">{rx},{ry}</text>')

    # Path: project (gx, gy) char coords to room-grid pixel space.
    if path:
        pts = []
        for (gx, gy) in path:
            rx = gx / GRID_W
            ry = gy / GRID_H
            px = MARGIN + HDR + rx * CELL
            py = MARGIN + 30 + HDR + ry * CELL
            pts.append(f"{px:.1f},{py:.1f}")
        poly = " ".join(pts)
        out.append(f'<polyline points="{poly}" fill="none" stroke="#22d3ee" '
                   f'stroke-width="2" stroke-linecap="round" opacity="0.85"/>')

    # Origin/target markers
    def marker(rx, ry, color, label):
        cx = MARGIN + HDR + (rx + 0.5) * CELL
        cy = MARGIN + 30 + HDR + (ry + 0.5) * CELL
        out.append(f'<circle cx="{cx}" cy="{cy}" r="9" fill="{color}" '
                   f'stroke="#000" stroke-width="1.5"/>')
        out.append(f'<text x="{cx}" y="{cy+4}" text-anchor="middle" '
                   f'font-family="monospace" font-size="11" font-weight="bold" '
                   f'fill="#000">{label}</text>')
    marker(origin[0], origin[1], '#22ff66', 'O')
    marker(target[0], target[1], '#ff2266', 'T')

    # Crossings highlighted as red dots
    for c in crossings:
        gx, gy = c['at_char']
        rx = gx / GRID_W
        ry = gy / GRID_H
        px = MARGIN + HDR + rx * CELL
        py = MARGIN + 30 + HDR + ry * CELL
        bad = not (c['allowed_from'] and c['allowed_to'])
        if bad:
            out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="6" '
                       f'fill="none" stroke="#ff3333" stroke-width="2"/>')

    out.append('</svg>')
    out_path.write_text('\n'.join(out), encoding='utf-8')


def main():
    if len(sys.argv) < 5:
        print("Usage: route_check.py ORIGIN_X ORIGIN_Y TARGET_X TARGET_Y")
        sys.exit(1)
    ox, oy, tx, ty = (int(sys.argv[i]) for i in range(1, 5))

    root = Path(__file__).resolve().parent.parent
    code = root / 'code'

    print("Parsing ASM + JSON...")
    map_table = bsg.parse_map_table(code / 'screen_data.asm')
    room_templates = bsg.parse_rooms(code / 'screen_rooms.asm')
    bg_dims = bsg.parse_bg_dims([code / 'bg_gfx.asm',
                                  code / 'bg_gfx_b.asm',
                                  code / 'bg_gfx_c.asm'])
    conn = parse_conn_table(code / 'minimap_conn.asm')
    if conn is None:
        print("ERROR: cannot parse code/minimap_conn.asm")
        sys.exit(1)

    print("Building world walkGrid (per-room + neighbor merge)...")
    world = build_world_walkgrid(map_table, room_templates, bg_dims)
    print(f"  walkable base chars: {sum(world)}/{GW*GH}")
    print("Eroding by 4x3 player footprint...")
    player = build_player_walkgrid(world)
    print(f"  walkable player-anchor chars: {sum(player)}/{GW*GH}")

    # Origin/target: room center anchor (matches editor formula)
    s0 = ox * GRID_W + (GRID_W >> 1) - (FOOT_W >> 1)
    s1 = oy * GRID_H + (GRID_H >> 1) - (FOOT_H >> 1)
    e0 = tx * GRID_W + (GRID_W >> 1) - (FOOT_W >> 1)
    e1 = ty * GRID_H + (GRID_H >> 1) - (FOOT_H >> 1)
    start = near_walk(player, s0, s1)
    end = near_walk(player, e0, e1)
    print(f"Origin anchor: nominal ({s0},{s1}) → walkable ({start[0]},{start[1]})")
    print(f"Target anchor: nominal ({e0},{e1}) → walkable ({end[0]},{end[1]})")

    print("Running BFS (player 4x3 footprint)...")
    path = bfs_path(player, start, end)
    rupture_info = None
    if path is not None:
        print(f"BFS: path found, {len(path)} chars long")
    else:
        print("BFS: NO PATH. Editor draws RED partial line via findRouteRupture.")
        rupture_info = find_rupture(player, (ox, oy), (tx, ty))
        rupture_a, rupture_b, partial_path, reached_o, reached_t = rupture_info
        print(f"  Rooms reachable from origin: {len(reached_o)}/256")
        print(f"  Rooms reachable from target: {len(reached_t)}/256")
        print(f"  Closest rupture pair: A={rupture_a}  B={rupture_b}")
        path = partial_path
        if path:
            print(f"  Partial path length: {len(path)} chars")

    crossings = find_boundary_crossings(path or [], conn) if path else []
    bad = [c for c in crossings if not (c['allowed_from'] and c['allowed_to'])]
    print(f"\nBoundary crossings on path: {len(crossings)}")
    for c in crossings:
        gx, gy = c['at_char']
        rx_from, ry_from = c['from']
        rx_to, ry_to = c['to']
        cf = c['conn_from']
        ct = c['conn_to']
        flag = 'OK' if (c['allowed_from'] and c['allowed_to']) else '*** BUG ***'
        print(f"  ({rx_from:2d},{ry_from:2d}) {c['side_from']} -> "
              f"({rx_to:2d},{ry_to:2d}) {c['side_to']}   at char ({gx},{gy})  "
              f"conn_from={cf:X} conn_to={ct:X}  {flag}")

    if rupture_info is not None:
        rupture_a, rupture_b, _, reached_o, reached_t = rupture_info
        if rupture_b is not None:
            ax, ay = rupture_a
            bx, by = rupture_b
            dx = bx - ax
            dy = by - ay
            if dx == 1:
                side_a_letter, side_a_bit = 'E', 0x01
                side_b_letter, side_b_bit = 'W', 0x02
            elif dx == -1:
                side_a_letter, side_a_bit = 'W', 0x02
                side_b_letter, side_b_bit = 'E', 0x01
            elif dy == 1:
                side_a_letter, side_a_bit = 'S', 0x04
                side_b_letter, side_b_bit = 'N', 0x08
            else:
                side_a_letter, side_a_bit = 'N', 0x08
                side_b_letter, side_b_bit = 'S', 0x04
            mm_a = bool(conn[ay][ax] & side_a_bit)
            mm_b = bool(conn[by][bx] & side_b_bit)
            print("\n--- Rupture analysis ---")
            print(f"  Player BFS no puede cruzar de {rupture_a} a {rupture_b}.")
            print(f"  Lado A ({ax},{ay}) {side_a_letter}: conn=${conn[ay][ax]:X} -> minimap dice {'OPEN' if mm_a else 'WALL'}")
            print(f"  Lado B ({bx},{by}) {side_b_letter}: conn=${conn[by][bx]:X} -> minimap dice {'OPEN' if mm_b else 'WALL'}")
            if mm_a and mm_b:
                print("  *** BUG: minimap dice OPEN pero player BFS dice WALL ***")
                print("  Probable causa: gap solo aguanta huella 2x3 (monster),")
                print("  no 4x3 (player + sword reach).")
            else:
                print("  Minimap tambien dice WALL en este lado: consistente.")

    if bad:
        print(f"\n!!! {len(bad)} crossings donde el path pasa por una pared "
              f"que el minimap declara cerrada.")
    elif rupture_info is None:
        print("\nNo hay discrepancias en el path encontrado.")

    out_svg = root / 'tools' / f'route_check_{ox}_{oy}_to_{tx}_{ty}.svg'
    render_svg(map_table, conn, path, crossings, (ox, oy), (tx, ty), out_svg)
    print(f"\nWrote {out_svg}")


if __name__ == '__main__':
    main()
