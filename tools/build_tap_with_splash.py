#!/usr/bin/env python3
"""
build_tap_with_splash.py
========================
Post-procesa code/juego.tap (generado por SAVETAP de sjasmplus) para producir
code/juego_release.tap con:

  - BASIC loader reescrito que ejecuta `LOAD ""SCREEN$ : LOAD ""CODE : USR $5E00`.
  - Bloque SCREEN$ con bg257 (sprite id 257 de code/bg_sprites.json), 6912 B.
  - El resto de bloques (loader máquina $5E00 + 7 bloques de banco) del TAP
    original, sin tocar.

Además emite code/splash_prompt.bin (198 B = 176 px + 22 attr), pre-renderizado
desde code/credits_font.asm con el texto fijo 'PRESS ANY KEY / BUTTON' centrado
en la fila char 22. Lo carga main.asm vía INCBIN para pintarlo en runtime tras
la carga (ver splash_wait.asm).

Idempotente: regenera salidas solo si cambian las entradas.

Uso:
    python tools/build_tap_with_splash.py
"""

from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CODE = REPO / "code"

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
BG_SPRITES_JSON  = CODE / "bg_sprites.json"
CREDITS_FONT_ASM = CODE / "credits_font.asm"
TAP_INPUT        = CODE / "juego.tap"
TAP_OUTPUT       = CODE / "juego_release.tap"
PROMPT_BIN       = CODE / "splash_prompt.bin"

SPLASH_SPRITE_ID = 257
PROMPT_TEXT      = "PRESS ANY KEY / BUTTON"
PROMPT_ROW       = 22                # fila char 22 (0..23)
PROMPT_ATTR      = 0x47 | 0x08       # ink 7 | paper 1<<3 | bright 1<<6 = $4F? recalculamos abajo

# Recalcular attr de forma explícita: bright=1 (bit 6), paper=1 (bits 3..5), ink=7 (bits 0..2)
PROMPT_ATTR = (1 << 6) | (1 << 3) | 7   # = 0x4F


# ---------------------------------------------------------------------------
# Util: VRAM addr del pixel (x=col*8, y=row*8 + sub_row)
# ---------------------------------------------------------------------------
def vram_pixel_addr(x_char: int, y_pixel: int) -> int:
    """Spectrum interleaved pixel address."""
    third = (y_pixel >> 6) & 3          # 0..2
    cell_y = (y_pixel >> 3) & 7         # fila char dentro del third (0..7)
    sub_y  = y_pixel & 7                # fila pixel dentro del char (0..7)
    return 0x4000 | (third << 11) | (sub_y << 8) | (cell_y << 5) | x_char


# ---------------------------------------------------------------------------
# 1) Extraer SCREEN$ desde bg_sprites.json
# ---------------------------------------------------------------------------
def linear_to_spectrum_native(linear: bytes) -> bytes:
    """
    El BG editor guarda los sprites 256x192 en formato row-major lineal
    (32 B/scanline x 192 scanlines = 6144 B), tal como confirma el wrapper
    SDL en port/src/video.c. El SCREEN$ de la VRAM Spectrum vive en orden
    interleaved en $4000-$57FF, por lo que LOAD ""SCREEN$ esperaria bytes
    en ese orden. Conversión:
        Spectrum addr bits (10..0) = third(2) | sub_y(3) | cell_y(3) | x_byte(5)
        donde y = (third<<6) | (cell_y<<3) | sub_y
    """
    if len(linear) != 6144:
        sys.exit(f"build_tap_with_splash: linear pixels len {len(linear)} != 6144")
    out = bytearray(6144)
    for y in range(192):
        third  = (y >> 6) & 3
        sub_y  = y & 7
        cell_y = (y >> 3) & 7
        dst_row = (third << 11) | (sub_y << 8) | (cell_y << 5)
        src_row = y * 32
        out[dst_row:dst_row + 32] = linear[src_row:src_row + 32]
    return bytes(out)


def extract_splash_scr(json_path: Path, sprite_id: int) -> bytes:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    sprite = next((s for s in data.get("sprites", []) if s.get("id") == sprite_id), None)
    if sprite is None:
        sys.exit(f"build_tap_with_splash: sprite id {sprite_id} not in {json_path.name}")
    if sprite.get("w") != 256 or sprite.get("h") != 192:
        sys.exit(f"build_tap_with_splash: sprite {sprite_id} is "
                 f"{sprite.get('w')}x{sprite.get('h')}, need 256x192")
    pixels = sprite.get("pixelBytes", [])
    attrs  = sprite.get("attrBytes", [])
    if len(pixels) != 6144 or len(attrs) != 768:
        sys.exit(f"build_tap_with_splash: bad sprite payload "
                 f"(px={len(pixels)}, attr={len(attrs)})")
    # pixels: linear row-major → Spectrum-native interleaved.
    # attrs: ya en formato row-major 32x24 = idéntico al layout VRAM $5800+.
    return linear_to_spectrum_native(bytes(pixels)) + bytes(attrs)


# ---------------------------------------------------------------------------
# 2) Parsear credits_font.asm
# ---------------------------------------------------------------------------
# Formato: comentario "; 0xNN 'C'" en una línea, y la siguiente línea DEFB con
# 8 bytes (formato $xx o decimal). El parser empareja "comentario + siguiente
# DEFB".
CHAR_COMMENT_RE = re.compile(r"^\s*;\s*0x([0-9A-Fa-f]+)\b")
DEFB_BYTE_RE    = re.compile(r"(?:\$([0-9A-Fa-f]+)|(\d+))")


def _parse_defb_bytes(line: str) -> list[int]:
    s = line.strip()
    if not s.upper().startswith("DEFB"):
        return []
    s = s[4:]
    # cortar comentario si lo hubiera
    if ";" in s:
        s = s.split(";", 1)[0]
    out: list[int] = []
    for m in DEFB_BYTE_RE.finditer(s):
        if m.group(1) is not None:
            out.append(int(m.group(1), 16))
        else:
            out.append(int(m.group(2)))
    return out


# Glifos custom para chars que el credits_font no cubre (o cubre con $00).
# El '/' del credits_font está vacío; lo inyecto aquí en build-time solo
# para el prompt del splash, sin tocar el .asm.
CUSTOM_GLYPHS: dict[int, list[int]] = {
    0x2F: [0x00, 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x00],   # '/'
}


def parse_credits_font(asm_path: Path) -> dict[int, list[int]]:
    """Devuelve {char_code: [b0..b7]} emparejando '; 0xNN' con la línea DEFB
    inmediatamente posterior."""
    glyphs: dict[int, list[int]] = {}
    lines = asm_path.read_text(encoding="utf-8").splitlines()
    pending: int | None = None
    for line in lines:
        if pending is None:
            m = CHAR_COMMENT_RE.match(line)
            if m:
                pending = int(m.group(1), 16)
            continue
        # Estamos esperando la DEFB de "pending"
        bs = _parse_defb_bytes(line)
        if not bs:
            # comentario u otra línea suelta - skip
            continue
        if len(bs) != 8:
            sys.exit(f"build_tap_with_splash: DEFB con {len(bs)} bytes para "
                     f"0x{pending:02X} (esperaba 8): {line!r}")
        glyphs[pending] = bs
        pending = None
    if 0x41 not in glyphs or 0x50 not in glyphs:
        sys.exit("build_tap_with_splash: credits_font.asm parse failed "
                 "(sin glifos A/P)")
    # Aplicar overrides custom
    for code, g in CUSTOM_GLYPHS.items():
        glyphs[code] = g
    return glyphs


# ---------------------------------------------------------------------------
# 3) Renderizar el prompt a un blob de pixels (8 stripes de N bytes) + attrs
# ---------------------------------------------------------------------------
def render_prompt(text: str, glyphs: dict[int, list[int]],
                  attr_byte: int) -> tuple[bytes, bytes]:
    n = len(text)
    # 8 filas pixel, cada una con n bytes (un byte por char)
    stripes = bytearray()
    for sub_y in range(8):
        for ch in text:
            g = glyphs.get(ord(ch))
            if g is None:
                sys.exit(f"build_tap_with_splash: glyph {ch!r} (0x{ord(ch):02X}) "
                         f"not in font")
            stripes.append(g[sub_y])
    attrs = bytes([attr_byte] * n)
    return bytes(stripes), attrs


# ---------------------------------------------------------------------------
# 4) Construcción del TAP
# ---------------------------------------------------------------------------
def tap_xor(buf: bytes) -> int:
    x = 0
    for b in buf:
        x ^= b
    return x & 0xFF


def tap_block(payload: bytes, flag: int) -> bytes:
    body = bytes([flag]) + payload
    body += bytes([tap_xor(body)])
    return struct.pack("<H", len(body)) + body


def tap_header_basic(name: str, data_len: int, autostart: int, vars_offset: int) -> bytes:
    nm = name.encode("ascii")[:10].ljust(10, b" ")
    h = bytes([0x00]) + nm + struct.pack("<HHH", data_len, autostart, vars_offset)
    return tap_block(h, 0x00)


def tap_header_code(name: str, data_len: int, load_addr: int, p2: int = 32768) -> bytes:
    nm = name.encode("ascii")[:10].ljust(10, b" ")
    h = bytes([0x03]) + nm + struct.pack("<HHH", data_len, load_addr, p2)
    return tap_block(h, 0x00)


def tap_data(payload: bytes) -> bytes:
    return tap_block(payload, 0xFF)


# Tokens BASIC del 48K Spectrum (subset que necesitamos)
T_BORDER    = 0xE7
T_PAPER     = 0xDA
T_INK       = 0xD9
T_CLEAR     = 0xFD
T_LOAD      = 0xEF
T_SCREEN_Q  = 0xAA   # SCREEN$
T_CODE      = 0xAF
T_RANDOMIZE = 0xF9
T_USR       = 0xC0
T_VAL       = 0xB0


def basic_line(line_num: int, body: bytes) -> bytes:
    """Devuelve la línea BASIC completa con prefijo line_num(BE)+len(LE) y EOL."""
    line_with_eol = body + bytes([0x0D])
    return struct.pack(">H", line_num) + struct.pack("<H", len(line_with_eol)) + line_with_eol


def build_basic_loader(usr_addr: int = 24064, ramtop: int = 24063) -> bytes:
    """
    Línea 10:
        BORDER VAL "0": PAPER VAL "0": INK VAL "0": CLEAR VAL "<ramtop>":
        LOAD ""CODE: LOAD ""SCREEN$: RANDOMIZE USR VAL "<usr>"

    Mantenemos VAL "n" en todo número para que sea ASCII puro (sin
    embedded FP number tras los dígitos).

    Orden: LOAD CODE *antes* que LOAD SCREEN$.  El ROM imprime "Bytes:"
    en la lower screen al ejecutar cada LOAD, y con ATTR_P=$00 (PAPER 0:
    INK 0) la zona del mensaje queda con attrs $00 (negro total).
    Si SCREEN$ se cargara antes, esa franja contaminaría el splash. Con
    SCREEN$ al final el LD_BYTES sobreescribe los 768 attrs $5800-$5AFF
    con los del bg257 originales, así que cualquier residuo desaparece.
    """
    def val(n: int) -> bytes:
        return bytes([T_VAL, 0x22]) + str(n).encode("ascii") + bytes([0x22])

    body  = bytes([T_BORDER]) + val(0) + b":"
    body += bytes([T_PAPER])  + val(0) + b":"
    body += bytes([T_INK])    + val(0) + b":"
    body += bytes([T_CLEAR])  + val(ramtop) + b":"
    body += bytes([T_LOAD, 0x22, 0x22, T_CODE])    + b":"
    body += bytes([T_LOAD, 0x22, 0x22, T_SCREEN_Q]) + b":"
    body += bytes([T_RANDOMIZE, T_USR]) + val(usr_addr)
    return basic_line(10, body)


# ---------------------------------------------------------------------------
# 5) Parsear el TAP original y extraer los bloques que conservamos
# ---------------------------------------------------------------------------
def parse_tap_blocks(path: Path) -> list[bytes]:
    data = path.read_bytes()
    i = 0
    out: list[bytes] = []
    while i < len(data):
        blen = struct.unpack("<H", data[i:i + 2])[0]
        i += 2
        out.append(data[i:i + blen])
        i += blen
    return out


def main() -> int:
    if not TAP_INPUT.is_file():
        sys.exit(f"build_tap_with_splash: missing {TAP_INPUT} (compila primero)")
    if not BG_SPRITES_JSON.is_file():
        sys.exit(f"build_tap_with_splash: missing {BG_SPRITES_JSON}")
    if not CREDITS_FONT_ASM.is_file():
        sys.exit(f"build_tap_with_splash: missing {CREDITS_FONT_ASM}")

    # --- Prompt bin -------------------------------------------------------
    glyphs = parse_credits_font(CREDITS_FONT_ASM)
    stripes, attrs = render_prompt(PROMPT_TEXT, glyphs, PROMPT_ATTR)
    prompt_blob = stripes + attrs
    expected_len = len(PROMPT_TEXT) * 8 + len(PROMPT_TEXT)
    assert len(prompt_blob) == expected_len, (len(prompt_blob), expected_len)

    # Idempotente
    if not PROMPT_BIN.is_file() or PROMPT_BIN.read_bytes() != prompt_blob:
        PROMPT_BIN.write_bytes(prompt_blob)
        print(f"build_tap_with_splash: wrote {PROMPT_BIN.name} "
              f"({len(prompt_blob)} B = {len(stripes)} px + {len(attrs)} attr)")
    else:
        print(f"build_tap_with_splash: {PROMPT_BIN.name} up to date")

    # --- SCREEN$ ----------------------------------------------------------
    scr = extract_splash_scr(BG_SPRITES_JSON, SPLASH_SPRITE_ID)
    assert len(scr) == 6912

    # --- TAP base ---------------------------------------------------------
    blocks = parse_tap_blocks(TAP_INPUT)
    # Esperamos: [0] BASIC hdr, [1] BASIC data, [2..N] code loader + banks
    if len(blocks) < 4:
        sys.exit(f"build_tap_with_splash: {TAP_INPUT.name} tiene "
                 f"{len(blocks)} bloques, esperaba >=4")
    # Inspeccionar el BASIC hdr para extraer el autostart line.
    basic_hdr = blocks[0]
    if basic_hdr[0] != 0x00 or basic_hdr[1] != 0x00:
        sys.exit("build_tap_with_splash: bloque #1 no es BASIC header")
    autostart = struct.unpack("<H", basic_hdr[14:16])[0]
    print(f"build_tap_with_splash: BASIC autostart line = {autostart}")

    # Construir nuevo BASIC
    new_basic_body = build_basic_loader(usr_addr=24064, ramtop=24063)
    new_basic_hdr  = tap_header_basic("LOADER", len(new_basic_body),
                                       autostart=autostart,
                                       vars_offset=len(new_basic_body))
    new_basic_data = tap_data(new_basic_body)

    # SCREEN$ blocks
    scr_hdr  = tap_header_code("screen", len(scr), load_addr=0x4000)
    scr_data = tap_data(scr)

    # Resto del TAP original: blocks[2:] (loader máquina + bancos).
    # PARCHE: el loader máquina en $5E00 emitido por sjasmplus arranca con
    # `LD A,$38; LD ($5C8D),A; CALL $0D6B` (= ATTR P = white|black + CL-ALL).
    # Ese CALL borra el SCREEN$ que acabamos de cargar antes de empezar el
    # loop de bancos. Lo neutralizamos sustituyendo los 3 bytes $CD,$6B,$0D
    # por 3 NOPs en el bloque de datos del loader (blocks[3] tras los 2
    # bloques BASIC del TAP original; aquí es blocks[3] del TAP base ya que
    # solo separamos BASIC hdr/data antes del SCREEN$).
    patched = list(blocks[2:])
    # blocks[2] = loader header, blocks[3] = loader data.
    ld_hdr  = patched[0]
    ld_data = bytearray(patched[1])
    # ld_data layout: flag($FF) + payload (146 B) + xor(1 B).
    CLS_OFFSET = 1 + 5      # flag + offset 5 (CD 6B 0D)
    if (ld_data[CLS_OFFSET], ld_data[CLS_OFFSET + 1], ld_data[CLS_OFFSET + 2]) != (0xCD, 0x6B, 0x0D):
        sys.exit(f"build_tap_with_splash: loader $5E00 no arranca con CALL $0D6B "
                 f"({ld_data[CLS_OFFSET]:02X} {ld_data[CLS_OFFSET+1]:02X} "
                 f"{ld_data[CLS_OFFSET+2]:02X}); ¿cambió sjasmplus? Abortando.")
    ld_data[CLS_OFFSET]     = 0x00
    ld_data[CLS_OFFSET + 1] = 0x00
    ld_data[CLS_OFFSET + 2] = 0x00
    # Recalcular XOR del bloque (último byte).
    xor = 0
    for b in ld_data[:-1]:
        xor ^= b
    ld_data[-1] = xor & 0xFF
    patched[1] = bytes(ld_data)
    print(f"build_tap_with_splash: parcheado CALL $0D6B (CL-ALL) -> 3 NOPs en "
          f"loader $5E00 (preserva el SCREEN$ tras la carga)")

    # Layout final del TAP:
    #   BASIC hdr  + BASIC data
    #   CODE  hdr "loader" + loader data (parcheado, sin CL-ALL)
    #   CODE  hdr "screen" + SCREEN$ data  ← se carga el último, sobreescribe
    #                                        residuos del mensaje "Bytes:" del LOAD ""CODE
    #   ... bloques de banco (data only) ...
    loader_hdr_data = (struct.pack("<H", len(patched[0])) + patched[0]
                       + struct.pack("<H", len(patched[1])) + patched[1])
    bank_blocks = b"".join(struct.pack("<H", len(b)) + b for b in patched[2:])

    out = (new_basic_hdr + new_basic_data
           + loader_hdr_data
           + scr_hdr + scr_data
           + bank_blocks)

    if TAP_OUTPUT.is_file() and TAP_OUTPUT.read_bytes() == out:
        print(f"build_tap_with_splash: {TAP_OUTPUT.name} up to date "
              f"({len(out)} B)")
    else:
        TAP_OUTPUT.write_bytes(out)
        print(f"build_tap_with_splash: wrote {TAP_OUTPUT.name} "
              f"({len(out)} B, {len(blocks[2:]) + 4} blocks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
