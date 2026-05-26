#!/usr/bin/env python3
"""
build_loading_185.py
====================
Extrae sprite 185 ("Splash alternative") de code/bg_sprites.json y produce
code/bg_185.scr (6912 B raw, formato VRAM-native Spectrum: pixels interleaved
+ attrs).

Lo consume el binario STANDALONE como INCBIN en $4000 dentro del bloque
IFDEF STANDALONE de main.asm. Asi sjasmplus emite la imagen directamente
en zona VRAM y SAVESNA la captura -> el SNA arranca con 185 visible en
pantalla, igual que un juego clasico cargado por LOAD ""SCREEN$.

(En TAP real, el BASIC loader cargaria 185 vez via LOAD ""SCREEN$. Para el
TAP standalone, sjasmplus emite los mismos bytes como un CODE block con
load_addr=$4000 que el loader maneja igual.)

Idempotente: regenera solo si sprite 185 cambia.

Uso:
    python tools/build_loading_185.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CODE = REPO / "code"

BG_SPRITES_JSON = CODE / "bg_sprites.json"
OUT             = CODE / "bg_185.scr"
HASH_STAMP      = CODE / ".bg_185.scr.stamp"

LOADING_SPRITE_ID = 185


def linear_to_spectrum_native(linear: bytes) -> bytes:
    if len(linear) != 6144:
        sys.exit(f"build_loading_185: linear pixels len {len(linear)} != 6144")
    out = bytearray(6144)
    for y in range(192):
        third  = (y >> 6) & 3
        sub_y  = y & 7
        cell_y = (y >> 3) & 7
        dst_row = (third << 11) | (sub_y << 8) | (cell_y << 5)
        src_row = y * 32
        out[dst_row:dst_row + 32] = linear[src_row:src_row + 32]
    return bytes(out)


def extract_scr(json_path: Path) -> bytes:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    sprite = next((s for s in data.get("sprites", []) if s.get("id") == LOADING_SPRITE_ID), None)
    if sprite is None:
        sys.exit(f"build_loading_185: sprite id {LOADING_SPRITE_ID} not in {json_path.name}")
    if sprite.get("w") != 256 or sprite.get("h") != 192:
        sys.exit(f"build_loading_185: sprite {LOADING_SPRITE_ID} is "
                 f"{sprite.get('w')}x{sprite.get('h')}, need 256x192")
    pixels = bytes(sprite.get("pixelBytes", []))
    attrs  = bytes(sprite.get("attrBytes", []))
    if len(pixels) != 6144 or len(attrs) != 768:
        sys.exit(f"build_loading_185: bad payload (px={len(pixels)}, attr={len(attrs)})")
    return linear_to_spectrum_native(pixels) + attrs


def main() -> int:
    if not BG_SPRITES_JSON.is_file():
        sys.exit(f"build_loading_185: missing {BG_SPRITES_JSON}")
    scr = extract_scr(BG_SPRITES_JSON)
    assert len(scr) == 6912

    scr_hash = hashlib.sha256(scr).hexdigest()
    stamp = HASH_STAMP.read_text().strip() if HASH_STAMP.is_file() else ""
    if stamp == scr_hash and OUT.is_file():
        print(f"build_loading_185: {OUT.name} up to date ({OUT.stat().st_size} B)")
        return 0
    OUT.write_bytes(scr)
    HASH_STAMP.write_text(scr_hash)
    print(f"build_loading_185: wrote {OUT.name} ({OUT.stat().st_size} B)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
