#!/usr/bin/env python3
"""
sync_bg_pickups.py - Sincroniza sprites code-referenced de bg_sprites.json
                     a bg_gfx*.asm sin requerir Export ASM del level editor.

USE CASE
--------
Tras modificar un pickup (o cualquier sprite en CODE_REF_IDS) en el BG
editor + click "Export All BG":
  - bg_sprites.json se actualiza con los nuevos pixelBytes/attrBytes.
  - bg_gfx.asm NO se toca (eso lo hace el level editor con Export ASM).

Este script cierra ese gap: lee bg_sprites.json y reescribe los bloques
DEFB de los sprites en CODE_REF_IDS dentro de bg_gfx*.asm. Tras cualquier
cambio real, ejecuta automaticamente compress_bg_rle.py para preservar la
compresion RLE de tamanno.

Es idempotente: si los datos en disco ya coinciden con el JSON (incluso
cuando estan RLE-comprimidos en el .asm), el script no toca ficheros ni
invoca el compresor. Para detectar coincidencia, decodifica el RLE del
.asm primero.

CODE_REF_IDS = sprites referenciados por label desde code/*.asm que
pueden o no estar pintados en salas. Lista replicada de
tools/level_editor.html (~line 8281). Mantener sincronizada cuando se
añadan/quiten refs en code/*.asm.

USO
---
    python tools/sync_bg_pickups.py            # aplica cambios + RLE recompress
    python tools/sync_bg_pickups.py --check    # exit 1 si haria cambios
                                               # (para git pre-commit hook)
    python tools/sync_bg_pickups.py --no-rle   # no recomprime tras escribir
                                               # (util si vas a commitear raw)

LIMITES
-------
* Solo actualiza sprites cuya definicion (`BgGfx_X:`) ya exista en
  bg_gfx*.asm. Si necesitas anadir sprites nuevos, usa el level editor.
* No toca aliases (`BgGfx_X EQU BgGfx_Y`). El alias hereda los datos del
  label primario, asi que actualizar el primario propaga el cambio.
* No reordena bancos. Si un sprite cambia de bioma (renombrado en BG
  editor), seguira en su bank actual; usa el level editor para mover.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG_JSON = ROOT / 'code' / 'bg_sprites.json'
BG_FILES = [
    ROOT / 'code' / 'bg_gfx.asm',
    ROOT / 'code' / 'bg_gfx_b.asm',
    ROOT / 'code' / 'bg_gfx_c.asm',
]
COMPRESS_SCRIPT = ROOT / 'tools' / 'compress_bg_rle.py'

# Sprites referenciados por label desde code/*.asm. Replicado de
# tools/level_editor.html (CODE_REF_IDS). Si añades/quitas refs en
# code/*.asm, sincroniza esta lista (ambos sitios).
CODE_REF_IDS = {
    12,   # BgGfx_well_pozo
    44,   # BgGfx_BankCheck
    54,   # BgGfx_bank_door_closed
    62,   # BgGfx_forestkey
    64,   # BgGfx_ruinskey
    65,   # BgGfx_cemeterykey
    66,   # BgGfx_clock_tower_key
    68,   # BgGfx_forestlock
    69,   # BgGfx_ruinslock
    70,   # BgGfx_forestlock_70
    71,   # BgGfx_cemeterylock
    186,  # BgGfx_town_gate_key
    191,  # BgGfx_church_key
    208,  # BgGfx_chimes_tower_door
    227,  # BgGfx_old_church_door_closed
    228,  # BgGfx_old_church_door_open
    230,  # BgGfx_ghost_remains
    231,  # BgGfx_skeleton_remains
    232,  # BgGfx_zombi_remains
    233,  # BgGfx_statue_ghost_braking
    234,  # BgGfx_statue_zombi_braking
    235,  # BgGfx_statue_skeleton_braking
    47,   # BgGfx_the_end_part1
    48,   # BgGfx_the_end_part2
    247,  # BgGfx_town_gate_v3_part1
    250,  # BgGfx_town_gate_door_open
    252,  # BgGfx_tomb
    253,  # BgGfx_lives
    13,   # BgGfx_life
    210,  # BgGfx_random_pickup
    254,  # BgGfx_health_pickup (variant 1)
    72,   # BgGfx_health_pickup_72 (variant 2, random alternation)
    74,   # BgGfx_health_pickup_3 (variant 3, random alternation)
    75,   # BgGfx_health_pickup_4 (variant 4, random alternation)
    255,  # BgGfx_stamina_pickup (variant 1)
    73,   # BgGfx_stamina_pickup_2 (variant 2, random alternation)
    28,   # BgGfx_pickup_ray
    29,   # BgGfx_pickup_snail
    33,   # BgGfx_pickup_mushroom
    34,   # BgGfx_pickup_compass
    37,   # BgGfx_compass_lasting
}


# -----------------------------------------------------------------------------
# RLE codec (espejo exacto de compress_bg_rle.py)
# Format: stream de chunks
#   $01-$7F: literal group, siguen <control> bytes raw
#   $80-$FF: run, count = (control & $7F) + 2 (rango 2..129), 1 byte valor
# Flag de compresion: bit 7 de width_bytes en el header del sprite.
# -----------------------------------------------------------------------------

def decode_rle(stream):
    """Decodifica un stream RLE en lista de bytes. No valida boundaries."""
    out = []
    i = 0
    n = len(stream)
    while i < n:
        ctrl = stream[i]; i += 1
        if ctrl <= 0x7F:
            out.extend(stream[i:i + ctrl])
            i += ctrl
        else:
            count = (ctrl & 0x7F) + 2
            if i >= n:
                break
            out.extend([stream[i]] * count)
            i += 1
    return out


# -----------------------------------------------------------------------------
# ASM block parsing
# -----------------------------------------------------------------------------

DEFB_LINE_RE = re.compile(r'^\s*DEFB\s+([^;\n]+)', re.MULTILINE)


def parse_defb_bytes(line):
    """Extrae lista de bytes de una linea DEFB. Maneja $XX y decimales."""
    out = []
    for tok in line.split(','):
        tok = tok.strip()
        if not tok:
            continue
        if tok.startswith('$'):
            out.append(int(tok[1:], 16))
        elif tok.startswith('0x') or tok.startswith('0X'):
            out.append(int(tok[2:], 16))
        else:
            out.append(int(tok))
    return out


def parse_block(content, sprite_id):
    """
    Localiza y parsea el bloque DEFB de `BgGfx_X:    ; BG<id> ...`.

    Devuelve dict {label, header_line_match, body_start, body_end,
                   h, width_bytes_raw, is_rle, pixel_bytes_decoded,
                   tint, attr_h, attr_w, attr_bytes} o None si no hay match.
    """
    # Matchea dos formatos de comentario:
    #   1. Generado por level editor:  BgGfx_X:    ; BG<id> · name · WxHpx
    #   2. Inyectado (inject_pickup_sprites.py): BgGfx_X:    ; INJECTED · id=<id> · ...
    bg_code = f'BG{sprite_id:02d}'
    id_eq = f'id={sprite_id}'
    header_re = re.compile(
        rf'^(BgGfx_\w+):([^\n]*(?:\b{re.escape(bg_code)}\b|{re.escape(id_eq)}\b)[^\n]*)\n',
        re.MULTILINE,
    )
    m = header_re.search(content)
    if not m:
        return None

    body_start = m.end()
    blank_re = re.compile(r'\n[ \t]*\n')
    end_m = blank_re.search(content, body_start)
    body_end = end_m.start() + 1 if end_m else len(content)

    body = content[body_start:body_end]
    defb_lines = DEFB_LINE_RE.findall(body)
    if len(defb_lines) < 4:
        return None

    # Linea 0: h, width_bytes_raw
    line0 = parse_defb_bytes(defb_lines[0])
    if len(line0) < 2:
        return None
    h = line0[0]
    width_bytes_raw = line0[1]
    is_rle = bool(width_bytes_raw & 0x80)
    width_bytes = width_bytes_raw & 0x7F

    # Buscar linea con tintPaper: tiene forma "DEFB N    ; tintPaper..."
    # En la lista DEFB_LINE_RE solo capturamos los bytes; usamos position en body.
    tint_idx = None
    for idx, line in enumerate(defb_lines):
        if 'tintPaper' in body.split('DEFB')[idx + 1].split('\n', 1)[0]:
            tint_idx = idx
            break
    # Fallback simple: tintPaper es una linea de 1 byte entre los pixel rows
    # y la linea attr_h/attr_w. Heuristica: la primera linea de 1 byte tras
    # la primera linea (header).
    if tint_idx is None:
        for idx in range(1, len(defb_lines)):
            vals = parse_defb_bytes(defb_lines[idx])
            if len(vals) == 1 and 0 <= vals[0] <= 255:
                # Verificar que la siguiente sea attr_h/attr_w (2 bytes pequeños)
                if idx + 1 < len(defb_lines):
                    nv = parse_defb_bytes(defb_lines[idx + 1])
                    if len(nv) == 2 and nv[0] <= 8 and nv[1] <= 8:
                        tint_idx = idx
                        break
    if tint_idx is None:
        return None

    # Pixel bytes: lineas 1..tint_idx-1 (concat)
    pixel_stream = []
    for idx in range(1, tint_idx):
        pixel_stream.extend(parse_defb_bytes(defb_lines[idx]))

    if is_rle:
        pixel_bytes_cpld = decode_rle(pixel_stream)
    else:
        pixel_bytes_cpld = pixel_stream
    # Datos en .asm estan CPL'd; devolver raw para comparar con JSON.
    pixel_bytes = [b ^ 0xFF for b in pixel_bytes_cpld]

    tint = parse_defb_bytes(defb_lines[tint_idx])[0]
    aw_line = parse_defb_bytes(defb_lines[tint_idx + 1])
    if len(aw_line) < 2:
        return None
    attr_h = aw_line[0]
    attr_w = aw_line[1]

    attr_bytes = []
    for idx in range(tint_idx + 2, len(defb_lines)):
        attr_bytes.extend(parse_defb_bytes(defb_lines[idx]))

    return {
        'label': m.group(1),
        'header_match_start': m.start(),
        'header_match_end': m.end(),
        'body_start': body_start,
        'body_end': body_end,
        'h': h,
        'width_bytes': width_bytes,
        'is_rle': is_rle,
        'pixel_bytes': pixel_bytes,
        'tint': tint,
        'attr_h': attr_h,
        'attr_w': attr_w,
        'attr_bytes': attr_bytes,
    }


# -----------------------------------------------------------------------------
# Emit raw block (sin RLE; compress_bg_rle.py se ocupa despues)
# -----------------------------------------------------------------------------

def emit_block_raw(sp):
    """Genera el cuerpo DEFB raw espejo de generateBgGfxAsm (level editor)."""
    pixels = sp['pixelBytes']
    attrs = sp['attrBytes']
    h = sp['h']
    w = sp['w']
    width_bytes = max(1, w // 8)
    attr_h = (h + 7) // 8
    attr_w = (w + 7) // 8
    cpl = [b ^ 0xFF for b in pixels]
    tint = sp.get('tintPaper', 255)

    lines = []
    lines.append(f'    DEFB {h}, {width_bytes}    ; height_px, width_bytes')
    for i in range(0, len(cpl), width_bytes):
        row = cpl[i:i + width_bytes]
        lines.append('    DEFB ' + ', '.join(f'${b:02X}' for b in row))
    lines.append(f'    DEFB {tint}    ; tintPaper (255=none)')
    lines.append(f'    DEFB {attr_h}, {attr_w}    ; attr_h, attr_w')
    for i in range(0, len(attrs), attr_w):
        row = attrs[i:i + attr_w]
        lines.append('    DEFB ' + ', '.join(f'${b:02X}' for b in row))
    return '\n'.join(lines) + '\n'


# -----------------------------------------------------------------------------
# Diff y patch
# -----------------------------------------------------------------------------

def sprite_matches(parsed, json_sp):
    """Compara datos parseados del .asm con los del JSON. RLE-aware."""
    if parsed['h'] != json_sp['h']:
        return False
    if parsed['width_bytes'] != max(1, json_sp['w'] // 8):
        return False
    if parsed['pixel_bytes'] != json_sp['pixelBytes']:
        return False
    if parsed['tint'] != json_sp.get('tintPaper', 255):
        return False
    if parsed['attr_bytes'] != json_sp['attrBytes']:
        return False
    return True


def patch_file(content, parsed, new_body):
    return content[:parsed['body_start']] + new_body + content[parsed['body_end']:]


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def load_json_sprites():
    raw = json.loads(BG_JSON.read_text(encoding='utf-8'))
    if isinstance(raw, dict):
        return {s['id']: s for s in raw.get('sprites', [])}
    if isinstance(raw, list):
        return {s['id']: s for s in raw}
    return {}


# Regex que captura sprite ids ya emitidos en bg_gfx*.asm:
#   - "; BG<id>" del level editor (acepta opcionalmente espacios)
#   - "; INJECTED ... id=<id>" del inject_pickup_sprites.py
_ASM_SPRITE_ID_RE = re.compile(
    r'^BgGfx_\w+:[^\n]*?(?:\bBG(\d+)\b|\bid=(\d+)\b)',
    re.MULTILINE,
)


def discover_asm_sprite_ids(file_contents):
    """Devuelve set de IDs presentes como definicion BgGfx_X: en cualquier
    bg_gfx*.asm. Esto incluye TODOS los sprites que el level editor's
    Export ASM emitio (placed o CODE_REF) y los inyectados por inject."""
    ids = set()
    for content in file_contents.values():
        for m in _ASM_SPRITE_ID_RE.finditer(content):
            sid_str = m.group(1) or m.group(2)
            if sid_str:
                ids.add(int(sid_str))
    return ids


def main(argv):
    check_only = '--check' in argv
    skip_rle = '--no-rle' in argv

    if not BG_JSON.exists():
        print(f'ERROR: {BG_JSON} no existe', file=sys.stderr)
        return 2

    sprites = load_json_sprites()

    changed = []
    not_found = []
    missing_json = []
    in_sync = []

    file_contents = {fp: fp.read_text(encoding='utf-8') for fp in BG_FILES if fp.exists()}

    # Auto-descubre todos los sprites que YA estan en bg_gfx*.asm.
    # Union con CODE_REF_IDS (para warnings de "missing in asm").
    asm_ids = discover_asm_sprite_ids(file_contents)
    target_ids = sorted(CODE_REF_IDS | asm_ids)

    for sid in target_ids:
        sp = sprites.get(sid)
        if not sp:
            missing_json.append(sid)
            continue

        # Buscar en cualquiera de los bg_gfx*.asm
        target_fp = None
        parsed = None
        for fp, content in file_contents.items():
            p = parse_block(content, sid)
            if p:
                target_fp = fp
                parsed = p
                break

        if not target_fp:
            not_found.append(sid)
            continue

        if sprite_matches(parsed, sp):
            in_sync.append((sid, sp.get('name', '?')))
            continue

        # Hay diff -> generar bloque raw, patchear (preservando header line)
        new_body = emit_block_raw(sp)
        new_content = patch_file(file_contents[target_fp], parsed, new_body)
        file_contents[target_fp] = new_content
        changed.append((sid, target_fp.name, sp.get('name', '?'), parsed['is_rle']))

    if check_only:
        if changed:
            print(f'[sync_bg_pickups --check] {len(changed)} sprite(s) fuera de sync:')
            for sid, fname, name, was_rle in changed:
                rle_tag = ' [RLE]' if was_rle else ''
                print(f'  id={sid:3d} ({name}){rle_tag} -> {fname}')
            print('  Ejecuta `python tools/sync_bg_pickups.py` para aplicar.')
            return 1
        print(f'[sync_bg_pickups --check] OK: bg_gfx*.asm en sync con bg_sprites.json '
              f'({len(in_sync)} sprite(s) revisados)')
        if not_found:
            print(f'  warning: {len(not_found)} id(s) sin definicion: {not_found}')
        if missing_json:
            print(f'  warning: {len(missing_json)} id(s) ausentes en JSON: {missing_json}')
        return 0

    # Aplicar cambios a disco
    for fp, content in file_contents.items():
        original = fp.read_text(encoding='utf-8')
        if content != original:
            fp.write_text(content, encoding='utf-8')

    if changed:
        print(f'[sync_bg_pickups] {len(changed)} sprite(s) actualizado(s) (raw, sin RLE):')
        for sid, fname, name, was_rle in changed:
            rle_tag = ' [era RLE]' if was_rle else ''
            print(f'  id={sid:3d} ({name}){rle_tag} -> {fname}')

        # Re-aplicar compresion RLE para no perder bytes (level editor emite raw,
        # compress_bg_rle.py es el segundo paso normal de su pipeline).
        if not skip_rle and COMPRESS_SCRIPT.exists():
            print(f'\n[sync_bg_pickups] re-aplicando RLE via {COMPRESS_SCRIPT.name}...')
            r = subprocess.run([sys.executable, str(COMPRESS_SCRIPT)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print(f'WARNING: compress_bg_rle.py fallo (exit {r.returncode}):')
                print(r.stdout)
                print(r.stderr, file=sys.stderr)
            else:
                # Filtrar output a los headers (no spammear). Los detalles ya estan
                # en el script de compresion.
                tail = r.stdout.strip().splitlines()[-3:]
                for ln in tail:
                    print(f'  {ln}')
    else:
        print(f'[sync_bg_pickups] nada que hacer ({len(in_sync)} sprite(s) ya en sync)')

    if not_found:
        print(f'\nWARNING: {len(not_found)} id(s) en CODE_REF_IDS sin definicion en bg_gfx*.asm:')
        print(f'  {not_found}')
        print('  Si son sprites nuevos, usa el level editor (Export ASM) para crearlos.')
    if missing_json:
        print(f'\nWARNING: {len(missing_json)} id(s) en CODE_REF_IDS no presentes en bg_sprites.json:')
        print(f'  {missing_json}')

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
