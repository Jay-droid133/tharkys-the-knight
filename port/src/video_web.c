/*
 * video_web.c - SDL_Renderer backend for the Emscripten / web build.
 *
 * Mirrors the video.h interface of the desktop OpenGL+CRT pipeline but
 * without shaders: it blits a palette-indexed 320x256 ZX framebuffer to a
 * streaming RGBA texture and lets SDL_RenderSetLogicalSize letterbox it.
 *
 * The text/overlay helpers (centered text, splash sprite, help screen,
 * pause label, OSD message) are ported straight from video.c's software
 * compositor -- they operate on the same 320x256 RGBA buffer, so the
 * language menu, story pages and wrapper splash all render in the browser
 * exactly as on desktop, just without the CRT filter on top.
 */

#include "video.h"

#include <SDL.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "key_icon.h"   /* key_icon_pixels / key_icon_attrs (16x16 frames) */

/* chips/zx visible area: 320x256 (256x192 screen + 32 px border each side). */
#define FB_W           320
#define FB_H           256
#define ZX_BORDER      32
#define ZX_CHAR_SIZE   8
#define ZX_SCREEN_COLS 32
#define ZX_SCREEN_ROWS 24

/* PAUSE label: 5 cells centred on the grid (same as video.c). */
#define PAUSE_COLS     5
#define PAUSE_AT_COL   ((ZX_SCREEN_COLS - PAUSE_COLS) / 2) /* 13 */
#define PAUSE_AT_ROW   ((ZX_SCREEN_ROWS - 1) / 2)          /* 11 */
#define OSD_MSG_ROW    (PAUSE_AT_ROW + 2)
static const char PAUSE_WORD[PAUSE_COLS] = { 'P', 'A', 'U', 'S', 'E' };

/* Standard Spectrum palette, RGBA in memory order on LE. 0..7 std, 8..15
 * bright. Identical to video.c so colours match the desktop build. */
static const uint32_t SPECTRUM_PALETTE[16] = {
    0xFF000000u, 0xFFD70000u, 0xFF0000D7u, 0xFFD700D7u,
    0xFF00D700u, 0xFFD7D700u, 0xFF00D7D7u, 0xFFD7D7D7u,
    0xFF000000u, 0xFFFF0000u, 0xFF0000FFu, 0xFFFF00FFu,
    0xFF00FF00u, 0xFFFFFF00u, 0xFF00FFFFu, 0xFFFFFFFFu,
};

/* Extended font for codepoints 0x80+ (accented Spanish vowels). File-static
 * like video.c so compose_line can read it directly. */
static const uint8_t *s_ext_font       = NULL;
static int            s_ext_font_count  = 0;

struct video {
    SDL_Renderer *ren;
    SDL_Texture  *tex;
    uint32_t      pixels[FB_W * FB_H];   /* CPU staging buffer */

    int           win_w, win_h;

    bool          paused;
    bool          crt_on;   /* tracked for parity; no shader in web */
    float         zoom;

    const uint8_t *pause_font;            /* 768-byte 8x8 font (reward) */

    const char    *help_text;
    bool           help_transparent;
    bool           help_center_lines;     /* center each help line on its own */
    int            preserve_x, preserve_y, preserve_w, preserve_h;

    char          msg_text[64];
    Uint32        msg_expires_ticks;
};

/* ----------------------------------------------------------------------- */
/* Software compositor (ported from video.c)                                */
/* ----------------------------------------------------------------------- */

static void apply_clear_black(uint32_t *buf) {
    for (int i = 0; i < FB_W * FB_H; i++) buf[i] = 0xFF000000u;
}

/* Dim the frame to ~35 % for the pause overlay. Operates per channel on
 * the RGBA32 little-endian words. */
static void apply_dim(uint32_t *buf) {
    for (int i = 0; i < FB_W * FB_H; i++) {
        const uint32_t p = buf[i];
        const uint32_t r = ((p        & 0xFF) * 90) >> 8;
        const uint32_t g = (((p >> 8)  & 0xFF) * 90) >> 8;
        const uint32_t b = (((p >> 16) & 0xFF) * 90) >> 8;
        buf[i] = 0xFF000000u | (b << 16) | (g << 8) | r;
    }
}

/* Render `len` chars from `line` at (col,row) on the 32x24 grid: white ink
 * on black paper, like BASIC PRINT. Clipped at the right edge. */
static void compose_line(uint32_t *buf, const uint8_t *font_768,
                         int grid_col, int grid_row,
                         const char *line, int len)
{
    if (!font_768 || !line || len <= 0) return;
    if (grid_col < 0 || grid_row < 0) return;
    if (grid_col + len > ZX_SCREEN_COLS) len = ZX_SCREEN_COLS - grid_col;
    if (len <= 0) return;

    const int text_x = ZX_BORDER + grid_col * ZX_CHAR_SIZE;
    const int text_y = ZX_BORDER + grid_row * ZX_CHAR_SIZE;
    const int text_w = len * ZX_CHAR_SIZE;
    if (text_x + text_w > FB_W || text_y + ZX_CHAR_SIZE > FB_H) return;

    for (int row = 0; row < ZX_CHAR_SIZE; row++) {
        uint32_t *dst_row = buf + (size_t)(text_y + row) * FB_W;
        for (int col = 0; col < text_w; col++) {
            const int letter        = col / ZX_CHAR_SIZE;
            const int col_in_letter = col % ZX_CHAR_SIZE;
            const unsigned char ch  = (unsigned char)line[letter];
            uint8_t bits = 0;
            if (ch >= 0x20 && ch < 0x80) {
                bits = font_768[(ch - 0x20) * 8 + row];
            } else if (ch >= 0x80 && (int)(ch - 0x80) < s_ext_font_count) {
                bits = s_ext_font[(ch - 0x80) * 8 + row];
            }
            const bool on         = (bits >> (7 - col_in_letter)) & 1;
            dst_row[text_x + col] = on ? 0xFFFFFFFFu : 0xFF000000u;
        }
    }
}

static int line_len(const char *cursor) {
    const char *eol = strchr(cursor, '\n');
    return eol ? (int)(eol - cursor) : (int)strlen(cursor);
}

/* Multi-line help/menu screen: title (line 0) centred on its own length,
 * body lines left-aligned at a shared, screen-centred column, double row
 * spacing. Background must already be set by the caller. */
static void compose_help_overlay(uint32_t *buf, const uint8_t *font_768,
                                 const char *help, bool center_each)
{
    if (!font_768 || !help || !*help) return;

    int num_lines = 1;
    for (const char *p = help; *p; p++) if (*p == '\n') num_lines++;

    const int total_rows = num_lines * 2 - 1;
    int start_row = (ZX_SCREEN_ROWS - total_rows) / 2;
    if (start_row < 0) start_row = 0;

    /* Body-block left column; unused in center_each mode (every line is
     * centred on its own length, mirroring the standalone story screen). */
    int max_body_w = 0;
    if (!center_each) {
        const char *c = help;
        for (int i = 0; i < num_lines; i++) {
            const int len = line_len(c);
            if (i > 0 && len > max_body_w) max_body_w = len;
            const char *eol = strchr(c, '\n');
            c = eol ? eol + 1 : c + len;
        }
    }
    if (max_body_w > ZX_SCREEN_COLS) max_body_w = ZX_SCREEN_COLS;
    const int body_col = (ZX_SCREEN_COLS - max_body_w) / 2;

    const char *cursor = help;
    for (int i = 0; i < num_lines; i++) {
        int len = line_len(cursor);
        if (len > ZX_SCREEN_COLS) len = ZX_SCREEN_COLS;
        const int col = (center_each || i == 0)
            ? (ZX_SCREEN_COLS - len) / 2
            : body_col;
        compose_line(buf, font_768, col, start_row + i * 2, cursor, len);
        const char *eol = strchr(cursor, '\n');
        cursor = eol ? eol + 1 : cursor + len;
    }
}

static void compose_msg_overlay(uint32_t *buf, const uint8_t *font_768,
                                const char *msg)
{
    if (!msg || !*msg) return;
    int len = (int)strlen(msg);
    if (len > ZX_SCREEN_COLS) len = ZX_SCREEN_COLS;
    const int col0 = (ZX_SCREEN_COLS - len) / 2;
    compose_line(buf, font_768, col0, OSD_MSG_ROW, msg, len);
}

/* ----------------------------------------------------------------------- */
/* Lifecycle                                                                */
/* ----------------------------------------------------------------------- */

video_t *video_create(SDL_Window *win) {
    if (!win) return NULL;
    video_t *v = (video_t *)calloc(1, sizeof(*v));
    if (!v) return NULL;

    v->ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!v->ren) v->ren = SDL_CreateRenderer(win, -1, 0);  /* software fallback */
    if (!v->ren) {
        fprintf(stderr, "video_web: SDL_CreateRenderer failed: %s\n", SDL_GetError());
        free(v);
        return NULL;
    }

    SDL_RenderSetLogicalSize(v->ren, FB_W, FB_H);

    /* RGBA32 (not ARGB8888) matches the chips/zx palette byte order; using
     * ARGB swapped R and B (red doors/roofs came out blue). */
    v->tex = SDL_CreateTexture(v->ren, SDL_PIXELFORMAT_RGBA32,
                               SDL_TEXTUREACCESS_STREAMING, FB_W, FB_H);
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

void video_upload_centered_text(video_t *v, const char *text) {
    if (!v || !text) return;
    apply_clear_black(v->pixels);
    if (!v->pause_font || !*text) return;

    int num_lines = 1;
    for (const char *p = text; *p; p++) if (*p == '\n') num_lines++;
    int start_row = (ZX_SCREEN_ROWS - num_lines) / 2;
    if (start_row < 0) start_row = 0;

    const char *cursor = text;
    for (int i = 0; i < num_lines; i++) {
        int len = 0;
        while (cursor[len] && cursor[len] != '\n') len++;
        if (len > ZX_SCREEN_COLS) len = ZX_SCREEN_COLS;
        const int col = (ZX_SCREEN_COLS - len) / 2;
        if (len > 0) compose_line(v->pixels, v->pause_font, col, start_row + i, cursor, len);
        cursor += len;
        if (*cursor == '\n') cursor++;
    }
}

void video_upload_splash(video_t *v,
                         const uint8_t *pixel_bytes,
                         const uint8_t *attr_bytes) {
    if (!v || !pixel_bytes || !attr_bytes) return;
    apply_clear_black(v->pixels);

    /* BG-editor screen format: row-major linear bitmap (32 bytes/row of
     * 256 px, 192 rows) + 8x8 attribute cells. Centred at (32,32). */
    for (int py = 0; py < 192; py++) {
        const int row_offset = py * 32;
        const int char_row   = py >> 3;
        uint32_t *dst_row    = v->pixels + (size_t)(ZX_BORDER + py) * FB_W + ZX_BORDER;
        for (int px = 0; px < 256; px++) {
            const int col       = px >> 3;
            const int bit       = 7 - (px & 7);
            const uint8_t pixel = pixel_bytes[row_offset + col];
            const bool    on    = (pixel >> bit) & 1;
            const uint8_t attr  = attr_bytes[char_row * 32 + col];
            const int ink       = attr & 7;
            const int paper     = (attr >> 3) & 7;
            const int bright    = (attr >> 6) & 1;
            const int colour    = (on ? ink : paper) + (bright ? 8 : 0);
            dst_row[px]         = SPECTRUM_PALETTE[colour];
        }
    }
}

void video_draw_key_intro(video_t *v) {
    if (!v) return;
    apply_clear_black(v->pixels);

    /* ~0.5 s per frame, cycled from the wall clock. */
    const int frame = (int)((SDL_GetTicks() / 500u) % KEY_ICON_FRAMES);
    const uint8_t *px = key_icon_pixels[frame];
    const uint8_t *at = key_icon_attrs[frame];
    const int SCALE = 2;                          /* 16x16 -> 32x32 */
    const int dim   = KEY_ICON_W * SCALE;
    const int ox    = (FB_W - dim) / 2;
    const int oy    = (FB_H - dim) / 2;

    for (int sy16 = 0; sy16 < KEY_ICON_H; sy16++) {
        const int cell_row = sy16 >> 3;           /* 0 or 1 (8px cells) */
        for (int sx16 = 0; sx16 < KEY_ICON_W; sx16++) {
            const int byte = sy16 * 2 + (sx16 >> 3); /* 2 bytes per row */
            const int bit  = 7 - (sx16 & 7);
            if (!((px[byte] >> bit) & 1)) continue;  /* off -> leave black */
            const uint8_t attr   = at[cell_row * 2 + (sx16 >> 3)];
            const int     ink    = attr & 7;
            const int     bright = (attr >> 6) & 1;
            const uint32_t color = SPECTRUM_PALETTE[ink + (bright ? 8 : 0)];
            /* paint a SCALE x SCALE block for this source pixel */
            for (int dy = 0; dy < SCALE; dy++) {
                uint32_t *row = v->pixels +
                    (size_t)(oy + sy16 * SCALE + dy) * FB_W + ox + sx16 * SCALE;
                for (int dx = 0; dx < SCALE; dx++) row[dx] = color;
            }
        }
    }
}

void video_present(video_t *v) {
    if (!v || !v->ren || !v->tex) return;

    /* Composite overlays on top of whatever frame video_upload* left in
     * v->pixels, in the same z-order as the desktop build. The base frame
     * is regenerated every tick, so overlays never stack. */
    if (v->help_text && !v->help_transparent) {
        if (v->preserve_w > 0 && v->preserve_h > 0) {
            const int rx = v->preserve_x, ry = v->preserve_y;
            const int rw = v->preserve_w, rh = v->preserve_h;
            for (int y = 0; y < FB_H; y++) {
                uint32_t *row = v->pixels + (size_t)y * FB_W;
                if (y < ry || y >= ry + rh) {
                    for (int x = 0; x < FB_W; x++) row[x] = 0xFF000000u;
                } else {
                    for (int x = 0; x < rx; x++) row[x] = 0xFF000000u;
                    for (int x = rx + rw; x < FB_W; x++) row[x] = 0xFF000000u;
                }
            }
        } else {
            apply_clear_black(v->pixels);
        }
    } else if (v->paused) {
        apply_dim(v->pixels);
    }
    if (v->paused && !v->help_text) {
        const Uint32 t        = SDL_GetTicks();
        const bool   blink_on = ((t / 400u) % 2u == 0u);
        if (blink_on)
            compose_line(v->pixels, v->pause_font,
                         PAUSE_AT_COL, PAUSE_AT_ROW, PAUSE_WORD, PAUSE_COLS);
    }
    if (v->help_text) {
        compose_help_overlay(v->pixels, v->pause_font, v->help_text,
                             v->help_center_lines);
    }
    if (v->msg_text[0] && SDL_GetTicks() < v->msg_expires_ticks) {
        compose_msg_overlay(v->pixels, v->pause_font, v->msg_text);
    }

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
    /* SDL_RenderSetLogicalSize handles letterboxing across resizes. */
}

/* ----------------------------------------------------------------------- */
/* Setters / state                                                          */
/* ----------------------------------------------------------------------- */

void video_set_crt(video_t *v, bool enabled)      { if (v) v->crt_on = enabled; }
bool video_crt(const video_t *v)                  { return v ? v->crt_on : false; }
void video_set_zoom(video_t *v, float zoom)       { if (v) v->zoom = zoom; }
void video_set_paused(video_t *v, bool paused)    { if (v) v->paused = paused; }
void video_set_pause_font(video_t *v, const uint8_t *font) { if (v) v->pause_font = font; }

void video_set_extended_font(video_t *v, const uint8_t *glyphs, int count) {
    (void)v;
    s_ext_font      = glyphs;
    s_ext_font_count = (glyphs && count > 0) ? count : 0;
}

void video_show_msg(video_t *v, const char *text, int duration_ms) {
    if (!v) return;
    if (!text || !*text) { v->msg_text[0] = '\0'; return; }
    snprintf(v->msg_text, sizeof(v->msg_text), "%s", text);
    v->msg_expires_ticks = SDL_GetTicks() + (Uint32)duration_ms;
}

void video_set_help(video_t *v, const char *text) {
    if (!v) return;
    v->help_text = text;
    if (!text) {
        v->help_transparent = false;
        v->preserve_w = v->preserve_h = 0;
    }
}

bool video_help_visible(const video_t *v) {
    return v && v->help_text != NULL;
}

void video_set_help_transparent(video_t *v, bool transparent) {
    if (v) v->help_transparent = transparent;
}

void video_set_help_center_lines(video_t *v, bool on) {
    if (v) v->help_center_lines = on;
}

void video_set_help_preserve_rect(video_t *v, int x, int y, int w, int h) {
    if (!v) return;
    v->preserve_x = x;
    v->preserve_y = y;
    v->preserve_w = w;
    v->preserve_h = h;
}
