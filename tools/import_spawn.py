#!/usr/bin/env python3
"""
import_spawn.py - Import the SPAWN nasty animation from Aseprite into sprite_data.asm

Usage:
    python tools/import_spawn.py [--night] [file.aseprite]

Without --night (default):
    Day variant. Default file: References/spawn03 day 24x24.aseprite
    Replaces SprSpawn0..SprSpawn5.

With --night:
    Night variant. Default file: References/spawn03 night 24x24.aseprite
    Replaces SprSpawnNight0..SprSpawnNight5.

Expects 6 frames (24x24 each), either as 6 timeline frames or as a single
horizontal strip frame of 144x24.

Output format (matches sprite_data.asm convention - bytes NOT CPL'd):
    SprSpawn{Night}N:      ; Frame N
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

NUM_FRAMES = 6
FRAME_W    = 24
FRAME_H    = 24

# Filled by main() based on --night flag
LABELS   = []
COMMENTS = []
DEFAULT_ASE = ''


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
    # The art uses near-black bg with anti-aliasing artifacts (1,1,1),
    # (2,2,2). A brightness threshold cleanly separates bg from sprite.
    BRIGHT_THRESHOLD = 128
    lines = [f'{label}:      ; {comment}',
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
    global LABELS, COMMENTS, DEFAULT_ASE

    args = sys.argv[1:]
    night = False
    if args and args[0] == '--night':
        night = True
        args.pop(0)

    if night:
        LABELS = [f'SprSpawnNight{i}' for i in range(NUM_FRAMES)]
        DEFAULT_ASE = os.path.join(ROOT, 'References',
                                   'spawn03 night 24x24.aseprite')
    else:
        LABELS = [f'SprSpawn{i}' for i in range(NUM_FRAMES)]
        DEFAULT_ASE = os.path.join(ROOT, 'References',
                                   'spawn03 day 24x24.aseprite')
    COMMENTS = [f'Frame {i}' for i in range(NUM_FRAMES)]

    ase = args[0] if args else DEFAULT_ASE
    if not os.path.exists(ase):
        print(f'File not found: {ase}', file=sys.stderr)
        sys.exit(1)

    variant = 'SPAWN NIGHT' if night else 'SPAWN'
    print(f'Importing {variant} from {ase}\n')
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
        if len(frames) > NUM_FRAMES:
            print(f'  WARNING: aseprite has {len(frames)} frames, using '
                  f'first {NUM_FRAMES}')
        fw, fh = frames[0]['frame']['w'], frames[0]['frame']['h']
        print(f'  Frame size: {fw}x{fh}')
        print(f'  Total frames: {len(frames)} (using 0..{NUM_FRAMES-1})')
        synthesized = frames[:NUM_FRAMES]
    elif len(frames) == 1:
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
    print(f'  {variant} -> {fw}x{fh}, {NUM_FRAMES} frames replaced')


if __name__ == '__main__':
    main()
