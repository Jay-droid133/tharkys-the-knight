#!/usr/bin/env python3
"""replace_bass_track.py - reemplaza el track 0 (bass) de un MIDI Type-1
por el track 0 de un MIDI Type-0. Mantiene los demás tracks intactos.

Uso:
    python tools/replace_bass_track.py base.mid new_bass.mid out.mid

Necesario porque al extraer melody.mid del original (Ableton drag-out),
el clip vuelve a empezar en tick 0, perdiendo el offset que tenía dentro
del proyecto. Si ese melody ya no se sincroniza con la composicion
original, hay que reusar el endgame viejo como base.
"""
import sys, struct
from pathlib import Path

def read_chunk(buf, off):
    tag = buf[off:off+4]
    length = struct.unpack(">I", buf[off+4:off+8])[0]
    data = buf[off+8:off+8+length]
    return tag, data, off + 8 + length

def main():
    if len(sys.argv) != 4:
        print(__doc__); sys.exit(1)
    base = Path(sys.argv[1]).read_bytes()
    new_bass = Path(sys.argv[2]).read_bytes()
    out_path = Path(sys.argv[3])

    # Parse base header
    tag, hdr, off = read_chunk(base, 0)
    assert tag == b'MThd'
    fmt, n_tracks, div = struct.unpack(">HHH", hdr[:6])
    assert fmt == 1, f"base debe ser Type-1, es Type-{fmt}"
    assert n_tracks >= 2, f"base necesita >= 2 tracks, tiene {n_tracks}"

    # Parse base tracks
    base_tracks = []
    while off < len(base):
        tag, data, off = read_chunk(base, off)
        if tag == b'MTrk':
            base_tracks.append(data)

    # Parse new_bass: single MTrk
    tag2, hdr2, off2 = read_chunk(new_bass, 0)
    assert tag2 == b'MThd'
    fmt2, n_tracks2, div2 = struct.unpack(">HHH", hdr2[:6])
    assert div == div2, f"PPQ mismatch: base={div} new_bass={div2}"
    tag2, new_track, _ = read_chunk(new_bass, off2)
    assert tag2 == b'MTrk'

    # Replace track 0 with new_bass track
    base_tracks[0] = new_track

    # Re-emit
    out = bytearray()
    out += b'MThd'
    out += struct.pack(">I", 6)
    out += struct.pack(">HHH", 1, len(base_tracks), div)
    for tr in base_tracks:
        out += b'MTrk'
        out += struct.pack(">I", len(tr))
        out += tr
    out_path.write_bytes(out)
    print(f"OK: {out_path} ({len(base_tracks)} tracks, PPQ={div})")
    print(f"  track 0 replaced with {sys.argv[2]} ({len(new_track)} B)")
    print(f"  track 1+ preserved from {sys.argv[1]}")

if __name__ == "__main__":
    main()
