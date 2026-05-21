#!/usr/bin/env python3
"""
preview_final_minimap.py — Genera dos SVG con el estado final del minimap:
  1) tools/minimap_unique_sprites.svg — los 24 sprites unicos agrupados por
     bytes, con salas miembro listadas debajo de cada uno.
  2) tools/minimap_full_preview.svg — los 256 rooms en su posicion (cuadricula
     16x16), cada uno con su sprite asignado. Es el "espejo" de lo que el
     juego pintara en runtime.
"""

import json
from pathlib import Path
from collections import defaultdict

MAP_W = 16
MAP_H = 16


def main():
    root = Path(__file__).resolve().parent.parent
    with (root / 'code' / 'minimap_types.json').open(encoding='utf-8') as f:
        data = json.load(f)
    room_sprites = data.get('room_sprites', {})

    groups = defaultdict(list)
    for key, info in room_sprites.items():
        rx, ry = map(int, key.split(','))
        groups[tuple(info['bytes'])].append((rx, ry))
    sorted_groups = sorted(groups.items(), key=lambda kv: -len(kv[1]))

    # ---- Sheet 1: unique sprites ----
    render_unique_sheet(sorted_groups, root / 'tools' / 'minimap_unique_sprites.svg')

    # ---- Sheet 2: full 16x16 preview ----
    render_full_preview(room_sprites, sorted_groups,
                        root / 'tools' / 'minimap_full_preview.svg')


def render_unique_sheet(sorted_groups, out_path):
    """Cada sprite unico + sus salas miembro."""
    CELL_PX = 12       # cada pixel del sprite en SVG (8x8 -> 96x96)
    SP_SIDE = 8 * CELL_PX
    CARD_W = SP_SIDE + 280
    CARD_H = SP_SIDE + 30
    COLS = 3
    rows = (len(sorted_groups) + COLS - 1) // COLS
    MARGIN = 20
    total_w = MARGIN * 2 + COLS * CARD_W + (COLS - 1) * 30
    total_h = MARGIN * 2 + 60 + rows * (CARD_H + 30)

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" '
           f'height="{total_h}" viewBox="0 0 {total_w} {total_h}" '
           f'shape-rendering="crispEdges">']
    out.append(f'<rect width="{total_w}" height="{total_h}" fill="#0a0a0a"/>')
    total_rooms = sum(len(rooms) for _, rooms in sorted_groups)
    out.append(f'<text x="{MARGIN}" y="32" font-family="monospace" '
               f'font-size="20" font-weight="bold" fill="#e0e0e0">'
               f'Minimap sprites — {len(sorted_groups)} unique / '
               f'{total_rooms} rooms — {len(sorted_groups)*8 + 256} B dedup</text>')

    for i, (bts, rooms) in enumerate(sorted_groups, 1):
        col = (i - 1) % COLS
        row = (i - 1) // COLS
        x = MARGIN + col * (CARD_W + 30)
        y = MARGIN + 60 + row * (CARD_H + 30)
        out.append(f'<rect x="{x}" y="{y}" width="{CARD_W}" height="{CARD_H}" '
                   f'fill="#1a1a1a" stroke="#333" stroke-width="1"/>')
        sx, sy = x + 10, y + 10
        out.append(f'<rect x="{sx}" y="{sy}" width="{SP_SIDE}" '
                   f'height="{SP_SIDE}" fill="#0a0a0a"/>')
        for py in range(8):
            for px in range(8):
                if (bts[py] >> (7 - px)) & 1:
                    pxl_x = sx + px * CELL_PX
                    pxl_y = sy + py * CELL_PX
                    out.append(f'<rect x="{pxl_x}" y="{pxl_y}" '
                               f'width="{CELL_PX}" height="{CELL_PX}" '
                               f'fill="#ffe066"/>')
        tx = sx + SP_SIDE + 16
        ty = sy + 16
        out.append(f'<text x="{tx}" y="{ty}" font-family="monospace" '
                   f'font-size="14" font-weight="bold" fill="#ffe066">'
                   f'S{i:2d}  ({len(rooms)} salas)</text>')
        bts_hex = ', '.join('$' + format(b, '02X') for b in bts)
        out.append(f'<text x="{tx}" y="{ty + 22}" font-family="monospace" '
                   f'font-size="10" fill="#9999bb">{bts_hex}</text>')
        rooms_sorted = sorted(rooms, key=lambda r: (r[0], r[1]))
        # Lista de salas, partida en varias lineas si es necesaria
        text_lines = []
        cur_line = []
        for rx, ry in rooms_sorted:
            cur_line.append(f'({rx},{ry})')
            if len(cur_line) >= 5:
                text_lines.append(' '.join(cur_line))
                cur_line = []
        if cur_line:
            text_lines.append(' '.join(cur_line))
        for li, line in enumerate(text_lines):
            out.append(f'<text x="{tx}" y="{ty + 42 + li * 14}" '
                       f'font-family="monospace" font-size="10" '
                       f'fill="#bbb">{line}</text>')
    out.append('</svg>')
    out_path.write_text('\n'.join(out), encoding='utf-8')
    print(f'Wrote {out_path}')


def render_full_preview(room_sprites, sorted_groups, out_path):
    """Cuadricula 16x16. Cada celda renderiza el sprite asignado a esa sala.
    Monocromo (amarillo) — espejo de lo que pintara el Spectrum in-game."""
    sprite_to_idx = {bts: i for i, (bts, _) in enumerate(sorted_groups, 1)}
    MONO_COLOR = '#ffe066'
    CELL_PX = 4        # pixel del sprite en SVG units
    SP_SIDE = 8 * CELL_PX
    GAP = 0
    CELL_TOTAL = SP_SIDE + GAP
    MARGIN = 24
    HDR = 24
    total_w = MARGIN * 2 + HDR + MAP_W * CELL_TOTAL + 250
    total_h = MARGIN * 2 + 80 + HDR + MAP_H * CELL_TOTAL

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w}" '
           f'height="{total_h}" viewBox="0 0 {total_w} {total_h}" '
           f'shape-rendering="crispEdges">']
    out.append(f'<rect width="{total_w}" height="{total_h}" fill="#0a0a0a"/>')
    out.append(f'<text x="{MARGIN}" y="32" font-family="monospace" '
               f'font-size="20" font-weight="bold" fill="#e0e0e0">'
               f'Minimap preview — 16×16 rooms con sprite asignado</text>')

    # X headers
    for rx in range(MAP_W):
        cx = MARGIN + HDR + rx * CELL_TOTAL + SP_SIDE // 2
        out.append(f'<text x="{cx}" y="{MARGIN + 80 + HDR - 5}" '
                   f'text-anchor="middle" font-family="monospace" '
                   f'font-size="10" fill="#8888aa">{rx}</text>')
    # Y headers
    for ry in range(MAP_H):
        cy = MARGIN + 80 + HDR + ry * CELL_TOTAL + SP_SIDE // 2 + 4
        out.append(f'<text x="{MARGIN + HDR - 4}" y="{cy}" '
                   f'text-anchor="end" font-family="monospace" '
                   f'font-size="10" fill="#8888aa">{ry}</text>')

    # Grid
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            key = f'{rx},{ry}'
            x0 = MARGIN + HDR + rx * CELL_TOTAL
            y0 = MARGIN + 80 + HDR + ry * CELL_TOTAL
            info = room_sprites.get(key)
            if info is None:
                out.append(f'<rect x="{x0}" y="{y0}" width="{SP_SIDE}" '
                           f'height="{SP_SIDE}" fill="#1a1a1a"/>')
                continue
            bts = tuple(info['bytes'])
            out.append(f'<rect x="{x0}" y="{y0}" width="{SP_SIDE}" '
                       f'height="{SP_SIDE}" fill="#0a0a0a"/>')
            for py in range(8):
                for px in range(8):
                    if (bts[py] >> (7 - px)) & 1:
                        pxl_x = x0 + px * CELL_PX
                        pxl_y = y0 + py * CELL_PX
                        out.append(f'<rect x="{pxl_x}" y="{pxl_y}" '
                                   f'width="{CELL_PX}" height="{CELL_PX}" '
                                   f'fill="{MONO_COLOR}"/>')

    # Coordenadas en el centro de cada sala con texto blanco + outline negro
    # (paint-order: stroke antes que fill -> sombra legible en cualquier fondo).
    for ry in range(MAP_H):
        for rx in range(MAP_W):
            x_center = MARGIN + HDR + rx * CELL_TOTAL + SP_SIDE // 2
            y_center = MARGIN + 80 + HDR + ry * CELL_TOTAL + SP_SIDE // 2 + 3
            out.append(f'<text x="{x_center}" y="{y_center}" '
                       f'text-anchor="middle" font-family="monospace" '
                       f'font-size="8" font-weight="bold" '
                       f'paint-order="stroke" stroke="black" stroke-width="3" '
                       f'stroke-linejoin="round" fill="white">'
                       f'{rx},{ry}</text>')

    # Lineas divisorias blancas+negras entre rooms (visible en cualquier fondo)
    grid_x0 = MARGIN + HDR
    grid_y0 = MARGIN + 80 + HDR
    grid_x1 = grid_x0 + MAP_W * CELL_TOTAL
    grid_y1 = grid_y0 + MAP_H * CELL_TOTAL
    for i in range(MAP_W + 1):
        x = grid_x0 + i * CELL_TOTAL
        out.append(f'<line x1="{x}" y1="{grid_y0}" x2="{x}" y2="{grid_y1}" '
                   f'stroke="white" stroke-width="1" stroke-dasharray="2,2"/>')
        out.append(f'<line x1="{x}" y1="{grid_y0}" x2="{x}" y2="{grid_y1}" '
                   f'stroke="black" stroke-width="1" stroke-dasharray="2,2" '
                   f'stroke-dashoffset="2"/>')
    for i in range(MAP_H + 1):
        y = grid_y0 + i * CELL_TOTAL
        out.append(f'<line x1="{grid_x0}" y1="{y}" x2="{grid_x1}" y2="{y}" '
                   f'stroke="white" stroke-width="1" stroke-dasharray="2,2"/>')
        out.append(f'<line x1="{grid_x0}" y1="{y}" x2="{grid_x1}" y2="{y}" '
                   f'stroke="black" stroke-width="1" stroke-dasharray="2,2" '
                   f'stroke-dashoffset="2"/>')

    # Resumen (sin leyenda de color porque es monocromo)
    lx = MARGIN + HDR + MAP_W * CELL_TOTAL + 20
    ly = MARGIN + 80 + HDR
    out.append(f'<text x="{lx}" y="{ly}" font-family="monospace" '
               f'font-size="12" font-weight="bold" fill="#e0e0e0">'
               f'{len(sorted_groups)} sprites unicos</text>')
    out.append(f'<text x="{lx}" y="{ly + 18}" font-family="monospace" '
               f'font-size="10" fill="#bbb">'
               f'{len(sorted_groups)*8 + 256} B dedup</text>')

    out.append('</svg>')
    out_path.write_text('\n'.join(out), encoding='utf-8')
    print(f'Wrote {out_path}')


if __name__ == '__main__':
    main()
