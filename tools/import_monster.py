#!/usr/bin/env python3
"""
import_monster.py - Import monster sprites from Aseprite into sprite_data.asm

Usage:
    python tools/import_monster.py <file.aseprite> --monster <0-2>

Expects 6 frames in the Aseprite file (16x21 each):
    Frame 0 = Right pose 0
    Frame 1 = Right pose 1
    Frame 2 = Right pose 2
    Frame 3 = Left pose 0
    Frame 4 = Left pose 1
    Frame 5 = Left pose 2

Or use Aseprite tags (optional, case-insensitive):
    "right" (3 frames)  +  "left" (3 frames)

Replaces the corresponding SprMonsterN blocks in sprite_data.asm.
"""

import sys, os, re, json, subprocess, argparse
from PIL import Image

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ASEPRITE    = r"C:\Program Files\Aseprite\aseprite.exe"
SPRITE_DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '..', 'code', 'sprite_data.asm')
EXPORT_DIR  = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '..', 'References', 'export')

EXPECTED_WIDTH  = 16
EXPECTED_HEIGHT = 21
FRAMES_PER_DIR  = 3

# ---------------------------------------------------------------------------
# Aseprite export
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Frame order
# ---------------------------------------------------------------------------
def get_frame_order(meta):
    """Return [R0, R1, R2, L0, L1, L2] using tags or positional."""
    tags = meta['meta'].get('frameTags', [])
    num_frames = len(meta['frames'])

    right_frames = []
    left_frames = []
    for tag in tags:
        name = tag['name'].lower().strip()
        indices = list(range(tag['from'], tag['to'] + 1))
        if 'right' in name or 'east' in name:
            right_frames = indices
        elif 'left' in name or 'west' in name:
            left_frames = indices

    if right_frames and left_frames:
        r = right_frames[:3]
        l = left_frames[:3]
        while len(r) < 3: r.append(r[-1])
        while len(l) < 3: l.append(l[-1])
        return r + l

    # Positional: expect 6 frames = R0, R1, R2, L0, L1, L2
    if num_frames >= 6:
        return [0, 1, 2, 3, 4, 5]
    elif num_frames == 3:
        print('  WARNING: only 3 frames, using same for left (no mirror)')
        return [0, 1, 2, 0, 1, 2]
    else:
        print(f'  ERROR: expected 3 or 6 frames, got {num_frames}', file=sys.stderr)
        sys.exit(1)

# ---------------------------------------------------------------------------
# Frame to DEFB
# ---------------------------------------------------------------------------
def frame_to_defb(img, frame_info, label, comment):
    """Convert a single frame to ASM DEFB text."""
    fx = frame_info['frame']['x']
    fy = frame_info['frame']['y']
    fw = frame_info['frame']['w']
    fh = frame_info['frame']['h']
    wb = fw // 8

    lines = [f'; --- {comment} ---', f'{label}:', f'    DEFB {wb}, {fh}']
    for y in range(fh):
        row = []
        for b in range(wb):
            byte = 0
            for bit in range(8):
                px = img.getpixel((fx + b * 8 + bit, fy + y))
                if px != 0:
                    byte |= (1 << (7 - bit))
            row.append(f'%{byte:08b}')
        lines.append(f'    DEFB {", ".join(row)}')
    return '\n'.join(lines)

# ---------------------------------------------------------------------------
# ASM replacement
# ---------------------------------------------------------------------------
def replace_monster_block(content, monster_num, defb_blocks, w, h):
    """Replace 6 frame blocks for monster_num in sprite_data.asm."""
    labels = [
        f'SprMonster{monster_num}_0',
        f'SprMonster{monster_num}_1',
        f'SprMonster{monster_num}_2',
        f'SprMonster{monster_num}_L0',
        f'SprMonster{monster_num}_L1',
        f'SprMonster{monster_num}_L2',
    ]
    comments = [
        f'Monster {monster_num} frame 0 Right',
        f'Monster {monster_num} frame 1 Right',
        f'Monster {monster_num} frame 2 Right',
        f'Monster {monster_num} frame 0 Left',
        f'Monster {monster_num} frame 1 Left',
        f'Monster {monster_num} frame 2 Left',
    ]

    for i, label in enumerate(labels):
        pattern = re.compile(
            rf'^; --- Monster {monster_num} frame.*?\n'
            rf'{re.escape(label)}:\n'
            rf'(?:    DEFB .*\n)+',
            re.MULTILINE
        )
        m = pattern.search(content)
        if m:
            content = content[:m.start()] + defb_blocks[i] + '\n' + content[m.end():]
        else:
            print(f'  ERROR: could not find {label} in sprite_data.asm', file=sys.stderr)
            sys.exit(1)

    # Update header comment with new dimensions
    old_header = re.compile(
        rf'(; SpriteID \d+-\d+: Monster {monster_num}\s+)\(.*?\)'
    )
    content = old_header.sub(rf'\g<1>({w}x{h})', content)

    return content

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='Import monster sprite from Aseprite')
    parser.add_argument('aseprite', help='Path to .aseprite file')
    parser.add_argument('--monster', type=int, required=True, choices=range(3),
                        help='Monster number (0-2)')
    args = parser.parse_args()

    if not os.path.exists(args.aseprite):
        print(f'File not found: {args.aseprite}', file=sys.stderr)
        sys.exit(1)

    monster = args.monster
    print(f'Importing Monster {monster} from {args.aseprite}\n')

    # Export
    sheet_png, sheet_json = export_aseprite(args.aseprite)
    img = Image.open(sheet_png)
    meta = json.load(open(sheet_json))

    # Frame order
    order = get_frame_order(meta)
    frames = meta['frames']

    fw = frames[0]['frame']['w']
    fh = frames[0]['frame']['h']
    print(f'  Frame size: {fw}x{fh}')
    print(f'  Frame order: R0={order[0]}, R1={order[1]}, R2={order[2]}, '
          f'L0={order[3]}, L1={order[4]}, L2={order[5]}')

    if fw != EXPECTED_WIDTH or fh != EXPECTED_HEIGHT:
        print(f'  WARNING: expected {EXPECTED_WIDTH}x{EXPECTED_HEIGHT}, '
              f'got {fw}x{fh}')

    # Generate DEFB blocks
    labels = [
        f'SprMonster{monster}_0', f'SprMonster{monster}_1', f'SprMonster{monster}_2',
        f'SprMonster{monster}_L0', f'SprMonster{monster}_L1', f'SprMonster{monster}_L2',
    ]
    comments = [
        f'Monster {monster} frame 0 Right', f'Monster {monster} frame 1 Right',
        f'Monster {monster} frame 2 Right',
        f'Monster {monster} frame 0 Left', f'Monster {monster} frame 1 Left',
        f'Monster {monster} frame 2 Left',
    ]

    defb_blocks = []
    for i in range(6):
        block = frame_to_defb(img, frames[order[i]], labels[i], comments[i])
        defb_blocks.append(block)

    # Replace in ASM
    content = open(SPRITE_DATA, encoding='utf-8').read()
    content = replace_monster_block(content, monster, defb_blocks, fw, fh)

    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'\n  Updated: {SPRITE_DATA}')
    print(f'  Monster {monster} -> {fw}x{fh}, 6 frames replaced (3R + 3L)')

if __name__ == '__main__':
    main()
