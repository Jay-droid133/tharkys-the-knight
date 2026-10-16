"""Comprueba que dos builds pintan lo mismo al entrar en cada sala.

    python tools/perf/drawcheck.py CARPETA_A CARPETA_B [--seeds 1 2 3] [--frames 6000] [--night]

En cada build vuelca, en el momento exacto de cada DrawScreen (zxrun --dump):
  - la pantalla entera (6912 B) justo antes de CALL DrawTombstonesInRoom
    (fondo + objetos, sin jugador, enemigos ni tumbas), con la sala, la fase
    del dia, las tablas de remap activas y si el pozo esta en enfriamiento;
  - ZoneCellCount/ZoneCellList justo despues de CALL BuildZoneCellList, con la
    entidad del jugador (semilla del BFS), la llave y el CollisionMap.
Las partidas de los dos builds se separan (otro ritmo de frames), asi que solo
se comparan las claves que aparecen en los dos: una misma sala, en el mismo
estado, tiene que dar exactamente los mismos bytes.
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_common as pc


def site(build, routine, target, after=False):
    for addr, name in pc.routine_calls(os.path.join(build, 'build.lst'), routine):
        if name == target:
            return addr + (3 if after else 0)
    raise SystemExit(f'{build}: no encuentro CALL {target} en {routine}')


def collect(build, seed, frames, poke_at=()):
    a = site(build, 'DrawScreen', 'DrawTombstonesInRoom')
    z = site(build, 'DrawScreen', 'BuildZoneCellList', after=True)
    args = ['--dump', f'{a}:CurrentScreenX:1=sx', '--dump', f'{a}:CurrentScreenY:1=sy',
            '--dump', f'{a}:CurrentTimeOfDay:1=tod', '--dump', f'{a}:WellCooldownTimer:2=wc',
            '--dump', f'{a}:CurrentRemapTable:2=rt', '--dump', f'{a}:CurrentHouseRemapTable:2=hrt',
            '--dump', f'{a}:16384:6912=scr',
            '--dump', f'{z}:CurrentScreenX:1=zsx', '--dump', f'{z}:CurrentScreenY:1=zsy',
            '--dump', f'{z}:EntityTable:16=pl', '--dump', f'{z}:CurrentKey:1=key',
            '--dump', f'{z}:CollisionMap:704=cm', '--dump', f'{z}:ZoneCellCount:511=zone']
    keys = pc.boot_keys() + pc.explore_keys(seed, 340, frames)
    out = pc.run_zxrun(build, frames, keys, args, warmup=200, poke_at=poke_at)
    syms = pc.load_syms(os.path.join(build, 'build.sym'))
    rev = {v: k for k, v in syms.items() if k.startswith('Remap')}   # punteros -> nombre de tabla

    def tname(h):
        b = bytes.fromhex(h.replace(' ', ''))
        return rev.get(b[0] | b[1] << 8, h)

    scr, zone, cur = {}, {}, {}
    for line in out.splitlines():
        if not line.startswith('dump '):
            continue
        head, data = line.split(':', 1)
        lab = head.split()[1]
        cur[lab] = data.strip()
        if lab == 'scr':
            k = (cur['sx'], cur['sy'], cur['tod'], cur['wc'] != '00 00', tname(cur['rt']), tname(cur['hrt']))
            scr.setdefault(k, set()).add(cur['scr'])
        elif lab == 'zone':
            zb = bytes.fromhex(cur['zone'].replace(' ', ''))
            zone.setdefault((cur['zsx'], cur['zsy'], cur['pl'], cur['key'], cur['cm']), set()).add(zb[:1 + 2 * zb[0]].hex())
    return scr, zone


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('a'); ap.add_argument('b')
    ap.add_argument('--seeds', type=int, nargs='+', default=[1, 2, 3])
    ap.add_argument('--frames', type=int, default=6000)
    ap.add_argument('--night', action='store_true', help='medianoche al empezar (monsters, remap de noche)')
    a = ap.parse_args()
    pk = pc.NIGHT if a.night else []
    ns = nz = bs = bz = 0
    for seed in a.seeds:
        sa, za = collect(a.a, seed, a.frames, pk)
        sb, zb = collect(a.b, seed, a.frames, pk)
        for k in sorted(set(sa) & set(sb)):
            ns += 1
            if sa[k] != sb[k]:
                bs += 1
                x = bytes.fromhex(next(iter(sa[k])).replace(' ', ''))
                y = bytes.fromhex(next(iter(sb[k])).replace(' ', ''))
                d = [i for i in range(len(x)) if x[i] != y[i]]
                print(f'  semilla {seed} sala {k[:3]}: PANTALLA DISTINTA ({len(d)} bytes; primero en +{d[0] if d else -1})')
        for k in sorted(set(za) & set(zb)):
            nz += 1
            if za[k] != zb[k]:
                bz += 1
                print(f'  semilla {seed} sala {k[:2]}: ZONA DISTINTA')
        print(f'semilla {seed}: pantallas A {len(sa)} B {len(sb)}; zonas A {len(za)} B {len(zb)}')
    print(f'TOTAL pantallas: {ns} comparadas, {bs} distintas; zonas: {nz} comparadas, {bz} distintas -> '
          + ('IGUALES' if not (bs or bz) else 'HAY DIFERENCIAS'))
    sys.exit(1 if (bs or bz) else 0)


if __name__ == '__main__':
    main()
