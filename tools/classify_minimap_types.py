#!/usr/bin/env python3
"""
classify_minimap_types.py — Clasifica las 256 salas por topología y produce:
  - code/minimap_types.json: assignment {room: type_id} + descripciones
  - tools/minimap_types_sheet.svg: hoja de referencia visual con los N tipos

Topology signature por sala:
  (T_state, B_state, L_state, R_state, n_compartments, computed_sprite_bitmap)

Donde n_compartments y el sprite computado se calculan con la lógica de
preview_minimap_sprite (coverage 4x3 per-room).
"""

import json
import sys
from pathlib import Path
from collections import defaultdict

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_screen_gaps as bsg
from route_check import build_world_walkgrid
from preview_minimap_sprite import (
    compute_topology_sprite, side_state, real_compartments, compartment_topology
)

MAP_W = 16
MAP_H = 16


def main():
    root = HERE.parent
    code = root / 'code'

    map_table = bsg.parse_map_table(code / 'screen_data.asm')
    room_templates = bsg.parse_rooms(code / 'screen_rooms.asm')
    bg_dims = bsg.parse_bg_dims([code / 'bg_gfx.asm',
                                  code / 'bg_gfx_b.asm',
                                  code / 'bg_gfx_c.asm'])
    with (code / 'level_data.json').open(encoding='utf-8') as f:
        cp = json.load(f)['closedPassages']
    world = build_world_walkgrid(map_table, room_templates, bg_dims)

    # Internamente closedPassages usa T/B/L/R (convención del editor).
    # User-facing: N/S/W/E (norte/sur/oeste/este).
    EDITOR_DIRS = ('T', 'B', 'L', 'R')
    NSWE = ('N', 'S', 'W', 'E')

    groups = defaultdict(list)
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            if map_table[ry][rx] == 0:
                continue
            sides = tuple(side_state(cp, rx, ry, d, map_table)
                          for d in EDITOR_DIRS)
            _, real_set = real_compartments(world, rx, ry)
            n_real = len(real_set)
            topo = compartment_topology(world, rx, ry)
            # Topo se hace hashable serializando ordenadamente
            topo_key = tuple(sorted(tuple(sorted(s)) for s in topo))
            signature = (sides, n_real, topo_key)
            groups[signature].append((rx, ry))

    sorted_groups = sorted(groups.items(), key=lambda kv: -len(kv[1]))

    # Cargar sprites guardados; agrupar por (sides_pattern, has_tabique)
    prev_sprites = {}     # (sides_tuple, has_tabique_bool) -> (sprite, bytes)
    if (code / 'minimap_types.json').exists():
        try:
            with (code / 'minimap_types.json').open(encoding='utf-8') as f:
                prev = json.load(f)
            for t in prev.get('types', []):
                if t.get('user_sprite'):
                    sides_key = (t['sides']['N'], t['sides']['S'],
                                 t['sides']['W'], t['sides']['E'])
                    has_tab = t['compartments'] > 1
                    prev_sprites[(sides_key, has_tab)] = (
                        t['user_sprite'], t.get('user_sprite_bytes'))
        except Exception:
            pass

    types = []
    room_to_type = {}
    for type_id, (sig, rooms) in enumerate(sorted_groups, 1):
        sides, n_real, topo_key = sig
        # Recompute sprite del primer room para el render visual (placeholder)
        rep_rx, rep_ry = rooms[0]
        sp_data = compute_topology_sprite(world, cp, map_table,
                                           rep_rx, rep_ry, 8, 8)
        sp = tuple(tuple(row) for row in sp_data)
        has_tab = n_real > 1
        key = (sides, has_tab)
        migrated_sprite = None
        migrated_bytes = None
        if key in prev_sprites:
            migrated_sprite, migrated_bytes = prev_sprites[key]
        elif (sides, not has_tab) in prev_sprites and not has_tab:
            # Fallback: si no hay match exacto pero hay versión con/sin tabique
            # del mismo patron, no migrar (el usuario debería redibujarlo).
            pass
        # Topology fingerprint legible (slot sets por compartimento)
        topo_str = ' | '.join('{' + ','.join(slot_set) + '}'
                              for slot_set in topo_key)
        types.append({
            'id': type_id,
            'sides': dict(zip(NSWE, sides)),
            'compartments': n_real,
            'topology': topo_str,
            'room_count': len(rooms),
            'rooms': [{'x': rx, 'y': ry} for rx, ry in rooms],
            'computed_sprite': [list(row) for row in sp],
            'user_sprite': migrated_sprite,
            'user_sprite_bytes': migrated_bytes,
        })
        for rx, ry in rooms:
            room_to_type[f'{rx},{ry}'] = type_id

    out = {
        'types': types,
        'room_to_type': room_to_type,
    }
    out_json = code / 'minimap_types.json'
    with out_json.open('w', encoding='utf-8') as f:
        json.dump(out, f, indent=2)
    print(f'Wrote {out_json}  ({len(types)} types)')

    # Generate reference SVG sheet
    render_sheet(types, root / 'tools' / 'minimap_types_sheet.svg')


def render_sheet(types, out_path):
    """SVG con todos los tipos: ID, descripción, sample rooms, sprite computado."""
    CELL_PX = 8                     # cada pixel del sprite en SVG units
    SP_SIDE = 8 * CELL_PX           # sprite 8x8 px = 64 SVG units
    TYPE_W = SP_SIDE + 280          # ancho de cada "card" de tipo
    TYPE_H = SP_SIDE + 50           # alto
    COLS = 2
    rows = (len(types) + COLS - 1) // COLS
    MARGIN = 20
    total_w = MARGIN * 2 + COLS * TYPE_W + (COLS - 1) * 30
    total_h = MARGIN * 2 + rows * (TYPE_H + 30) + 50

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" '
           f'height="{total_h}" viewBox="0 0 {total_w} {total_h}" '
           f'shape-rendering="crispEdges">']
    out.append(f'<rect width="{total_w}" height="{total_h}" fill="#0a0a0a"/>')
    out.append(f'<text x="{MARGIN}" y="32" font-family="monospace" '
               f'font-size="20" font-weight="bold" fill="#e0e0e0">'
               f'Minimap room types — {len(types)} unique topologies</text>')

    for i, t in enumerate(types):
        col = i % COLS
        row = i // COLS
        x = MARGIN + col * (TYPE_W + 30)
        y = MARGIN + 50 + row * (TYPE_H + 30)

        # Card background
        out.append(f'<rect x="{x}" y="{y}" width="{TYPE_W}" height="{TYPE_H}" '
                   f'fill="#1a1a1a" stroke="#333" stroke-width="1"/>')

        # Sprite preview (left). Si hay user_sprite, mostrarlo (amarillo bright).
        # Si no, mostrar computed_sprite tenue (gris) como referencia.
        sx, sy = x + 10, y + 10
        out.append(f'<rect x="{sx}" y="{sy}" width="{SP_SIDE}" '
                   f'height="{SP_SIDE}" fill="#0a0a0a"/>')
        is_user = t.get('user_sprite') is not None
        sprite_data = t['user_sprite'] if is_user else t['computed_sprite']
        color = '#ffe066' if is_user else '#555'
        for py in range(8):
            for px in range(8):
                if sprite_data[py][px]:
                    pxl_x = sx + px * CELL_PX
                    pxl_y = sy + py * CELL_PX
                    out.append(f'<rect x="{pxl_x}" y="{pxl_y}" '
                               f'width="{CELL_PX}" height="{CELL_PX}" '
                               f'fill="{color}"/>')
        # Marca visual si es user-provided
        if is_user:
            out.append(f'<rect x="{sx-2}" y="{sy-2}" width="{SP_SIDE+4}" '
                       f'height="{SP_SIDE+4}" fill="none" '
                       f'stroke="#22d3ee" stroke-width="2"/>')

        # Info text (right of sprite)
        tx = sx + SP_SIDE + 16
        ty = sy + 14
        out.append(f'<text x="{tx}" y="{ty}" font-family="monospace" '
                   f'font-size="14" font-weight="bold" fill="#ffe066">'
                   f'Tipo {t["id"]:2d}  ({t["room_count"]} salas)</text>')
        sides_str = (f"N={t['sides']['N']}  S={t['sides']['S']}  "
                     f"W={t['sides']['W']}  E={t['sides']['E']}")
        out.append(f'<text x="{tx}" y="{ty + 22}" font-family="monospace" '
                   f'font-size="11" fill="#bbb">{sides_str}</text>')
        out.append(f'<text x="{tx}" y="{ty + 38}" font-family="monospace" '
                   f'font-size="11" fill="#bbb">'
                   f'compartimentos: {t["compartments"]}</text>')
        sample = ', '.join(f"({r['x']},{r['y']})"
                            for r in t['rooms'][:4])
        if t['room_count'] > 4:
            sample += '…'
        out.append(f'<text x="{tx}" y="{ty + 54}" font-family="monospace" '
                   f'font-size="10" fill="#888">ej: {sample}</text>')

    out.append('</svg>')
    out_path.write_text('\n'.join(out), encoding='utf-8')
    print(f'Wrote {out_path}')


if __name__ == '__main__':
    main()
