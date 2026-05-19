; ==============================================================================
; splash_wait.asm - prompt 'PRESS ANY KEY / BUTTON' tras carga de cinta.
; ==============================================================================
; Tras la carga del TAP, el SCREEN$ con bg257 ya está pintado en VRAM por
; el BASIC loader (LOAD ""SCREEN$). Aquí pintamos el prompt en fila 22 y
; esperamos cualquier tecla del teclado completo o el botón fire/dir del
; Kempston. Detección Kempston defensiva: si el puerto $1F devuelve todos
; los bits a 1 (bus flotante en HW real sin interface), se ignora.
;
; Datos del prompt pre-renderizados desde tools/build_tap_with_splash.py:
;   splash_prompt.bin = 176 B pixels (8 filas pixel × 22 chars) + 22 B attrs.
;
; Vive en slot 1 (bank 5). Solo se ejecuta una vez en el boot; después
; se sobreescribe naturalmente por el flujo normal del juego.
; ==============================================================================

SPLASH_PROMPT_LEN   EQU 22                              ; chars en la fila
SPLASH_PIXELS_ADDR  EQU $50C5                           ; row char 22, col 5
SPLASH_ATTRS_ADDR   EQU $5800 + 22*32 + 5               ; = $5AC5
SPLASH_PIXELS_SIZE  EQU SPLASH_PROMPT_LEN * 8           ; 176

; ------------------------------------------------------------------------------
; SplashWait - pinta prompt + espera pulsación + debounce.
; IN:  -
; OUT: -
; Destruye: AF, BC, DE, HL.
; ------------------------------------------------------------------------------
SplashWait:
    ; --- Pintar attrs ($5AC5, 22 B) ---
    LD HL, SplashPromptAttrs
    LD DE, SPLASH_ATTRS_ADDR
    LD BC, SPLASH_PROMPT_LEN
    LDIR

    ; --- Pintar pixels: 8 filas pixel de 22 B; DE += $0100 entre filas ---
    LD HL, SplashPromptPixels
    LD DE, SPLASH_PIXELS_ADDR
    LD B, 8
.spwRow:
    PUSH BC
    LD BC, SPLASH_PROMPT_LEN
    LDIR
    POP BC
    ; DE quedó en (rowStart + 22). Restaurar col y subir 1 pixel row.
    LD A, E
    SUB SPLASH_PROMPT_LEN
    LD E, A
    INC D                                               ; +$0100 = next pixel row
    DJNZ .spwRow

    ; --- Idle inicial: descarta input residual del LOAD ("J"/ENTER, etc.) ---
    ; En cada iter llamamos a PrefetchMusic: la música EndGame (track 2) vive
    ; en bank 7 y el IRQ a 25 Hz consume notas del buffer slot 1; PrefetchMusic
    ; rellena el buffer cuando el handler setea MusicNeedPrefetch=1. Es no-op
    ; si no hay nada que rellenar, así que llamarlo en cada poll es barato.
.spwInitIdle:
    CALL PrefetchMusic
    CALL SplashCheckInput
    JR NZ, .spwInitIdle

    ; --- Esperar pulsación real ---
.spwWaitPress:
    CALL PrefetchMusic
    CALL SplashCheckInput
    JR Z, .spwWaitPress

    ; --- Debounce: esperar release antes de continuar ---
.spwWaitRelease:
    CALL PrefetchMusic
    CALL SplashCheckInput
    JR NZ, .spwWaitRelease
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
; Layout del .bin: [176 B pixels][22 B attrs].
; ------------------------------------------------------------------------------
SplashPromptPixels:
    INCBIN "splash_prompt.bin", 0, SPLASH_PIXELS_SIZE
SplashPromptAttrs:
    INCBIN "splash_prompt.bin", SPLASH_PIXELS_SIZE, SPLASH_PROMPT_LEN
SplashPromptEnd:
