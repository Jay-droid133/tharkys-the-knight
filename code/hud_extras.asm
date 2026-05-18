; ==============================================================================
; hud_extras.asm
;   * 3 iconos buff con on/off por timer (rayo / escudo / espada)
; ==============================================================================
; Layout (cantado por el viewer, hud_layout.json):
;   buff_rayo     cols 6-7    rows 0-1  (SpeedBuffType == 1)
;   buff_escudo   cols 8-9    rows 0-1  (EscudoTimer)
;   buff_espada   cols 10-11  rows 0-1  (EspadaTimer)
;
; Buffs cada frame:
;   activo   -> redibuja sprite (pixels + attrs nativos del pickup).
;                Reescribir la misma cosa cada frame no parpadea.
;                Ademas garantiza que el icono sobrevive screen transitions.
;   inactivo -> escribe attrs $00 (ink=paper=black -> sprite invisible).
;                No dibuja pixels (los que queden del ultimo activo no se ven).
;
; Asi evitamos el patron "draw + override" que producia el parpadeo: el
; ULA podia leer los attrs nativos durante la ventana entre el write del
; sprite y el override a $00.
; ==============================================================================

    INCLUDE "hud_decoration_sprites.inc"

HUD_BUFF_RAYO_COL    EQU 6
HUD_BUFF_ESCUDO_COL  EQU 8
HUD_BUFF_ESPADA_COL  EQU 10

HUD_BUFF_INACTIVE_ATTR EQU $00     ; ink=paper=black -> sprite invisible

; Parpadeo en los ultimos ~3 segundos (75 frames @ 25 fps).
HUD_BUFF_BLINK_THRESHOLD EQU 75
HUD_BUFF_BLINK_MASK      EQU $04   ; toggle cada 4 frames = ~3 Hz @ 25 fps

; ==============================================================================
; DrawBuffIcons - cada frame: si activo redibuja sprite, si no pinta attrs $00.
; ==============================================================================
DrawBuffIcons:
    ; --- Rayo (SpeedBuffType == 1; ==2 es caracol y no enciende rayo) ---
    LD A, (SpeedBuffType)
    CP 1
    JR NZ, .rayoOff
    LD HL, (SpeedBuffTimer)
    CALL .checkBlink
    JR C, .rayoOff
    LD IX, BgGfx_hud_buff_rayo
    LD B, HUD_BUFF_RAYO_COL
    CALL .draw2x2
    JR .escudo
.rayoOff:
    LD HL, $5800 + 0 * 32 + HUD_BUFF_RAYO_COL
    CALL .paintInactive2x2

    ; --- Escudo (EscudoTimer != 0) ---
.escudo:
    LD HL, (EscudoTimer)
    LD A, H
    OR L
    JR Z, .escudoOff
    CALL .checkBlink
    JR C, .escudoOff
    LD IX, BgGfx_hud_buff_escudo
    LD B, HUD_BUFF_ESCUDO_COL
    CALL .draw2x2
    JR .espada
.escudoOff:
    LD HL, $5800 + 0 * 32 + HUD_BUFF_ESCUDO_COL
    CALL .paintInactive2x2

    ; --- Espada (EspadaTimer != 0) ---
.espada:
    LD HL, (EspadaTimer)
    LD A, H
    OR L
    JR Z, .espadaOff
    CALL .checkBlink
    JR C, .espadaOff
    LD IX, BgGfx_hud_buff_espada
    LD B, HUD_BUFF_ESPADA_COL
    JP .draw2x2
.espadaOff:
    LD HL, $5800 + 0 * 32 + HUD_BUFF_ESPADA_COL
    JP .paintInactive2x2

; ----------------------------------------------------------------------------
; .checkBlink - HL = timer (>= 1). Devuelve CF=0 visible, CF=1 oculto.
; Si timer >= threshold (75 frames = ~3s) -> visible.
; Si timer <  threshold -> alterna por GameFrameCounter & mask.
; ----------------------------------------------------------------------------
.checkBlink:
    LD A, H
    OR A
    JR NZ, .cbVisible                ; timer >= 256 -> visible
    LD A, L
    CP HUD_BUFF_BLINK_THRESHOLD
    JR NC, .cbVisible                ; timer >= 75 -> visible
    LD A, (GameFrameCounter)
    AND HUD_BUFF_BLINK_MASK
    JR Z, .cbVisible                 ; mask bit 0 -> fase visible del blink
    SCF                              ; fase off del blink
    RET
.cbVisible:
    OR A                             ; CF=0
    RET

; HL = attr addr (row 0 col X). Pinta 2x2 chars con attr $00.
.paintInactive2x2:
    LD A, HUD_BUFF_INACTIVE_ATTR
    LD (HL), A
    INC HL
    LD (HL), A                       ; row 0 col X+1
    LD DE, 31                        ; HL += 31 -> row 1 col X
    ADD HL, DE
    LD (HL), A
    INC HL
    LD (HL), A                       ; row 1 col X+1
    RET

.draw2x2:
    LD A, 0
    SUB BG_Y_OFFSET
    LD C, A
    XOR A
    LD (BgSpriteIsHouse), A
    LD (CurrentTintVar), A
    JP DrawBgGfxSprite
