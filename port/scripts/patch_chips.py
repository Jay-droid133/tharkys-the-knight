#!/usr/bin/env python3
"""Patch chips/systems/zx.h to emulate the Spectrum floating data bus.

chips/zx.h does not handle the IORQ + M1 cycle (interrupt acknowledge).
On real ZX Spectrums the ULA does not drive the data bus during ack, so
it floats high and reads as $FF. Games using IM 2 with a uniform vector
table (the standard Spectrum idiom) depend on this; without it the byte
the CPU latches as the low half of the vector is whatever rubbish was
last on the bus, and the IM 2 read jumps somewhere random.

Tharkys hits this when the magic compass BFS's "visited" array overlaps
the first 60 bytes of its IM 2 table at $7A00. The table is intact past
the overlap, so on real hardware (bus = $FF) the IRQ vector resolves
fine via $7AFF/$7B00; on chips, ~24% of the time the bus byte lands in
the corrupted range and the next IRQ flies off into garbage.

This patch inserts a small `if (pins & Z80_M1) ...` arm at the top of
the IORQ block so the wrapper behaves like a real Spectrum during ack.
Idempotent: re-runs are no-ops, runs after a fresh FetchContent of
chips will re-apply automatically.
"""

from __future__ import annotations

import sys
from pathlib import Path

PATCH_MARKER = "/* tharkys-wrapper: floating bus during IRQ ack */"

ORIGINAL = (
    "    else if (pins & Z80_IORQ) {\n"
    "        if ((pins & Z80_A0) == 0) {\n"
)

PATCHED = (
    "    else if (pins & Z80_IORQ) {\n"
    f"        {PATCH_MARKER}\n"
    "        if (pins & Z80_M1) {\n"
    "            /* Interrupt acknowledge: Spectrum ULA leaves the data bus\n"
    "             * floating, which reads as $FF on real hardware. Games\n"
    "             * with a uniform IM 2 vector table rely on this. */\n"
    "            Z80_SET_DATA(pins, 0xFF);\n"
    "        }\n"
    "        else if ((pins & Z80_A0) == 0) {\n"
)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: patch_chips.py <path/to/chips/systems/zx.h>", file=sys.stderr)
        return 1

    path = Path(argv[1])
    if not path.is_file():
        print(f"patch_chips.py: not a file: {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")

    if PATCH_MARKER in text:
        return 0  # already patched

    if ORIGINAL not in text:
        print(
            f"patch_chips.py: anchor not found in {path}.\n"
            f"Upstream chips/zx.h IORQ block has changed shape; update this script.",
            file=sys.stderr,
        )
        return 1

    path.write_text(text.replace(ORIGINAL, PATCHED, 1), encoding="utf-8")
    print(f"patch_chips.py: floating-bus fix applied to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
