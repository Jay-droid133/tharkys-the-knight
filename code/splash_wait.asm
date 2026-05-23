; ==============================================================================
; splash_wait.asm - prompt animado (tecla + botón) tras carga de cinta.
; ==============================================================================
; Tras la carga del TAP, el SCREEN$ con bg257 ya está pintado en VRAM por el
; BASIC loader (LOAD ""SCREEN$). Aquí pintamos dos iconos 16x16 en filas char
; 22-23 — una tecla pulsándose (frames A=40, B=178) y un botón pulsándose
; (frames A=171, B=172) — que alternan cada ~160 ms. Esperamos cualquier tecla
; del teclado o el botón/dir del Kempston. Detección Kempston defensiva: si el
; puerto $1F devuelve todos los bits a 1 (bus flotante en HW real sin
; interface), se ignora.
;
; Datos pre-renderizados desde tools/build_tap_with_splash.py:
;   splash_prompt.bin = 128 B pixels (4 sprites × 32 B) + 8 B attrs (2 × 4 B).
;   Layout:  [0..31]=keyA  [32..63]=keyB  [64..95]=btnA  [96..127]=btnB
;            [128..131]=keyAttrs  [132..135]=btnAttrs
;
; Vive en slot 1 (bank 5). Solo se ejecuta una vez en el boot; después se
; sobreescribe naturalmente por el flujo normal del juego.
; ==============================================================================

; --- Posiciones VRAM (top-left de cada icono 16x16) ---------------------------
; Iconos centrados aprox.: tecla cols 13-14, botón cols 17-18 (gap 2 chars).
; Fila char 22 = pixel y=176 → vram_pixel_addr(col, 176) = $50C0 | col.
SPLASH_KEY_PX_ADDR   EQU $50C0 + 13                  ; = $50CD
SPLASH_BTN_PX_ADDR   EQU $50C0 + 17                  ; = $50D1
SPLASH_KEY_ATTR_TOP  EQU $5800 + 22*32 + 13          ; = $5ACD
SPLASH_KEY_ATTR_BOT  EQU SPLASH_KEY_ATTR_TOP + 32    ; = $5AED
SPLASH_BTN_ATTR_TOP  EQU $5800 + 22*32 + 17          ; = $5AD1
SPLASH_BTN_ATTR_BOT  EQU SPLASH_BTN_ATTR_TOP + 32    ; = $5AF1

; --- Offsets dentro de splash_prompt.bin -------------------------------------
SPLASH_KEY_PX_A      EQU 0
SPLASH_KEY_PX_B      EQU 32
SPLASH_BTN_PX_A      EQU 64
SPLASH_BTN_PX_B      EQU 96

; Bit del system frame counter ($5C78) que controla la cadencia de la
; animación. Bit 3 → cambia cada 8 frames a 50 Hz ≈ 160 ms (pulsación viva).
SPLASH_ANIM_BIT      EQU $08

; ------------------------------------------------------------------------------
; SplashWait - pinta attrs, anima iconos, espera pulsación + debounce.
; IN:  -
; OUT: -
; Destruye: AF, BC, DE, HL.
; ------------------------------------------------------------------------------
SplashWait:
    ; --- Pintar attrs de los dos iconos (4 B cada uno, 2x2 chars) ---
    ; Orden en bg_sprites.json: [TL, TR, BL, BR] (row-major 2x2).
    LD HL, SplashKeyAttrs
    LD DE, SPLASH_KEY_ATTR_TOP
    LD BC, 2
    LDIR                                                ; TL, TR
    LD DE, SPLASH_KEY_ATTR_BOT
    LD BC, 2
    LDIR                                                ; BL, BR
    LD HL, SplashBtnAttrs
    LD DE, SPLASH_BTN_ATTR_TOP
    LD BC, 2
    LDIR
    LD DE, SPLASH_BTN_ATTR_BOT
    LD BC, 2
    LDIR

    ; --- Forzar pintado en la primera vuelta del loop ---
    LD A, $FF
    LD (SplashPrevAnimBit), A

    ; --- Idle inicial: descarta input residual del LOAD ("J"/ENTER, etc.) ---
    ; En cada iter llamamos a PrefetchMusic: la música EndGame (track 2) vive
    ; en bank 7 y el IRQ a 25 Hz consume notas del buffer slot 1; PrefetchMusic
    ; rellena el buffer cuando el handler setea MusicNeedPrefetch=1. Es no-op
    ; si no hay nada que rellenar, así que llamarlo en cada poll es barato.
.spwInitIdle:
    CALL PrefetchMusic
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .spwInitIdle

    ; --- Esperar pulsación real ---
.spwWaitPress:
    CALL PrefetchMusic
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR Z, .spwWaitPress

    ; --- Debounce: esperar release antes de continuar (con animación) ---
.spwWaitRelease:
    CALL PrefetchMusic
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .spwWaitRelease
    RET

; ------------------------------------------------------------------------------
; UpdateSplashAnim - alterna frames de los dos iconos cuando toca.
; ------------------------------------------------------------------------------
; Lee el bit SPLASH_ANIM_BIT del system frame counter $5C78 que el
; MusicIrqHandler mantiene actualizado a 50 Hz. Si cambió respecto a la última
; pasada, repinta ambos iconos con el frame correspondiente; si no, RET.
; Destruye: AF, BC, DE, HL.
; ------------------------------------------------------------------------------
UpdateSplashAnim:
    LD A, ($5C78)
    AND SPLASH_ANIM_BIT
    LD HL, SplashPrevAnimBit
    CP (HL)
    RET Z                                               ; sin cambio
    LD (HL), A
    OR A
    JR Z, .uspaFrameA
.uspaFrameB:
    LD DE, SplashIconPixels + SPLASH_KEY_PX_B
    LD HL, SPLASH_KEY_PX_ADDR
    CALL PaintIcon16x16
    LD DE, SplashIconPixels + SPLASH_BTN_PX_B
    LD HL, SPLASH_BTN_PX_ADDR
    JP PaintIcon16x16
.uspaFrameA:
    LD DE, SplashIconPixels + SPLASH_KEY_PX_A
    LD HL, SPLASH_KEY_PX_ADDR
    CALL PaintIcon16x16
    LD DE, SplashIconPixels + SPLASH_BTN_PX_A
    LD HL, SPLASH_BTN_PX_ADDR
    JP PaintIcon16x16

; ------------------------------------------------------------------------------
; PaintIcon16x16 - escribe 16x16 px row-major en VRAM.
; ------------------------------------------------------------------------------
; IN:  DE = src pixels (32 B, row-major: y0_b0, y0_b1, y1_b0, y1_b1, ...)
;      HL = VRAM addr top-left
; Destruye: AF, B, DE, HL.
; ------------------------------------------------------------------------------
; NextPixelLine vive en bank 2 slot 2 (always-visible junto con engine_graphics),
; así que el CALL desde slot 1 funciona sin paginar nada.
PaintIcon16x16:
    LD B, 16
.pi16Row:
    LD A, (DE)
    LD (HL), A                                          ; byte 0 (col)
    INC DE
    INC L                                               ; col+1 (no cruza char)
    LD A, (DE)
    LD (HL), A                                          ; byte 1 (col+1)
    INC DE
    DEC L                                               ; restaurar col
    CALL NextPixelLine                                  ; HL → siguiente row pixel
    DJNZ .pi16Row
    RET

; ------------------------------------------------------------------------------
; SplashCheckInput - polling no-bloqueante.
; OUT: A=0 / Z   → ningún input activo
;      A!=0 / NZ → pulsación detectada (Kempston o teclado)
; Destruye: A, BC.
; ------------------------------------------------------------------------------
; Kempston puerto $1F (bits 0..4 = right/left/down/up/fire). Sin interface
; el bus queda flotante; muchos emus devuelven $FF. Si la lectura sale con
; los 5 bits a 1 la ignoramos (no es una pulsación real, es bus libre).
; Teclado: LD BC,$00FE; IN A,(C) hace el wired-OR de todas las half-rows;
; CPL e inviertes para que bit=1 sea "pulsada", y AND $1F descarta CAPS/SYM.
; ------------------------------------------------------------------------------
SplashCheckInput:
    IN A, ($1F)
    AND $1F
    CP $1F
    JR Z, .scikbd                                       ; bus flotante → ignorar
    OR A
    RET NZ                                              ; Kempston pulsado
.scikbd:
    LD BC, $00FE
    IN A, (C)
    CPL
    AND $1F
    RET                                                 ; Z=idle, NZ=press

; ------------------------------------------------------------------------------
; Datos pre-renderizados (generados por tools/build_tap_with_splash.py).
; Layout del .bin: [128 B pixels][8 B attrs].
; ------------------------------------------------------------------------------
SplashIconPixels:
    INCBIN "splash_prompt.bin", 0, 128
SplashKeyAttrs:
    INCBIN "splash_prompt.bin", 128, 4
SplashBtnAttrs:
    INCBIN "splash_prompt.bin", 132, 4
SplashPromptEnd:

; ------------------------------------------------------------------------------
; SplashPrevAnimBit: estado del bit de animación leído en la pasada anterior.
; Inicia en $FF (valor imposible tras AND con SPLASH_ANIM_BIT) para forzar el
; primer pintado. Lo mantiene UpdateSplashAnim.
SplashPrevAnimBit: DEFB $FF

; ------------------------------------------------------------------------------
; SplashAlreadyShown: flag persistente entre llamadas a Inicio.
; ------------------------------------------------------------------------------
; Boot fresco desde TAP: el byte se emite en bank 5 (slot 1) inicializado a 0.
; Tras la primera pulsacion del splash se pone a 1. GameOver -> SPACE -> JP
; Inicio reentra sin pasar por el TAP loader, y el zero-fill de low-RAM ($5D00+)
; NO afecta esta var porque vive en bank 5 ORG $6000+ (slot 1 always-visible
; pero fuera de la zona zero-fileada). Asi el reinicio post-game-over salta el
; splash y la musica EndGame, yendo directo al gameplay.
SplashAlreadyShown: DEFB 0
