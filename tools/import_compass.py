#!/usr/bin/env python3
"""
import_compass.py - Importa sprites de la brujula desde PNGs a milestones.asm

Lee `References/export/flecha_0.png` ... `flecha_7.png` (16x16 cada uno)
y reemplaza los DEFB de los 8 sprites direccionales en `code/milestones.asm`.
La X (`Sprite_Compass_X`) NO se toca — se mantiene tal como esta.

Convencion del orden de frames en Aseprite (sentido horario desde N = 12h):
    frame 0 = N
    frame 1 = NE
    frame 2 = E
    frame 3 = SE
    frame 4 = S
    frame 5 = SW
    frame 6 = W
    frame 7 = NW

La conversion es 1-bit: cualquier pixel con alpha > 128 cuenta como
"encendido" (bit = 1). El color se pierde — el HUD de la brujula colorea
en runtime via attrs (blanco / verde / rojo).

Formato de salida (igual que el actual en milestones.asm):
    Sprite_Compass_N:
        DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
        DEFB $61,$86, $63,$C6, $C7,$E3, $CF,$F3
        DEFB $C1,$83, $C1,$83, $61,$86, $61,$86
        DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Uso:
    # 1. Si los PNGs ya estan exportados en References/export/:
    python tools/import_compass.py

    # 2. Si tienes solo el .aseprite y quieres que exporte y luego importe:
    python tools/import_compass.py References/flechas03-...aseprite

Requisitos:
    - pip install Pillow
    - Aseprite instalado en ASEPRITE_EXE (solo si pasas .aseprite)
"""

import os
import re
import subprocess
import sys
from PIL import Image

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORT_DIR = os.path.join(ROOT, "References", "export")
MILESTONES = os.path.join(ROOT, "code", "milestones.asm")
ASEPRITE_EXE = r"C:\Program Files\Aseprite\aseprite.exe"

# Mapeo: frame index en aseprite (sentido horario desde N) -> label ASM.
# Las labels coinciden con las que ya existen en milestones.asm.
FRAME_TO_LABEL = [
    "Sprite_Compass_N",   # 0  N  (12h)
    "Sprite_Compass_NE",  # 1  NE (1:30)
    "Sprite_Compass_E",   # 2  E  (3h)
    "Sprite_Compass_SE",  # 3  SE (4:30)
    "Sprite_Compass_S",   # 4  S  (6h)
    "Sprite_Compass_SW",  # 5  SW (7:30)
    "Sprite_Compass_W",   # 6  W  (9h)
    "Sprite_Compass_NW",  # 7  NW (10:30)
]

SPRITE_W = 16
SPRITE_H = 16
ALPHA_THRESHOLD = 128  # >  threshold -> pixel "encendido"


# ---------------------------------------------------------------------------
# PIL image -> bytes (16 filas x 2 bytes = 32 bytes)
# ---------------------------------------------------------------------------
def img_to_bytes(img, x_offset=0):
    """
    Convierte un area 16x16 de un PIL Image (modo RGBA) a 32 bytes.
    x_offset permite leer un sprite concreto dentro de un strip horizontal
    (e.g. para slicing de un sheet 128x16: x_offset 0, 16, 32, ..., 112).

    Regla de "pixel encendido":
        alpha > ALPHA_THRESHOLD  AND  RGB != (0,0,0)

    Esto soporta dos workflows del usuario:
      A) PNG con fondo transparente -> alpha=0 fuera del sprite -> apagado.
      B) PNG con fondo NEGRO opaco (default Aseprite si hay layer Background)
         -> alpha=255 pero RGB=(0,0,0) -> apagado.
    En ambos casos los pixels coloreados (rojo de la esfera, etc.) se
    encienden. El color se pierde al ser 1-bit; el HUD lo aplica via attrs.
    """
    pixels = img.load()
    rows = []
    for y in range(SPRITE_H):
        bytes_in_row = []
        for byte_x in range(SPRITE_W // 8):
            byte = 0
            for bit in range(8):
                x = x_offset + byte_x * 8 + bit
                r, g, b, a = pixels[x, y]
                if a > ALPHA_THRESHOLD and (r | g | b) != 0:
                    byte |= (1 << (7 - bit))
            bytes_in_row.append(byte)
        rows.append(bytes_in_row)
    return rows  # [[byte_left, byte_right], ...] x 16


def png_to_bytes(path):
    """Lee un PNG 16x16 mono -> 32 bytes."""
    img = Image.open(path).convert("RGBA")
    if img.size != (SPRITE_W, SPRITE_H):
        raise ValueError(
            f"{os.path.basename(path)}: esperado {SPRITE_W}x{SPRITE_H}, "
            f"recibido {img.size[0]}x{img.size[1]}"
        )
    return img_to_bytes(img)


def strip_to_bytes_list(path, n_frames):
    """
    Lee un PNG strip horizontal (n_frames x 16, alto 16) y devuelve una
    lista de N x 32 bytes (uno por frame).
    """
    img = Image.open(path).convert("RGBA")
    expected = (SPRITE_W * n_frames, SPRITE_H)
    if img.size != expected:
        raise ValueError(
            f"{os.path.basename(path)}: esperado strip {expected[0]}x{expected[1]} "
            f"({n_frames} frames de {SPRITE_W}x{SPRITE_H}), "
            f"recibido {img.size[0]}x{img.size[1]}"
        )
    return [img_to_bytes(img, x_offset=i * SPRITE_W) for i in range(n_frames)]


# ---------------------------------------------------------------------------
# bytes -> bloque ASM (4 lineas DEFB)
# ---------------------------------------------------------------------------
def rows_to_defb_block(label, rows, comment=None):
    """
    rows: list[16] of [byte_left, byte_right]
    Output:
        Sprite_Compass_N:
            DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
            DEFB ...
            DEFB ...
            DEFB ...
    (4 filas por linea, sin trailing newline)
    """
    out = []
    if comment:
        out.append(f"; {comment}")
    out.append(f"{label}:")
    for chunk_start in range(0, 16, 4):
        chunk = rows[chunk_start:chunk_start + 4]
        defb = "    DEFB " + ", ".join(
            f"${row[0]:02X},${row[1]:02X}" for row in chunk
        )
        out.append(defb)
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Replace existing DEFB block en milestones.asm
# ---------------------------------------------------------------------------
def replace_sprite_block(asm_text, label, new_block):
    """
    Encuentra el bloque actual:
        <label>:
            DEFB ...
            DEFB ...
            DEFB ...
            DEFB ...
    y lo reemplaza con new_block. Asume 4 lineas DEFB tras el label, que
    es como estan los Sprite_Compass_* hoy.
    """
    pattern = re.compile(
        r"^" + re.escape(label) + r":\s*\n"
        r"(?:[ \t]*DEFB[^\n]*\n){4}",
        flags=re.MULTILINE,
    )
    m = pattern.search(asm_text)
    if not m:
        raise RuntimeError(
            f"No se encontro el bloque de '{label}' (4 lineas DEFB tras label) "
            f"en milestones.asm. Comprueba que el formato sigue intacto."
        )
    # new_block ya tiene formato "<label>:\n    DEFB ...\n    DEFB ...\n    DEFB ...\n    DEFB ..."
    # Hay que conservar el newline final que tenia el bloque original.
    return asm_text[: m.start()] + new_block + "\n" + asm_text[m.end():]


# ---------------------------------------------------------------------------
# Aseprite -> PNGs (uno por frame en EXPORT_DIR/flecha_<N>.png)
# ---------------------------------------------------------------------------
def export_aseprite_frames(aseprite_path):
    """
    Lanza Aseprite CLI con --save-as <dir>/flecha_{frame}.png para volcar cada
    frame como PNG separado. Aseprite expande {frame} a 0,1,2,...
    """
    if not os.path.isfile(ASEPRITE_EXE):
        print(f"[ERR] Aseprite no encontrado en {ASEPRITE_EXE}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(aseprite_path):
        print(f"[ERR] No existe {aseprite_path}", file=sys.stderr)
        sys.exit(1)
    os.makedirs(EXPORT_DIR, exist_ok=True)
    out_pattern = os.path.join(EXPORT_DIR, "flecha_{frame}.png")
    cmd = [
        ASEPRITE_EXE, "-b",
        aseprite_path,
        "--save-as", out_pattern,
    ]
    print(f"  Aseprite -> {out_pattern}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[ERR] Aseprite CLI fallo:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    # 0. Si pasan un .aseprite como argumento, exportar PNGs primero.
    if len(sys.argv) > 1:
        aseprite_path = sys.argv[1]
        if not aseprite_path.lower().endswith(".aseprite"):
            print(f"[ERR] Argumento debe ser .aseprite: {aseprite_path}",
                  file=sys.stderr)
            sys.exit(1)
        export_aseprite_frames(aseprite_path)

    # 1. Cargar PNGs. Soportamos dos formatos:
    #    A) flecha_0.png ... flecha_7.png cada uno 16x16.
    #    B) flecha_0.png como un strip horizontal de N frames (16*N x 16) y
    #       el resto inexistente. Es lo que sale del export por defecto de
    #       Aseprite cuando el documento tiene 1 frame con todos los sprites
    #       en linea.
    rows_per_label = {}
    first_path = os.path.join(EXPORT_DIR, "flecha_0.png")
    if not os.path.isfile(first_path):
        print(f"[ERR] No existe {first_path}", file=sys.stderr)
        sys.exit(1)
    first_img = Image.open(first_path)
    n_frames = len(FRAME_TO_LABEL)
    if first_img.size == (SPRITE_W * n_frames, SPRITE_H):
        # Strip horizontal con todos los frames
        print(f"  Strip detectado: {first_img.size[0]}x{first_img.size[1]} "
              f"-> slicing en {n_frames} frames de {SPRITE_W}x{SPRITE_H}")
        all_rows = strip_to_bytes_list(first_path, n_frames)
        for frame_idx, label in enumerate(FRAME_TO_LABEL):
            rows_per_label[label] = all_rows[frame_idx]
            print(f"    frame {frame_idx} -> {label}")
    else:
        # Multiples PNGs separados, uno por frame
        for frame_idx, label in enumerate(FRAME_TO_LABEL):
            png_path = os.path.join(EXPORT_DIR, f"flecha_{frame_idx}.png")
            if not os.path.isfile(png_path):
                print(f"[ERR] No existe {png_path}", file=sys.stderr)
                sys.exit(1)
            rows_per_label[label] = png_to_bytes(png_path)
            print(f"  flecha_{frame_idx}.png -> {label}")

    # 2. Leer milestones.asm
    with open(MILESTONES, "r", encoding="utf-8") as f:
        asm_text = f.read()

    # 3. Reemplazar cada bloque
    for label, rows in rows_per_label.items():
        new_block = rows_to_defb_block(label, rows)
        asm_text = replace_sprite_block(asm_text, label, new_block)

    # 4. Escribir
    with open(MILESTONES, "w", encoding="utf-8") as f:
        f.write(asm_text)

    print(f"\n{len(rows_per_label)} sprites importados a {MILESTONES}")
    print("(Sprite_Compass_X intacto.)")


if __name__ == "__main__":
    main()
