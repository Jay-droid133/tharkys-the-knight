/*
 * Tharkys the Knight - desktop wrapper
 *
 * Phase 0 scaffold: just verifies that SDL2 + the embedded SNA blob compile
 * and link on every host platform. Opens a placeholder window and exits on
 * Esc / window close.
 *
 * Phase 1 will wire up chips/zx.h here: emulator init, framebuffer blit,
 * audio callback, keyboard + Kempston joystick input.
 */

#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>

#include "juego_sna.h"

#define WIN_WIDTH  (256 * 3)
#define WIN_HEIGHT (192 * 3)

int main(int argc, char *argv[]) {
    (void)argc;
    (void)argv;

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return EXIT_FAILURE;
    }

    SDL_Window *window = SDL_CreateWindow(
        "Tharkys the Knight",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WIN_WIDTH, WIN_HEIGHT,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return EXIT_FAILURE;
    }

    SDL_Renderer *renderer = SDL_CreateRenderer(
        window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC
    );
    if (!renderer) {
        fprintf(stderr, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return EXIT_FAILURE;
    }

    /* Phase 0 sanity print: confirm the SNA blob is linked in. */
    printf("[tharkys] SNA blob present: %u bytes\n", juego_sna_len);
    printf("[tharkys] Phase 0 scaffold - emulator integration lands in Phase 1.\n");

    int running = 1;
    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            switch (ev.type) {
                case SDL_QUIT:
                    running = 0;
                    break;
                case SDL_KEYDOWN:
                    if (ev.key.keysym.sym == SDLK_ESCAPE) {
                        running = 0;
                    }
                    break;
                default:
                    break;
            }
        }

        /* Solid colour fill until we hook the emulator framebuffer in. */
        SDL_SetRenderDrawColor(renderer, 0x10, 0x10, 0x18, 0xFF);
        SDL_RenderClear(renderer);
        SDL_RenderPresent(renderer);
    }

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return EXIT_SUCCESS;
}
