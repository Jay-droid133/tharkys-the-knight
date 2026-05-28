/*
 * video_web.c - SDL_Renderer backend for the Emscripten / web build.
 *
 * Mirrors the video.h interface of the desktop OpenGL+CRT pipeline but
 * does the minimum: blit a palette-indexed 320x256 ZX framebuffer to a
 * streaming RGBA texture, scale to the canvas via SDL_RenderSetLogicalSize.
 *
 * Overlays (centered text, splash sprite, msg, help, pause label) are
 * stubbed out for the MVP -- the splash cards will show black for ~10 s
 * before the game itself takes over the screen. Implementing them needs
 * a software rasteriser of the Spectrum char grid, which we'll add once
 * the boot path is confirmed working end-to-end.
 */

#include "video.h"

#include <SDL.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The chips/zx visible area: 320x256 (256x192 screen + 32 px border each side). */
#define FB_W 320
#define FB_H 256

struct video {
    SDL_Renderer *ren;
    SDL_Texture  *tex;

    /* CPU-side staging buffer. video_upload writes into here; video_present
     * pushes it to the streaming texture and renders. */
    uint32_t      pixels[FB_W * FB_H];

    /* Tracked for parity with the desktop video.c API; not used by the
     * MVP since SDL_RenderSetLogicalSize handles letterboxing for us. */
    int           win_w, win_h;

    /* Flags kept so video_crt() etc. return sensible values; no shader
     * pipeline reads them in the web build. */
    bool          paused;
    bool          crt_on;
    float         zoom;

    /* Held but unused in MVP. Wired up so the desktop code paths that
     * pass these pointers don't crash; the renderer ignores them. */
    const uint8_t *ext_font;
    int            ext_font_count;
    const uint8_t *pause_font;

    const char    *help_text;
    bool           help_transparent;
    SDL_Rect       help_preserve;
};

/* ----------------------------------------------------------------------- */
/* Lifecycle                                                                */
/* ----------------------------------------------------------------------- */

video_t *video_create(SDL_Window *win) {
    if (!win) return NULL;
    video_t *v = (video_t *)calloc(1, sizeof(*v));
    if (!v) return NULL;

    /* PRESENTVSYNC keeps us aligned to the display refresh, which on the
     * web is what emscripten_set_main_loop(fps=0) already targets via
     * requestAnimationFrame. Belt and braces. */
    v->ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!v->ren) {
        /* Fall back to software on browsers without ACCELERATED. */
        v->ren = SDL_CreateRenderer(win, -1, 0);
    }
    if (!v->ren) {
        fprintf(stderr, "video_web: SDL_CreateRenderer failed: %s\n", SDL_GetError());
        free(v);
        return NULL;
    }

    /* Logical 320x256 means the renderer letterboxes the picture inside
     * whatever canvas size we get, preserving aspect ratio without any
     * shader work. */
    SDL_RenderSetLogicalSize(v->ren, FB_W, FB_H);

    /* RGBA32 matches the byte order the chips/zx palette is generated in
     * (R, G, B, A in memory order), so the palette[index] uint32_t can
     * be copied straight into the texture without a swizzle. Using
     * ARGB8888 here swapped the R and B channels on little-endian (red
     * doors / roofs appeared blue). */
    v->tex = SDL_CreateTexture(v->ren,
                               SDL_PIXELFORMAT_RGBA32,
                               SDL_TEXTUREACCESS_STREAMING,
                               FB_W, FB_H);
    if (!v->tex) {
        fprintf(stderr, "video_web: SDL_CreateTexture failed: %s\n", SDL_GetError());
        SDL_DestroyRenderer(v->ren);
        free(v);
        return NULL;
    }
    SDL_SetTextureScaleMode(v->tex, SDL_ScaleModeLinear);

    SDL_GetWindowSize(win, &v->win_w, &v->win_h);
    return v;
}

void video_destroy(video_t *v) {
    if (!v) return;
    if (v->tex) SDL_DestroyTexture(v->tex);
    if (v->ren) SDL_DestroyRenderer(v->ren);
    free(v);
}

/* ----------------------------------------------------------------------- */
/* Frame upload + present                                                   */
/* ----------------------------------------------------------------------- */

void video_upload(video_t *v,
                  const uint8_t  *fb,
                  int             fb_stride,
                  int             vis_width,
                  int             vis_height,
                  const uint32_t *palette) {
    if (!v || !fb || !palette) return;
    const int copy_w = vis_width  > FB_W ? FB_W : vis_width;
    const int copy_h = vis_height > FB_H ? FB_H : vis_height;
    for (int y = 0; y < copy_h; y++) {
        const uint8_t *src = fb + y * fb_stride;
        uint32_t      *dst = v->pixels + y * FB_W;
        for (int x = 0; x < copy_w; x++) {
            dst[x] = palette[src[x] & 0x0F];
        }
    }
}

void video_present(video_t *v) {
    if (!v || !v->ren || !v->tex) return;
    SDL_UpdateTexture(v->tex, NULL, v->pixels, FB_W * (int)sizeof(uint32_t));
    SDL_SetRenderDrawColor(v->ren, 0, 0, 0, 255);
    SDL_RenderClear(v->ren);
    SDL_RenderCopy(v->ren, v->tex, NULL, NULL);
    SDL_RenderPresent(v->ren);
}

void video_resize(video_t *v, int width, int height) {
    if (!v) return;
    v->win_w = width;
    v->win_h = height;
    /* SDL_RenderSetLogicalSize already handles letterboxing on its own
     * across window resizes, so there's nothing else to do here. */
}

/* ----------------------------------------------------------------------- */
/* MVP stubs: keep state for getters, no rendering                           */
/* ----------------------------------------------------------------------- */

void video_upload_centered_text(video_t *v, const char *text) {
    (void)v; (void)text;
    /* TODO: paint text into v->pixels using the ZX ROM font. MVP leaves
     * the splash cards black. */
}

void video_upload_splash(video_t *v,
                         const uint8_t *pixel_bytes,
                         const uint8_t *attr_bytes) {
    (void)v; (void)pixel_bytes; (void)attr_bytes;
    /* TODO: decode the 6144 + 768 ZX-native screen into v->pixels. */
}

void video_set_crt(video_t *v, bool enabled) {
    if (v) v->crt_on = enabled;
}

bool video_crt(const video_t *v) {
    return v ? v->crt_on : false;
}

void video_set_zoom(video_t *v, float zoom) {
    if (v) v->zoom = zoom;
}

void video_set_extended_font(video_t *v, const uint8_t *glyphs, int count) {
    if (!v) return;
    v->ext_font       = glyphs;
    v->ext_font_count = count;
}

void video_set_paused(video_t *v, bool paused) {
    if (v) v->paused = paused;
}

void video_set_pause_font(video_t *v, const uint8_t *font) {
    if (v) v->pause_font = font;
}

void video_show_msg(video_t *v, const char *text, int duration_ms) {
    (void)v; (void)text; (void)duration_ms;
}

void video_set_help(video_t *v, const char *text) {
    if (v) v->help_text = text;
}

bool video_help_visible(const video_t *v) {
    return v && v->help_text != NULL;
}

void video_set_help_transparent(video_t *v, bool transparent) {
    if (v) v->help_transparent = transparent;
}

void video_set_help_preserve_rect(video_t *v, int x, int y, int w, int h) {
    if (!v) return;
    v->help_preserve.x = x;
    v->help_preserve.y = y;
    v->help_preserve.w = w;
    v->help_preserve.h = h;
}
