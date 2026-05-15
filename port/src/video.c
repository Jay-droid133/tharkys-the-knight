/*
 * video.c - OpenGL 3.3 core implementation.
 *
 * Architecture
 * ------------
 * - One 320x256 RGBA8 streaming texture holds each emulator frame.
 * - A fullscreen-triangle vertex shader (3 verts, no VBO needed) + a
 *   CRT fragment shader sample that texture and write to the backbuffer.
 * - The CRT effect is gated by a uniform so the same program handles
 *   both "raw" and "TV look" modes; toggling at runtime costs nothing.
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
        if (!_##name) { fprintf(stderr, "[video] GL function missing: %s\n", #name); missing++; }
    GL_FUNCS
    #undef X
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
    "uniform sampler2D u_pause_tex;\n"
    "uniform vec2      u_tex_size;\n"
    "uniform int       u_crt;\n"
    "uniform int       u_paused;\n"
    "uniform int       u_blink;\n"  /* 1 = label visible, 0 = off (blink) */
    "in  vec2 v_uv;\n"
    "out vec4 o_color;\n"
    "vec2 barrel(vec2 uv, float k) {\n"
    "    vec2 cc = uv - 0.5;\n"
    "    float r2 = dot(cc, cc);\n"
    "    return uv + cc * r2 * k;\n"
    "}\n"
    "/* Sample the PAUSE-label font texture, returns the [0..1] glyph\n"
    " * coverage at this fragment (0 outside the label box or off-glyph,\n"
    " * 1 fully on a glyph pixel, fractional values at edges thanks to\n"
    " * GL_LINEAR on the font texture -- that's where the blur comes from\n"
    " * so the label matches the soft-edged look of the game pixels). */\n"
    "float pause_coverage(vec2 uv_for_text) {\n"
    "    vec2 text_box = vec2(0.30, 0.075);\n"
    "    vec2 local    = (uv_for_text - vec2(0.5)) / text_box;\n"
    "    if (abs(local.x) >= 1.0 || abs(local.y) >= 1.0) return 0.0;\n"
    "    vec2 font_uv  = local * 0.5 + 0.5;\n"
    "    return texture(u_pause_tex, font_uv).a;\n"
    "}\n"
    "void main() {\n"
    "    if (u_crt == 0) {\n"
    "        /* Raw mode: just sample + maybe paste the label. No filters. */\n"
    "        vec3 col = texture(u_tex, v_uv).rgb;\n"
    "        if (u_paused == 1) {\n"
    "            col *= 0.35;\n"
    "            if (u_blink == 1) col = mix(col, vec3(1.0), pause_coverage(v_uv));\n"
    "        }\n"
    "        o_color = vec4(col, 1.0);\n"
    "        return;\n"
    "    }\n"
    "    /* 1. Tube curvature. */\n"
    "    vec2 uv = barrel(v_uv, 0.12);\n"
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
    "    /* 2b. Pause label injected into `col` BEFORE the scanline /\n"
    "     *     mask / vignette pipeline so the label inherits every\n"
    "     *     downstream filter (scanlines, RGB grille, vignette,\n"
    "     *     boost). Dim the underlying game first; bright white text\n"
    "     *     overrides where there's a glyph pixel. Uses the CURVED\n"
    "     *     uv so the label bends with the tube too. */\n"
    "    if (u_paused == 1) {\n"
    "        col *= 0.35;\n"
    "        if (u_blink == 1) col = mix(col, vec3(1.0), pause_coverage(uv));\n"
    "    }\n"
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
    "    /* 4. Aperture grille: 3-pixel-cycle R/G/B stripes at output res.\n"
    "     *    Floor at 0.78 keeps the RGB tinge legible without screaming\n"
    "     *    -- contrast 1.0/0.78 ~= 1.28 vs Hyllian's classic ~1.8. */\n"
    "    float mc   = mod(gl_FragCoord.x, 3.0);\n"
    "    vec3  mask = vec3(0.78);\n"
    "    if      (mc < 1.0) mask.r = 1.0;\n"
    "    else if (mc < 2.0) mask.g = 1.0;\n"
    "    else               mask.b = 1.0;\n"
    "    /* 5. Compose + brightness compensation. Boost trimmed (1.75 ->\n"
    "     *    1.45) because the lifted scanline floor steals less light. */\n"
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
    SDL_GLContext ctx;
    GLuint        program;
    GLuint        vao;
    GLuint        tex;
    GLuint        pause_tex;              /* 40x8 RGBA "PAUSE" font        */
    GLint         u_tex;
    GLint         u_pause_tex;
    GLint         u_tex_size;
    GLint         u_crt;
    GLint         u_paused;
    GLint         u_blink;
    int           win_w, win_h;
    int           tex_w, tex_h;            /* allocated texture size       */
    int           last_vis_w, last_vis_h;  /* most recent visible content  */
    uint32_t     *upload_buf;              /* RGBA conversion scratch      */
    size_t        upload_buf_cap;
    bool          crt_enabled;
    bool          paused;
};

/* Fallback PAUSE glyphs used when the caller hasn't provided a font yet
 * (e.g., during the initial video_create() before emu_create() has set
 * one up). 5 glyphs x 8 rows, MSB = leftmost pixel. */
static const uint8_t PAUSE_FALLBACK[5][8] = {
    /* P */ { 0x78, 0x48, 0x48, 0x78, 0x40, 0x40, 0x40, 0x00 },
    /* A */ { 0x30, 0x48, 0x48, 0x78, 0x48, 0x48, 0x48, 0x00 },
    /* U */ { 0x48, 0x48, 0x48, 0x48, 0x48, 0x48, 0x30, 0x00 },
    /* S */ { 0x38, 0x40, 0x40, 0x30, 0x08, 0x08, 0x70, 0x00 },
    /* E */ { 0x78, 0x40, 0x40, 0x70, 0x40, 0x40, 0x78, 0x00 },
};

/* Bake the 5x8 word "PAUSE" into the existing 40x8 RGBA texture. If
 * `font_768` is non-NULL it must be a 768-byte 8x8 ZX-style font (chars
 * 0x20..0x7F, MSB-first). NULL falls back to PAUSE_FALLBACK. */
static void build_pause_texture(GLuint tex, const uint8_t *font_768) {
    static const char WORD[5] = { 'P', 'A', 'U', 'S', 'E' };
    uint32_t pixels[8 * 40];
    for (int row = 0; row < 8; row++) {
        for (int col = 0; col < 40; col++) {
            const int letter        = col / 8;
            const int col_in_letter = col % 8;
            uint8_t bits;
            if (font_768) {
                const int ch_idx = (unsigned char)WORD[letter] - 0x20;
                bits = font_768[ch_idx * 8 + row];
            } else {
                bits = PAUSE_FALLBACK[letter][row];
            }
            const bool on          = (bits >> (7 - col_in_letter)) & 1;
            pixels[row * 40 + col] = on ? 0xFFFFFFFFu : 0x00000000u;
        }
    }
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 40, 8, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    /* GL_LINEAR so bilinear interpolation softens the glyph edges as the
     * 40x8 texture upscales to fill ~30% of the viewport (~12x). Matches
     * the blur the game's framebuffer texture already gets, so the label
     * doesn't read as sharp pasted vector text against a soft picture. */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_CLAMP_TO_EDGE);
}

video_t *video_create(SDL_Window *win) {
    if (!win) return NULL;

    /* Request OpenGL 3.3 core BEFORE the context exists. */
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
#ifdef __APPLE__
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
#endif
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    video_t *v = (video_t *)calloc(1, sizeof(*v));
    if (!v) return NULL;
    v->win         = win;
    v->crt_enabled = true;

    v->ctx = SDL_GL_CreateContext(win);
    if (!v->ctx) {
        fprintf(stderr, "[video] SDL_GL_CreateContext: %s\n", SDL_GetError());
        free(v);
        return NULL;
    }
    SDL_GL_MakeCurrent(win, v->ctx);
    SDL_GL_SetSwapInterval(0); /* main loop paces to 50 Hz manually */

    if (!load_gl_funcs()) {
        SDL_GL_DeleteContext(v->ctx);
        free(v);
        return NULL;
    }

    /* Shaders & program */
    GLuint vs = compile_shader(GL_VERTEX_SHADER,   VS_SRC);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, FS_SRC);
    if (!vs || !fs) {
        if (vs) _glDeleteShader(vs);
        if (fs) _glDeleteShader(fs);
        SDL_GL_DeleteContext(v->ctx);
        free(v);
        return NULL;
    }
    v->program = link_program(vs, fs);
    _glDeleteShader(vs);
    _glDeleteShader(fs);
    if (!v->program) {
        SDL_GL_DeleteContext(v->ctx);
        free(v);
        return NULL;
    }
    v->u_tex       = _glGetUniformLocation(v->program, "u_tex");
    v->u_pause_tex = _glGetUniformLocation(v->program, "u_pause_tex");
    v->u_tex_size  = _glGetUniformLocation(v->program, "u_tex_size");
    v->u_crt       = _glGetUniformLocation(v->program, "u_crt");
    v->u_paused    = _glGetUniformLocation(v->program, "u_paused");
    v->u_blink     = _glGetUniformLocation(v->program, "u_blink");

    /* Empty VAO (core profile requires one bound when drawing). */
    _glGenVertexArrays(1, &v->vao);

    /* Pause-label font texture (re-built from real Spectrum ROM font
     * once main.c calls video_set_pause_font; fallback glyphs until then
     * keep the overlay visible if anything calls video_set_paused early). */
    glGenTextures(1, &v->pause_tex);
    build_pause_texture(v->pause_tex, NULL);

    /* Streaming texture: 320x256 covers any sane visible area chips emits. */
    v->tex_w = 320;
    v->tex_h = 256;
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
    SDL_GL_GetDrawableSize(win, &v->win_w, &v->win_h);
    glViewport(0, 0, v->win_w, v->win_h);

    /* Upload scratch big enough for the texture. */
    v->upload_buf_cap = (size_t)v->tex_w * v->tex_h * sizeof(uint32_t);
    v->upload_buf    = (uint32_t *)malloc(v->upload_buf_cap);

    fprintf(stderr, "[video] GL %s on %s\n",
            glGetString(GL_VERSION),  glGetString(GL_RENDERER));
    return v;
}

void video_destroy(video_t *v) {
    if (!v) return;
    if (v->ctx) {
        SDL_GL_MakeCurrent(v->win, v->ctx);
        if (v->tex)       glDeleteTextures(1, &v->tex);
        if (v->pause_tex) glDeleteTextures(1, &v->pause_tex);
        if (v->vao)       _glDeleteVertexArrays(1, &v->vao);
        if (v->program)   _glDeleteProgram(v->program);
        SDL_GL_DeleteContext(v->ctx);
    }
    free(v->upload_buf);
    free(v);
}

void video_set_paused(video_t *v, bool paused) {
    if (v) v->paused = paused;
}

void video_set_pause_font(video_t *v, const uint8_t *font) {
    if (!v) return;
    SDL_GL_MakeCurrent(v->win, v->ctx);
    build_pause_texture(v->pause_tex, font);
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

    glBindTexture(GL_TEXTURE_2D, v->tex);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, vis_width, vis_height,
                    GL_RGBA, GL_UNSIGNED_BYTE, v->upload_buf);
}

void video_present(video_t *v) {
    if (!v) return;

    /* Re-fetch drawable size each frame: handles DPI changes / move
     * between monitors / fullscreen toggle without explicit event work. */
    SDL_GL_GetDrawableSize(v->win, &v->win_w, &v->win_h);

    /* Letterbox to the source aspect ratio (5:4). Black bars elsewhere. */
    const float src_aspect = (float)v->last_vis_w / (float)v->last_vis_h;
    const float win_aspect = (float)v->win_w     / (float)v->win_h;
    int vp_w = v->win_w, vp_h = v->win_h, vp_x = 0, vp_y = 0;
    if (win_aspect > src_aspect) {
        vp_w = (int)(v->win_h * src_aspect);
        vp_x = (v->win_w - vp_w) / 2;
    } else if (win_aspect < src_aspect) {
        vp_h = (int)(v->win_w / src_aspect);
        vp_y = (v->win_h - vp_h) / 2;
    }

    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glViewport(0, 0, v->win_w, v->win_h);
    glClear(GL_COLOR_BUFFER_BIT);

    glViewport(vp_x, vp_y, vp_w, vp_h);

    _glUseProgram(v->program);
    _glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, v->tex);
    _glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, v->pause_tex);
    /* Blink phase: 400 ms on, 400 ms off (period 800 ms, ~1.25 Hz). */
    const int blink_on = ((SDL_GetTicks() / 400u) % 2u == 0u) ? 1 : 0;
    _glUniform1i(v->u_tex,       0);
    _glUniform1i(v->u_pause_tex, 1);
    _glUniform2f(v->u_tex_size,  (float)v->last_vis_w, (float)v->last_vis_h);
    _glUniform1i(v->u_crt,       v->crt_enabled ? 1 : 0);
    _glUniform1i(v->u_paused,    v->paused ? 1 : 0);
    _glUniform1i(v->u_blink,     blink_on);

    _glBindVertexArray(v->vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);

    SDL_GL_SwapWindow(v->win);
}
