"""
Inject sprite data for ids 13, 210, 254, 255 (life/random_pickup/health/stamina)
into bg_gfx.asm if missing. The labels are referenced from code/screen_system.asm
random pickup ptr-switch. The editor's Export ASM will regenerate bg_gfx.asm
wholesale (with CODE_REF_IDS already including these), making this script a
no-op. Run before build until the user has re-exported once.

Idempotent: if the labels already exist, exits 0 without changes.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG_GFX = ROOT / 'code' / 'bg_gfx.asm'
BG_JSON = ROOT / 'code' / 'bg_sprites.json'

# Sprites a inyectar: id -> label (debe coincidir con generate_label del editor)
TARGETS = {
    13:  'BgGfx_life',
    210: 'BgGfx_random_pickup',
    254: 'BgGfx_health_pickup',
    255: 'BgGfx_stamina_pickup',
}

SENTINEL = '; --- INJECTED PICKUP SPRITES (will be replaced by editor Export ASM) ---'


def fmt_defb_line(values):
    return '    DEFB ' + ', '.join(f'${v:02X}' for v in values)


def emit_sprite(sp, label):
    pixels = sp['pixelBytes']
    attrs  = sp['attrBytes']
    w, h   = sp['w'], sp['h']
    width_bytes = w // 8
    attr_w = (w + 7) // 8
    attr_h = (h + 7) // 8
    cpl = [b ^ 0xFF for b in pixels]
    lines = []
    lines.append(f'{label}:    ; INJECTED · id={sp["id"]} · {sp.get("name","?")} · {w}x{h}px')
    lines.append(f'    DEFB {h}, {width_bytes}    ; height_px, width_bytes')
    # 16 bytes per line for pixel data
    for i in range(0, len(cpl), 16):
        lines.append(fmt_defb_line(cpl[i:i+16]))
    lines.append('    DEFB 255    ; tintPaper (255=none)')
    lines.append(f'    DEFB {attr_h}, {attr_w}    ; attr_h, attr_w')
    for i in range(0, len(attrs), 16):
        lines.append(fmt_defb_line(attrs[i:i+16]))
    return '\n'.join(lines) + '\n'


def main():
    txt = BG_GFX.read_text(encoding='utf-8')
    sprites = {s['id']: s for s in json.loads(BG_JSON.read_text(encoding='utf-8'))['sprites']} \
        if False else None
    # bg_sprites.json es un dict-like JSON con sprites como entries; let me parse
    raw = json.loads(BG_JSON.read_text(encoding='utf-8'))
    if isinstance(raw, list):
        sprites = {s['id']: s for s in raw}
    else:
        sprites = {s['id']: s for s in raw.get('sprites', raw.get('bgSprites', []))}
        if not sprites and isinstance(raw, dict):
            # entries directly indexed by id (string keys)
            for k, v in raw.items():
                if isinstance(v, dict) and 'pixelBytes' in v and 'id' in v:
                    sprites[v['id']] = v

    missing = {sid: lbl for sid, lbl in TARGETS.items() if f'\n{lbl}:' not in '\n'+txt}
    if not missing:
        print('All target labels already present in bg_gfx.asm. No changes.')
        return 0

    for sid, lbl in missing.items():
        if sid not in sprites:
            print(f'ERROR: sprite id {sid} not found in bg_sprites.json')
            return 1

    out_blocks = '\n' + SENTINEL + '\n\n'
    out_blocks += '\n'.join(emit_sprite(sprites[sid], lbl) for sid, lbl in missing.items())
    out_blocks += '\n; --- END INJECTED ---\n'

    if SENTINEL in txt:
        # Replace from SENTINEL to end of file
        txt = txt.split(SENTINEL)[0].rstrip() + '\n' + out_blocks
    else:
        if not txt.endswith('\n'):
            txt += '\n'
        txt += out_blocks

    BG_GFX.write_text(txt, encoding='utf-8')
    print(f'Injected {len(missing)} pickup sprite(s) into bg_gfx.asm: {", ".join(missing.values())}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
