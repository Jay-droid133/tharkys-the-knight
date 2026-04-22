; ==============================================================================
; MONSTER AI v2 — runtime code (fase 3+)
; ==============================================================================
; DEBE incluirse desde main.asm en bank 2 fijo ($8000-$BFFF), antes del
; limite $C000, porque las rutinas paginan bank 6 en slot 3 y se ejecutarian
; ellas mismas si estuvieran en bank 0.
;
; Patron de paginacion (copiado de LoadRoomToBuffer en paging.asm):
;   1. Guardar IFF (LD A,I + PUSH AF) mientras bank 0 sigue en slot 3
;   2. DI
;   3. Inline page-switch via OUT — NO CALLs intermedios
;   4. Trabajo con bank 6 paginado. Sin PUSH/POP ni CALL (excepto usando
;      un stack temporal en bank 2)
;   5. Inline page-switch de vuelta a bank 0
;   6. POP AF + RET PO / EI + RET
; ==============================================================================

; ==============================================================================
; MaiComputeFlowField
; ==============================================================================
; BFS de distancias desde la celda del player a todas las celdas del screen
; actual. FlowField[cy*32+cx] = distancia (celdas bloqueadas/inalcanzables
; quedan en $FF).
;
; Usa un stack temporal en bank 2 durante la ventana de paginacion porque el
; BFS interno hace CALLs a .tryCell que empujan/popean return addresses.
;
; Input: EntityTable[SLOT_PLAYER].POSX/POSY (pixeles)
; Output: FlowField relleno en bank 6
; Destruye: AF, BC, DE, HL
; ==============================================================================
MaiComputeFlowField:
    ; --- Celda del player en char-space (antes de cambiar stack) ---
    LD A, (EntityTable + ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiFlowPlCx), A

    LD A, (EntityTable + ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiFlowPlCy), A

    ; --- Swap a stack temporal (bank 2) ---
    LD (MaiFlowSavedSP), SP
    LD SP, MaiTempStackTop

    ; --- Ventana de paginacion ---
    LD A, I
    PUSH AF                         ; push en stack temporal (bank 2, OK)
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; --- Ejecutar BFS (usa temp stack para CALLs internos) ---
    CALL MaiFlowBfs

    ; --- Cerrar ventana: repaginar bank 0 ---
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    POP AF                          ; pop del stack temporal
    LD SP, (MaiFlowSavedSP)         ; restaurar stack original
    JP PO, .mcffNoEI
    EI
.mcffNoEI:
    RET

; ------------------------------------------------------------------------------
; MaiFlowBfs — cuerpo del BFS (asumiendo bank 6 ya paginado, SP en temp stack)
; ------------------------------------------------------------------------------
MaiFlowBfs:
    ; Limpiar FlowField a $FF
    LD HL, FlowField
    LD D, H
    LD E, L
    INC DE
    LD BC, 703
    LD (HL), $FF
    LDIR

    ; Init punteros de cola
    LD HL, BfsQueue
    LD (MaiFlowQHead), HL
    LD (MaiFlowQTail), HL

    ; Semilla: celda del player
    LD A, (MaiFlowPlCy)
    CALL MaiOffsetFromCy            ; HL = cy*32
    LD A, (MaiFlowPlCx)
    LD E, A
    LD D, 0
    ADD HL, DE                      ; HL = cy*32 + cx
    LD DE, FlowField
    ADD HL, DE
    LD (HL), 0                      ; dist = 0

    LD HL, (MaiFlowQTail)
    LD A, (MaiFlowPlCx)
    LD (HL), A
    INC HL
    LD A, (MaiFlowPlCy)
    LD (HL), A
    INC HL
    LD (MaiFlowQTail), HL

.mfbLoop:
    LD HL, (MaiFlowQHead)
    LD DE, (MaiFlowQTail)
    OR A
    SBC HL, DE
    RET Z                           ; queue vacia → done

    LD HL, (MaiFlowQHead)
    LD A, (HL)                      ; cx
    INC HL
    LD B, (HL)                      ; B = cy
    INC HL
    LD (MaiFlowQHead), HL
    LD C, A                         ; C = cx

    ; Leer distancia actual
    LD A, B
    CALL MaiOffsetFromCy
    LD E, C
    LD D, 0
    ADD HL, DE
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    INC A
    LD (MaiFlowNewDist), A

    ; N: (cx, cy-1)
    LD A, B
    OR A
    JR Z, .mfbSkipN
    DEC A
    LD D, A
    LD E, C
    CALL MaiTryCell
.mfbSkipN:
    ; S: (cx, cy+1)
    LD A, B
    CP 21
    JR Z, .mfbSkipS
    INC A
    LD D, A
    LD E, C
    CALL MaiTryCell
.mfbSkipS:
    ; W: (cx-1, cy)
    LD A, C
    OR A
    JR Z, .mfbSkipW
    DEC A
    LD E, A
    LD D, B
    CALL MaiTryCell
.mfbSkipW:
    ; E: (cx+1, cy)
    LD A, C
    CP 31
    JR Z, .mfbSkipE
    INC A
    LD E, A
    LD D, B
    CALL MaiTryCell
.mfbSkipE:
    JR .mfbLoop

; ------------------------------------------------------------------------------
; MaiOffsetFromCy — HL = cy * 32, dado A = cy
; ------------------------------------------------------------------------------
MaiOffsetFromCy:
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    RET

; ------------------------------------------------------------------------------
; MaiTryCell — marca y encola vecino si es pasable y no visitado.
; IN: E = nx, D = ny. Lee (MaiFlowNewDist) como distancia a escribir.
; ------------------------------------------------------------------------------
MaiTryCell:
    PUSH DE
    LD A, D
    CALL MaiOffsetFromCy            ; HL = ny*32
    POP DE
    PUSH DE
    LD A, E
    LD E, A
    LD D, 0
    ADD HL, DE                      ; HL = ny*32 + nx
    POP DE

    ; Check CollisionMap (RAM baja, accesible sin paginar)
    PUSH DE
    PUSH HL
    LD DE, CollisionMap
    ADD HL, DE
    LD A, (HL)
    OR A
    POP HL
    POP DE
    RET NZ                          ; bloqueado

    ; Check FlowField visited (bank 6, ya paginado)
    PUSH DE
    PUSH HL
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    CP $FF
    JR Z, .mtcMark
    POP HL
    POP DE
    RET                             ; ya visitado

.mtcMark:
    LD A, (MaiFlowNewDist)
    LD (HL), A
    POP HL
    POP DE

    LD HL, (MaiFlowQTail)
    LD (HL), E
    INC HL
    LD (HL), D
    INC HL
    LD (MaiFlowQTail), HL
    RET


; ==============================================================================
; MaiPickRandomGap
; ==============================================================================
; Selecciona un opening aleatorio del screen actual (ScreenGaps en bank 6) y
; traduce (side, coord) a posicion pixel con MAI_ENTRY_OFFSET aplicado.
;
; Output:
;   A = 0 exito; (MaiSpawnX), (MaiSpawnY) contienen posicion spawn
;   A = 1 no hay gaps validos; el caller debe usar fallback (LastEntryPos)
; Destruye: AF, BC, DE, HL
; ==============================================================================
MaiPickRandomGap:
    ; screen_id = Y * 16 + X
    LD A, (CurrentScreenY)
    RLCA
    RLCA
    RLCA
    RLCA
    LD HL, CurrentScreenX
    ADD A, (HL)
    LD (MaiGapScreenId), A

    ; Save IFF antes de cambiar stack (no cambiamos stack aqui; inline simple)
    LD A, I
    PUSH AF
    DI

    ; Inline page bank 6
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; --- BANK 6 PAGED. NO STACK OPS. NO CALLs. ---
    LD A, (MaiGapScreenId)
    LD L, A
    LD H, 0
    ADD HL, HL                      ; *2
    LD DE, ScreenGapsTable
    ADD HL, DE                      ; HL = &ScreenGapsTable[sid]

    ; Leer puntero record
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL                       ; HL = record ptr

    LD A, (HL)
    OR A
    JR Z, .mprgNoGapsPaged

    ; idx = R mod count
    LD B, A                         ; B = count
    LD A, R
.mprgMod:
    CP B
    JR C, .mprgModDone
    SUB B
    JR .mprgMod
.mprgModDone:
    INC HL                          ; skip count byte
    ADD A, A                        ; idx *= 2
    LD E, A
    LD D, 0
    ADD HL, DE

    LD A, (HL)
    LD (MaiGapSide), A
    INC HL
    LD A, (HL)
    LD (MaiGapCoord), A
    XOR A
    LD (MaiGapFallback), A
    JR .mprgPageBack

.mprgNoGapsPaged:
    LD A, 1
    LD (MaiGapFallback), A

.mprgPageBack:
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    POP AF
    JP PO, .mprgNoEI
    EI
.mprgNoEI:

    ; Stack ops nuevamente seguras. Despachar.
    LD A, (MaiGapFallback)
    OR A
    JR Z, .mprgTranslate
    LD A, 1
    RET

.mprgTranslate:
    LD A, (MaiGapCoord)
    LD B, A                         ; B = coord
    LD A, (MaiGapSide)

    CP MAI_SIDE_N
    JR Z, .mprgSideN
    CP MAI_SIDE_S
    JR Z, .mprgSideS
    CP MAI_SIDE_W
    JR Z, .mprgSideW
    ; side == E
    LD A, SCREEN_MAX_X - MAI_ENTRY_OFFSET
    LD (MaiSpawnX), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    ADD A, SCREEN_MIN_Y
    LD (MaiSpawnY), A
    XOR A
    RET

.mprgSideN:
    LD A, SCREEN_MIN_Y + MAI_ENTRY_OFFSET
    LD (MaiSpawnY), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (MaiSpawnX), A
    XOR A
    RET

.mprgSideS:
    LD A, SCREEN_MAX_Y - MAI_ENTRY_OFFSET
    LD (MaiSpawnY), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (MaiSpawnX), A
    XOR A
    RET

.mprgSideW:
    LD A, MAI_ENTRY_OFFSET
    LD (MaiSpawnX), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    ADD A, SCREEN_MIN_Y
    LD (MaiSpawnY), A
    XOR A
    RET


; ==============================================================================
; MaiPickRandomGapOnSide
; ==============================================================================
; Variante de MaiPickRandomGap que filtra por side concreto (N/S/W/E).
; Usado por Regla 2 (follow al cambiar room) para que los monsters entren
; por el mismo borde que uso el player.
;
; IN:  A = side deseado (MAI_SIDE_N/S/W/E)
; OUT: A = 0 ok (MaiSpawnX/Y llenos); A = 1 sin gaps en ese side → fallback
; ==============================================================================
MaiPickRandomGapOnSide:
    LD (MaiGapWantSide), A

    ; screen_id
    LD A, (CurrentScreenY)
    RLCA
    RLCA
    RLCA
    RLCA
    LD HL, CurrentScreenX
    ADD A, (HL)
    LD (MaiGapScreenId), A

    LD A, I
    PUSH AF
    DI

    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; HL = pointer al record
    LD A, (MaiGapScreenId)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, ScreenGapsTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL                       ; HL = record ptr

    LD A, (HL)
    OR A
    JP Z, .mosNoGaps
    LD B, A                         ; B = total count
    INC HL                          ; HL = first entry

    ; --- Pass 1: count entries matching wantSide ---
    PUSH HL                         ; save entries ptr
    PUSH BC                         ; save B (total)
    LD C, 0                         ; C = match count
.mosCountLoop:
    LD A, (HL)                      ; side
    INC HL
    INC HL                          ; skip coord byte → next entry
    LD E, A                         ; E = entry side
    LD A, (MaiGapWantSide)
    CP E
    JR NZ, .mosCountSkip
    INC C
.mosCountSkip:
    DJNZ .mosCountLoop

    LD A, C
    OR A
    JR NZ, .mosHaveMatch

    ; Sin matches en este side
    POP BC
    POP HL
    JP .mosNoGaps

.mosHaveMatch:
    ; C = count of matches. Pick random idx (into A, keep off C/B registers).
    LD B, C                         ; B = matches (divisor)
    LD A, R
.mosMod:
    CP B
    JR C, .mosModDone
    SUB B
    JR .mosMod
.mosModDone:
    ; A = target idx 0..matches-1. Descartar stack ANTES de moverlo a C,
    ; porque POP BC machaca C (bug anterior: target se perdia, siempre idx 0).
    POP BC                          ; discard saved total count
    POP HL                          ; HL = first entry ptr again
    LD C, A                         ; C = target match index
    LD B, 0                         ; B = matches seen so far

.mosFindLoop:
    LD A, (HL)                      ; side
    INC HL                          ; HL → coord
    LD E, A                         ; E = entry side
    LD A, (MaiGapWantSide)
    CP E
    JR NZ, .mosFindNext
    ; Match: is it the Cth?
    LD A, B
    CP C
    JR Z, .mosFound
    INC B
.mosFindNext:
    INC HL                          ; skip coord → next entry
    JR .mosFindLoop

.mosFound:
    ; HL at coord byte, E = side
    LD A, (HL)
    LD (MaiGapCoord), A
    LD A, E
    LD (MaiGapSide), A
    XOR A
    LD (MaiGapFallback), A
    JR .mosPageBack

.mosNoGaps:
    LD A, 1
    LD (MaiGapFallback), A

.mosPageBack:
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    POP AF
    JP PO, .mosNoEI
    EI
.mosNoEI:

    LD A, (MaiGapFallback)
    OR A
    JR Z, .mosTranslate
    LD A, 1
    RET

.mosTranslate:
    ; Reusar la misma logica de traduccion que MaiPickRandomGap
    LD A, (MaiGapCoord)
    LD B, A
    LD A, (MaiGapSide)

    CP MAI_SIDE_N
    JR Z, .mosSideN
    CP MAI_SIDE_S
    JR Z, .mosSideS
    CP MAI_SIDE_W
    JR Z, .mosSideW
    ; side == E
    LD A, SCREEN_MAX_X - MAI_ENTRY_OFFSET
    LD (MaiSpawnX), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    ADD A, SCREEN_MIN_Y
    LD (MaiSpawnY), A
    XOR A
    RET
.mosSideN:
    LD A, SCREEN_MIN_Y + MAI_ENTRY_OFFSET
    LD (MaiSpawnY), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (MaiSpawnX), A
    XOR A
    RET
.mosSideS:
    LD A, SCREEN_MAX_Y - MAI_ENTRY_OFFSET
    LD (MaiSpawnY), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (MaiSpawnX), A
    XOR A
    RET
.mosSideW:
    LD A, MAI_ENTRY_OFFSET
    LD (MaiSpawnX), A
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    ADD A, SCREEN_MIN_Y
    LD (MaiSpawnY), A
    XOR A
    RET


; ==============================================================================
; MaiPickNearestGapOnSide
; ==============================================================================
; Como MaiPickRandomGapOnSide pero en lugar de elegir aleatorio elige el
; opening del side cuya coord sea mas proxima a MaiGapTargetCoord. Usado
; por Regla 4 (reaparicion post-knockback) para que el monster vuelva por
; el mismo hueco del borde por donde fue empujado.
;
; IN:  A = side (MAI_SIDE_N/S/W/E), (MaiGapTargetCoord) = coord objetivo
; OUT: A = 0 ok (MaiSpawnX/Y llenos); A = 1 sin gaps en ese side
; ==============================================================================
MaiPickNearestGapOnSide:
    LD (MaiGapWantSide), A

    LD A, (CurrentScreenY)
    RLCA
    RLCA
    RLCA
    RLCA
    LD HL, CurrentScreenX
    ADD A, (HL)
    LD (MaiGapScreenId), A

    LD A, I
    PUSH AF
    DI

    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    LD A, (MaiGapScreenId)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, ScreenGapsTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL

    LD A, (HL)
    OR A
    JP Z, .mpnNoGaps
    LD B, A                         ; B = total count
    INC HL                          ; HL = first entry

    ; Inicializar best_dist=$FF, best_coord=0
    LD A, $FF
    LD (MaiFdBest), A               ; reutilizo MaiFdBest como best_dist
    XOR A
    LD (MaiGapCoord), A

.mpnLoop:
    LD A, (HL)                      ; side
    INC HL
    LD E, A                         ; E = entry side
    LD A, (MaiGapWantSide)
    CP E
    JR NZ, .mpnSkip                 ; no side match

    ; Match. Calcular |coord - target|
    LD A, (HL)                      ; coord de la entrada
    LD C, A                         ; C = entry coord
    LD A, (MaiGapTargetCoord)
    SUB C
    JR NC, .mpnAbsOk
    NEG
.mpnAbsOk:
    ; A = |target - coord|
    LD D, A
    LD A, (MaiFdBest)
    CP D
    JR C, .mpnSkip                  ; best < D → no mejor
    JR Z, .mpnSkip                  ; empate → mantener primer encontrado
    LD A, D
    LD (MaiFdBest), A
    LD A, C
    LD (MaiGapCoord), A

.mpnSkip:
    INC HL                          ; past coord byte
    DJNZ .mpnLoop

    ; Verificar que encontramos match
    LD A, (MaiFdBest)
    CP $FF
    JR Z, .mpnNoGaps

    ; Registrar side y marcar sin fallback
    LD A, (MaiGapWantSide)
    LD (MaiGapSide), A
    XOR A
    LD (MaiGapFallback), A
    JR .mpnPageBack

.mpnNoGaps:
    LD A, 1
    LD (MaiGapFallback), A

.mpnPageBack:
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    POP AF
    JP PO, .mpnNoEI
    EI
.mpnNoEI:

    LD A, (MaiGapFallback)
    OR A
    JR Z, .mpnTranslate
    LD A, 1
    RET

.mpnTranslate:
    ; Reutiliza la traduccion de MaiPickRandomGapOnSide.
    JP MaiPickRandomGapOnSide.mosTranslate


; ==============================================================================
; MaiGetEntrySide
; ==============================================================================
; Traduce ScreenTransition (direccion en la que se movio el player al cruzar
; el borde) al side de ENTRADA en el nuevo room (el borde opuesto).
;
;   DIR_N (player fue al norte) → SIDE_S (entro por el sur del nuevo room)
;   DIR_S → SIDE_N
;   DIR_E → SIDE_W
;   DIR_W → SIDE_E
;
; OUT: A = MAI_SIDE_N/S/W/E o $FF si no hay transicion activa.
; ==============================================================================
MaiGetEntrySide:
    LD A, (ScreenTransition)
    CP DIR_N
    JR Z, .mesSideS
    CP DIR_S
    JR Z, .mesSideN
    CP DIR_E
    JR Z, .mesSideW
    CP DIR_W
    JR Z, .mesSideE
    LD A, $FF
    RET
.mesSideN:
    LD A, MAI_SIDE_N
    RET
.mesSideS:
    LD A, MAI_SIDE_S
    RET
.mesSideW:
    LD A, MAI_SIDE_W
    RET
.mesSideE:
    LD A, MAI_SIDE_E
    RET


; ==============================================================================
; MaiMaybeRecomputeFlow
; ==============================================================================
; Llamado cada frame desde el main loop. Solo recalcula el flow field si la
; celda char del player ha cambiado desde el ultimo calculo. Cuando el player
; esta quieto, cero trabajo. El flow field permanece valido porque el mapa
; de walkability no cambia en runtime.
;
; Destruye: AF, BC, DE, HL (via MaiComputeFlowField)
; ==============================================================================
MaiMaybeRecomputeFlow:
    ; Sin monsters activos (dia, o antes de la primera noche) → no BFS.
    LD A, (MonstersActive)
    OR A
    RET Z

    ; Throttle: si el timer no ha expirado, decrementar y salir.
    LD A, (MaiFlowTimer)
    OR A
    JR Z, .mrfCheckCell
    DEC A
    LD (MaiFlowTimer), A
    RET

.mrfCheckCell:
    ; Celda del player
    LD A, (EntityTable + ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD B, A                         ; B = cx actual
    LD A, (EntityTable + ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD C, A                         ; C = cy actual

    LD A, (MaiFlowLastCx)
    CP B
    JR NZ, .mrfRecompute
    LD A, (MaiFlowLastCy)
    CP C
    RET Z                           ; misma celda → nada que hacer

.mrfRecompute:
    LD A, B
    LD (MaiFlowLastCx), A
    LD A, C
    LD (MaiFlowLastCy), A
    LD A, MAI_FLOW_INTERVAL
    LD (MaiFlowTimer), A
    JP MaiComputeFlowField          ; tail-call

; ==============================================================================
; MaiFlowFieldDirection
; ==============================================================================
; Lee el FlowField alrededor de la celda del monster y elige el vecino con
; menor distancia al player. Escribe (IX+ENT_DELTAX), (IX+ENT_DELTAY) con la
; direccion escogida (MONSTER_SPEED / -MONSTER_SPEED / 0).
;
; Si no hay vecino mejor (monster atrapado o en cell inalcanzable), deltas=0,0.
;
; IN:  IX = monster entity
; OUT: IX+ENT_DELTAX / ENT_DELTAY actualizados
; Destruye: AF, BC, DE, HL. Preserva IX.
; ==============================================================================
MaiFlowFieldDirection:
    ; Celda del monster
    LD A, (IX+ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiFdCx), A
    LD A, (IX+ENT_POSY)
    SUB SCREEN_MIN_Y
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (MaiFdCy), A

    ; Cambiar a stack temporal + guardar IFF
    LD (MaiFdSavedSP), SP
    LD SP, MaiTempStackTop
    LD A, I
    PUSH AF
    DI

    ; Inline page bank 6
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; --- BANK 6 PAGED ---
    ; Leer distancia actual (cell del monster)
    LD A, (MaiFdCy)
    CALL MaiOffsetFromCy            ; HL = cy*32
    LD A, (MaiFdCx)
    LD E, A
    LD D, 0
    ADD HL, DE                      ; HL = cy*32 + cx
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    LD (MaiFdBest), A               ; best = current; queremos < este

    LD A, MAI_DIR_NONE
    LD (MaiFdDir), A

    ; N: (cx, cy-1)
    LD A, (MaiFdCy)
    OR A
    JR Z, .mfdTryS
    DEC A
    CALL MaiOffsetFromCy            ; HL = (cy-1)*32
    LD A, (MaiFdCx)
    LD E, A
    LD D, 0
    ADD HL, DE
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    LD HL, MaiFdBest
    CP (HL)
    JR NC, .mfdTryS                 ; A >= best → no mejor
    LD (HL), A
    LD A, MAI_DIR_N
    LD (MaiFdDir), A

.mfdTryS:
    ; S: (cx, cy+1)
    LD A, (MaiFdCy)
    CP 21
    JR Z, .mfdTryW
    INC A
    CALL MaiOffsetFromCy
    LD A, (MaiFdCx)
    LD E, A
    LD D, 0
    ADD HL, DE
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    LD HL, MaiFdBest
    CP (HL)
    JR NC, .mfdTryW
    LD (HL), A
    LD A, MAI_DIR_S
    LD (MaiFdDir), A

.mfdTryW:
    ; W: (cx-1, cy)
    LD A, (MaiFdCx)
    OR A
    JR Z, .mfdTryE
    DEC A
    LD C, A                         ; nx = cx-1
    LD A, (MaiFdCy)
    CALL MaiOffsetFromCy
    LD A, C
    LD E, A
    LD D, 0
    ADD HL, DE
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    LD HL, MaiFdBest
    CP (HL)
    JR NC, .mfdTryE
    LD (HL), A
    LD A, MAI_DIR_W
    LD (MaiFdDir), A

.mfdTryE:
    ; E: (cx+1, cy)
    LD A, (MaiFdCx)
    CP 31
    JR Z, .mfdDone
    INC A
    LD C, A
    LD A, (MaiFdCy)
    CALL MaiOffsetFromCy
    LD A, C
    LD E, A
    LD D, 0
    ADD HL, DE
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    LD HL, MaiFdBest
    CP (HL)
    JR NC, .mfdDone
    LD (HL), A
    LD A, MAI_DIR_E
    LD (MaiFdDir), A

.mfdDone:
    ; Cerrar ventana de paginacion
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    POP AF
    LD SP, (MaiFdSavedSP)
    JP PO, .mfdNoEI
    EI
.mfdNoEI:

    ; Aplicar direccion
    LD A, (MaiFdDir)
    CP MAI_DIR_N
    JR Z, .mfdApplyN
    CP MAI_DIR_S
    JR Z, .mfdApplyS
    CP MAI_DIR_W
    JR Z, .mfdApplyW
    CP MAI_DIR_E
    JR Z, .mfdApplyE
    ; NONE: sin movimiento
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    RET
.mfdApplyN:
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), -MONSTER_SPEED
    RET
.mfdApplyS:
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), MONSTER_SPEED
    RET
.mfdApplyW:
    LD (IX+ENT_DELTAX), -MONSTER_SPEED
    LD (IX+ENT_DELTAY), 0
    RET
.mfdApplyE:
    LD (IX+ENT_DELTAX), MONSTER_SPEED
    LD (IX+ENT_DELTAY), 0
    RET


; ==============================================================================
; Datos locales (bank 2, RAM de trabajo del modulo)
; ==============================================================================
MaiFlowPlCx:      DEFB 0
MaiFlowPlCy:      DEFB 0
MaiFlowNewDist:   DEFB 0
MaiFlowQHead:     DEFW 0
MaiFlowQTail:     DEFW 0
MaiFlowSavedSP:   DEFW 0

MaiGapScreenId:   DEFB 0
MaiGapSide:       DEFB 0
MaiGapCoord:      DEFB 0
MaiGapFallback:   DEFB 0
MaiGapWantSide:   DEFB 0
MaiGapTargetCoord: DEFB 0      ; Coord objetivo para MaiPickNearestGapOnSide (Regla 4)

MaiSpawnX:        DEFB 0
MaiSpawnY:        DEFB 0

; $FF = nunca calculado, forzar recompute en frame 1
MaiFlowLastCx:    DEFB $FF
MaiFlowLastCy:    DEFB $FF
MaiFlowTimer:     DEFB 0          ; Throttle frames entre BFS consecutivos
MaiFdCx:          DEFB 0          ; Locales para MaiFlowFieldDirection
MaiFdCy:          DEFB 0
MaiFdBest:        DEFB 0
MaiFdDir:         DEFB 0
MaiFdSavedSP:     DEFW 0

; Stack temporal para MaiComputeFlowField (128 bytes).
; Usado solo durante la ventana de paginacion del BFS, para que los CALL
; internos no toquen el stack real (que vive en slot 3 paginable).
MaiTempStack:     DEFS 128
MaiTempStackTop:
