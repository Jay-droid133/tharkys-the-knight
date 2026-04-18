#!/usr/bin/env python3
"""clone_biomes.py — Clonado de sprites base town -> forest / ruins / cemetery.

Convencion: el clon se llama `<base.name> <biome>`. El engine (level_editor.html,
funcion getBiomeSprite) hace auto-swap por nombre.

Idempotente:
  - Salta cualquier variante que ya exista en sprites[] por nombre.
  - Rerunir es seguro (no duplica).

Para anadir mas bases en el futuro:
  1) Dibuja el sprite town en el editor.
  2) Anade su ID al final de la lista BASES.
  3) Opcional: anade su asignacion de IDs en ID_PLAN (o deja que el
     script la calcule automaticamente reusando huecos libres).
  4) Rerunir `py tools/clone_biomes.py`.

Uso:
    py tools/clone_biomes.py           # clona todo
    py tools/clone_biomes.py --dry-run # solo reporta lo que haria
"""
import json
import sys
from pathlib import Path

BG_PATH = Path(r'C:/NUEVO_JUEGO/code/bg_sprites.json')

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

BIOMES = ('forest', 'ruins', 'cemetery')

# Lista de IDs base (sprites town) a clonar.
# Solo arquitectura city + decoracion (pots). Neutrals (well, bench, keys,
# locks, farola estrecha) no se clonan.
BASES = [
    2,   # big house
    3,   # tall house
    4,   # narrow tall house
    5,   # house short
    6,   # small house
    7,   # little house
    8,   # very little house
    9,   # minimal house
    10,  # pot 3x3
    11,  # pot 4x4
    18,  # house farola curved right
    22,  # anexo 2x3
    23,  # house 4x3
    24,  # 2x7
    25,  # house 4x7
    26,  # house 5x5
    27,  # 2x5
    31,  # farola 2x5 house
    32,  # house farola straight
    61,  # house farola curved left
]

# Bloques contiguos por bioma para legibilidad (100-199).
# forest:   100-119 (20 IDs)
# ruins:    120-138 (19 IDs, salta big house ruins que ya existe como id 30)
# cemetery: 139-158 (20 IDs)
ID_BLOCKS = {
    'forest':   range(100, 120),
    'ruins':    range(120, 139),
    'cemetery': range(139, 159),
}

# IDs que NO debemos usar porque ya hay una variante con ese nombre.
# (Caso del legado: id=30 'big house ruins' = variante ruins de id=2 'big house'.)
PREEXISTING = {
    ('big house', 'ruins'): 30,
}


def load():
    with open(BG_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)


def save(d):
    with open(BG_PATH, 'w', encoding='utf-8') as f:
        json.dump(d, f, separators=(',', ':'), ensure_ascii=False)


def clone_one(base_sp, biome, new_id):
    """Devuelve dict de nuevo sprite (copia exacta de base_sp con name + ' ' + biome)."""
    name = f"{base_sp['name']} {biome}"
    new_sp = {
        'id': new_id,
        'w': base_sp['w'],
        'h': base_sp['h'],
        'name': name,
        'pixelBytes': list(base_sp['pixelBytes']),
        'attrBytes':  list(base_sp['attrBytes']),
    }
    if 'tintPaper' in base_sp:
        new_sp['tintPaper'] = base_sp['tintPaper']
    return new_sp


def main():
    dry = '--dry-run' in sys.argv
    d = load()
    sprites_by_id = {s['id']: s for s in d['sprites']}
    sprites_by_name = {s.get('name', ''): s for s in d['sprites']}

    # Sanity: todos los BASES existen
    missing = [b for b in BASES if b not in sprites_by_id]
    if missing:
        print(f'ERROR: IDs base no existen en sprites[]: {missing}')
        sys.exit(1)

    # Reservar IDs que ya estan ocupados en los bloques (por seguridad)
    reserved = set(sprites_by_id.keys())

    plan = []        # (base_id, biome, new_id)
    skipped = []     # (base_id, biome, reason)

    for biome in BIOMES:
        block = list(ID_BLOCKS[biome])
        # Iterador que devuelve el siguiente ID libre en el bloque
        def next_free():
            while block:
                cand = block.pop(0)
                if cand not in reserved:
                    reserved.add(cand)
                    return cand
            return None

        for base_id in BASES:
            base_sp = sprites_by_id[base_id]
            base_name = base_sp.get('name', '')
            variant_name = f"{base_name} {biome}"

            # Preexistente legado
            if (base_name, biome) in PREEXISTING:
                pre_id = PREEXISTING[(base_name, biome)]
                skipped.append((base_id, biome, f'preexistente id={pre_id} "{variant_name}"'))
                continue

            # Ya hay un sprite con ese nombre -> idempotente
            if variant_name in sprites_by_name:
                existing_id = sprites_by_name[variant_name]['id']
                skipped.append((base_id, biome, f'ya existe id={existing_id}'))
                continue

            new_id = next_free()
            if new_id is None:
                print(f'ERROR: bloque "{biome}" sin IDs libres para base {base_id}')
                sys.exit(1)
            plan.append((base_id, biome, new_id))

    # Reporte
    print(f'Plan de clonado ({len(plan)} nuevos clones):')
    for base_id, biome, new_id in plan:
        base_sp = sprites_by_id[base_id]
        name = f"{base_sp['name']} {biome}"
        print(f'   id={new_id:>3}  <-  base {base_id:>2} "{base_sp["name"]}"   name="{name}"')
    if skipped:
        print(f'\nSaltados ({len(skipped)}):')
        for base_id, biome, reason in skipped:
            print(f'   base={base_id:>2} biome={biome:<9} {reason}')

    if dry:
        print('\n[DRY-RUN] no se escribio nada.')
        return

    if not plan:
        print('\nNada que clonar.')
        return

    # Ejecutar
    for base_id, biome, new_id in plan:
        base_sp = sprites_by_id[base_id]
        new_sp = clone_one(base_sp, biome, new_id)
        d['sprites'].append(new_sp)
        d['bgNames'][str(new_id)] = new_sp['name']
        if 'tintPaper' in new_sp:
            d.setdefault('bgTintPaper', {})[str(new_id)] = new_sp['tintPaper']

    # Mantener sprites[] ordenados por id (opcional, ayuda legibilidad)
    d['sprites'].sort(key=lambda s: s['id'])

    save(d)
    print(f'\nOK. {len(plan)} clones anadidos.')


if __name__ == '__main__':
    main()
