"""IRQ perdidas: frames cuyo INT llega con la CPU en DI (el handler IM 2 no corre).

    python tools/perf/irqlost.py CARPETA [--seeds 1 2 3] [--frames 6000] [--night]

Una IRQ perdida es un tick menos de musica (la musica avanza en el handler),
un tick menos en $5C78 (el reloj del bucle: la vuelta dura un frame mas sin
que el juego lo sepa) y un frame sin SFX AY. Agrupa por la rutina en la que
estaba la CPU cuando se perdio el INT (zxrun --irq).
"""
import argparse, collections, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_common as pc


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('build')
    ap.add_argument('--seeds', type=int, nargs='+', default=[1, 2, 3])
    ap.add_argument('--frames', type=int, default=6000)
    ap.add_argument('--night', action='store_true')
    a = ap.parse_args()
    tot = collections.Counter(); lost = frames = 0
    for seed in a.seeds:
        keys = pc.boot_keys() + pc.explore_keys(seed, 340, a.frames)
        out = pc.run_zxrun(a.build, a.frames, keys, ['--irq', 'Im2Vector'], warmup=330,
                           poke_at=pc.NIGHT if a.night else ())
        for l in out.splitlines():
            m = re.match(r'irq perdidas: (\d+) de (\d+)', l)
            if m:
                lost += int(m.group(1)); frames += int(m.group(2))
            m = re.match(r'\s+irq perdida con PC \w+ ([\w.]+)\+\d+: (\d+)', l)
            if m:
                tot[m.group(1).split('.')[0]] += int(m.group(2))
    print(f'IRQ perdidas: {lost} de {frames} frames ({100.0 * lost / max(1, frames):.2f} %)')
    for k, v in tot.most_common(20):
        print(f'  {k:32} {v:5} ({100.0 * v / max(1, lost):.1f} %)')


if __name__ == '__main__':
    main()
