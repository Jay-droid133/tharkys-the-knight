#!/usr/bin/env python3
"""
build_splash_zx0.py
===================
Extrae sprite 257 ("image", el splash que aparece cuando arranca la música)
de code/bg_sprites.json, lo convierte a formato VRAM-native Spectrum (pixels
interleaved + attrs) y lo comprime con ZX0 (Einar Saukas v2.2). Produce
code/bg_splash.zx0 (~4 KB).

(Sprite 185, "Splash alternative", solo es necesario durante el periodo de
carga del TAP — no se embebe en RAM. Si se necesita en el futuro, anadirlo
como SCREEN$ block en build_tap_with_splash_standalone.py.)

Lo consume el binario STANDALONE: INCBIN en bank 1, descompresion runtime con
dzx0_standard a $4000.

Idempotente: regenera solo si bg_sprites.json (sprite 257) cambia.

Uso:
    python tools/build_splash_zx0.py
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CODE = REPO / "code"
TOOLS = REPO / "tools"

BG_SPRITES_JSON = CODE / "bg_sprites.json"
ZX0_EXE         = TOOLS / "zx0" / "zx0.exe"
SCR_TMP         = CODE / "bg_splash.scr"
ZX0_OUT         = CODE / "bg_splash.zx0"
HASH_STAMP      = CODE / ".bg_splash.zx0.stamp"

SPLASH_SPRITE_ID = 257


def linear_to_spectrum_native(linear: bytes) -> bytes:
    if len(linear) != 6144:
        sys.exit(f"build_splash_zx0: linear pixels len {len(linear)} != 6144")
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
    sprite = next((s for s in data.get("sprites", []) if s.get("id") == SPLASH_SPRITE_ID), None)
    if sprite is None:
        sys.exit(f"build_splash_zx0: sprite id {SPLASH_SPRITE_ID} not in {json_path.name}")
    if sprite.get("w") != 256 or sprite.get("h") != 192:
        sys.exit(f"build_splash_zx0: sprite {SPLASH_SPRITE_ID} is "
                 f"{sprite.get('w')}x{sprite.get('h')}, need 256x192")
    pixels = bytes(sprite.get("pixelBytes", []))
    attrs  = bytes(sprite.get("attrBytes", []))
    if len(pixels) != 6144 or len(attrs) != 768:
        sys.exit(f"build_splash_zx0: bad payload (px={len(pixels)}, attr={len(attrs)})")
    return linear_to_spectrum_native(pixels) + attrs


def main() -> int:
    if not ZX0_EXE.is_file():
        sys.exit(f"build_splash_zx0: missing {ZX0_EXE} (binario oficial Einar Saukas)")
    if not BG_SPRITES_JSON.is_file():
        sys.exit(f"build_splash_zx0: missing {BG_SPRITES_JSON}")

    scr = extract_scr(BG_SPRITES_JSON)
    assert len(scr) == 6912

    # Idempotencia: hash del .scr decide regenerar
    scr_hash = hashlib.sha256(scr).hexdigest()
    stamp = HASH_STAMP.read_text().strip() if HASH_STAMP.is_file() else ""
    if stamp == scr_hash and ZX0_OUT.is_file():
        print(f"build_splash_zx0: {ZX0_OUT.name} up to date ({ZX0_OUT.stat().st_size} B)")
        return 0

    SCR_TMP.write_bytes(scr)
    # ZX0 v2.2 compresion optima. -f overwrite.
    result = subprocess.run(
        [str(ZX0_EXE), "-f", str(SCR_TMP), str(ZX0_OUT)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"build_splash_zx0: zx0.exe failed:\n{result.stdout}\n{result.stderr}")

    HASH_STAMP.write_text(scr_hash)
    print(f"build_splash_zx0: wrote {ZX0_OUT.name} "
          f"({ZX0_OUT.stat().st_size} B from {len(scr)} B, "
          f"{ZX0_OUT.stat().st_size * 100 // len(scr)}% ratio)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
