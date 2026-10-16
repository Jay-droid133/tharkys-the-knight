"""Comun a las herramientas de rendimiento de Tharkys (partidas en zxrun, sin ventana).

zxrun es el emulador sin ventana del repo Experiment (tools/zxrun), con el
parche tools/perf/zxrun_tharkys.patch aplicado (--irq, --dump, --stable,
--beam-skip, haz a 25 fps). Rutas: ver README.md de esta carpeta.
"""
import os, random, re, shutil, subprocess, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FRAME = 70908                     # T-states por frame (128K)
_LST = re.compile(r'^\s*(\d+)\+?\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2} ?)+?)\s{2,}(.*)$')
_CALL = re.compile(r'CALL\s+(?:(?:N?Z|N?C|P[OE]?|M)\s*,\s*)?([\w.]+)$', re.I)
_GLOBAL = re.compile(r'^\s*\d+\+?\s+[0-9A-F]{4}\s+([A-Za-z_]\w*):')


def _first(cands):
    for c in cands:
        if c and os.path.exists(c):
            return c
    return None


def zxrun_path():
    p = os.environ.get('ZXRUN') or _first([
        r'C:\Experiment\tools\zxrun\zxrun.exe',
        os.path.join(REPO, '..', 'Experiment', 'tools', 'zxrun', 'zxrun.exe'),
        os.path.join(REPO, '..', 'experiment', 'tools', 'zxrun', 'zxrun'),
        shutil.which('zxrun')])
    if not p:
        raise SystemExit('No encuentro zxrun: ZXRUN=<ruta a zxrun.exe> (ver tools/perf/README.md)')
    return p


def sjasmplus_path():
    p = os.environ.get('SJASMPLUS') or _first([
        r'I:\PROGRAMACION\COMPILADORES\sjasmplus-1.21.1.win\sjasmplus.exe',
        r'C:\Experiment\tools\bin\sjasmplus\sjasmplus.exe',
        shutil.which('sjasmplus')])
    if not p:
        raise SystemExit('No encuentro sjasmplus 1.21.1: SJASMPLUS=<ruta> (ver tools/perf/README.md)')
    return p


def work_dir(name):
    """Carpeta de trabajo de una variante (fuera del repo)."""
    return os.path.join(os.environ.get('THARKYS_PERF_WORK') or os.path.join(tempfile.gettempdir(), 'tharkys_perf'), name)


# ---------------------------------------------------------------- .sym / .lst
def load_syms(path):
    s = {}
    for line in open(path, encoding='latin-1'):
        m = re.match(r'^(\S+): EQU 0x([0-9A-F]+)', line)
        if m:
            s[m.group(1)] = int(m.group(2), 16)
    return s


def _lst_code(line):
    m = _LST.match(line.rstrip('\n'))
    if not m:
        return None, None
    return int(m.group(2), 16), m.group(4).split(';')[0].strip()


def routine_calls(lst, name):
    """CALLs dentro de la rutina NAME (hasta la siguiente etiqueta global): [(addr, destino)]"""
    out, inside = [], False
    for line in open(lst, encoding='latin-1'):
        g = _GLOBAL.match(line)
        if not inside:
            inside = bool(g and g.group(1) == name)
            continue
        if g and g.group(1) != name:
            break
        addr, code = _lst_code(line)
        m = _CALL.match(code or '')
        if m:
            out.append((addr, m.group(1)))
    return out


def mainloop_calls(lst):
    """CALLs entre MainLoop: y MainLoop.frameStart (el cuerpo del bucle principal)."""
    out, inside = [], False
    for line in open(lst, encoding='latin-1'):
        if not inside:
            inside = bool(re.search(r'^\s*\d+\+?\s+[0-9A-F]{4}\s+MainLoop:', line))
            continue
        if '.frameStart:' in line:
            break
        addr, code = _lst_code(line)
        m = _CALL.match(code or '')
        if m:
            out.append((addr, m.group(1)))
    return out


def call_sites(lst, targets):
    """Todos los CALL a alguna de las rutinas TARGETS: [(addr, destino)]"""
    out = []
    for line in open(lst, encoding='latin-1'):
        addr, code = _lst_code(line)
        m = _CALL.match(code or '')
        if m and m.group(1) in targets:
            out.append((addr, m.group(1)))
    return out


# ---------------------------------------------------------------- entradas
NIGHT = ['345:GameHours=23', '345:GameMinutes=59']   # a medianoche: campanas y monsters


def boot_keys():
    """SPACE en la splash; la partida empieza hacia el frame 300."""
    return [(60, 64, 'SPACE')]


def explore_keys(seed, start, end, fire=True):
    """Paseo al azar con el joystick Kempston: tramos largos en una direccion
    (cruza salas) y espadazos de vez en cuando. Misma semilla = misma entrada."""
    rnd = random.Random(seed)
    dirs = [('JU',), ('JD',), ('JL',), ('JR',), ('JU', 'JL'), ('JU', 'JR'), ('JD', 'JL'), ('JD', 'JR')]
    k, f = [], start
    while f < end:
        d = rnd.randint(25, 160)
        for key in rnd.choice(dirs):
            k.append((f, min(end, f + d), key))
        if fire and rnd.random() < 0.5:
            g = f + rnd.randint(0, d)
            k.append((g, min(end, g + rnd.randint(3, 12)), 'JF'))
        f += d + rnd.randint(0, 20)
    return k


def run_zxrun(build, frames, keys, args=(), warmup=0, pokes=(), poke_at=()):
    """Una partida: devuelve la salida de texto de zxrun."""
    cmd = [zxrun_path(), os.path.join(build, 'juego.sna'), '--sym', os.path.join(build, 'build.sym'),
           '--frames', str(frames), '--warmup', str(warmup)]
    for p in pokes:
        cmd += ['--poke', p]
    for p in poke_at:
        cmd += ['--poke-at', p]
    fd, kf = tempfile.mkstemp(suffix='.keys')
    try:
        with os.fdopen(fd, 'w') as f:
            for f0, f1, key in keys:
                f.write(f'{f0}-{f1}:{key}\n')
        out = subprocess.run(cmd + ['--keys', kf] + list(args), capture_output=True, text=True)
        if out.returncode:
            raise RuntimeError(out.stderr or out.stdout)
        return out.stdout
    finally:
        os.unlink(kf)
