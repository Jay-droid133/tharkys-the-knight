#!/usr/bin/env python3
"""
Export HUD sprites (clock + decorations) from bg_sprites.json to ASM include
files. Run before sjasmplus assembly so the JSON is always the source of truth.

Outputs two files:
  code/hud_clock_sprites.inc        — ids 44, 45 (clock)
  code/hud_decoration_sprites.inc   — ids 171, 172, 178, 179 (key + compass)
"""
import json, os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
JSON_PATH  = os.path.join(SCRIPT_DIR, '..', 'code', 'bg_sprites.json')
OUT_CLOCK  = os.path.join(SCRIPT_DIR, '..', 'code', 'hud_clock_sprites.inc')
OUT_DECO   = os.path.join(SCRIPT_DIR, '..', 'code', 'hud_decoration_sprites.inc')

CLOCK_SPRITES = {
    44: ('BgGfx_hud_clock',          'Hud Clock',          48, 16),
    45: ('BgGfx_hud_clock_decay',    'Hud Clock (decayed)', 48, 16),
}

DECO_SPRITES = {
    171: ('BgGfx_hud_key_deco_izq',     'Key deco left',       8, 16),
    172: ('BgGfx_hud_key_deco_der',     'Key deco right',      8, 16),
    178: ('BgGfx_hud_compass_deco_izq', 'Compass deco left',   8, 16),
    179: ('BgGfx_hud_compass_deco_der', 'Compass deco right',  8, 16),
    # Buff icons (pickups copy) — slot 1 para evitar paging + romper deps
    # con bg_gfx (pickup_shield/sword no estan definidos hoy).
    87:  ('BgGfx_hud_buff_rayo',        'Buff icon ray',      16, 16),
    76:  ('BgGfx_hud_buff_escudo',      'Buff icon shield',   16, 16),
    78:  ('BgGfx_hud_buff_espada',      'Buff icon sword',    16, 16),
}

def emit_sprite_block(sp, label, comment, sid):
    """Build DEFB block for one sprite. Returns list of lines."""
    w_bytes = sp['w'] // 8
    h_px    = sp['h']
    pixels  = sp['pixelBytes']
    attrs   = sp.get('attrBytes', [])

    lines = []
    lines.append(f'{label}:    ; BG{sid:02d} - {comment} - {sp["w"]}x{h_px}px')
    lines.append(f'    DEFB {h_px}, {w_bytes}    ; height_px, width_bytes')

    # Pixel data — CPL (XOR 0xFF) to match DrawBgGfxSprite expectations.
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
    return lines


def export_set(out_path, sprite_set, by_id):
    lines = ['; Auto-generated from bg_sprites.json - DO NOT EDIT',
             '; Run tools/export_hud_sprites.py to regenerate', '']

    for sid, (label, comment, expected_w, expected_h) in sprite_set.items():
        sp = by_id.get(sid)
        if sp is None:
            print(f'SKIP: sprite {sid} not in {JSON_PATH} (using existing .inc)',
                  file=sys.stderr)
            return
        if sp['w'] != expected_w or sp['h'] != expected_h:
            print(f'SKIP: sprite {sid} has dimensions {sp["w"]}x{sp["h"]}, '
                  f'expected {expected_w}x{expected_h}. Keeping existing .inc',
                  file=sys.stderr)
            return
        lines.extend(emit_sprite_block(sp, label, comment, sid))

    content = '\n'.join(lines) + '\n'

    if os.path.exists(out_path):
        with open(out_path, 'r') as f:
            if f.read() == content:
                return
    with open(out_path, 'w', newline='\n') as f:
        f.write(content)
    print(f'HUD sprites exported: {out_path}')


def export():
    with open(JSON_PATH, 'r') as f:
        data = json.load(f)

    by_id = {sp['id']: sp for sp in data['sprites']}
    export_set(OUT_CLOCK, CLOCK_SPRITES, by_id)
    export_set(OUT_DECO,  DECO_SPRITES,  by_id)


if __name__ == '__main__':
    export()
