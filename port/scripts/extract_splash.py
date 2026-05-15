#!/usr/bin/env python3
"""Extract a 256x192 Spectrum-native BG sprite from code/bg_sprites.json
into a C header (pixelBytes + attrBytes as static arrays). Used by the
wrapper to display the splash screen at startup until the user presses
any key.

usage: extract_splash.py <bg_sprites.json> <output_header> <sprite_id>
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 1

    json_path = Path(argv[1])
    out_path  = Path(argv[2])
    try:
        sprite_id = int(argv[3])
    except ValueError:
        print(f"extract_splash: bad sprite id {argv[3]!r}", file=sys.stderr)
        return 1

    if not json_path.is_file():
        print(f"extract_splash: not a file: {json_path}", file=sys.stderr)
        return 1

    data = json.loads(json_path.read_text(encoding="utf-8"))
    sprite = next((s for s in data.get("sprites", []) if s.get("id") == sprite_id), None)
    if sprite is None:
        print(f"extract_splash: sprite id {sprite_id} not in {json_path.name}", file=sys.stderr)
        return 1

    name   = sprite.get("name", f"id{sprite_id}")
    w      = sprite.get("w", 0)
    h      = sprite.get("h", 0)
    pixels = sprite.get("pixelBytes", [])
    attrs  = sprite.get("attrBytes", [])

    if w != 256 or h != 192:
        print(f"extract_splash: sprite {sprite_id} is {w}x{h}; need 256x192", file=sys.stderr)
        return 1
    if len(pixels) != 6144:
        print(f"extract_splash: pixelBytes len {len(pixels)} != 6144", file=sys.stderr)
        return 1
    if len(attrs) != 768:
        print(f"extract_splash: attrBytes len {len(attrs)} != 768", file=sys.stderr)
        return 1

    def hexrow(seq: list[int], i: int, n: int) -> str:
        return ", ".join(f"0x{b:02X}" for b in seq[i:i + n])

    lines: list[str] = []
    lines.append(f"// Auto-generated from {json_path.name} sprite id {sprite_id} ('{name}').\n")
    lines.append(f"// {w}x{h} Spectrum-native: 6144 pixel bytes (interleaved) + 768 attr bytes (32x24 cells).\n")
    lines.append("#pragma once\n")
    lines.append("#include <stdint.h>\n\n")

    lines.append("static const uint8_t splash_pixels[6144] = {\n")
    for i in range(0, 6144, 16):
        lines.append(f"    {hexrow(pixels, i, 16)},\n")
    lines.append("};\n\n")

    lines.append("static const uint8_t splash_attrs[768] = {\n")
    for i in range(0, 768, 16):
        lines.append(f"    {hexrow(attrs, i, 16)},\n")
    lines.append("};\n")

    rendered = "".join(lines)
    # Idempotent: skip rewrite if content matches so the build dep mtime stays stable.
    if out_path.is_file() and out_path.read_text(encoding="utf-8") == rendered:
        return 0

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(rendered, encoding="utf-8")
    print(f"extract_splash.py: wrote {out_path} (sprite {sprite_id} '{name}')")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
