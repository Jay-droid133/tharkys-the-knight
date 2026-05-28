#!/usr/bin/env python3
"""Extract small 16x16 BG sprites (animation frames) from
code/bg_sprites.json into a C header. Used by the web wrapper's
"press any key" intro, which cycles the key icon (ids 40 + 178).

usage: extract_key_frames.py <bg_sprites.json> <output_header> <id> [<id> ...]
The ids become consecutive frames, in the order given.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 1

    json_path = Path(argv[1])
    out_path  = Path(argv[2])
    try:
        ids = [int(a) for a in argv[3:]]
    except ValueError:
        print("extract_key_frames: ids must be integers", file=sys.stderr)
        return 1

    if not json_path.is_file():
        print(f"extract_key_frames: not a file: {json_path}", file=sys.stderr)
        return 1

    data = json.loads(json_path.read_text(encoding="utf-8"))
    by_id = {s.get("id"): s for s in data.get("sprites", [])}

    frames = []
    for sid in ids:
        s = by_id.get(sid)
        if s is None:
            print(f"extract_key_frames: sprite id {sid} not found", file=sys.stderr)
            return 1
        if s.get("w") != 16 or s.get("h") != 16:
            print(f"extract_key_frames: id {sid} is {s.get('w')}x{s.get('h')}; need 16x16",
                  file=sys.stderr)
            return 1
        px = s.get("pixelBytes", [])
        at = s.get("attrBytes", [])
        if len(px) != 32:
            print(f"extract_key_frames: id {sid} pixelBytes len {len(px)} != 32", file=sys.stderr)
            return 1
        if len(at) != 4:
            print(f"extract_key_frames: id {sid} attrBytes len {len(at)} != 4", file=sys.stderr)
            return 1
        frames.append((sid, s.get("name", f"id{sid}"), px, at))

    def row(seq: list[int]) -> str:
        return ", ".join(f"0x{b:02X}" for b in seq)

    n = len(frames)
    lines: list[str] = []
    lines.append(f"// Auto-generated from {json_path.name} sprite ids {ids}.\n")
    lines.append("// 16x16 key-icon animation frames for the web wrapper intro.\n")
    lines.append("#pragma once\n")
    lines.append("#include <stdint.h>\n\n")
    lines.append("#define KEY_ICON_W      16\n")
    lines.append("#define KEY_ICON_H      16\n")
    lines.append(f"#define KEY_ICON_FRAMES {n}\n\n")

    lines.append(f"static const uint8_t key_icon_pixels[{n}][32] = {{\n")
    for sid, name, px, _ in frames:
        lines.append(f"    {{ {row(px)} }}, // id {sid} '{name}'\n")
    lines.append("};\n\n")

    lines.append(f"static const uint8_t key_icon_attrs[{n}][4] = {{\n")
    for sid, name, _, at in frames:
        lines.append(f"    {{ {row(at)} }}, // id {sid}\n")
    lines.append("};\n")

    rendered = "".join(lines)
    if out_path.is_file() and out_path.read_text(encoding="utf-8") == rendered:
        return 0
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(rendered, encoding="utf-8")
    print(f"extract_key_frames.py: wrote {out_path} ({n} frames {ids})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
