/*
 * emu.h - chips/zx ZX Spectrum 128K wrapper.
 *
 * Hides every chips-internal type behind an opaque emu_t so main.c never
 * has to #include chips headers (CHIPS_IMPL only lives in emu.c).
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct emu emu_t;

typedef struct {
    int   sample_rate;          /* e.g. 44100                                */
    void (*audio_cb)(const float *samples, int num_samples, void *user);
    void  *audio_user;
} emu_desc_t;

/* What the host needs to blit a frame. The buffer is palette indices
 * (1 byte per pixel) the host must look up in `palette` and convert to RGBA. */
typedef struct {
    int             fb_width;   /* internal stride (= 512)                   */
    int             fb_height;  /* internal height (= 256)                   */
    int             vis_width;  /* visible area incl. border (= 320)         */
    int             vis_height; /* visible area incl. border (= 256)         */
    const uint8_t  *fb;         /* palette-indexed framebuffer               */
    const uint32_t *palette;    /* 16 entries, RGBA in memory order on LE    */
} emu_display_t;

/* Joystick mask bits (Kempston layout: bit0=Right .. bit4=Fire). */
#define EMU_JOY_RIGHT  (1<<0)
#define EMU_JOY_LEFT   (1<<1)
#define EMU_JOY_DOWN   (1<<2)
#define EMU_JOY_UP     (1<<3)
#define EMU_JOY_FIRE   (1<<4)

emu_t *emu_create (const emu_desc_t *desc);
void   emu_destroy(emu_t *e);

/* Load a 128K .sna snapshot into the running machine. Returns false on a
 * malformed or 48K-only blob. */
bool   emu_load_sna(emu_t *e, const uint8_t *data, size_t size);

/* Save / resume. The save format is a standard 128K .sna image (so a
 * player can download their save and open it in any Spectrum emulator)
 * plus a 15-byte sidecar: the AY register file (R0..R13) and the AY
 * 4-bit address latch, none of which the SNA format (which predates the
 * 128K) can carry. emu_load_state accepts both sizes (a plain SNA just
 * loses the AY sidecar; the game's 25 Hz music driver rewrites the
 * audible registers within a couple of frames anyway). */
#define EMU_STATE_SNA_SIZE  131103              /* pure 128K .sna       */
#define EMU_STATE_SIZE      (131103 + 15)       /* .sna + AY sidecar    */

/* Serialize the current machine state into `out`. Ticks the CPU forward
 * (at most one instruction) to reach an instruction boundary so the
 * snapshot registers are coherent. Returns EMU_STATE_SIZE, or 0 on
 * error. `cap` must be >= EMU_STATE_SIZE. */
size_t emu_save_state(emu_t *e, uint8_t *out, size_t cap);

/* Restore a blob produced by emu_save_state (or any 128K .sna). The
 * caller should follow up with emu_audio_warmup_reset() so ayumi
 * resyncs from the restored AY register file. */
bool   emu_load_state(emu_t *e, const uint8_t *data, size_t size);

/* Attach a .tap blob and enable the LD-BYTES trap. The emulator boots
 * normally into the 128K ROM menu and any LOAD "" call (from BASIC or
 * the "Tape Loader" menu option) reads its bytes from this blob instead
 * of the audio decoder. The blob must stay alive as long as the emulator
 * may read more blocks. Returns false on NULL / short input. */
bool   emu_load_tap(emu_t *e, const uint8_t *data, size_t size);

/* True once every block in the attached TAP has been consumed by the
 * LD-BYTES trap. Used by the precharge loop to drop out of turbo as
 * soon as the loader finishes, so the in-game music driver starts
 * playing into a live (not muted) audio queue. */
bool   emu_tape_at_end(const emu_t *e);

/* Advance the emulator by one PAL frame (~20 ms of CPU time). */
void   emu_run_frame(emu_t *e);

emu_display_t emu_display(emu_t *e);

/* Key codes follow chips/zx conventions: ASCII for printable keys, plus a
 * few control values:  0x0D=Enter, 0x08-0x0B=cursors L/D/U/R, ' '=Space. */
void   emu_key_down(emu_t *e, int zx_key);
void   emu_key_up  (emu_t *e, int zx_key);

/* Set current Kempston joystick state (OR of EMU_JOY_*). */
void   emu_joystick(emu_t *e, uint8_t mask);

/* Returns a pointer to the 768-byte ZX Spectrum character font (chars
 * 0x20..0x7F, 8 rows of 1 byte each, MSB = leftmost pixel). Lives at
 * $3D00 in the 48K-compat ROM. Static data; safe to call any time. */
const uint8_t *emu_spectrum_font(void);

/* Enable / query the per-second peak amplitude log in the audio
 * trampoline (beeper peak vs ay peak). Off by default. main.c flips
 * it on when --audio-debug is passed on the command line. */
void emu_set_audio_debug(bool on);
bool emu_audio_debug(void);

/* Reset the ayumi AY emulator's internal state (DC blocker history,
 * oscillator phase, channel volumes) and re-sync the per-register
 * delta-detect cache so the next emu_run_frame replays every live
 * AY register into ayumi from scratch. Call this right after lifting
 * the precharge mute -- otherwise the first audible note inherits a
 * pile of state accumulated while the wrapper ran at 40x speed and
 * sounds distorted. */
void emu_audio_warmup_reset(emu_t *e);

/* Toggle ayumi processing in the audio trampoline. When off (false),
 * the trampoline returns early and ayumi is NOT ticked; the AY
 * register file on chips' side still tracks OUTs, but ayumi's filters
 * stay frozen. Use during the 40x turbo precharge so ayumi doesn't
 * accumulate filter history at 40x emulated speed -- followed by
 * emu_audio_warmup_reset() before re-enabling. */
void emu_set_audio_processing(emu_t *e, bool enabled);

/* Returns a pointer to the chips AY register file (14 bytes, R0..R13).
 * Read-only diagnostic; the layout is the standard AY-3-8910 indirect
 * register numbering. */
const uint8_t *emu_ay_regs(const emu_t *e);

/* Perf probe: per-tick CPU work measurement for the 50fps viability study.
 *
 * While enabled, every Z80 tick is classified as WORK (HALT pin low) or
 * IDLE (HALT pin high -- the game parks in HALT between frames), and every
 * rising MREQ edge into ULA-contended RAM (0x4000-0x7FFF, or a contended
 * bank 1/3/5/7 paged at 0xC000) is counted. chips does not emulate
 * contention delays, so the tick counts are a LOWER BOUND of real-HW time;
 * the contended-access count feeds the analytic uplift done offline.
 *
 * Output: one printf line per 50 ULA frames (1 emulated second) with the
 * sliding-two-frame (game runs at 25fps = 2 ULA frames per game frame)
 * work maximum/average, counts of pairs exceeding 1 / 2 frame budgets,
 * and session maxima. Off by default; ~0 cost while disabled. */
void emu_set_perf_probe(emu_t *e, bool on);

/* Dump the PC-sample histogram the probe accumulates (top 64-byte blocks
 * with work-tick counts; banked 0xC000+ blocks are prefixed "B<n>:").
 * reset != 0 clears the histogram after dumping. */
void emu_perf_hist_dump(emu_t *e, int reset);

/* Same data as emu_perf_hist_dump but written into `buf` (NUL-terminated)
 * instead of stdout, so a host/JS caller can fetch it without console
 * races. Returns the number of bytes written. */
size_t emu_perf_report(emu_t *e, int reset, char *buf, size_t cap);

/* Drill-down of the same histogram: per-8-byte-group counts in [lo, hi).
 * bank < 0 = always-visible 0x0000-0xBFFF; bank 0-7 = 0xC000+ window. */
size_t emu_perf_range(emu_t *e, int bank, uint32_t lo, uint32_t hi,
                      char *buf, size_t cap);
