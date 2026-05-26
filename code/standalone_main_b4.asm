; ==============================================================================
; STANDALONE MAIN body - Bank 4
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Vive en bank 4 (slot 3) junto a
; bg_gfx_b.asm, ay_sound.asm y credits_font.asm.
;
; Reorganizacion (refactor B previo a F4): el body standalone (cards + render +
; glyphs) vivia en bank 1 junto al blob ZX0, pero bank 1 quedaba con 102 B
; libres y F3-F5 no caben. Bank 4 tiene 4533 B libres. Bank 1 ahora solo
; contiene blob bg_splash_zx0_data + dzx0_standard (co-located por simplicidad
; del descompresor: HL apunta al blob, ambos en bank 1).
;
; Llamado por StandaloneF1Setup (slot 1):
;   1. F1Setup pagina bank 4 en slot 3
;   2. CALL StandaloneF1Body
;   3. F1Body carga font (LDIR CreditsFontData -> BgSpriteBuffer)
;   4. Cards 0/1 (clear black + print + wait)
;   5. CALL DecompressSplashTrampoline (slot 1): pagina bank 1, descomprime
;      bg-185 a $4000, pagina bank 4 (vuelve aqui)
;   6. RET a F1Setup -> page bank 0 + restore SP + RET a caller
;
; Las rutinas Print* viven aqui; reciben HL = string en bank 4 (slot 3 = bank 4
; durante body), DE = (row, col), escriben pixels a $4000+ (slot 1 always-vis).
; ==============================================================================

; ==============================================================================
; StandaloneF1Body - 3-card splash + bg-185 decompress (F2, en bank 4)
; ==============================================================================
StandaloneF1Body:
    ; --- Wait at boot: splash de carga (sprite 185 cargado como SCREEN$ por el
    ; TAP loader) visible hasta que el usuario pulse cualquier control. En SNA
    ; dev VRAM tiene basura — el wait sigue funcionando, solo cambia lo que el
    ; user ve durante la espera. Release-gate primero para descartar input
    ; residual (e.g. la tecla 'J'/'ENTER' del LOAD que aun esta presionada).
.sf1bInitIdle:
    HALT
    CALL SplashCheckInput
    JR NZ, .sf1bInitIdle
.sf1bWaitPress:
    HALT
    CALL SplashCheckInput
    JR Z, .sf1bWaitPress
    ; --- Paso 1: cargar font Reward (bank 4 = ya paginado aqui) -> BgSpriteBuffer ---
    ; CreditsFontData vive en bank 4 (este mismo bank, slot 3). LDIR directo.
    LD HL, CreditsFontData
    LD DE, BgSpriteBuffer
    LD BC, CREDITS_FONT_SIZE
    LDIR
    ; --- Card 0 ---
    CALL ClearScreenBlack
    LD HL, F2Card0Text
    CALL PrintMultiLineCenteredBody
    LD A, 150                       ; 3 s @ 50 Hz
    CALL F2WaitOrSkip
    ; --- Card 1 ---
    CALL ClearScreenBlack
    LD HL, F2Card1Text
    CALL PrintMultiLineCenteredBody
    LD A, 150
    CALL F2WaitOrSkip
    ; --- Card 2: descomprime 257 + arranca musica EndGame + pinta iconos ---
    ; Music drives durante menu/historia gracias a SafeHaltAndPrefetch (slot 1)
    ; en cada HALT del wait loop, que pagina bank 7 + repagina bank 4 para
    ; que el body siga visible despues del prefetch.
    CALL DecompressSplashTrampoline ; 257 a $4000
    DI
    LD A, 2
    LD (MusicTrackArg), A
    CALL StartMusicImpl             ; bank 4, mismo bank que F1Body
    EI
    CALL PaintBaseIcons             ; iconos en fila 22 sobre 257
    ; Wait 7 s (350 frames) o skip por control press. Musica + iconos siguen.
    CALL StandaloneSplashCard2Wait
    ; --- Menu idioma (F3) ---
    CALL StandaloneLangMenu
    ; --- Historia bilingue (F4) ramificada segun SLMSelection ---
    LD A, (SLMSelection)
    CP 2
    JR Z, .sf1bSkipStory            ; 2 = Skip story
    LD HL, StoryPagesEN
    OR A
    JR Z, .sf1bShowStory            ; 0 = English
    LD HL, StoryPagesES             ; 1 = Espanol
.sf1bShowStory:
    CALL StandaloneStoryShow
.sf1bSkipStory:
    RET                             ; music ya arrancada; main.asm hace jingle

; ==============================================================================
; PaintBaseIcons - Pinta attrs + frame A de iconos key/btn en fila 22
; ==============================================================================
; Replica el setup de SplashWait: 4 attrs key + 4 attrs btn + 32 B pixels key
; + 32 B pixels btn. Resetea SplashPrevAnimBit/SplashBeatCounter para que
; UpdateSplashAnim re-pinte desde el primer frame al siguiente call.
; Llamado tras cada ClearScreenBlack en menu/historia para mantener iconos.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
PaintBaseIcons:
    ; Key attrs (TL, TR)
    LD HL, SplashKeyAttrs
    LD DE, SPLASH_KEY_ATTR_TOP
    LD BC, 2
    LDIR
    ; Key attrs (BL, BR) — HL ya avanzo 2 bytes
    LD DE, SPLASH_KEY_ATTR_BOT
    LD BC, 2
    LDIR
    ; Btn attrs (TL, TR)
    LD HL, SplashBtnAttrs
    LD DE, SPLASH_BTN_ATTR_TOP
    LD BC, 2
    LDIR
    LD DE, SPLASH_BTN_ATTR_BOT
    LD BC, 2
    LDIR
    ; Reset anim state -> UpdateSplashAnim re-pinta primera vez
    LD A, $FF
    LD (SplashPrevAnimBit), A
    XOR A
    LD (SplashBeatCounter), A
    ; Pintar frame A inicial (key + btn)
    LD DE, SplashIconPixels + SPLASH_KEY_PX_A
    LD HL, SPLASH_KEY_PX_ADDR
    CALL PaintIcon16x16
    LD DE, SplashIconPixels + SPLASH_BTN_PX_A
    LD HL, SPLASH_BTN_PX_ADDR
    JP PaintIcon16x16               ; tail-call

; ==============================================================================
; ClearScreenBlack - VRAM pixels=0, attrs=$07 (white ink, black paper)
; ==============================================================================
ClearScreenBlack:
    LD HL, $4000
    LD DE, $4001
    LD BC, 6143
    LD (HL), 0
    LDIR
    LD HL, $5800
    LD DE, $5801
    LD BC, 767
    LD (HL), $07
    LDIR
    RET

; ==============================================================================
; F2WaitOrSkip - HALT loop con timer + input skip + release-gate
; ==============================================================================
; IN: A = frame count (1..255).
; NO llama PrefetchMusic (pagina bank 7 -> bank 4 desaparece de slot 3 -> lock).
; Las cards corren en silencio; musica EndGame arranca tras el RET de F1Setup.
; Destruye: AF, BC.
; ==============================================================================
F2WaitOrSkip:
    PUSH AF
.f2wrsRelease:
    HALT
    CALL SplashCheckInput
    JR NZ, .f2wrsRelease
    POP AF
.f2wrsLoop:
    HALT
    PUSH AF
    CALL SplashCheckInput
    JR NZ, .f2wrsSkip
    POP AF
    DEC A
    JR NZ, .f2wrsLoop
    RET                             ; timer expired
.f2wrsSkip:
    POP AF                          ; balance stack
    RET

; ==============================================================================
; StandaloneSplashCard2Wait - max 7 s o skip por press, musica + iconos (F5)
; ==============================================================================
; Timer 350 frames (= 7 s @ 50 Hz) cap estricto. Cualquier press en cualquier
; momento sale inmediato (incluye cascade si user mantiene fire desde Card 1).
; Destruye: AF, BC.
; ==============================================================================
StandaloneSplashCard2Wait:
    LD BC, 300                      ; 6 s @ 50 Hz, cap maximo
.scwLoop:
    PUSH BC                         ; preserve counter (SafeHaltAndPrefetch
                                    ; destruye BC con LD BC,$7FFD para OUT)
    CALL SafeHaltAndPrefetch
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .scwSkip
    POP BC
    DEC BC
    LD A, B
    OR C
    JR NZ, .scwLoop
    RET
.scwSkip:
    POP BC
    RET

; ==============================================================================
; PrintMultiLineCenteredBody - Itera tabla de lineas + pinta centradas
; ==============================================================================
; IN:  HL = puntero a tabla {row(1B), str(N B + 0)}*, terminada en $FF
; OUT: HL = al byte $FF terminador
; Destruye: AF, BC, DE, HL.
; ==============================================================================
PrintMultiLineCenteredBody:
.pmlcLoop:
    LD A, (HL)
    CP $FF
    RET Z
    INC HL                          ; HL -> inicio string
    LD D, A                         ; D = row
    CALL PrintStringCenteredAt
    JR .pmlcLoop

; ==============================================================================
; PrintStringCenteredAt - Centra string en fila D y pinta
; ==============================================================================
; IN:  D = row, HL = string 0-terminated
; OUT: HL = byte tras el 0 terminador
; ==============================================================================
PrintStringCenteredAt:
    PUSH HL
    LD B, 0
.pscaCount:
    LD A, (HL)
    OR A
    JR Z, .pscaCountDone
    INC B
    INC HL
    JR .pscaCount
.pscaCountDone:
    POP HL
    LD A, 32
    SUB B
    SRL A
    LD E, A
    ; Cae a PrintStringFontAtExt (tail-call implicito).

; ==============================================================================
; PrintStringFontAtExt - Pinta cadena 0-terminated en (D=row, E=col)
; ==============================================================================
PrintStringFontAtExt:
.psfxLoop:
    LD A, (HL)
    INC HL
    OR A
    RET Z
    PUSH HL
    PUSH DE
    CALL DrawCharFontAtExt
    POP DE
    POP HL
    INC E
    JR .psfxLoop

; ==============================================================================
; DrawCharFontAtExt - Dibuja un char (con fallback a font extendida en bank 4)
; ==============================================================================
; IN:  D = row, E = col, A = char (ASCII 0x20-0x7F o ext 0x80-0x8B)
; ExtFontGlyphs vive en bank 4 (este mismo bank, slot 3 actual = bank 4).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DrawCharFontAtExt:
    PUSH DE
    CP $80
    JR NC, .dcfaExt
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, BgSpriteBuffer - $0100
    ADD HL, BC
    JR .dcfaDraw
.dcfaExt:
    SUB $80
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, ExtFontGlyphs
    ADD HL, BC
.dcfaDraw:
    POP DE
    PUSH HL
    LD A, D
    ADD A, A
    ADD A, A
    ADD A, A
    LD D, A
    LD A, E
    ADD A, A
    ADD A, A
    ADD A, A
    LD E, A
    CALL CalcPixelAddr
    EX DE, HL
    POP HL
    LD B, 8
.dcfxLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D
    DJNZ .dcfxLoop
    RET

; ==============================================================================
; F2 card strings - texto centrado de las cards 0 y 1
; ==============================================================================
F2Card0Text:
    DEFB 11
    DEFB "JayDroid Presents", 0
    DEFB $FF

F2Card1Text:
    DEFB 10
    DEFB "A Sinclair ZX Spectrum", 0
    DEFB 12
    DEFB "128 K computer game", 0
    DEFB $FF

; ==============================================================================
; StandaloneLangMenu - Menu idioma overlay sobre bg-185 (F3)
; ==============================================================================
; Pinta titulo + 3 opciones, cursor ">" en col 9. Loop con ReadMenuInput:
; up/down clamp (no-cycle), fire confirma. F3 minima: ninguna persistencia
; de la seleccion (F4 anadira variable y ramificacion historia vs skip).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
; Layout: 3 opciones con 2 filas vacias entre cada par, height = 7 rows.
; Centrado vertical: (24 - 7) / 2 = 8. Filas 8 / 11 / 14.
SLM_ROW_OPT0    EQU 8
SLM_ROW_OPT1    EQU 11
SLM_ROW_OPT2    EQU 14
; Cursor dinamico: col = col_start de la opcion seleccionada - 2 (= 2 chars
; antes del primer char del texto). Calculado en SLMCursorRowCol.

StandaloneLangMenu:
    ; Fondo negro tras Card 2 (limpia 257); iconos animados sobreviven via
    ; PaintBaseIcons. Sin titulo: solo 3 opciones centradas vertical+horiz.
    CALL ClearScreenBlack
    CALL PaintBaseIcons             ; re-pinta iconos en fila 22
    LD HL, SLMOpt0Text
    LD D, SLM_ROW_OPT0
    CALL PrintStringCenteredAt
    LD HL, SLMOpt1Text
    LD D, SLM_ROW_OPT1
    CALL PrintStringCenteredAt
    LD HL, SLMOpt2Text
    LD D, SLM_ROW_OPT2
    CALL PrintStringCenteredAt
    ; Init selection = 0
    XOR A
    LD (SLMSelection), A
    CALL SLMDrawCursor
    ; Wait release inicial con anim de iconos
.slmRelease:
    CALL SafeHaltAndPrefetch
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .slmRelease
.slmLoop:
    CALL SafeHaltAndPrefetch
    CALL UpdateSplashAnim
    CALL ReadMenuInput              ; A: bit 0=up, bit 1=down, bit 2=fire
    OR A
    JR Z, .slmLoop
    BIT 2, A
    JR NZ, .slmConfirm
    BIT 0, A
    JR NZ, .slmUp
    BIT 1, A
    JR NZ, .slmDown
    JR .slmLoop
.slmUp:
    LD A, (SLMSelection)
    OR A
    JR Z, .slmWaitRelease           ; clamped en 0
    CALL SLMEraseCursor
    LD A, (SLMSelection)
    DEC A
    LD (SLMSelection), A
    CALL SLMDrawCursor
    JR .slmWaitRelease
.slmDown:
    LD A, (SLMSelection)
    CP 2
    JR Z, .slmWaitRelease           ; clamped en 2
    CALL SLMEraseCursor
    LD A, (SLMSelection)
    INC A
    LD (SLMSelection), A
    CALL SLMDrawCursor
    JR .slmWaitRelease
.slmConfirm:
    RET
.slmWaitRelease:
    CALL SafeHaltAndPrefetch
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .slmWaitRelease
    JR .slmLoop

; --- SLMCursorRowCol: calcula (D=row, E=col) del cursor segun SLMSelection ---
; col = (32 - len(opcion)) / 2 - 2 (2 chars antes del texto)
; row = SLM_ROW_OPT0 + selection * 3 (step 3 = 1 text + 2 empty)
; Destruye: AF, B (preserva nada mas). HL local.
SLMCursorRowCol:
    LD A, (SLMSelection)
    LD HL, SLMOpt0Text
    OR A
    JR Z, .slmcrcPtr
    LD HL, SLMOpt1Text
    DEC A
    JR Z, .slmcrcPtr
    LD HL, SLMOpt2Text
.slmcrcPtr:
    LD B, 0
.slmcrcCnt:
    LD A, (HL)
    OR A
    JR Z, .slmcrcCntDone
    INC B
    INC HL
    JR .slmcrcCnt
.slmcrcCntDone:
    LD A, 32
    SUB B
    SRL A
    SUB 2                           ; col = col_start - 2
    LD E, A
    LD A, (SLMSelection)
    LD B, A
    ADD A, A                        ; *2
    ADD A, B                        ; *3
    ADD A, SLM_ROW_OPT0
    LD D, A
    RET

SLMDrawCursor:
    CALL SLMCursorRowCol
    LD A, '>'
    JP DrawCharFontAtExt            ; tail-call

SLMEraseCursor:
    CALL SLMCursorRowCol
    LD A, ' '
    JP DrawCharFontAtExt

; --- ReadMenuInput: kempston + kbd $EFFE (keys 7/6/0) ---
; OUT: A bit 0=up, bit 1=down, bit 2=fire
ReadMenuInput:
    LD E, 0
    ; --- Kempston ---
    IN A, ($1F)
    LD B, A
    AND $1F
    CP $1F
    JR Z, .rmiKbd                   ; bus flotante -> ignora kempston
    BIT 3, B                        ; up
    JR Z, .rmiKnu
    SET 0, E
.rmiKnu:
    BIT 2, B                        ; down
    JR Z, .rmiKnd
    SET 1, E
.rmiKnd:
    BIT 4, B                        ; fire
    JR Z, .rmiKbd
    SET 2, E
.rmiKbd:
    ; --- Kbd port $EFFE: keys 0/9/8/7/6 (bits 0..4) ---
    LD BC, $EFFE
    IN A, (C)
    CPL                             ; 1 = pressed
    LD B, A
    BIT 3, B                        ; key 7 = up
    JR Z, .rmiKbnu
    SET 0, E
.rmiKbnu:
    BIT 4, B                        ; key 6 = down
    JR Z, .rmiKbnd
    SET 1, E
.rmiKbnd:
    BIT 0, B                        ; key 0 = fire
    JR Z, .rmiDone
    SET 2, E
.rmiDone:
    LD A, E
    RET

; --- F3 strings ---
SLMOpt0Text:    DEFB "English", 0
SLMOpt1Text:    DEFB "Espa", $8A, "ol", 0      ; Español
SLMOpt2Text:    DEFB "Skip / Saltar", 0        ; bilingue

; --- F3 state ---
SLMSelection:   DEFB 0

; ==============================================================================
; StandaloneStoryShow - Itera tabla de paginas e imprime con wait-input (F4)
; ==============================================================================
; IN: HL = puntero a StoryPagesEN o StoryPagesES
; Formato tabla: por linea {row(1B), char*, 0}; $FE = fin de pagina (espera
; release + press, clear, siguiente); $FF = fin de historia (RET).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
StandaloneStoryShow:
    ; Fondo negro entre paginas + iconos animados en fila 22 (re-pintados
    ; tras cada ClearScreenBlack que los machacaria). PUSH/POP HL preserva
    ; puntero a tabla story durante las CALLs que destruyen HL.
    PUSH HL
    CALL ClearScreenBlack
    CALL PaintBaseIcons
    POP HL
.sssLineLoop:
    LD A, (HL)
    CP $FF
    RET Z                           ; fin de historia
    CP $FE
    JR Z, .sssEndPage
    INC HL                          ; HL -> inicio string
    LD D, A                         ; row
    CALL PrintStringCenteredAt      ; HL avanza al post-0
    JR .sssLineLoop
.sssEndPage:
    INC HL                          ; skip $FE
    ; Wait release + wait press con anim de iconos
    PUSH HL
.sssRelease:
    CALL SafeHaltAndPrefetch
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .sssRelease
.sssWaitPress:
    CALL SafeHaltAndPrefetch
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR Z, .sssWaitPress
    POP HL
    ; Peek: si la siguiente entry es $FF (fin historia), RET sin clear para
    ; mantener la ultima pagina visible durante el jingle. main.asm hace
    ; StartMusic 5 + wait MusicEnded mostrando esta pagina; al acabar el
    ; jingle el ClearScreenBlack del game inicia gameplay normal.
    LD A, (HL)
    CP $FF
    RET Z
    JR StandaloneStoryShow          ; clear + next page

    INCLUDE "standalone_story_data.asm"

; ==============================================================================
; ExtFontGlyphs - 12 glyphs custom para acentos espanoles (96 B)
; ==============================================================================
ExtFontGlyphs:
    DEFB $06, $00, $78, $0C, $7C, $CC, $FE, $76  ; 0x80 a-acute
    DEFB $06, $00, $3C, $66, $7E, $60, $7E, $3E  ; 0x81 e-acute
    DEFB $0C, $08, $00, $38, $38, $18, $3C, $3C  ; 0x82 i-acute
    DEFB $06, $00, $3C, $7E, $66, $66, $7E, $3C  ; 0x83 o-acute
    DEFB $06, $00, $EE, $EE, $66, $6E, $7F, $37  ; 0x84 u-acute
    DEFB $06, $30, $38, $6C, $6C, $FE, $C6, $C6  ; 0x85 A-acute
    DEFB $07, $FE, $FE, $66, $70, $66, $FE, $FE  ; 0x86 E-acute
    DEFB $06, $00, $3C, $3C, $18, $18, $3C, $3C  ; 0x87 I-acute
    DEFB $06, $38, $7C, $EE, $C6, $EE, $7C, $38  ; 0x88 O-acute
    DEFB $03, $00, $C6, $C6, $C6, $C6, $FE, $7C  ; 0x89 U-acute
    DEFB $28, $14, $00, $EC, $FE, $76, $E7, $E7  ; 0x8A n-tilde
    DEFB $3C, $00, $F7, $F3, $7B, $6F, $E7, $F7  ; 0x8B N-tilde
