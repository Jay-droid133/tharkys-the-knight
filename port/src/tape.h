/*
 * tape.h - .tap file parser + cursor.
 *
 * A .tap file is a flat concatenation of blocks; each block is:
 *   [len_lo][len_hi]   uint16_t length, little-endian
 *   [flag]             1 byte (0=header, $FF=data, others rare)
 *   [...data...]       (len - 2) bytes payload
 *   [checksum]         1 byte XOR of flag + data
 *
 * The wrapper consumes this via a "tape trap": when the Z80 enters
 * LD-BYTES at $0556 in the 48K-compat ROM, emu.c asks tape_next() for
 * the next block whose flag matches A' and writes its payload straight
 * to the destination IX (bypassing the actual audio decoding loop).
 *
 * Mismatched blocks are skipped silently to match real-ROM LOAD ""
 * behaviour: e.g. LOAD "" CODE wants flag $FF; if it stumbles onto a
 * header (flag 0) first it ignores it and keeps reading.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    const uint8_t *data;
    size_t         size;
    size_t         cursor;   /* byte offset of next block's length field */
    bool           loaded;
} tape_t;

/* Attach a .tap blob (caller-owned, must outlive the tape_t). */
bool tape_load(tape_t *t, const uint8_t *data, size_t size);

/* Rewind to the first block (the data pointer stays the same). */
void tape_rewind(tape_t *t);

/* Find the next block whose flag byte matches want_flag, advancing
 * past any non-matching blocks. On success returns true and fills:
 *   *out_payload     -> pointer into the original blob, past flag byte
 *   *out_payload_len -> number of payload bytes (block_len - 2)
 * Returns false once the cursor reaches end of tape with no match. */
bool tape_next(tape_t *t, uint8_t want_flag,
               const uint8_t **out_payload, uint16_t *out_payload_len);

/* True once the cursor is past the end (nothing more to read). */
bool tape_at_end(const tape_t *t);
