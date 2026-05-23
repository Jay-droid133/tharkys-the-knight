#include "tape.h"

bool tape_load(tape_t *t, const uint8_t *data, size_t size) {
    if (!t || !data || size < 2) return false;
    t->data   = data;
    t->size   = size;
    t->cursor = 0;
    t->loaded = true;
    return true;
}

void tape_rewind(tape_t *t) {
    if (t) t->cursor = 0;
}

bool tape_at_end(const tape_t *t) {
    return !t || !t->loaded || t->cursor >= t->size;
}

bool tape_next(tape_t *t, uint8_t want_flag,
               const uint8_t **out_payload, uint16_t *out_payload_len) {
    if (!t || !t->loaded || !out_payload || !out_payload_len) return false;

    while (t->cursor + 2 <= t->size) {
        const uint16_t blen =
            (uint16_t)(t->data[t->cursor] | (t->data[t->cursor + 1] << 8));

        /* Block length must cover at least flag + checksum, and fit. */
        if (blen < 2 || t->cursor + 2 + blen > t->size) {
            t->cursor = t->size;
            return false;
        }

        const uint8_t flag = t->data[t->cursor + 2];
        const uint8_t *payload = &t->data[t->cursor + 3];
        const uint16_t payload_len = (uint16_t)(blen - 2);

        t->cursor += (size_t)(2 + blen);

        if (flag == want_flag) {
            *out_payload     = payload;
            *out_payload_len = payload_len;
            return true;
        }
        /* flag mismatch -> silently consume and try next block */
    }
    return false;
}
