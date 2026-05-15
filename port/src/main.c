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

static SDL_AudioDeviceID g_audio       = 0;
static int               g_audio_freq  = 44100;
static int               g_paused      = 0;

/* Toggle pause from any source (keyboard, gamepad). Freezes the emulator
 * and silences audio; the last rendered frame keeps showing because chips'
 * framebuffer doesn't change when zx_exec isn't called.
 *
 * On pause: drop the queued audio so resume starts fresh instead of
 * replaying ~50 ms of stale samples (SDL_PauseAudioDevice alone would
 * keep the queue, causing a brief snippet from before the pause to play
 * on resume). */
static video_t *g_video = NULL;  /* set in main() so toggle_pause can update it */

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

/* Cap the SDL audio queue to ~50 ms (≈2.5 PAL frames). Without this,
 * any drift between host SDL_Delay pacing and the SDL audio clock
 * (typically a fraction of a percent on Windows) accumulates into the
 * queue and the user hears audio progressively lagging behind video
 * until the lag is seconds long. Dropping ~20 ms once in a while is
 * essentially inaudible vs an ever-growing delay. */
#define AUDIO_MAX_QUEUE_MS 50

static void audio_push(const float *samples, int num_samples, void *user) {
    (void)user;
    if (!g_audio) return;
    const Uint32 cap_bytes = (Uint32)(g_audio_freq * sizeof(float) *
                                      AUDIO_MAX_QUEUE_MS / 1000);
    if (SDL_GetQueuedAudioSize(g_audio) > cap_bytes) {
        return; /* queue already too deep, drop this chunk */
    }
    SDL_QueueAudio(g_audio, samples, (Uint32)(num_samples * sizeof(float)));
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
    int         start_fullscreen = 0;
    int         start_windowed   = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--sna") == 0 && i + 1 < argc) {
            sna_path = argv[++i];
        } else if (strcmp(argv[i], "--fullscreen") == 0) {
            start_fullscreen = 1;
        } else if (strcmp(argv[i], "--windowed") == 0) {
            start_windowed = 1;
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

    SDL_Window *win = SDL_CreateWindow(
        "Tharkys the Knight",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_W, WIN_H,
        win_flags
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
    g_video = vid;

    /* --- Audio: 44.1 kHz mono float32, queue mode ------------------- */
    SDL_AudioSpec want = {0}, have = {0};
    want.freq     = 44100;
    want.format   = AUDIO_F32SYS;
    want.channels = 1;
    want.samples  = 1024;
    want.callback = NULL;
    g_audio = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (g_audio) {
        g_audio_freq = have.freq;
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

    /* Now that the ROMs are loaded, swap the pause label's font from
     * the hardcoded fallback to the real ZX Spectrum 8x8 character font
     * sitting at $3D00 of the 48K-compat ROM. */
    video_set_pause_font(vid, emu_spectrum_font());

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

    fprintf(stderr, "[tharkys] running. Move: QAOP/WASD/arrows. Fire: Space/Ctrl. P=pause, F2=CRT, F11=fullscreen, Esc=quit.\n");

    /* --- Main loop --------------------------------------------------- */
    Uint64 next_tick   = SDL_GetTicks64();
    int    running     = 1;
    int    fullscreen  = start_fullscreen;

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
                    if (k == SDLK_p)      { toggle_pause();   break; }
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
                    /* Swallow input while paused so games that read keys
                     * directly (QAOP, 1-5) don't accumulate stuck presses. */
                    if (g_paused) break;
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

                case SDL_CONTROLLERBUTTONDOWN:
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_START) {
                        toggle_pause();
                    } else if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK ||
                               ev.cbutton.button == SDL_CONTROLLER_BUTTON_MISC1) {
                        /* Select/View/Back/Share -> minimap (in-game ZX key
                         * is 'M' despite minimap.asm's "tecla I" comment;
                         * the handler actually reads port $7FFE bit 2 = M). */
                        if (!g_paused) emu_key_down(emu, 'm');
                    }
                    break;

                case SDL_CONTROLLERBUTTONUP:
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK ||
                        ev.cbutton.button == SDL_CONTROLLER_BUTTON_MISC1) {
                        emu_key_up(emu, 'm');
                    }
                    break;

                default: break;
            }
        }

        if (!g_paused) {
            /* Merge keyboard (WASD / arrows / Ctrl) and gamepad masks
             * into a single Kempston state so the game reads them as
             * one stick on port $1F. */
            emu_joystick(emu, gamepad_poll(pad) | input_kbd_joystick_mask());
            emu_run_frame(emu);
        }

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
