#!/usr/bin/env python3
"""
import_smoke.py - Importa los frames de humo desde PNGs a milestones.asm

Lee `References/export/smoke_0.png` ... `smoke_2.png` (16x16 cada uno) o
un strip horizontal `smoke_0.png` de 48x16 con los 3 frames seguidos, y
reemplaza los bloques DEFB de `SmokeFrame0`, `SmokeFrame1`, `SmokeFrame2`
en `code/milestones.asm`.

La animacion del humo se usa en la cutscene de la trampa de la iglesia
(fase SMOKE), encima de los restos del monstruo atrapado.

Formato de salida (compatible con DrawBgSprite16XorAtPixel):
    SmokeFrame<N>:
        DEFB 16, 2                              ; height_px, width_bytes
        DEFB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
        DEFB ...
        DEFB ...
        DEFB ...

  - Header (2B): height_px=16, width_bytes=2.
  - Pixel data (32B): 16 filas x 2 bytes, CPL'd (XOR 0xFF). El engine
    re-CPL en el draw para obtener el bit pattern original.

Regla de "pixel encendido":
    alpha > ALPHA_THRESHOLD  AND  RGB != (0,0,0)
Soporta tanto PNGs con fondo transparente como con fondo NEGRO opaco
(default Aseprite si hay layer Background).

Uso:
    # 1. Si los PNGs ya estan exportados en References/export/:
    python tools/import_smoke.py

    # 2. Si tienes solo el .aseprite y quieres que exporte y luego importe:
    python tools/import_smoke.py References/smoke02-...aseprite

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

# Mapeo: frame index en aseprite -> label ASM en milestones.asm.
FRAME_TO_LABEL = [
    "SmokeFrame0",
    "SmokeFrame1",
    "SmokeFrame2",
]

SPRITE_W = 16
SPRITE_H = 16
ALPHA_THRESHOLD = 128

# Invertir la mascara antes de guardar. Util cuando el sprite del aseprite
# representa la "silueta vacia" del humo en vez del area visible: con
# INVERT_PIXELS=True, los pixels NO-DIBUJADOS del PNG son los que tocan
# pantalla via XOR. Para el humo del church trap (smoke02) queda bien
# porque la S dibujada en rojo debe verse como hueco, no como dibujo.
INVERT_PIXELS = False


# ---------------------------------------------------------------------------
# PIL image -> bytes (16 filas x 2 bytes = 32 bytes)
# ---------------------------------------------------------------------------
def img_to_bytes(img, x_offset=0):
    """
    Convierte un area 16x16 de un PIL Image (modo RGBA) a 32 bytes.
    x_offset permite leer un sprite concreto dentro de un strip horizontal.

    Regla de "pixel encendido":
        alpha > ALPHA_THRESHOLD  AND  RGB != (0,0,0)
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
            if INVERT_PIXELS:
                byte ^= 0xFF
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
    Lee un PNG strip horizontal (n_frames * 16 x 16) y devuelve una lista
    de N x 32 bytes (uno por frame).
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
# bytes -> bloque ASM (header + 4 lineas DEFB de pixel CPL'd)
# ---------------------------------------------------------------------------
def rows_to_defb_block(label, rows):
    """
    rows: list[16] of [byte_left, byte_right]
    Output:
        SmokeFrameN:
            DEFB 16, 2                              ; height_px, width_bytes
            DEFB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
            ...
    Bytes pixel se almacenan CPL'd (XOR 0xFF) porque el engine los re-CPL
    al dibujar (formato comun para sprites BG en este proyecto).
    """
    out = [f"{label}:"]
    out.append("    DEFB 16, 2                              ; height_px, width_bytes")
    for chunk_start in range(0, 16, 4):
        chunk = rows[chunk_start:chunk_start + 4]
        defb = "    DEFB " + ", ".join(
            f"${(row[0] ^ 0xFF):02X},${(row[1] ^ 0xFF):02X}" for row in chunk
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
            DEFB 16, 2 ...           (header)
            DEFB ...                 (4 lineas pixel)
            DEFB ...
            DEFB ...
            DEFB ...
    y lo reemplaza con new_block. Asume header + 4 lineas DEFB tras el
    label, que es como estan los SmokeFrame* hoy.
    """
    pattern = re.compile(
        r"^" + re.escape(label) + r":\s*\n"
        r"(?:[ \t]*DEFB[^\n]*\n){5}",
        flags=re.MULTILINE,
    )
    m = pattern.search(asm_text)
    if not m:
        raise RuntimeError(
            f"No se encontro el bloque de '{label}' (header + 4 lineas DEFB) "
            f"en milestones.asm. Comprueba que el formato sigue intacto."
        )
    return asm_text[: m.start()] + new_block + "\n" + asm_text[m.end():]


# ---------------------------------------------------------------------------
# Aseprite -> PNGs (uno por frame en EXPORT_DIR/smoke_<N>.png)
# ---------------------------------------------------------------------------
def export_aseprite_frames(aseprite_path):
    """
    Lanza Aseprite CLI con --save-as <dir>/smoke_{frame}.png. Para
    aseprites de 1 frame con sprites en strip horizontal, sale un solo
    PNG con todos los sprites en linea (detectado luego por strip_to_bytes_list).
    """
    if not os.path.isfile(ASEPRITE_EXE):
        print(f"[ERR] Aseprite no encontrado en {ASEPRITE_EXE}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(aseprite_path):
        print(f"[ERR] No existe {aseprite_path}", file=sys.stderr)
        sys.exit(1)
    os.makedirs(EXPORT_DIR, exist_ok=True)
    out_pattern = os.path.join(EXPORT_DIR, "smoke_{frame}.png")
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
    #    A) smoke_0.png ... smoke_2.png cada uno 16x16.
    #    B) smoke_0.png como strip horizontal (16*N x 16) y el resto inexistente.
    rows_per_label = {}
    first_path = os.path.join(EXPORT_DIR, "smoke_0.png")
    if not os.path.isfile(first_path):
        print(f"[ERR] No existe {first_path}", file=sys.stderr)
        sys.exit(1)
    first_img = Image.open(first_path)
    n_frames = len(FRAME_TO_LABEL)
    if first_img.size == (SPRITE_W * n_frames, SPRITE_H):
        print(f"  Strip detectado: {first_img.size[0]}x{first_img.size[1]} "
              f"-> slicing en {n_frames} frames de {SPRITE_W}x{SPRITE_H}")
        all_rows = strip_to_bytes_list(first_path, n_frames)
        for frame_idx, label in enumerate(FRAME_TO_LABEL):
            rows_per_label[label] = all_rows[frame_idx]
            print(f"    frame {frame_idx} -> {label}")
    else:
        for frame_idx, label in enumerate(FRAME_TO_LABEL):
            png_path = os.path.join(EXPORT_DIR, f"smoke_{frame_idx}.png")
            if not os.path.isfile(png_path):
                print(f"[ERR] No existe {png_path}", file=sys.stderr)
                sys.exit(1)
            rows_per_label[label] = png_to_bytes(png_path)
            print(f"  smoke_{frame_idx}.png -> {label}")

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

    print(f"\n{len(rows_per_label)} frames de humo importados a {MILESTONES}")


if __name__ == "__main__":
    main()
