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

#include "emu.h"
#include "gamepad.h"
#include "input.h"
#include "video.h"
#include "juego_sna.h"

/* Visible area emitted by chips/zx (screen + borders). */
#define VIS_W       320
#define VIS_H       256
#define WIN_SCALE   2
#define WIN_W       (VIS_W * WIN_SCALE)
#define WIN_H       (VIS_H * WIN_SCALE)

/* PAL 128K Spectrum runs at ~50.08 Hz; 20 ms is the host-side budget. */
#define FRAME_MS    20

static SDL_AudioDeviceID g_audio = 0;

static void audio_push(const float *samples, int num_samples, void *user) {
    (void)user;
    if (g_audio) {
        SDL_QueueAudio(g_audio, samples, (Uint32)(num_samples * sizeof(float)));
    }
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
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_OPENGL
    );
    if (!win) {
        fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        return EXIT_FAILURE;
    }
    SDL_SetWindowMinimumSize(win, VIS_W, VIS_H);

    /* --- Video (OpenGL + CRT shader) -------------------------------- */
    video_t *vid = video_create(win);
    if (!vid) {
        fprintf(stderr, "video_create failed\n");
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
    want.callback = NULL;
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

    /* --- Gamepad ---------------------------------------------------- */
    gamepad_t *pad = gamepad_create();
    if (!pad) {
        fprintf(stderr, "gamepad_create failed (continuing without gamepad)\n");
    }

    fprintf(stderr, "[tharkys] running. Esc=quit, F2=CRT toggle, F11=fullscreen.\n");

    /* --- Main loop --------------------------------------------------- */
    Uint64 next_tick   = SDL_GetTicks64();
    int    running     = 1;
    int    fullscreen  = 0;

    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            switch (ev.type) {
                case SDL_QUIT:
                    running = 0;
                    break;

                case SDL_WINDOWEVENT:
                    if (ev.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                        video_resize(vid, ev.window.data1, ev.window.data2);
                    }
                    break;

                case SDL_KEYDOWN: {
                    SDL_Keycode k = ev.key.keysym.sym;
                    if (k == SDLK_ESCAPE) { running = 0; break; }
                    if (k == SDLK_F2) {
                        video_set_crt(vid, !video_crt(vid));
                        fprintf(stderr, "[tharkys] CRT %s\n",
                                video_crt(vid) ? "on" : "off");
                        break;
                    }
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

                case SDL_CONTROLLERDEVICEADDED:
                case SDL_CONTROLLERDEVICEREMOVED:
                    gamepad_handle_event(pad, &ev);
                    break;

                default: break;
            }
        }

        emu_joystick(emu, gamepad_poll(pad));
        emu_run_frame(emu);

        const emu_display_t disp = emu_display(emu);
        video_upload(vid, disp.fb, disp.fb_width,
                     disp.vis_width, disp.vis_height, disp.palette);
        video_present(vid);

        /* 50 Hz pacing (catch up if we fell behind). */
        next_tick += FRAME_MS;
        const Uint64 now = SDL_GetTicks64();
        if (now < next_tick) SDL_Delay((Uint32)(next_tick - now));
        else                 next_tick = now;
    }

    /* --- Cleanup ----------------------------------------------------- */
    gamepad_destroy(pad);
    emu_destroy(emu);
    if (g_audio) SDL_CloseAudioDevice(g_audio);
    video_destroy(vid);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return EXIT_SUCCESS;
}
