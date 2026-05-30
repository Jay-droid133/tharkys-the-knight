#!/usr/bin/env python3
"""
asm_to_json_sprite.py - Recupera sprites compilados en bg_gfx*.asm de vuelta
a bg_sprites.json (la fuente del editor).

Caso de uso: dibujaste un sprite en el editor, se exportó al .asm (commit),
pero por algún motivo se perdió de la JSON / IndexedDB del editor (típicamente
porque te saltaste "Export All BG" o porque la heurística de poda del export
lo descartó al no estar placado en ningún room). Si los bytes siguen vivos en
el .asm (o en git HEAD), este script los reconstruye en la JSON.

  Descomprime el RLE del editor (compress_bg_rle.py):
    Control $01-$7F: literal group, siguen `control` bytes raw.
    Control $80-$FF: run, count = (control & $7F) + 2, sigue 1 byte valor.
    Bit 7 de width_bytes en el header indica si los datos están comprimidos.

  Formato del bloque sprite en el .asm:
    LABEL:    ; BG<id> · <name> · <w>×<h>px
        DEFB <h_px>, <wb_or_wb|0x80>     ; header pixels
        DEFB <pixel data ...>            ; RLE o raw, según bit 7
        DEFB <tint_paper>                ; 0..7 = color, 255 = none
        DEFB <attr_h>, <attr_w>          ; header attrs (en chars)
        DEFB <attr data ...>             ; raw

Uso:
    python tools/asm_to_json_sprite.py castle_part1 castle_part2 castle_part3 castle_part4
    python tools/asm_to_json_sprite.py --dry-run castle_part1
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG_GFX_FILES = [
    os.path.join(ROOT, 'code', 'bg_gfx.asm'),
    os.path.join(ROOT, 'code', 'bg_gfx_b.asm'),
]
JSON_PATH = os.path.join(ROOT, 'code', 'bg_sprites.json')


def parse_defb(val):
    val = val.strip()
    if val.startswith('$'):
        return int(val[1:], 16)
    if val.startswith('%'):
        return int(val[1:], 2)
    return int(val)


def find_label_block(asm_text, label):
    """Devuelve (sprite_id, name, w, h, raw_bytes_list) o lanza."""
    pat = re.compile(
        rf'^BgGfx_{re.escape(label)}:\s*;\s*BG(\d+)\s*[·•]\s*(.+?)\s*[·•]\s*(\d+)×(\d+)px\s*\n'
        rf'((?:[ \t]*DEFB[^\n]*\n)+)',
        re.MULTILINE
    )
    m = pat.search(asm_text)
    if not m:
        raise ValueError(f'Label BgGfx_{label} no encontrado')
    sid = int(m.group(1))
    name = m.group(2).strip()
    w = int(m.group(3))
    h = int(m.group(4))
    body = m.group(5)
    # Recoger todos los valores DEFB del bloque, en orden
    bytes_out = []
    for line in body.split('\n'):
        line = re.sub(r';.*', '', line)  # tirar comentarios
        m2 = re.match(r'[ \t]*DEFB\s+(.+)', line)
        if not m2:
            continue
        for v in m2.group(1).split(','):
            v = v.strip()
            if not v:
                continue
            bytes_out.append(parse_defb(v))
    return sid, name, w, h, bytes_out


def decompress_rle(data, out_len):
    """Decodifica el stream RLE de compress_bg_rle.py al tamaño esperado."""
    out = []
    i = 0
    while i < len(data) and len(out) < out_len:
        ctrl = data[i]
        i += 1
        if ctrl & 0x80:
            count = (ctrl & 0x7F) + 2
            if i >= len(data):
                raise ValueError('RLE truncado: falta value tras run control')
            value = data[i]
            i += 1
            out.extend([value] * count)
        else:
            if ctrl == 0:
                raise ValueError('Control byte 0 invalido en RLE')
            if i + ctrl > len(data):
                raise ValueError('RLE truncado: literal pasa del fin del stream')
            out.extend(data[i:i + ctrl])
            i += ctrl
    if len(out) != out_len:
        raise ValueError(f'Decompress length mismatch: got {len(out)}, expected {out_len}')
    return out, i  # devolver tambien bytes consumidos del stream


def extract_sprite(asm_text, label):
    """Extrae un sprite del .asm a la estructura JSON del editor."""
    sid, name, w, h, raw = find_label_block(asm_text, label)
    if len(raw) < 2:
        raise ValueError('bloque DEFB demasiado corto')
    h_hdr = raw[0]
    wb_hdr = raw[1]
    rle = bool(wb_hdr & 0x80)
    wb = wb_hdr & 0x7F
    if h_hdr != h:
        print(f'  warning: header h={h_hdr} != comment h={h}', file=sys.stderr)
    if wb * 8 != w:
        print(f'  warning: header wb*8={wb*8} != comment w={w}', file=sys.stderr)
    pixel_size = wb * h     # bytes
    stream = raw[2:]
    if rle:
        pixels, consumed = decompress_rle(stream, pixel_size)
    else:
        if len(stream) < pixel_size:
            raise ValueError('pixel data raw demasiado corta')
        pixels = stream[:pixel_size]
        consumed = pixel_size
    rest = stream[consumed:]
    if len(rest) < 3:
        raise ValueError('faltan bytes tras pixel data (tintPaper + attr header esperado)')
    tint_paper = rest[0]
    attr_h = rest[1]
    attr_w = rest[2]
    attr_bytes_count = attr_h * attr_w
    if len(rest) < 3 + attr_bytes_count:
        raise ValueError(f'attrBytes truncado: necesito {attr_bytes_count}, hay {len(rest)-3}')
    attr_bytes = rest[3:3 + attr_bytes_count]
    sprite = {
        'id': sid,
        'w': w,
        'h': h,
        'name': name,
        'pixelBytes': pixels,
        'attrBytes': attr_bytes,
    }
    if tint_paper != 255:
        sprite['tintPaper'] = tint_paper
    return sprite


def main():
    argv = sys.argv[1:]
    dry_run = False
    if argv and argv[0] == '--dry-run':
        dry_run = True
        argv = argv[1:]
    if not argv:
        print('Uso: python tools/asm_to_json_sprite.py [--dry-run] LABEL [LABEL2 ...]')
        print('Ejemplo: python tools/asm_to_json_sprite.py castle_part1 castle_part2 castle_part3 castle_part4')
        return 1

    # Cargar TODO el asm en un buffer (los 2 ficheros)
    asm_text = ''
    for p in BG_GFX_FILES:
        if os.path.exists(p):
            with open(p, encoding='utf-8') as f:
                asm_text += f.read() + '\n'

    js = json.load(open(JSON_PATH, encoding='utf-8'))
    sprites = js['sprites']
    by_id = {s['id']: i for i, s in enumerate(sprites)}
    bg_names = js.setdefault('bgNames', [])

    added = updated = 0
    for label in argv:
        try:
            sprite = extract_sprite(asm_text, label)
        except Exception as e:
            print(f'  ERROR {label}: {e}', file=sys.stderr)
            return 2
        sid = sprite['id']
        action = 'update' if sid in by_id else 'add'
        if dry_run:
            print(f'  [{action}] id={sid} {sprite["name"]!r} w={sprite["w"]} h={sprite["h"]} '
                  f'pixelBytes={len(sprite["pixelBytes"])} attrBytes={len(sprite["attrBytes"])} '
                  f'tintPaper={sprite.get("tintPaper", "none")}')
            continue
        if sid in by_id:
            sprites[by_id[sid]] = sprite
            updated += 1
        else:
            sprites.append(sprite)
            by_id[sid] = len(sprites) - 1
            added += 1
        # Mantener bgNames sincronizada (lista por id; expandir con strings vacíos)
        while len(bg_names) <= sid:
            bg_names.append('')
        bg_names[sid] = sprite['name']
        print(f'  [{action}] id={sid} {sprite["name"]!r}')

    if dry_run:
        print('(dry-run, no se escribió nada)')
        return 0

    # Reordenar sprites por id para mantener orden canónico (estilo editor)
    sprites.sort(key=lambda s: s['id'])

    with open(JSON_PATH, 'w', encoding='utf-8') as f:
        json.dump(js, f, ensure_ascii=False, separators=(',', ':'))
    print(f'\n  bg_sprites.json: +{added} added, {updated} updated')
    return 0


if __name__ == '__main__':
    sys.exit(main())
