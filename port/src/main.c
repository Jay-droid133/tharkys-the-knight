/*
 * Tharkys the Knight - desktop wrapper, main entry.
 *
 * Phase 1 booted the SNA in chips/zx and blitted with SDL_Renderer.
 * Phase 4 replaces that path with an OpenGL 3.3 core pipeline in video.c
 * so we can layer a CRT shader on top. main.c is now just orchestration:
 * SDL bootstrap, event pump, frame pacing.
 *
 * --sna <path>  swap the embedded blob for an external SNA (dev loop).
 */

#include <SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

#include "emu.h"
#include "gamepad.h"
#include "input.h"
#include "video.h"
#include "juego_sna.h"
#include "juego_tap.h"
#include "reward_font.h"
#include "splash_sprite.h"

/* Visible area emitted by chips/zx (screen + borders). */
#define VIS_W       320
#define VIS_H       256
#define WIN_SCALE   2
#define WIN_W       (VIS_W * WIN_SCALE)
#define WIN_H       (VIS_H * WIN_SCALE)

/* PAL 128K Spectrum runs at ~50.08 Hz; 20 ms is the host-side budget. */
#define FRAME_MS    20

static SDL_AudioDeviceID g_audio           = 0;
static int               g_audio_freq      = 44100;
static int               g_paused          = 0;
static int               g_splash_active   = 1;  /* dismissed on first input (SNA) or precharge done (TAP) */
static int               g_help_owns_pause = 0;  /* opener of help owes us an un-pause on close */
static int               g_audio_muted     = 0;  /* drop samples during TAP precharge so the turbo run is silent */
static int               g_audio_fade_in_samples = 0; /* set on unmute to ramp the first ~50 ms gracefully */
static int               g_splash_user_skip = 0;  /* user pressed something during the splash; dismiss ASAP */
static Uint64            g_splash_start_ms = 0;   /* timestamp of first frame of the wrapper splash (Jaydroid + bg257 cards) */
static int               g_splash_card = 0;       /* 0 = "Jaydroid's" presenter, 1 = bg257 title */
static Uint64            g_splash_card_start_ms = 0; /* timestamp of the current card (for per-card timing / skip) */
static int               g_input_needs_release = 0; /* set after skip/story-end; cleared once every key + pad button is in rest so the same press that triggered the skip doesn't reach the game */

/* Border crop mode -- F3 cycles between full (32 px ZX-authentic),
 * medium (16 px) and minimum (8 px = 1 char). Smaller borders let the
 * picture fill more of the window in fullscreen / TV setups.
 *
 * The actual cropping happens in the fragment shader via a symmetric
 * UV inset (same factor on both axes so the picture stays unstretched).
 * Texture stays full 320x256 so CRT effects (barrel, scanlines, mask)
 * keep their per-source-pixel calibration regardless of border mode. */
enum { BORDER_FULL = 0, BORDER_MEDIUM, BORDER_MIN, BORDER_MODE_COUNT };
static int g_border_mode = BORDER_FULL;
/* Zoom factor: 0 = full 320x256, 0.075 â‰ˆ 24 px off each X side / 19 off
 * each Y side, 0.10 â‰ˆ 32 px off X / 26 off Y. Chosen so MEDIUM hides
 * roughly half the original border and MIN drops it to a thin frame. */
static const float BORDER_ZOOM[BORDER_MODE_COUNT] = { 0.00f, 0.05f, 0.095f };
static const char *BORDER_NAME[BORDER_MODE_COUNT] = {
    "BORDER FULL", "BORDER MEDIUM", "BORDER MIN"
};

/* Audio diagnostic toggles (CLI flags). Each disables one of the recent
 * audio path changes so we can A/B test which (if any) introduced a
 * regression on a given machine. */
static int g_no_soft_clip   = 0;  /* skip the post-mix soft limiter      */
static int g_no_audio_pace  = 0;  /* go back to wall-clock 50 Hz pacing  */
static int g_force_44100    = 0;  /* don't let SDL change the freq       */
static int g_audio_debug    = 0;  /* per-second peak log in trampoline   */

/* Custom glyphs for Spanish accented vowels (Ã Ã‰ Ã Ã“ Ãš Ã¡ Ã© Ã­ Ã³ Ãº).
 * Hand-tweaked from the same reward font used by the in-game credits
 * cutscene, so the wrapper text matches the visual style of the rest
 * of the game. Each glyph is 8 bytes (one row per byte, MSB = left
 * pixel) and lives at codepoint 0x80 + array index. */
static const uint8_t EXT_FONT_GLYPHS[] = {
    /* 0x80 Ã¡ */ 0x06, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0xFE, 0x76,
    /* 0x81 Ã© */ 0x06, 0x00, 0x3C, 0x66, 0x7E, 0x60, 0x7E, 0x3E,
    /* 0x82 Ã­ */ 0x0C, 0x08, 0x00, 0x38, 0x38, 0x18, 0x3C, 0x3C,
    /* 0x83 Ã³ */ 0x06, 0x00, 0x3C, 0x7E, 0x66, 0x66, 0x7E, 0x3C,
    /* 0x84 Ãº */ 0x06, 0x00, 0xEE, 0xEE, 0x66, 0x6E, 0x7F, 0x37,
    /* 0x85 Ã */ 0x06, 0x30, 0x38, 0x6C, 0x6C, 0xFE, 0xC6, 0xC6,
    /* 0x86 Ã‰ */ 0x07, 0xFE, 0xFE, 0x66, 0x70, 0x66, 0xFE, 0xFE,
    /* 0x87 Ã */ 0x06, 0x00, 0x3C, 0x3C, 0x18, 0x18, 0x3C, 0x3C,
    /* 0x88 Ã“ */ 0x06, 0x38, 0x7C, 0xEE, 0xC6, 0xEE, 0x7C, 0x38,
    /* 0x89 Ãš */ 0x03, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0xFE, 0x7C,
    /* 0x8A Ã± */ 0x28, 0x14, 0x00, 0xEC, 0xFE, 0x76, 0xE7, 0xE7,
    /* 0x8B Ã‘ */ 0x3C, 0x00, 0xF7, 0xF3, 0x7B, 0x6F, 0xE7, 0xF7,
};
#define EXT_FONT_COUNT ((int)(sizeof(EXT_FONT_GLYPHS) / 8))

/* UTF-8 â†’ compact-byte conversion. The story strings are stored with
 * real accented characters (e.g. "Ã¡" = 0xC3 0xA1 in UTF-8 source), and
 * compose_line wants single-byte codepoints, so we rewrite the string
 * in place at startup: every 2-byte UTF-8 sequence we recognise turns
 * into a one-byte code in the 0x80..0x89 range that maps to one of
 * EXT_FONT_GLYPHS above. Unknown UTF-8 sequences are dropped to '?' so
 * they're visible during testing. The conversion always produces a
 * shorter-or-equal string, so it's safe to write back into the source
 * buffer. */
static void utf8_to_compact(char *s) {
    char *out = s;
    for (const unsigned char *in = (const unsigned char *)s; *in; ) {
        if (*in == 0xC3 && in[1]) {
            char mapped = '?';
            switch (in[1]) {
                case 0xA1: mapped = (char)0x80; break;  /* Ã¡ */
                case 0xA9: mapped = (char)0x81; break;  /* Ã© */
                case 0xAD: mapped = (char)0x82; break;  /* Ã­ */
                case 0xB3: mapped = (char)0x83; break;  /* Ã³ */
                case 0xBA: mapped = (char)0x84; break;  /* Ãº */
                case 0x81: mapped = (char)0x85; break;  /* Ã */
                case 0x89: mapped = (char)0x86; break;  /* Ã‰ */
                case 0x8D: mapped = (char)0x87; break;  /* Ã */
                case 0x93: mapped = (char)0x88; break;  /* Ã“ */
                case 0x9A: mapped = (char)0x89; break;  /* Ãš */
                case 0xB1: mapped = (char)0x8A; break;  /* Ã± */
                case 0x91: mapped = (char)0x8B; break;  /* Ã‘ */
                default: break;
            }
            *out++ = mapped;
            in   += 2;
        } else {
            *out++ = (char)*in++;
        }
    }
    *out = '\0';
}

/* Story pages shown after the title splash + language menu. Spanish
 * text now uses real accents (Ã¡ Ã© Ã­ Ã³ Ãº); they're translated to the
 * extended-font codepoints at startup. Each line stays under 28 chars;
 * the first "line" of every page is blank so compose_help_overlay
 * treats the whole page as left-aligned body centred as a block. */
static char STORY_PAGES_ES[][384] = {
    "\n"
    "Sir Tharkys es un tipo\n"
    "con mala suerte.\n"
    "Durante mucho tiempo\n"
    "extendiÃ³ cheques que su\n"
    "cuerpo no podÃ­a pagar.\n"
    "Su escudero le ha\n"
    "abandonado. Le ha\n"
    "abandonado hasta\n"
    "su caballo.",

    "\n"
    "No le queda mÃ¡s remedio\n"
    "que ir allÃ¡ donde se\n"
    "requiera una espada,\n"
    "esperando algunas migajas\n"
    "a cambio de sus servicios.",

    "\n"
    "Le llegaron noticias\n"
    "de un pueblo que vive\n"
    "atemorizado por unos\n"
    "monstruos de origen\n"
    "desconocido.\n"
    "A quien les liberara,\n"
    "prometÃ­an entregar una\n"
    "jugosa recompensa que le\n"
    "sacarÃ­a de sus apuros.",

    "\n"
    "Tras hablar con el\n"
    "alcalde, Ã©ste le entrega\n"
    "una brÃºjula rota que\n"
    "le indicarÃ¡ vagamente\n"
    "la ubicaciÃ³n de sus\n"
    "objetivos. TambiÃ©n dice\n"
    "que tenÃ­a un mapa en\n"
    "una servilleta (!?!),\n"
    "pero se lo llevÃ³\n"
    "el aire (!!\?\?!!).",

    "\n"
    "Le desea buena suerte\n"
    "y, como despedida, avisa\n"
    "que han cerrado la puerta\n"
    "de la ciudad para que no\n"
    "ceda a la tentaciÃ³n\n"
    "de huir.",

    "\n"
    "Ganas le dan, tras ver\n"
    "cÃ³mo estÃ¡ todo lleno\n"
    "de bichos y, sobre todo,\n"
    "tras conocer que muchos\n"
    "otros caballeros\n"
    "han caÃ­do antes\n"
    "en el intento...",
};

/* English version, same six-page split as the Spanish text. */
static const char *STORY_PAGES_EN[] = {
    "\n"
    "Sir Tharkys is a man\n"
    "with bad luck.\n"
    "For a long time he wrote\n"
    "checks his body could not\n"
    "cash. His squire has\n"
    "abandoned him.\n"
    "Even his horse has\n"
    "abandoned him.",

    "\n"
    "He has no choice but\n"
    "to go wherever a sword\n"
    "is needed, hoping for\n"
    "a few scraps in return\n"
    "for his services.",

    "\n"
    "Word reached him of a\n"
    "village living in terror\n"
    "of monsters of unknown\n"
    "origin. To whoever freed\n"
    "them, they promised a\n"
    "handsome reward that\n"
    "would lift the knight out\n"
    "of his financial troubles.",

    "\n"
    "After speaking with the\n"
    "mayor, the latter hands\n"
    "him a broken compass\n"
    "that will vaguely show\n"
    "the location of his\n"
    "targets. He also mentions\n"
    "a map on a napkin (!?!),\n"
    "but the wind blew it\n"
    "away (!!\?\?!!).",

    "\n"
    "He wishes him good luck\n"
    "and, as a parting note,\n"
    "informs him they have\n"
    "locked the town gate so\n"
    "he cannot give in to the\n"
    "temptation of fleeing.",

    "\n"
    "He feels like doing just\n"
    "that, after seeing the\n"
    "place crawling with\n"
    "creatures and, above all,\n"
    "after learning that many\n"
    "knights have already\n"
    "fallen trying...",
};

/* Active language flag; set by the language menu (defaults to Spanish
 * so SNA dev boots that skip the menu still get something). */
static int g_lang_is_english = 0;
static const char *story_get_page(int p) {
    return g_lang_is_english ? STORY_PAGES_EN[p] : STORY_PAGES_ES[p];
}
#define NUM_STORY_PAGES ((int)(sizeof(STORY_PAGES_ES) / sizeof(STORY_PAGES_ES[0])))

/* No auto-advance: every page transition is user-driven (the pro
 * pattern -- respects reading speed, no race-del-dedo possible). The
 * game's own SplashWait icons (already running in VRAM under the
 * transparent help overlay) serve as the "press to continue" cue. */

/* After the story finishes (or is skipped) we want the press that
 * triggered the transition to NOT also fire the game's SplashWait.
 * Strategy: latch g_input_needs_release; while it's set we forward no
 * input; it's cleared the moment every key and pad button is back to
 * rest. The user's NEXT press lands clean on the game splash. */

/* -1 = inactive, 0..NUM_STORY_PAGES-1 = page currently on screen. */
static int    g_story_page          = -1;
static Uint64 g_story_page_start_ms = 0;

/* Language picker shown before the story. Three options:
 *   0 = English     (story in English)
 *   1 = EspaÃ±ol     (story in Spanish)
 *   2 = Skip story  (jump straight to the game without narration)
 * Navigable with cursor keys / WASD / D-pad / stick, confirmed with
 * ENTER / SPACE / any face button. */
static int g_lang_menu_active = 0;
static int g_lang_selected    = 0;
#define LANG_MENU_OPTIONS 3

/* Forward decls; defined after g_video is in scope. */
static void story_show_page(int page);
static void lang_menu_refresh(void);
static void lang_menu_confirm(void);

/* Multi-line help screen (F1). Centred on a 32-col Spectrum screen, so
 * keep every line <= 32 chars. Uppercase reads best in the ZX font. */
static const char *HELP_TEXT =
    "THARKYS THE KNIGHT\n"
    "\n"
    "MOVE   Q A O P / W A S D\n"
    "       OR ARROW KEYS\n"
    "FIRE   SPACE / CTRL\n"
    "MAP    M\n"
    "PAUSE  ESC\n"
    "CRT    F2\n"
    "BORDER F3\n"
    "FULL   F11\n"
    "EXIT   ESC ESC (WHILE PAUSED)\n"
    "\n"
    "GAMEPAD  D-PAD / STICK / A B X Y\n"
    "START PAUSE   BACK MAP\n"
    "\n"
    "F1 TO CLOSE";

/* Toggle pause from any source (keyboard, gamepad). Freezes the emulator
 * and silences audio; the last rendered frame keeps showing because chips'
 * framebuffer doesn't change when zx_exec isn't called.
 *
 * On pause: drop the queued audio so resume starts fresh instead of
 * replaying ~50 ms of stale samples (SDL_PauseAudioDevice alone would
 * keep the queue, causing a brief snippet from before the pause to play
 * on resume). */
static video_t   *g_video      = NULL;  /* set in main() so toggle_pause can update it */
static SDL_Window *g_win        = NULL;
static emu_t      *g_emu        = NULL;
static gamepad_t  *g_pad        = NULL;
static int        g_running     = 1;
static int        g_fullscreen  = 0;
static Uint64     g_next_tick   = 0;
enum { BOOT_SNA, BOOT_TAP };
static int        g_boot_mode   = BOOT_TAP;

static void one_frame(void);  /* fwd: body of the main loop, one iteration */

#ifdef __EMSCRIPTEN__
/* ---- Web audio: pull-based callback + lock-free ring buffer ----------
 *
 * SDL_QueueAudio (push model) is the wrong fit for the browser: the
 * emulator produces samples in irregular bursts (RAF jitter, tab
 * throttling), so the queue alternately starves and overflows and you
 * hear clicks. Instead we run SDL audio in CALLBACK mode -- the browser
 * pulls a fixed block whenever its AudioContext needs one -- and bridge
 * producer (emu) to consumer (device) through a ring buffer.
 *
 * Single-threaded Emscripten has no real preemption: the audio callback
 * and the main loop interleave cooperatively on one thread, so a plain
 * unsynchronised ring is safe here. On underrun the callback holds the
 * last sample (a DC hold is far less audible than zero-filling, which
 * clicks). RING_CAP is a power of two so the masks are cheap. */
#define RING_CAP 32768                 /* mono floats; ~680 ms @ 48 kHz */
static float    g_ring[RING_CAP];
static unsigned g_ring_w = 0;          /* producer index (emu)    */
static unsigned g_ring_r = 0;          /* consumer index (device) */
static float    g_ring_last = 0.0f;    /* held on underrun        */

static inline unsigned ring_count(void) {
    return (g_ring_w - g_ring_r) & (RING_CAP - 1);
}

static void ring_write(const float *src, int n) {
    for (int i = 0; i < n; i++) {
        const unsigned next = (g_ring_w + 1) & (RING_CAP - 1);
        if (next == g_ring_r) break;   /* full: drop (pacing prevents this) */
        g_ring[g_ring_w] = src[i];
        g_ring_w = next;
    }
}

/* SDL pull callback: copy from the ring, hold last sample on underrun. */
static void audio_callback(void *user, Uint8 *stream, int len) {
    (void)user;
    float    *out = (float *)stream;
    const int n   = len / (int)sizeof(float);
    for (int i = 0; i < n; i++) {
        if (g_ring_r != g_ring_w) {
            g_ring_last = g_ring[g_ring_r];
            g_ring_r = (g_ring_r + 1) & (RING_CAP - 1);
        }
        out[i] = g_ring_last;
    }
}

/* Pace the emulator by ring fill level rather than wall-clock: run frames
 * until the ring holds ~150 ms of cushion, capped at 4 frames per tick so
 * a stall can't spin us. The callback drains the ring at the device's
 * exact crystal rate, so this self-regulates regardless of RAF cadence or
 * monitor refresh. Muted precharge (cards 0/1) just steps once. */
static void emu_step_for_audio(void) {
    if (g_audio_muted || !g_audio) {
        emu_run_frame(g_emu);
        return;
    }
    const unsigned target = (unsigned)(g_audio_freq * 150 / 1000); /* 150 ms */
    int budget = 4;
    while (ring_count() < target && budget-- > 0) {
        emu_run_frame(g_emu);
    }
}
#endif

static void toggle_pause(void) {
    g_paused = !g_paused;
    if (g_audio) {
        if (g_paused) {
            SDL_ClearQueuedAudio(g_audio);
            SDL_PauseAudioDevice(g_audio, 1);
        } else {
            SDL_PauseAudioDevice(g_audio, 0);
        }
    }
    if (g_video) video_set_paused(g_video, g_paused);
    fprintf(stderr, "[tharkys] %s\n", g_paused ? "paused" : "resumed");
}

/* Drop the help overlay and roll back any pause we ourselves opened.
 * If the user toggled pause manually between open and close, their P
 * state wins (we only un-pause when help_owns_pause says we caused it). */
static void close_help(void) {
    if (!g_video) return;
    video_set_help(g_video, NULL);
    if (g_help_owns_pause && g_paused) toggle_pause();
    g_help_owns_pause = 0;
}

/* Rebuild the language menu overlay with the current selection. The
 * caret is rendered as '>' on the chosen line and a space on the other.
 * Held in a static buffer so video_set_help can keep its pointer. */
static void lang_menu_refresh(void) {
    if (!g_video) return;
    /* Two buffers: raw (with UTF-8 from the source) and compact (after
     * utf8_to_compact, what we hand to video_set_help). The compact
     * buffer is what compose_help_overlay reads, so it must outlive
     * this function -- 'static'. */
    static char raw[192];
    static char buf[192];
    snprintf(raw, sizeof(raw),
             "\n"
             "Select language / Elige idioma\n"
             "\n"
             "%c English\n"
             "%c EspaÃ±ol\n"
             "\n"
             "\n"
             "%c Skip story / Saltar historia",
             g_lang_selected == 0 ? '>' : ' ',
             g_lang_selected == 1 ? '>' : ' ',
             g_lang_selected == 2 ? '>' : ' ');
    /* Copy then convert in place. */
    snprintf(buf, sizeof(buf), "%s", raw);
    utf8_to_compact(buf);
    video_set_help(g_video, buf);
}

/* Commit the menu selection and hand off to the story (or skip it). */
static void lang_menu_confirm(void) {
    g_lang_menu_active  = 0;
    if (g_video) video_set_help(g_video, NULL);
    if (g_lang_selected == 2) {
        /* Skip story: latch the "needs release" gate so the same press
         * that confirmed the skip doesn't bleed into the game's
         * SplashWait. The gate clears as soon as the user releases. */
        g_input_needs_release = 1;
        fprintf(stderr, "[tharkys] story skipped\n");
        return;
    }
    g_lang_is_english = (g_lang_selected == 0);
    fprintf(stderr, "[tharkys] language = %s\n",
            g_lang_is_english ? "English" : "Spanish");
    story_show_page(0);
}

/* Show story page `page`. page < 0 or >= NUM_STORY_PAGES ends the story
 * and clears the overlay so the game's own splash (with the animated
 * key/button icons) becomes visible. Called from the precharge hand-off,
 * from the auto-advance timer, and from the user input skip. */
/* The story overlay renders straight on top of the game's own splash,
 * which already has the animated key/button icons painted in VRAM by
 * SplashWait. So the page text is just the narration -- the game
 * supplies the "press to continue" visual cue automatically. */
static void story_show_page(int page) {
    if (!g_video) return;
    if (page < 0 || page >= NUM_STORY_PAGES) {
        g_story_page = -1;
        video_set_help(g_video, NULL);
        video_set_help_preserve_rect(g_video, 0, 0, 0, 0);
        /* Same gate as the skip path: the press that flipped past the
         * last page shouldn't also fire the game's SplashWait. */
        g_input_needs_release = 1;
        fprintf(stderr, "[tharkys] story ended\n");
        return;
    }
    g_story_page          = page;
    g_story_page_start_ms = SDL_GetTicks64();

    /* Mask out everything except the two 16x16 SplashWait icons (key +
     * button) painted by the game at char rows 22-23, cols 14-17. In
     * wrapper pixel coords (32 px border around 256x192):
     *   x = 32 + 14*8 = 144     w = 4 chars * 8 = 32 px
     *   y = 32 + 22*8 = 208     h = 2 chars * 8 = 16 px
     * The narration sits on black; the animated icons keep blinking
     * underneath as the "press to continue" affordance. */
    video_set_help_preserve_rect(g_video, 144, 208, 32, 16);
    video_set_help(g_video, story_get_page(page));
    fprintf(stderr, "[tharkys] story page %d/%d\n", page + 1, NUM_STORY_PAGES);
}

/* Audio pacing.
 *
 * The host audio device runs on its own crystal clock; SDL_Delay-based
 * wall-clock frame pacing is bounded by SDL_Delay's resolution and the
 * scheduler. The two clocks drift by a fraction of a percent. With a
 * tight queue cap (the old 50 ms), that drift trips the cap a few times
 * a second and chunks of audio get dropped -- after a few minutes the
 * music sounds progressively broken even though each individual drop is
 * tiny. That's exactly the "music deteriorates over time" symptom.
 *
 * Fix: in the main loop, pace the emulator to the audio queue (see
 * `Pacing` below). With audio-driven pacing the queue oscillates inside
 * a tight band around the target and the safety cap is only there to
 * catch real anomalies (system sleep, ALSA hiccup), so we can lift it
 * generously without paying any latency. */
#define AUDIO_TARGET_QUEUE_MS  50   /* what the emulator paces to        */
#ifdef __EMSCRIPTEN__
#define AUDIO_MAX_QUEUE_MS     1000 /* web: high cap -- the fixed-timestep
                                     * accumulator keeps production matched
                                     * to consumption, so dropping chunks
                                     * (which causes clicks) is never the
                                     * right response to setTimeout jitter */
#else
#define AUDIO_MAX_QUEUE_MS     200  /* hard cap; drop chunks above this  */
#endif

/* Smooth-knee soft limiter, used in audio_push to catch any sample that
 * would otherwise clip on the host audio device. Rational soft-clip:
 * the curve is identity below Â±0.95 (no flavour added in the normal
 * range) and asymptotes to Â±1.0 above. Crucially it's smooth -- a hard
 * clip throws off harmonics that sound buzzy, this one just rolls the
 * peak off.
 *
 * Why it matters: chips' AY mixer sums all three tone channels raw, so
 * a chord at vol 15 on all three (which is exactly what the bell SFX
 * does on attack) reaches an instantaneous raw value of ~3.0 before the
 * AY's `mag` scale -- and the 11.6 ms DC-adjust buffer hasn't kicked in
 * yet at onset, so the post-DC peak rides right at 3 * 0.33 = 0.99.
 * Add even a touch of beeper residual on top and we go above 1.0. With
 * this limiter the bell stays clean and we don't need to keep dropping
 * ay_volume further (which would just trade distortion for muddiness). */
static inline float soft_clip(float x) {
    if (x >  0.95f) { const float o = x - 0.95f;
                      return  0.95f + o / (1.0f + o * 20.0f); }
    if (x < -0.95f) { const float o = -0.95f - x;
                      return -0.95f - o / (1.0f + o * 20.0f); }
    return x;
}

/* Emit a processed mono-float block to the device. Desktop pushes to the
 * SDL audio queue; the web build hands it to the ring buffer drained by
 * audio_callback. */
static inline void audio_emit(const float *buf, int num_samples) {
#ifdef __EMSCRIPTEN__
    ring_write(buf, num_samples);
#else
    SDL_QueueAudio(g_audio, buf, (Uint32)(num_samples * sizeof(float)));
#endif
}

static void audio_push(const float *samples, int num_samples, void *user) {
    (void)user;
    if (!g_audio || g_audio_muted) return;
#ifdef __EMSCRIPTEN__
    /* Callback mode has no SDL queue; gate on ring fill instead. Leave
     * headroom (a full chips batch) so ring_write never has to drop. */
    if (ring_count() > RING_CAP - 1024 - 1) {
        return;
    }
#else
    const Uint32 cap_bytes = (Uint32)(g_audio_freq * sizeof(float) *
                                      AUDIO_MAX_QUEUE_MS / 1000);
    if (SDL_GetQueuedAudioSize(g_audio) > cap_bytes) {
        return; /* queue already too deep, drop this chunk */
    }
#endif
    /* chips' default audio batch is 128 samples; the system-level max is
     * 1024 (ZX_MAX_AUDIO_SAMPLES). 1024 floats = 4 KB on the stack, safe. */
    float buf[1024];
    if (num_samples > 1024) num_samples = 1024;
    /* Very short exponential fade-in (~10 ms) to absorb the DC step
     * when ayumi goes from cold to a live note. Curve: gain = 1 - x^4
     * where x = fade_left / fade_total; reaches 0.94 at the halfway
     * point so the attack of the first note is barely attenuated. */
    const int fade_total = g_audio_freq / 100; /* ~10 ms in samples */
    int fade_left = g_audio_fade_in_samples;
    /* Inline lambda for the fade gain (1 - x^4 curve where x runs 1â†’0).
     * Reaches 0.94 at the halfway point, so the attack of the note is
     * audible almost immediately while the very first samples that
     * carry the DC step are softly squashed. */
    #define FADE_GAIN(left, total) \
        ({ const float _x = (float)(left) / (float)(total); \
           const float _x2 = _x * _x; \
           1.0f - _x2 * _x2; })
    if (g_no_soft_clip) {
        if (fade_left > 0) {
            for (int i = 0; i < num_samples; i++) {
                const float g = (fade_left > 0) ? FADE_GAIN(fade_left, fade_total) : 1.0f;
                buf[i] = samples[i] * g;
                if (fade_left > 0) fade_left--;
            }
            g_audio_fade_in_samples = fade_left;
            audio_emit(buf, num_samples);
        } else {
            audio_emit(samples, num_samples);
        }
        return;
    }
    for (int i = 0; i < num_samples; i++) {
        float s = soft_clip(samples[i]);
        if (fade_left > 0) {
            s *= FADE_GAIN(fade_left, fade_total);
            fade_left--;
        }
        buf[i] = s;
    }
    #undef FADE_GAIN
    g_audio_fade_in_samples = fade_left;
    audio_emit(buf, num_samples);
}

static uint8_t *load_file(const char *path, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long n = ftell(f);
    if (n <= 0) { fclose(f); return NULL; }
    rewind(f);
    uint8_t *buf = (uint8_t *)malloc((size_t)n);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);
    if (got != (size_t)n) { free(buf); return NULL; }
    *out_size = (size_t)n;
    return buf;
}

int main(int argc, char *argv[]) {
    /* --- args -------------------------------------------------------- */
    const char *sna_path        = NULL;
    const char *tap_path        = NULL;
    int         start_fullscreen = 0;
    int         start_windowed   = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--sna") == 0 && i + 1 < argc) {
            sna_path = argv[++i];
        } else if (strcmp(argv[i], "--tap") == 0 && i + 1 < argc) {
            tap_path = argv[++i];
        } else if (strcmp(argv[i], "--fullscreen") == 0) {
            start_fullscreen = 1;
        } else if (strcmp(argv[i], "--windowed") == 0) {
            start_windowed = 1;
        } else if (strcmp(argv[i], "--no-soft-clip") == 0) {
            g_no_soft_clip = 1;
        } else if (strcmp(argv[i], "--no-audio-pace") == 0) {
            g_no_audio_pace = 1;
        } else if (strcmp(argv[i], "--force-44100") == 0) {
            g_force_44100 = 1;
        } else if (strcmp(argv[i], "--audio-debug") == 0) {
            g_audio_debug = 1;
        }
    }

    /* On Windows GUI-subsystem builds the process has no console, so
     * fprintf(stderr, ...) goes nowhere regardless of how it's launched.
     * Redirect stderr to a log file beside the .exe so the user can read
     * the runtime info / debug messages with any text editor. Unbuffered
     * so live tail-watching shows updates instantly. */
    {
        char *base = SDL_GetBasePath();
        if (base) {
            char log_path[1024];
            snprintf(log_path, sizeof(log_path), "%stharkys.log", base);
            if (freopen(log_path, "w", stderr)) {
                setvbuf(stderr, NULL, _IONBF, 0);
            }
            SDL_free(base);
        }
    }

#ifdef __EMSCRIPTEN__
    /* Capture keys on the canvas only, not the whole window. With the
     * default ("#window") SDL calls preventDefault on every keydown, so
     * the browser's own shortcuts (Ctrl+Shift+R to reload, F12 for
     * DevTools, Ctrl+T, etc.) all die while the page is open. Scoping to
     * "#canvas" means the game only grabs the keyboard once the user
     * clicks the canvas; clicking outside it (e.g. the address bar)
     * hands the shortcuts back. Must be set before SDL_Init. */
    SDL_SetHint(SDL_HINT_EMSCRIPTEN_KEYBOARD_ELEMENT, "#canvas");
#endif

    /* --- SDL --------------------------------------------------------- */
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER) != 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return EXIT_FAILURE;
    }

    /* Default startup mode is maximised: title bar stays accessible so
     * the user can resize / close without keyboard, but the picture is
     * already filling their screen. --fullscreen takes over the whole
     * desktop (Esc / F11 to exit). --windowed forces the 640x512 default. */
    Uint32 win_flags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_OPENGL;
    if (start_fullscreen) {
        win_flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    } else if (!start_windowed) {
        win_flags |= SDL_WINDOW_MAXIMIZED;
    }

    g_win = SDL_CreateWindow(
        "Tharkys the Knight",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_W, WIN_H,
        win_flags
    );
    if (!g_win) {
        fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        return EXIT_FAILURE;
    }
    SDL_SetWindowMinimumSize(g_win, VIS_W, VIS_H);

    /* --- Video (OpenGL + CRT shader on desktop / SDL_Renderer on web) -- */
    g_video = video_create(g_win);
    if (!g_video) {
        fprintf(stderr, "video_create failed\n");
        SDL_DestroyWindow(g_win);
        SDL_Quit();
        return EXIT_FAILURE;
    }

    /* --- Audio: mono float32, queue mode ----------------------------- */
    /* Request 44.1 kHz but allow SDL to give us the device's native rate
     * (Windows / macOS mixers usually run at 48 kHz). chips gets told
     * whatever was negotiated via emu_desc.sample_rate below, so the AY
     * runs natively at the same rate the device consumes -- no Windows-
     * side resampling pass, which on old Realtek drivers can soften the
     * AY's sharp square-wave edges or add subtle aliasing. */
    SDL_AudioSpec want = {0}, have = {0};
    want.freq     = 44100;
    want.format   = AUDIO_F32SYS;
    want.channels = 1;
#ifdef __EMSCRIPTEN__
    /* Web: CALLBACK mode (pull). The browser asks for a 2048-sample block
     * whenever its AudioContext needs one; audio_callback serves it from
     * the ring buffer that emu_step_for_audio keeps topped up.
     *
     * CRITICAL: SDL's Emscripten audio backend does NOT resample -- it
     * feeds our samples straight into a Web Audio context whose sample
     * rate is fixed by the browser/OS (almost always 48000 Hz). If we
     * produced at 44100 the ring would drain ~9 % faster than it fills
     * and underrun forever (the crackle). So query the context's native
     * rate up front and produce at exactly that. */
    want.samples  = 2048;
    want.callback = audio_callback;
    {
        /* emscripten_run_script_int (not EM_ASM, which needs -std=gnu*) */
        const int browser_rate = emscripten_run_script_int(
            "(function(){try{"
            "var AC=window.AudioContext||window.webkitAudioContext;"
            "var c=new AC();var r=c.sampleRate|0;c.close();return r;"
            "}catch(e){return 0;}})()");
        if (browser_rate >= 8000) want.freq = browser_rate;
    }
    /* Don't allow a frequency change: we already matched the device, and
     * letting SDL pick a different rate would re-introduce the mismatch. */
    g_audio = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
#else
    want.samples  = 1024;
    want.callback = NULL;  /* desktop: queue mode (SDL_QueueAudio) */
    g_audio = SDL_OpenAudioDevice(NULL, 0, &want, &have,
                                  g_force_44100 ? 0 : SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
#endif
    if (g_audio) {
        g_audio_freq = have.freq;
        fprintf(stderr, "[tharkys] audio: %d Hz mono float32 (%d sample buffer)\n",
                have.freq, have.samples);
        SDL_PauseAudioDevice(g_audio, 0);
    } else {
        fprintf(stderr, "SDL_OpenAudioDevice failed (silent run): %s\n", SDL_GetError());
    }

    /* --- Emulator ---------------------------------------------------- */
    const emu_desc_t emu_desc = {
        .sample_rate = g_audio ? have.freq : 44100,
        .audio_cb    = audio_push,
        .audio_user  = NULL,
    };
    g_emu = emu_create(&emu_desc);
    if (!g_emu) {
        fprintf(stderr, "emu_create failed\n");
        return EXIT_FAILURE;
    }

    /* Install the reward font (Damien Guard / ZX Origins) as the
     * overlay font for the wrapper. Same 8x8 layout as the ROM font
     * but bold + drop shadow, matching the in-game credits cutscene.
     * Used by the language menu, the story pages, the PAUSE label and
     * the F1 help screen. The accented glyphs in EXT_FONT_GLYPHS were
     * hand-tweaked to sit on top of reward, so the look stays coherent. */
    video_set_pause_font(g_video, reward_font);

    /* Install custom glyphs for Spanish accented vowels (codepoints
     * 0x80..0x89) and rewrite the in-place Spanish story pages to use
     * those compact codepoints instead of multi-byte UTF-8. The EN
     * pages are plain ASCII and don't need conversion. */
    video_set_extended_font(g_video, EXT_FONT_GLYPHS, EXT_FONT_COUNT);
    for (int i = 0; i < NUM_STORY_PAGES; i++) {
        utf8_to_compact(STORY_PAGES_ES[i]);
    }

    /* Pick the boot source. Priority:
     *   --sna <path>   external SNA snapshot (instant boot, no tape menu)
     *   --tap <path>   external TAP cassette (goes through 128K menu)
     *   default        embedded juego_release.tap (with BASIC LOADER + splash)
     *
     * The TAP path leaves the Z80 in the ROM 128K boot menu; main.c will
     * auto-press ENTER after a short delay to pick "Tape Loader", at which
     * point emu.c's LD-BYTES trap streams blocks straight from the blob. */
    const uint8_t *blob_data = NULL;
    size_t         blob_size = 0;
    uint8_t       *blob_loaded = NULL;

    if (sna_path) {
        g_boot_mode = BOOT_SNA;
        blob_loaded = load_file(sna_path, &blob_size);
        if (!blob_loaded) {
            fprintf(stderr, "Cannot read SNA file: %s\n", sna_path);
            return EXIT_FAILURE;
        }
        blob_data = blob_loaded;
        fprintf(stderr, "[tharkys] loading external SNA: %s (%zu bytes)\n",
                sna_path, blob_size);
    } else if (tap_path) {
        g_boot_mode = BOOT_TAP;
        blob_loaded = load_file(tap_path, &blob_size);
        if (!blob_loaded) {
            fprintf(stderr, "Cannot read TAP file: %s\n", tap_path);
            return EXIT_FAILURE;
        }
        blob_data = blob_loaded;
        fprintf(stderr, "[tharkys] loading external TAP: %s (%zu bytes)\n",
                tap_path, blob_size);
    } else {
        g_boot_mode = BOOT_TAP;
        blob_data = juego_tap;
        blob_size = juego_tap_len;
        fprintf(stderr, "[tharkys] using embedded TAP (%zu bytes)\n", blob_size);
    }

    if (g_boot_mode == BOOT_SNA) {
        if (!emu_load_sna(g_emu, blob_data, blob_size)) {
            fprintf(stderr, "emu_load_sna: rejected blob (size=%zu; expected 131103 for 128K)\n",
                    blob_size);
            return EXIT_FAILURE;
        }
    } else {
        if (!emu_load_tap(g_emu, blob_data, blob_size)) {
            fprintf(stderr, "emu_load_tap: rejected blob (size=%zu)\n", blob_size);
            return EXIT_FAILURE;
        }
        /* Heap-allocated tap blobs need to outlive emu_load_tap, since the
         * tape trap reads from them on demand. Embedded blob lives in
         * .rodata; external blob lives on the heap and must not be freed
         * here. NULL out blob_loaded so the free() below is a no-op. */
        blob_loaded = NULL;
    }
    free(blob_loaded);

    /* --- Gamepad ---------------------------------------------------- */
    g_pad = gamepad_create();
    if (!g_pad) {
        fprintf(stderr, "gamepad_create failed (continuing without gamepad)\n");
    }
    /* Suppress analog-axis events during precharge: a connected stick
     * with even a tiny resting drift fires AXIS_MOTION events at the
     * SDL event-queue rate, and the resulting event-pump pressure has
     * been observed to coincide with first-note audio distortion on
     * the unmute boundary. We keep BUTTON events live so the user can
     * still skip the splash. Re-armed once the splash is dismissed. */
    SDL_EventState(SDL_CONTROLLERAXISMOTION, SDL_IGNORE);

    if (g_no_soft_clip || g_no_audio_pace || g_force_44100 || g_audio_debug) {
        fprintf(stderr, "[tharkys] audio diag flags:%s%s%s%s\n",
                g_no_soft_clip  ? " --no-soft-clip"  : "",
                g_no_audio_pace ? " --no-audio-pace" : "",
                g_force_44100   ? " --force-44100"   : "",
                g_audio_debug   ? " --audio-debug"   : "");
    }
    if (g_audio_debug) emu_set_audio_debug(true);
    fprintf(stderr, "[tharkys] running. Move: QAOP/WASD/arrows. Fire: Space/Ctrl. Esc=pause (Esc Esc=quit), F1=help, F2=CRT, F11=fullscreen.\n");

    /* --- Main loop --------------------------------------------------- */
    g_next_tick  = SDL_GetTicks64();
    g_fullscreen = start_fullscreen;

#ifdef __EMSCRIPTEN__
    /* Browser: hand the loop over to requestAnimationFrame (fps=0).
     * setTimeout(20ms) jitter is ±4-8 ms which a small audio buffer
     * can't absorb; instead we drive the emu rate from inside one_frame
     * using the SDL audio queue depth as feedback -- see
     * emu_step_for_audio(). RAF gives a smooth presentation while the
     * audio device's crystal clock effectively paces the emulator.
     * simulate_infinite_loop=1 makes this call never return. */
    emscripten_set_main_loop(one_frame, 0, 1);
    return EXIT_SUCCESS;  /* unreachable */
#else
    while (g_running) one_frame();

    /* --- Cleanup ----------------------------------------------------- */
    gamepad_destroy(g_pad);
    emu_destroy(g_emu);
    if (g_audio) SDL_CloseAudioDevice(g_audio);
    video_destroy(g_video);
    SDL_DestroyWindow(g_win);
    SDL_Quit();
    return EXIT_SUCCESS;
#endif
}

/* One iteration of the main loop: event pump, splash / story / lang menu
 * state machine, emu_run_frame, video_present, audio pacing. Driven by
 * emscripten_set_main_loop in the browser and by a plain while(g_running)
 * loop on desktop. All state lives in g_* globals so the function is
 * idempotent across calls. */
static void one_frame(void) {
#ifdef __EMSCRIPTEN__
        /* MVP web: video_web.c stubs out the text/sprite overlays that
         * the wrapper splash, lang menu and story rely on. Force-skip
         * each wrapper card as soon as the TAP precharge advances, so
         * the user lands on the game's own (rendered) splash screen
         * instead of staring at ~10 s of black. Lang menu + story are
         * skipped where they are activated, below. */
        if (g_splash_active) g_splash_user_skip = 1;
#endif
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            switch (ev.type) {
                case SDL_QUIT:
                    g_running = 0;
                    break;

                case SDL_WINDOWEVENT:
                    if (ev.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                        video_resize(g_video, ev.window.data1, ev.window.data2);
                    }
                    break;

                case SDL_KEYDOWN: {
                    SDL_Keycode k = ev.key.keysym.sym;
                    /* Splash dismissal: first key fires *only* the dismiss
                     * (consume it, don't propagate to game / wrapper).
                     * In TAP mode the precharge owns the splash lifetime;
                     * a keypress just flags "skip" so the main-loop check
                     * dismisses at the next iteration (once warmup is
                     * done -- before that the game isn't yet at SplashWait
                     * and skipping would lose the first input). */
                    if (g_splash_active) {
                        if (ev.key.repeat) break;
                        if (g_boot_mode == BOOT_TAP) g_splash_user_skip = 1;
                        else                       g_splash_active   = 0;
                        break;
                    }
                    /* Language menu: cursor / WASD navigates the 3
                     * options, ENTER / SPACE / Ctrl confirms. Everything
                     * else is consumed so the game underneath doesn't see it. */
                    if (g_lang_menu_active) {
                        if (ev.key.repeat) break;
                        const int dir_prev =
                            (k == SDLK_UP    || k == SDLK_LEFT ||
                             k == SDLK_w     || k == SDLK_a);
                        const int dir_next =
                            (k == SDLK_DOWN  || k == SDLK_RIGHT ||
                             k == SDLK_s     || k == SDLK_d);
                        const int is_confirm =
                            (k == SDLK_RETURN || k == SDLK_KP_ENTER ||
                             k == SDLK_SPACE  ||
                             k == SDLK_LCTRL  || k == SDLK_RCTRL);
                        if (dir_prev && g_lang_selected > 0) {
                            g_lang_selected--;
                            lang_menu_refresh();
                        } else if (dir_next && g_lang_selected < LANG_MENU_OPTIONS - 1) {
                            g_lang_selected++;
                            lang_menu_refresh();
                        } else if (is_confirm) {
                            lang_menu_confirm();
                        }
                        break;
                    }
                    /* Story page advance: any key during the narration
                     * jumps to the next page (or ends it). Consume so
                     * the keypress doesn't also reach the game. */
                    if (g_story_page >= 0) {
                        if (ev.key.repeat) break;
                        story_show_page(g_story_page + 1);
                        break;
                    }
                    /* Help dismissal: any keyboard key closes the help
                     * overlay and is consumed (so the closing keypress
                     * doesn't also fire its normal action). Ignore OS
                     * auto-repeat so a held key doesn't insta-close. */
                    if (video_help_visible(g_video)) {
                        if (ev.key.repeat) break;
                        close_help();
                        break;
                    }
                    if (k == SDLK_F1) {
                        if (ev.key.repeat) break;
                        /* Open help. Closing is handled above (any key). */
                        if (!g_paused) {
                            toggle_pause();
                            g_help_owns_pause = 1;
                        }
                        video_set_help(g_video, HELP_TEXT);
                        break;
                    }
                    if (k == SDLK_ESCAPE) {
                        if (ev.key.repeat) break;
                        /* ESC has two roles, multiplexed on game state:
                         *   1. Not paused -> pause + show "ESC AGAIN
                         *      TO EXIT" warning for 2 s.
                         *   2. Paused, within the 2 s window -> quit.
                         *   3. Paused, window expired -> resume
                         *      (normal toggle).
                         * SDLK_p was the previous pause binding but
                         * conflicts with QAOP-right; ESC absorbs both
                         * the pause and the two-step exit. */
                        static Uint32 esc_confirm_until = 0;
                        const Uint32  ESC_CONFIRM_MS    = 2000;
                        const Uint32 now = SDL_GetTicks();
                        if (g_paused && now <= esc_confirm_until) {
                            g_running = 0;          /* second ESC -> quit */
                        } else if (!g_paused) {
                            toggle_pause();
                            esc_confirm_until = now + ESC_CONFIRM_MS;
                            video_show_msg(g_video, "ESC AGAIN TO EXIT",
                                           (int)ESC_CONFIRM_MS);
                        } else {
                            toggle_pause();       /* expired -> resume */
                        }
                        break;
                    }
                    if (k == SDLK_F2) {
                        video_set_crt(g_video, !video_crt(g_video));
                        fprintf(stderr, "[tharkys] CRT %s\n",
                                video_crt(g_video) ? "on" : "off");
                        break;
                    }
                    if (k == SDLK_F3) {
                        if (ev.key.repeat) break;
                        g_border_mode = (g_border_mode + 1) % BORDER_MODE_COUNT;
                        video_set_zoom(g_video, BORDER_ZOOM[g_border_mode]);
                        video_show_msg(g_video, BORDER_NAME[g_border_mode], 1500);
                        fprintf(stderr, "[tharkys] %s (zoom %.3f)\n",
                                BORDER_NAME[g_border_mode], BORDER_ZOOM[g_border_mode]);
                        break;
                    }
                    if (k == SDLK_F11 ||
                        (k == SDLK_RETURN && (ev.key.keysym.mod & KMOD_ALT))) {
                        g_fullscreen = !g_fullscreen;
                        SDL_SetWindowFullscreen(g_win,
                            g_fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
                        break;
                    }
                    /* Swallow input while paused so games that read keys
                     * directly (QAOP, 1-5) don't accumulate stuck presses. */
                    if (g_paused) break;
                    /* Post-story release gate: if we just flipped past
                     * the story (skip or last page), the press still on
                     * the keyboard doesn't count -- only the NEXT
                     * fresh press will reach the emulator. */
                    if (g_input_needs_release) break;
                    int zx = input_sdl_to_zx(k);
                    if (zx) emu_key_down(g_emu, zx);
                } break;

                case SDL_KEYUP: {
                    int zx = input_sdl_to_zx(ev.key.keysym.sym);
                    if (zx) emu_key_up(g_emu, zx);
                } break;

                case SDL_CONTROLLERDEVICEADDED:
                case SDL_CONTROLLERDEVICEREMOVED:
                    gamepad_handle_event(g_pad, &ev);
                    break;

                case SDL_CONTROLLERBUTTONDOWN:
                    if (g_splash_active) {
                        if (g_boot_mode == BOOT_TAP) g_splash_user_skip = 1;
                        else                       g_splash_active   = 0;
                        break;
                    }
                    if (g_lang_menu_active) {
                        const uint8_t b = ev.cbutton.button;
                        if ((b == SDL_CONTROLLER_BUTTON_DPAD_UP ||
                             b == SDL_CONTROLLER_BUTTON_DPAD_LEFT) &&
                            g_lang_selected > 0) {
                            g_lang_selected--;
                            lang_menu_refresh();
                        } else if ((b == SDL_CONTROLLER_BUTTON_DPAD_DOWN ||
                                    b == SDL_CONTROLLER_BUTTON_DPAD_RIGHT) &&
                                   g_lang_selected < LANG_MENU_OPTIONS - 1) {
                            g_lang_selected++;
                            lang_menu_refresh();
                        } else if (b == SDL_CONTROLLER_BUTTON_A ||
                                   b == SDL_CONTROLLER_BUTTON_B ||
                                   b == SDL_CONTROLLER_BUTTON_X ||
                                   b == SDL_CONTROLLER_BUTTON_Y ||
                                   b == SDL_CONTROLLER_BUTTON_START) {
                            lang_menu_confirm();
                        }
                        break;
                    }
                    if (g_story_page >= 0) {
                        story_show_page(g_story_page + 1);
                        break;
                    }
                    /* Help dismissal: any gamepad button closes help. */
                    if (video_help_visible(g_video)) {
                        close_help();
                        break;
                    }
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_START) {
                        toggle_pause();
                    } else if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK ||
                               ev.cbutton.button == SDL_CONTROLLER_BUTTON_MISC1) {
                        /* Select/View/Back/Share -> minimap (in-game ZX key
                         * is 'M' despite minimap.asm's "tecla I" comment;
                         * the handler actually reads port $7FFE bit 2 = M). */
                        if (!g_paused) emu_key_down(g_emu, 'm');
                    }
                    break;

                case SDL_CONTROLLERBUTTONUP:
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK ||
                        ev.cbutton.button == SDL_CONTROLLER_BUTTON_MISC1) {
                        emu_key_up(g_emu, 'm');
                    }
                    break;

                default: break;
            }
        }

        /* TAP precharge.
         *
         * Spectaculator's "fast load" UX: the user opens a .tap and
         * within a beat the game's own splash with its blinking
         * "press a key" icons is on screen -- no ROM menu, no BASIC
         * LOADER list, no SCREEN$ paint visible. We reproduce that by
         * g_running the emulator at turbo speed under the wrapper splash
         * (the same bg-257 image the game itself paints) and faking
         * the keyboard:
         *
         *   1. emu_load_tap() already paged in ROM 1 and reset the Z80,
         *      so we boot straight into the 48K BASIC interpreter (no
         *      128K menu visible). Wait ~80 frames for the "(C) 1982
         *      Sinclair Research" copyright and K-cursor to appear.
         *   2. Autotype `J "" ENTER`. In K-cursor mode the J key
         *      expands to the LOAD keyword; the two SS+P " glyphs and
         *      ENTER complete `LOAD ""`. The interpreter calls
         *      LD-BYTES at ROM 1 $0556 -> our trap streams the .tap
         *      blocks straight into RAM with no audio decoding.
         *   3. The BASIC LOADER on the .tap then runs CLEAR + LOAD ""
         *      SCREEN$ + LOAD "" CODE + RANDOMIZE USR; all of those
         *      LOADs go through the same trap, so the only wall-clock
         *      time is what the BASIC interpreter needs to walk its
         *      bytecode.
         *
         * 400 frames @ 50 Hz of emulated time covers everything with
         * margin; at full host speed that's a few hundred milliseconds
         * of wall clock, so the wrapper splash flashes briefly and is
         * replaced by the same bg-257 already painted by the game --
         * the only visible change is the icons fading in.
         *
         * Audio is muted during the run because the ROM beeper would
         * otherwise dump several seconds of "key beep" into the output
         * queue in one host frame. */
        if (g_boot_mode == BOOT_TAP && g_splash_active) {
            /* Scripted keypress sequence relative to tap_boot_frame.
             * "key" follows chips/zx conventions: ASCII for printable
             * keys, 0x0D for ENTER, 0x22 for SS+P (the " glyph). */
            typedef struct { int press_at, release_at, key; } scripted_key_t;
            static const scripted_key_t SCRIPT[] = {
                /* 48 BASIC boot takes ~100-150 frames to fully settle
                 * into K-cursor input. Each keypress is held for
                 * ~12 frames (~240 ms) with a 18-frame gap before
                 * the next press so the BASIC editor's debounce sees
                 * each one as a discrete event. The double " is the
                 * trickiest: SS+P twice in quick succession can be
                 * collapsed by chips' kbd matrix if the second press
                 * starts while the first is still held; the gap keeps
                 * them distinct. */
                { 150, 162, 'j'  },  /* J in K-cursor -> LOAD keyword */
                { 180, 192, '"'  },  /* SS+P -> opening quote          */
                { 210, 222, '"'  },  /* SS+P -> closing quote          */
                { 240, 252, 0x0D },  /* Enter -> LD-BYTES via $0556    */
            };
            static int tap_boot_frame = 0;
            const int  TAP_PRECHARGE_FRAMES = 500;
            const int  CHUNK                = 40;   /* per wall-clock frame */
            const int  N_SCRIPT             = (int)(sizeof SCRIPT / sizeof SCRIPT[0]);

            /* Two-phase precharge:
             *   PHASE TURBO: audio muted, CHUNK g_emu frames per wall frame
             *                so the BASIC loader's CPU time compresses into
             *                a fraction of a second. Runs until LD-BYTES
             *                drains the last TAP block.
             *   PHASE WARMUP: audio LIVE, ONE g_emu frame per wall frame,
             *                splash wrapper still visible. The game finishes
             *                RANDOMIZE USR, installs the music IRQ, and
             *                reaches SplashWait -- so by the time we lift
             *                the wrapper splash, the first user input is
             *                actually being polled, and the music's first
             *                note plays into a live audio queue (not muted).
             *
             * Without warmup, splash dismiss races the game's init: user
             * presses gamepad on the game's splash â†’ game isn't yet in
             * SplashWait â†’ input lost. Warmup window of ~50 frames (= 1 s
             * wall-clock) is generous enough for both. */
            static int    tape_done_frame   = -1;
            const int     WARMUP_FRAMES     = 50;
            /* Three-card splash. Each presenter card runs for
             * PRESENTER_MS while the AY stays muted and the g_emu is
             * paused (after TURBO loads the TAP). The bg-257 final
             * card runs for the remainder, calibrated so EndGame
             * plays through the end of bar 3 (~3 s of music after
             * a ~500 ms boot delay = 3.5 s). Skip with any input. */
            const Uint64  PRESENTER_MS      = 3000;
            const Uint64  BG257_MS          = 4500;
            const Uint64  MIN_SPLASH_MS     = 2 * PRESENTER_MS + BG257_MS;
            if (g_splash_start_ms == 0) {
                g_splash_start_ms      = SDL_GetTicks64();
                g_splash_card          = 0;
                g_splash_card_start_ms = g_splash_start_ms;
            }

            /* During cards 0 and 1 (presenter cards): turbo precharge
             * the TAP, then FREEZE the emulator. The game is paused
             * mid-BASIC just after the last LOAD "" -- RANDOMIZE USR
             * hasn't run yet, so StartMusic hasn't run, so no notes
             * have been "played silently" past the unmute. When card 2
             * (bg-257) starts we unmute and resume; the music driver
             * lights up clean and its very first note coincides with
             * the bg-257 reveal.
             *
             * During card 2: g_emu runs at native speed with audio live. */
            if (g_splash_card < 2) {
                if (tape_done_frame < 0) {
                    int hit_end = 0;
                    for (int i = 0; i < CHUNK && tap_boot_frame < TAP_PRECHARGE_FRAMES; i++) {
                        for (int s = 0; s < N_SCRIPT; s++) {
                            if (tap_boot_frame == SCRIPT[s].press_at)
                                emu_key_down(g_emu, SCRIPT[s].key);
                            if (tap_boot_frame == SCRIPT[s].release_at)
                                emu_key_up  (g_emu, SCRIPT[s].key);
                        }
                        emu_run_frame(g_emu);
                        tap_boot_frame++;
                        if (emu_tape_at_end(g_emu)) { hit_end = 1; break; }
                    }
                    if (hit_end) {
                        for (int s = 0; s < N_SCRIPT; s++) {
                            if (SCRIPT[s].press_at   <  tap_boot_frame &&
                                SCRIPT[s].release_at >= tap_boot_frame) {
                                emu_key_up(g_emu, SCRIPT[s].key);
                            }
                        }
                        tape_done_frame = tap_boot_frame;
                        fprintf(stderr, "[tharkys] TAP consumed at %d frames; g_emu paused for card 0\n",
                                tap_boot_frame);
                    } else if (tap_boot_frame >= TAP_PRECHARGE_FRAMES) {
                        /* Timeout fallback. */
                        g_splash_active = 0;
                        g_audio_muted   = 0;
                        emu_audio_warmup_reset(g_emu);
                        emu_set_audio_processing(g_emu, true);
                        if (g_audio) SDL_ClearQueuedAudio(g_audio);
                        fprintf(stderr, "[tharkys] TAP precharge timeout at %d frames\n",
                                tap_boot_frame);
                    }
                }
                /* else: tape done, g_emu frozen until card 1. */
            } else {
                /* Card 2 (bg-257): g_emu running normally, audio live. */
#ifdef __EMSCRIPTEN__
                emu_step_for_audio();
#else
                emu_run_frame(g_emu);
#endif
                tap_boot_frame++;
            }

            /* Live-poll the controllers: any keyboard scancode pressed
             * OR any gamepad button / stick past its deadzone counts
             * as "skip this splash card". Same release-gate as the
             * story pages: after a card transition we wait for the
             * user to FULLY RELEASE everything before the next press
             * counts, so one press doesn't blast through all three
             * cards in three frames. */
            {
                const Uint8 *kbd = SDL_GetKeyboardState(NULL);
                int any_kbd = 0;
                for (int i = 0; i < SDL_NUM_SCANCODES; i++) {
                    if (kbd[i]) { any_kbd = 1; break; }
                }
                const int any_input = any_kbd || gamepad_any_input(g_pad);
                if (g_input_needs_release) {
                    /* Don't accept a new skip until everything is at rest. */
                    if (!any_input) g_input_needs_release = 0;
                } else if (any_input) {
                    g_splash_user_skip = 1;
                }
            }

            /* Card state machine:
             *   0,1 -> stay muted, g_emu paused (only if can_advance).
             *   1 -> 2 transition is where we unmute + resume g_emu.
             *   2 -> dismiss is where we hand off to the language menu. */
            const Uint64 now_ms        = SDL_GetTicks64();
            const Uint64 card_elapsed  = now_ms - g_splash_card_start_ms;
            const Uint64 splash_elapsed = now_ms - g_splash_start_ms;
            const int can_advance      = (tape_done_frame >= 0);
            if (g_splash_card < 2) {
                /* Presenter cards: keep audio muted + ayumi frozen. */
                g_audio_muted = 1;
                emu_set_audio_processing(g_emu, false);
                if (can_advance &&
                    (card_elapsed >= PRESENTER_MS || g_splash_user_skip)) {
                    /* Always gate the next card behind a release. Even
                     * if the transition was timer-driven, any input
                     * the user happened to be holding shouldn't count
                     * as "skip" for the next card -- they have to
                     * release and press fresh. Keeps the sequence
                     * strictly one-press-per-card. */
                    g_input_needs_release  = 1;
                    g_splash_card++;
                    g_splash_card_start_ms = now_ms;
                    g_splash_user_skip     = 0;
                    if (g_splash_card == 2) {
                        /* Crossing into bg-257: unmute and resume the
                         * g_emu so the game's StartMusic kicks in here. */
                        g_audio_muted           = 0;
                        emu_set_audio_processing(g_emu, true);
                        g_audio_fade_in_samples = g_audio_freq / 100;
                        if (g_audio) SDL_ClearQueuedAudio(g_audio);
                        fprintf(stderr,
                            "[tharkys] splash card 1->2 (bg-257 + audio on)\n");
                    } else {
                        fprintf(stderr,
                            "[tharkys] splash card %d->%d\n",
                            g_splash_card - 1, g_splash_card);
                    }
                }
            } else {
                /* Card 2 (bg-257): dismiss after MIN_SPLASH_MS or skip,
                 * and only once the game has had WARMUP_FRAMES to
                 * reach SplashWait. */
                const int warmup_elapsed = tap_boot_frame - tape_done_frame;
                if (can_advance &&
                    warmup_elapsed >= WARMUP_FRAMES &&
                    (splash_elapsed >= MIN_SPLASH_MS || g_splash_user_skip)) {
                    /* Same rule: always gate the lang menu's first
                     * input behind a release so a held key doesn't
                     * both dismiss the splash and confirm a menu
                     * choice in the same frame. */
                    g_input_needs_release = 1;
                    g_splash_active       = 0;
                    fprintf(stderr, "[tharkys] splash dismissed (%llu ms)\n",
                            (unsigned long long)splash_elapsed);
                    SDL_EventState(SDL_CONTROLLERAXISMOTION, SDL_ENABLE);
                    g_lang_menu_active = 1;
                    g_lang_selected    = 0;
                    lang_menu_refresh();
#ifdef __EMSCRIPTEN__
                    /* MVP web: lang menu and story aren't rendered (text
                     * overlays are stubbed in video_web.c), so confirm
                     * the "skip story" option immediately and hand
                     * control straight to the game's SplashWait. */
                    g_lang_selected = 2;  /* "Skip story" */
                    lang_menu_confirm();
#endif
                }
            }
        } else if (!g_splash_active && !g_paused) {
            /* During the language menu and the story overlay we want
             * the music to keep playing (so emu_run_frame stays) but
             * user input is for the wrapper UI, not for the in-game
             * SplashWait -- so the joystick mask isn't forwarded. */
            if (g_story_page < 0 && !g_lang_menu_active) {
                /* Clear the post-story release gate as soon as the user
                 * actually releases every input. Until then we forward
                 * a zero mask so the press that triggered skip / last-
                 * page-flip doesn't bleed into the game's SplashWait. */
                if (g_input_needs_release) {
                    int any_kbd = 0;
                    const Uint8 *kbd = SDL_GetKeyboardState(NULL);
                    for (int i = 0; i < SDL_NUM_SCANCODES; i++) {
                        if (kbd[i]) { any_kbd = 1; break; }
                    }
                    if (!any_kbd && !gamepad_any_input(g_pad)) {
                        g_input_needs_release = 0;
                    }
                }
                /* Merge keyboard (WASD / arrows / Ctrl) and gamepad masks
                 * into a single Kempston state so the game reads them as
                 * one stick on port $1F. */
                const uint8_t mask = g_input_needs_release
                    ? 0
                    : (gamepad_poll(g_pad) | input_kbd_joystick_mask());
                emu_joystick(g_emu, mask);
            }
#ifdef __EMSCRIPTEN__
            emu_step_for_audio();
#else
            emu_run_frame(g_emu);
#endif

            /* Analog-stick edge detection for the language menu. Only
             * the LEFT STICK here -- the D-g_pad and keyboard arrows are
             * already handled by the KEYDOWN / CONTROLLERBUTTONDOWN
             * switches above, and including them in the poll would
             * double-step the cursor on every press. */
            if (g_lang_menu_active) {
                static int stick_armed = 1;
                const uint8_t jmask = gamepad_poll_stick_only(g_pad);
                const int up    = (jmask & EMU_JOY_UP)   != 0;
                const int down  = (jmask & EMU_JOY_DOWN) != 0;
                const int left  = (jmask & EMU_JOY_LEFT) != 0;
                const int right = (jmask & EMU_JOY_RIGHT)!= 0;
                const int prev  = up   || left;
                const int next  = down || right;
                if ((prev || next) && stick_armed) {
                    if (prev && g_lang_selected > 0) {
                        g_lang_selected--;
                        lang_menu_refresh();
                    } else if (next && g_lang_selected < LANG_MENU_OPTIONS - 1) {
                        g_lang_selected++;
                        lang_menu_refresh();
                    }
                    stick_armed = 0;
                } else if (!prev && !next) {
                    stick_armed = 1;
                }
            }

            /* No auto-advance, no blink to drive: the page sits there
             * until the user presses, with the game's own animated
             * icons doing the "press to continue" affordance. */
        }

        if (g_splash_active) {
            /* Three-card splash:
             *   0 = "JayDroid / Presents"             (3 s, muted, g_emu paused after TAP)
             *   1 = "A Sinclair ZX Spectrum 128 K /
             *        computer game"                   (3 s, muted, g_emu paused)
             *   2 = bg-257 title                      (~4 s, audio live, g_emu resumes
             *                                          so EndGame plays through ~bar 3) */
            if (g_splash_card == 0) {
                video_upload_centered_text(g_video,
                    "JayDroid\n\n\nPresents");
            } else if (g_splash_card == 1) {
                video_upload_centered_text(g_video,
                    "A Sinclair ZX Spectrum 128 K\n\n\ncomputer game");
            } else {
                video_upload_splash(g_video, splash_pixels, splash_attrs);
            }
        } else {
            /* Always upload the full visible area; F3 border crop is
             * applied by the fragment shader via a UV inset, not by
             * resizing the texture. Keeps the CRT effects calibrated
             * against the same source-pixel grid in every mode. */
            const emu_display_t disp = emu_display(g_emu);
            video_upload(g_video, disp.fb, disp.fb_width,
                         disp.vis_width, disp.vis_height, disp.palette);
        }
        video_present(g_video);

        /* Pacing.
         *
         * When the emulator is producing audio (game g_running, audio
         * device open), use the audio queue depth as the master clock:
         * sleep until the queue drains below AUDIO_TARGET_QUEUE_MS, then
         * run one more frame. This locks emulation to the audio device's
         * crystal clock instead of SDL_Delay's wall-clock guess. Result:
         * the queue oscillates inside a tight band and never trips the
         * drop cap, so music stays clean indefinitely instead of
         * deteriorating with every accumulated drift dropout.
         *
         * Fall back to fixed-step wall-clock pacing in the cases where
         * no audio is being produced (splash, paused, audio device
         * unavailable) -- otherwise the queue stays empty forever and
         * the wait loop is a no-op that spins the CPU.
         *
         * The 40 ms safety bound on the audio wait keeps a stalled audio
         * device (eg. OS sleep / device unplug) from freezing the
         * wrapper -- if we waited longer than that, something's wrong
         * and the next frame will recover. */
#ifndef __EMSCRIPTEN__
        /* Host-side pacing only runs on desktop. The browser drives the
         * 50 Hz rate via emscripten_set_main_loop(..., 50, ...) and we
         * mustn't ever block the main thread with SDL_Delay -- doing so
         * freezes the page. */
        if (g_audio && !g_splash_active && !g_paused && !g_no_audio_pace) {
            const Uint32 target_bytes = (Uint32)(g_audio_freq * sizeof(float) *
                                                 AUDIO_TARGET_QUEUE_MS / 1000);
            const Uint64 wait_start = SDL_GetTicks64();
            while (SDL_GetQueuedAudioSize(g_audio) > target_bytes) {
                SDL_Delay(1);
                if (SDL_GetTicks64() - wait_start > 40) break;
            }
            g_next_tick = SDL_GetTicks64(); /* keep fallback baseline fresh */
        } else {
            g_next_tick += FRAME_MS;
            const Uint64 now = SDL_GetTicks64();
            if (now < g_next_tick) SDL_Delay((Uint32)(g_next_tick - now));
            else                   g_next_tick = now;
        }
#endif
}
