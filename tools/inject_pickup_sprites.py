"""
Inject sprite data for ids 13, 28, 29, 210, 254, 255 (life / rayo / caracol /
random_pickup / health / stamina) into bg_gfx.asm if missing. Los labels son
referenciados desde code/screen_system.asm + code/random_pickups.asm (ptr-switch
del random pickup). El Export ASM del editor regenera bg_gfx.asm wholesale
(con CODE_REF_IDS ya incluyendo estos ids) → script no-op tras eso.

Para ids que aun no existen en bg_sprites.json (rayo / caracol antes de que el
usuario los dibuje), se inyecta un placeholder con pixels de random_pickup
y attrs distintivos: amarillo para rayo, verde para caracol. Permite build
verde antes de que se dibujen los sprites reales.

Idempotent: si los labels ya existen, exit 0 sin cambios.
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
    28:  'BgGfx_pickup_ray',
    29:  'BgGfx_pickup_snail',
    33:  'BgGfx_pickup_mushroom',
    34:  'BgGfx_pickup_compass',
    37:  'BgGfx_compass_lasting',     # compass permanente (M8: tras cheque, ALT2 church_key)
    44:  'BgGfx_BankCheck',           # cheque dropped por church cutscene (bank_cutscene)
    210: 'BgGfx_random_pickup',
    254: 'BgGfx_health_pickup',
    255: 'BgGfx_stamina_pickup',
}

# Placeholder para ids que el usuario aun no dibujo en el BG editor.
# Pixels: copia del random_pickup ("?") · attrs: distintivos por tipo.
PLACEHOLDER_PIXELS = [
    3, 192, 12, 48, 16, 8, 35, 196,  71, 226, 76, 114, 128, 49, 128, 97,
    128, 193, 129, 129, 65, 130, 64, 2, 33, 132, 17, 136, 12, 48, 3, 192,
]
PLACEHOLDERS = {
    28: ('rayo',     [0x46, 0x46, 0x46, 0x46]),  # yellow  bright
    29: ('caracol',  [0x44, 0x44, 0x44, 0x44]),  # green   bright
    33: ('mushroom', [0x43, 0x43, 0x43, 0x43]),  # magenta bright
    34: ('compass',  [0x46, 0x46, 0x46, 0x46]),  # yellow  bright (placeholder mismo color)
    37: ('compass_lasting', [0x45, 0x45, 0x45, 0x45]),  # cyan bright (distinguir del 34)
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

    # Detectar missing DESPUES de strippear cualquier bloque SENTINEL existente.
    # Si lo hicieramos antes, los labels ya inyectados en el SENTINEL block se
    # detectarian como "presentes" → al re-emitir el bloque limpio los
    # perderiamos (bug observado: re-correr tras anadir un TARGET nuevo
    # eliminaba los anteriores). Re-detectar despues del strip garantiza
    # que el bloque emitido contenga TODOS los TARGETS aun necesarios.
    if SENTINEL in txt:
        txt_clean = txt.split(SENTINEL)[0]
    else:
        txt_clean = txt
    missing = {sid: lbl for sid, lbl in TARGETS.items() if f'\n{lbl}:' not in '\n'+txt_clean}
    if not missing:
        print('All target labels already present in bg_gfx.asm. No changes.')
        return 0

    # Para ids missing que no estan en bg_sprites.json: usar placeholder si
    # esta definido, sino error.
    for sid, lbl in missing.items():
        if sid in sprites:
            continue
        if sid in PLACEHOLDERS:
            name, attrs = PLACEHOLDERS[sid]
            sprites[sid] = {
                'id': sid, 'w': 16, 'h': 16, 'name': name + ' (placeholder)',
                'pixelBytes': PLACEHOLDER_PIXELS, 'attrBytes': attrs,
            }
        else:
            print(f'ERROR: sprite id {sid} not found in bg_sprites.json (no placeholder)')
            return 1

    out_blocks = '\n' + SENTINEL + '\n\n'
    out_blocks += '\n'.join(emit_sprite(sprites[sid], lbl) for sid, lbl in missing.items())
    out_blocks += '\n; --- END INJECTED ---\n'

    # Reemplazar el SENTINEL block previo (si existia) por el nuevo bloque
    # completo. txt_clean ya tiene todo lo de antes del SENTINEL marker.
    txt = txt_clean.rstrip() + '\n' + out_blocks

    BG_GFX.write_text(txt, encoding='utf-8')
    print(f'Injected {len(missing)} pickup sprite(s) into bg_gfx.asm: {", ".join(missing.values())}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
