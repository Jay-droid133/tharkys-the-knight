#include "input.h"

int input_sdl_to_zx(SDL_Keycode sym) {
    /* a..z and 0..9 come straight through (SDL_Keycode == ASCII for these). */
    if (sym >= SDLK_a && sym <= SDLK_z) return (int)sym;          /* 0x61..0x7A */
    if (sym >= SDLK_0 && sym <= SDLK_9) return (int)sym;          /* 0x30..0x39 */

    switch (sym) {
        case SDLK_SPACE:    return ' ';
        case SDLK_RETURN:
        case SDLK_KP_ENTER: return 0x0D;
        case SDLK_LEFT:     return 0x08;
        case SDLK_DOWN:     return 0x0A;
        case SDLK_UP:       return 0x0B;
        case SDLK_RIGHT:    return 0x09;
        case SDLK_BACKSPACE:return 0x0C;   /* Shift+0 = Delete on Spectrum    */
        case SDLK_LSHIFT:
        case SDLK_RSHIFT:   return 0;      /* let chips handle shift via upper-case keys */
        default:            return 0;
    }
}
