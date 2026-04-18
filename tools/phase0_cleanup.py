#!/usr/bin/env python3
"""Fase 0 — Limpieza previa al clonado biomas.

1) bg_sprites.json:
   - Borra claves fantasma de bgNames: 42,44,45-49,51-59 (sin datos en sprites[]).
   - Borra sprite id 13 (entrada vacia sin nombre).
2) level_data.json:
   - Borra pickups huerfanos: cellOverlays["5,4"] id 70, cellOverlays["11,5"] id 71.

Uso: py tools/phase0_cleanup.py
"""
import json, os, sys

BG_PATH = r'C:/NUEVO_JUEGO/code/bg_sprites.json'
LVL_PATH = r'C:/NUEVO_JUEGO/code/level_data.json'

GHOST_NAMES = {'42','44','45','46','47','48','49','51','52','53','54','55','56','57','58','59'}
SPRITE_IDS_TO_REMOVE = {13}

ORPHAN_PICKUPS = [
    ('5,4', 70),
    ('11,5', 71),
]


def clean_bg_sprites():
    with open(BG_PATH, 'r', encoding='utf-8') as f:
        d = json.load(f)
    removed_names = []
    for k in list(d.get('bgNames', {}).keys()):
        if k in GHOST_NAMES:
            removed_names.append((k, d['bgNames'][k]))
            del d['bgNames'][k]
    removed_sprites = []
    before = len(d['sprites'])
    d['sprites'] = [s for s in d['sprites'] if s['id'] not in SPRITE_IDS_TO_REMOVE or removed_sprites.append((s['id'], s.get('name',''))) or False]
    # also drop bgTintPaper entries pointing at removed sprites (none here, but safe):
    bgtp = d.get('bgTintPaper', {})
    for sid in SPRITE_IDS_TO_REMOVE:
        bgtp.pop(str(sid), None)
    with open(BG_PATH, 'w', encoding='utf-8') as f:
        json.dump(d, f, separators=(',', ':'), ensure_ascii=False)
    print(f'[bg_sprites.json] bgNames fantasma borrados ({len(removed_names)}):')
    for k, v in removed_names:
        print(f'   - "{k}":"{v}"')
    print(f'[bg_sprites.json] sprites[] borrados ({len(removed_sprites)}): {before} -> {len(d["sprites"])}')
    for sid, name in removed_sprites:
        print(f'   - id={sid} name="{name}"')


def clean_level_data():
    with open(LVL_PATH, 'r', encoding='utf-8') as f:
        d = json.load(f)
    co = d.get('cellOverlays') or {}
    removed = []
    for key, sid in ORPHAN_PICKUPS:
        pls = co.get(key)
        if not pls:
            continue
        before = len(pls)
        pls[:] = [p for p in pls if p.get('id') != sid]
        removed.append((key, sid, before - len(pls)))
        if not pls:
            del co[key]
    with open(LVL_PATH, 'w', encoding='utf-8') as f:
        json.dump(d, f, separators=(',', ':'), ensure_ascii=False)
    print('[level_data.json] pickups huerfanos borrados:')
    for key, sid, n in removed:
        print(f'   - cellOverlays["{key}"] id={sid} x{n}')


if __name__ == '__main__':
    clean_bg_sprites()
    print()
    clean_level_data()
    print('\nFase 0 completada. Backups en *.bak')
