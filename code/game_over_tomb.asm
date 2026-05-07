; ==============================================================================
; GAME OVER — TUMBA DEL JUGADOR A 2x (BODY, vive en BANK 7)
; ==============================================================================
; Cuerpo de la rutina. Vive en bank 7 (slot 3 cuando paged) por estar
; "holgado": tras bg_gfx_c (~$D226) y antes del storage de tombstones ($E000+),
; quedan ~3.5 KB libres. Bank 0 estaba al 96 % y este código es one-shot.
;
; Llamado por DrawTombstone2xCentered (thunk en slot 1) DESPUÉS de que el
; thunk haya cargado el sprite en BgSpriteBuffer y paginado bank 7 en slot 3.
; El body NO debe llamar a LoadBgSpriteToBuffer (esa rutina restaura bank 0
; en slot 3 al final → bank 7 desaparece → crash).
;
; Sprite ID 144 (BgGfx_little_house_cemetery, 48x40 px = 6x5 chars) renderizado
; al doble de tamaño (96x80 px = 12x10 chars) centrado en la pantalla de
; Game Over. La muerte hace moonwalk justo encima del techo.
;
; Sprite original: bg_gfx_b.asm (bank 4), formato BG con pixeles RLE+CPL'd.
;
; Algoritmo (precondición: BgSpriteBuffer ya tiene el sprite cargado):
;   1. DecodeRLEPixels: walk RLE stream, decodifica + CPL → escribe 240 bytes
;      planos en TombDecodedPixels (en bank 7 RAM). Salva src ptr post-pixels.
;   2. Draw2xPixels: itera 40 src rows × 6 src bytes. Por cada src byte: doble
;      via NibbleDoubleLUT (16 B), escribe 2 bytes a VRAM dst row top y dst
;      row bot (vertical doubling). Posicion final: pixel(80, 80)..(175, 159).
;   3. Draw2xAttrs: 5 src rows × 6 src attrs → 10 dst rows × 12 dst attrs.
;      Cada src attr replicado 2x2. Posicion final: char(10, 10)..(21, 19).
;
; Coste: ~30K T-states one-shot. Invisible.
; Tamaño: ~280 B código + 16 B LUT + 240 B scratch + 2 B var = ~538 B en bank 7.
;
; Capas:
;   - Tumba 2x: pixel Y range 80..159 (charY 10..19).
;   - Muerte moonwalk: pixel Y range 56..79 (charY 7..9). NO solapa con tumba.
; ==============================================================================

TOMB_2X_DST_PIXEL_X     EQU 80      ; centrar 96 px en 256: (256-96)/2 = 80
TOMB_2X_DST_PIXEL_Y     EQU 80      ; deja Y 0..79 para HUD/título y la muerte
TOMB_2X_DST_CHAR_X      EQU 10      ; = TOMB_2X_DST_PIXEL_X / 8
TOMB_2X_DST_CHAR_Y      EQU 10      ; = TOMB_2X_DST_PIXEL_Y / 8
TOMB_SRC_W_BYTES        EQU 6       ; 48 px / 8
TOMB_SRC_H_PX           EQU 40      ; height en pixeles
TOMB_SRC_ATTR_H         EQU 5       ; attr rows
TOMB_SRC_ATTR_W         EQU 6       ; attr cols
TOMB_SRC_BANK           EQU 4       ; bg_gfx_b.asm vive en bank 4 (cemetery)

; ==============================================================================
; DrawTombstone2xBody - entry point del body en bank 7
; ==============================================================================
; Precondición: bank 7 paginado en slot 3 + BgSpriteBuffer ya cargado con
; el sprite (lo hace el thunk antes de llamar a esta rutina).
;
; Asume que la pantalla está limpia (pixels=0, attrs=$47) — el render escribe
; directamente a VRAM sin XOR.
;
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
DrawTombstone2xBody:
    ; --- 1. Decodificar pixeles RLE+CPL → flat buffer ---
    CALL DecodeTombRLEPixels        ; out: TombAttrSrcPtr = ptr a attr data

    ; --- 2. Dibujar pixeles 2x desde flat buffer ---
    CALL DrawTombPixels2x

    ; --- 3. Dibujar attrs 2x desde BgSpriteBuffer ---
    JP DrawTombAttrs2x              ; tail-call

; ==============================================================================
; DecodeTombRLEPixels - parsea el stream RLE de BgSpriteBuffer y emite 240 bytes
; planos (CPL'd → des-CPL'd) a TombDecodedPixels.
; ==============================================================================
; Formato RLE (mismo que DrawBgGfxSprite):
;   Control $01-$7F: literal group, siguen (control) bytes raw.
;   Control $80-$FF: run, count = (control & $7F) + 2, sigue 1 byte valor.
;
; Tras emitir 240 bytes, HL apunta al siguiente byte del buffer = tint.
; Salvamos HL+3 (saltar tint, AH, AW) en TombAttrSrcPtr → ptr a attrs.
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DecodeTombRLEPixels:
    LD HL, BgSpriteBuffer + 2       ; saltar header (H, W|RLE)
    LD DE, TombDecodedPixels
    LD BC, TOMB_SRC_W_BYTES * TOMB_SRC_H_PX   ; 240 bytes a emitir
    XOR A
    LD (.drlPending), A
.drlLoop:
    LD A, B
    OR C
    JR Z, .drlDone                  ; remaining == 0 → done
    LD A, (.drlPending)
    OR A
    JR Z, .drlNewToken
    JP M, .drlLitEmit
    ; pending > 0 → run en curso
.drlRunEmit:
    LD A, (.drlValue)
    CPL
    LD (DE), A
    INC DE
    DEC BC
    LD A, (.drlPending)
    DEC A
    LD (.drlPending), A
    JR .drlLoop

.drlLitEmit:
    LD A, (HL)
    INC HL
    CPL
    LD (DE), A
    INC DE
    DEC BC
    LD A, (.drlPending)
    INC A                           ; hacia 0
    LD (.drlPending), A
    JR .drlLoop

.drlNewToken:
    LD A, (HL)
    INC HL
    BIT 7, A
    JR NZ, .drlNewRun
    ; Literal group: pending = -count
    NEG
    LD (.drlPending), A
    JR .drlLoop

.drlNewRun:
    AND $7F
    ADD A, 2
    LD (.drlPending), A
    LD A, (HL)
    INC HL
    LD (.drlValue), A
    JR .drlLoop

.drlDone:
    ; HL apunta al byte tras los pixeles RLE = tint byte.
    ; attrs comienzan en HL + 3 (skip tint + AH + AW).
    INC HL
    INC HL
    INC HL
    LD (TombAttrSrcPtr), HL
    RET

.drlPending:    DEFB 0
.drlValue:      DEFB 0

; ==============================================================================
; DrawTombPixels2x - 240 src bytes (6×40) → 960 dst bytes (12×80) en VRAM
; ==============================================================================
; Por cada src row: calcula dst_top y dst_bot via CalcPixelAddr. Por cada src
; byte: doble via NibbleDoubleLUT, escribe 2 bytes a top y 2 a bot (con misma
; pareja de bytes — vertical doubling).
;
; Estado en .dpx* scratch (ahorra 6+ pushes en el loop interno).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DrawTombPixels2x:
    LD A, TOMB_SRC_H_PX             ; 40 src rows
    LD (.dpxRowsLeft), A
    LD A, TOMB_2X_DST_PIXEL_Y
    LD (.dpxDstY), A
    LD HL, TombDecodedPixels
    LD (.dpxSrcPtr), HL

.dpxNextRow:
    ; Calc dst top addr at (TOMB_2X_DST_PIXEL_X, dstY)
    LD A, (.dpxDstY)
    LD D, A
    LD E, TOMB_2X_DST_PIXEL_X
    CALL CalcPixelAddr
    LD (.dpxDstTop), HL

    ; Calc dst bot addr at (TOMB_2X_DST_PIXEL_X, dstY + 1) via NextPixelLine
    CALL NextPixelLine
    LD (.dpxDstBot), HL

    ; Procesar 6 src bytes para esta src row
    LD HL, (.dpxSrcPtr)
    LD B, TOMB_SRC_W_BYTES
.dpxByteLoop:
    LD A, (HL)
    INC HL
    LD C, A                         ; C = src byte original
    PUSH HL                         ; save src ptr
    PUSH BC                         ; save count + src byte

    ; --- High nibble doubled ---
    AND $F0
    RRCA : RRCA : RRCA : RRCA       ; high nibble en posición baja
    LD E, A
    LD D, 0
    LD HL, NibbleDoubleLUT
    ADD HL, DE
    LD A, (HL)                      ; A = high doubled
    LD HL, (.dpxDstTop)
    LD (HL), A
    INC HL
    LD (.dpxDstTop), HL
    LD HL, (.dpxDstBot)
    LD (HL), A
    INC HL
    LD (.dpxDstBot), HL

    ; --- Low nibble doubled ---
    POP BC                          ; recover src byte (en C)
    PUSH BC
    LD A, C
    AND $0F
    LD E, A
    LD D, 0
    LD HL, NibbleDoubleLUT
    ADD HL, DE
    LD A, (HL)                      ; A = low doubled
    LD HL, (.dpxDstTop)
    LD (HL), A
    INC HL
    LD (.dpxDstTop), HL
    LD HL, (.dpxDstBot)
    LD (HL), A
    INC HL
    LD (.dpxDstBot), HL

    POP BC                          ; restaura B (counter) + C (irrelevante)
    POP HL                          ; src ptr
    DJNZ .dpxByteLoop

    ; Avanzar a siguiente src row
    LD (.dpxSrcPtr), HL             ; HL ya apunta al siguiente row src
    LD A, (.dpxDstY)
    ADD A, 2                        ; 2 dst rows por 1 src row
    LD (.dpxDstY), A
    LD A, (.dpxRowsLeft)
    DEC A
    LD (.dpxRowsLeft), A
    JP NZ, .dpxNextRow
    RET

.dpxRowsLeft:   DEFB 0
.dpxDstY:       DEFB 0
.dpxSrcPtr:     DEFW 0
.dpxDstTop:     DEFW 0
.dpxDstBot:     DEFW 0

; ==============================================================================
; DrawTombAttrs2x - 30 src attrs (6×5) → 120 dst attrs (12×10) en attr VRAM
; ==============================================================================
; Cada src attr se replica en bloque 2×2 chars en dst.
; Src ptr en TombAttrSrcPtr (set por DecodeTombRLEPixels).
; Dst start: $5800 + TOMB_2X_DST_CHAR_Y * 32 + TOMB_2X_DST_CHAR_X.
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DrawTombAttrs2x:
    LD HL, (TombAttrSrcPtr)         ; HL = src attrs (en BgSpriteBuffer)
    LD DE, ATTR_BASE + TOMB_2X_DST_CHAR_Y * 32 + TOMB_2X_DST_CHAR_X
    LD A, TOMB_SRC_ATTR_H           ; 5 src rows
.daxRow:
    LD (.daxRowsLeft), A
    PUSH DE                         ; guardar dst row top start
    LD B, TOMB_SRC_ATTR_W           ; 6 src attrs por row
.daxCol:
    LD A, (HL)
    INC HL
    LD (DE), A                      ; dst top col 2N
    INC DE
    LD (DE), A                      ; dst top col 2N+1
    INC DE
    DJNZ .daxCol
    ; Replicar la dst row top a dst row top+1 (= +32 bytes)
    POP DE                          ; DE = dst row top start
    PUSH HL                         ; save src ptr
    LD H, D
    LD L, E                         ; HL = dst row top start
    LD A, E
    ADD A, 32
    LD E, A
    JR NC, .daxNoCarry1
    INC D
.daxNoCarry1:
    ; HL = top row start, DE = bot row start. LDIR 12 bytes.
    LD BC, TOMB_SRC_ATTR_W * 2      ; 12
    LDIR                            ; copy 12 attrs from top row to bot row
    ; DE ahora apunta al char tras la última col de bot row.
    ; Necesitamos resetear DE al inicio de la siguiente "row top" = +32 desde
    ; donde estamos. Calculemos: bot row inició en (top + 32). Tras LDIR de 12
    ; bytes, DE = top + 32 + 12. Próxima top row = top + 64.
    ; → DE += 32 - 12 = +20.
    LD A, E
    ADD A, 32 - TOMB_SRC_ATTR_W * 2
    LD E, A
    JR NC, .daxNoCarry2
    INC D
.daxNoCarry2:
    POP HL                          ; restore src ptr
    LD A, (.daxRowsLeft)
    DEC A
    JP NZ, .daxRow
    RET

.daxRowsLeft:   DEFB 0

; ==============================================================================
; LUT: nibble (4 bits abcd) → byte doblado (aabbccdd)
; ==============================================================================
NibbleDoubleLUT:
    DEFB %00000000  ; 0000 → 00000000
    DEFB %00000011  ; 0001 → 00000011
    DEFB %00001100  ; 0010 → 00001100
    DEFB %00001111  ; 0011 → 00001111
    DEFB %00110000  ; 0100 → 00110000
    DEFB %00110011  ; 0101 → 00110011
    DEFB %00111100  ; 0110 → 00111100
    DEFB %00111111  ; 0111 → 00111111
    DEFB %11000000  ; 1000 → 11000000
    DEFB %11000011  ; 1001 → 11000011
    DEFB %11001100  ; 1010 → 11001100
    DEFB %11001111  ; 1011 → 11001111
    DEFB %11110000  ; 1100 → 11110000
    DEFB %11110011  ; 1101 → 11110011
    DEFB %11111100  ; 1110 → 11111100
    DEFB %11111111  ; 1111 → 11111111

; ==============================================================================
; Buffer plano de pixeles decodificados (240 B). Cold storage en slot 1.
; Vivirá en .lst después del code; sjasmplus lo ubica donde el ORG actual.
; ==============================================================================
TombDecodedPixels:
    DEFS TOMB_SRC_W_BYTES * TOMB_SRC_H_PX   ; 240 bytes

; ==============================================================================
; Variable global: ptr a la sección de attrs en BgSpriteBuffer (set por
; DecodeTombRLEPixels). 16-bit, en slot 1 (cold).
; ==============================================================================
TombAttrSrcPtr:
    DEFW 0
