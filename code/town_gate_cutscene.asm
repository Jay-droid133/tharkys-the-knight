; ==============================================================================
; town_gate_cutscene.asm - Funciones COMPARTIDAS slot 1 (resto en bank 7)
; ==============================================================================
; Tras commit "town_gate to bank 7", el body de la cinematica M11 (puerta
; final del juego) vive en bank 7 (town_gate_cutscene_bank7.asm). Aqui
; quedan solo las funciones que tienen que vivir en slot 1 always-visible
; por dos razones:
;
;   1. Son llamadas por bank_cutscene.asm (que tambien vive en bank 7).
;      Si vivieran en bank 7, el body bank_cutscene las llamaria via thunks
;      _B7, pero esas son INTERNALMENTE problematicas porque al pasar por
;      bank 0 paginated invalidaria el stack frame del caller bank 7.
;        - KillDeathIfActive
;        - TownGateAllNastiesDeadCheck
;        - TownGateRedrawPlayer / TownGateErasePlayer / TownGateDrawPlayerHere
;
;   2. Paginan slot 3 internamente (LD CurrentPaging + OUT). Si vivieran
;      en bank 7, el OUT que cambia slot 3 a bank 6 haria desaparecer el
;      codigo bajo sus pies -> crash inmediato.
;        - TownGatePlayerSlideErase / TownGatePlayerSlideDraw
;        - TownGatePlayerXOR_BiClip (no pagina pero la llaman las Slide*)
;
; El body bank 7 (entry thunks CheckTownGateTriggerBg / UpdateTownGateCutscene
; en bank_cutscene_thunks.asm) llama a estas via:
;   - JP/CALL directo (slot 1 always-visible, sin paging) cuando la rutina
;     no toca paging (TownGateAllNastiesDeadCheck, BiClip).
;   - Thunks _B7 con post-page-back (KillDeathIfActive_B7,
;     TownGateRedrawPlayer_B7, TownGatePlayerSlideErase_B7, etc.) cuando la
;     rutina paginate slot 3 internamente.
; ==============================================================================

; --- Constantes usadas por TownGatePlayerXOR_BiClip (compartidas con el body
;     bank 7 que las redefine localmente — sjasmplus las acepta como EQU
;     siempre que el valor coincida). ---
; TGCS_ARCH_PX_TOP / BOTTOM tambien viven en town_gate_cutscene_bank7.asm
; con el mismo valor — sjasmplus emite error si difieren. Mantener sincronizado.
PLAYER_H_PX              EQU 21

; ==============================================================================
; KillDeathIfActive - death (slot 11) → STATE_DYING con puff
; ==============================================================================
; Si TYPE_DEATH activa y no estaba ya muriendo, transicion a STATE_DYING con
; SPRID_PUFF. Llamado por StartBankCutscene (bank 7) via KillDeathIfActive_B7
; thunk y por StartTownGateCutscene (bank 7) tambien via _B7.
; ==============================================================================
KillDeathIfActive:
    LD IX, EntityTable + (SLOT_DEATH * ENT_SIZE)
    LD A, (IX+ENT_TYPE)
    OR A
    RET Z                               ; muerte ya inactiva
    LD A, (IX+ENT_STATE)
    CP STATE_DYING
    RET Z                               ; ya muriendo
    LD (IX+ENT_STATE), STATE_DYING
    LD (IX+ENT_ANIMBASE), SPRID_PUFF
    LD (IX+ENT_SPRITEID), SPRID_PUFF
    LD (IX+ENT_ANIMTIMER), ANIM_DELAY_PUFF
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_ATTR), WHITE | $40
    ; Death se va con puff -> parar musica de la muerte. $FD = stop-if-loopable.
    LD A, $FD
    JP StartMusic

; ==============================================================================
; TownGateDrawPlayerHere - draw + attrs del player en (DRAWX, PlayerDrawY)
; ==============================================================================
TownGateDrawPlayerHere:
    LD IX, EntityTable
    PUSH IX
    CALL GetSpriteAddr
    POP IX
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (PlayerDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

; ==============================================================================
; TownGateRedrawPlayer - erase old + draw new
; ==============================================================================
TownGateRedrawPlayer:
    CALL TownGateErasePlayer
    JP TownGateDrawPlayerHere

; ==============================================================================
; TownGateErasePlayer - XOR-erase del sprite del player en (OLDX, OLDY)
; ==============================================================================
TownGateErasePlayer:
    LD IX, EntityTable
    PUSH IX
    CALL GetOldSpriteAddr
    LD D, (IX+ENT_OLDY)
    LD A, (IX+ENT_OLDX)
    LD E, A
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    CALL RestoreOldAttr
    RET

; ==============================================================================
; TownGateAllNastiesDeadCheck - Z si todos los nasty slots son TYPE_NONE
; ==============================================================================
TownGateAllNastiesDeadCheck:
    LD IX, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.tgandcLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    RET NZ                              ; algun nasty aun activo
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .tgandcLoop
    XOR A                               ; Z = todos TYPE_NONE
    RET

; ==============================================================================
; TownGatePlayerXOR_BiClip - XOR player pixels skipping rows en rect de part1
; ==============================================================================
; Vive aqui porque TownGatePlayerSlideErase/Draw (slot 1) la llaman tras
; paginar bank 6. Si BiClip viviera en bank 7, las Slide* no podrian llamarla
; sin paginar bank 7 antes — sobrecarga innecesaria.
;
; Las constantes TGCS_ARCH_PX_TOP / BOTTOM las define town_gate_cutscene_bank7.asm.
; Necesitan estar disponibles aqui. Para evitar duplicate EQU error, las
; declaramos solo en el archivo bank 7 y dejamos que sjasmplus las resuelva
; cross-file via include order.
;
; IN: D = Y, E = X (aligned a 8). IY = sprite ptr CON header. Bank 6 paginado.
; ==============================================================================
TownGatePlayerXOR_BiClip:
    INC IY
    INC IY                              ; skip header
    PUSH DE
    CALL CalcPixelAddr                  ; HL = VRAM at (D, E)
    POP DE
    LD B, PLAYER_H_PX                   ; B = row counter
    LD C, D                             ; C = current pixel Y
.tgpxbcRow:
    LD A, C
    CP 192
    JR NC, .tgpxbcAdvance               ; off-screen
    CP TGCS_ARCH_PX_TOP
    JR C, .tgpxbcDraw                   ; arriba del arco: dibujar
    CP TGCS_ARCH_PX_BOTTOM + 1
    JR NC, .tgpxbcDraw                  ; abajo del arco: dibujar
    JR .tgpxbcAdvance                   ; in [120, 151] → skip
.tgpxbcDraw:
    LD A, (IY+0)
    XOR (HL)
    LD (HL), A
    INC HL
    LD A, (IY+1)
    XOR (HL)
    LD (HL), A
    DEC HL
.tgpxbcAdvance:
    INC IY
    INC IY
    INC C
    PUSH BC
    CALL NextPixelLine
    POP BC
    DJNZ .tgpxbcRow
    RET

; ==============================================================================
; TownGatePlayerSlideErase / SlideDraw - wrappers con paging bank 6
; ==============================================================================
; Paginan slot 3 a bank 6 internamente para que TownGatePlayerXOR_BiClip
; lea los pixels del player sprite. Llamadas por el body bank 7 via
; TownGatePlayerSlideErase_B7 / SlideDraw_B7 thunks (que solo añaden el
; post-wrap a bank 7).
; ==============================================================================
TownGatePlayerSlideErase:
    LD IX, EntityTable
    PUSH IX
    CALL GetOldSpriteAddr               ; pages bank 6, restora bank 0
    POP IX
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD IY, (OldSprAddr)
    LD D, (IX+ENT_OLDY)
    LD A, (IX+ENT_OLDX)
    LD E, A
    CALL TownGatePlayerXOR_BiClip
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

TownGatePlayerSlideDraw:
    LD IX, EntityTable
    PUSH IX
    CALL GetSpriteAddr
    POP IX
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD IY, (SpriteAddrTemp)
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    CALL TownGatePlayerXOR_BiClip
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (PlayerDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET
