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

/* Render a 256x192 Spectrum-native screen (6144 interleaved-scanline
 * pixel bytes + 768 char-cell attribute bytes) into the framebuffer,
 * centred in the visible area with black border around it. Goes through
 * the same GL pipeline as game frames, so the splash gets scanlines,
 * RGB grille, vignette and tube curvature like the rest. */
void     video_upload_splash(video_t      *v,
                             const uint8_t *pixel_bytes,
                             const uint8_t *attr_bytes);

/* Draw the textured fullscreen quad with the current effect and present. */
void     video_present(video_t *v);

/* Inform the renderer that the window was resized. */
void     video_resize(video_t *v, int width, int height);

/* CRT effect toggle (default: on). */
void     video_set_crt(video_t *v, bool enabled);
bool     video_crt(const video_t *v);

/* Symmetric UV inset for "border crop" zoom in the shader. 0 = no zoom
 * (full 320x256 visible), 0.1 = ~10 % cropped on every side. Same
 * factor on both axes so the picture aspect ratio is preserved. */
void     video_set_zoom(video_t *v, float zoom);

/* Install custom glyphs for codepoints 0x80..0x80+count-1. Each glyph
 * is 8 bytes (one row per byte, MSB = leftmost pixel) -- same format as
 * the ROM font. Used for Spanish accented vowels that aren't in the
 * 48K ROM character set. Pointer is stored, not copied. */
void     video_set_extended_font(video_t *v, const uint8_t *glyphs, int count);

/* Pause overlay: dims the frame and stamps a centred "PAUSE" label that
 * blinks ~1.25 Hz and inherits whatever filters the CRT pass applies. */
void     video_set_paused(video_t *v, bool paused);

/* Optional: rebuild the pause-label texture from a 768-byte 8x8 char
 * font (96 chars starting at ASCII 0x20). Pass the ZX Spectrum ROM font
 * via emu_spectrum_font() for the authentic look. NULL reverts to the
 * hardcoded fallback glyphs. */
void     video_set_pause_font(video_t *v, const uint8_t *font);

/* Show a transient OSD message centred near the bottom of the Spectrum
 * screen for duration_ms. Replaces any pending message. Text is
 * truncated to 32 chars (screen width) and rendered with the Spectrum
 * font, so uppercase A-Z + digits + space read best. Pass NULL or "" to
 * cancel immediately. */
void     video_show_msg(video_t *v, const char *text, int duration_ms);

/* Show a persistent multi-line help screen centred on the Spectrum
 * screen. Text uses '\n' as line separator. Caller retains ownership of
 * the string (the pointer is stored, not copied -- use string literals
 * or a buffer with a lifetime exceeding any frame). NULL hides. */
void     video_set_help(video_t *v, const char *text);
bool     video_help_visible(const video_t *v);

/* When true, the help-overlay text is drawn directly on top of the
 * current game framebuffer (no black wash). Used by the wrapper's
 * story phase so the animated key / button icons painted by the
 * game's SplashWait remain visible behind the narration. Defaults
 * to false, restoring the classic F1 help look (text on black). */
void     video_set_help_transparent(video_t *v, bool transparent);

/* Mask-out: the help overlay's black wash is applied EXCEPT inside
 * this rectangle (pixel coords on the 320x256 visible area). Used by
 * the wrapper's story phase to keep just the animated key/button
 * icons visible while everything else around the narration is black.
 * Width = 0 disables (full clear). */
void     video_set_help_preserve_rect(video_t *v,
                                      int x, int y, int w, int h);
