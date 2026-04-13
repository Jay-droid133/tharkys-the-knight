#!/usr/bin/env python3
"""
Export HUD clock sprites (44, 45) from bg_sprites.json to ASM include file.
Run before sjasmplus assembly so the JSON is always the source of truth.
"""
import json, os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
JSON_PATH  = os.path.join(SCRIPT_DIR, '..', 'code', 'bg_sprites.json')
OUT_PATH   = os.path.join(SCRIPT_DIR, '..', 'code', 'hud_clock_sprites.inc')

SPRITES = {
    44: ('BgGfx_hud_clock',          'Hud Clock',          48, 16),
    45: ('BgGfx_hud_clock_decay', 'Hud Clock (decayed)', 48, 16),
}

def export():
    with open(JSON_PATH, 'r') as f:
        data = json.load(f)

    by_id = {sp['id']: sp for sp in data['sprites']}

    lines = ['; Auto-generated from bg_sprites.json - DO NOT EDIT',
             '; Run tools/export_hud_sprites.py to regenerate', '']

    for sid, (label, comment, expected_w, expected_h) in SPRITES.items():
        sp = by_id.get(sid)
        if sp is None:
            print(f'SKIP: sprite {sid} not in {JSON_PATH} (using existing .inc)', file=sys.stderr)
            return  # Keep existing hud_clock_sprites.inc unchanged

        if sp['w'] != expected_w or sp['h'] != expected_h:
            print(f'SKIP: sprite {sid} has dimensions {sp["w"]}x{sp["h"]}, '
                  f'expected {expected_w}x{expected_h}. Keeping existing .inc', file=sys.stderr)
            return  # Keep existing hud_clock_sprites.inc unchanged

        w_bytes = sp['w'] // 8
        h_px    = sp['h']
        pixels  = sp['pixelBytes']
        attrs   = sp.get('attrBytes', [])

        lines.append(f'{label}:    ; BG{sid:02d} - {comment} - {sp["w"]}x{h_px}px')
        lines.append(f'    DEFB {h_px}, {w_bytes}    ; height_px, width_bytes')

        # Pixel data — CPL (XOR 0xFF)
        for row in range(h_px):
            row_bytes = []
            for bx in range(w_bytes):
                raw = pixels[row * w_bytes + bx]
                row_bytes.append(f'${(raw ^ 0xFF) & 0xFF:02X}')
            lines.append(f'    DEFB {", ".join(row_bytes)}')

        # TintPaper byte (HUD sprites are not tintable)
        tp = sp.get('tintPaper', 255)
        if tp is None:
            tp = 255
        lines.append(f'    DEFB ${tp:02X}          ; tintPaper (none)')

        # Attribute data
        if attrs:
            attr_h = h_px // 8
            attr_w = w_bytes
            lines.append(f'    DEFB {attr_h}, {attr_w}    ; attr_h, attr_w')
            for row in range(attr_h):
                row_bytes = []
                for bx in range(attr_w):
                    row_bytes.append(f'${attrs[row * attr_w + bx]:02X}')
                lines.append(f'    DEFB {", ".join(row_bytes)}')

        lines.append('')

    content = '\n'.join(lines) + '\n'

    # Only write if changed (avoid unnecessary rebuilds)
    if os.path.exists(OUT_PATH):
        with open(OUT_PATH, 'r') as f:
            if f.read() == content:
                return

    with open(OUT_PATH, 'w', newline='\n') as f:
        f.write(content)
    print(f'HUD sprites exported: {OUT_PATH}')

if __name__ == '__main__':
    export()
