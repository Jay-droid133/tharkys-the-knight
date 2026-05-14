/*
 * input.h - SDL keyboard -> ZX Spectrum input translation.
 *
 * Two complementary paths:
 *
 *   1. input_sdl_to_zx(sym): event-driven mapping to the ZX keyboard
 *      matrix. Letters / digits go through as lowercase ASCII (chips/zx
 *      registers 'a'..'z' / '0'..'9' for the no-shift layer); Space and
 *      Enter get their control codes. Returns 0 when there is no useful
 *      mapping so callers can ignore.
 *
 *   2. input_kbd_joystick_mask(): polled each frame, reads SDL's current
 *      keyboard state and produces a Kempston-style joystick mask from
 *      WASD / arrow keys / Ctrl. This is OR'd with the gamepad mask in
 *      main.c and pushed via emu_joystick(), so the game reads it through
 *      port $1F just like a real Kempston stick.
 *
 *      The keys handled here (W/A/S/D, arrows, L/R-Ctrl) are deliberately
 *      excluded from input_sdl_to_zx so they don't also pollute the ZX
 *      keyboard matrix.
 */

#pragma once

#include <SDL_keycode.h>
#include <stdint.h>

int     input_sdl_to_zx(SDL_Keycode sym);
uint8_t input_kbd_joystick_mask(void);
