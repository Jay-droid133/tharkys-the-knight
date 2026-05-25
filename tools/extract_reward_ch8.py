#!/usr/bin/env python3
"""Reconstruct the 768-byte reward.ch8 binary from reward_font_data.inc.

The .inc lives in code/ and contains the font data as DEFB statements
(the source format Damien Guard himself distributes alongside the
.ch8). The desktop wrapper still wants the raw .ch8 to embed via bin2c,
so this tool turns the .inc back into a flat binary at build time --
no .ch8 is checked into the repo.

Usage:
    extract_reward_ch8.py <input.inc> <output.ch8>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1
    src = Path(argv[1]).read_text(encoding="utf-8")
    # DEFB statements may have leading whitespace and commas; pull every
    # $XX literal in source order.
    hex_bytes = re.findall(r"\$([0-9A-Fa-f]{1,2})", src)
    data = bytes(int(b, 16) for b in hex_bytes)
    if len(data) != 768:
        print(f"extract_reward_ch8.py: expected 768 bytes, got {len(data)}",
              file=sys.stderr)
        return 1
    out_path = Path(argv[2])
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
