#!/usr/bin/env python3
"""
build_minimap_overlay.py
========================
Extrae sprites 179 (cam) y 187 (cam no) de code/bg_sprites.json y emite
code/minimap_overlay.bin con los pixels y attrs RAW (sin CPL) que
minimap.asm vuelca directamente en VRAM mientras ShowMinimapTimed esta
abierto. Idempotente: solo reescribe si cambia el contenido.

Layout del .bin (72 B):
    [0..31]    sprite 179 pixels (32 B row-major: y0_b0, y0_b1, y1_b0, ...)
    [32..63]   sprite 187 pixels
    [64..67]   sprite 179 attrs (4 B, orden row-major: TL, TR, BL, BR)
    [68..71]   sprite 187 attrs

Los sprites se quedan tal cual en bg_sprites.json (sin CPL). Mi rutina de
pintado vuelca byte a byte a VRAM (LD A,(DE) / LD (HL),A) — escribir CPL'd
mostraria el sprite invertido.

Uso:
    python tools/build_minimap_overlay.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BG_JSON = REPO / "code" / "bg_sprites.json"
OUT_BIN = REPO / "code" / "minimap_overlay.bin"

OVERLAY_IDS = (179, 187)        # frame A (cam) y frame B (cam no)


def main() -> int:
    if not BG_JSON.is_file():
        sys.exit(f"build_minimap_overlay: missing {BG_JSON}")

    data = json.loads(BG_JSON.read_text(encoding="utf-8"))
    sprites = {}
    for sid in OVERLAY_IDS:
        s = next((s for s in data.get("sprites", []) if s.get("id") == sid), None)
        if s is None:
            sys.exit(f"build_minimap_overlay: sprite id {sid} not in bg_sprites.json")
        if s.get("w") != 16 or s.get("h") != 16:
            sys.exit(f"build_minimap_overlay: sprite {sid} dims "
                     f"{s.get('w')}x{s.get('h')} != 16x16")
        if len(s.get("pixelBytes", [])) != 32:
            sys.exit(f"build_minimap_overlay: sprite {sid} pixelBytes != 32")
        if len(s.get("attrBytes", [])) != 4:
            sys.exit(f"build_minimap_overlay: sprite {sid} attrBytes != 4")
        sprites[sid] = s

    blob = (bytes(sprites[OVERLAY_IDS[0]]["pixelBytes"])
            + bytes(sprites[OVERLAY_IDS[1]]["pixelBytes"])
            + bytes(sprites[OVERLAY_IDS[0]]["attrBytes"])
            + bytes(sprites[OVERLAY_IDS[1]]["attrBytes"]))
    assert len(blob) == 64 + 8, len(blob)

    if not OUT_BIN.is_file() or OUT_BIN.read_bytes() != blob:
        OUT_BIN.write_bytes(blob)
        print(f"build_minimap_overlay: wrote {OUT_BIN.name} "
              f"({len(blob)} B, ids={OVERLAY_IDS})")
    else:
        print(f"build_minimap_overlay: {OUT_BIN.name} up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
