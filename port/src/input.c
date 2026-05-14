#include "input.h"
#include "emu.h"     /* EMU_JOY_* bit definitions */

#include <SDL.h>

int input_sdl_to_zx(SDL_Keycode sym) {
    /* Keys delegated entirely to the joystick mask path. Returning 0 here
     * keeps them out of the ZX kbd matrix; otherwise they'd register as
     * 'w','a','s','d' / cursor key codes that the game does not read
     * but would still occupy slots in chips' kbd state. */
    switch (sym) {
        case SDLK_w: case SDLK_a: case SDLK_s: case SDLK_d:
        case SDLK_UP: case SDLK_DOWN: case SDLK_LEFT: case SDLK_RIGHT:
        case SDLK_LCTRL: case SDLK_RCTRL:
            return 0;
        default: break;
    }

    /* a..z and 0..9 come straight through (SDL_Keycode == ASCII for these). */
    if (sym >= SDLK_a && sym <= SDLK_z) return (int)sym;          /* 0x61..0x7A */
    if (sym >= SDLK_0 && sym <= SDLK_9) return (int)sym;          /* 0x30..0x39 */

    switch (sym) {
        case SDLK_SPACE:    return ' ';
        case SDLK_RETURN:
        case SDLK_KP_ENTER: return 0x0D;
        case SDLK_BACKSPACE:return 0x0C;   /* Shift+0 = Delete on Spectrum    */
        case SDLK_LSHIFT:
        case SDLK_RSHIFT:   return 0;      /* let chips handle shift via upper-case keys */
        default:            return 0;
    }
}

uint8_t input_kbd_joystick_mask(void) {
    /* SDL_GetKeyboardState returns a pointer to SDL's internal scancode
     * array (read-only). Polling here keeps "held down" detection rock
     * solid even when the OS event queue is busy. */
    const Uint8 *kbd = SDL_GetKeyboardState(NULL);
    uint8_t mask = 0;
    if (kbd[SDL_SCANCODE_W] || kbd[SDL_SCANCODE_UP])         mask |= EMU_JOY_UP;
    if (kbd[SDL_SCANCODE_S] || kbd[SDL_SCANCODE_DOWN])       mask |= EMU_JOY_DOWN;
    if (kbd[SDL_SCANCODE_A] || kbd[SDL_SCANCODE_LEFT])       mask |= EMU_JOY_LEFT;
    if (kbd[SDL_SCANCODE_D] || kbd[SDL_SCANCODE_RIGHT])      mask |= EMU_JOY_RIGHT;
    if (kbd[SDL_SCANCODE_LCTRL] || kbd[SDL_SCANCODE_RCTRL])  mask |= EMU_JOY_FIRE;
    return mask;
}
