#!/usr/bin/env python3
"""
import_nasty.py - Import enemy sprites from Aseprite into sprite_data.asm

Usage:
    python tools/import_nasty.py <file.aseprite> --enemy <0-7>

Expects 4 frames in the Aseprite file:
    Frame 0 = Right pose 0
    Frame 1 = Right pose 1
    Frame 2 = Left pose 0
    Frame 3 = Left pose 1

Or use Aseprite tags (optional, case-insensitive):
    "right" (2 frames)  +  "left" (2 frames)

Replaces the corresponding SprEnemyN blocks in sprite_data.asm and
updates the header comment with the new dimensions.
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

ENEMY_NAMES = {
    0: 'Spider', 1: 'Scorpion', 2: 'Bat', 3: 'Snake',
    4: 'Eagle', 5: 'Rat', 6: 'Goat', 7: 'RabidCat',
}

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
# Frame extraction
# ---------------------------------------------------------------------------
def get_frame_order(meta, enemy_name=''):
    """Return list of frame indices as [R0, R1, L0, L1] using tags or positional."""
    tags = meta['meta'].get('frameTags', [])
    num_frames = len(meta['frames'])
    filter_name = enemy_name.lower()

    # Try tags first
    right_frames = []
    left_frames = []
    for tag in tags:
        name = tag['name'].lower().strip()
        # If multi-enemy file, only match tags containing the enemy name
        if filter_name and filter_name not in name:
            continue
        indices = list(range(tag['from'], tag['to'] + 1))
        if 'right' in name or 'east' in name:
            right_frames = indices
        elif 'left' in name or 'west' in name:
            left_frames = indices

    if right_frames and left_frames:
        r = right_frames[:2]
        l = left_frames[:2]
        # Pad to 2 if only 1 frame
        while len(r) < 2: r.append(r[-1])
        while len(l) < 2: l.append(l[-1])
        return r + l

    # Positional: expect 4 frames = R0, R1, L0, L1
    if num_frames >= 4:
        return [0, 1, 2, 3]
    elif num_frames == 2:
        # 2 frames = R0, R1 (mirror left manually? just duplicate)
        print('  WARNING: only 2 frames, using same for left (no mirror)')
        return [0, 1, 0, 1]
    else:
        print(f'  ERROR: expected 2 or 4 frames, got {num_frames}', file=sys.stderr)
        sys.exit(1)

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
def replace_enemy_block(content, enemy_num, defb_blocks, name, w, h):
    """Replace 4 frame blocks for enemy_num in sprite_data.asm."""
    labels = [
        f'SprEnemy{enemy_num}_0',
        f'SprEnemy{enemy_num}_1',
        f'SprEnemy{enemy_num}_L0',
        f'SprEnemy{enemy_num}_L1',
    ]

    for i, label in enumerate(labels):
        # Match from comment line before label to end of DEFB block
        pattern = re.compile(
            rf'^; --- {re.escape(name)} frame.*?\n'
            rf'{re.escape(label)}:\n'
            rf'(?:    DEFB .*\n)+',
            re.MULTILINE
        )
        m = pattern.search(content)
        if m:
            content = content[:m.start()] + defb_blocks[i] + '\n' + content[m.end():]
        else:
            # Try without specific name in comment (just match the label)
            pattern2 = re.compile(
                rf'^; --- .*frame.*\n'
                rf'{re.escape(label)}:\n'
                rf'(?:    DEFB .*\n)+',
                re.MULTILINE
            )
            m2 = pattern2.search(content)
            if m2:
                content = content[:m2.start()] + defb_blocks[i] + '\n' + content[m2.end():]
            else:
                print(f'  ERROR: could not find {label} in sprite_data.asm', file=sys.stderr)
                sys.exit(1)

    # Update header comment with new dimensions
    old_header = re.compile(
        rf'(; SpriteID \d+-\d+: Enemy {enemy_num} - {re.escape(name)}\s+)\(.*?\)'
    )
    content = old_header.sub(rf'\g<1>({w}x{h})', content)

    # Remove "(placeholder)" from SPRID EQU line if present
    content = re.sub(
        rf'(SPRID_ENEMY_{enemy_num}\s+EQU\s+\d+)\s*;.*(?i:placeholder).*',
        rf'\1',
        content
    )

    return content

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='Import enemy sprite from Aseprite')
    parser.add_argument('aseprite', help='Path to .aseprite file')
    parser.add_argument('--enemy', type=int, required=True, choices=range(8),
                        help='Enemy number (0-7)')
    args = parser.parse_args()

    if not os.path.exists(args.aseprite):
        print(f'File not found: {args.aseprite}', file=sys.stderr)
        sys.exit(1)

    enemy = args.enemy
    name = ENEMY_NAMES[enemy]
    print(f'Importing {name} (Enemy {enemy}) from {args.aseprite}\n')

    # Export
    sheet_png, sheet_json = export_aseprite(args.aseprite)
    img = Image.open(sheet_png)
    meta = json.load(open(sheet_json))

    # Frame order
    order = get_frame_order(meta, name)
    frames = meta['frames']

    fw = frames[0]['frame']['w']
    fh = frames[0]['frame']['h']
    print(f'  Frame size: {fw}x{fh}')
    print(f'  Frame order: R0={order[0]}, R1={order[1]}, L0={order[2]}, L1={order[3]}')

    # Generate DEFB blocks
    labels = [f'SprEnemy{enemy}_0', f'SprEnemy{enemy}_1',
              f'SprEnemy{enemy}_L0', f'SprEnemy{enemy}_L1']
    comments = [f'{name} frame 0 Right', f'{name} frame 1 Right',
                f'{name} frame 0 Left', f'{name} frame 1 Left']

    defb_blocks = []
    for i in range(4):
        block = frame_to_defb(img, frames[order[i]], labels[i], comments[i])
        defb_blocks.append(block)

    # Replace in ASM
    content = open(SPRITE_DATA, encoding='utf-8').read()
    content = replace_enemy_block(content, enemy, defb_blocks, name, fw, fh)

    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f'\n  Updated: {SPRITE_DATA}')
    print(f'  {name} -> {fw}x{fh}, 4 frames replaced')

if __name__ == '__main__':
    main()
