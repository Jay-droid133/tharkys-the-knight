/*
 * video.c - rendering backend: OpenGL 3.3 core with SDL_Renderer fallback.
 *
 * Two paths share the same upload buffer and overlay compositing:
 *
 *   - Preferred: OpenGL 3.3 core + CRT shader (curvature, scanlines, mask,
 *     vignette). The default on any GPU from the last ~15 years.
 *
 *   - Fallback: SDL_Renderer + a streaming texture. Loses the CRT effect
 *     but keeps the game playable on old hardware (eg. pre-2010 Intel
 *     integrated, software GL, VMs without 3D accel, Windows machines
 *     with broken OpenGL drivers). Triggered automatically when GL 3.3
 *     core can't be created OR when the modern GL entry points fail to
 *     load -- a GL 1.1 fallback context is exactly that case (this is
 *     what produces the "[video] GL function missing: ..." log spam on
 *     ancient boxes).
 *
 * GL function loading: SDL_GL_GetProcAddress for every modern entry point
 * (anything past GL 1.1). Core 1.1 stuff (glClear, glViewport, texture
 * basics) is linked through the system OpenGL lib via find_package in
 * CMake.
 */

#include "video.h"

#include <SDL.h>
#include <SDL_opengl.h>
#include <SDL_opengl_glext.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------- */
/* GL function pointer loader                                          */
/* ------------------------------------------------------------------- */
#define GL_FUNCS \
    X(PFNGLACTIVETEXTUREPROC,       glActiveTexture)       \
    X(PFNGLCREATESHADERPROC,        glCreateShader)        \
    X(PFNGLSHADERSOURCEPROC,        glShaderSource)        \
    X(PFNGLCOMPILESHADERPROC,       glCompileShader)       \
    X(PFNGLGETSHADERIVPROC,         glGetShaderiv)         \
    X(PFNGLGETSHADERINFOLOGPROC,    glGetShaderInfoLog)    \
    X(PFNGLDELETESHADERPROC,        glDeleteShader)        \
    X(PFNGLCREATEPROGRAMPROC,       glCreateProgram)       \
    X(PFNGLATTACHSHADERPROC,        glAttachShader)        \
    X(PFNGLLINKPROGRAMPROC,         glLinkProgram)         \
    X(PFNGLGETPROGRAMIVPROC,        glGetProgramiv)        \
    X(PFNGLGETPROGRAMINFOLOGPROC,   glGetProgramInfoLog)   \
    X(PFNGLDELETEPROGRAMPROC,       glDeleteProgram)       \
    X(PFNGLUSEPROGRAMPROC,          glUseProgram)          \
    X(PFNGLGETUNIFORMLOCATIONPROC,  glGetUniformLocation)  \
    X(PFNGLUNIFORM1FPROC,           glUniform1f)           \
    X(PFNGLUNIFORM2FPROC,           glUniform2f)           \
    X(PFNGLUNIFORM1IPROC,           glUniform1i)           \
    X(PFNGLGENVERTEXARRAYSPROC,     glGenVertexArrays)     \
    X(PFNGLBINDVERTEXARRAYPROC,     glBindVertexArray)     \
    X(PFNGLDELETEVERTEXARRAYSPROC,  glDeleteVertexArrays)

#define X(type, name) static type _##name = NULL;
GL_FUNCS
#undef X

static int load_gl_funcs(void) {
    int missing = 0;
    #define X(type, name) \
        _##name = (type)SDL_GL_GetProcAddress(#name); \
        if (!_##name) missing++;
    GL_FUNCS
    #undef X
    if (missing) {
        fprintf(stderr,
                "[video] %d modern GL entry points missing -- "
                "this looks like a GL 1.x fallback context\n", missing);
    }
    return missing == 0;
}

/* ------------------------------------------------------------------- */
/* Shader sources                                                      */
/* ------------------------------------------------------------------- */
/*
 * Vertex shader: emits one of three positions chosen by gl_VertexID so a
 * single glDrawArrays(GL_TRIANGLES, 0, 3) covers the entire viewport. No
 * VBO needed; we just keep an empty VAO bound (core profile requirement).
 */
static const char *VS_SRC =
    "#version 330 core\n"
    "out vec2 v_uv;\n"
    "void main() {\n"
    "    vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0,\n"
    "                    (gl_VertexID == 2) ? 3.0 : -1.0);\n"
    "    v_uv = pos * 0.5 + 0.5;\n"
    "    v_uv.y = 1.0 - v_uv.y;\n" /* flip Y: texture top is uv.y=0 */
    "    gl_Position = vec4(pos, 0.0, 1.0);\n"
    "}\n";

/*
 * Fragment shader: emulates the look of crt-hyllian-fast (Hyllian, GPL,
 * part of libretro/glsl-shaders). NOT a port of his code -- this is an
 * inspired-by reimplementation with the three defining ingredients:
 *
 *   - Aperture-grille mask: vertical R/G/B sub-pixel stripes evaluated
 *     at OUTPUT-pixel granularity via gl_FragCoord.x. Cycles every 3
 *     window pixels, so on any reasonable scale the eye reads it as a
 *     fine RGB grille.
 *   - Source-pixel scanlines: sample the texture at the centre of the
 *     nearest source row, then weight by a gaussian on the distance
 *     from that centre. The beam width is per-channel and depends on
 *     pixel intensity (bright = wider beam, less darkening) -- that's
 *     where Hyllian's "alive" feel comes from.
 *   - Aggressive brightness boost (~2x) so mask + scanlines don't end
 *     up flattening the image.
 *
 * Plus our existing barrel curvature and corner vignette on top.
 *
 * All parameters baked in. CRT toggle (u_crt == 0) bypasses everything.
 */
static const char *FS_SRC =
    "#version 330 core\n"
    "uniform sampler2D u_tex;\n"
    "uniform vec2      u_tex_size;\n"
    "uniform int       u_crt;\n"
    "uniform float     u_zoom;\n"
    "in  vec2 v_uv;\n"
    "out vec4 o_color;\n"
    "vec2 barrel(vec2 uv, float k) {\n"
    "    vec2 cc = uv - 0.5;\n"
    "    float r2 = dot(cc, cc);\n"
    "    return uv + cc * r2 * k;\n"
    "}\n"
    "/* Symmetric zoom about the texture centre: u_zoom = 0 leaves UVs\n"
    " * untouched, u_zoom = 0.1 crops 10 %% off every side. Applied before\n"
    " * any other transform so barrel curvature + scanlines + mask see the\n"
    " * SAME source rectangle as the user. */\n"
    "vec2 apply_zoom(vec2 uv) {\n"
    "    return (uv - 0.5) * (1.0 - 2.0 * u_zoom) + 0.5;\n"
    "}\n"
    "void main() {\n"
    "    if (u_crt == 0) {\n"
    "        o_color = texture(u_tex, apply_zoom(v_uv));\n"
    "        return;\n"
    "    }\n"
    "    /* 1. Tube curvature, then border-crop zoom. The zoom is applied\n"
    "     *    AFTER barrel so the curvature still maps to the screen edges\n"
    "     *    (otherwise less border would also flatten the tube look). */\n"
    "    vec2 uv = apply_zoom(barrel(v_uv, 0.12));\n"
    "    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {\n"
    "        o_color = vec4(0.0, 0.0, 0.0, 1.0);\n"
    "        return;\n"
    "    }\n"
    "    /* 2. Bilinear sample, but only on X. Y is locked to the centre\n"
    "     *    of the nearest source row so the scanline weight further\n"
    "     *    down still sees clean per-row geometry; X uses the raw uv\n"
    "     *    so the GL_LINEAR filter smooths the horizontal upscale. */\n"
    "    vec2 tex_coord = uv * u_tex_size;\n"
    "    vec2 sample_uv = vec2(uv.x,\n"
    "                          (floor(tex_coord.y) + 0.5) / u_tex_size.y);\n"
    "    vec3 col       = texture(u_tex, sample_uv).rgb;\n"
    "    /* 3. Hyllian scanline weighting: gaussian on Y distance, per-\n"
    "     *    channel beam width driven by intensity (bright = wider).\n"
    "     *    Exp factor 20 squeezes the dark gap into the outer ~30%\n"
    "     *    of each row -- the bright band is essentially flat-top\n"
    "     *    for the central half; mix(0.55) keeps the lifted floor\n"
    "     *    so the lines read as fine, not as hard banding. */\n"
    "    float dy     = fract(tex_coord.y) - 0.5;\n"
    "    vec3  beamW  = vec3(0.7) + 0.5 * col;\n"
    "    vec3  weight = exp(-(dy * dy) * 20.0 / (beamW * beamW));\n"
    "    weight       = mix(vec3(1.0), weight, 0.55);\n"
    "    /* 4. Aperture grille: 3-pixel-cycle R/G/B stripes at output res. */\n"
    "    float mc   = mod(gl_FragCoord.x, 3.0);\n"
    "    vec3  mask = vec3(0.78);\n"
    "    if      (mc < 1.0) mask.r = 1.0;\n"
    "    else if (mc < 2.0) mask.g = 1.0;\n"
    "    else               mask.b = 1.0;\n"
    "    /* 5. Compose + brightness compensation. */\n"
    "    vec3 result = col * weight * mask * 1.45;\n"
    "    result      = pow(max(result, vec3(0.0)), vec3(0.92));\n"
    "    /* 6. Corner vignette. */\n"
    "    vec2 vig = (uv - 0.5) * 2.0;\n"
    "    result *= clamp(1.0 - dot(vig, vig) * 0.20, 0.0, 1.0);\n"
    "    o_color = vec4(result, 1.0);\n"
    "}\n";

/* ------------------------------------------------------------------- */
/* GL helpers                                                          */
/* ------------------------------------------------------------------- */
static GLuint compile_shader(GLenum type, const char *src) {
    GLuint s = _glCreateShader(type);
    _glShaderSource(s, 1, &src, NULL);
    _glCompileShader(s);
    GLint ok = 0;
    _glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        _glGetShaderInfoLog(s, sizeof(log), NULL, log);
        fprintf(stderr, "[video] shader compile failed (%s):\n%s\n",
                type == GL_VERTEX_SHADER ? "VS" : "FS", log);
        _glDeleteShader(s);
        return 0;
    }
    return s;
}

static GLuint link_program(GLuint vs, GLuint fs) {
    GLuint p = _glCreateProgram();
    _glAttachShader(p, vs);
    _glAttachShader(p, fs);
    _glLinkProgram(p);
    GLint ok = 0;
    _glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[1024];
        _glGetProgramInfoLog(p, sizeof(log), NULL, log);
        fprintf(stderr, "[video] program link failed:\n%s\n", log);
        _glDeleteProgram(p);
        return 0;
    }
    return p;
}

/* ------------------------------------------------------------------- */
/* video_t                                                             */
/* ------------------------------------------------------------------- */
struct video {
    SDL_Window   *win;

    /* OpenGL 3.3 core backend (preferred). */
    SDL_GLContext gl_ctx;
    GLuint        program;
    GLuint        vao;
    GLuint        tex;
    GLint         u_tex;
    GLint         u_tex_size;
    GLint         u_crt;
    GLint         u_zoom;       /* symmetric inset factor (0..0.5)             */

    /* SDL_Renderer fallback for GPUs without GL 3.3 core. No shader, so
     * the CRT toggle becomes a visual no-op (the bool still tracks state
     * in case the user toggles it from main.c -- harmless either way). */
    SDL_Renderer *renderer;
    SDL_Texture  *renderer_tex;
    bool          use_renderer;

    int           win_w, win_h;
    int           tex_w, tex_h;            /* allocated texture size       */
    int           last_vis_w, last_vis_h;  /* most recent visible content  */
    uint32_t     *upload_buf;              /* RGBA conversion scratch      */
    size_t        upload_buf_cap;
    bool          crt_enabled;
    float         zoom;                    /* UV inset 0..0.5 (0 = no crop) */
    bool          paused;
    const uint8_t *font;                   /* 768-byte 8x8 font, NULL = no label */
    char          msg_text[33];            /* current OSD message + NUL    */
    Uint32        msg_expires_ticks;       /* SDL_GetTicks() value at fade */
    const char   *help_text;               /* persistent help, NULL = hidden */
};

/* The PAUSE label is composited into the upload buffer at SOURCE pixel
 * resolution before the GPU sees it. 1 glyph pixel = 1 Spectrum pixel,
 * so once GL_LINEAR (X-axis only), scanlines, mask, vignette and
 * curvature apply, the label is processed identically to any other
 * Spectrum pixel -- it ends up looking like the system itself wrote it.
 *
 * Position math: chips emits a 320 x 256 visible area where the 256 x 192
 * actual Spectrum screen sits centred with a 32-pixel border on every
 * side. Inside that screen the Spectrum font runs on a 32 x 24 grid of
 * 8 x 8 character cells. So a `PRINT AT R, C; "..."` lands at framebuffer
 * pixel (32 + 8*C, 32 + 8*R). For a centred 5-char "PAUSE" we use
 * column 13, row 11 -- the same coordinates a BASIC program would.
 */
#define ZX_BORDER      32
#define ZX_CHAR_SIZE   8
#define ZX_SCREEN_COLS 32
#define ZX_SCREEN_ROWS 24
#define PAUSE_COLS     5
#define PAUSE_TEXT_W   (PAUSE_COLS * ZX_CHAR_SIZE)
#define PAUSE_TEXT_H   ZX_CHAR_SIZE
#define PAUSE_AT_COL   ((ZX_SCREEN_COLS - PAUSE_COLS) / 2) /* = 13 */
#define PAUSE_AT_ROW   ((ZX_SCREEN_ROWS - 1) / 2)          /* = 11 */

/* Two rows below the PAUSE label so a 'PAUSE' + 'ESC AGAIN TO EXIT'
 * stack reads as a natural two-line dialog with a clear blank line
 * between them. Earlier choice (row 22, near the bottom border) felt
 * disconnected from the PAUSE label when both happened to be on. */
#define OSD_MSG_ROW (PAUSE_AT_ROW + 2)

static const char PAUSE_WORD[PAUSE_COLS] = { 'P', 'A', 'U', 'S', 'E' };

/* Multiply every RGB component of the visible area by ~0.352 (90/256).
 * Used to make the picture recede behind overlays. */
static void apply_dim(uint32_t *buf, int vis_w, int vis_h) {
    const size_t n = (size_t)vis_w * vis_h;
    for (size_t i = 0; i < n; i++) {
        const uint32_t c = buf[i];
        const uint32_t r = ((c      ) & 0xFFu) * 90u >> 8;
        const uint32_t g = ((c >>  8) & 0xFFu) * 90u >> 8;
        const uint32_t b = ((c >> 16) & 0xFFu) * 90u >> 8;
        buf[i] = 0xFF000000u | (b << 16) | (g << 8) | r;
    }
}

/* Paint the whole visible area opaque black. Used when an overlay wants
 * the game completely hidden (e.g., the help screen). */
static void apply_clear_black(uint32_t *buf, int vis_w, int vis_h) {
    const size_t n = (size_t)vis_w * vis_h;
    for (size_t i = 0; i < n; i++) buf[i] = 0xFF000000u;
}

/* Render `len` characters from `line` at the (col, row) Spectrum-grid
 * position. Black paper + white ink, like a BASIC PRINT. Clipped if the
 * line would run off the right edge of the screen. */
static void compose_line(uint32_t *buf, int vis_w, int vis_h,
                         const uint8_t *font_768,
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
    const int text_h = ZX_CHAR_SIZE;
    if (text_x + text_w > vis_w || text_y + text_h > vis_h) return;

    for (int row = 0; row < text_h; row++) {
        uint32_t *dst_row = buf + (size_t)(text_y + row) * vis_w;
        for (int col = 0; col < text_w; col++) {
            const int letter        = col / ZX_CHAR_SIZE;
            const int col_in_letter = col % ZX_CHAR_SIZE;
            const unsigned char ch  = (unsigned char)line[letter];
            uint8_t bits = 0;
            if (ch >= 0x20 && ch < 0x80) {
                bits = font_768[(ch - 0x20) * 8 + row];
            }
            const bool on         = (bits >> (7 - col_in_letter)) & 1;
            dst_row[text_x + col] = on ? 0xFFFFFFFFu : 0xFF000000u;
        }
    }
}

/* The PAUSE word: 5 cells starting at PRINT AT PAUSE_AT_ROW, PAUSE_AT_COL. */
static void compose_pause_overlay(uint32_t *buf, int vis_w, int vis_h,
                                  const uint8_t *font_768, bool blink_on)
{
    if (!blink_on) return;
    compose_line(buf, vis_w, vis_h, font_768,
                 PAUSE_AT_COL, PAUSE_AT_ROW, PAUSE_WORD, PAUSE_COLS);
}

/* Single-line OSD at the bottom, centred. */
static void compose_msg_overlay(uint32_t *buf, int vis_w, int vis_h,
                                const uint8_t *font_768, const char *msg)
{
    if (!msg || !*msg) return;
    int len = (int)strlen(msg);
    if (len > ZX_SCREEN_COLS) len = ZX_SCREEN_COLS;
    const int col0 = (ZX_SCREEN_COLS - len) / 2;
    compose_line(buf, vis_w, vis_h, font_768, col0, OSD_MSG_ROW, msg, len);
}

/* Length of one line up to the next '\n' (or string end). */
static int line_len(const char *cursor) {
    const char *eol = strchr(cursor, '\n');
    return eol ? (int)(eol - cursor) : (int)strlen(cursor);
}

/* Multi-line help screen centred on the Spectrum grid.
 *
 * Layout policy:
 *   - Line 0 (title): centred on its own length.
 *   - Lines 1..N (body): left-aligned at a common column so they share
 *     one left edge. The body block as a whole is then centred on
 *     screen by computing the column from the widest body line:
 *     body_col = (32 - max_body_w) / 2.
 *
 * Caller is expected to have already invoked apply_dim() (or
 * apply_clear_black()) -- we don't touch the background here so the
 * same function works on a paused / black / live frame. */
static void compose_help_overlay(uint32_t *buf, int vis_w, int vis_h,
                                 const uint8_t *font_768, const char *help)
{
    if (!font_768 || !help || !*help) return;

    /* Total line count = 1 + number of '\n'. */
    int num_lines = 1;
    for (const char *p = help; *p; p++) if (*p == '\n') num_lines++;

    int start_row = (ZX_SCREEN_ROWS - num_lines) / 2;
    if (start_row < 0) start_row = 0;

    /* Pass 1: widest body line determines the body-block left column. */
    int max_body_w = 0;
    {
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

    /* Pass 2: render. */
    const char *cursor = help;
    for (int i = 0; i < num_lines; i++) {
        int len = line_len(cursor);
        if (len > ZX_SCREEN_COLS) len = ZX_SCREEN_COLS;

        const int col = (i == 0)
            ? (ZX_SCREEN_COLS - len) / 2       /* title centred           */
            : body_col;                        /* body left-aligned block */
        compose_line(buf, vis_w, vis_h, font_768,
                     col, start_row + i, cursor, len);

        const char *eol = strchr(cursor, '\n');
        cursor = eol ? eol + 1 : cursor + len;
    }
}

/* Returns true on success and populates v->gl_ctx + GL state. On failure,
 * tears down any GL state it created (so the caller can try a different
 * backend) but leaves v itself intact. */
static bool try_init_gl(video_t *v) {
    /* Request OpenGL 3.3 core BEFORE the context exists. */
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
#ifdef __APPLE__
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
#endif
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    v->gl_ctx = SDL_GL_CreateContext(v->win);
    if (!v->gl_ctx) {
        fprintf(stderr, "[video] SDL_GL_CreateContext: %s\n", SDL_GetError());
        return false;
    }
    SDL_GL_MakeCurrent(v->win, v->gl_ctx);
    SDL_GL_SetSwapInterval(0); /* main loop paces to 50 Hz manually */

    /* Some drivers silently hand back a GL 1.1 fallback context when 3.3
     * core can't be honoured (Mesa GDI on Windows, ancient Intel, RDP
     * sessions...). The function loader catches that since none of the
     * modern entry points exist there. */
    if (!load_gl_funcs()) {
        SDL_GL_DeleteContext(v->gl_ctx);
        v->gl_ctx = NULL;
        return false;
    }

    /* Shaders & program */
    GLuint vs = compile_shader(GL_VERTEX_SHADER,   VS_SRC);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, FS_SRC);
    if (!vs || !fs) {
        if (vs) _glDeleteShader(vs);
        if (fs) _glDeleteShader(fs);
        SDL_GL_DeleteContext(v->gl_ctx);
        v->gl_ctx = NULL;
        return false;
    }
    v->program = link_program(vs, fs);
    _glDeleteShader(vs);
    _glDeleteShader(fs);
    if (!v->program) {
        SDL_GL_DeleteContext(v->gl_ctx);
        v->gl_ctx = NULL;
        return false;
    }
    v->u_tex      = _glGetUniformLocation(v->program, "u_tex");
    v->u_tex_size = _glGetUniformLocation(v->program, "u_tex_size");
    v->u_crt      = _glGetUniformLocation(v->program, "u_crt");
    v->u_zoom     = _glGetUniformLocation(v->program, "u_zoom");

    /* Empty VAO (core profile requires one bound when drawing). */
    _glGenVertexArrays(1, &v->vao);

    /* Streaming texture: 320x256 covers any sane visible area chips emits. */
    glGenTextures(1, &v->tex);
    glBindTexture(GL_TEXTURE_2D, v->tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, v->tex_w, v->tex_h, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    /* GL_LINEAR mag/min gives free bilinear interpolation when the
     * shader samples between texel centres. The fragment shader picks
     * its sample positions to use this only on the X axis (smooths
     * horizontal upscale) while keeping Y locked to row centres
     * (preserves the source-pixel scanline structure). */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_CLAMP_TO_EDGE);

    /* Initial viewport. */
    SDL_GL_GetDrawableSize(v->win, &v->win_w, &v->win_h);
    glViewport(0, 0, v->win_w, v->win_h);

    fprintf(stderr, "[video] GL %s on %s\n",
            glGetString(GL_VERSION),  glGetString(GL_RENDERER));
    return true;
}

/* SDL_Renderer fallback for ancient / broken GL stacks. Tries accelerated
 * first (D3D9 on Windows, GL2/GLES on Linux, Metal on macOS) and falls
 * back to software, which always works. No shader -> no CRT effect; the
 * frame is just bilinear-scaled to fill the window with letterboxing.
 *
 * Why this works on a window created with SDL_WINDOW_OPENGL: that flag
 * only sets up the window's pixel format. SDL2's non-GL renderer drivers
 * (direct3d, software) don't care and will create their own present path.
 * On the few drivers that do care, software is the catch-all. */
static bool try_init_renderer(video_t *v) {
    /* Prefer linear filtering on the upscale so 320x256 stretched to
     * 1080p doesn't look like blocky LEGO. SDL2 wants this set BEFORE
     * SDL_CreateTexture; the texture captures the hint at create time. */
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");

    v->renderer = SDL_CreateRenderer(v->win, -1,
                                     SDL_RENDERER_ACCELERATED |
                                     SDL_RENDERER_PRESENTVSYNC);
    if (!v->renderer) {
        v->renderer = SDL_CreateRenderer(v->win, -1, SDL_RENDERER_ACCELERATED);
    }
    if (!v->renderer) {
        v->renderer = SDL_CreateRenderer(v->win, -1, SDL_RENDERER_SOFTWARE);
    }
    if (!v->renderer) {
        fprintf(stderr, "[video] SDL_CreateRenderer: %s\n", SDL_GetError());
        return false;
    }

    SDL_RendererInfo info;
    if (SDL_GetRendererInfo(v->renderer, &info) == 0) {
        fprintf(stderr, "[video] SDL_Renderer driver: %s (CRT shader disabled)\n",
                info.name);
    }

    v->renderer_tex = SDL_CreateTexture(v->renderer,
                                        SDL_PIXELFORMAT_RGBA32,
                                        SDL_TEXTUREACCESS_STREAMING,
                                        v->tex_w, v->tex_h);
    if (!v->renderer_tex) {
        fprintf(stderr, "[video] SDL_CreateTexture: %s\n", SDL_GetError());
        SDL_DestroyRenderer(v->renderer);
        v->renderer = NULL;
        return false;
    }

    SDL_GetWindowSize(v->win, &v->win_w, &v->win_h);
    v->use_renderer = true;
    return true;
}

video_t *video_create(SDL_Window *win) {
    if (!win) return NULL;

    video_t *v = (video_t *)calloc(1, sizeof(*v));
    if (!v) return NULL;
    v->win            = win;
    v->crt_enabled    = true;
    v->tex_w          = 320;
    v->tex_h          = 256;
    v->upload_buf_cap = (size_t)v->tex_w * v->tex_h * sizeof(uint32_t);
    v->upload_buf     = (uint32_t *)malloc(v->upload_buf_cap);
    if (!v->upload_buf) { free(v); return NULL; }

    if (try_init_gl(v)) return v;

    fprintf(stderr, "[video] modern GL unavailable -- trying SDL_Renderer fallback\n");
    if (try_init_renderer(v)) return v;

    fprintf(stderr, "[video] every backend failed; the wrapper cannot render\n");
    free(v->upload_buf);
    free(v);
    return NULL;
}

void video_destroy(video_t *v) {
    if (!v) return;
    if (v->use_renderer) {
        if (v->renderer_tex) SDL_DestroyTexture(v->renderer_tex);
        if (v->renderer)     SDL_DestroyRenderer(v->renderer);
    } else if (v->gl_ctx) {
        SDL_GL_MakeCurrent(v->win, v->gl_ctx);
        if (v->tex)     glDeleteTextures(1, &v->tex);
        if (v->vao)     _glDeleteVertexArrays(1, &v->vao);
        if (v->program) _glDeleteProgram(v->program);
        SDL_GL_DeleteContext(v->gl_ctx);
    }
    free(v->upload_buf);
    free(v);
}

void video_set_paused(video_t *v, bool paused) {
    if (v) v->paused = paused;
}

void video_set_pause_font(video_t *v, const uint8_t *font) {
    if (v) v->font = font;
}

void video_show_msg(video_t *v, const char *text, int duration_ms) {
    if (!v) return;
    if (!text || !*text || duration_ms <= 0) {
        v->msg_text[0]        = '\0';
        v->msg_expires_ticks  = 0;
        return;
    }
    const size_t cap = sizeof(v->msg_text) - 1;
    size_t n = strlen(text);
    if (n > cap) n = cap;
    memcpy(v->msg_text, text, n);
    v->msg_text[n] = '\0';
    v->msg_expires_ticks = SDL_GetTicks() + (Uint32)duration_ms;
}

void video_set_help(video_t *v, const char *text) {
    if (v) v->help_text = text;
}

bool video_help_visible(const video_t *v) {
    return v && v->help_text != NULL;
}

void video_resize(video_t *v, int width, int height) {
    if (!v || width <= 0 || height <= 0) return;
    v->win_w = width;
    v->win_h = height;
}

void video_set_crt(video_t *v, bool enabled) {
    if (v) v->crt_enabled = enabled;
}

bool video_crt(const video_t *v) {
    return v ? v->crt_enabled : false;
}

void video_set_zoom(video_t *v, float zoom) {
    if (!v) return;
    if (zoom < 0.0f) zoom = 0.0f;
    if (zoom > 0.45f) zoom = 0.45f;   /* avoid degenerate (1 - 2z) == 0 */
    v->zoom = zoom;
}

/* Standard Spectrum palette, RGBA in memory order on LE (matches chips
 * and the GL_RGBA texture format we use). 0..7 = std, 8..15 = bright. */
static const uint32_t SPECTRUM_PALETTE[16] = {
    0xFF000000u, 0xFFD70000u, 0xFF0000D7u, 0xFFD700D7u,
    0xFF00D700u, 0xFFD7D700u, 0xFF00D7D7u, 0xFFD7D7D7u,
    0xFF000000u, 0xFFFF0000u, 0xFF0000FFu, 0xFFFF00FFu,
    0xFF00FF00u, 0xFFFFFF00u, 0xFF00FFFFu, 0xFFFFFFFFu,
};

/* Push the assembled v->upload_buf onto whichever backend texture is
 * live. Shared by video_upload and video_upload_splash so the only
 * branch on backend lives here. */
static void backend_upload_texture(video_t *v, int vis_w, int vis_h) {
    if (v->use_renderer) {
        const SDL_Rect r = {0, 0, vis_w, vis_h};
        SDL_UpdateTexture(v->renderer_tex, &r,
                          v->upload_buf, vis_w * (int)sizeof(uint32_t));
    } else {
        glBindTexture(GL_TEXTURE_2D, v->tex);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vis_w, vis_h,
                        GL_RGBA, GL_UNSIGNED_BYTE, v->upload_buf);
    }
}

void video_upload_splash(video_t *v, const uint8_t *pixel_bytes,
                         const uint8_t *attr_bytes)
{
    if (!v || !pixel_bytes || !attr_bytes) return;

    const int vis_w = v->tex_w;          /* 320 */
    const int vis_h = v->tex_h;          /* 256 */
    uint32_t *dst   = v->upload_buf;

    /* Black border first; splash is centred over it. */
    apply_clear_black(dst, vis_w, vis_h);

    /* Spectrum screen lives at (32, 32) inside the 320x256 visible area
     * (32-pixel border on every side around the 256x192 picture). */
    const int OFF_X = ZX_BORDER;
    const int OFF_Y = ZX_BORDER;

    /* BG editor stores sprites as row-major linear bitmaps (32 bytes
     * per row of 256 pixels, 192 rows = 6144 bytes), not in the
     * Spectrum's interleaved VRAM layout. So for pixel (px, py):
     *   row byte offset = py * 32
     *   col byte        = (px >> 3)
     *   bit (MSB-first) = 7 - (px & 7)
     * Attribute cells are still 8x8: attr_bytes[(py/8) * 32 + (px/8)],
     * with bits 0..2 INK, 3..5 PAPER, 6 BRIGHT, 7 FLASH (ignored). */
    for (int py = 0; py < 192; py++) {
        const int row_offset = py * 32;
        const int char_row   = py >> 3;
        uint32_t *dst_row    = dst + (size_t)(OFF_Y + py) * vis_w + OFF_X;

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

    /* Standard tracking + upload so overlays / present logic work as
     * with a normal game frame (overlays are still composited on top). */
    v->last_vis_w = vis_w;
    v->last_vis_h = vis_h;

    backend_upload_texture(v, vis_w, vis_h);
}

void video_upload(video_t *v,
                  const uint8_t  *fb,
                  int             fb_stride,
                  int             vis_width,
                  int             vis_height,
                  const uint32_t *palette) {
    if (!v || !fb || !palette) return;
    if (vis_width  > v->tex_w) vis_width  = v->tex_w;
    if (vis_height > v->tex_h) vis_height = v->tex_h;

    /* Palette index -> RGBA in CPU scratch (chips palette is already in
     * RGBA byte order on little-endian hosts, so we just copy). */
    for (int y = 0; y < vis_height; y++) {
        const uint8_t *src = fb + (size_t)y * fb_stride;
        uint32_t      *dst = v->upload_buf + (size_t)y * vis_width;
        for (int x = 0; x < vis_width; x++) {
            dst[x] = palette[src[x] & 0x0F];
        }
    }
    v->last_vis_w = vis_width;
    v->last_vis_h = vis_height;

    /* Overlays composited at source-pixel granularity so once the GPU
     * pipeline applies bilinear, scanlines, mask, vignette and tube
     * curvature, every overlay is treated identically to game pixels
     * and blends into the picture instead of sitting on top of it.
     *
     * Background:
     *   - help up: paint the visible area opaque black (game fully
     *     hidden -- help screen is the only thing visible)
     *   - else if paused: dim the game to ~35 % brightness
     *   - else: leave the game alone
     *
     * Then overlays in z-order: PAUSE label (only when paused AND no
     * help, to avoid colliding mid-screen with the help block), the
     * help screen itself, the transient OSD message. */
    if (v->help_text) {
        apply_clear_black(v->upload_buf, vis_width, vis_height);
    } else if (v->paused) {
        apply_dim(v->upload_buf, vis_width, vis_height);
    }
    if (v->paused && !v->help_text) {
        const Uint32 t        = SDL_GetTicks();
        const bool   blink_on = ((t / 400u) % 2u == 0u);
        compose_pause_overlay(v->upload_buf, vis_width, vis_height,
                              v->font, blink_on);
    }
    if (v->help_text) {
        compose_help_overlay(v->upload_buf, vis_width, vis_height,
                             v->font, v->help_text);
    }
    if (v->msg_text[0] && SDL_GetTicks() < v->msg_expires_ticks) {
        compose_msg_overlay(v->upload_buf, vis_width, vis_height,
                            v->font, v->msg_text);
    }

    backend_upload_texture(v, vis_width, vis_height);
}

/* Letterbox the source aspect ratio (5:4) inside the window. Black bars
 * fill the rest. Shared by the GL and SDL_Renderer paths. */
static void compute_letterbox(int win_w, int win_h,
                              int src_w, int src_h,
                              int *vp_x, int *vp_y,
                              int *vp_w, int *vp_h)
{
    const float src_aspect = (float)src_w / (float)src_h;
    const float win_aspect = (float)win_w / (float)win_h;
    *vp_w = win_w;
    *vp_h = win_h;
    *vp_x = 0;
    *vp_y = 0;
    if (win_aspect > src_aspect) {
        *vp_w = (int)(win_h * src_aspect);
        *vp_x = (win_w - *vp_w) / 2;
    } else if (win_aspect < src_aspect) {
        *vp_h = (int)(win_w / src_aspect);
        *vp_y = (win_h - *vp_h) / 2;
    }
}

void video_present(video_t *v) {
    if (!v) return;

    if (v->use_renderer) {
        /* SDL_Renderer path: no shader, no CRT. SDL_RenderCopy with a
         * letterboxed dst rect; SDL handles the bilinear upscale per
         * the RENDER_SCALE_QUALITY hint set in try_init_renderer. */
        SDL_GetWindowSize(v->win, &v->win_w, &v->win_h);

        int vp_x, vp_y, vp_w, vp_h;
        compute_letterbox(v->win_w, v->win_h,
                          v->last_vis_w, v->last_vis_h,
                          &vp_x, &vp_y, &vp_w, &vp_h);

        SDL_SetRenderDrawColor(v->renderer, 0, 0, 0, 255);
        SDL_RenderClear(v->renderer);
        const SDL_Rect src = {0, 0, v->last_vis_w, v->last_vis_h};
        const SDL_Rect dst = {vp_x, vp_y, vp_w, vp_h};
        SDL_RenderCopy(v->renderer, v->renderer_tex, &src, &dst);
        SDL_RenderPresent(v->renderer);
        return;
    }

    /* GL path. Re-fetch drawable size each frame: handles DPI changes /
     * move between monitors / fullscreen toggle without explicit event
     * work. */
    SDL_GL_GetDrawableSize(v->win, &v->win_w, &v->win_h);

    int vp_x, vp_y, vp_w, vp_h;
    compute_letterbox(v->win_w, v->win_h,
                      v->last_vis_w, v->last_vis_h,
                      &vp_x, &vp_y, &vp_w, &vp_h);

    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glViewport(0, 0, v->win_w, v->win_h);
    glClear(GL_COLOR_BUFFER_BIT);

    glViewport(vp_x, vp_y, vp_w, vp_h);

    _glUseProgram(v->program);
    _glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, v->tex);
    _glUniform1i(v->u_tex,      0);
    _glUniform2f(v->u_tex_size, (float)v->last_vis_w, (float)v->last_vis_h);
    _glUniform1i(v->u_crt,      v->crt_enabled ? 1 : 0);
    _glUniform1f(v->u_zoom,     v->zoom);

    _glBindVertexArray(v->vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);

    SDL_GL_SwapWindow(v->win);
}
