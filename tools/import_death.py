#!/usr/bin/env python3
"""
import_death.py - Import the Death sprite from Aseprite into sprite_data.asm

Usage:
    python tools/import_death.py [file.aseprite]

Default file: References/death01-376x192-24x24.aseprite

Expects 4 frames (24x24) in positional order:
    Frame 0 = Right pose 0
    Frame 1 = Right pose 1
    Frame 2 = Left pose 0
    Frame 3 = Left pose 1

Or 2 frames (Right only) - mirrored automatically as Left.

Or Aseprite tags (case-insensitive):
    "right" / "east" (1-2 frames) + "left" / "west" (1-2 frames)

Replaces SprDeath_0/1/L0/L1 blocks in code/sprite_data.asm.
"""

import sys, os, re, json, subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASEPRITE    = r"C:\Program Files\Aseprite\aseprite.exe"
SPRITE_DATA = os.path.join(ROOT, 'code', 'sprite_data.asm')
EXPORT_DIR  = os.path.join(ROOT, 'References', 'export')
DEFAULT_ASE = os.path.join(ROOT, 'References', 'death01-376x192-24x24.aseprite')


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


def get_frame_order(meta):
    tags = meta['meta'].get('frameTags', [])
    num_frames = len(meta['frames'])

    right_frames, left_frames = [], []
    for tag in tags:
        n = tag['name'].lower().strip()
        idx = list(range(tag['from'], tag['to'] + 1))
        if 'right' in n or 'east' in n:
            right_frames = idx
        elif 'left' in n or 'west' in n:
            left_frames = idx

    if right_frames:
        r = right_frames[:2]
        while len(r) < 2: r.append(r[-1])
        if left_frames:
            l = left_frames[:2]
            while len(l) < 2: l.append(l[-1])
        else:
            l = r[:]
            print('  WARNING: no left tag, mirroring right')
        return r + l

    # Positional
    if num_frames >= 4:
        return [0, 1, 2, 3]
    if num_frames == 2:
        print('  WARNING: only 2 frames, duplicating as left')
        return [0, 1, 0, 1]
    if num_frames == 1:
        print('  WARNING: only 1 frame, all four poses identical')
        return [0, 0, 0, 0]
    print(f'  ERROR: unexpected frame count {num_frames}', file=sys.stderr)
    sys.exit(1)


def frame_to_defb(img, frame_info, label, comment):
    fx, fy = frame_info['frame']['x'], frame_info['frame']['y']
    fw, fh = frame_info['frame']['w'], frame_info['frame']['h']
    wb = fw // 8

    lines = [f'; --- {comment} ---', f'{label}:', f'    DEFB {wb}, {fh}']
    for y in range(fh):
        row = []
        for b in range(wb):
            byte = 0
            for bit in range(8):
                px = img.getpixel((fx + b * 8 + bit, fy + y))
                # Paletted: index 0 = empty. Other modes: any non-zero pixel = on.
                if isinstance(px, tuple):
                    on = any(c > 0 for c in px[:3]) and (len(px) < 4 or px[3] > 128)
                else:
                    on = px != 0
                if on:
                    byte |= (1 << (7 - bit))
            row.append(f'%{byte:08b}')
        lines.append(f'    DEFB {", ".join(row)}')
    return '\n'.join(lines)


def replace_block(content, label, new_block):
    pattern = re.compile(
        rf'^; --- Death frame.*?\n'
        rf'{re.escape(label)}:\n'
        rf'(?:    DEFB .*\n)+',
        re.MULTILINE
    )
    m = pattern.search(content)
    if not m:
        print(f'  ERROR: could not find {label} in sprite_data.asm', file=sys.stderr)
        sys.exit(1)
    return content[:m.start()] + new_block + '\n' + content[m.end():]


def main():
    ase = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ASE
    if not os.path.exists(ase):
        print(f'File not found: {ase}', file=sys.stderr)
        sys.exit(1)

    print(f'Importing Death from {ase}\n')
    sheet_png, sheet_json = export_aseprite(ase)
    img = Image.open(sheet_png)
    meta = json.load(open(sheet_json))

    order = get_frame_order(meta)
    frames = meta['frames']
    fw, fh = frames[0]['frame']['w'], frames[0]['frame']['h']
    print(f'  Frame size: {fw}x{fh}')
    print(f'  Frame order (R0,R1,L0,L1): {order}')

    labels   = ['SprDeath_0', 'SprDeath_1', 'SprDeath_L0', 'SprDeath_L1']
    comments = ['Death frame 0 Right', 'Death frame 1 Right',
                'Death frame 0 Left',  'Death frame 1 Left']

    blocks = [frame_to_defb(img, frames[order[i]], labels[i], comments[i])
              for i in range(4)]

    content = open(SPRITE_DATA, encoding='utf-8').read()
    for label, block in zip(labels, blocks):
        content = replace_block(content, label, block)

    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'\n  Updated: {SPRITE_DATA}')
    print(f'  Death -> {fw}x{fh}, 4 frames replaced')


if __name__ == '__main__':
    main()
