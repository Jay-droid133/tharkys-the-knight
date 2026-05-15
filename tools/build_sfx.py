#!/usr/bin/env python3
"""
build_sfx.py — Compile code/sfx_library.json into code/sfx_data.asm.

The library JSON is the source of truth, edited by tools/sfx_editor.html
(Bfxr-style UI) or by hand. This script validates the schema and emits a
single ASM file the assembler picks up.

Sources:
  code/sfx_library.json — array of SFX, each with: id, name, channels[], commands[]

Output:
  code/sfx_data.asm
    - AYSFX_<NAME> EQUs (sequential ids, indices into AySfxTable)
    - AYSFX_COUNT EQU
    - AySfxTable:           DEFW AySfxData_<Name>, ...
    - AySfxChannelMaskTable: DEFB <mask>, ...   ; bit 0=A 1=B 2=C 3=Noise
    - AySfxData_<Name>:     opcode stream, terminated by SFXCMD_END

Opcode IDs (must match SFXCMD_* in code/sfx_interp.asm):
  $00 END                     0 args
  $01 WAIT       frames       1B
  $02 TONE       ch lo hi     1B + 2B
  $03 VOL        ch v         1B + 1B
  $04 MIXER      mask         1B
  $05 NOISE      period       1B
  $06 ENV_SHAPE  shape        1B
  $07 ENV_PERIOD lo hi        2B
  $08 SWEEP_TONE ch from to f 1B + 2B + 2B + 1B
  $09 SWEEP_VOL  ch from to f 1B + 1B + 1B + 1B

Usage:
    python tools/build_sfx.py
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
JSON_PATH = REPO / "code" / "sfx_library.json"
ASM_PATH = REPO / "code" / "sfx_data.asm"

# Channel name -> opcode arg byte (used inside commands).
CH_TO_BYTE = {"A": 0, "B": 1, "C": 2}

# Channel name -> reservation mask bit (used in AySfxChannelMaskTable).
CH_TO_MASK_BIT = {"A": 0x01, "B": 0x02, "C": 0x04, "N": 0x08}

# Opcode table. Each entry: (id, [(arg_name, kind), ...])
# kind: "u8" (1 byte), "u16le" (2 bytes), "ch" (channel name -> 1 byte 0/1/2)
#
# SWEEP_TONE / SWEEP_VOL take {ch, from, to, frames} in JSON (human-friendly)
# but encode as {ch, from, delta, frames} where delta is precomputed at build
# time. This keeps the Z80 ticker arithmetic to a single ADD HL,DE per frame.
# See encode_sweep_tone / encode_sweep_vol below.
OPCODES = {
    "END":        (0x00, []),
    "WAIT":       (0x01, [("frames", "u8")]),
    "TONE":       (0x02, [("ch", "ch"), ("period", "u16le")]),
    "VOL":        (0x03, [("ch", "ch"), ("v", "u8")]),
    "MIXER":      (0x04, [("mask", "u8")]),
    "NOISE":      (0x05, [("period", "u8")]),
    "ENV_SHAPE":  (0x06, [("shape", "u8")]),
    "ENV_PERIOD": (0x07, [("period", "u16le")]),
    "SWEEP_TONE": (0x08, "__sweep__"),  # custom encoder
    "SWEEP_VOL":  (0x09, "__sweep__"),
}


def fail(msg):
    print(f"build_sfx: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def id_to_label(sfx_id):
    # "AYSFX_PLAYER_HIT" -> "PlayerHit"
    parts = sfx_id.split("_")[1:]
    return "".join(p.capitalize() for p in parts)


def encode_arg(value, kind, ctx):
    if kind == "u8":
        if not isinstance(value, int) or not (0 <= value <= 255):
            fail(f"{ctx}: u8 out of range: {value!r}")
        return [value]
    if kind == "u16le":
        if not isinstance(value, int) or not (0 <= value <= 65535):
            fail(f"{ctx}: u16 out of range: {value!r}")
        return [value & 0xFF, (value >> 8) & 0xFF]
    if kind == "ch":
        if value not in CH_TO_BYTE:
            fail(f"{ctx}: channel must be A/B/C, got {value!r}")
        return [CH_TO_BYTE[value]]
    fail(f"{ctx}: unknown arg kind: {kind}")


def encode_sweep(cmd, opcode_id, is_vol, ctx):
    # Common args: ch, from, to, frames. We emit: opcode, ch_byte, from_lo,
    # from_hi, delta_lo, delta_hi, frames (7 bytes).
    for arg in ("ch", "from", "to", "frames"):
        if arg not in cmd:
            fail(f"{ctx}: missing arg {arg!r}")
    ch = cmd["ch"]
    if ch not in CH_TO_BYTE:
        fail(f"{ctx}: invalid channel {ch!r}")
    frm = cmd["from"]
    to = cmd["to"]
    frames = cmd["frames"]
    if not (1 <= frames <= 255):
        fail(f"{ctx}: frames must be 1..255 (got {frames})")
    if is_vol:
        if not (0 <= frm <= 15 and 0 <= to <= 15):
            fail(f"{ctx}: vol must be 0..15 (got from={frm}, to={to})")
        frm_fp = frm << 8            # 8.8 fixed-point — hi byte goes to AY
        to_fp = to << 8
    else:
        if not (0 <= frm <= 4095 and 0 <= to <= 4095):
            fail(f"{ctx}: tone period must be 0..4095 (got from={frm}, to={to})")
        frm_fp = frm
        to_fp = to
    # Signed integer division. Two's-complement to fit in u16.
    delta = ((to_fp - frm_fp) // frames) & 0xFFFF
    return [
        opcode_id,
        CH_TO_BYTE[ch],
        frm_fp & 0xFF, (frm_fp >> 8) & 0xFF,
        delta & 0xFF, (delta >> 8) & 0xFF,
        frames,
    ]


def encode_command(cmd, ctx):
    op = cmd.get("op")
    if op not in OPCODES:
        fail(f"{ctx}: unknown op: {op!r}")
    opcode_id, arg_spec = OPCODES[op]
    if arg_spec == "__sweep__":
        return encode_sweep(cmd, opcode_id, is_vol=(op == "SWEEP_VOL"), ctx=ctx), op
    out = [opcode_id]
    for name, kind in arg_spec:
        if name not in cmd:
            fail(f"{ctx}: op {op} missing arg {name!r}")
        out.extend(encode_arg(cmd[name], kind, f"{ctx}.{name}"))
    return out, op


def compute_channel_mask(sfx):
    mask = 0
    for ch in sfx.get("channels", []):
        if ch not in CH_TO_MASK_BIT:
            fail(f"{sfx['id']}: channel '{ch}' invalid (use A/B/C/N)")
        mask |= CH_TO_MASK_BIT[ch]
    return mask


def emit_asm(library):
    L = []
    L.append("; ==============================================================================")
    L.append("; sfx_data.asm — GENERATED by tools/build_sfx.py from code/sfx_library.json")
    L.append("; DO NOT EDIT BY HAND. Re-run build_sfx.py to regenerate.")
    L.append("; ==============================================================================")
    L.append("")

    sfxs = library["sfx"]

    L.append("; --- SFX id constants (indices into AySfxTable) ---")
    for i, sfx in enumerate(sfxs):
        L.append(f"{sfx['id']:<28} EQU {i}")
    L.append(f"{'AYSFX_COUNT':<28} EQU {len(sfxs)}")
    L.append("")

    L.append("; --- Pointer table: SFX id -> data block ---")
    L.append("AySfxTable:")
    for sfx in sfxs:
        label = "AySfxData_" + id_to_label(sfx["id"])
        L.append(f"    DEFW {label}")
    L.append("")

    L.append("; --- Channel reservation mask per SFX (bits: 0=A, 1=B, 2=C, 3=Noise) ---")
    L.append("AySfxChannelMaskTable:")
    for sfx in sfxs:
        mask = compute_channel_mask(sfx)
        chs = "".join(sfx.get("channels", [])) or "-"
        L.append(f"    DEFB %{mask:08b}    ; {sfx['id']} ({chs})")
    L.append("")

    L.append("; --- SFX data blocks ---")
    for sfx in sfxs:
        label = "AySfxData_" + id_to_label(sfx["id"])
        ctx_base = sfx["id"]
        L.append(f"{label}:    ; {sfx['name']}")
        total_bytes = 0
        seen_end = False
        for i, cmd in enumerate(sfx["commands"]):
            bs, op = encode_command(cmd, f"{ctx_base}.cmd[{i}]")
            total_bytes += len(bs)
            byte_str = ", ".join(f"${b:02X}" for b in bs)
            args_pretty = ", ".join(f"{k}={v}" for k, v in cmd.items() if k != "op")
            L.append(f"    DEFB {byte_str:<32}; {op}" + (f" {args_pretty}" if args_pretty else ""))
            if op == "END":
                seen_end = True
                break
        if not seen_end:
            # Auto-append END as a safety net.
            L.append("    DEFB $00                        ; END (auto-appended)")
            total_bytes += 1
        L.append(f"    ; total: {total_bytes} bytes")
        L.append("")

    return "\n".join(L) + "\n"


def validate(library):
    if library.get("version") != 1:
        fail(f"unsupported schema version: {library.get('version')!r}")
    if "sfx" not in library or not isinstance(library["sfx"], list):
        fail("missing or invalid 'sfx' array")

    seen_ids = set()
    for i, sfx in enumerate(library["sfx"]):
        ctx = f"sfx[{i}]"
        if "id" not in sfx:
            fail(f"{ctx}: missing 'id'")
        if not re.match(r"^AYSFX_[A-Z][A-Z0-9_]*$", sfx["id"]):
            fail(f"{ctx}: invalid id format: {sfx['id']!r} (must be AYSFX_UPPER_SNAKE)")
        if sfx["id"] in seen_ids:
            fail(f"{ctx}: duplicate id: {sfx['id']}")
        seen_ids.add(sfx["id"])
        if "commands" not in sfx or not isinstance(sfx["commands"], list):
            fail(f"{ctx}: missing or invalid 'commands' array")
        if "channels" not in sfx or not isinstance(sfx["channels"], list):
            fail(f"{ctx}: missing or invalid 'channels' array")


def main():
    if not JSON_PATH.exists():
        fail(f"missing {JSON_PATH}")
    with JSON_PATH.open("r", encoding="utf-8") as f:
        library = json.load(f)
    validate(library)
    asm = emit_asm(library)
    ASM_PATH.write_text(asm, encoding="utf-8")
    print(f"build_sfx: wrote {ASM_PATH} ({len(library['sfx'])} SFX)")


if __name__ == "__main__":
    main()
