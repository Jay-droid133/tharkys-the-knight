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
    ; IFF tracking via StartupComplete (RAM) - evita race del LD A,I
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

    LD SP, (MaiFlowSavedSP)         ; restaurar stack original
    LD A, (StartupComplete)
    OR A
    JR Z, .mcffNoEI                 ; aun en Inicio -> dejar DI
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
; MaiGetCurrentScreenId - A = screen_id (Y*16+X) del room actual del player.
; Preserva: BC, DE, HL, IX.
; ==============================================================================
MaiGetCurrentScreenId:
    PUSH HL
    LD A, (CurrentScreenY)
    RLCA
    RLCA
    RLCA
    RLCA
    LD HL, CurrentScreenX
    ADD A, (HL)
    POP HL
    RET

; ==============================================================================
; MaiGetNeighborScreenId - A = screen_id del vecino segun DIR de salida.
; Input:  A = DIR_N/S/E/W (1/2/4/8). Otros valores → preserva current id.
; Output: A = screen_id del vecino (wraparound de 8 bits si X/Y sale de rango).
; Preserva: BC, DE, HL, IX.
; ==============================================================================
MaiGetNeighborScreenId:
    PUSH BC
    LD B, A                             ; B = dir
    LD A, (CurrentScreenY)
    RLCA
    RLCA
    RLCA
    RLCA
    LD C, A                             ; C = Y*16
    LD A, (CurrentScreenX)
    ADD A, C                            ; A = current_id
    LD C, A                             ; C = current_id
    LD A, B                             ; A = dir
    CP DIR_N
    JR Z, .mgnN
    CP DIR_S
    JR Z, .mgnS
    CP DIR_E
    JR Z, .mgnE
    CP DIR_W
    JR Z, .mgnW
    LD A, C
    POP BC
    RET
.mgnN:
    LD A, C
    SUB 16
    POP BC
    RET
.mgnS:
    LD A, C
    ADD A, 16
    POP BC
    RET
.mgnE:
    LD A, C
    INC A
    POP BC
    RET
.mgnW:
    LD A, C
    DEC A
    POP BC
    RET

; ==============================================================================
; MaiGetOldScreenId - A = screen_id del room de donde vino el player (en
; el momento actual de la transicion). Usa ScreenTransition.
; Preserva: BC, DE, HL, IX.
; ==============================================================================
MaiGetOldScreenId:
    LD A, (ScreenTransition)
    CP DIR_N
    JR Z, .gosFlipS
    CP DIR_S
    JR Z, .gosFlipN
    CP DIR_E
    JR Z, .gosFlipW
    CP DIR_W
    JR Z, .gosFlipE
    JP MaiGetCurrentScreenId            ; Sin transicion: devolver current
.gosFlipS:
    LD A, DIR_S
    JP MaiGetNeighborScreenId
.gosFlipN:
    LD A, DIR_N
    JP MaiGetNeighborScreenId
.gosFlipW:
    LD A, DIR_W
    JP MaiGetNeighborScreenId
.gosFlipE:
    LD A, DIR_E
    JP MaiGetNeighborScreenId

; ==============================================================================
; MaiDirToEntrySide - A = MAI_SIDE correspondiente al DIR de salida opuesto.
; Si monster sale por DIR_N (arriba), entra al vecino por el S → MAI_SIDE_S.
; Input:  A = DIR_N/S/E/W. Output: A = MAI_SIDE_N/S/W/E ($FF si invalido).
; ==============================================================================
MaiDirToEntrySide:
    CP DIR_N
    JR Z, .mdesSideS
    CP DIR_S
    JR Z, .mdesSideN
    CP DIR_E
    JR Z, .mdesSideW
    CP DIR_W
    JR Z, .mdesSideE
    LD A, $FF
    RET
.mdesSideS:
    LD A, MAI_SIDE_S
    RET
.mdesSideN:
    LD A, MAI_SIDE_N
    RET
.mdesSideW:
    LD A, MAI_SIDE_W
    RET
.mdesSideE:
    LD A, MAI_SIDE_E
    RET


; ==============================================================================
; MaiGetMonsterSlot - IX = monster entity → A = slot index (0/1/2).
; Preserva: BC, DE, HL, IX.
; ==============================================================================
MaiGetMonsterSlot:
    PUSH HL
    PUSH DE
    PUSH IX
    POP HL
    LD DE, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    OR A
    SBC HL, DE
    SRL L
    SRL L
    SRL L
    SRL L                               ; /16 = ENT_SIZE
    LD A, L
    POP DE
    POP HL
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

    ; IFF tracking via StartupComplete (RAM) - evita race del LD A,I
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

    LD A, (StartupComplete)
    OR A
    JR Z, .mprgNoEI                 ; aun en Inicio -> dejar DI
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

    ; IFF tracking via StartupComplete (RAM) - evita race del LD A,I
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

    LD A, (StartupComplete)
    OR A
    JR Z, .mosNoEI                  ; aun en Inicio -> dejar DI
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

    ; IFF tracking via StartupComplete (RAM) - evita race del LD A,I
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

    LD A, (StartupComplete)
    OR A
    JR Z, .mpnNoEI                  ; aun en Inicio -> dejar DI
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

    ; Cambiar a stack temporal. IFF tracking via StartupComplete (RAM).
    LD (MaiFdSavedSP), SP
    LD SP, MaiTempStackTop
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
    LD SP, (MaiFdSavedSP)
    LD A, (StartupComplete)
    OR A
    JR Z, .mfdNoEI                  ; aun en Inicio -> dejar DI
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
; BuildZoneCellList - construye ZoneCellList (main RAM) iterando FlowField
; ==============================================================================
; Llamada desde DrawScreen al entrar a una sala (tras MaiComputeFlowField).
; Anade (cx, cy) a la lista para CADA celda alcanzable desde el player en su
; posicion de entrada (FlowField byte != $FF). La lista representa el "hueco"
; completo donde puedo estar, sin filtro de proximidad.
; Cap 255 entradas. SpawnOneNasty elige idx random de aqui.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
BuildZoneCellList:
    XOR A
    LD (ZoneCellCount), A
    LD HL, ZoneCellList
    LD (.bzclPtr), HL
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD DE, FlowField
    LD C, 0                                 ; cy
.bzclRow:
    LD B, 0                                 ; cx
.bzclCol:
    LD A, (DE)
    INC DE
    CP $FF
    JR Z, .bzclSkipCell
    ; Append (cx, cy)
    LD A, (ZoneCellCount)
    CP 255
    JR Z, .bzclSkipCell
    INC A
    LD (ZoneCellCount), A
    LD HL, (.bzclPtr)
    LD (HL), B                              ; cx
    INC HL
    LD (HL), C                              ; cy
    INC HL
    LD (.bzclPtr), HL
.bzclSkipCell:
    INC B
    LD A, B
    CP 32
    JR NZ, .bzclCol
    INC C
    LD A, C
    CP 22
    JR NZ, .bzclRow
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (StartupComplete)
    OR A
    JR Z, .bzclNoEI
    EI
.bzclNoEI:
    RET
.bzclPtr:  DEFW 0

; ==============================================================================
; CheckPlayerZoneAtChar - test si la celda (D=cy, E=cx) es alcanzable
; ==============================================================================
; Lee FlowField (bank 6) en offset cy*32+cx. FlowField se actualiza al cambiar
; de sala via MaiComputeFlowField llamado desde DrawScreen.
; OUT: Z si NO alcanzable (FlowField == $FF), NZ si alcanzable.
; Destruye: AF, BC, HL.
; ==============================================================================
CheckPlayerZoneAtChar:
    ; offset = cy*32 + cx
    LD H, 0
    LD L, D
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; HL = cy * 32
    LD A, E
    ADD A, L
    LD L, A
    JR NC, .cpzaNoCarry
    INC H
.cpzaNoCarry:
    LD BC, FlowField
    ADD HL, BC                              ; HL = FlowField + offset
    PUSH HL
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    POP HL
    LD A, (HL)                              ; FlowField byte
    PUSH AF
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (StartupComplete)
    OR A
    JR Z, .cpzaNoEI
    EI
.cpzaNoEI:
    POP AF
    INC A                                   ; $FF -> 0 (Z = unreachable), else NZ (reachable)
    RET

; ==============================================================================
; FindFarthestZoneCell - Celda alcanzable mas lejana, validada como spawn nasty
; ==============================================================================
; Escanea FlowField (bank 6, 32x22) y devuelve la (cx, cy) con MAYOR distancia
; BFS al player que ademas pase las restricciones equivalentes a SpawnOneNasty:
;   1. FlowField != $FF (alcanzable desde el player).
;   2. Bounds del bbox 24x24: cx <= MAX_CX, cy <= MAX_CY.
;   3. 4 esquinas del bbox no solidas en CollisionMap (mismo criterio que
;      SpawnOneNasty: solo izq/dcha extremas, no medio).
;
; Empieza con BestDist=0; la celda del player tiene dist=0 y se descarta por
; ser update estricto (>). Si nada cualifica retorna Z.
;
; OUT:
;   NZ + B=cx, C=cy, A=dist  -> celda encontrada
;   Z                         -> sin candidato valido
; Destruye: AF, BC, DE, HL.
; ==============================================================================
FFZ_MAX_CX  EQU 29                          ; (232 - 24) / 8 + 1 (POSX+23 no wrap)
FFZ_MAX_CY  EQU 16                          ; (168 - 24 - 16) / 8 (POSY+23 < SCREEN_MAX_Y)
FindFarthestZoneCell:
    XOR A
    LD (.ffzBestDist), A
    LD (.ffzBestCx), A
    LD (.ffzBestCy), A
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD DE, FlowField
    LD C, 0                                 ; cy
.ffzRow:
    LD B, 0                                 ; cx
.ffzCol:
    LD A, (DE)
    INC DE
    CP $FF
    JR Z, .ffzSkip                          ; inalcanzable
    LD (.ffzCurDist), A                     ; cachear dist
    ; Bounds del sprite 24x24
    LD A, B
    CP FFZ_MAX_CX + 1
    JR NC, .ffzSkip
    LD A, C
    CP FFZ_MAX_CY + 1
    JR NC, .ffzSkip
    ; Solo evaluar esquinas si la dist mejora la mejor actual
    LD A, (.ffzCurDist)
    LD HL, .ffzBestDist
    CP (HL)
    JR C, .ffzSkip                          ; dist < best
    JR Z, .ffzSkip                          ; dist == best
    ; --- 4 esquinas en CollisionMap: (cx,cy), (cx+2,cy), (cx,cy+2), (cx+2,cy+2)
    ; Equivale a las 4 esquinas pixel del bbox 24x24 a granularidad de char.
    PUSH BC                                 ; B=cx, C=cy
    PUSH DE
    LD H, 0
    LD L, C
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; HL = cy*32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .ffzCmNoCarry
    INC H
.ffzCmNoCarry:
    LD DE, CollisionMap
    ADD HL, DE                              ; HL = &CollisionMap[cy][cx]
    ; Esquina (cx, cy)
    LD A, (HL)
    OR A
    JR NZ, .ffzCornerBlocked
    ; → (cx+2, cy)
    INC HL
    INC HL
    LD A, (HL)
    OR A
    JR NZ, .ffzCornerBlocked
    ; → (cx+2, cy+2): bajar 2 filas (+64), col se queda en cx+2
    LD DE, 64
    ADD HL, DE
    LD A, (HL)
    OR A
    JR NZ, .ffzCornerBlocked
    ; → (cx, cy+2): retroceder 2 cols
    DEC HL
    DEC HL
    LD A, (HL)
    OR A
    JR NZ, .ffzCornerBlocked
    ; 4 esquinas libres
    POP DE
    POP BC
    LD A, (.ffzCurDist)
    LD (.ffzBestDist), A
    LD A, B
    LD (.ffzBestCx), A
    LD A, C
    LD (.ffzBestCy), A
    JR .ffzSkip
.ffzCornerBlocked:
    POP DE
    POP BC
.ffzSkip:
    INC B
    LD A, B
    CP 32
    JR NZ, .ffzCol
    INC C
    LD A, C
    CP 22
    JR NZ, .ffzRow
    ; Cerrar paging
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (StartupComplete)
    OR A
    JR Z, .ffzNoEI
    EI
.ffzNoEI:
    LD A, (.ffzBestDist)
    OR A
    RET Z
    LD A, (.ffzBestCx)
    LD B, A
    LD A, (.ffzBestCy)
    LD C, A
    LD A, (.ffzBestDist)
    OR A
    RET
.ffzBestDist: DEFB 0
.ffzBestCx:   DEFB 0
.ffzBestCy:   DEFB 0
.ffzCurDist:  DEFB 0

; ==============================================================================
; UpdateMonsterLeave - Salida al amanecer (Regla 7 / STATE_LEAVING)
; ==============================================================================
; IX = monster entity en STATE_SCARED.
;
; Primera llamada (flag MAI_FLAG_LEAVING clear): elige un gap aleatorio del
; screen actual, guarda side+coord en MonsterEntryBorder/ExitCoord[slot] y
; marca el flag. Llamadas posteriores: camina hacia el pixel del gap con AI
; hibrida simplificada (greedy + persistence + 4 candidatos). Al llegar al
; pixel objetivo setea NastyFleeDespawn=1 → .peScaredDespawn borra sprite
; limpiamente (sin puff).
;
; Fallback: si el screen no tiene gaps, tail-call a UpdateNastyFlee.
;
; Destruye: AF, BC, DE, HL. Preserva IX.
; ==============================================================================
UpdateMonsterLeave:
    ; --- Slot index (0..2) desde IX ---
    PUSH IX
    POP HL
    LD DE, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    OR A
    SBC HL, DE
    SRL L
    SRL L
    SRL L
    SRL L                               ; /16 = ENT_SIZE
    LD A, L
    LD (MulSlot), A

    ; --- Lazy init: picar gap si flag clear ---
    LD E, A
    LD D, 0
    LD HL, MonsterAiFlags
    ADD HL, DE
    LD A, (HL)
    AND MAI_FLAG_LEAVING
    JR NZ, .mulHaveGap

    CALL MaiPickRandomGap
    OR A
    JP NZ, UpdateNastyFlee              ; Sin gaps → fallback
    ; Guardar side/coord per-slot
    LD A, (MulSlot)
    LD E, A
    LD D, 0
    LD HL, MonsterEntryBorder
    ADD HL, DE
    LD A, (MaiGapSide)
    LD (HL), A
    LD HL, MonsterExitCoord
    ADD HL, DE
    LD A, (MaiGapCoord)
    LD (HL), A
    LD HL, MonsterAiFlags
    ADD HL, DE
    LD A, (HL)
    OR MAI_FLAG_LEAVING
    LD (HL), A

.mulHaveGap:
    ; --- Cargar side/coord y traducir a pixel (MaiSpawnX/Y) ---
    LD A, (MulSlot)
    LD E, A
    LD D, 0
    LD HL, MonsterEntryBorder
    ADD HL, DE
    LD A, (HL)
    LD (MaiGapSide), A
    LD HL, MonsterExitCoord
    ADD HL, DE
    LD A, (HL)
    LD (MaiGapCoord), A
    CALL MaiPickRandomGap.mprgTranslate ; Escribe MaiSpawnX/Y

    ; --- Reach (char-align): char top-left del monster == char del gap.
    ; Tolerancia 1 char (AND $F8) = monster visualmente en el footprint
    ; del gap. ---
    LD A, (IX+ENT_POSX)
    AND $F8
    LD B, A
    LD A, (MaiSpawnX)
    AND $F8
    CP B
    JR NZ, .mulNotReached
    LD A, (IX+ENT_POSY)
    AND $F8
    LD B, A
    LD A, (MaiSpawnY)
    AND $F8
    CP B
    JR NZ, .mulNotReached
    LD A, 1
    LD (NastyFleeDespawn), A
    RET

.mulNotReached:
    ; --- Escape bbox-stuck: si el bbox del monster solapa una wall en su
    ; posicion actual, empujar 2px hacia el gap. Uso CheckEnemyCollision
    ; (chequea todo el bbox) en vez de IsPointBlocked (solo top-left) —
    ; el monster desalineado al gap cubre 3 chars de ancho y queda atascado
    ; con el top-left en celda libre pero el bbox solapando walls adyacentes. ---
    CALL CheckEnemyCollision
    JR Z, .mulNotInWall
    ; Stuck: empujar 2px hacia (MaiSpawnX, MaiSpawnY) leyendo IX directo
    ; (CheckEnemyCollision destruye BC/DE).
    LD A, (MaiSpawnX)
    CP (IX+ENT_POSX)
    JR Z, .mulWallXDone
    JR C, .mulWallLeft
    LD A, (IX+ENT_POSX)
    ADD A, 2
    JR .mulWallSetX
.mulWallLeft:
    LD A, (IX+ENT_POSX)
    SUB 2
.mulWallSetX:
    LD (IX+ENT_POSX), A
.mulWallXDone:
    LD A, (MaiSpawnY)
    CP (IX+ENT_POSY)
    JR Z, .mulWallYDone
    JR C, .mulWallUp
    LD A, (IX+ENT_POSY)
    ADD A, 2
    JR .mulWallSetY
.mulWallUp:
    LD A, (IX+ENT_POSY)
    SUB 2
.mulWallSetY:
    LD (IX+ENT_POSY), A
.mulWallYDone:
    JP .mulAnimate                      ; skip AI este frame, reintentar el siguiente
.mulNotInWall:

    ; --- hDx = sign(tx - POSX) ---
    LD A, (MaiSpawnX)
    SUB (IX+ENT_POSX)
    JR Z, .mulNoDx
    LD A, MONSTER_SPEED
    JR NC, .mulDxDone
    LD A, -MONSTER_SPEED
    JR .mulDxDone
.mulNoDx:
    XOR A
.mulDxDone:
    LD (MulHDx), A

    LD A, (MaiSpawnY)
    SUB (IX+ENT_POSY)
    JR Z, .mulNoDy
    LD A, MONSTER_SPEED
    JR NC, .mulDyDone
    LD A, -MONSTER_SPEED
    JR .mulDyDone
.mulNoDy:
    XOR A
.mulDyDone:
    LD (MulVDy), A

    ; --- Randomize eje alineado (cuando aligned, da candidatos laterales) ---
    LD A, (MulHDx)
    OR A
    JR NZ, .mulHdxOk
    LD A, R
    AND 1
    LD A, MONSTER_SPEED
    JR NZ, .mulHdxSet
    NEG
.mulHdxSet:
    LD (MulHDx), A
.mulHdxOk:
    LD A, (MulVDy)
    OR A
    JR NZ, .mulVdyOk
    LD A, R
    AND 1
    LD A, MONSTER_SPEED
    JR NZ, .mulVdySet
    NEG
.mulVdySet:
    LD (MulVDy), A
.mulVdyOk:

    ; --- Greedy primary: eje con mayor |delta| al objetivo ---
    LD A, (MaiSpawnX)
    SUB (IX+ENT_POSX)
    JR NC, .mulGrDxOk
    NEG
.mulGrDxOk:
    LD B, A                             ; B = |dx|
    LD A, (MaiSpawnY)
    SUB (IX+ENT_POSY)
    JR NC, .mulGrDyOk
    NEG
.mulGrDyOk:
    CP B
    JR NC, .mulGreedyVert               ; |dy| >= |dx| → vertical primary
    ; Horizontal primary
    LD A, (MulHDx)
    LD D, A
    LD E, 0
    JR .mulGreedyTry
.mulGreedyVert:
    LD D, 0
    LD A, (MulVDy)
    LD E, A
.mulGreedyTry:
    CALL MulTryPassable
    JP Z, .mulApply

    ; --- Diagonal primario (hDx, vDy): progresa en AMBOS ejes hacia target.
    ; Salto si cualquier componente es 0 (pure axis, ya cubierta por greedy). ---
    LD A, (MulHDx)
    LD D, A
    OR A
    JR Z, .mulRecalc
    LD A, (MulVDy)
    LD E, A
    OR A
    JR Z, .mulRecalc
    CALL MulTryPassable
    JP Z, .mulApply

    ; Nota: la "persistence" del AI normal (UpdateMonster) se ha eliminado en
    ; este flee. Con target fijo (gap), persistence tendia a re-aplicar un
    ; backtrack previo → oscilacion contra la pared. Los 4 candidatos + 4
    ; diagonales de .mulRecalc cubren las opciones necesarias.

.mulRecalc:
    ; --- Full recalc: 4 candidatos ordenados por eje primario ---
    LD A, (MaiSpawnX)
    SUB (IX+ENT_POSX)
    JR NC, .mulAbsDxOk
    NEG
.mulAbsDxOk:
    LD B, A
    LD A, (MaiSpawnY)
    SUB (IX+ENT_POSY)
    JR NC, .mulAbsDyOk
    NEG
.mulAbsDyOk:
    CP B
    JR NC, .mulVertPrim                 ; |dy| >= |dx| → vertical primary
    ; Horizontal primary: (hDx,0), (0,vDy), (0,-vDy), (-hDx,0)
    LD HL, MulCandidates
    LD A, (MulHDx)
    LD (HL), A
    INC HL
    XOR A
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD A, (MulVDy)
    LD (HL), A
    INC HL
    XOR A
    LD (HL), A
    INC HL
    LD A, (MulVDy)
    NEG
    LD (HL), A
    INC HL
    LD A, (MulHDx)
    NEG
    LD (HL), A
    INC HL
    XOR A
    LD (HL), A
    JR .mulTryCands

.mulVertPrim:
    ; Vertical primary: (0,vDy), (hDx,0), (-hDx,0), (0,-vDy)
    LD HL, MulCandidates
    XOR A
    LD (HL), A
    INC HL
    LD A, (MulVDy)
    LD (HL), A
    INC HL
    LD A, (MulHDx)
    LD (HL), A
    INC HL
    XOR A
    LD (HL), A
    INC HL
    LD A, (MulHDx)
    NEG
    LD (HL), A
    INC HL
    XOR A
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD A, (MulVDy)
    NEG
    LD (HL), A

.mulTryCands:
    LD HL, MulCandidates
    LD B, 4
.mulLoop:
    LD D, (HL)
    INC HL
    LD E, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .mulLoopSkip
    PUSH HL
    PUSH BC
    CALL MulTryPassable
    POP BC
    POP HL
    JR Z, .mulApply
.mulLoopSkip:
    DJNZ .mulLoop
    ; --- Pass 3: diagonales (salir de pockets, igual que UpdateNastyFlee) ---
    LD A, (MulHDx)
    LD D, A
    LD A, (MulVDy)
    LD E, A
    CALL MulTryPassable
    JP Z, .mulApply
    LD A, (MulHDx)
    NEG
    LD D, A
    LD A, (MulVDy)
    LD E, A
    CALL MulTryPassable
    JP Z, .mulApply
    LD A, (MulHDx)
    LD D, A
    LD A, (MulVDy)
    NEG
    LD E, A
    CALL MulTryPassable
    JP Z, .mulApply
    LD A, (MulHDx)
    NEG
    LD D, A
    LD A, (MulVDy)
    NEG
    LD E, A
    CALL MulTryPassable
    JP Z, .mulApply
    ; Todo bloqueado de verdad → quieto este frame
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    JP .mulAnimate

.mulApply:
    LD (IX+ENT_DELTAX), D
    LD (IX+ENT_DELTAY), E
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    ; Clamp X suave: permitir POSX hasta 239 para que pueda alcanzar
    ; el target del gap E (=SCREEN_MAX_X=232). Con el clamp estricto el
    ; monster quedaba atascado en 231 y el reach char-align nunca matcheaba
    ; (231 & $F8 = 224, target 232 & $F8 = 232). POSX >= 240 = underflow.
    LD A, (IX+ENT_POSX)
    CP 240
    JR C, .mulXOk
    XOR A
    LD (IX+ENT_POSX), A
.mulXOk:
    ; Clamp Y suave (como .moApply): 0-199 valido, >=200 = underflow
    LD A, (IX+ENT_POSY)
    CP 200
    JR C, .mulYOk
    XOR A
    LD (IX+ENT_POSY), A
.mulYOk:

.mulAnimate:
    ; Animacion tipo .moAnimate simplificada (sin stun).
    LD A, (IX+ENT_DELTAX)
    OR A
    JR Z, .mulKeepDir
    BIT 7, A
    LD C, MONSTER_FRAMES_RIGHT
    JR Z, .mulAnimTick
    LD C, MONSTER_FRAMES_LEFT
    JR .mulAnimTick
.mulKeepDir:
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    CP MONSTER_FRAMES_LEFT
    LD C, MONSTER_FRAMES_LEFT
    JR NC, .mulAnimTick
    LD C, MONSTER_FRAMES_RIGHT
.mulAnimTick:
    DEC (IX+ENT_ANIMTIMER)
    JR NZ, .mulAnimDone
    LD A, ENEMY_ANIM_DELAY
    LD (IX+ENT_ANIMTIMER), A
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    AND MONSTER_BOUNCE_LEN - 1
    INC A
    CP MONSTER_BOUNCE_LEN
    JR C, .mulFrameSet
    XOR A
.mulFrameSet:
    ADD A, C
    ADD A, (IX+ENT_ANIMBASE)
    LD (IX+ENT_SPRITEID), A
.mulAnimDone:
    RET

; ------------------------------------------------------------------------------
; MulTryPassable: D=deltaX, E=deltaY. Z=pasable, NZ=bloqueado. Preserva D,E,IX.
; Solo comprueba colision con fondo (no overlap monster/player durante fuga).
; ------------------------------------------------------------------------------
MulTryPassable:
    PUSH DE
    LD A, (IX+ENT_POSX)
    LD (MulSvX), A
    LD A, (IX+ENT_POSY)
    LD (MulSvY), A
    LD A, (IX+ENT_POSX)
    ADD A, D
    LD (IX+ENT_POSX), A
    LD A, (IX+ENT_POSY)
    ADD A, E
    LD (IX+ENT_POSY), A
    CALL CheckEnemyCollision
    PUSH AF
    LD A, (MulSvX)
    LD (IX+ENT_POSX), A
    LD A, (MulSvY)
    LD (IX+ENT_POSY), A
    POP AF
    POP DE
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

; Locales de UpdateMonsterLeave (Regla 7)
MulSlot:          DEFB 0
MulHDx:           DEFB 0
MulVDy:           DEFB 0
MulSvX:           DEFB 0
MulSvY:           DEFB 0
MulCandidates:    DEFS 8            ; 4 pares (dx, dy)

; Stack temporal para MaiComputeFlowField (128 bytes).
; Usado solo durante la ventana de paginacion del BFS, para que los CALL
; internos no toquen el stack real (que vive en slot 3 paginable).
MaiTempStack:     DEFS 128
MaiTempStackTop:
