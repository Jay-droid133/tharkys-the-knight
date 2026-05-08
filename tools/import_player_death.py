#!/usr/bin/env python3
"""
import_player_death.py - Importa la anim de muerte del player desde un .aseprite

Default: References/player death 02-32x16.aseprite (strip 96x16 = 6 frames 16x16)
         Layout del .aseprite: 3 frames LEFT-facing (0..2) + 3 frames RIGHT-facing (3..5).
         El codigo asume el orden inverso (R primero, L despues), asi que el
         script REORDENA al exportar: aseprite[3..5] -> SprPlayerDeath0..2 (right),
         aseprite[0..2] -> SprPlayerDeath3..5 (left).

Reemplaza los bloques DEFB de SprPlayerDeath0..5 en sprite_data.asm.

Formato de salida (sprite_data.asm convention - bytes NO CPL'd):
    SprPlayerDeath{N}:
        DEFB 2, 16
        DEFB %........, %........
        ... (16 lineas)
"""

import sys, os, re, json, subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASEPRITE    = r"C:\Program Files\Aseprite\aseprite.exe"
SPRITE_DATA = os.path.join(ROOT, 'code', 'sprite_data.asm')
EXPORT_DIR  = os.path.join(ROOT, 'References', 'export')
DEFAULT_ASE = os.path.join(ROOT, 'References',
                           'player death 02-32x16.aseprite')

NUM_FRAMES = 6
FRAME_W    = 16
FRAME_H    = 16
LABELS = [f'SprPlayerDeath{i}' for i in range(NUM_FRAMES)]


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

    print(f'Importando PLAYER DEATH desde {ase}\n')
    sheet_png, sheet_json = export_aseprite(ase)
    img = Image.open(sheet_png).convert('RGBA')
    meta = json.load(open(sheet_json))
    frames = meta['frames']

    if len(frames) >= NUM_FRAMES:
        if len(frames) > NUM_FRAMES:
            print(f'  WARNING: {len(frames)} frames, uso los primeros {NUM_FRAMES}')
        synthesized = frames[:NUM_FRAMES]
        fw, fh = frames[0]['frame']['w'], frames[0]['frame']['h']
        print(f'  Frame size: {fw}x{fh}')
    elif len(frames) == 1:
        f0 = frames[0]['frame']
        fw, fh = f0['w'], f0['h']
        if fh != FRAME_H or fw < FRAME_W * NUM_FRAMES:
            print(f'  ERROR: strip {fw}x{fh}, esperado >={FRAME_W * NUM_FRAMES}x{FRAME_H}',
                  file=sys.stderr)
            sys.exit(1)
        print(f'  Strip detectado: {fw}x{fh} -> {NUM_FRAMES} frames de {FRAME_W}x{FRAME_H}')
        synthesized = [
            {'frame': {'x': f0['x'] + i * FRAME_W, 'y': f0['y'],
                       'w': FRAME_W, 'h': FRAME_H}}
            for i in range(NUM_FRAMES)
        ]
        fw, fh = FRAME_W, FRAME_H
    else:
        print(f'  ERROR: aseprite tiene {len(frames)} frames; necesito >= {NUM_FRAMES}',
              file=sys.stderr)
        sys.exit(1)

    # El aseprite trae los frames en orden L-L-L-R-R-R; el codigo necesita
    # SprPlayerDeath0..2 = RIGHT, SprPlayerDeath3..5 = LEFT. Reordenamos.
    REMAP = [3, 4, 5, 0, 1, 2]
    blocks = [frame_to_defb(img, synthesized[REMAP[i]], LABELS[i]) for i in range(NUM_FRAMES)]
    content = open(SPRITE_DATA, encoding='utf-8').read()
    for label, block in zip(LABELS, blocks):
        content = replace_block(content, label, block)
    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'\n  Updated: {SPRITE_DATA}')
    print(f'  PLAYER DEATH -> {fw}x{fh}, {NUM_FRAMES} frames replaced')


if __name__ == '__main__':
    main()
