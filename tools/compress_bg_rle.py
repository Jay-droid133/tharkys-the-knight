#!/usr/bin/env python3
"""
compress_bg_rle.py - Comprime pixel data de BG sprites con RLE in-place.

Formato RLE (stream de chunks, sin ambiguedad token/dato):
  Control $01-$7F: literal group, siguen (control) bytes raw de pixel data
  Control $80-$FF: run, count = (control & $7F)+2 (rango 2..129), sigue 1 byte valor

Flag de compresion: bit 7 de width_bytes en el header del sprite.
Si los datos RLE no son menores que los originales, se deja sin comprimir.

Uso: python compress_bg_rle.py [--dry-run]
"""

import re
import sys
import os

BG_GFX_PATHS = [
    os.path.join(os.path.dirname(__file__), '..', 'code', 'bg_gfx.asm'),
    os.path.join(os.path.dirname(__file__), '..', 'code', 'bg_gfx_b.asm'),
]

# Sprites que NO deben comprimirse (acceso directo a pixel data en runtime)
EXCLUDE_SPRITES = {
    'BgGfx_reloj_plaza',    # DrawPlazaClock lee pixels directamente con IX+offset
}

# Patrones de nombre: sprites cuyo label matchea se excluyen del RLE.
# Motivo: DrawBgSpriteXOR (usado para pickups en el mundo) enmascara el flag
# RLE pero NO descomprime. Si un sprite de pickup (keys, locks) se comprime,
# los pixeles salen corruptos al dibujarlo como pickup. El HUD si descomprime
# bien via LoadBgSpriteToBuffer. Hasta que se arregle DrawBgSpriteXOR,
# mejor dejar estos sin comprimir.
EXCLUDE_NAME_PATTERNS = (
    'key',    # forestkey, ruinskey, cemeterykey, towngatekey, church_key, clock_tower_key
    'lock',   # forestlock, ruinslock, cemeterylock, towngatelock (+ _NN aliases)
    'door',   # church_door_closed, town_hall_door — usadas como pickups (lock/trigger)
    'pickup', # health pickup, stamina pickup (+ variantes 2/3/4) — random pickup XOR draw
              # tampoco decodifica RLE. Cubre id 254/255 + 72/73/74/75.
    'arrow',  # BgGfx_arrow_2x2_* y BgGfx_arrow_2x3_* (pista magic compass sobre gap).
              # DrawCompassGapHint usa DrawBgSpriteXOR -> no decodifica RLE -> corrupcion.
)


def encode_rle(data):
    """Codifica una lista de bytes en formato grouped-literal + run."""
    result = []
    i = 0
    n = len(data)

    while i < n:
        # Comprobar si hay un run de 3+ bytes identicos
        run_len = 1
        while (i + run_len < n
               and data[i + run_len] == data[i]
               and run_len < 129):
            run_len += 1

        if run_len >= 3:
            # Run chunk: control ($80 | (count-2)), value
            result.append(0x80 | (run_len - 2))
            result.append(data[i])
            i += run_len
        else:
            # Recoger literales hasta encontrar un run de 3+ o fin de datos
            lit_start = i
            while i < n:
                # Mirar si empieza un run de 3+
                if (i + 2 < n
                        and data[i] == data[i + 1] == data[i + 2]):
                    break
                i += 1
                if i - lit_start >= 127:
                    break  # max literal group size

            lit_count = i - lit_start
            # Control byte: count (1-127)
            result.append(lit_count)
            result.extend(data[lit_start:lit_start + lit_count])

    return result


def parse_defb_value(val):
    """Parsea un valor DEFB individual (hex $XX, binario %BBBBBBBB, decimal)."""
    val = val.strip()
    if val.startswith('$'):
        return int(val[1:], 16)
    elif val.startswith('%'):
        return int(val[1:], 2)
    elif val.startswith('0x') or val.startswith('0X'):
        return int(val, 16)
    else:
        return int(val)


def format_defb_line(values, per_line=16):
    """Formatea una lista de bytes como lineas DEFB $XX."""
    lines = []
    for i in range(0, len(values), per_line):
        chunk = values[i:i + per_line]
        hex_vals = ', '.join('${:02X}'.format(v) for v in chunk)
        lines.append('    DEFB ' + hex_vals)
    return '\n'.join(lines)


def verify_rle(original, encoded):
    """Decodifica RLE y verifica que produce los datos originales."""
    decoded = []
    i = 0
    while i < len(encoded):
        control = encoded[i]
        i += 1
        if control & 0x80:
            # Run
            count = (control & 0x7F) + 2
            value = encoded[i]
            i += 1
            decoded.extend([value] * count)
        else:
            # Literal group
            count = control
            decoded.extend(encoded[i:i + count])
            i += count

    if decoded != original:
        raise ValueError(
            'RLE verification failed! '
            'original={} bytes, decoded={} bytes'.format(
                len(original), len(decoded)))


def process_sprite_block(block_lines):
    """
    Procesa un bloque de sprite: extrae pixel data, comprime RLE,
    y retorna las lineas modificadas (o las originales si no comprime).

    Retorna: (new_lines, raw_size, rle_size, was_compressed)
    """
    # Encontrar la linea del header (height, width)
    header_idx = None
    header_match = None
    for i, line in enumerate(block_lines):
        m = re.match(r'^(\s*DEFB\s+)(\d+),\s*(\d+)(\s*;\s*height_px.*)', line)
        if m:
            header_idx = i
            header_match = m
            break

    if header_idx is None:
        return block_lines, 0, 0, False

    height = int(header_match.group(2))
    width = int(header_match.group(3))
    indent = header_match.group(1)
    comment = header_match.group(4)

    if height == 0 or width == 0:
        return block_lines, 0, 0, False

    expected_pixels = height * width

    # Extraer pixel data (lineas DEFB despues del header, hasta tintPaper)
    pixel_bytes = []
    pixel_start_idx = header_idx + 1
    pixel_end_idx = pixel_start_idx

    for i in range(pixel_start_idx, len(block_lines)):
        line = block_lines[i].strip()
        if 'tintPaper' in line:
            pixel_end_idx = i
            break
        m = re.match(r'DEFB\s+(.*?)(?:;|$)', line)
        if m:
            vals_str = m.group(1).strip().rstrip(',')
            for v in vals_str.split(','):
                v = v.strip()
                if v:
                    try:
                        pixel_bytes.append(parse_defb_value(v))
                    except ValueError:
                        # No es un numero, parar
                        pixel_end_idx = i
                        break
            else:
                continue
            break
    else:
        pixel_end_idx = len(block_lines)

    if len(pixel_bytes) != expected_pixels:
        # Datos no coinciden con header, no comprimir
        return block_lines, len(pixel_bytes), len(pixel_bytes), False

    # Comprimir con RLE
    rle_data = encode_rle(pixel_bytes)

    # Verificar integridad
    verify_rle(pixel_bytes, rle_data)

    raw_size = len(pixel_bytes)
    rle_size = len(rle_data)

    if rle_size >= raw_size:
        # No vale la pena comprimir
        return block_lines, raw_size, raw_size, False

    # Reconstruir el bloque con datos comprimidos
    new_lines = list(block_lines[:header_idx])

    # Header con flag RLE (bit 7 de width)
    new_width = width | 0x80
    new_lines.append('{}{}, {}{}'.format(indent, height, new_width, comment))

    # Datos RLE
    new_lines.append(format_defb_line(rle_data))

    # Resto del bloque (desde tintPaper en adelante)
    new_lines.extend(block_lines[pixel_end_idx:])

    return new_lines, raw_size, rle_size, True


def process_file(bg_gfx_path, dry_run):
    if not os.path.exists(bg_gfx_path):
        return 0  # archivo opcional (ej. bg_gfx_b.asm no existe antes de Stage C)

    with open(bg_gfx_path, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')

    # Encontrar los inicios de cada sprite (labels BgGfx_*)
    sprite_starts = []
    for i, line in enumerate(lines):
        m = re.match(r'^(BgGfx_\w+):', line)
        if m:
            sprite_starts.append((i, m.group(1)))

    # Dividir en bloques
    total_raw = 0
    total_rle = 0
    compressed_count = 0
    results = []

    new_lines = []
    prev_end = 0

    for si, (start_idx, name) in enumerate(sprite_starts):
        # Fin del bloque = inicio del siguiente sprite o fin del archivo
        if si + 1 < len(sprite_starts):
            end_idx = sprite_starts[si + 1][0]
        else:
            end_idx = len(lines)

        block = lines[start_idx:end_idx]

        # Copiar lineas entre bloques (antes de este sprite)
        new_lines.extend(lines[prev_end:start_idx])

        if name in EXCLUDE_SPRITES:
            new_lines.extend(block)
            prev_end = end_idx
            continue

        # Exclusion por patron de nombre (keys, locks, etc.)
        lower_name = name.lower()
        if any(pat in lower_name for pat in EXCLUDE_NAME_PATTERNS):
            new_lines.extend(block)
            prev_end = end_idx
            continue

        processed, raw, rle, was_compressed = process_sprite_block(block)
        new_lines.extend(processed)
        prev_end = end_idx

        total_raw += raw
        total_rle += rle
        if was_compressed:
            compressed_count += 1
            saved = raw - rle
            results.append((name, raw, rle, saved))

    # Lineas restantes despues del ultimo sprite
    new_lines.extend(lines[prev_end:])

    # Reportar resultados
    results.sort(key=lambda x: -x[3])
    print('=== BG Sprite RLE Compression (grouped-literal + run) ===')
    print('{:<30} {:>5} {:>5} {:>6}'.format('Sprite', 'Raw', 'RLE', 'Saved'))
    print('-' * 50)
    for name, raw, rle, saved in results:
        print('{:<30} {:>5} {:>5} {:>6}'.format(name, raw, rle, saved))
    print('-' * 50)
    total_saved = total_raw - total_rle
    print('{:<30} {:>5} {:>5} {:>6}'.format(
        'TOTAL ({} sprites)'.format(compressed_count),
        total_raw, total_rle, total_saved))
    print()

    if dry_run:
        print('[DRY RUN] No se modifico ningun archivo.')
    else:
        new_content = '\n'.join(new_lines)
        with open(bg_gfx_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print('Escrito: {}'.format(bg_gfx_path))
        print('Ahorro: {} bytes ({} sprites comprimidos)'.format(
            total_saved, compressed_count))
    return total_saved


def main():
    dry_run = '--dry-run' in sys.argv
    grand_total = 0
    for path in BG_GFX_PATHS:
        saved = process_file(path, dry_run)
        grand_total += saved
    if len(BG_GFX_PATHS) > 1:
        print('\n=== TOTAL entre ficheros: {} bytes ==='.format(grand_total))


if __name__ == '__main__':
    main()
