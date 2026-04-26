#!/usr/bin/env python3
"""
renumber_sprites.py - Renumera sprites con id >= 200 a huecos libres en 1-199.

Razon: AUTO_FILL_BASE_ID volvio a 200 (el rango 230-255 era insuficiente para
los autofills que se generan ahora). Los sprites manuales que cayeron en
200-208 hay que moverlos a IDs libres por debajo.

Modifica in-place:
- code/bg_sprites.json: bgNames, bgTintPaper, sprites[].id, sprites[].derivedFrom.
- code/level_data.json: bgPlacements[].id (todos los rooms).

Tras ejecutar este script:
1. Abre el level editor (Ctrl+R para forzar recarga).
2. Pulsa "Load BG JSON" si tienes ese boton (sincroniza IDB con el disk).
3. Pulsa "Export ASM" para regenerar screen_data.asm con los IDs nuevos.
4. Pulsa "Export All BG" para regenerar bg_sprites.json + el editor recargara.
5. Recompila.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG_PATH = ROOT / 'code' / 'bg_sprites.json'
LEVEL_PATH = ROOT / 'code' / 'level_data.json'


def main():
    bg = json.loads(BG_PATH.read_text(encoding='utf-8'))
    level = json.loads(LEVEL_PATH.read_text(encoding='utf-8'))

    used_ids = {int(k) for k in bg['bgNames'].keys()}
    high_ids = sorted(i for i in used_ids if i >= 200)
    if not high_ids:
        print('No sprites con id >= 200. Nada que renumerar.')
        return

    free_low = [i for i in range(1, 200) if i not in used_ids]
    if len(free_low) < len(high_ids):
        print(f'ERROR: solo {len(free_low)} huecos libres en 1..199 para {len(high_ids)} sprites. Aborto.')
        sys.exit(1)

    mapping = dict(zip(high_ids, free_low[:len(high_ids)]))
    print('Mapeo de IDs:')
    for old, new in mapping.items():
        name = bg['bgNames'].get(str(old), '?')
        print(f'  {old:3d} -> {new:3d}  {name!r}')

    # bgNames
    new_names = {}
    for sid, name in bg['bgNames'].items():
        sid_n = int(sid)
        new_id = mapping.get(sid_n, sid_n)
        new_names[str(new_id)] = name
    bg['bgNames'] = new_names

    # bgTintPaper
    if 'bgTintPaper' in bg:
        new_tint = {}
        for sid, val in bg['bgTintPaper'].items():
            sid_n = int(sid)
            new_id = mapping.get(sid_n, sid_n)
            new_tint[str(new_id)] = val
        bg['bgTintPaper'] = new_tint

    # sprites array: id + derivedFrom
    for sp in bg.get('sprites', []):
        if sp.get('id') in mapping:
            sp['id'] = mapping[sp['id']]
        if sp.get('derivedFrom') in mapping:
            sp['derivedFrom'] = mapping[sp['derivedFrom']]

    # bgPlacements en level_data: cada room tiene una lista de placements con .id
    bgp = level.get('bgPlacements', {})
    placement_changes = 0
    for room_key, placements in bgp.items():
        if not isinstance(placements, list):
            continue
        for p in placements:
            if p.get('id') in mapping:
                p['id'] = mapping[p['id']]
                placement_changes += 1
    print(f'Placements actualizados en level_data.json: {placement_changes}')

    # Otras estructuras pueden referenciar IDs (templates, templateLibrary, etc.):
    # caminamos recursivamente y actualizamos cualquier dict con clave 'id' o 'spriteId'.
    def walk_remap(obj):
        nonlocal extra_changes
        if isinstance(obj, dict):
            for k in ('id', 'spriteId', 'bgSpriteId', 'derivedFrom'):
                if k in obj and isinstance(obj[k], int) and obj[k] in mapping:
                    obj[k] = mapping[obj[k]]
                    extra_changes += 1
            for v in obj.values():
                walk_remap(v)
        elif isinstance(obj, list):
            for v in obj:
                walk_remap(v)

    extra_changes = 0
    # Excluimos bgPlacements (ya hecho) para evitar doble conteo.
    for k, v in level.items():
        if k == 'bgPlacements':
            continue
        walk_remap(v)
    print(f'Otras referencias actualizadas en level_data.json: {extra_changes}')

    BG_PATH.write_text(json.dumps(bg, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    LEVEL_PATH.write_text(json.dumps(level, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    print()
    print('OK. Archivos actualizados:')
    print(f'  {BG_PATH}')
    print(f'  {LEVEL_PATH}')
    print()
    print('Siguiente paso: en el level editor pulsa Ctrl+R, despues Load BG JSON,')
    print('despues Export ASM (y Export All BG si te ofrece). Luego recompila.')


if __name__ == '__main__':
    main()
