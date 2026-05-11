/*
 * Tharkys the Knight - desktop wrapper, main entry.
 *
 * Phase 1: boots the embedded juego.sna inside a chips/zx 128K core,
 * displays the framebuffer scaled to the window, pipes the AY-3-8912
 * audio to SDL2, and wires the host keyboard into the emulated matrix.
 *
 * --sna <path> swaps the embedded blob for an external SNA file so the
 * dev iteration loop is just `make` (no wrapper recompile required).
 */

#include <SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "emu.h"
#include "input.h"
#include "juego_sna.h"

/* Visible area exposed by chips/zx (screen + borders). */
#define VIS_W       320
#define VIS_H       256
#define WIN_SCALE   2
#define WIN_W       (VIS_W * WIN_SCALE)
#define WIN_H       (VIS_H * WIN_SCALE)

/* PAL 128K Spectrum runs at ~50.08 Hz. 20 ms is the host-side budget. */
#define FRAME_MS    20

static SDL_AudioDeviceID g_audio = 0;

/* chips fires this from the AY/beeper mixer; forward straight into SDL. */
static void audio_push(const float *samples, int num_samples, void *user) {
    (void)user;
    if (g_audio) {
        SDL_QueueAudio(g_audio, samples, (Uint32)(num_samples * sizeof(float)));
    }
}

/* Slurp a file into a heap buffer; used by --sna. */
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

/* Convert one frame of chips' palette-indexed fb (1 byte/px, 512 stride)
 * into the RGBA streaming texture (4 bytes/px, host-allocated stride). */
static void blit_framebuffer(SDL_Texture *tex, const emu_display_t *d) {
    void *pixels = NULL;
    int   pitch  = 0;
    if (SDL_LockTexture(tex, NULL, &pixels, &pitch) != 0) return;

    const uint8_t *src = d->fb;
    uint32_t *dst      = (uint32_t *)pixels;
    const int  dst_stride = pitch / 4;

    for (int y = 0; y < d->vis_height; y++) {
        const uint8_t *src_row = src + (size_t)y * d->fb_width;
        uint32_t      *dst_row = dst + (size_t)y * dst_stride;
        for (int x = 0; x < d->vis_width; x++) {
            dst_row[x] = d->palette[src_row[x] & 0x0F];
        }
    }
    SDL_UnlockTexture(tex);
}

int main(int argc, char *argv[]) {
    /* --- args -------------------------------------------------------- */
    const char *sna_path = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--sna") == 0 && i + 1 < argc) {
            sna_path = argv[++i];
        }
    }

    /* --- SDL --------------------------------------------------------- */
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER) != 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return EXIT_FAILURE;
    }

    SDL_Window *win = SDL_CreateWindow(
        "Tharkys the Knight",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_W, WIN_H,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );
    if (!win) {
        fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        return EXIT_FAILURE;
    }

    SDL_Renderer *renderer = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer) {
        fprintf(stderr, "SDL_CreateRenderer: %s\n", SDL_GetError());
        SDL_DestroyWindow(win);
        SDL_Quit();
        return EXIT_FAILURE;
    }
    SDL_RenderSetLogicalSize(renderer, VIS_W, VIS_H);
    SDL_RenderSetIntegerScale(renderer, SDL_TRUE);

    SDL_Texture *tex = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_STREAMING,
        VIS_W, VIS_H
    );
    if (!tex) {
        fprintf(stderr, "SDL_CreateTexture: %s\n", SDL_GetError());
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(win);
        SDL_Quit();
        return EXIT_FAILURE;
    }

    /* --- Audio: 44.1 kHz mono float32, queue mode ------------------- */
    SDL_AudioSpec want = {0}, have = {0};
    want.freq     = 44100;
    want.format   = AUDIO_F32SYS;
    want.channels = 1;
    want.samples  = 1024;
    want.callback = NULL;     /* NULL => queue mode (we push from chips) */
    g_audio = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (g_audio) {
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
    emu_t *emu = emu_create(&emu_desc);
    if (!emu) {
        fprintf(stderr, "emu_create failed\n");
        return EXIT_FAILURE;
    }

    /* Pick the SNA: --sna wins, else the blob baked in at build time. */
    const uint8_t *sna_data = juego_sna;
    size_t         sna_size = juego_sna_len;
    uint8_t       *sna_loaded = NULL;
    if (sna_path) {
        sna_loaded = load_file(sna_path, &sna_size);
        if (!sna_loaded) {
            fprintf(stderr, "Cannot read SNA file: %s\n", sna_path);
            return EXIT_FAILURE;
        }
        sna_data = sna_loaded;
        fprintf(stderr, "[tharkys] loading external SNA: %s (%zu bytes)\n",
                sna_path, sna_size);
    } else {
        fprintf(stderr, "[tharkys] using embedded SNA (%zu bytes)\n", sna_size);
    }

    if (!emu_load_sna(emu, sna_data, sna_size)) {
        fprintf(stderr, "emu_load_sna: rejected blob (size=%zu; expected 131103 for 128K)\n",
                sna_size);
        return EXIT_FAILURE;
    }
    free(sna_loaded);

    fprintf(stderr, "[tharkys] running. Esc to quit, F11 fullscreen.\n");

    /* --- Main loop --------------------------------------------------- */
    Uint64 next_tick = SDL_GetTicks64();
    int    running    = 1;
    int    fullscreen = 0;

    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            switch (ev.type) {
                case SDL_QUIT:
                    running = 0;
                    break;

                case SDL_KEYDOWN: {
                    SDL_Keycode k = ev.key.keysym.sym;
                    if (k == SDLK_ESCAPE) { running = 0; break; }
                    if (k == SDLK_F11 ||
                        (k == SDLK_RETURN && (ev.key.keysym.mod & KMOD_ALT))) {
                        fullscreen = !fullscreen;
                        SDL_SetWindowFullscreen(win,
                            fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
                        break;
                    }
                    int zx = input_sdl_to_zx(k);
                    if (zx) emu_key_down(emu, zx);
                } break;

                case SDL_KEYUP: {
                    int zx = input_sdl_to_zx(ev.key.keysym.sym);
                    if (zx) emu_key_up(emu, zx);
                } break;

                default: break;
            }
        }

        emu_run_frame(emu);

        const emu_display_t disp = emu_display(emu);
        blit_framebuffer(tex, &disp);

        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0xFF);
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, tex, NULL, NULL);
        SDL_RenderPresent(renderer);

        /* 50 Hz pacing (catch up if we fell behind). */
        next_tick += FRAME_MS;
        const Uint64 now = SDL_GetTicks64();
        if (now < next_tick) SDL_Delay((Uint32)(next_tick - now));
        else                 next_tick = now;
    }

    /* --- Cleanup ----------------------------------------------------- */
    emu_destroy(emu);
    if (g_audio) SDL_CloseAudioDevice(g_audio);
    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return EXIT_SUCCESS;
}
