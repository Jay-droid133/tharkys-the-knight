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

Además emite code/splash_prompt.bin (136 B = 128 px + 8 attr), pre-renderizado
desde code/bg_sprites.json con dos iconos animados de 16x16 — tecla (ids 40 y
178) y botón (ids 171 y 172) — que alternan dos frames durante la espera. Lo
carga main.asm vía INCBIN para pintarlo en runtime tras la carga (ver
splash_wait.asm).

Idempotente: regenera salidas solo si cambian las entradas.

Uso:
    python tools/build_tap_with_splash.py
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CODE = REPO / "code"

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
BG_SPRITES_JSON  = CODE / "bg_sprites.json"
TAP_INPUT        = CODE / "juego.tap"
TAP_OUTPUT       = CODE / "juego_release.tap"
PROMPT_BIN       = CODE / "splash_prompt.bin"

SPLASH_SPRITE_ID = 257

# Iconos animados del prompt: dos sprites 16x16 con 2 frames cada uno
#   tecla:  ids 40 (frame A) y 178 (frame B)
#   botón:  ids 171 (frame A) y 172 (frame B)
# Cada frame comparte attrs entre A y B (se valida en extract_icon_blob).
PROMPT_KEY_IDS = (40, 178)
PROMPT_BTN_IDS = (171, 172)


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
# 2) Extraer pixels + attrs de los 4 sprites del prompt animado
# ---------------------------------------------------------------------------
# Cada sprite es 16x16: 32 B pixels (row-major, 2 B por fila pixel) + 4 B attrs
# (2x2 chars). Devuelve un blob compacto:
#     [0..31]    key_frame_A pixels (id 40)
#     [32..63]   key_frame_B pixels (id 178)
#     [64..95]   btn_frame_A pixels (id 171)
#     [96..127]  btn_frame_B pixels (id 172)
#     [128..131] key attrs (4 B, comunes a A/B)
#     [132..135] btn attrs (4 B, comunes a A/B)
def _load_sprite(data: dict, sid: int) -> dict:
    sprite = next((s for s in data.get("sprites", []) if s.get("id") == sid), None)
    if sprite is None:
        sys.exit(f"build_tap_with_splash: sprite id {sid} not in bg_sprites.json")
    if sprite.get("w") != 16 or sprite.get("h") != 16:
        sys.exit(f"build_tap_with_splash: sprite {sid} is "
                 f"{sprite.get('w')}x{sprite.get('h')}, need 16x16")
    if len(sprite.get("pixelBytes", [])) != 32:
        sys.exit(f"build_tap_with_splash: sprite {sid} pixelBytes "
                 f"len {len(sprite.get('pixelBytes', []))} != 32")
    if len(sprite.get("attrBytes", [])) != 4:
        sys.exit(f"build_tap_with_splash: sprite {sid} attrBytes "
                 f"len {len(sprite.get('attrBytes', []))} != 4")
    return sprite


def extract_icon_blob(json_path: Path) -> bytes:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    key_a = _load_sprite(data, PROMPT_KEY_IDS[0])
    key_b = _load_sprite(data, PROMPT_KEY_IDS[1])
    btn_a = _load_sprite(data, PROMPT_BTN_IDS[0])
    btn_b = _load_sprite(data, PROMPT_BTN_IDS[1])
    if key_a["attrBytes"] != key_b["attrBytes"]:
        sys.exit(f"build_tap_with_splash: tecla frames {PROMPT_KEY_IDS} "
                 f"tienen attrs distintos ({key_a['attrBytes']} vs "
                 f"{key_b['attrBytes']}); el splash usa attrs compartidos")
    if btn_a["attrBytes"] != btn_b["attrBytes"]:
        sys.exit(f"build_tap_with_splash: botón frames {PROMPT_BTN_IDS} "
                 f"tienen attrs distintos ({btn_a['attrBytes']} vs "
                 f"{btn_b['attrBytes']}); el splash usa attrs compartidos")
    pixels = (bytes(key_a["pixelBytes"]) + bytes(key_b["pixelBytes"])
              + bytes(btn_a["pixelBytes"]) + bytes(btn_b["pixelBytes"]))
    attrs = bytes(key_a["attrBytes"]) + bytes(btn_a["attrBytes"])
    return pixels + attrs


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
    if not BG_SPRITES_JSON.is_file():
        sys.exit(f"build_tap_with_splash: missing {BG_SPRITES_JSON}")

    # --- Prompt bin (iconos animados 16x16) -------------------------------
    # Se genera SIEMPRE (incluso sin TAP_INPUT) porque splash_wait.asm hace
    # INCBIN de este archivo en tiempo de ensamblado. Llamar al script antes
    # de sjasmplus (build .bat) garantiza el .bin actualizado.
    prompt_blob = extract_icon_blob(BG_SPRITES_JSON)
    assert len(prompt_blob) == 128 + 8, len(prompt_blob)

    # Idempotente
    if not PROMPT_BIN.is_file() or PROMPT_BIN.read_bytes() != prompt_blob:
        PROMPT_BIN.write_bytes(prompt_blob)
        print(f"build_tap_with_splash: wrote {PROMPT_BIN.name} "
              f"({len(prompt_blob)} B = 128 px + 8 attr, "
              f"key={PROMPT_KEY_IDS} btn={PROMPT_BTN_IDS})")
    else:
        print(f"build_tap_with_splash: {PROMPT_BIN.name} up to date")

    # --- TAP processing requiere juego.tap (sólo tras sjasmplus) ----------
    # Si todavía no existe (primer paso del .bat antes de compilar), salimos
    # tras generar el .bin. La segunda invocación del script (post-build)
    # genera el juego_release.tap.
    if not TAP_INPUT.is_file():
        print(f"build_tap_with_splash: {TAP_INPUT.name} todavía no existe; "
              f"se generará el TAP en la siguiente invocación post-build.")
        return 0

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
