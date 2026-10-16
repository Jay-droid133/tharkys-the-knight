"""Compila una variante de Tharkys fuera del repo para medirla.

    python tools/perf/build.py NOMBRE [--patch P1.patch ...] [--sed 'fichero|viejo|nuevo' ...] [-D STANDALONE=1]

Copia code/ a la carpeta de trabajo (perf_common.work_dir: %TEMP%\\tharkys_perf\\NOMBRE),
aplica parches (git apply, en orden) y sustituciones literales, y compila con
sjasmplus. Deja juego.sna, build.sym y build.lst en esa carpeta (lo que leen
bench.py, drawcheck.py e irqlost.py). No toca el repo ni los .sna commiteados.

Ej.: la linea base y los parches del informe (docs/rendimiento):
    python tools/perf/build.py base
    python tools/perf/build.py todos --patch docs/rendimiento/parches/todos.patch
"""
import argparse, os, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from perf_common import REPO, sjasmplus_path, work_dir


def build(name, patches=(), seds=(), defines=(), extra=None):
    """extra: {ruta relativa a code/: contenido} que se escribe antes de compilar."""
    d = work_dir(name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    shutil.copytree(os.path.join(REPO, 'code'), os.path.join(d, 'code'))
    for p in patches:
        r = subprocess.run(['git', 'apply', os.path.abspath(p)], cwd=d, capture_output=True, text=True)
        if r.returncode:
            sys.exit(f'no aplica {p}:\n{r.stdout}{r.stderr}')
    for s in seds:
        f, old, new = s.split('|', 2)
        path = os.path.join(d, 'code', f)
        txt = open(path, encoding='utf-8', errors='surrogateescape').read()
        if old not in txt:
            sys.exit(f'no encuentro en {f}: {old!r}')
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(txt.replace(old, new, 1))
    for rel, content in (extra or {}).items():
        with open(os.path.join(d, 'code', rel), 'w', encoding='utf-8') as f:
            f.write(content)
    cmd = [sjasmplus_path(), '--fullpath', '--syntax=abfF', '--sym=../build.sym', '--lst=../build.lst'] + \
          [f'-D{x}' for x in defines] + ['main.asm']
    r = subprocess.run(cmd, cwd=os.path.join(d, 'code'), capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode:
        sys.exit(f'{name}: no compila\n' + '\n'.join(l for l in out.splitlines() if 'rror' in l)[:3000])
    sna = 'juego_standalone.sna' if any(x.startswith('STANDALONE') for x in defines) else 'juego.sna'
    shutil.copy(os.path.join(d, 'code', sna), os.path.join(d, 'juego.sna'))
    return d, [l for l in out.splitlines() if 'Libre' in l or 'usados' in l]


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('name')
    ap.add_argument('--patch', action='append', default=[])
    ap.add_argument('--sed', action='append', default=[])
    ap.add_argument('-D', action='append', default=[], dest='defines')
    a = ap.parse_args()
    d, info = build(a.name, a.patch, a.sed, a.defines)
    print(d)
    print('\n'.join(info))
