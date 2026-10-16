"""Audicion de SFX: graba cada efecto (beeper o AY) a un WAV con zxrun.

    python tools/perf/sfx_audition.py [--out CARPETA] [--patch P.patch ...]
                                      [--only beeper:SFX_Attack ay:AYSFX_ATTACK tick:30:100 ...]

Compila una variante con -DSFXTEST (code/sfx_test.asm): tras la splash, en vez
de jugar, para la musica y toca uno a uno los SFX de la lista con ~0,8 s de
silencio entre ellos. Graba todo el audio de la partida (zxrun --wav, beeper +
AY a 44,1 kHz), lo corta por SFX (SfxTestStep) y deja en --out:
  NN-<tipo>-<nombre>.wav   un WAV por SFX
  todos.wav                todos seguidos
  sfx.png                  forma de onda + espectrograma de cada uno
Sin --only: todos los SFX de beeper que usa el codigo, los dos tics de beeper
(buff, brujula) y todos los SFX de code/sfx_library.json.
"""
import argparse, json, os, re, struct, sys, wave
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_common as pc
from build import build

SR = 44100
PER_FRAME = SR // 50


def default_list():
    code = os.path.join(pc.REPO, 'code')
    used = set()
    for fn in os.listdir(code):
        if fn.endswith('.asm') and fn != 'sound.asm':
            used |= set(re.findall(r'LD HL, (SFX_\w+)', open(os.path.join(code, fn), encoding='latin-1').read()))
    defined = re.findall(r'^(SFX_\w+):', open(os.path.join(code, 'sound.asm'), encoding='latin-1').read(), re.M)
    items = [('beeper', s) for s in defined if s in used]
    items += [('tick', '30:100'), ('tick', '30:70')]          # BeeperTick buff / brujula
    lib = json.load(open(os.path.join(code, 'sfx_library.json'), encoding='utf-8'))
    items += [('ay', s['id']) for s in lib['sfx']]
    return items


def list_asm(items):
    L = ['SfxTestList:']
    for kind, name in items:
        if kind == 'beeper':
            L.append(f'    DEFB 0 : DEFW {name}')
        elif kind == 'ay':
            L.append(f'    DEFB 1, {name}, 0')
        else:
            b, e = name.split(':')
            L.append(f'    DEFB 2, {int(b)}, {int(e)}')
    L.append('    DEFB $FF')
    return '\n'.join(L) + '\n'


def write_wav(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(struct.pack(f'<{len(samples)}h', *samples))


def sheet(path, clips):
    """Forma de onda + espectrograma (numpy) de cada clip, uno debajo de otro."""
    import numpy as np
    from PIL import Image, ImageDraw
    W, HW, HS, PAD = 900, 36, 64, 16
    img = Image.new('RGB', (W, len(clips) * (HW + HS + PAD) + 4), (16, 16, 24))
    dr = ImageDraw.Draw(img)
    y = 2
    for name, s in clips:
        a = np.array(s, dtype=np.float32) / 32768.0
        dr.text((4, y), name, fill=(220, 220, 220))
        y += PAD - 4
        if len(a) == 0:
            y += HW + HS + 4; continue
        n = max(1, len(a) // W)
        for x in range(min(W, len(a) // n)):
            seg = a[x * n:(x + 1) * n]
            lo, hi = float(seg.min()), float(seg.max())
            dr.line([(x, y + HW / 2 - hi * HW / 2), (x, y + HW / 2 - lo * HW / 2)], fill=(120, 200, 255))
        y += HW
        win = 1024
        hop = max(1, (len(a) - win) // W) if len(a) > win else 1
        spec = np.zeros((HS, W), dtype=np.float32)
        for x in range(W):
            i = x * hop
            if i + win > len(a):
                break
            mag = np.abs(np.fft.rfft(a[i:i + win] * np.hanning(win)))[:512]   # 0..~22 kHz
            bins = np.linspace(0, 511, HS + 1).astype(int)
            col = np.array([mag[bins[k]:bins[k + 1] + 1].max() for k in range(HS)])
            spec[::-1, x] = col
        spec = np.log10(spec + 1e-3)
        spec = np.clip((spec + 1.5) / 3.0, 0, 1)
        rgb = (np.stack([spec ** 0.7, spec ** 1.5, spec ** 3], axis=2) * 255).astype(np.uint8)
        img.paste(Image.fromarray(rgb, 'RGB'), (0, y))
        y += HS + 4
    img.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=pc.work_dir('audicion'))
    ap.add_argument('--name', default='sfxtest')
    ap.add_argument('--patch', action='append', default=[])
    ap.add_argument('--only', nargs='+', default=None, help='tipo:nombre (beeper:SFX_x, ay:AYSFX_x, tick:B:E)')
    a = ap.parse_args()
    items = [tuple(x.split(':', 1)) for x in a.only] if a.only else default_list()
    d, _ = build(a.name, a.patch, defines=['SFXTEST=1'], extra={'sfx_test_list.asm': list_asm(items)})
    frames = 260 + 60 * len(items)
    os.makedirs(a.out, exist_ok=True)
    wav_all = os.path.join(a.out, 'todos.wav')
    out = pc.run_zxrun(d, frames, pc.boot_keys(),
                       ['--wav', wav_all, '--every', '1', '--peek', 'SfxTestStep:1'])
    step_at = {}
    for line in out.splitlines():
        m = re.match(r't (\d+) SfxTestStep: ([0-9A-F]{2})', line)
        if m:
            step_at.setdefault(int(m.group(2), 16), int(m.group(1)))
    with wave.open(wav_all) as w:
        raw = w.readframes(w.getnframes())
    pcm = list(struct.unpack(f'<{len(raw) // 2}h', raw))
    clips = []
    for i, (kind, name) in enumerate(items, 1):
        if i not in step_at:
            print(f'  {kind}:{name}: no llego a sonar (¿pocos frames?)'); continue
        f0, f1 = step_at[i], step_at.get(i + 1, step_at[i] + 45)
        s = pcm[f0 * PER_FRAME:(f1 - 1) * PER_FRAME]       # en el ultimo frame ya empieza el siguiente
        end = len(s)                                      # quitar el silencio del final: sin
        while end > 1 and abs(s[end - 1] - s[end - 2]) < 60:   # variacion (el altavoz del beeper
            end -= 1                                      # puede quedarse en un nivel fijo)
        s = s[:min(len(s), end + SR // 10)]
        fn = f'{i:02d}-{kind}-{name.replace(":", "_")}.wav'
        write_wav(os.path.join(a.out, fn), s)
        clips.append((f'{i:02d} {kind}:{name}  ({1000 * end / SR:.0f} ms)', s))
        print(f'  {fn}: {1000 * end / SR:.0f} ms')
    sheet(os.path.join(a.out, 'sfx.png'), clips)
    print(f'-> {a.out}')


if __name__ == '__main__':
    main()
