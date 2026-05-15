/*
 * emu.c - chips/zx integration.
 *
 * - CHIPS_IMPL lives here (single translation unit).
 * - zx_roms.h is also included here so its non-static ROM arrays don't
 *   end up linked twice.
 * - chips' built-in zx_quickload() only reads .z80 files; this game ships
 *   as .sna, so a 128K-SNA loader is implemented below.
 */

#include "emu.h"

#define CHIPS_IMPL
#include "chips_common.h"
#include "z80.h"
#include "beeper.h"
#include "ay38910.h"
#include "mem.h"
#include "kbd.h"
#include "clk.h"
#include "zx.h"

#include "zx_roms.h"

#include <stdlib.h>
#include <string.h>

struct emu {
    zx_t  zx;
    void (*audio_cb)(const float *, int, void *);
    void  *audio_user;
};

/* ------------------------------------------------------------------------- */
/* Audio: chips fires this with float samples; we forward to the host.       */
/* ------------------------------------------------------------------------- */
static void chips_audio_trampoline(const float *samples, int num_samples, void *user) {
    emu_t *e = (emu_t *)user;
    if (e && e->audio_cb) {
        e->audio_cb(samples, num_samples, e->audio_user);
    }
}

/* ------------------------------------------------------------------------- */
/* 128K memory paging: replicates chips' static _zx_update_memory_map_zx128. */
/* Used only by the SNA loader to install the snapshot's port-7FFD state.   */
/* ------------------------------------------------------------------------- */
static void update_memory_map_128(zx_t *zx, uint8_t data) {
    if (zx->memory_paging_disabled) return;

    zx->last_mem_config   = data;
    zx->display_ram_bank  = (data & (1 << 3)) ? 7 : 5;

    mem_map_ram(&zx->mem, 0, 0xC000, 0x4000, zx->ram[data & 0x07]);
    mem_map_rom(&zx->mem, 0, 0x0000, 0x4000, zx->rom[(data >> 4) & 1]);

    if (data & (1 << 5)) {
        zx->memory_paging_disabled = true;
    }
}

/* ------------------------------------------------------------------------- */
/* Lifecycle                                                                 */
/* ------------------------------------------------------------------------- */
emu_t *emu_create(const emu_desc_t *desc) {
    emu_t *e = (emu_t *)calloc(1, sizeof(*e));
    if (!e) return NULL;

    if (desc) {
        e->audio_cb   = desc->audio_cb;
        e->audio_user = desc->audio_user;
    }

    const zx_desc_t zd = {
        .type          = ZX_TYPE_128,
        .joystick_type = ZX_JOYSTICKTYPE_KEMPSTON,
        .audio = {
            .callback = {
                .func      = chips_audio_trampoline,
                .user_data = e,
            },
            .sample_rate = desc && desc->sample_rate > 0 ? desc->sample_rate : 44100,
        },
        .roms = {
            .zx128_0 = { .ptr = dump_amstrad_zx128k_0_bin, .size = sizeof(dump_amstrad_zx128k_0_bin) },
            .zx128_1 = { .ptr = dump_amstrad_zx128k_1_bin, .size = sizeof(dump_amstrad_zx128k_1_bin) },
        },
    };
    zx_init(&e->zx, &zd);
    return e;
}

void emu_destroy(emu_t *e) {
    if (!e) return;
    zx_discard(&e->zx);
    free(e);
}

/* ------------------------------------------------------------------------- */
/* SNA 128K loader.                                                          */
/*                                                                           */
/* Format (131103 bytes total):                                              */
/*   [0..26]      27-byte header (I, alt regs, IFF, R, AF, SP, IM, border)   */
/*   [27..49178]  48 KB dump: bank 5 + bank 2 + currently-paged bank         */
/*   [49179..80]  PC (lo, hi)                                                */
/*   [49181]      port $7FFD value                                           */
/*   [49182]      TR-DOS flag (ignored)                                      */
/*   [49183..end] 5 x 16 KB = 81920 bytes, remaining banks in 0..7 order     */
/*                excluding {2, 5, currently-paged}                          */
/* ------------------------------------------------------------------------- */
#define SNA_128_SIZE (27 + 48 * 1024 + 4 + 5 * 16 * 1024)  /* = 131103 */

bool emu_load_sna(emu_t *e, const uint8_t *data, size_t size) {
    if (!e || !data || size != SNA_128_SIZE) return false;

    zx_t *zx = &e->zx;

    /* 27-byte header */
    const uint8_t  I    = data[0];
    const uint16_t HLa  = (uint16_t)(data[1]  | (data[2]  << 8));
    const uint16_t DEa  = (uint16_t)(data[3]  | (data[4]  << 8));
    const uint16_t BCa  = (uint16_t)(data[5]  | (data[6]  << 8));
    const uint16_t AFa  = (uint16_t)(data[7]  | (data[8]  << 8));
    const uint16_t HL   = (uint16_t)(data[9]  | (data[10] << 8));
    const uint16_t DE   = (uint16_t)(data[11] | (data[12] << 8));
    const uint16_t BC   = (uint16_t)(data[13] | (data[14] << 8));
    const uint16_t IY   = (uint16_t)(data[15] | (data[16] << 8));
    const uint16_t IX   = (uint16_t)(data[17] | (data[18] << 8));
    const uint8_t  iff  = data[19];
    const uint8_t  R    = data[20];
    const uint16_t AF   = (uint16_t)(data[21] | (data[22] << 8));
    const uint16_t SP   = (uint16_t)(data[23] | (data[24] << 8));
    const uint8_t  IM   = data[25];
    const uint8_t  brdr = data[26] & 0x07;

    /* First 48 KB always: bank 5 then bank 2 then currently-paged bank */
    memcpy(zx->ram[5], data + 27,                  0x4000);
    memcpy(zx->ram[2], data + 27 + 0x4000,         0x4000);

    /* Post-dump fields */
    const uint16_t PC        = (uint16_t)(data[49179] | (data[49180] << 8));
    const uint8_t  out_7ffd  = data[49181];
    const uint8_t  cur_bank  = out_7ffd & 0x07;
    /* uint8_t trdos = data[49182]; -- not modelled */

    memcpy(zx->ram[cur_bank], data + 27 + 0x4000 * 2, 0x4000);

    /* Remaining five banks in numerical order skipping {2, 5, cur_bank} */
    const uint8_t *p = data + 49183;
    for (int b = 0; b <= 7; b++) {
        if (b == 2 || b == 5 || b == cur_bank) continue;
        memcpy(zx->ram[b], p, 0x4000);
        p += 0x4000;
    }

    /* CPU registers */
    z80_reset(&zx->cpu);
    zx->cpu.a   = (uint8_t)(AF  >> 8);  zx->cpu.f = (uint8_t)(AF  & 0xFF);
    zx->cpu.b   = (uint8_t)(BC  >> 8);  zx->cpu.c = (uint8_t)(BC  & 0xFF);
    zx->cpu.d   = (uint8_t)(DE  >> 8);  zx->cpu.e = (uint8_t)(DE  & 0xFF);
    zx->cpu.h   = (uint8_t)(HL  >> 8);  zx->cpu.l = (uint8_t)(HL  & 0xFF);
    zx->cpu.ix  = IX;
    zx->cpu.iy  = IY;
    zx->cpu.af2 = AFa;
    zx->cpu.bc2 = BCa;
    zx->cpu.de2 = DEa;
    zx->cpu.hl2 = HLa;
    zx->cpu.sp  = SP;
    zx->cpu.i   = I;
    zx->cpu.r   = R;
    zx->cpu.iff1 = zx->cpu.iff2 = ((iff & 0x04) != 0);
    zx->cpu.im   = (uint8_t)(IM & 0x03);

    /* Border + memory map */
    zx->border_color           = brdr;
    zx->memory_paging_disabled = false;
    update_memory_map_128(zx, out_7ffd);

    /* Prime the CPU at the snapshot's PC. */
    zx->pins = z80_prefetch(&zx->cpu, PC);
    return true;
}

/* ------------------------------------------------------------------------- */
/* Per-frame execution                                                       */
/* ------------------------------------------------------------------------- */
void emu_run_frame(emu_t *e) {
    if (!e) return;
    /* PAL 128K runs at 50.08 Hz; 20000 µs is close enough and aligns with
     * the music driver's 50 Hz tick expectation. */
    zx_exec(&e->zx, 20000);
}

emu_display_t emu_display(emu_t *e) {
    const chips_display_info_t info = zx_display_info(&e->zx);
    const emu_display_t out = {
        .fb_width   = info.frame.dim.width,
        .fb_height  = info.frame.dim.height,
        .vis_width  = info.screen.width,
        .vis_height = info.screen.height,
        .fb         = (const uint8_t  *)info.frame.buffer.ptr,
        .palette    = (const uint32_t *)info.palette.ptr,
    };
    return out;
}

void emu_key_down(emu_t *e, int zx_key) { if (e && zx_key) zx_key_down(&e->zx, zx_key); }
void emu_key_up  (emu_t *e, int zx_key) { if (e && zx_key) zx_key_up  (&e->zx, zx_key); }
void emu_joystick(emu_t *e, uint8_t mask) { if (e) zx_joystick(&e->zx, mask); }

const uint8_t *emu_spectrum_font(void) {
    /* 96 chars * 8 rows = 768 bytes starting at $3D00 in the 48K-compat
     * ROM (ROM 1 in 128K mode). Same layout as a real Spectrum: the byte
     * for char ASCII C, row R lives at offset (C - 0x20) * 8 + R. */
    return &dump_amstrad_zx128k_1_bin[0x3D00];
}
