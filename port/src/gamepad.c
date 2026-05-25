/*
 * gamepad.c - SDL_GameController polling.
 *
 * Single-controller model: open the first controller SDL reports added
 * (works for both already-plugged-in controllers at startup and ones
 * plugged in later), close it on remove. Subsequent controllers are
 * ignored for now -- two-player support would just need a second slot.
 */

#include "gamepad.h"
#include "emu.h"

#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>

/* Analog deadzone. SDL axes are Sint16 (-32768..32767); ~37% of full
 * range is a sane default that works for both crisp D-pad-style stick
 * use and slow-thumb pressure. The official Xbox guidance is 7849 for
 * left stick, but games for old joysticks tend to want a bigger zone
 * so a casual tilt doesn't move the character. */
#define STICK_DEADZONE 12000

struct gamepad {
    SDL_GameController *ctrl;
    SDL_JoystickID      instance_id;
};

gamepad_t *gamepad_create(void) {
    gamepad_t *g = (gamepad_t *)calloc(1, sizeof(*g));
    if (!g) return NULL;
    g->instance_id = -1;
    return g;
}

void gamepad_destroy(gamepad_t *g) {
    if (!g) return;
    if (g->ctrl) SDL_GameControllerClose(g->ctrl);
    free(g);
}

bool gamepad_connected(const gamepad_t *g) {
    return g && g->ctrl != NULL;
}

void gamepad_handle_event(gamepad_t *g, const SDL_Event *ev) {
    if (!g || !ev) return;

    switch (ev->type) {
        case SDL_CONTROLLERDEVICEADDED: {
            /* `which` is the joystick device index here. */
            if (g->ctrl) break;  /* we already own one */
            if (!SDL_IsGameController(ev->cdevice.which)) break;

            SDL_GameController *c = SDL_GameControllerOpen(ev->cdevice.which);
            if (!c) {
                fprintf(stderr, "[gamepad] SDL_GameControllerOpen failed: %s\n",
                        SDL_GetError());
                break;
            }
            g->ctrl        = c;
            g->instance_id = SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(c));
            fprintf(stderr, "[gamepad] connected: %s\n",
                    SDL_GameControllerName(c));
        } break;

        case SDL_CONTROLLERDEVICEREMOVED: {
            /* `which` is the instance ID here (post-open identifier). */
            if (g->ctrl && ev->cdevice.which == g->instance_id) {
                fprintf(stderr, "[gamepad] disconnected: %s\n",
                        SDL_GameControllerName(g->ctrl));
                SDL_GameControllerClose(g->ctrl);
                g->ctrl        = NULL;
                g->instance_id = -1;
            }
        } break;

        default:
            break;
    }
}

bool gamepad_any_input(const gamepad_t *g) {
    if (!g || !g->ctrl) return false;
    SDL_GameController *c = g->ctrl;
    /* D-pad + face + shoulders. SDL_CONTROLLER_BUTTON_MAX bounds the enum. */
    for (int b = 0; b < SDL_CONTROLLER_BUTTON_MAX; b++) {
        if (SDL_GameControllerGetButton(c, (SDL_GameControllerButton)b)) return true;
    }
    /* Sticks + triggers (deadzoned). */
    if (SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTX)  >  STICK_DEADZONE) return true;
    if (SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTX)  < -STICK_DEADZONE) return true;
    if (SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTY)  >  STICK_DEADZONE) return true;
    if (SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTY)  < -STICK_DEADZONE) return true;
    if (SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_TRIGGERLEFT)  > STICK_DEADZONE) return true;
    if (SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_TRIGGERRIGHT) > STICK_DEADZONE) return true;
    return false;
}

uint8_t gamepad_poll_stick_only(const gamepad_t *g) {
    if (!g || !g->ctrl) return 0;
    uint8_t mask = 0;
    SDL_GameController *c = g->ctrl;
    const Sint16 lx = SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTX);
    const Sint16 ly = SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTY);
    if (lx < -STICK_DEADZONE) mask |= EMU_JOY_LEFT;
    if (lx >  STICK_DEADZONE) mask |= EMU_JOY_RIGHT;
    if (ly < -STICK_DEADZONE) mask |= EMU_JOY_UP;
    if (ly >  STICK_DEADZONE) mask |= EMU_JOY_DOWN;
    return mask;
}

uint8_t gamepad_poll(const gamepad_t *g) {
    if (!g || !g->ctrl) return 0;

    uint8_t mask = 0;
    SDL_GameController *c = g->ctrl;

    /* --- D-pad: digital, 1:1 mapping ---------------------------------- */
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_UP))    mask |= EMU_JOY_UP;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_DOWN))  mask |= EMU_JOY_DOWN;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_LEFT))  mask |= EMU_JOY_LEFT;
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) mask |= EMU_JOY_RIGHT;

    /* --- Left stick: deadzoned, OR'd onto the D-pad result ------------- */
    const Sint16 lx = SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTX);
    const Sint16 ly = SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_LEFTY);
    if (lx < -STICK_DEADZONE) mask |= EMU_JOY_LEFT;
    if (lx >  STICK_DEADZONE) mask |= EMU_JOY_RIGHT;
    if (ly < -STICK_DEADZONE) mask |= EMU_JOY_UP;
    if (ly >  STICK_DEADZONE) mask |= EMU_JOY_DOWN;

    /* --- Any face button is fire --------------------------------------- *
     * Different gamepad cultures put "the main action" on different
     * faces (Xbox=A, PlayStation=Cross, Nintendo=B). Mapping all four
     * faces + the triggers / shoulder buttons to fire avoids surprising
     * the user without needing a remap UI in Phase 2. */
    if (SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_A) ||
        SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_B) ||
        SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_X) ||
        SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_Y) ||
        SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_LEFTSHOULDER) ||
        SDL_GameControllerGetButton(c, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER) ||
        SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_TRIGGERLEFT)  > STICK_DEADZONE ||
        SDL_GameControllerGetAxis(c, SDL_CONTROLLER_AXIS_TRIGGERRIGHT) > STICK_DEADZONE) {
        mask |= EMU_JOY_FIRE;
    }

    return mask;
}
