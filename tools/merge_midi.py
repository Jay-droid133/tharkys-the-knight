#!/usr/bin/env python3
"""
merge_midi.py - combina varios MIDIs Type-0 (single-track) en un MIDI Type-1
multi-pista. Pensado para Ableton: cuando arrastras un clip fuera de Live,
exporta un MIDI Type-0 con tempo + notas. Este script toma 2..N de esos y
produce un MIDI multi-pista listo para el music_converter.html.

Uso:
    python tools/merge_midi.py out.mid in1.mid in2.mid [in3.mid ...]

Ejemplo:
    python tools/merge_midi.py music/endgame.mid music/bass.mid music/melody.mid

Sin dependencias externas. Parser SMF minimal (chunks MThd + MTrk).
"""
import sys
import struct
from pathlib import Path


def read_chunk(buf, off):
    if off + 8 > len(buf):
        raise ValueError(f"chunk truncado en offset {off}")
    tag = buf[off:off + 4]
    length = struct.unpack(">I", buf[off + 4:off + 8])[0]
    data = buf[off + 8:off + 8 + length]
    if len(data) != length:
        raise ValueError(f"chunk {tag} truncado: esperaba {length} got {len(data)}")
    return tag, data, off + 8 + length


def parse_midi(path):
    buf = Path(path).read_bytes()
    tag, header, off = read_chunk(buf, 0)
    if tag != b"MThd":
        raise ValueError(f"{path}: no es un MIDI (header tag = {tag!r})")
    fmt, ntrks, division = struct.unpack(">HHH", header[:6])
    tracks = []
    while off < len(buf):
        tag, data, off = read_chunk(buf, off)
        if tag == b"MTrk":
            tracks.append(data)
    return fmt, ntrks, division, tracks


def strip_end_of_track(track_data):
    """Quita el meta-event End-of-Track final (FF 2F 00) si está presente.
    Devuelve los bytes sin ese evento. Asume que viene al final como ultimos
    3-4 bytes (delta + FF 2F 00)."""
    # Busca el ultimo FF 2F 00. El delta VLQ que lo precede puede ser 1..4 B.
    # Para simplicidad: si los 3 ultimos bytes son FF 2F 00, retrocede mientras
    # los bytes anteriores tengan bit 7 = 1 (VLQ continuation) o sean el primer
    # byte VLQ.
    if len(track_data) < 3:
        return track_data
    if track_data[-3:] != b"\xff\x2f\x00":
        return track_data
    # Retrocede para incluir el delta VLQ del EOT.
    i = len(track_data) - 4
    # Caso comun: delta = 0 (1 byte sin bit 7) -> i apunta a ese byte.
    # Si ese byte tiene bit 7 set, retrocede mientras siga teniendo bit 7.
    while i > 0 and (track_data[i] & 0x80):
        i -= 1
    # i ahora apunta al ultimo byte sin bit 7 (= ultimo byte de la VLQ del EOT)
    # o al primer byte si hubo solo 1 byte. El delta empieza justo despues del
    # byte anterior si ese byte tampoco es VLQ del EOT.
    # Mas robusto: el delta puede tener 1..4 bytes. Recortamos hasta el primer
    # byte sin bit 7 hacia atras desde len-4.
    eot_start = i  # primer byte del delta del EOT
    return track_data[:eot_start]


def append_end_of_track(track_data):
    """Aniade el meta-event End-of-Track (delta=0 FF 2F 00)."""
    return track_data + b"\x00\xff\x2f\x00"


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    out_path = sys.argv[1]
    in_paths = sys.argv[2:]

    parsed = []
    for p in in_paths:
        fmt, ntrks, division, tracks = parse_midi(p)
        if len(tracks) == 0:
            raise ValueError(f"{p}: sin tracks")
        if len(tracks) > 1:
            print(f"warning: {p} es Type-{fmt} con {len(tracks)} tracks; uso solo el primero")
        parsed.append((fmt, ntrks, division, tracks[0], p))

    # Verifica PPQ comun (todos los clips del mismo Live set deberian coincidir).
    divisions = {d for (_, _, d, _, _) in parsed}
    if len(divisions) > 1:
        raise ValueError(f"PPQ inconsistente entre MIDIs: {divisions}. "
                         "Re-exporta desde el mismo Live set.")
    division = divisions.pop()

    # Construye Type-1: header + tracks. Mantenemos el meta (tempo, time-sig)
    # del primer MIDI integrado en su pista; las demas pistas conservan tambien
    # su contenido (Ableton suele repetir el tempo en cada export).
    out = bytearray()
    out += b"MThd"
    out += struct.pack(">I", 6)
    out += struct.pack(">HHH", 1, len(parsed), division)

    for fmt, ntrks, _, track, p in parsed:
        # Asegura EOT al final.
        track_clean = strip_end_of_track(track)
        track_final = append_end_of_track(track_clean)
        out += b"MTrk"
        out += struct.pack(">I", len(track_final))
        out += track_final

    Path(out_path).write_bytes(bytes(out))
    print(f"OK: {out_path}  ({len(parsed)} tracks, PPQ={division})")
    for _, _, _, _, p in parsed:
        print(f"  + {p}")


if __name__ == "__main__":
    main()
