#!/usr/bin/env python3
"""
import_puff.py - Import the PUFF death animation from Aseprite into sprite_data.asm

Usage:
    python tools/import_puff.py [file.aseprite]

Default file: References/pufsheet-0x0-152x24-0x0-144x24.aseprite

Expects 6 sequential frames (24x24 each) in row order. Maps to
SprPuff0..SprPuff5 in code/sprite_data.asm (replaces the 6 DEFB blocks).

Output format (matches sprite_data.asm convention - bytes NOT CPL'd):
    SprPuffN:       ; Frame N: <descripcion>
        DEFB 3, 24
        DEFB %........, %........, %........
        ... (24 lines)
"""

import sys, os, re, json, subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASEPRITE    = r"C:\Program Files\Aseprite\aseprite.exe"
SPRITE_DATA = os.path.join(ROOT, 'code', 'sprite_data.asm')
EXPORT_DIR  = os.path.join(ROOT, 'References', 'export')
DEFAULT_ASE = os.path.join(ROOT, 'References',
                           'pufsheet-0x0-152x24-0x0-144x24.aseprite')

NUM_FRAMES = 6
FRAME_W    = 24
FRAME_H    = 24

LABELS = [f'SprPuff{i}' for i in range(NUM_FRAMES)]
COMMENTS = [
    'Frame 0',
    'Frame 1',
    'Frame 2',
    'Frame 3',
    'Frame 4',
    'Frame 5',
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


def frame_to_defb(img, frame_info, label, comment):
    fx, fy = frame_info['frame']['x'], frame_info['frame']['y']
    fw, fh = frame_info['frame']['w'], frame_info['frame']['h']
    if fw != FRAME_W or fh != FRAME_H:
        print(f'  ERROR: frame {label} is {fw}x{fh}, expected '
              f'{FRAME_W}x{FRAME_H}', file=sys.stderr)
        sys.exit(1)
    wb = fw // 8

    # Pixel "on" rule: bright pixel on a dark background.
    # The puff art uses near-black bg with anti-aliasing artifacts (1,1,1),
    # (2,2,2). A brightness threshold cleanly separates bg from sprite.
    BRIGHT_THRESHOLD = 128
    lines = [f'{label}:       ; {comment}',
             f'    DEFB {wb}, {fh}']
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
    # Match "<label>:" on its own (optional trailing comment), then
    # header DEFB + N pixel DEFB lines (greedy until next non-DEFB line).
    pattern = re.compile(
        rf'^{re.escape(label)}:[^\n]*\n'
        rf'(?:[ \t]*DEFB[^\n]*\n)+',
        re.MULTILINE
    )
    m = pattern.search(content)
    if not m:
        print(f'  ERROR: could not find {label} in sprite_data.asm',
              file=sys.stderr)
        sys.exit(1)
    return content[:m.start()] + new_block + '\n' + content[m.end():]


def main():
    ase = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ASE
    if not os.path.exists(ase):
        print(f'File not found: {ase}', file=sys.stderr)
        sys.exit(1)

    print(f'Importing PUFF from {ase}\n')
    sheet_png, sheet_json = export_aseprite(ase)
    # Force RGBA: paletted PNGs (mode 'P') return an index from getpixel
    # instead of RGB tuples, which breaks the brightness threshold.
    img = Image.open(sheet_png).convert('RGBA')
    meta = json.load(open(sheet_json))

    frames = meta['frames']

    # Two layouts supported:
    #   A) Aseprite has N independent frames (animation timeline)
    #   B) Aseprite has 1 frame containing a horizontal strip with all
    #      sprites (sheet authored as static layers/canvas)
    if len(frames) >= NUM_FRAMES:
        # Layout A: take the first NUM_FRAMES frames as-is.
        if len(frames) > NUM_FRAMES:
            print(f'  WARNING: aseprite has {len(frames)} frames, using '
                  f'first {NUM_FRAMES}')
        fw, fh = frames[0]['frame']['w'], frames[0]['frame']['h']
        print(f'  Frame size: {fw}x{fh}')
        print(f'  Total frames: {len(frames)} (using 0..{NUM_FRAMES-1})')
        synthesized = frames[:NUM_FRAMES]
    elif len(frames) == 1:
        # Layout B: split the lone frame as a horizontal strip.
        f0 = frames[0]['frame']
        fw, fh = f0['w'], f0['h']
        if fh != FRAME_H:
            print(f'  ERROR: strip height is {fh}, expected {FRAME_H}',
                  file=sys.stderr)
            sys.exit(1)
        if fw < FRAME_W * NUM_FRAMES:
            print(f'  ERROR: strip width {fw} too small for {NUM_FRAMES} '
                  f'frames of {FRAME_W}px ({FRAME_W * NUM_FRAMES} required)',
                  file=sys.stderr)
            sys.exit(1)
        if fw > FRAME_W * NUM_FRAMES:
            print(f'  INFO: strip width {fw} > {FRAME_W * NUM_FRAMES}, '
                  f'using leftmost {NUM_FRAMES} frames')
        print(f'  Strip detected: {fw}x{fh} -> slicing into {NUM_FRAMES} '
              f'frames of {FRAME_W}x{FRAME_H}')
        synthesized = []
        for i in range(NUM_FRAMES):
            synthesized.append({'frame': {
                'x': f0['x'] + i * FRAME_W,
                'y': f0['y'],
                'w': FRAME_W,
                'h': FRAME_H,
            }})
        fw, fh = FRAME_W, FRAME_H
    else:
        print(f'  ERROR: aseprite has {len(frames)} frames; need either '
              f'{NUM_FRAMES} timeline frames or 1 strip frame',
              file=sys.stderr)
        sys.exit(1)

    blocks = [frame_to_defb(img, synthesized[i], LABELS[i], COMMENTS[i])
              for i in range(NUM_FRAMES)]

    content = open(SPRITE_DATA, encoding='utf-8').read()
    for label, block in zip(LABELS, blocks):
        content = replace_block(content, label, block)

    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'\n  Updated: {SPRITE_DATA}')
    print(f'  PUFF -> {fw}x{fh}, {NUM_FRAMES} frames replaced')


if __name__ == '__main__':
    main()
