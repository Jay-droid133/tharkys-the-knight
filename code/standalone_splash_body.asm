; ==============================================================================
; STANDALONE SPLASH body - Bank 1
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Vive en bank 1 (slot 3) junto al
; blob ZX0, descompresor y rutinas de render multi-line con font extendida.
;
; F1: entry combinado StandaloneF1Body (one-shot boot). Refactor a entry
; points separados (DecompressSplash, PrintText) cuando F2+ los necesite.
;
; Las rutinas de render NO repaginan; el caller (StandaloneF1Body o futuros
; thunks F2+) maneja el repaging bank 0 antes del RET final. Esto mantiene
; las rutinas reusables sin asumir state de slot 3.
; ==============================================================================

; ==============================================================================
; StandaloneF1Body - 3-card splash + bg-185 decompress (F2)
; ==============================================================================
; Llamado por StandaloneF1Setup. Bank 1 ya paginado en slot 3, font cargada.
; Secuencia:
;   Card 0: pantalla negra + "JayDroid Presents" centrado (~3 s o skip)
;   Card 1: pantalla negra + "A Sinclair ZX Spectrum 128 K computer game" (~3 s)
;   Card 2: descomprime bg-185 a $4000 (lo recoge el SplashWait que viene tras
;           el RET, pintando iconos animados + PRESS ANY KEY en fila 22).
; Repagina bank 0 antes del RET.
;
; Nombre F1Body mantenido por simplicidad (resto de fases lo extenderan in-place).
; ==============================================================================
StandaloneF1Body:
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
    ; --- Card 2: descomprime bg-185 (SplashWait pondra iconos + "PRESS ANY KEY") ---
    LD HL, bg_splash_zx0_data
    LD DE, $4000
    CALL dzx0_standard
    ; Repagina bank 0 ANTES del RET (stack normal accesible otra vez)
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

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
; IN: A = frame count (1..255). RET cuando: timer expired o input NZ tras release.
; Step 1: wait release de input previo (debounce -> evita cascada entre cards).
; Step 2: HALT loop. Cada frame: CheckInput. Salida temprana si press detectado.
; Destruye: AF, BC.
;
; NO llama PrefetchMusic durante las cards. PrefetchMusic pagina bank 7
; internamente y al RET deja bank 0 en slot 3 -> mi F1Body en bank 1
; desaparece de slot 3 -> siguiente HALT lee garbage de bank 0 -> lock.
; Consecuencia: musica EndGame se silencia durante las cards (~3-6 s totales)
; hasta que SplashWait reanude PrefetchMusic. UX aceptable; el music driver
; se queda idle con buffer vacio, no crashea.
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
; PrintMultiLineCenteredBody - Itera tabla de lineas + pinta centradas
; ==============================================================================
; IN:  HL = puntero a tabla. Formato: {row(1B), str(N B + 0)}*, terminada en $FF
; OUT: HL = al byte $FF terminador
; NO repagina. Caller responsable del paging.
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
; OUT: HL = byte tras el 0 terminador (para iterar tablas multi-linea)
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
    POP HL                          ; HL = inicio string
    LD A, 32
    SUB B                           ; A = 32 - len
    SRL A                           ; A = (32 - len) / 2 = col_start
    LD E, A
    ; Cae a PrintStringFontAtExt (tail-call implicito).

; ==============================================================================
; PrintStringFontAtExt - Pinta cadena 0-terminated en (D=row, E=col)
; ==============================================================================
; IN:  D = row, E = col, HL = string 0-terminated
; OUT: HL = byte tras el 0 terminador
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
    INC E                           ; siguiente columna
    JR .psfxLoop

; ==============================================================================
; DrawCharFontAtExt - Dibuja un char (con fallback a font extendida)
; ==============================================================================
; IN:  D = row, E = col, A = char (ASCII 0x20-0x7F o ext 0x80-0x8B)
; Mismo render que town_gate_cutscene_bank7.DrawCharFontAt pero con fallback
; a ExtFontGlyphs (codepoints 0x80-0x8B = acentos espanoles).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DrawCharFontAtExt:
    PUSH DE
    CP $80
    JR NC, .dcfaExt
    ; --- Path normal: font Reward en BgSpriteBuffer (slot 2, always-visible) ---
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                      ; HL = char * 8
    LD BC, BgSpriteBuffer - $0100   ; base - 32*8 (offset compensado)
    ADD HL, BC
    JR .dcfaDraw
.dcfaExt:
    ; --- Path ext: ExtFontGlyphs en bank 1 (slot 3 paginado a bank 1 ahora) ---
    SUB $80
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                      ; HL = (char - $80) * 8
    LD BC, ExtFontGlyphs
    ADD HL, BC
.dcfaDraw:
    POP DE
    PUSH HL                         ; save font ptr
    LD A, D
    ADD A, A
    ADD A, A
    ADD A, A                        ; A = row * 8 = pixel Y
    LD D, A
    LD A, E
    ADD A, A
    ADD A, A
    ADD A, A                        ; A = col * 8 = pixel X
    LD E, A
    CALL CalcPixelAddr              ; HL = VRAM addr (en slot 2 bank 2 fijo)
    EX DE, HL                       ; DE = VRAM addr
    POP HL                          ; HL = font ptr
    LD B, 8
.dcfxLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                           ; siguiente scan line dentro del char (DE += $100)
    DJNZ .dcfxLoop
    RET

    INCLUDE "dzx0_standard.asm"

; ==============================================================================
; F2 card strings - texto centrado de las cards 0 y 1 (F2)
; ==============================================================================
; Formato {row(1B), string+0, ...}*, terminada en $FF.
; Card 0: 1 linea (row 11)
; Card 1: 2 lineas (rows 10 y 12), porque "A Sinclair ZX Spectrum 128 K computer
; game" (42 chars) no cabe en una linea de 32.
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
; ExtFontGlyphs - 12 glyphs custom para acentos espanoles (96 B)
; ==============================================================================
; Codepoints 0x80-0x8B. Copiados del wrapper SDL (port/src/main.c EXT_FONT_GLYPHS).
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

bg_splash_zx0_data:
    INCBIN "bg_splash.zx0"
bg_splash_zx0_end:
