#!/usr/bin/env python3
"""Fase 1 — Normalizar nombres base a minusculas + espacios.

Actualiza `name` en sprites[] y `bgNames` de bg_sprites.json.
"""
import json

BG_PATH = r'C:/NUEVO_JUEGO/code/bg_sprites.json'

RENAMES = {
    3:  'tall house',
    4:  'narrow tall house',
    6:  'small house',
    7:  'little house',
    8:  'very little house',
    9:  'minimal house',
    10: 'pot 3x3',
}


def main():
    with open(BG_PATH, 'r', encoding='utf-8') as f:
        d = json.load(f)
    changed = []
    # sprites[]
    for s in d['sprites']:
        sid = s['id']
        if sid in RENAMES:
            old = s.get('name', '')
            new = RENAMES[sid]
            if old != new:
                s['name'] = new
                changed.append((sid, old, new))
    # bgNames
    for sid, new in RENAMES.items():
        key = str(sid)
        if key in d.get('bgNames', {}):
            d['bgNames'][key] = new
    with open(BG_PATH, 'w', encoding='utf-8') as f:
        json.dump(d, f, separators=(',', ':'), ensure_ascii=False)
    print('Renombrados:')
    for sid, old, new in changed:
        print(f'   id={sid:>2}  "{old}"  ->  "{new}"')
    print(f'Total: {len(changed)}')


if __name__ == '__main__':
    main()
