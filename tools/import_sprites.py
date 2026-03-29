#!/usr/bin/env python3
"""
import_sprites.py - Importa sprites de Aseprite a sprite_data.asm

Uso:
    python tools/import_sprites.py <archivo.aseprite>

Requisitos:
    - pip install Pillow
    - Aseprite instalado en la ruta de ASEPRITE abajo

Los tags del .aseprite definen qué se importa. Tags conocidos (case-insensitive):
    idle, move east, move west, move north, move south, fight east, fight west

Cualquier otro tag se convierte automáticamente:
    "jump left" -> SprJumpLeft  /  SPRID_JUMP_LEFT

Para animaciones nuevas, el script avisa qué añadir manualmente en logic_game.asm.
"""

import sys, os, re, json, subprocess
from PIL import Image

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ASEPRITE    = r"C:\Program Files\Aseprite\aseprite.exe"
SPRITE_DATA = r"c:\NUEVO_JUEGO\code\sprite_data.asm"

# Tags conocidos -> prefijo ASM ya existente
TAG_MAP = {
    "idle":       "SprIdle",
    "move east":  "SprWalkE",  "walk east":  "SprWalkE",
    "move west":  "SprWalkW",  "walk west":  "SprWalkW",
    "move north": "SprWalkN",  "walk north": "SprWalkN",
    "move south": "SprWalkS",  "walk south": "SprWalkS",
    "fight east": "SprFightE",
    "fight west": "SprFightW",
}

# ---------------------------------------------------------------------------
# Helpers de nomenclatura — funcionan con cualquier prefijo
# ---------------------------------------------------------------------------
def tag_to_prefix(name):
    """'move east' -> 'SprWalkE'  /  'jump left' -> 'SprJumpLeft'"""
    if name in TAG_MAP:
        return TAG_MAP[name]
    return "Spr" + "".join(w.title() for w in name.split())

def prefix_to_sprid(prefix):
    """'SprWalkE' -> 'SPRID_WALK_E'  /  'SprJumpLeft' -> 'SPRID_JUMP_LEFT'"""
    name = prefix[3:]                                    # quita 'Spr'
    snake = re.sub(r'([A-Z])', r'_\1', name).lstrip('_').upper()
    return f"SPRID_{snake}"

# ---------------------------------------------------------------------------
# Exportar Aseprite -> spritesheet PNG + JSON
# ---------------------------------------------------------------------------
def export_aseprite(aseprite_path, tmp_dir):
    sheet_png  = os.path.join(tmp_dir, "sheet.png")
    sheet_json = os.path.join(tmp_dir, "sheet.json")
    r = subprocess.run([
        ASEPRITE, "--batch", aseprite_path,
        "--sheet", sheet_png, "--sheet-type", "rows",
        "--data",  sheet_json, "--format", "json-array",
        "--list-tags",
    ], capture_output=True, text=True)
    if r.returncode != 0:
        print("Error Aseprite:", r.stderr); sys.exit(1)
    return sheet_png, sheet_json

# ---------------------------------------------------------------------------
# Pixel helpers
# ---------------------------------------------------------------------------
def frame_pixels(img, fi):
    fx, fy, fw, fh = fi['x'], fi['y'], fi['w'], fi['h']
    return [img.getpixel((fx+x, fy+y)) for y in range(fh) for x in range(fw)]

def is_bounce(pxlist):
    """True si el último frame == segundo frame (patrón 0,1,2,1)."""
    return len(pxlist) >= 3 and pxlist[-1] == pxlist[1]

def frame_to_defb(img, fi, label):
    fx, fy, fw, fh = fi['x'], fi['y'], fi['w'], fi['h']
    wb = fw // 8
    lines = [f"{label}:", f"    DEFB {wb}, {fh}"]
    for y in range(fh):
        row = []
        for b in range(wb):
            byte = 0
            for bit in range(8):
                if img.getpixel((fx + b*8 + bit, fy + y)) != 0:
                    byte |= (1 << (7 - bit))
            row.append(f"%{byte:08b}")
        lines.append(f"    DEFB {', '.join(row)}")
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Leer estado actual del ASM
# ---------------------------------------------------------------------------
def read_anim_order(content):
    """Lee el orden de animaciones de los labels SprXxx0: en el ASM."""
    return re.findall(r'^(Spr\w+?)0:', content, re.MULTILINE)

def read_table_counts(content, anim_order):
    """Devuelve {prefix: count} leyendo la SpriteFrameTable."""
    counts = {}
    m = re.search(r'SpriteFrameTable:(.*)', content, re.DOTALL)
    if not m:
        return counts
    table = m.group(1)
    for prefix in anim_order:
        dm = re.search(rf'DEFW\s+((?:{re.escape(prefix)}\w+,?\s*)+)', table)
        if dm:
            counts[prefix] = len(re.findall(rf'{re.escape(prefix)}\w+', dm.group(0)))
    return counts

# ---------------------------------------------------------------------------
# Escribir/insertar bloques en el ASM
# ---------------------------------------------------------------------------
def upsert_sprite_block(content, prefix, defb_text, is_new):
    """Reemplaza el bloque existente o inserta uno nuevo antes de SpriteFrameTable."""
    if not is_new:
        pat = re.compile(
            rf'({re.escape(prefix)}0:.*?)(?=\n; ===|\nSpriteFrameTable)',
            re.DOTALL
        )
        m = pat.search(content)
        if m:
            return content[:m.start()] + defb_text + content[m.end():]
        print(f"  AVISO: no encontré '{prefix}0:' — tratando como nueva animación")

    # Insertar antes de SpriteFrameTable
    idx = content.find('\nSpriteFrameTable:')
    if idx == -1:
        idx = len(content)
    anim_name = prefix[3:]  # quita 'Spr'
    section = (
        f"\n\n; {'='*78}\n"
        f"; {anim_name.upper()} - Nueva animación\n"
        f"; {'='*78}\n"
        f"{defb_text}\n"
    )
    return content[:idx] + section + content[idx:]

def upsert_sprid_equ(content, sprid, value):
    """Reemplaza el EQU existente o inserta uno nuevo junto a los demás SPRID_."""
    pat = rf'{re.escape(sprid)}\s+EQU\s+\d+'
    new_line = f'{sprid:<16} EQU {value}'
    if re.search(pat, content):
        return re.sub(pat, new_line, content)
    # Insertar después del último SPRID_ EQU existente
    last = None
    for m in re.finditer(r'SPRID_\w+\s+EQU\s+\d+', content):
        last = m
    if last:
        return content[:last.end()] + f'\n{new_line}' + content[last.end():]
    return content + f'\n{new_line}\n'

# ---------------------------------------------------------------------------
# Reconstruir tabla y EQUs
# ---------------------------------------------------------------------------
def rebuild(content, anim_order, anim_sizes):
    """
    Recalcula SPRID_ EQUs y SpriteFrameTable.
    anim_sizes: {prefix: (num_unique, bounce)}
    """
    running = 0
    for prefix in anim_order:
        num_unique, bounce = anim_sizes.get(prefix, (0, False))
        total = num_unique + (1 if bounce else 0)
        if total == 0:
            continue
        content = upsert_sprid_equ(content, prefix_to_sprid(prefix), running)
        running += total

    # SpriteFrameTable
    table_lines = ["SpriteFrameTable:"]
    running = 0
    for prefix in anim_order:
        num_unique, bounce = anim_sizes.get(prefix, (0, False))
        total = num_unique + (1 if bounce else 0)
        if total == 0:
            continue
        labels = [f"{prefix}{i}" for i in range(num_unique)]
        if bounce:
            labels.append(f"{prefix}1")
        end_id = running + total - 1
        suffix = " (0,1,2,1)" if bounce else ""
        table_lines.append(f"    ; SpriteID {running}-{end_id}: {prefix[3:]}{suffix}")
        table_lines.append(f"    DEFW {', '.join(labels)}")
        running += total

    content = re.sub(
        r'SpriteFrameTable:.*', "\n".join(table_lines),
        content, flags=re.DOTALL
    )
    return content

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        print("Uso: python tools/import_sprites.py <archivo.aseprite>")
        sys.exit(1)

    path = sys.argv[1]
    if not os.path.exists(path):
        print(f"No encuentro: {path}"); sys.exit(1)

    print(f"Procesando: {path}\n")

    export_dir = os.path.join(os.path.dirname(SPRITE_DATA), "..", "References", "export")
    os.makedirs(export_dir, exist_ok=True)
    sheet_png, sheet_json = export_aseprite(path, export_dir)
    img  = Image.open(sheet_png)
    meta = json.load(open(sheet_json))

    frames = meta['frames']
    tags   = meta['meta'].get('frameTags', [])
    if not tags:
        print("ERROR: el archivo no tiene tags. Añade tags en Aseprite."); sys.exit(1)

    content    = open(SPRITE_DATA, encoding='utf-8').read()
    anim_order = read_anim_order(content)
    anim_sizes = {p: (n, False) for p, n in read_table_counts(content, anim_order).items()}

    new_animations = []

    for tag in tags:
        name   = tag['name'].lower().strip()
        prefix = tag_to_prefix(name)
        is_new = prefix not in anim_order

        tag_frames  = frames[tag['from']:tag['to']+1]
        pxlist      = [frame_pixels(img, f['frame']) for f in tag_frames]
        bounce      = is_bounce(pxlist)
        num_unique  = len(tag_frames) - (1 if bounce else 0)

        defb_blocks = [
            frame_to_defb(img, tag_frames[i]['frame'], f"{prefix}{i}")
            for i in range(num_unique)
        ]
        defb_text = "\n\n".join(defb_blocks)

        content = upsert_sprite_block(content, prefix, defb_text, is_new)

        if is_new:
            anim_order.append(prefix)
            new_animations.append(prefix)

        anim_sizes[prefix] = (num_unique, bounce)

        status     = "NUEVA" if is_new else "actualizada"
        bounce_str = " -> bounce 0,1,2,1" if bounce else ""
        print(f"  [{status}] {tag['name']} -> {prefix} ({num_unique} frames{bounce_str})")

    content = rebuild(content, anim_order, anim_sizes)

    with open(SPRITE_DATA, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"\nActualizado: {SPRITE_DATA}")

    if new_animations:
        print("\n*** ANIMACIONES NUEVAS — editar manualmente logic_game.asm ***")
        for prefix in new_animations:
            sprid = prefix_to_sprid(prefix)
            print(f"  - Añadir caso para {sprid} en UpdatePlayerAnim")

if __name__ == "__main__":
    main()
