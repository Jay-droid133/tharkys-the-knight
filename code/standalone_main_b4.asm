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
    ; --- Card 2: descomprime bg-185 (cross-bank via trampoline slot 1) ---
    CALL DecompressSplashTrampoline ; pagina bank 1, descomprime, repagina bank 4
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
