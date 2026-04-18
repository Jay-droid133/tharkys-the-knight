#!/usr/bin/env python3
"""Fase 2 — Normalizar fillers a convention `filler <biome>`.

Renombra:
  id=20 'FillerCemetery' -> 'filler cemetery'
  id=21 'FillerForest'   -> 'filler forest'

Mantiene:
  id=17 'Filler'         (baseline town)
  id=19 'filler ruins'   (ya correcto)
"""
import json

BG_PATH = r'C:/NUEVO_JUEGO/code/bg_sprites.json'

RENAMES = {
    20: 'filler cemetery',
    21: 'filler forest',
}


def main():
    with open(BG_PATH, 'r', encoding='utf-8') as f:
        d = json.load(f)
    changed = []
    for s in d['sprites']:
        sid = s['id']
        if sid in RENAMES:
            old = s.get('name', '')
            new = RENAMES[sid]
            if old != new:
                s['name'] = new
                changed.append((sid, old, new))
    for sid, new in RENAMES.items():
        key = str(sid)
        if key in d.get('bgNames', {}):
            d['bgNames'][key] = new
    with open(BG_PATH, 'w', encoding='utf-8') as f:
        json.dump(d, f, separators=(',', ':'), ensure_ascii=False)
    print('Fillers renombrados:')
    for sid, old, new in changed:
        print(f'   id={sid:>2}  "{old}"  ->  "{new}"')
    print(f'Total: {len(changed)}')


if __name__ == '__main__':
    main()
