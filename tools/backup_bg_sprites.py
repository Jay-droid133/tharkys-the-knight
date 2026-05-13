#!/usr/bin/env python3
"""
backup_bg_sprites.py - Snapshot fechado de bg_sprites.json antes de cada build.

Llamado por build_and_spectaculator.bat / build_and_zesarux.bat al arrancar.
Crea code/backups/bg_sprites.YYYYMMDD-HHMMSS.json con copia idéntica del JSON
actual. Conserva los ultimos N snapshots (default 30), rota el resto.

Si algún día el JSON queda corrupto/desincronizado/perdido, puedes recuperar
el más reciente válido desde code/backups/ con un simple `copy /Y`.

Coste: ~158 KB por build (= ~5 MB con 30 snapshots).
Idempotente: si bg_sprites.json no existe, no crea snapshot.
"""

import shutil
import datetime
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'code' / 'bg_sprites.json'
BACKUPS_DIR = ROOT / 'code' / 'backups'
MAX_SNAPSHOTS = 30


def main():
    if not SRC.exists():
        print(f'[backup_bg_sprites] {SRC} no existe — sin snapshot')
        return 0

    BACKUPS_DIR.mkdir(exist_ok=True)

    ts = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    dst = BACKUPS_DIR / f'bg_sprites.{ts}.json'

    # Evita snapshot duplicado si llamadas seguidas dentro del mismo segundo
    if dst.exists():
        print(f'[backup_bg_sprites] snapshot {dst.name} ya existe — skip')
    else:
        shutil.copy2(SRC, dst)
        size_kb = dst.stat().st_size / 1024
        print(f'[backup_bg_sprites] {dst.name} ({size_kb:.0f} KB)')

    # Rotation: keep last MAX_SNAPSHOTS
    snapshots = sorted(BACKUPS_DIR.glob('bg_sprites.*.json'))
    if len(snapshots) > MAX_SNAPSHOTS:
        to_delete = snapshots[:-MAX_SNAPSHOTS]
        for fp in to_delete:
            fp.unlink()
        print(f'[backup_bg_sprites] rotado: borrados {len(to_delete)} snapshots viejos')

    return 0


if __name__ == '__main__':
    sys.exit(main())
