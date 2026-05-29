#!/usr/bin/env python3
"""Generate the PWA icons (icon-192.png, icon-512.png) for the web build.

Pure stdlib (zlib+struct) PNG writer -- no PIL/Pillow dependency. Draws a
simple, bold knight's sword on a dark field so it reads at small home-screen
sizes. Maskable-safe: all content sits inside the inner ~80% safe zone.

This is a placeholder you can replace with your own pixel art at any time:
just drop icon-192.png / icon-512.png (square, opaque) into this folder and
re-deploy. Run:  python port/web/gen_icons.py
"""
import zlib, struct, os

# Palette (RGB)
BG     = (0x0c, 0x0c, 0x16)   # near-black navy field
BLADE  = (0xec, 0xec, 0xec)   # silver/white blade
EDGE   = (0xff, 0xff, 0xff)   # blade highlight
GUARD  = (0xff, 0xc8, 0x00)   # gold crossguard + pommel
GRIP   = (0x6b, 0x42, 0x22)   # brown grip


def write_png(path, w, h, rgb):
    """rgb: bytearray of length w*h*3 (8-bit RGB, no alpha)."""
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))
    raw = bytearray()
    for y in range(h):
        raw.append(0)                       # filter type 0 (none)
        raw += rgb[y * w * 3:(y + 1) * w * 3]
    sig  = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)   # color type 2 = RGB
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def render(S):
    buf = bytearray(S * S * 3)
    # fill background
    for i in range(S * S):
        buf[i*3:i*3+3] = bytes(BG)

    def px(x, y, c):
        if 0 <= x < S and 0 <= y < S:
            o = (y * S + x) * 3
            buf[o:o+3] = bytes(c)

    def rect(x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1)):
            for x in range(int(x0), int(x1)):
                px(x, y, c)

    def disc(cx, cy, r, c):
        r2 = r * r
        for y in range(int(cy - r), int(cy + r + 1)):
            for x in range(int(cx - r), int(cx + r + 1)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                    px(x, y, c)

    cx = S / 2.0
    bw = max(2, int(S * 0.085))            # blade half-width *2
    # blade body (vertical bar)
    rect(cx - bw/2, S*0.14, cx + bw/2, S*0.66, BLADE)
    # blade highlight (thin left strip)
    rect(cx - bw/2, S*0.14, cx - bw/2 + max(1, S*0.012), S*0.66, EDGE)
    # blade tip (triangle narrowing to a point at the top)
    tip_top = S * 0.075
    tip_bot = S * 0.14
    for y in range(int(tip_top), int(tip_bot)):
        t = (y - tip_top) / (tip_bot - tip_top)      # 0 at point -> 1 at body
        hw = (bw / 2.0) * t
        rect(cx - hw, y, cx + hw, y + 1, BLADE)
    # crossguard (gold horizontal bar)
    gw = S * 0.50
    rect(cx - gw/2, S*0.635, cx + gw/2, S*0.695, GUARD)
    # grip (brown vertical bar below the guard)
    grw = max(2, int(S * 0.055))
    rect(cx - grw/2, S*0.695, cx + grw/2, S*0.83, GRIP)
    # pommel (gold disc)
    disc(cx, S*0.85, S*0.045, GUARD)
    return buf


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    for size in (192, 512):
        out = os.path.join(here, f"icon-{size}.png")
        write_png(out, size, size, render(size))
        print("wrote", out)
