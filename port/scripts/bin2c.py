#!/usr/bin/env python3
"""Convert a binary file into a C header with a uint8_t array.

Usage:
    bin2c.py <input_binary> <output_header> <symbol_name>

Generates:
    static const uint8_t <symbol_name>[<size>] = { 0x.., 0x.., ... };
    static const unsigned int <symbol_name>_len = <size>;

Idempotent: if the output already matches the input, the file is not
rewritten (preserves mtime, plays nicely with build-system dep tracking).
"""

from __future__ import annotations

import sys
from pathlib import Path


def encode(data: bytes, symbol: str, source_name: str) -> str:
    """Render the C header text for the given blob."""
    lines: list[str] = []
    lines.append(f"// Auto-generated from {source_name} - do not edit by hand.\n")
    lines.append("#pragma once\n")
    lines.append("#include <stdint.h>\n\n")
    lines.append(f"static const uint8_t {symbol}[{len(data)}] = {{\n")

    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        hex_bytes = ", ".join(f"0x{b:02X}" for b in chunk)
        lines.append(f"    {hex_bytes},\n")

    lines.append("};\n")
    lines.append(f"static const unsigned int {symbol}_len = {len(data)};\n")
    return "".join(lines)


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 1

    in_path = Path(argv[1])
    out_path = Path(argv[2])
    symbol = argv[3]

    if not in_path.is_file():
        print(f"bin2c.py: input not found: {in_path}", file=sys.stderr)
        return 1

    data = in_path.read_bytes()
    rendered = encode(data, symbol, in_path.name)

    # Skip rewrite if content is unchanged so make/ninja don't rebuild.
    if out_path.is_file() and out_path.read_text(encoding="utf-8") == rendered:
        return 0

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(rendered, encoding="utf-8")
    print(f"bin2c.py: wrote {out_path} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
