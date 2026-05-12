/*
 * video.h - OpenGL 3.3 core rendering pipeline.
 *
 * Owns the GL context, the framebuffer texture, the shader program and
 * the empty VAO needed by core profile. main.c uploads palette-indexed
 * emulator frames each tick; video_present() draws a fullscreen quad
 * with the CRT effect on top and swaps buffers.
 *
 * One global state: u_crt_enabled. Toggleable at runtime from the host.
 */

#pragma once

#include <SDL.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct video video_t;

video_t *video_create(SDL_Window *win);
void     video_destroy(video_t *v);

/* Take a frame of palette-indexed pixels (1 byte/px) plus the 16-entry
 * RGBA palette, convert and upload to the GPU texture. Only the visible
 * area (vis_width × vis_height starting at top-left) is uploaded. */
void     video_upload(video_t *v,
                      const uint8_t  *fb,
                      int             fb_stride,
                      int             vis_width,
                      int             vis_height,
                      const uint32_t *palette);

/* Draw the textured fullscreen quad with the current effect and present. */
void     video_present(video_t *v);

/* Inform the renderer that the window was resized. */
void     video_resize(video_t *v, int width, int height);

/* CRT effect toggle (default: on). */
void     video_set_crt(video_t *v, bool enabled);
bool     video_crt(const video_t *v);
