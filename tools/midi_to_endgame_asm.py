#!/usr/bin/env python3
"""midi_to_endgame_asm.py — Reemplazo Python del music_converter.html (Poly3).

Lee un MIDI multi-pista (formato Type-1) y emite EndGameMusicTable_Bank7
para code/music_endgame_bank7.asm. Replica la logica del HTML:
  - Voice A = track con notas agudas (melody)
  - Voice B = REST (sin notas en EndGame)
  - Voice C = track con notas graves (bass)

Asignacion automatica: la pista con el promedio MIDI mas alto va a A,
la mas baja a C. (Para 2 pistas. Si hay solo 1, va a A y C=REST.)

Uso:
    python tools/midi_to_endgame_asm.py music/endgame.mid \\
        > code/music_endgame_bank7.asm

Notas:
  - AY clock = 1.75 MHz; period = round(1750000 / (16 * freq_hz)).
  - FPS = 25 (game tick rate).
  - Cada entry: 7 B = periodA(2) + periodB(2) + periodC(2) + dur(1).
  - Durations > 255 frames se trocean en chunks consecutivos.
  - Entries consecutivas con mismos periods se mergean.
  - Trim leading/trailing all-rest entries.
"""
import sys
from pathlib import Path

try:
    import mido
except ImportError:
    print("ERROR: pip install mido", file=sys.stderr)
    sys.exit(1)


AY_CLOCK = 1_750_000
FPS = 25
AY_PERIOD_MAX = 4095
LABEL = "EndGameMusicTable_Bank7"
HEADER_TEMPLATE = """; ==============================================================================
; music_endgame_bank7.asm - EndGameMusicTable en bank 7 (slot 3 paginado)
; ==============================================================================
; La tabla original vivia en slot 1 al lado del driver IRQ. Demasiado grande
; (1085 B) para slot 1 (que esta al 99% lleno). Movida aqui via prefetch:
;
;   - PrefetchMusic (slot 1, llamado desde MainLoop): pagina bank 7, copia
;     7 B desde MusicBank7Ptr al buffer en slot 1, repagina bank 0.
;   - MusicAdvanceNote (slot 1, llamado desde IRQ): cuando MusicTrackInBank7=1,
;     resetea MusicPtr al buffer y consume desde alli. Pone flag para que el
;     proximo PrefetchMusic refilen el buffer.
;
; Bank 7 paging desde MainLoop NO necesita alt-stack porque PrefetchMusic
; no hace PUSH/POP/CALL mientras bank 7 esta paginado — solo LDIR + IO.
; IRQ entrante hace PUSH/POP balanceados al area "alta" del bank 7 RAM (zona
; muerta sobre SP), nada se corrompe.
;
; Formato: Poly3 (A+B+C), 7 B/entry. Generado por tools/midi_to_endgame_asm.py
; desde {midi_filename}.
;
; Tempo: 100% | Notes: {n_entries} | Bytes: {bytes_total} | Duration: {dur_s:.2f}s @ 25fps
; ==============================================================================
"""

NOTE_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]


def midi_to_freq(midi_note):
    """A4 (midi 69) = 440 Hz. f = 440 * 2^((n - 69) / 12)."""
    return 440.0 * (2 ** ((midi_note - 69) / 12.0))


def midi_to_name(midi_note):
    octave = (midi_note // 12) - 1
    return f"{NOTE_NAMES[midi_note % 12]}{octave}"


def midi_to_period(midi_note):
    freq = midi_to_freq(midi_note)
    period = round(AY_CLOCK / (16 * freq))
    return max(1, min(AY_PERIOD_MAX, period))


def extract_notes(track, tempo_map, ticks_per_beat):
    """Extrae (start_sec, duration_sec, midi_note) por nota. tempo_map = lista
    (abs_tick, microseconds_per_beat) ordenada. Honora cambios de tempo."""

    def tick_to_sec(target_tick):
        prev_tick = 0
        prev_sec = 0.0
        for tt, tempo_us in tempo_map:
            if tt >= target_tick:
                break
            seg_ticks = tt - prev_tick
            prev_sec += seg_ticks * (tempo_us / 1_000_000.0) / ticks_per_beat
            prev_tick = tt
        # último segmento desde prev_tick hasta target_tick con el tempo actual
        cur_tempo = None
        for tt, tempo_us in tempo_map:
            if tt <= prev_tick:
                cur_tempo = tempo_us
            else:
                break
        if cur_tempo is None:
            cur_tempo = 500_000  # default 120 bpm
        seg_ticks = target_tick - prev_tick
        prev_sec += seg_ticks * (cur_tempo / 1_000_000.0) / ticks_per_beat
        return prev_sec

    abs_tick = 0
    active = {}  # midi_note -> start_tick
    notes = []
    for msg in track:
        abs_tick += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            active[msg.note] = abs_tick
        elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
            if msg.note in active:
                start_tick = active.pop(msg.note)
                start_sec = tick_to_sec(start_tick)
                end_sec = tick_to_sec(abs_tick)
                notes.append((start_sec, end_sec - start_sec, msg.note))
    return notes


def build_timeline(notes):
    """Convierte lista de notas a [(time_sec, period, name)] ordenada por tiempo.
    Inserta REST entre notas si hay gap. Termina con REST final."""
    if not notes:
        return [(0.0, 0, "REST")]
    notes = sorted(notes, key=lambda n: n[0])
    events = []
    last_end = 0.0
    for start, dur, midi in notes:
        if start > last_end + 1e-6:
            events.append((last_end, 0, "REST"))
        events.append((start, midi_to_period(midi), midi_to_name(midi)))
        last_end = start + dur
    events.append((last_end, 0, "REST"))
    return events


def active_at(timeline, t):
    """Última entry con time <= t. Devuelve (period, name)."""
    last = (0, "REST")
    for time, period, name in timeline:
        if time <= t + 1e-9:
            last = (period, name)
        else:
            break
    return last


def convert_poly3(midi_path):
    mf = mido.MidiFile(midi_path)
    tpb = mf.ticks_per_beat

    # Tempo map: recorrer todas las pistas para encontrar set_tempo.
    tempo_events = []  # (abs_tick, microseconds_per_beat)
    for track in mf.tracks:
        t = 0
        for msg in track:
            t += msg.time
            if msg.type == "set_tempo":
                tempo_events.append((t, msg.tempo))
    tempo_events.sort()
    if not tempo_events or tempo_events[0][0] != 0:
        tempo_events.insert(0, (0, 500_000))

    # Extraer notas por pista.
    tracks_notes = [extract_notes(t, tempo_events, tpb) for t in mf.tracks]
    # Descartar pistas sin notas (control/meta).
    indexed = [(i, ns) for i, ns in enumerate(tracks_notes) if ns]
    if not indexed:
        raise SystemExit("MIDI sin notas")

    # Asignar voice A = pista más aguda; voice C = pista más grave; B = REST.
    def avg_midi(notes):
        return sum(n[2] for n in notes) / len(notes)

    indexed.sort(key=lambda kv: -avg_midi(kv[1]))
    voiceA_notes = indexed[0][1]
    voiceC_notes = indexed[-1][1] if len(indexed) > 1 else []

    tlA = build_timeline(voiceA_notes)
    tlC = build_timeline(voiceC_notes)
    # voice B = REST permanente (single entry).
    tlB = [(0.0, 0, "REST")]

    # Puntos de cambio: union de tiempos de tlA + tlC.
    points = sorted({e[0] for e in tlA} | {e[0] for e in tlC})

    # firstNoteTime = min de primer note-on cualquiera.
    first_t = float("inf")
    for tl in (tlA, tlC):
        for time, period, _ in tl:
            if period > 0:
                if time < first_t:
                    first_t = time
                break
    if first_t == float("inf"):
        first_t = 0.0

    entries = []
    for i in range(len(points) - 1):
        t = points[i]
        t_next = points[i + 1]
        start_frame = round((t - first_t) * FPS)
        end_frame = round((t_next - first_t) * FPS)
        dur = end_frame - start_frame
        if dur <= 0:
            continue
        pA, nA = active_at(tlA, t)
        pC, nC = active_at(tlC, t)
        entries.append({
            "periodA": pA,
            "periodB": 0,
            "periodC": pC,
            "duration": dur,
            "nameA": nA,
            "nameC": nC,
        })
    return entries


def merge_consecutive(entries):
    if not entries:
        return []
    merged = [dict(entries[0])]
    for e in entries[1:]:
        last = merged[-1]
        if (e["periodA"] == last["periodA"]
                and e["periodB"] == last["periodB"]
                and e["periodC"] == last["periodC"]):
            last["duration"] += e["duration"]
        else:
            merged.append(dict(e))
    return merged


def split_long(entries):
    split = []
    for e in entries:
        remaining = e["duration"]
        while remaining > 0:
            chunk = min(255, remaining)
            d = dict(e)
            d["duration"] = chunk
            split.append(d)
            remaining -= chunk
    return split


def trim_silence(entries):
    while entries and entries[0]["periodA"] == 0 and entries[0]["periodB"] == 0 and entries[0]["periodC"] == 0:
        entries.pop(0)
    while entries and entries[-1]["periodA"] == 0 and entries[-1]["periodB"] == 0 and entries[-1]["periodC"] == 0:
        entries.pop()
    return entries


def emit_asm(entries, midi_path):
    bytes_total = len(entries) * 7 + 7
    total_frames = sum(e["duration"] for e in entries)
    dur_s = total_frames / FPS
    header = HEADER_TEMPLATE.format(
        midi_filename=str(midi_path).replace("\\", "/"),
        n_entries=len(entries),
        bytes_total=bytes_total,
        dur_s=dur_s,
    )
    lines = [header, f"{LABEL}:"]
    for e in entries:
        pa = f"${e['periodA']:04X}"
        pb = f"${e['periodB']:04X}"
        pc = f"${e['periodC']:04X}"
        dur_s = f"{e['duration']:>3}"
        comment = f"; A={e['nameA']} B=REST C={e['nameC']}"
        lines.append(
            f"    DEFW {pa} : DEFW {pb} : DEFW {pc} : DEFB {dur_s}   {comment}"
        )
    # Terminator
    lines.append("    DEFW 0     : DEFW 0     : DEFW 0     : DEFB   0   ; fin")
    return "\n".join(lines) + "\n"


def get_midi_bpm(midi_path):
    """Devuelve BPM del primer set_tempo encontrado, o 120 por defecto."""
    mf = mido.MidiFile(midi_path)
    for track in mf.tracks:
        for msg in track:
            if msg.type == "set_tempo":
                return 60_000_000 / msg.tempo
    return 120.0


def parse_bar_beat(s):
    """Parse 'BAR.BEAT' (e.g. '2.4') -> elapsed beats from start (0-indexed)."""
    if "." not in s:
        bar, beat = int(s), 1
    else:
        bar_str, beat_str = s.split(".", 1)
        bar = int(bar_str)
        beat = int(beat_str)
    # Convención Ableton: bar 1 beat 1 = inicio (0 elapsed). 4/4 por defecto.
    return (bar - 1) * 4 + (beat - 1)


def entries_until_frame(entries, target_frame):
    """Cuántas entries del array hay que dejar como 'intro' (antes del loop
    restart point) para que la posición acumulada sea >= target_frame."""
    acc = 0
    for i, e in enumerate(entries):
        if acc >= target_frame:
            return i
        acc += e["duration"]
    return len(entries)


def update_intro_entries_in_ay_sound(intro_entries, ay_sound_path):
    """Reescribe la línea `ENDGAME_INTRO_ENTRIES   EQU N` con el valor nuevo."""
    txt = Path(ay_sound_path).read_text(encoding="utf-8")
    import re
    new_txt, n = re.subn(
        r"(ENDGAME_INTRO_ENTRIES\s+EQU\s+)(\d+)",
        lambda m: m.group(1) + str(intro_entries),
        txt,
        count=1,
    )
    if n == 0:
        print(f"WARN: no encontre ENDGAME_INTRO_ENTRIES en {ay_sound_path}",
              file=sys.stderr)
        return False
    Path(ay_sound_path).write_text(new_txt, encoding="utf-8")
    return True


def main():
    args = sys.argv[1:]
    midi_path = None
    out_path = None
    loop_from = None
    ay_sound_path = "code/ay_sound.asm"

    i = 0
    positional = []
    while i < len(args):
        a = args[i]
        if a == "--loop-from":
            loop_from = args[i + 1]
            i += 2
        elif a == "--ay-sound":
            ay_sound_path = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1

    if not positional:
        print(
            "uso: midi_to_endgame_asm.py <midi> [<out.asm>] "
            "[--loop-from BAR.BEAT] [--ay-sound code/ay_sound.asm]",
            file=sys.stderr,
        )
        sys.exit(1)
    midi_path = positional[0]
    if len(positional) > 1:
        out_path = positional[1]

    entries = convert_poly3(midi_path)
    entries = merge_consecutive(entries)
    entries = split_long(entries)
    entries = trim_silence(entries)

    # Si --loop-from se pidió, calcular cuántas entries son "intro" (saltadas
    # al loopear) y actualizar ENDGAME_INTRO_ENTRIES en ay_sound.asm.
    if loop_from:
        bpm = get_midi_bpm(midi_path)
        elapsed_beats = parse_bar_beat(loop_from)
        elapsed_sec = elapsed_beats * (60.0 / bpm)
        target_frame = round(elapsed_sec * FPS)
        intro_entries = entries_until_frame(entries, target_frame)
        print(
            f"loop-from {loop_from} -> {elapsed_beats} beats @ {bpm:.1f} BPM "
            f"= {elapsed_sec:.3f}s = {target_frame} frames -> "
            f"ENDGAME_INTRO_ENTRIES = {intro_entries}",
            file=sys.stderr,
        )
        ok = update_intro_entries_in_ay_sound(intro_entries, ay_sound_path)
        if ok:
            print(f"OK: ENDGAME_INTRO_ENTRIES actualizado en {ay_sound_path}",
                  file=sys.stderr)

    asm = emit_asm(entries, midi_path)
    if out_path:
        Path(out_path).write_text(asm, encoding="utf-8")
        total_frames = sum(e["duration"] for e in entries)
        print(
            f"OK: {out_path}  ({len(entries)} entries, "
            f"{len(entries) * 7 + 7} B, {total_frames / FPS:.2f}s)",
            file=sys.stderr,
        )
    else:
        sys.stdout.write(asm)


if __name__ == "__main__":
    main()
