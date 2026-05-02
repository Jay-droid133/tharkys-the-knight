; ==============================================================================
; TOMBSTONES - Tumbas persistentes en el mundo donde el player muere
; ==============================================================================
; Storage: bank 7 a $E000, 800 bytes (200 entradas x 4 bytes cada una).
; Layout por entrada: DEFB roomX, roomY, posX, posY  (todos 8-bit).
; TombstoneCount (1 byte, 0..200) en bank 2 (variables.asm, siempre visible).
;
; Vive en slot 1 ($6000+) tras paging.asm: las rutinas hacen el page switch
; siguiendo el patron de LoadBgSpriteToBuffer (DI durante la ventana, IFF
; tracking via StartupComplete, no CALLs/PUSH/POP entre los OUT).
;
; Cold paths: TombStore se llama 1 vez por muerte; DrawTombstonesInRoom al
; cargar pantalla. Coste invisible.
; ==============================================================================

TOMBSTONE_MAX     EQU 200
TOMBSTONE_BYTES   EQU 4
TOMBSTONE_BANK    EQU 7
TOMBSTONE_ADDR    EQU $E000
SPRID_TOMBSTONE   EQU 252

; ==============================================================================
; TombStore - Anade una tumba en la sala/posicion actual del player muerto
; ==============================================================================
; Lee CurrentScreenX/Y + EntityTable[player].POSX/POSY. Si TombstoneCount<MAX,
; escribe entry en bank 7 y bumpea el contador. No-op si tope alcanzado.
; Destruye: A, BC, DE, HL.
; ==============================================================================
TombStore:
    LD A, (TombstoneCount)
    CP TOMBSTONE_MAX
    RET NC                                  ; tope alcanzado

    ; HL = TOMBSTONE_ADDR + count * 4
    LD H, 0
    LD L, A
    ADD HL, HL                              ; *2
    ADD HL, HL                              ; *4
    LD DE, TOMBSTONE_ADDR
    ADD HL, DE                              ; HL = slot a escribir (bank 7)

    DI
    ; --- Page bank 7 en slot 3 (inline; no CALL — stack vive en slot 3) ---
    LD A, (CurrentPaging)
    AND $F8
    OR TOMBSTONE_BANK
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; --- Escribir 4 bytes (sin PUSH/POP/CALL: stack vive en bank 7 ahora) ---
    LD A, (CurrentScreenX)
    LD (HL), A
    INC HL
    LD A, (CurrentScreenY)
    LD (HL), A
    INC HL
    LD A, (EntityTable + ENT_POSX)
    LD (HL), A
    INC HL
    LD A, (EntityTable + ENT_POSY)
    LD (HL), A

    ; --- Page bank 0 ---
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    LD A, (StartupComplete)
    OR A
    JR Z, .tsNoEI
    EI
.tsNoEI:
    LD A, (TombstoneCount)
    INC A
    LD (TombstoneCount), A
    RET

; ==============================================================================
; DrawTombstonesInRoom - Dibuja todas las tumbas que pertenezcan a la sala actual
; ==============================================================================
; Llamado desde DrawScreen tras pintar BG sprites + objetos. No-op si no hay
; tumbas. Para cada match (roomX,roomY == CurrentScreenX/Y):
;   x_char = posX / 8 ; y_char = posY / 8 - BG_Y_OFFSET
;   draw via DrawBgGfxSprite con BgGfx_tomb cargado al buffer.
; Destruye: A, BC, DE, HL, IX (usa BgSpriteBuffer).
; ==============================================================================
DrawTombstonesInRoom:
    LD A, (TombstoneCount)
    OR A
    RET Z

    ; Cargar sprite tomb al buffer una vez (todas las tumbas comparten sprite)
    LD HL, BgGfx_tomb
    LD A, 3                                 ; bank 3
    CALL LoadBgSpriteToBuffer               ; copia sprite a BgSpriteBuffer

    LD A, (TombstoneCount)
    LD B, A                                 ; B = loop counter
    LD HL, TOMBSTONE_ADDR                   ; HL apunta a entry actual (bank 7)

.dtirLoop:
    PUSH BC                                 ; preservar contador (bank 0 stack)
    PUSH HL                                 ; preservar puntero entry

    ; --- Page bank 7 + leer entry + page bank 0 ---
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR TOMBSTONE_BANK
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    LD A, (HL)                              ; roomX
    LD D, A
    INC HL
    LD A, (HL)                              ; roomY
    LD E, A
    INC HL
    LD A, (HL)                              ; posX
    LD (.dtirPosX), A                       ; .dtir* viven en slot 1 (siempre visibles)
    INC HL
    LD A, (HL)                              ; posY
    LD (.dtirPosY), A

    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    LD A, (StartupComplete)
    OR A
    JR Z, .dtirNoEI
    EI
.dtirNoEI:

    ; --- Comparar room ---
    LD A, (CurrentScreenX)
    CP D
    JR NZ, .dtirSkip
    LD A, (CurrentScreenY)
    CP E
    JR NZ, .dtirSkip

    ; --- Match: dibujar tumba ---
    LD A, (.dtirPosX)
    SRL A
    SRL A
    SRL A                                   ; x_char = posX / 8
    LD B, A
    LD A, (.dtirPosY)
    SRL A
    SRL A
    SRL A                                   ; posY / 8
    SUB BG_Y_OFFSET                         ; DrawBgGfxSprite re-suma BG_Y_OFFSET
    LD C, A
    LD IX, BgSpriteBuffer
    CALL DrawBgGfxSprite
    ; Override attrs cyan fijo (sin cycle day/night)
    LD A, (.dtirPosX)
    LD B, A
    LD A, (.dtirPosY)
    LD C, A
    CALL WriteTombAttrsCyan

.dtirSkip:
    POP HL                                  ; restaurar puntero a entry leida
    LD DE, TOMBSTONE_BYTES
    ADD HL, DE                              ; siguiente entry
    POP BC                                  ; restaurar contador
    DJNZ .dtirLoop
    RET

.dtirPosX: DEFB 0
.dtirPosY: DEFB 0

; ==============================================================================
; WriteTombAttrsCyan - Override 6 attrs (3x2) con los valores originales del sprite
; ==============================================================================
; B = pixelX, C = pixelY del top-left de la tumba (en coords pantalla).
; Escribe ATTR_BASE (override del remap) y CleanAttrMap (para que entidades
; que pisen la tumba la preserven via RestoreOldAttr).
; Bypasses ApplyDayCycleRemap → tumba siempre cyan en cualquier fase del dia.
; Destruye: A, BC, DE, HL.
; ==============================================================================
WriteTombAttrsCyan:
    ; offset = (pixelY/8) * 32 + (pixelX/8)
    LD A, C
    SRL A
    SRL A
    SRL A
    LD H, 0
    LD L, A
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; *32
    LD A, B
    SRL A
    SRL A
    SRL A
    LD E, A
    LD D, 0
    ADD HL, DE                          ; HL = char offset

    ; --- ATTR_BASE override (siempre cyan) ---
    PUSH HL
    LD DE, ATTR_BASE
    ADD HL, DE
    LD (HL), $68                        ; row 0: bright cyan paper
    INC HL
    LD (HL), $68
    INC HL
    LD (HL), $68
    LD DE, 30                           ; saltar a fila 1 (32 - 2 INCs = 30)
    ADD HL, DE
    LD (HL), $28                        ; row 1: dim cyan paper
    INC HL
    LD (HL), $28
    INC HL
    LD (HL), $28
    POP HL

    ; --- CleanAttrMap override (necesario para DrawPendingTomb; redundante
    ;     pero inocuo en DrawTombstonesInRoom — SaveCleanAttrs lo re-volcaria) ---
    LD DE, CleanAttrMap
    ADD HL, DE
    LD (HL), $68
    INC HL
    LD (HL), $68
    INC HL
    LD (HL), $68
    LD DE, 30
    ADD HL, DE
    LD (HL), $28
    INC HL
    LD (HL), $28
    INC HL
    LD (HL), $28
    RET

; ==============================================================================
; RefreshTombAttrsForRoom - Re-aplica attrs cyan a tumbas de la sala actual
; ==============================================================================
; Llamado desde RemapScreenAttrs.rsDone tras SaveCleanAttrs. Si un entity
; (player/nasty/puff/spawn) estaba encima de una tumba durante el cambio de
; fase, sus attrs se habrian colado en CleanAttrMap. Esta rutina re-pinta
; cyan en las celdas de cada tumba de la sala (ATTR_BASE + CleanAttrMap).
; No re-dibuja pixels (XOR los borraria); solo attrs.
; Mismo iterador que DrawTombstonesInRoom pero sin LoadBgSpriteToBuffer ni
; DrawBgGfxSprite.
; Destruye: A, BC, DE, HL.
; ==============================================================================
RefreshTombAttrsForRoom:
    LD A, (TombstoneCount)
    OR A
    RET Z

    LD A, (TombstoneCount)
    LD B, A                                 ; B = loop counter
    LD HL, TOMBSTONE_ADDR

.rtfrLoop:
    PUSH BC
    PUSH HL

    ; --- Page bank 7 + leer entry + page bank 0 ---
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR TOMBSTONE_BANK
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    LD A, (HL)                              ; roomX
    LD D, A
    INC HL
    LD A, (HL)                              ; roomY
    LD E, A
    INC HL
    LD A, (HL)                              ; posX
    LD (.rtfrPosX), A
    INC HL
    LD A, (HL)                              ; posY
    LD (.rtfrPosY), A

    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (StartupComplete)
    OR A
    JR Z, .rtfrNoEI
    EI
.rtfrNoEI:

    ; --- Comparar room ---
    LD A, (CurrentScreenX)
    CP D
    JR NZ, .rtfrSkip
    LD A, (CurrentScreenY)
    CP E
    JR NZ, .rtfrSkip

    LD A, (.rtfrPosX)
    LD B, A
    LD A, (.rtfrPosY)
    LD C, A
    CALL WriteTombAttrsCyan                 ; reset ATTR_BASE + CleanAttrMap

.rtfrSkip:
    POP HL
    LD DE, TOMBSTONE_BYTES
    ADD HL, DE
    POP BC
    DJNZ .rtfrLoop
    RET

.rtfrPosX: DEFB 0
.rtfrPosY: DEFB 0

; ==============================================================================
; DrawPendingTomb - Pinta tumba in-place tras la animacion de muerte
; ==============================================================================
; Llamado desde MainLoop tras ProcessPlayer. Si TombDrawPending=1: ProcessPlayer
; en este frame hizo XOR-erase del sprite de muerte (ya invisible), asi que
; dibujar la tumba en (CorpseX, CorpseY) la deja "in-place" sobre la sala
; actual. Consume el flag.
;
; Tras el draw, parchea CleanAttrMap con los 6 chars (3x2) que ocupa la tumba
; para que RestoreOldAttr (entidades que pisen la tumba) preserve sus attrs
; en vez del BG original. Al re-entrar a la sala, DrawTombstonesInRoom +
; SaveCleanAttrs vuelve a sincronizar todo.
; ==============================================================================
DrawPendingTomb:
    LD A, (TombDrawPending)
    OR A
    RET Z
    XOR A
    LD (TombDrawPending), A             ; consumir

    LD HL, BgGfx_tomb
    LD A, 3
    CALL LoadBgSpriteToBuffer

    LD A, (CorpseX)
    SRL A
    SRL A
    SRL A                               ; x_char = posX / 8
    LD B, A
    LD A, (CorpseY)
    SRL A
    SRL A
    SRL A                               ; abs_char_y = posY / 8
    SUB BG_Y_OFFSET                     ; DrawBgGfxSprite re-suma BG_Y_OFFSET
    LD C, A
    LD IX, BgSpriteBuffer
    CALL DrawBgGfxSprite

    ; Override attrs cyan fijo (sin remap day/night) + patch CleanAttrMap
    LD A, (CorpseX)
    LD B, A
    LD A, (CorpseY)
    LD C, A
    JP WriteTombAttrsCyan               ; tail call
