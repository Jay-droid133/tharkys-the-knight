#!/usr/bin/env python3
"""
import_player_run.py - Importa las animaciones de correr del player (East/West)
desde un .aseprite.

Default: References/player04.aseprite -- strip 16x21 frames con tags:
    "move west" (0..3), "move east" (4..7), "idle" (8..9),
    "move south" (10..13), "move north" (14..17).

Solo importa EAST y WEST por ahora. El engine reproduce la animacion como
patron 0,1,2,1 (sprite 1 reutilizado como pose de paso), asi que solo se
necesitan 3 sprites por direccion: cogemos los primeros 3 frames de cada tag
y descartamos el 4o.

Reemplaza los bloques DEFB de SprWalkE0..2 y SprWalkW0..2 en sprite_data.asm.

Formato de salida (sprite_data.asm convention - bytes NO CPL'd):
    SprWalkE{N}:
        DEFB 2, 21
        DEFB %........, %........
        ... (21 lineas)
"""

import sys, os, re, json, subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASEPRITE    = r"C:\Program Files\Aseprite\aseprite.exe"
SPRITE_DATA = os.path.join(ROOT, 'code', 'sprite_data.asm')
EXPORT_DIR  = os.path.join(ROOT, 'References', 'export')
DEFAULT_ASE = os.path.join(ROOT, 'References', 'player04.aseprite')

FRAME_W = 16
FRAME_H = 21
# Mapeo: para cada label, qué tag del aseprite y qué offset (0..2 dentro del tag).
# El engine repite el frame 1 al final (patron 0,1,2,1), asi que ignoramos el
# 4o frame de cada tag.
TARGETS = [
    ('SprWalkW0', 'move west', 0),
    ('SprWalkW1', 'move west', 1),
    ('SprWalkW2', 'move west', 2),
    ('SprWalkE0', 'move east', 0),
    ('SprWalkE1', 'move east', 1),
    ('SprWalkE2', 'move east', 2),
]


def export_aseprite(aseprite_path):
    name = os.path.splitext(os.path.basename(aseprite_path))[0]
    sheet_png  = os.path.join(EXPORT_DIR, f'{name}_sheet.png')
    sheet_json = os.path.join(EXPORT_DIR, f'{name}_sheet.json')
    os.makedirs(EXPORT_DIR, exist_ok=True)
    r = subprocess.run([
        ASEPRITE, '--batch', aseprite_path,
        '--sheet', sheet_png, '--sheet-type', 'rows',
        '--data', sheet_json, '--format', 'json-array',
        '--list-tags',
    ], capture_output=True, text=True)
    if r.returncode != 0:
        print(f'Aseprite error: {r.stderr}', file=sys.stderr)
        sys.exit(1)
    return sheet_png, sheet_json


def frame_to_defb(img, frame_info, label):
    fx, fy = frame_info['frame']['x'], frame_info['frame']['y']
    fw, fh = frame_info['frame']['w'], frame_info['frame']['h']
    if fw != FRAME_W or fh != FRAME_H:
        print(f'  ERROR: frame {label} es {fw}x{fh}, esperado '
              f'{FRAME_W}x{FRAME_H}', file=sys.stderr)
        sys.exit(1)
    wb = fw // 8
    BRIGHT_THRESHOLD = 128
    lines = [f'{label}:', f'    DEFB {wb}, {fh}']
    for y in range(fh):
        row = []
        for b in range(wb):
            byte = 0
            for bit in range(8):
                px = img.getpixel((fx + b * 8 + bit, fy + y))
                if isinstance(px, tuple):
                    if len(px) >= 4 and px[3] < 128:
                        on = False
                    else:
                        on = max(px[:3]) >= BRIGHT_THRESHOLD
                else:
                    on = px >= BRIGHT_THRESHOLD
                if on:
                    byte |= (1 << (7 - bit))
            row.append(f'%{byte:08b}')
        lines.append(f'    DEFB {", ".join(row)}')
    return '\n'.join(lines)


def replace_block(content, label, new_block):
    pattern = re.compile(
        rf'^{re.escape(label)}:[^\n]*\n'
        rf'(?:[ \t]*DEFB[^\n]*\n)+',
        re.MULTILINE
    )
    m = pattern.search(content)
    if not m:
        print(f'  ERROR: no encontrado {label} en sprite_data.asm', file=sys.stderr)
        sys.exit(1)
    return content[:m.start()] + new_block + '\n' + content[m.end():]


def main():
    ase = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ASE
    if not os.path.exists(ase):
        print(f'No existe: {ase}', file=sys.stderr)
        sys.exit(1)

    print(f'Importando PLAYER RUN E/W desde {ase}\n')
    sheet_png, sheet_json = export_aseprite(ase)
    img = Image.open(sheet_png).convert('RGBA')
    meta = json.load(open(sheet_json))
    frames = meta['frames']
    tags   = {t['name']: t for t in meta.get('meta', {}).get('frameTags', [])}

    # Resolver cada TARGET: tag -> frame_index_base, offset -> frame final.
    blocks = []
    for label, tag_name, offset in TARGETS:
        if tag_name not in tags:
            print(f'  ERROR: tag "{tag_name}" no encontrado en {ase}', file=sys.stderr)
            sys.exit(1)
        base = tags[tag_name]['from']
        idx  = base + offset
        if idx >= len(frames):
            print(f'  ERROR: frame {idx} fuera de rango (total {len(frames)})',
                  file=sys.stderr)
            sys.exit(1)
        blocks.append((label, frame_to_defb(img, frames[idx], label)))
        print(f'  {label} <- frame {idx} (tag "{tag_name}" offset {offset})')

    content = open(SPRITE_DATA, encoding='utf-8').read()
    for label, block in blocks:
        content = replace_block(content, label, block)
    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'\n  Updated: {SPRITE_DATA}')
    print(f'  PLAYER RUN E/W -> 6 sprites replaced')


if __name__ == '__main__':
    main()
