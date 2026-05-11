/*
 * input.h - SDL keyboard -> ZX Spectrum key code translation.
 *
 * Letters / digits are mapped to lowercase ASCII (chips/zx registers
 * 'a'..'z' / '0'..'9' for the no-shift layer). Enter, Space and cursor
 * keys get the chips control codes.
 *
 * Returns 0 when there is no useful mapping, so callers can ignore.
 */

#pragma once

#include <SDL_keycode.h>

int input_sdl_to_zx(SDL_Keycode sym);
