#!/usr/bin/env python3
"""
parse_build_stats.py - Parse sjasmplus build output into build_stats.json.

Se lanza desde build_and_spectaculator.bat y build_and_zesarux.bat tras
compilar. Lee las lineas de DISPLAY (Fin bank N / Bytes bank N usados / RAM
Libre en Upper block / Fin de codigo actual) y escribe un JSON que el level
editor lee para mostrar el uso real de cada banco en el banner.

Uso: python parse_build_stats.py <sjasmplus_output.tmp> <out.json>
"""

import json, re, sys, time
from pathlib import Path

BANK_SIZE = 16384   # 16 KB por banco en ZX Spectrum 128

# Etiquetas para el banner del editor. Sincronizar con INCLUDEs en main.asm.
BANK_LABELS = {
    0: 'main code (upper portion)',
    1: 'screen_rooms',
    3: 'bg_gfx (town/forest)',
    4: 'bg_gfx_b (ruins/cemetery)',
    6: 'screen_gaps + monster_ai_bank6 + sprite_data + shift_tables',
}


def _to_int(s: str) -> int:
    s = s.strip()
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    if s.startswith('$'):
        return int(s[1:], 16)
    return int(s, 10)


def parse(text: str) -> dict:
    banks = {}

    # "Bytes bank N usados: 0xXXXX"
    for m in re.finditer(r'Bytes bank\s+(\d+)\s+usados:\s*([0-9A-Fa-fxX$]+)', text):
        bank = int(m.group(1))
        used = _to_int(m.group(2))
        banks[bank] = {'used_bytes': used}

    # Bank 0 no aparece como "bank 0 usados" sino como
    # "RAM Libre en Upper block: 0xXXXX" (libre en $C000..$FFFF).
    m = re.search(r'RAM Libre en Upper block:\s*([0-9A-Fa-fxX$]+)', text)
    if m:
        free = _to_int(m.group(1))
        banks[0] = {'used_bytes': BANK_SIZE - free}

    # Completar con tamaño y label.
    for bank, info in banks.items():
        info['size_bytes'] = BANK_SIZE
        info['free_bytes'] = BANK_SIZE - info['used_bytes']
        info['percent'] = round(100.0 * info['used_bytes'] / BANK_SIZE, 2)
        info['label'] = BANK_LABELS.get(bank, '')

    # "Fin de codigo actual (PC): 0xXXXX" — extremo superior del bank 0.
    m = re.search(r'Fin de codigo actual \(PC\):\s*([0-9A-Fa-fxX$]+)', text)
    if m and 0 in banks:
        banks[0]['end_addr'] = _to_int(m.group(1))

    return {
        'timestamp': int(time.time()),
        'banks': {str(k): v for k, v in sorted(banks.items())},
    }


def main():
    if len(sys.argv) != 3:
        print('Usage: parse_build_stats.py <sjasmplus_out.tmp> <out.json>',
              file=sys.stderr)
        sys.exit(1)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    if not src.exists():
        print(f'Build output not found: {src}', file=sys.stderr)
        sys.exit(1)
    # sjasmplus mezcla consola estandar y DISPLAY; leer bytes y decodificar
    # en latin-1 para sobrevivir a cualquier byte raro.
    text = src.read_bytes().decode('latin-1', errors='replace')
    stats = parse(text)
    dst.write_text(json.dumps(stats, indent=2), encoding='utf-8')
    print(f'Wrote {dst} ({len(stats["banks"])} banks parsed)')


if __name__ == '__main__':
    main()
