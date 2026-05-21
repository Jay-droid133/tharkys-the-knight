#!/usr/bin/env python3
"""
preview_minimap_sprite.py — Preview the sprite-based minimap proposal.

Renders three panels side-by-side at 4x zoom:
  Panel 1: Current minimap (paramétrico desde MinimapConnTable).
  Panel 2: Option A — sprite 8x8 px por sala, derivado del playerWalkGrid 4x3
           sub-sampleado. 1 char (8x8 px) por sala. Drop-in al layout actual.
  Panel 3: Option B — sprite 16x8 px por sala (2 chars × 1 char). Resolucion
           horizontal x2; ocupa todo el ancho de pantalla in-game (32 cols).

Sub-sampleo: pixel walkable si HAY al menos 1 anchor player walkable
(4x3 footprint) dentro del grupo de chars que ese pixel representa.

Tambien imprime stats de deduplicacion (cuantos sprites unicos para A/B).
"""

import json
import re
import sys
from pathlib import Path
from collections import Counter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_screen_gaps as bsg
from route_check import build_world_walkgrid, build_player_walkgrid

GRID_W = 32
GRID_H = 22
MAP_W = 16
MAP_H = 16
GW = MAP_W * GRID_W
GH = MAP_H * GRID_H


def parse_conn_table(path):
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


def subsample_room(walk, rx, ry, sprite_w, sprite_h, mode='AND'):
    """For each pixel of the sprite, sample the chars in its sub-region.
    mode='AND': pixel walkable iff ALL chars walkable (conservative, preserva
                tabiques de 1 char).
    mode='OR':  pixel walkable iff ANY char walkable (liberal, ignora tabiques
                pequenios).
    Returns 2D list of 0/1, [sprite_h][sprite_w]."""
    base_x = rx * GRID_W
    base_y = ry * GRID_H
    sprite = [[0] * sprite_w for _ in range(sprite_h)]
    for py in range(sprite_h):
        cy0 = base_y + (py * GRID_H) // sprite_h
        cy1 = base_y + ((py + 1) * GRID_H) // sprite_h
        for px in range(sprite_w):
            cx0 = base_x + (px * GRID_W) // sprite_w
            cx1 = base_x + ((px + 1) * GRID_W) // sprite_w
            if mode == 'AND':
                walkable = True
                for cy in range(cy0, cy1):
                    if not walkable:
                        break
                    for cx in range(cx0, cx1):
                        if not walk[cy * GW + cx]:
                            walkable = False
                            break
            else:
                walkable = False
                for cy in range(cy0, cy1):
                    if walkable:
                        break
                    for cx in range(cx0, cx1):
                        if walk[cy * GW + cx]:
                            walkable = True
                            break
            sprite[py][px] = 1 if walkable else 0
    return sprite


def side_state(closed_passages, rx, ry, dir_letter, map_table=None):
    """Return 'closed', 'dual', or 'open'. Si no hay sala vecina, devuelve
    'closed' (el borde del mapa siempre es pared)."""
    if map_table is not None:
        nx, ny = rx, ry
        if dir_letter == 'T':
            ny = ry - 1
        elif dir_letter == 'B':
            ny = ry + 1
        elif dir_letter == 'L':
            nx = rx - 1
        elif dir_letter == 'R':
            nx = rx + 1
        if nx < 0 or nx >= MAP_W or ny < 0 or ny >= MAP_H \
                or map_table[ny][nx] == 0:
            return 'closed'
    v = closed_passages.get(f"{rx},{ry},{dir_letter}")
    if v == 'closed' or v is True:
        return 'closed'
    if v == 'dual':
        return 'dual'
    return 'open'


FOOT_W, FOOT_H = 4, 3


def find_room_compartments(walk, rx, ry):
    """Per-room: componentes conexas de coverage cells (chars donde el
    player puede estar, con huella 4x3 que no escapa de este room).
    Devuelve (comp_grid, n_comps) donde comp_grid[cy][cx] = idx (>=0)
    o -1 si el char no es player-reachable."""
    base_x = rx * GRID_W
    base_y = ry * GRID_H
    # Player walkGrid local (anchors per-room; no neighbor merge — tabiques
    # son intra-room, no inter-room).
    pw = [[False] * GRID_W for _ in range(GRID_H)]
    for cy in range(GRID_H - FOOT_H + 1):
        for cx in range(GRID_W - FOOT_W + 1):
            ok = True
            for dy in range(FOOT_H):
                if not ok:
                    break
                for dx in range(FOOT_W):
                    if not walk[(base_y + cy + dy) * GW + (base_x + cx + dx)]:
                        ok = False
                        break
            if ok:
                pw[cy][cx] = True
    # Coverage: char (cx, cy) está cubierto si algún anchor en
    # [cx-3..cx, cy-2..cy] es walkable.
    cover = [[False] * GRID_W for _ in range(GRID_H)]
    for cy in range(GRID_H):
        for cx in range(GRID_W):
            done = False
            for dy in range(FOOT_H):
                ay = cy - dy
                if ay < 0:
                    break
                for dx in range(FOOT_W):
                    ax = cx - dx
                    if ax < 0:
                        break
                    if pw[ay][ax]:
                        cover[cy][cx] = True
                        done = True
                        break
                if done:
                    break
    # CC sobre coverage
    comp = [[-1] * GRID_W for _ in range(GRID_H)]
    n_comps = 0
    for cy0 in range(GRID_H):
        for cx0 in range(GRID_W):
            if not cover[cy0][cx0] or comp[cy0][cx0] != -1:
                continue
            stack = [(cx0, cy0)]
            while stack:
                cx, cy = stack.pop()
                if comp[cy][cx] != -1:
                    continue
                comp[cy][cx] = n_comps
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < GRID_W and 0 <= ny < GRID_H \
                            and cover[ny][nx] and comp[ny][nx] == -1:
                        stack.append((nx, ny))
            n_comps += 1
    return comp, n_comps


def exit_slots(walk, rx, ry):
    """Find contiguous walkable runs along each room border.
    Returns dict {side: [list of cells (cx, cy) in walkgrid coords]}.
    Each slot is a contiguous run on that border; slots are labeled by
    position (top-to-bottom for W/E, left-to-right for N/S)."""
    base_x = rx * GRID_W
    base_y = ry * GRID_H
    slots = {'N': [], 'S': [], 'W': [], 'E': []}

    def find_runs(coords):
        """coords is a list of indices; group consecutive into runs."""
        runs = []
        for c in coords:
            if runs and c == runs[-1][-1] + 1:
                runs[-1].append(c)
            else:
                runs.append([c])
        return runs

    # N: row 0
    n_walk = [cx for cx in range(GRID_W)
              if walk[base_y * GW + (base_x + cx)]]
    for run in find_runs(n_walk):
        slots['N'].append([(cx, 0) for cx in run])
    # S: row GRID_H-1
    s_walk = [cx for cx in range(GRID_W)
              if walk[(base_y + GRID_H - 1) * GW + (base_x + cx)]]
    for run in find_runs(s_walk):
        slots['S'].append([(cx, GRID_H - 1) for cx in run])
    # W: col 0
    w_walk = [cy for cy in range(GRID_H)
              if walk[(base_y + cy) * GW + base_x]]
    for run in find_runs(w_walk):
        slots['W'].append([(0, cy) for cy in run])
    # E: col GRID_W-1
    e_walk = [cy for cy in range(GRID_H)
              if walk[(base_y + cy) * GW + (base_x + GRID_W - 1)]]
    for run in find_runs(e_walk):
        slots['E'].append([(GRID_W - 1, cy) for cy in run])
    return slots


def compartment_topology(walk, rx, ry):
    """Devuelve la signature topologica de la sala: para cada compartimento
    REAL, qué exit slots (etiquetados N0/N1/S0/.../W0/W1/E0/E1) contiene.
    Returns frozenset({frozenset_of_slot_labels for each compartment}).
    Dos salas con la misma signature tienen exactamente la misma topología
    de routing (mismas conexiones interiores entre exits)."""
    comp, _ = find_room_compartments(walk, rx, ry)
    slots = exit_slots(walk, rx, ry)
    # Para cada slot, encontrar qué compartimento real lo contiene
    # (busca un cell del slot en el comp grid).
    slot_to_comp = {}
    for side, side_slots in slots.items():
        for idx, cells in enumerate(side_slots):
            label = f'{side}{idx}'
            for (cx, cy) in cells:
                cid = comp[cy][cx]
                if cid >= 0:
                    slot_to_comp[label] = cid
                    break
    # Invertir: para cada comp, qué slots tiene
    comp_to_slots = {}
    for label, cid in slot_to_comp.items():
        comp_to_slots.setdefault(cid, set()).add(label)
    # Signature: frozenset de frozensets de slot labels
    return frozenset(frozenset(s) for s in comp_to_slots.values())


def real_compartments(walk, rx, ry):
    """Devuelve (comp_grid, real_set) donde real_set son los IDs de
    componentes que TOCAN al menos un borde walkable del room (es decir,
    conectan con algún exit). Pockets internos (sin acceso al borde) se
    filtran — no son tabiques desde el punto de vista del gameplay."""
    comp, _ = find_room_compartments(walk, rx, ry)
    real_set = set()
    for cx in range(GRID_W):
        if comp[0][cx] >= 0:
            real_set.add(comp[0][cx])
        if comp[GRID_H - 1][cx] >= 0:
            real_set.add(comp[GRID_H - 1][cx])
    for cy in range(GRID_H):
        if comp[cy][0] >= 0:
            real_set.add(comp[cy][0])
        if comp[cy][GRID_W - 1] >= 0:
            real_set.add(comp[cy][GRID_W - 1])
    return comp, real_set


def find_tabique_chars(walk, rx, ry):
    """Tabique = chars unwalkable que separan COMPARTIMENTOS REALES (con
    acceso a algún borde de la sala). Pockets internos se ignoran."""
    comp, real_set = real_compartments(walk, rx, ry)
    if len(real_set) <= 1:
        return set()
    base_x = rx * GRID_W
    base_y = ry * GRID_H
    tabique = set()
    for cy in range(GRID_H):
        for cx in range(GRID_W):
            if walk[(base_y + cy) * GW + (base_x + cx)]:
                continue
            comps_seen = set()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < GRID_W and 0 <= ny < GRID_H:
                    cid = comp[ny][nx]
                    if cid in real_set:
                        comps_seen.add(cid)
            if len(comps_seen) >= 2:
                tabique.add((cx, cy))
    return tabique


def room_interior_walls(walk, rx, ry, sprite_w, sprite_h):
    """Render del area interior del sprite (px 1..W-2, py 1..H-2) marcando
    pixels que contienen chars TABIQUE (separadores reales del room). No
    pinta decoraciones aisladas."""
    tabique = find_tabique_chars(walk, rx, ry)
    sprite = [[0] * sprite_w for _ in range(sprite_h)]
    if not tabique:
        return sprite
    INNER_X0, INNER_X1 = 1, GRID_W - 1     # cols 1..30 (interior del room)
    INNER_Y0, INNER_Y1 = 1, GRID_H - 1     # rows 1..20
    inner_w = sprite_w - 2
    inner_h = sprite_h - 2
    chars_w = INNER_X1 - INNER_X0
    chars_h = INNER_Y1 - INNER_Y0
    for ipy in range(inner_h):
        cy0 = INNER_Y0 + (ipy * chars_h) // inner_h
        cy1 = INNER_Y0 + ((ipy + 1) * chars_h) // inner_h
        for ipx in range(inner_w):
            cx0 = INNER_X0 + (ipx * chars_w) // inner_w
            cx1 = INNER_X0 + ((ipx + 1) * chars_w) // inner_w
            for cy in range(cy0, cy1):
                hit = False
                for cx in range(cx0, cx1):
                    if (cx, cy) in tabique:
                        sprite[1 + ipy][1 + ipx] = 1
                        hit = True
                        break
                if hit:
                    break
    return sprite


def compute_topology_sprite(walk, closed_passages, map_table, rx, ry,
                             sprite_w, sprite_h):
    """Topology sprite: bordes según closedPassages + tabiques internos
    según walkGrid. Convention: 1 = pared/decoración, 0 = espacio caminable."""
    sprite = [[0] * sprite_w for _ in range(sprite_h)]
    n = side_state(closed_passages, rx, ry, 'T', map_table)
    s = side_state(closed_passages, rx, ry, 'B', map_table)
    w = side_state(closed_passages, rx, ry, 'L', map_table)
    e = side_state(closed_passages, rx, ry, 'R', map_table)

    # --- Tabiques internos (sample interior solamente)
    interior = room_interior_walls(walk, rx, ry, sprite_w, sprite_h)
    for py in range(sprite_h):
        for px in range(sprite_w):
            if interior[py][px]:
                sprite[py][px] = 1

    # --- Outer border
    # Pixel patterns por estado:
    #   closed: linea continua
    #   open  : nada
    #   dual  : 2 segmentos (uno cerca de cada esquina)
    def draw_top():
        if n == 'closed':
            for x in range(sprite_w):
                sprite[0][x] = 1
        elif n == 'dual':
            seg = max(1, sprite_w // 4)
            for x in range(seg):
                sprite[0][x] = 1
                sprite[0][sprite_w - 1 - x] = 1

    def draw_bot():
        if s == 'closed':
            for x in range(sprite_w):
                sprite[sprite_h - 1][x] = 1
        elif s == 'dual':
            seg = max(1, sprite_w // 4)
            for x in range(seg):
                sprite[sprite_h - 1][x] = 1
                sprite[sprite_h - 1][sprite_w - 1 - x] = 1

    def draw_left():
        if w == 'closed':
            for y in range(sprite_h):
                sprite[y][0] = 1
        elif w == 'dual':
            seg = max(1, sprite_h // 4)
            for y in range(seg):
                sprite[y][0] = 1
                sprite[sprite_h - 1 - y][0] = 1

    def draw_right():
        if e == 'closed':
            for y in range(sprite_h):
                sprite[y][sprite_w - 1] = 1
        elif e == 'dual':
            seg = max(1, sprite_h // 4)
            for y in range(seg):
                sprite[y][sprite_w - 1] = 1
                sprite[sprite_h - 1 - y][sprite_w - 1] = 1

    draw_top(); draw_bot(); draw_left(); draw_right()

    # --- Corner dots: si hay BG sprite decorativo en la esquina del room,
    # mostrar el dot. Se detecta por el char esquinero del walkGrid.
    base_x = rx * GRID_W
    base_y = ry * GRID_H
    if not walk[base_y * GW + base_x]:
        sprite[0][0] = 1
    if not walk[base_y * GW + (base_x + GRID_W - 1)]:
        sprite[0][sprite_w - 1] = 1
    if not walk[(base_y + GRID_H - 1) * GW + base_x]:
        sprite[sprite_h - 1][0] = 1
    if not walk[(base_y + GRID_H - 1) * GW + (base_x + GRID_W - 1)]:
        sprite[sprite_h - 1][sprite_w - 1] = 1

    return sprite


def compute_sprites(walk, map_table, sprite_w, sprite_h, mode='AND',
                    closed_passages=None):
    """Returns: per_room[ry][rx] = sprite (or None), unique_count.
    Si closed_passages se provee, usa la representacion topologica
    (bordes desde closedPassages + interior desde walkGrid).
    Si no, usa sub-sampleo plano."""
    per_room = [[None] * MAP_W for _ in range(MAP_H)]
    bitmap_keys = []
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            if map_table[ry][rx] == 0:
                continue
            if closed_passages is not None:
                sp = compute_topology_sprite(walk, closed_passages, map_table,
                                              rx, ry, sprite_w, sprite_h)
            else:
                sp = subsample_room(walk, rx, ry, sprite_w, sprite_h, mode)
            per_room[ry][rx] = sp
            key = tuple(tuple(row) for row in sp)
            bitmap_keys.append(key)
    unique = len(set(bitmap_keys))
    return per_room, unique


def conn_to_walls(conn, rx, ry):
    """Returns (N,S,W,E) bool wall flags from conn byte (1 in bit means open)."""
    f = conn[ry][rx]
    return (not (f & 0x08), not (f & 0x04), not (f & 0x02), not (f & 0x01))


def render_svg(map_table, conn, sprites_a, sprites_b, out_path,
               sprite_a_dims, sprite_b_dims, unique_a, unique_b):
    """Render 3 panels side-by-side at 4x zoom."""
    ZOOM = 4
    MARGIN = 16
    HDR = 18
    TITLE_H = 50

    # Panel A and "current" use same cell size (8x8 px scaled 4x = 32x32)
    cell_aw, cell_ah = sprite_a_dims[0] * ZOOM, sprite_a_dims[1] * ZOOM
    cell_bw, cell_bh = sprite_b_dims[0] * ZOOM, sprite_b_dims[1] * ZOOM
    cur_cell_w, cur_cell_h = 8 * ZOOM, 8 * ZOOM   # current is 8x8 logical

    def panel_size(cell_w, cell_h):
        w = MARGIN * 2 + HDR + MAP_W * cell_w + 10
        h = TITLE_H + MARGIN + HDR + MAP_H * cell_h + MARGIN
        return w, h

    w_cur, h_cur = panel_size(cur_cell_w, cur_cell_h)
    w_a, h_a = panel_size(cell_aw, cell_ah)
    w_b, h_b = panel_size(cell_bw, cell_bh)

    gap = 20
    total_w = MARGIN + w_cur + gap + w_a + gap + w_b + MARGIN
    total_h = MARGIN + max(h_cur, h_a, h_b) + MARGIN

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" '
           f'height="{total_h}" viewBox="0 0 {total_w} {total_h}" '
           f'shape-rendering="crispEdges">']
    out.append(f'<rect width="{total_w}" height="{total_h}" fill="#0a0a0a"/>')

    def draw_headers(x_off, y_off, cell_w, cell_h):
        # X headers
        for rx in range(MAP_W):
            cx = x_off + HDR + rx * cell_w + cell_w // 2
            out.append(f'<text x="{cx}" y="{y_off + HDR - 5}" '
                       f'text-anchor="middle" font-family="monospace" '
                       f'font-size="10" fill="#8888aa">{rx}</text>')
        # Y headers
        for ry in range(MAP_H):
            cy = y_off + HDR + ry * cell_h + cell_h // 2 + 4
            out.append(f'<text x="{x_off + HDR - 4}" y="{cy}" '
                       f'text-anchor="end" font-family="monospace" '
                       f'font-size="10" fill="#8888aa">{ry}</text>')

    def panel_title(x_off, w, title, subtitle):
        out.append(f'<text x="{x_off + w//2}" y="{MARGIN + 20}" '
                   f'text-anchor="middle" font-family="monospace" '
                   f'font-size="14" font-weight="bold" fill="#e0e0e0">'
                   f'{title}</text>')
        out.append(f'<text x="{x_off + w//2}" y="{MARGIN + 38}" '
                   f'text-anchor="middle" font-family="monospace" '
                   f'font-size="11" fill="#9999bb">{subtitle}</text>')

    # --- Panel 1: Current (paramétrico) ---
    x_off = MARGIN
    y_off = MARGIN + TITLE_H
    panel_title(x_off, w_cur, "Actual (paramétrico)",
                "1 byte/sala desde MinimapConnTable")
    draw_headers(x_off, y_off, cur_cell_w, cur_cell_h)
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            x = x_off + HDR + rx * cur_cell_w
            y = y_off + HDR + ry * cur_cell_h
            exists = map_table[ry][rx] != 0
            fill = '#000033' if exists else '#0a0a0a'
            out.append(f'<rect x="{x}" y="{y}" width="{cur_cell_w}" '
                       f'height="{cur_cell_h}" fill="{fill}"/>')
            if not exists:
                continue
            wn, ws, ww, we = conn_to_walls(conn, rx, ry)
            wc = '#ffe066'
            t = 2
            if wn:
                out.append(f'<line x1="{x}" y1="{y}" x2="{x+cur_cell_w}" '
                           f'y2="{y}" stroke="{wc}" stroke-width="{t}"/>')
            if ws:
                out.append(f'<line x1="{x}" y1="{y+cur_cell_h}" '
                           f'x2="{x+cur_cell_w}" y2="{y+cur_cell_h}" '
                           f'stroke="{wc}" stroke-width="{t}"/>')
            if ww:
                out.append(f'<line x1="{x}" y1="{y}" x2="{x}" '
                           f'y2="{y+cur_cell_h}" stroke="{wc}" '
                           f'stroke-width="{t}"/>')
            if we:
                out.append(f'<line x1="{x+cur_cell_w}" y1="{y}" '
                           f'x2="{x+cur_cell_w}" y2="{y+cur_cell_h}" '
                           f'stroke="{wc}" stroke-width="{t}"/>')

    def draw_sprite_panel(x_off, w_panel, sprites, sprite_w, sprite_h,
                          cell_w, cell_h, title, subtitle):
        panel_title(x_off, w_panel, title, subtitle)
        y_off = MARGIN + TITLE_H
        draw_headers(x_off, y_off, cell_w, cell_h)
        px_w = cell_w / sprite_w
        px_h = cell_h / sprite_h
        for ry in range(MAP_H):
            for rx in range(MAP_W):
                x0 = x_off + HDR + rx * cell_w
                y0 = y_off + HDR + ry * cell_h
                sp = sprites[ry][rx]
                fill_bg = '#0a0a0a'
                if sp is None:
                    out.append(f'<rect x="{x0}" y="{y0}" width="{cell_w}" '
                               f'height="{cell_h}" fill="{fill_bg}"/>')
                    continue
                # Walls = amarillo, walkable = fondo oscuro (mismo lenguaje
                # visual que el minimap actual: paredes en amarillo brillante).
                out.append(f'<rect x="{x0}" y="{y0}" width="{cell_w}" '
                           f'height="{cell_h}" fill="#1a1a1a"/>')
                for py in range(sprite_h):
                    for px in range(sprite_w):
                        if sp[py][px]:
                            px_x = x0 + px * px_w
                            px_y = y0 + py * px_h
                            out.append(f'<rect x="{px_x:.1f}" y="{px_y:.1f}" '
                                       f'width="{px_w:.1f}" height="{px_h:.1f}" '
                                       f'fill="#ffe066"/>')

    # --- Panel 2: Option A ---
    x_off_a = MARGIN + w_cur + gap
    sw_a, sh_a = sprite_a_dims
    bytes_per_sprite = (sw_a * sh_a) // 8
    raw_bytes = 256 * bytes_per_sprite
    dedup_bytes = unique_a * bytes_per_sprite + 256  # +256 for index table
    draw_sprite_panel(
        x_off_a, w_a, sprites_a, sw_a, sh_a, cell_aw, cell_ah,
        f"Opción A: sprite {sw_a}x{sh_a} px/sala",
        f"únicos {unique_a}/256, {dedup_bytes}B dedup ({raw_bytes}B raw)")

    # --- Panel 3: Option B ---
    x_off_b = x_off_a + w_a + gap
    sw_b, sh_b = sprite_b_dims
    bytes_per_sprite_b = (sw_b * sh_b) // 8
    raw_bytes_b = 256 * bytes_per_sprite_b
    dedup_bytes_b = unique_b * bytes_per_sprite_b + 256
    draw_sprite_panel(
        x_off_b, w_b, sprites_b, sw_b, sh_b, cell_bw, cell_bh,
        f"Opción B: sprite {sw_b}x{sh_b} px/sala",
        f"únicos {unique_b}/256, {dedup_bytes_b}B dedup ({raw_bytes_b}B raw)")

    out.append('</svg>')
    out_path.write_text('\n'.join(out), encoding='utf-8')


def main():
    root = Path(__file__).resolve().parent.parent
    code = root / 'code'

    print("Parsing ASM...")
    map_table = bsg.parse_map_table(code / 'screen_data.asm')
    room_templates = bsg.parse_rooms(code / 'screen_rooms.asm')
    bg_dims = bsg.parse_bg_dims([code / 'bg_gfx.asm',
                                  code / 'bg_gfx_b.asm',
                                  code / 'bg_gfx_c.asm'])
    conn = parse_conn_table(code / 'minimap_conn.asm')

    print("Loading closedPassages...")
    with (code / 'level_data.json').open(encoding='utf-8') as f:
        ld = json.load(f)
    closed_passages = ld.get('closedPassages', {})

    print("Building world walkGrid + player erosion (4x3)...")
    world = build_world_walkgrid(map_table, room_templates, bg_dims)
    player = build_player_walkgrid(world)
    print(f"  walkable player anchors: {sum(player)}/{GW*GH}")

    # Coverage: char (cx,cy) está "ocupable por el player" si existe algun
    # ancla 4x3 walkable que lo cubra (ax in [cx-3..cx], ay in [cy-2..cy]).
    # Esto elimina el sesgo de borde derecho/inferior del playerWalkGrid puro.
    FW, FH = 4, 3
    cover = bytearray(GW * GH)
    for cy in range(GH):
        for cx in range(GW):
            for dy in range(FH):
                ay = cy - dy
                if ay < 0:
                    break
                for dx in range(FW):
                    ax = cx - dx
                    if ax < 0:
                        break
                    if player[ay * GW + ax]:
                        cover[cy * GW + cx] = 1
                        break
                if cover[cy * GW + cx]:
                    break
    print(f"  player-reachable chars (coverage): {sum(cover)}/{GW*GH}")

    # Topological: outer border desde closedPassages + solo TABIQUES reales
    # (chars que separan compartimentos, no decoraciones). Usa walkGrid base.
    print("Computing 8x8 px topology sprites (Opción A)...")
    sprites_a, unique_a = compute_sprites(world, map_table, 8, 8,
                                           closed_passages=closed_passages)
    print(f"  unique sprites: {unique_a}/256")

    print("Computing 16x8 px topology sprites (Opción B)...")
    sprites_b, unique_b = compute_sprites(world, map_table, 16, 8,
                                           closed_passages=closed_passages)
    print(f"  unique sprites: {unique_b}/256")

    out_svg = root / 'tools' / 'minimap_sprite_preview.svg'
    render_svg(map_table, conn, sprites_a, sprites_b, out_svg,
               (8, 8), (16, 8), unique_a, unique_b)
    print(f"\nWrote {out_svg}")
    print("\nSize estimates:")
    print(f"  Opción A (8x8): {unique_a*8 + 256} B dedup, {256*8} B raw")
    print(f"  Opción B (16x8): {unique_b*16 + 256} B dedup, {256*16} B raw")


if __name__ == '__main__':
    main()
