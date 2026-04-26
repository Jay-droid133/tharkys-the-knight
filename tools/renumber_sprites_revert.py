#!/usr/bin/env python3
"""
renumber_sprites_revert.py - Revierte el renumber a IDs 200-208 originales.

El renumber inicial movio sprites manuales de 200-208 a IDs libres en 1-199
(13, 33-40). Ese cambio rompio placements que el script no pudo actualizar
(IDB del level editor con placements pickup). Esta reversion vuelve los
sprites a los IDs originales (200-208) y AUTO_FILL_BASE_ID sube a 209 para
que no colisione.

Mapeo inverso (mismo orden que el renumber inicial):
  13  -> 200  (old church  part4)
  33  -> 201  (old church  part5)
  34  -> 202  (old church  part6)
  35  -> 203  (old church  part7)
  36  -> 204  (old church  part8)
  37  -> 205  (old church  part9)
  38  -> 206  (old church door closed)
  39  -> 207  (old church door open)
  40  -> 208  (Chimes tower door)
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG_PATH = ROOT / 'code' / 'bg_sprites.json'
LEVEL_PATH = ROOT / 'code' / 'level_data.json'

# Mapeo inverso del renumber inicial
MAPPING = {
    13: 200,
    33: 201,
    34: 202,
    35: 203,
    36: 204,
    37: 205,
    38: 206,
    39: 207,
    40: 208,
}


def main():
    bg = json.loads(BG_PATH.read_text(encoding='utf-8'))
    level = json.loads(LEVEL_PATH.read_text(encoding='utf-8'))

    # Verificar que los IDs origen existen en bgNames
    missing = [old for old in MAPPING if str(old) not in bg['bgNames']]
    if missing:
        print(f'WARNING: estos IDs no existen en bgNames: {missing}')
        print('(quiza el renumber inicial nunca se aplico o ya se revirtio)')

    # Verificar que los destinos no estan ocupados
    occupied = [new for new in MAPPING.values() if str(new) in bg['bgNames']]
    if occupied:
        print(f'ERROR: estos IDs destino ya estan ocupados: {occupied}')
        print('Aborto. Revisa manualmente.')
        return

    print('Revirtiendo:')
    for old, new in MAPPING.items():
        name = bg['bgNames'].get(str(old), '(no existe)')
        print(f'  {old:3d} -> {new:3d}  {name!r}')

    # bgNames
    new_names = {}
    for sid, name in bg['bgNames'].items():
        sid_n = int(sid)
        new_id = MAPPING.get(sid_n, sid_n)
        new_names[str(new_id)] = name
    bg['bgNames'] = new_names

    # bgTintPaper
    if 'bgTintPaper' in bg:
        new_tint = {}
        for sid, val in bg['bgTintPaper'].items():
            sid_n = int(sid)
            new_id = MAPPING.get(sid_n, sid_n)
            new_tint[str(new_id)] = val
        bg['bgTintPaper'] = new_tint

    # sprites array: id + derivedFrom
    for sp in bg.get('sprites', []):
        if sp.get('id') in MAPPING:
            sp['id'] = MAPPING[sp['id']]
        if sp.get('derivedFrom') in MAPPING:
            sp['derivedFrom'] = MAPPING[sp['derivedFrom']]

    # bgPlacements
    bgp = level.get('bgPlacements', {})
    placement_changes = 0
    for room_key, placements in bgp.items():
        if not isinstance(placements, list):
            continue
        for p in placements:
            if p.get('id') in MAPPING:
                p['id'] = MAPPING[p['id']]
                placement_changes += 1
    print(f'Placements actualizados: {placement_changes}')

    # Otras estructuras (templates, etc.)
    extra_changes = 0
    def walk_remap(obj):
        nonlocal extra_changes
        if isinstance(obj, dict):
            for k in ('id', 'spriteId', 'bgSpriteId', 'derivedFrom'):
                if k in obj and isinstance(obj[k], int) and obj[k] in MAPPING:
                    obj[k] = MAPPING[obj[k]]
                    extra_changes += 1
            for v in obj.values():
                walk_remap(v)
        elif isinstance(obj, list):
            for v in obj:
                walk_remap(v)
    for k, v in level.items():
        if k == 'bgPlacements':
            continue
        walk_remap(v)
    print(f'Otras referencias actualizadas: {extra_changes}')

    BG_PATH.write_text(json.dumps(bg, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    LEVEL_PATH.write_text(json.dumps(level, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print()
    print('OK. Revert aplicado.')
    print('Siguiente: cierra y reabre el level editor (Ctrl+R no basta — cierra pestana).')
    print('Pulsa Load BG JSON. Verifica placements. Export ASM + Export All BG. Recompila.')


if __name__ == '__main__':
    main()
