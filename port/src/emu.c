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
#include "tape.h"

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
#include "ayumi.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* AY emulation strategy
 * ----------------------
 * chips/ay38910 samples the AY's square waves directly at the host rate
 * with no anti-aliasing, no oversampling and a moving-average DC blocker
 * with audible sinc-shaped lobes. The result is the "no del todo limpia"
 * tone the user described comparing against Spectaculator.
 *
 * Replacement: route AY sample generation through ayumi (Peter Sovietov,
 * MIT, vendored under port/vendor/ayumi). Ayumi does proper oversampling
 * + a 192-tap FIR decimator + an IIR DC blocker, and it's the de-facto
 * reference open-source AY emulator -- chips already uses ayumi's
 * volume table.
 *
 * Mechanism: chips keeps emulating the Z80 + paging + beeper + AY-state
 * (register writes from OUT instructions flow into zx->ay.reg[] as
 * before). We silence chips' AY by zeroing its `mag` field, so chips'
 * audio callback hands us samples that contain only the beeper. In the
 * callback we then:
 *   1. Diff chips' AY register snapshot against the previous one and
 *      forward any change to ayumi via ayumi_set_tone / _noise / etc.
 *   2. Run ayumi_process() N times to produce N output samples (one per
 *      chips callback sample).
 *   3. Add ayumi's mono mix to chips' beeper samples.
 *   4. Hand the combined buffer to our host audio callback.
 *
 * Granularity: chips fires its callback every 128 samples (~2.7 ms at
 * 48 kHz). Register changes happening between callbacks are coalesced
 * to "final value at end of batch". For Tharkys this is fine -- the
 * music driver writes registers once every 2 IRQs (~40 ms / 25 Hz) and
 * the SFX system isn't faster than 25 Hz either.
 *
 * Stereo: ayumi outputs left + right (panning is configurable). We
 * average to mono since the host audio device is mono. Pan is set to
 * ABC channel layout (the classic 128K stereo wiring): A left, B
 * centre, C right -- if a later patch wants to expose stereo, we just
 * have to flip the audio device to 2 channels and forward L/R
 * separately. */
#define ZX_128_AY_CLOCK_HZ 1773400.0  /* exactly half the CPU clock     */

/* --- Perf probe state (50fps viability study, see emu_set_perf_probe) --- */
typedef struct {
    bool     enabled;
    bool     prev_int;         /* INT pin edge detect = ULA frame boundary   */
    bool     prev_mreq;        /* MREQ edge detect = one memory access       */
    uint32_t f_work, f_cont;   /* current ULA frame: work ticks / contended  */
    uint32_t pf_work, pf_cont; /* previous ULA frame (sliding 2-frame pair)  */
    uint32_t w_frames;         /* per-second window accumulators             */
    uint32_t w_pair_max, w_pair_max_cont;
    uint64_t w_pair_sum;
    uint32_t w_fmax;           /* max single-frame work in window            */
    uint32_t w_over1, w_over2; /* pairs exceeding 1 / 2 ULA frame budgets    */
    uint32_t w_sat;            /* saturated frames (tick ran past its IRQ)   */
    uint32_t frame_no;         /* ULA frames since probe enable              */
} perf_t;

struct emu {
    zx_t  zx;
    struct ayumi ay;
    uint8_t last_ay_reg[14];  /* delta-detect register writes per batch */
    int     sample_rate;
    void  (*audio_cb)(const float *, int, void *);
    void   *audio_user;
    bool    audio_processing;  /* when false, trampoline skips ayumi tick */

    /* Tape state for the LD-BYTES trap (see zx_debug_cb below). */
    tape_t  tape;
    bool    tape_trap_armed;   /* edge-detect: already handled this M1 fetch */
    bool    debug_stopped;     /* chips_debug_t.stopped target (always false) */

    perf_t    perf;
    uint32_t *perf_hist;       /* PC sample histogram, see emu_perf_hist_dump */
};

/* Histogram layout: one counter per PC value. 0x0000-0xBFFF map 1:1 (ROM +
 * always-visible RAM); 0xC000-0xFFFF is pageable, so it fans out per paged
 * bank: idx = 0x10000 + bank*0x4000 + (pc - 0xC000). */
#define PERF_HIST_ENTRIES (0x10000u + 8u * 0x4000u)

/* Mirror one AY register write from chips into ayumi. Reg numbers and
 * bit layouts are AY-3-8910 native, so chips' ay.reg[i] can be fed in
 * directly; we just split the period registers into the pair they
 * actually form on the chip. */
static void ay_reg_to_ayumi(struct ayumi *ay, int reg, uint8_t val, const uint8_t *all) {
    switch (reg) {
        case 0: case 1: {
            const int period = (all[0] | (all[1] << 8)) & 0x0FFF;
            ayumi_set_tone(ay, 0, period);
            break;
        }
        case 2: case 3: {
            const int period = (all[2] | (all[3] << 8)) & 0x0FFF;
            ayumi_set_tone(ay, 1, period);
            break;
        }
        case 4: case 5: {
            const int period = (all[4] | (all[5] << 8)) & 0x0FFF;
            ayumi_set_tone(ay, 2, period);
            break;
        }
        case 6:
            ayumi_set_noise(ay, val & 0x1F);
            break;
        case 7:
            /* Mixer bits: 0..2 tone disable A/B/C, 3..5 noise disable. */
            for (int ch = 0; ch < 3; ch++) {
                const int t_off = (val >> ch)        & 1;
                const int n_off = (val >> (ch + 3))  & 1;
                const int e_on  = (all[8 + ch] >> 4) & 1;
                ayumi_set_mixer(ay, ch, t_off, n_off, e_on);
            }
            break;
        case 8: case 9: case 10: {
            const int ch    = reg - 8;
            const int e_on  = (val >> 4) & 1;
            const int t_off = (all[7] >> ch)         & 1;
            const int n_off = (all[7] >> (ch + 3))   & 1;
            ayumi_set_mixer(ay, ch, t_off, n_off, e_on);
            ayumi_set_volume(ay, ch, val & 0x0F);
            break;
        }
        case 11: case 12: {
            const int period = (all[11] | (all[12] << 8)) & 0xFFFF;
            ayumi_set_envelope(ay, period);
            break;
        }
        case 13:
            ayumi_set_envelope_shape(ay, val & 0x0F);
            break;
        default: break;
    }
}

/* chips fires this every num_samples beeper ticks (default 128). The
 * incoming `samples` already contains beeper output (chips' AY was
 * silenced via mag=0 in emu_create). We add ayumi's freshly-generated
 * AY mix on top before forwarding to the host. */
static void chips_audio_trampoline(const float *samples, int num_samples, void *user) {
    emu_t *e = (emu_t *)user;
    if (!e || !e->audio_cb) return;

    /* Bypass during precharge / paused. Don't tick ayumi, don't push
     * samples to the host. The AY register file on chips' side keeps
     * tracking Z80 OUTs (so the music driver advances normally), but
     * ayumi's filters stay quiescent and won't accumulate garbage at
     * 40x turbo speed. main.c flips this back on (with a warmup reset)
     * once it lets audio out. */
    if (!e->audio_processing) return;

    /* 1. Replay any AY register changes that landed during this batch. */
    const uint8_t *cur = e->zx.ay.reg;
    for (int reg = 0; reg < 14; reg++) {
        if (cur[reg] != e->last_ay_reg[reg]) {
            e->last_ay_reg[reg] = cur[reg];
            ay_reg_to_ayumi(&e->ay, reg, cur[reg], cur);
        }
    }

    /* 1b. Mono anti-flange override.
     *
     * Tracks poly2 derivadas de un MIDI mono (Tension/Sunrise/Death) duplican
     * el tone period en A y C "mientras no haya converter". En un 128K real
     * con jack stereo o en Spectaculator (estereo ABC default) cada voz va a
     * un altavoz distinto, no se interfieren acusticamente y la duplicacion
     * suena mas "ancha". En este wrapper mezclamos todos los canales a mono
     * (linear pan 0.5 + tomar solo ay.left): dos squares identicos con phases
     * iniciales independientes oscilan dentro y fuera de fase = flange audible.
     *
     * Solucion: cuando los dos canales tienen el mismo tone period activo (y
     * ambos con tone enable + vol > 0), silenciar volumen de C en ayumi. La
     * SNA no cambia — Spectaculator / HW real siguen tocando estereo ABC con
     * +6 dB combinados. Aqui perdemos -6 dB en esas tracks (sunrise lo nota,
     * tension/death son cortas o enmascaradas por SFX), pero sin flange.
     *
     * Se aplica cada batch (no es delta) para que el estado siga la pista:
     * si A == C -> vol C = 0; si A != C -> vol C = lo que el music driver
     * dejo en R10. */
    {
        const int period_a   = (cur[0] | (cur[1] << 8)) & 0x0FFF;
        const int period_c   = (cur[4] | (cur[5] << 8)) & 0x0FFF;
        const int tone_off_a = (cur[7] >> 0) & 1;
        const int tone_off_c = (cur[7] >> 2) & 1;
        const int vol_c      = cur[10] & 0x0F;
        const int dup        = (period_a != 0) && (period_a == period_c) &&
                               !tone_off_a && !tone_off_c && (vol_c > 0);
        ayumi_set_volume(&e->ay, 2, dup ? 0 : vol_c);
    }

    /* 2. Generate N AY samples from ayumi, sum with chips' beeper
     *    samples (which arrive in `samples[i]`; chips' AY is silenced
     *    via mag=0 above).
     *
     * Why ayumi for AY, not chips: chips' 512-sample DC blocker has
     * its first zero around 86 Hz at 44.1k -- it eats the fundamental
     * of bass notes (Tension theme low Cs etc.), making the music
     * sound thin / treble-heavy. ayumi's 1024-sample DC blocker pushes
     * the first zero down to ~43 Hz, fully preserving bass.
     *
     * Amplitude budget:
     *   - ayumi: centre-linear pan -> each channel contributes up to
     *     0.5 to ay->left, three channels max sum 1.5, scaled by 0.40
     *     -> AY peak 0.60.
     *   - beeper: chips' base_volume = 0.30 -> beeper peak ~0.30.
     *   - Worst-case coincidence: 0.90 -- safely below the 0.95 soft-
     *     clip knee. */
    float buf[1024];
    if (num_samples > 1024) num_samples = 1024;

    /* Diagnostic: track peak |sample| separately for beeper and AY,
     * logged once per second to stderr (tharkys.log) when
     * --audio-debug is set in main.c. Static counters are safe for
     * single-threaded chips callback access. */
    static float dbg_beeper_peak = 0.0f;
    static float dbg_ay_peak     = 0.0f;
    static int   dbg_sample_acc  = 0;

    for (int i = 0; i < num_samples; i++) {
        ayumi_process(&e->ay);
        ayumi_remove_dc(&e->ay);
        const float ay_sample     = (float)(e->ay.left * 0.40);
        const float beeper_sample = samples[i];
        const float beeper_abs    = beeper_sample < 0 ? -beeper_sample : beeper_sample;
        const float ay_abs        = ay_sample     < 0 ? -ay_sample     : ay_sample;
        if (beeper_abs > dbg_beeper_peak) dbg_beeper_peak = beeper_abs;
        if (ay_abs     > dbg_ay_peak)     dbg_ay_peak     = ay_abs;
        buf[i] = beeper_sample + ay_sample;
    }

    dbg_sample_acc += num_samples;
    if (dbg_sample_acc >= e->sample_rate && emu_audio_debug()) {
        fprintf(stderr, "[audio] peaks last 1 s -- beeper %.4f  ay %.4f\n",
                dbg_beeper_peak, dbg_ay_peak);
        dbg_beeper_peak = 0.0f;
        dbg_ay_peak     = 0.0f;
        dbg_sample_acc  = 0;
    }

    e->audio_cb(buf, num_samples, e->audio_user);
}

/* ------------------------------------------------------------------------- */
/* Tape trap.                                                                */
/*                                                                           */
/* chips/zx has no built-in tape support. We intercept LD-BYTES at $0556 of  */
/* the 48K-compat ROM (ROM 1 on 128K) and replay the next matching block     */
/* from a .tap blob straight into the destination, in zero CPU cycles.       */
/*                                                                           */
/* Mechanics:                                                                */
/*   1. emu_load_tap() attaches a tape_t and patches rom[1][$0556] from      */
/*      $14 (INC D, the start of the real LD-BYTES routine) to $C9 (RET).   */
/*      The patched byte makes the trap "self-cleaning": once we've set up  */
/*      the registers the Z80 just returns to the caller as if LD-BYTES     */
/*      finished successfully.                                              */
/*   2. zx_init() is given a debug callback that fires after every Z80 tick.*/
/*      Most ticks are filtered out cheaply (M1 + addr match + ROM 1 page). */
/*   3. On hit we read the LD-BYTES contract from registers: A' = expected  */
/*      flag, IX = dest, DE = expected length. tape_next() finds the next   */
/*      matching block (skipping headers/data blocks the caller didn't ask  */
/*      for, exactly like the real ROM does). We mem_wr the payload, bump   */
/*      IX/DE, set A and carry, and let the patched RET pop SP and exit.    */
/*                                                                          */
/* Only ROM 1 (bit 4 of $7FFD = 1) is trapped. ROM 0 (128K editor / menu)   */
/* has unrelated code at $0556, so the trap is gated by `rom1_active`. The  */
/* "Tape Loader" option from the 128K boot menu flips to ROM 1 + USR 0      */
/* mode before issuing LOAD "", so the trap kicks in there naturally.       */
/* ------------------------------------------------------------------------- */
#define ZX_ROM_LD_BYTES_ADDR  0x0556
#define ZX_ROM_RET_OPCODE     0xC9

/* ------------------------------------------------------------------------- */
/* Perf probe (50fps viability study).                                       */
/*                                                                           */
/* The game parks in HALT between frames (fixed-25fps double-HALT MainLoop), */
/* so "Z80_HALT pin low" == the game is doing real work. Counting non-HALT   */
/* ticks between ULA frame boundaries (Z80_INT rising edge, every 70908 T on */
/* the 128K) yields the exact per-frame CPU cost; a sliding sum of two       */
/* consecutive frames reconstructs the game's 25fps frame pair regardless of */
/* parity. chips does NOT emulate ULA contention (zx.h has a FIXME there),   */
/* so these counts are a lower bound of real hardware time; every rising     */
/* MREQ edge into contended RAM (0x4000-0x7FFF = bank 5, or an odd bank      */
/* paged at 0xC000 -- banks 1/3/5/7 are the contended ones on the 128K) is   */
/* counted separately so the contention uplift can be estimated offline.     */
/* ------------------------------------------------------------------------- */
#define PERF_FRAME_TICKS   70908u   /* 228 T x 311 lines, ZX 128K ULA frame  */
#define PERF_WINDOW_FRAMES 50u      /* one summary line per emulated second  */

static void perf_frame_boundary(emu_t *e) {
    perf_t *p = &e->perf;
    p->frame_no++;
    const uint32_t pair_work = p->f_work + p->pf_work;
    const uint32_t pair_cont = p->f_cont + p->pf_cont;
    if (pair_work > p->w_pair_max) {
        p->w_pair_max      = pair_work;
        p->w_pair_max_cont = pair_cont;
    }
    p->w_pair_sum += pair_work;
    if (p->f_work > p->w_fmax) p->w_fmax = p->f_work;
    if (pair_work > PERF_FRAME_TICKS)     p->w_over1++;
    if (pair_work > 2 * PERF_FRAME_TICKS) p->w_over2++;
    /* Saturated frame = the CPU never reached HALT inside this ULA frame,
     * i.e. a hybrid sub-frame overran its IRQ boundary and the pair will
     * stretch to 3 frames (momentary sub-25fps). The success metric for the
     * 50 Hz hybrid is sat == 0 during normal gameplay. */
    if (p->f_work >= PERF_FRAME_TICKS - 64) p->w_sat++;
    p->pf_work = p->f_work;
    p->pf_cont = p->f_cont;
    p->f_work  = 0;
    p->f_cont  = 0;
    if (++p->w_frames >= PERF_WINDOW_FRAMES) {
        printf("[perf] f=%06u | pair max=%6u avg=%6u cont=%5u | fmax=%6u sat=%2u | >1f=%2u >2f=%2u\n",
               p->frame_no, p->w_pair_max,
               (uint32_t)(p->w_pair_sum / p->w_frames), p->w_pair_max_cont,
               p->w_fmax, p->w_sat, p->w_over1, p->w_over2);
        p->w_frames = 0;
        p->w_pair_max = 0; p->w_pair_max_cont = 0;
        p->w_pair_sum = 0; p->w_fmax = 0;
        p->w_over1 = 0; p->w_over2 = 0; p->w_sat = 0;
    }
}

static void perf_tick(emu_t *e, uint64_t pins) {
    perf_t *p = &e->perf;
    if (!(pins & Z80_HALT)) {
        p->f_work++;
        if (e->perf_hist) {
            /* cpu.pc points at the next fetch (+1 instruction skew) --
             * irrelevant for statistical attribution. */
            const uint16_t pc = e->zx.cpu.pc;
            uint32_t idx;
            if (pc < 0xC000) {
                idx = pc;
            } else {
                const uint32_t bank = e->zx.last_mem_config & 7;
                idx = 0x10000u + (bank << 14) + (uint32_t)(pc - 0xC000);
            }
            e->perf_hist[idx]++;
        }
        const bool mreq = (pins & Z80_MREQ) != 0;
        if (mreq && !p->prev_mreq) {
            const uint16_t a = (uint16_t)Z80_GET_ADDR(pins);
            bool cont = (a >= 0x4000 && a < 0x8000);
            if (a >= 0xC000) {
                cont = (e->zx.last_mem_config & 1) != 0;  /* odd bank paged */
            }
            if (cont) p->f_cont++;
        }
        p->prev_mreq = mreq;
    } else {
        p->prev_mreq = false;
    }
    const bool int_now = (pins & Z80_INT) != 0;
    if (int_now && !p->prev_int) perf_frame_boundary(e);
    p->prev_int = int_now;
}

static void zx_debug_cb(void *user_data, uint64_t pins) {
    emu_t *e = (emu_t *)user_data;
    if (!e) return;
    if (e->perf.enabled) perf_tick(e, pins);
    if (!e->tape.loaded) return;

    /* Cheap filter first: only on M1 fetch at the trap address. */
    if (!(pins & Z80_M1)) {
        e->tape_trap_armed = false;
        return;
    }
    const uint16_t pc = Z80_GET_ADDR(pins);
    if (pc != ZX_ROM_LD_BYTES_ADDR) {
        e->tape_trap_armed = false;
        return;
    }
    /* Bit 4 of port $7FFD: 0 = ROM 0 (128K editor), 1 = ROM 1 (48K-compat).
     * LD-BYTES only exists at $0556 in ROM 1; ignore the menu ROM. */
    if ((e->zx.last_mem_config & 0x10) == 0) return;

    /* M1 stays asserted for several ticks; only run the trap once per fetch. */
    if (e->tape_trap_armed) return;
    e->tape_trap_armed = true;

    /* The expected flag is in A (main), not A'. The caller does
     * `LD A, $XX / SCF` and CALLs $0556; the INC D / EX AF,AF' /
     * DEC D dance happens INSIDE LD-BYTES (at $0557), not before,
     * so when we trap at $0556 the swap hasn't happened yet. */
    const uint8_t want = e->zx.cpu.a;
    const uint8_t *payload;
    uint16_t       payload_len;

    if (tape_next(&e->tape, want, &payload, &payload_len)) {
        const uint16_t req = e->zx.cpu.de;
        const uint16_t n   = (payload_len < req) ? payload_len : req;
        const uint16_t ix0 = e->zx.cpu.ix;
        for (uint16_t i = 0; i < n; i++) {
            mem_wr(&e->zx.mem, (uint16_t)(ix0 + i), payload[i]);
        }
        e->zx.cpu.ix = (uint16_t)(ix0 + n);
        e->zx.cpu.de = (uint16_t)(req - n);
        e->zx.cpu.a  = want;
        if (n == req) e->zx.cpu.f |=  Z80_CF;   /* success */
        else          e->zx.cpu.f &= (uint8_t)~Z80_CF;  /* short read */
    } else {
        e->zx.cpu.f &= (uint8_t)~Z80_CF;
    }
    /* Patched RET at $0556 will pop SP and return to the caller on the
     * next tick; nothing else to do here. */
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
    e->sample_rate      = (desc && desc->sample_rate > 0) ? desc->sample_rate : 44100;
    e->audio_processing = true;   /* main.c flips off during turbo precharge */

    const zx_desc_t zd = {
        .type          = ZX_TYPE_128,
        .joystick_type = ZX_JOYSTICKTYPE_KEMPSTON,
        .debug = {
            /* Per-tick hook used exclusively by the tape trap (see
             * zx_debug_cb). When no .tap is attached the callback
             * returns immediately, so the overhead is one indirect
             * call + one branch per Z80 tick. */
            .callback = {
                .func      = zx_debug_cb,
                .user_data = e,
            },
            .stopped = &e->debug_stopped,
        },
        .audio = {
            .callback = {
                .func      = chips_audio_trampoline,
                .user_data = e,
            },
            .sample_rate = e->sample_rate,
            /* AY silenced inside chips (mag=0) -- ayumi handles AY in
             * the trampoline below for proper bass preservation.
             * Beeper kept at chips' built-in path for the ~17 still-
             * beeper-native SFX in sound.asm (footstep, attack, pickup,
             * doors, thunder, etc.).
             *
             * Amplitude budget: ayumi AY peak 0.60 (scaled 0.40 in
             * trampoline) + beeper peak 0.30 = 0.90 worst case --
             * below the 0.95 soft-clip knee. */
            .ay_volume     = 0.0f,
            .beeper_volume = 0.30f,
        },
        .roms = {
            .zx128_0 = { .ptr = dump_amstrad_zx128k_0_bin, .size = sizeof(dump_amstrad_zx128k_0_bin) },
            .zx128_1 = { .ptr = dump_amstrad_zx128k_1_bin, .size = sizeof(dump_amstrad_zx128k_1_bin) },
        },
    };
    zx_init(&e->zx, &zd);

    /* GOTCHA: chips' _ZX_DEFAULT(val, def) macro treats `val == 0` as
     * "unspecified" and substitutes the default (`0.5f` for ay_volume).
     * So setting `.ay_volume = 0.0f` above does NOT silence chips' AY
     * -- it sets it to half volume. The trampoline was then summing
     * chips' raw (no FIR, no oversampling) AY mix into `samples[i]` on
     * top of ayumi's clean AY mix in the same trampoline -- two AY
     * renderings of the same Z80 state at slightly different filter
     * delays summed together = comb filter = the "phased" coloration
     * the user heard on every long AY tone (player-respawn tics most
     * obviously). Forcing mag=0 directly after init bypasses the
     * macro and actually silences chips' AY path. Don't `.ay_volume`
     * a tiny epsilon either -- it'd survive the macro but still drive
     * chips' AY at audible level. */
    e->zx.ay.mag = 0.0f;

    /* ayumi: AY-3-8910 mode (is_ym=0), 128K AY clock, host sample rate. */
    if (!ayumi_configure(&e->ay, 0, ZX_128_AY_CLOCK_HZ, e->sample_rate)) {
        /* configure rejects out-of-range sample rates; fall back to 44100. */
        ayumi_configure(&e->ay, 0, ZX_128_AY_CLOCK_HZ, 44100);
    }
    /* All three channels panned to centre with linear law, so each
     * channel contributes exactly 0.5 to both ay->left and ay->right.
     * Critical for mono output: any other pan distribution makes
     * (L + R) / 2 weight the channels unevenly (eg. an ABC equal-power
     * spread makes ch B end up sqrt(2) louder than A or C in the mono
     * sum, which a real 128K wouldn't do). With centre-linear we can
     * just take ay->left -- it already equals ay->right -- and skip
     * the redundant addition. If/when stereo gets exposed, re-pan to
     * ABC at the call site instead of changing the default. */
    ayumi_set_pan(&e->ay, 0, 0.5, 0);
    ayumi_set_pan(&e->ay, 1, 0.5, 0);
    ayumi_set_pan(&e->ay, 2, 0.5, 0);

    /* AY post-reset state is all zeros; last_ay_reg already calloc'd to
     * zero, so the first delta-write will pick up any non-zero reg from
     * the SNA snapshot. */
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

    /* Guard: a snapshot taken with bank 2 or 5 paged at $C000 is the OTHER
     * legal .sna variant (147487 bytes, six tail banks) which this loader
     * does not model -- the loop below would read 16 KB past the caller's
     * 131103-byte blob. Reachable only with a foreign hand-placed .sna
     * (this game never pages 2/5); refuse instead of OOB-reading. */
    if (cur_bank == 2 || cur_bank == 5) return false;

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
/* SNA 128K saver (save / resume).                                           */
/*                                                                           */
/* Exact inverse of emu_load_sna above, plus a 14-byte AY sidecar (the SNA   */
/* format predates the 128K and has no AY fields). Why SNA instead of        */
/* memcpy'ing zx_t (chips' own zx_save_snapshot): the struct layout follows  */
/* chips master (FetchContent GIT_TAG master), so any rebuild could silently */
/* invalidate every stored save; the .sna layout is frozen since the 80s,    */
/* and a player can download their save and open it in a real emulator.     */
/*                                                                           */
/* Instruction boundary: zx_exec() returns whenever its tick budget runs     */
/* out, possibly mid-instruction, where registers hold transient state. We   */
/* tick the machine forward (same inner loop as zx_exec; _zx_tick is         */
/* reachable because CHIPS_IMPL lives in this TU) until z80_opdone() -- the  */
/* overlapped M1/T2 fetch of the next opcode. At that point the address on   */
/* the CPU pins IS the next instruction's address: exactly what the SNA PC   */
/* field wants, and what emu_load_sna feeds to z80_prefetch on restore.      */
/* (HALT included: the refetch of the HALT opcode puts its own address on    */
/* the pins, so a game saved inside HALT re-enters HALT and wakes on the     */
/* next IRQ, like real hardware.) A few extra ticks (<1/700 of a frame) are  */
/* inaudible and invisible.                                                  */
/* ------------------------------------------------------------------------- */
size_t emu_save_state(emu_t *e, uint8_t *out, size_t cap) {
    if (!e || !out || cap < EMU_STATE_SIZE) return 0;
    zx_t *zx = &e->zx;

    /* Reach an instruction boundary. Longest Z80 instruction is 23 T-states
     * (EX (SP),IX and friends); interrupt entry adds ~19 more. 128 covers
     * every case with a wide margin; bail out if something is very wrong. */
    int guard = 128;
    while (!z80_opdone(&zx->cpu) && guard-- > 0) {
        zx->pins = _zx_tick(zx, zx->pins);
    }
    if (!z80_opdone(&zx->cpu)) return 0;

    const uint16_t PC = (uint16_t)Z80_GET_ADDR(zx->cpu.pins);

    /* 27-byte header (see emu_load_sna for the field map) */
    out[0]  = zx->cpu.i;
    out[1]  = (uint8_t)(zx->cpu.hl2 & 0xFF); out[2]  = (uint8_t)(zx->cpu.hl2 >> 8);
    out[3]  = (uint8_t)(zx->cpu.de2 & 0xFF); out[4]  = (uint8_t)(zx->cpu.de2 >> 8);
    out[5]  = (uint8_t)(zx->cpu.bc2 & 0xFF); out[6]  = (uint8_t)(zx->cpu.bc2 >> 8);
    out[7]  = (uint8_t)(zx->cpu.af2 & 0xFF); out[8]  = (uint8_t)(zx->cpu.af2 >> 8);
    out[9]  = zx->cpu.l;  out[10] = zx->cpu.h;
    out[11] = zx->cpu.e;  out[12] = zx->cpu.d;
    out[13] = zx->cpu.c;  out[14] = zx->cpu.b;
    out[15] = (uint8_t)(zx->cpu.iy & 0xFF);  out[16] = (uint8_t)(zx->cpu.iy >> 8);
    out[17] = (uint8_t)(zx->cpu.ix & 0xFF);  out[18] = (uint8_t)(zx->cpu.ix >> 8);
    out[19] = zx->cpu.iff2 ? 0x04 : 0x00;
    out[20] = zx->cpu.r;
    out[21] = zx->cpu.f;  out[22] = zx->cpu.a;
    out[23] = (uint8_t)(zx->cpu.sp & 0xFF);  out[24] = (uint8_t)(zx->cpu.sp >> 8);
    out[25] = zx->cpu.im;
    out[26] = (uint8_t)(zx->border_color & 0x07);

    /* 48 KB dump: bank 5 + bank 2 + currently-paged bank.
     *
     * Guard: with bank 2 or 5 paged at $C000 the dump would duplicate an
     * already-dumped bank and the tail loop below would emit SIX banks --
     * that's the OTHER legal .sna variant (147487 bytes) which neither this
     * saver nor emu_load_sna models, and it would overflow `out` by 16 KB.
     * Unreachable with this game (it only ever pages 0/1/3/4/6/7 into
     * slot 3, see code/paging.asm), but emu.c is a general API: refuse. */
    const uint8_t cur_bank = zx->last_mem_config & 0x07;
    if (cur_bank == 2 || cur_bank == 5) return 0;
    memcpy(out + 27,              zx->ram[5],        0x4000);
    memcpy(out + 27 + 0x4000,     zx->ram[2],        0x4000);
    memcpy(out + 27 + 0x4000 * 2, zx->ram[cur_bank], 0x4000);

    /* Post-dump fields */
    out[49179] = (uint8_t)(PC & 0xFF);
    out[49180] = (uint8_t)(PC >> 8);
    out[49181] = zx->last_mem_config;
    out[49182] = 0;                              /* TR-DOS: not modelled */

    /* Remaining five banks in numerical order skipping {2, 5, cur_bank} */
    uint8_t *p = out + 49183;
    for (int b = 0; b <= 7; b++) {
        if (b == 2 || b == 5 || b == cur_bank) continue;
        memcpy(p, zx->ram[b], 0x4000);
        p += 0x4000;
    }

    /* AY sidecar: the chips register file tracks every OUT the Z80 did,
     * so it IS the machine-visible AY state. Byte 14 is the 4-bit address
     * latch -- a save can land between the game's select OUT ($FFFD) and
     * data OUT ($BFFD); without the latch the pending data write would hit
     * whatever register the post-restore session had selected. */
    memcpy(out + EMU_STATE_SNA_SIZE, zx->ay.reg, 14);
    out[EMU_STATE_SNA_SIZE + 14] = (uint8_t)(zx->ay.addr & 0x0F);
    return EMU_STATE_SIZE;
}

bool emu_load_state(emu_t *e, const uint8_t *data, size_t size) {
    if (!e || !data) return false;
    if (size != EMU_STATE_SIZE && size != EMU_STATE_SNA_SIZE) return false;
    if (!emu_load_sna(e, data, EMU_STATE_SNA_SIZE)) return false;
    if (size == EMU_STATE_SIZE) {
        /* Restore the AY register file + address latch. ayumi is NOT
         * touched here: the caller runs emu_audio_warmup_reset(), which
         * zeroes the delta cache so the next audio batch replays all 14
         * registers. */
        memcpy(e->zx.ay.reg, data + EMU_STATE_SNA_SIZE, 14);
        e->zx.ay.addr = data[EMU_STATE_SNA_SIZE + 14] & 0x0F;
    }
    return true;
}

/* ------------------------------------------------------------------------- */
/* Tape loader (attach a .tap blob; the trap handles the rest)               */
/* ------------------------------------------------------------------------- */
bool emu_load_tap(emu_t *e, const uint8_t *data, size_t size) {
    if (!e) return false;
    if (!tape_load(&e->tape, data, size)) return false;

    /* Patch LD-BYTES in ROM 1 (48K-compat) so the routine returns straight
     * to the caller. The debug callback above pre-loads bytes into RAM
     * and sets A / IX / DE / CF before this RET executes, so the BASIC
     * loader can't tell the difference between us and the real ROM. */
    e->zx.rom[1][ZX_ROM_LD_BYTES_ADDR] = ZX_ROM_RET_OPCODE;
    e->tape_trap_armed = false;

    /* Skip the 128K boot menu entirely and start in 48K BASIC (ROM 1).
     *
     * The "Tape Loader" entry in the 128K menu runs its own cassette
     * loader bolted onto ROM 0; it does NOT call LD-BYTES at $0556
     * and its entry-point can't be located by pattern matching on the
     * Amstrad ROM (the routine has no characteristic signature). The
     * cleanest fix is to bypass the menu: page ROM 1 in at $0000 and
     * reset the Z80, so the machine boots straight into 48K BASIC,
     * which we know calls $0556 (= our trap).
     *
     * This is exactly what Spectaculator's "fast load" does. The 128K
     * paging hardware (RAM bank select via $7FFD, AY, ROM toggle)
     * stays fully wired: only the menu UI is skipped, not any 128K
     * functionality. Tharkys' OUT $7FFD calls work identically. */
    e->zx.last_mem_config = 0x10;          /* bit 4 = 1 -> ROM 1 paged in  */
    update_memory_map_128(&e->zx, 0x10);
    e->zx.pins = z80_reset(&e->zx.cpu);
    e->zx.pins = z80_prefetch(&e->zx.cpu, 0x0000);
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

bool emu_tape_at_end(const emu_t *e) {
    return e ? tape_at_end(&e->tape) : true;
}

static bool g_audio_debug = false;
void emu_set_audio_debug(bool on) { g_audio_debug = on; }
bool emu_audio_debug(void)        { return g_audio_debug; }

void emu_set_audio_processing(emu_t *e, bool enabled) {
    if (e) e->audio_processing = enabled;
}

const uint8_t *emu_ay_regs(const emu_t *e) {
    return e ? e->zx.ay.reg : NULL;
}

void emu_set_perf_probe(emu_t *e, bool on) {
    if (!e) return;
    memset(&e->perf, 0, sizeof e->perf);
    e->perf.enabled = on;
    if (on && !e->perf_hist) {
        e->perf_hist = (uint32_t *)calloc(PERF_HIST_ENTRIES, sizeof(uint32_t));
    } else if (e->perf_hist) {
        memset(e->perf_hist, 0, PERF_HIST_ENTRIES * sizeof(uint32_t));
    }
}

/* Build a report of the top PC-sample blocks (64-byte granularity)
 * accumulated since the probe was enabled / last reset, into `buf`.
 * Symbolication against code/NuevoJuego.lst happens offline -- this just
 * reports address-space blocks with tick counts. `reset` != 0 clears the
 * histogram after reporting (scenario A/B workflow). Returns bytes written. */
size_t emu_perf_report(emu_t *e, int reset, char *buf, size_t cap) {
    if (!buf || cap == 0) return 0;
    buf[0] = 0;
    if (!e || !e->perf_hist) { snprintf(buf, cap, "no data"); return strlen(buf); }
    enum { BLK = 64, NBLK = (int)(PERF_HIST_ENTRIES / BLK), TOP = 80 };
    uint64_t total = 0;
    static uint32_t blk[NBLK];          /* 12 KB static scratch, single thread */
    for (int b = 0; b < NBLK; b++) {
        uint32_t s = 0;
        const uint32_t *h = e->perf_hist + (uint32_t)b * BLK;
        for (int i = 0; i < BLK; i++) s += h[i];
        blk[b] = s;
        total += s;
    }
    int used[TOP]; int n = 0;
    for (int b = 0; b < NBLK; b++) {
        if (!blk[b]) continue;
        int i = n < TOP ? n : TOP - 1;
        if (n < TOP) n++;
        else if (blk[b] <= blk[used[TOP - 1]]) continue;
        while (i > 0 && blk[used[i - 1]] < blk[b]) { used[i] = used[i - 1]; i--; }
        used[i] = b;
    }
    size_t off = (size_t)snprintf(buf, cap, "total=%llu\n", (unsigned long long)total);
    uint64_t covered = 0;
    for (int i = 0; i < n && off + 32 < cap; i++) {
        const uint32_t base = (uint32_t)used[i] * BLK;
        covered += blk[used[i]];
        const double pct = total ? (100.0 * blk[used[i]] / (double)total) : 0.0;
        if (base < 0x10000u) {
            off += (size_t)snprintf(buf + off, cap - off, "%04X %u %.2f\n",
                                    base, blk[used[i]], pct);
        } else {
            const uint32_t bank = (base - 0x10000u) >> 14;
            const uint32_t addr = 0xC000u + ((base - 0x10000u) & 0x3FFFu);
            off += (size_t)snprintf(buf + off, cap - off, "B%u:%04X %u %.2f\n",
                                    bank, addr, blk[used[i]], pct);
        }
    }
    if (off + 32 < cap) {
        off += (size_t)snprintf(buf + off, cap - off, "covered=%.1f%%\n",
                                total ? (100.0 * (double)covered / (double)total) : 0.0);
    }
    if (reset) memset(e->perf_hist, 0, PERF_HIST_ENTRIES * sizeof(uint32_t));
    return off;
}

void emu_perf_hist_dump(emu_t *e, int reset) {
    static char rpt[8192];
    emu_perf_report(e, reset, rpt, sizeof rpt);
    printf("[hist]\n%s", rpt);
}

/* Fine-grained drill-down: per-8-byte-group counts inside [lo, hi) of the
 * histogram. bank < 0 = always-visible address (0x0000-0xBFFF); bank 0-7 =
 * pageable window address 0xC000-0xFFFF seen with that bank paged. */
size_t emu_perf_range(emu_t *e, int bank, uint32_t lo, uint32_t hi,
                      char *buf, size_t cap) {
    if (!buf || cap == 0) return 0;
    buf[0] = 0;
    if (!e || !e->perf_hist) { snprintf(buf, cap, "no data"); return strlen(buf); }
    uint32_t base = 0;
    if (bank >= 0) {
        if (lo < 0xC000u) lo = 0xC000u;
        base = 0x10000u + ((uint32_t)bank << 14) - 0xC000u;
    }
    if (hi > 0x10000u) hi = 0x10000u;
    size_t off = 0;
    for (uint32_t a = lo & ~7u; a < hi && off + 24 < cap; a += 8) {
        uint32_t s = 0;
        for (uint32_t i = 0; i < 8; i++) s += e->perf_hist[base + a + i];
        if (!s) continue;
        off += (size_t)snprintf(buf + off, cap - off, "%04X %u\n", a, s);
    }
    return off;
}

void emu_audio_warmup_reset(emu_t *e) {
    if (!e) return;
    /* 1. Re-init ayumi so its FIR filter history, DC blocker memory and
     *    oscillator phases all go back to zero. Without this, the 40x
     *    turbo precharge has stuffed ~250 emulated frames of audio
     *    through ayumi's filters; the residual energy lights up the
     *    first audible note as a sharp transient. */
    ayumi_configure(&e->ay, 0, ZX_128_AY_CLOCK_HZ, e->sample_rate);
    ayumi_set_pan(&e->ay, 0, 0.5, 0);
    ayumi_set_pan(&e->ay, 1, 0.5, 0);
    ayumi_set_pan(&e->ay, 2, 0.5, 0);

    /* 2. Wipe ayumi's per-channel volumes. The next register write the
     *    game's music driver does to R8/R9/R10 will re-set them. Until
     *    that happens (a frame or two), the channels are silent. */
    for (int ch = 0; ch < 3; ch++) {
        ayumi_set_volume(&e->ay, ch, 0);
        ayumi_set_mixer(&e->ay, ch, 1, 1, 0);   /* tone off, noise off */
    }

    /* 3. Zero the delta-detect cache so the very next callback replays
     *    every live AY register (R0..R13) into ayumi from scratch. The
     *    chips AY register file (e->zx.ay.reg) holds the real, current
     *    Z80-visible state; ay_reg_to_ayumi() in the trampoline will
     *    push it through on the next batch. */
    memset(e->last_ay_reg, 0, sizeof e->last_ay_reg);

    /* 4. Reset the chips beeper. During the 40x turbo precharge the
     *    ROM and BASIC LOADER toss many OUT (FE) clicks (border tone,
     *    keypress beeps from the autotyped LOAD ""); those accumulate
     *    in chips' beeper sample buffer and DC blocker. Without a
     *    reset, the first audible output is a stew of stale clicks
     *    on top of the real AY note. */
    beeper_reset(&e->zx.beeper);
}

const uint8_t *emu_spectrum_font(void) {
    /* 96 chars * 8 rows = 768 bytes starting at $3D00 in the 48K-compat
     * ROM (ROM 1 in 128K mode). Same layout as a real Spectrum: the byte
     * for char ASCII C, row R lives at offset (C - 0x20) * 8 + R. */
    return &dump_amstrad_zx128k_1_bin[0x3D00];
}
