; ==============================================================================
; MONSTER AI v2 — runtime code (fase 3+)
; ==============================================================================
; Rutinas para el sistema de AI de monsters basado en flow field.
;
; Vive en bank 0 ($8000-$BFFF) como el resto del engine. Accede a buffers
; de bank 6 (FlowField, BfsQueue) paginando inline durante la BFS.
; ==============================================================================

; ==============================================================================
; MaiComputeFlowField
; ==============================================================================
; Calcula BFS de distancias desde la celda del player a todas las celdas del
; screen actual. Resultado: FlowField[cy*32+cx] = distancia (0..~50). Celdas
; inalcanzables o bloqueadas quedan en $FF (valor inicial).
;
; Coste: ~140000 T-states peor caso (grid entero alcanzable). Se debe llamar
; idealmente cada ~10 frames, no cada frame.
;
; Input: EntityTable[SLOT_PLAYER].POSX/POSY (pixeles)
; Output: FlowField relleno (en bank 6)
; Destruye: AF, BC, DE, HL
; ==============================================================================
MaiComputeFlowField:
    ; --- Calcular celda del player ---
    LD A, (EntityTable + ENT_POSX)
    RRCA
    RRCA
    RRCA
    AND $1F                         ; cx 0..31
    LD (.plCx), A

    LD A, (EntityTable + ENT_POSY)
    SUB SCREEN_MIN_Y                ; quitar offset HUD
    RRCA
    RRCA
    RRCA
    AND $1F                         ; cy 0..21 (truncado por mascara)
    LD (.plCy), A

    ; --- Paginar bank 6 al slot 3 ---
    LD A, 6
    CALL PageBankSlot3

    ; --- Limpiar FlowField a $FF ---
    LD HL, FlowField
    LD D, H
    LD E, L
    INC DE
    LD BC, 703
    LD (HL), $FF
    LDIR

    ; --- Init punteros de cola ---
    LD HL, BfsQueue
    LD (.qHead), HL
    LD (.qTail), HL

    ; --- Semilla: celda del player, dist=0 ---
    LD A, (.plCy)
    CALL .offsetFromCy              ; HL = cy*32
    LD A, (.plCx)
    LD E, A
    LD D, 0
    ADD HL, DE                      ; HL = cy*32 + cx
    LD DE, FlowField
    ADD HL, DE
    LD (HL), 0

    ; Encolar (plCx, plCy)
    LD HL, (.qTail)
    LD A, (.plCx)
    LD (HL), A
    INC HL
    LD A, (.plCy)
    LD (HL), A
    INC HL
    LD (.qTail), HL

    ; --- Bucle principal ---
.loop:
    ; Queue vacia si qHead == qTail
    LD HL, (.qHead)
    LD DE, (.qTail)
    OR A
    SBC HL, DE
    JR Z, .done

    ; Dequeue (cx, cy)
    LD HL, (.qHead)
    LD A, (HL)                      ; cx
    INC HL
    LD B, (HL)                      ; B = cy
    INC HL
    LD (.qHead), HL
    LD C, A                         ; C = cx

    ; Leer dist actual de FlowField[cy*32 + cx]
    LD A, B
    CALL .offsetFromCy              ; HL = cy*32
    LD E, C
    LD D, 0
    ADD HL, DE                      ; HL = cy*32 + cx
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    INC A                           ; A = distancia de vecino
    LD (.newDist), A

    ; --- Expandir 4 vecinos ---
    ; N: (cx, cy-1)
    LD A, B
    OR A
    JR Z, .skipN
    DEC A
    LD D, A
    LD E, C
    CALL .tryCell
.skipN:
    ; S: (cx, cy+1)
    LD A, B
    CP 21
    JR Z, .skipS
    INC A
    LD D, A
    LD E, C
    CALL .tryCell
.skipS:
    ; W: (cx-1, cy)
    LD A, C
    OR A
    JR Z, .skipW
    DEC A
    LD E, A
    LD D, B
    CALL .tryCell
.skipW:
    ; E: (cx+1, cy)
    LD A, C
    CP 31
    JR Z, .skipE
    INC A
    LD E, A
    LD D, B
    CALL .tryCell
.skipE:
    JR .loop

.done:
    ; Restaurar bank 0
    XOR A
    CALL PageBankSlot3
    RET

; ------------------------------------------------------------------------------
; .offsetFromCy — HL = cy * 32, dado A = cy (preserva BC, DE)
; ------------------------------------------------------------------------------
.offsetFromCy:
    LD L, A
    LD H, 0
    ADD HL, HL                      ; ×2
    ADD HL, HL                      ; ×4
    ADD HL, HL                      ; ×8
    ADD HL, HL                      ; ×16
    ADD HL, HL                      ; ×32
    RET

; ------------------------------------------------------------------------------
; .tryCell — Si (E=nx, D=ny) es pasable y no visitado, marca y encola.
; IN: E = nx, D = ny. Usa (.newDist) como distancia a escribir.
; Destroys: AF, HL (preserva BC y restaura DE=nx,ny al entrar en enqueue).
; ------------------------------------------------------------------------------
.tryCell:
    ; Offset = ny * 32 + nx → HL
    PUSH DE
    LD A, D
    CALL .offsetFromCy              ; HL = ny*32
    POP DE
    PUSH DE
    LD A, E
    LD E, A
    LD D, 0
    ADD HL, DE                      ; HL = ny*32 + nx
    POP DE

    ; --- Check CollisionMap (RAM baja, no requiere paginar) ---
    PUSH DE                         ; preservar nx/ny
    PUSH HL                         ; preservar offset
    LD DE, CollisionMap
    ADD HL, DE
    LD A, (HL)
    OR A
    POP HL
    POP DE
    RET NZ                          ; 1 = bloqueado, skip

    ; --- Check FlowField visited (bank 6 ya paginado) ---
    PUSH DE                         ; preservar nx/ny para enqueue
    PUSH HL                         ; preservar offset
    LD DE, FlowField
    ADD HL, DE
    LD A, (HL)
    CP $FF
    JR Z, .tcMark
    POP HL
    POP DE
    RET                             ; ya visitado, skip

.tcMark:
    LD A, (.newDist)
    LD (HL), A                      ; FlowField[offset] = dist
    POP HL                          ; descartar offset
    POP DE                          ; nx (E), ny (D)

    ; Encolar (E=cx, D=cy)
    LD HL, (.qTail)
    LD (HL), E
    INC HL
    LD (HL), D
    INC HL
    LD (.qTail), HL
    RET

; ------------------------------------------------------------------------------
; Locals
; ------------------------------------------------------------------------------
.plCx:    DEFB 0
.plCy:    DEFB 0
.newDist: DEFB 0
.qHead:   DEFW 0
.qTail:   DEFW 0
