"""Banco de rendimiento: una partida guionizada en zxrun y su perfil por vuelta de MainLoop.

    python tools/perf/bench.py CARPETA [--frames 6000] [--seed 1] [--scenario explore|night|nofire|stand]
                               [--inside RUTINA ...] [--beam 128k] [--csv-out f.csv] [--top 25]

CARPETA = salida de build.py (juego.sna, build.sym, build.lst).

El juego va a 25 fps: cada vuelta de MainLoop debe durar 2 ticks de 50 Hz; 3 o
mas es un tiron. Mide cada vuelta (MainLoop -> JP MainLoop), el trabajo hasta
.frameSync, el handler IM 2 y cada CALL del bucle (tramo de la M1 del CALL a la
M1 de la instruccion siguiente: incluye lo que llama y las IRQ que caigan
dentro). Las vueltas con DrawScreen > --trans T son cambios de sala; las del
minimapa modal (ShowMinimap*) se excluyen.

  --inside R   perfila tambien los CALL de dentro de la rutina R (p. ej. DrawScreen)
  --beam 128k  parpadeo: bytes que el haz ve a medio dibujar (excluye los frames
               en los que se redibuja la sala)

Las partidas son caoticas: cualquier cambio de codigo cambia trayectorias.
Comparar medias de varias semillas, no frame a frame.
"""
import argparse, csv, os, statistics, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_common as pc

MODALS = ('ShowMinimapTimed', 'ShowMinimap')


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p / 100))] if v else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('build')
    ap.add_argument('--frames', type=int, default=6000)
    ap.add_argument('--warmup', type=int, default=330)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--scenario', default='explore', choices=['explore', 'night', 'stand', 'nofire'])
    ap.add_argument('--beam', default=None, help='128k | pentagon | 48k')
    ap.add_argument('--beam-shot', default=None)
    ap.add_argument('--csv-out', default=None)
    ap.add_argument('--top', type=int, default=25)
    ap.add_argument('--trans', type=int, default=30000, help='DrawScreen > N T = vuelta de cambio de sala')
    ap.add_argument('--poke', action='append', default=[])
    ap.add_argument('--poke-at', action='append', default=[])
    ap.add_argument('--shot', action='append', default=[])
    ap.add_argument('--inside', action='append', default=[])
    a = ap.parse_args()

    lst = os.path.join(a.build, 'build.lst')
    syms = pc.load_syms(os.path.join(a.build, 'build.sym'))
    profs = [(syms['MainLoop'], syms['MainLoop.frameStart'] - 3, 'iter'),   # el JP MainLoop va justo antes de .frameStart
             (syms['MainLoop'], syms['MainLoop.frameSync'], 'work'),
             (syms['Im2Vector'], syms['MusicIrqHandler.mihEpilogue'] + 5, 'irq')]
    seen = {}
    for addr, name in pc.mainloop_calls(lst):
        seen[name] = seen.get(name, 0) + 1
        profs.append((addr, addr + 3, name if seen[name] == 1 else f'{name}@{seen[name]}'))
    for addr, name in pc.call_sites(lst, MODALS):
        profs.append((addr, addr + 3, f'modal:{name}@{addr:04X}'))
    for r in a.inside:
        for addr, name in pc.routine_calls(lst, r):
            lab = f'{r}>{name}'
            seen[lab] = seen.get(lab, 0) + 1
            profs.append((addr, addr + 3, lab if seen[lab] == 1 else f'{lab}@{seen[lab]}'))

    keys = pc.boot_keys()
    if a.scenario in ('explore', 'night'):
        keys += pc.explore_keys(a.seed, 340, a.frames)
    elif a.scenario == 'nofire':
        keys += pc.explore_keys(a.seed, 340, a.frames, fire=False)
    poke_at = list(a.poke_at) + (pc.NIGHT if a.scenario == 'night' else [])
    fd, csvf = tempfile.mkstemp(suffix='.csv'); os.close(fd)
    args = ['--csv', csvf]
    for p0, p1, lab in profs:
        args += ['--prof', f'{p0}:{p1}={lab}']
    if a.beam:
        args += ['--beam', a.beam, '--beam-skip', 'DrawScreen+5:DrawBgGfxSprite']   # +5: tras el RET Z
        if a.beam_shot:
            args += ['--beam-shot', a.beam_shot]
    for s in a.shot:
        args += ['--shot', s]
    try:
        text = pc.run_zxrun(a.build, a.frames, keys, args, a.warmup, a.poke, poke_at)
        rows = list(csv.DictReader(open(csvf)))
    finally:
        os.unlink(csvf)
    if a.csv_out:
        with open(a.csv_out, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)

    labs = [p[2] for p in profs]
    it = [{k: int(v) for k, v in r.items()} for r in rows]
    if not it:
        print(text); sys.exit('sin vueltas medidas')
    modal_labs = [l for l in labs if l.startswith('modal:')]
    modal = [r for r in it if any(r[l] for l in modal_labs)]
    it = [r for r in it if not any(r[l] for l in modal_labs)]
    trans = [r for r in it if r.get('DrawScreen', 0) > a.trans]
    play = [r for r in it if r.get('DrawScreen', 0) <= a.trans]

    def nframes(r):
        return max(1, round(r['iter'] / pc.FRAME))

    total = sum(nframes(r) for r in it)
    hist = {}
    for r in play:
        hist[nframes(r)] = hist.get(nframes(r), 0) + 1
    lost_play = sum(max(0, nframes(r) - 2) for r in play)
    lost_trans = sum(max(0, nframes(r) - 2) for r in trans)
    print(f'escenario {a.scenario} semilla {a.seed}: {len(it)} vueltas, {total} frames medidos')
    print(f'  juego: {len(play)} vueltas; ticks por vuelta: ' +
          ', '.join(f'{k}: {v} ({100.0 * v / len(play):.1f} %)' for k, v in sorted(hist.items())))
    print(f'  frames de mas en juego: {lost_play} ({100.0 * lost_play / max(1, total):.2f} % del tiempo)')
    w = [r['work'] for r in play]
    print(f'  trabajo por vuelta (T, con contienda): media {int(statistics.mean(w))}  p50 {pct(w, 50)}  '
          f'p90 {pct(w, 90)}  p99 {pct(w, 99)}  max {max(w)}  (2 frames = {2 * pc.FRAME})')
    if trans:
        tf = [nframes(r) for r in trans]
        print(f'  cambios de sala: {len(trans)}; frames por vuelta de cambio: media {statistics.mean(tf):.1f} '
              f'min {min(tf)} max {max(tf)}; DrawScreen media {int(statistics.mean(r["DrawScreen"] for r in trans))} T; '
              f'tiempo congelado total {lost_trans} frames de mas')
    print(f'  IRQ: {int(statistics.mean(r["irq"] for r in play))} T por vuelta'
          + (f'; vueltas con mapa modal (excluidas): {len(modal)}' if modal else ''))

    slow = [r for r in play if nframes(r) > 2]
    print(f'\n  {"rutina":34} {"media":>7} {"p99":>7} {"max":>7} {"%trab":>6} {"lentas":>7}')
    tw = statistics.mean(w)
    rank = sorted([l for l in labs[3:] if not l.startswith('modal:') and '>' not in l],
                  key=lambda l: -statistics.mean(r[l] for r in play))
    for l in rank[:a.top]:
        v = [r[l] for r in play]
        sm = int(statistics.mean(r[l] for r in slow)) if slow else 0
        print(f'  {l:34} {int(statistics.mean(v)):7} {pct(v, 99):7} {max(v):7} {100.0 * statistics.mean(v) / tw:5.1f}% {sm:7}')
    il = [l for l in labs if '>' in l]
    if il:
        base = trans if trans and any(l.startswith('DrawScreen>') for l in il) else play
        print(f'\n  dentro de {", ".join(a.inside)} (media por vuelta {"de cambio de sala" if base is trans else "de juego"}, T):')
        for l in sorted(il, key=lambda l: -statistics.mean(r[l] for r in base))[:a.top]:
            v = [r[l] for r in base]
            print(f'  {l:48} media {int(statistics.mean(v)):9}  max {max(v):9}')
    if a.beam:
        print()
        for line in text.splitlines():
            if line.startswith(('haz', '  celda', '  escrito', '  (frames')):
                print(line)


if __name__ == '__main__':
    main()
