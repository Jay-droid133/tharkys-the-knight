/*
 * gamepad.h - SDL_GameController -> Kempston joystick mask.
 *
 * The game's ReadInput (logic_game.asm) already polls the Kempston port
 * directly, so the wrapper only has to forward a mask via emu_joystick().
 * This module owns one active gamepad at a time (hotplug-aware) and
 * exports its state as an EMU_JOY_* bitfield.
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include <SDL_events.h>

typedef struct gamepad gamepad_t;

gamepad_t *gamepad_create(void);
void       gamepad_destroy(gamepad_t *g);

/* Forward SDL_CONTROLLERDEVICEADDED / SDL_CONTROLLERDEVICEREMOVED events
 * so we can open the first controller plugged in and close it cleanly
 * when removed. Other event types are ignored. */
void       gamepad_handle_event(gamepad_t *g, const SDL_Event *ev);

/* Current state as a Kempston-style mask (EMU_JOY_* bits). Returns 0
 * when no controller is connected. Safe to call every frame. */
uint8_t    gamepad_poll(const gamepad_t *g);

/* Poll only the left analog stick (no D-pad, no face buttons). Used by
 * the wrapper's language menu where the D-pad arrives via discrete
 * CONTROLLERBUTTONDOWN events; including it in the poll would
 * double-step the cursor. */
uint8_t    gamepad_poll_stick_only(const gamepad_t *g);

bool       gamepad_connected(const gamepad_t *g);

/* True if any face button, D-pad, shoulder, trigger or stick is past
 * its rest position right now. Used by the wrapper to detect when the
 * user has fully released after a story-skip so the next press can be
 * counted as a fresh input. */
bool       gamepad_any_input(const gamepad_t *g);
