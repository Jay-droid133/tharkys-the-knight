; ==============================================================================
; CADENA DE HITOS (CurrentObjective + resolucion de coordenadas)
; ==============================================================================
; CurrentObjective vive en variables.asm. Valor:
;   0..8 = hito que el jugador esta buscando ahora mismo (1..9 humano)
;   9    = todos los hitos completados (juego ganado)
;
; ----------------------------------------------------------------------------
; MilestoneTable: 9 entradas x 2 bytes {tipo, ref} - regla de AVANCE.
;   tipo 1 (PICKUP)  -> ref es key id 1..6 (ver KeyLockTable). Avanza al
;                       recoger el sprite cuyo behavior coincide.
;   tipo 2 (TRIGGER) -> ref es action id de BumpTriggerTable
;                       (1=townhall, 2=churchdoor, futuro 3=towngate).
;                       Avanza al disparar el trigger correspondiente.
;   tipo 3 (SPECIAL) -> ref ignorado. Solo avanza con la tecla M (debug stub).
;
; MilestoneResolveTable: 9 x 2 bytes {tipo, ref} - regla de RESOLUCION
; (a que pantalla apunta la brujula). Igual que MilestoneTable salvo:
;   - Hito 7 (SPECIAL para advance): se resuelve como TRIGGER action 2
;     (puerta de la iglesia), donde se "encerrara" a los monsters.
;   - Hito 9 (SPECIAL para advance): se resuelve como TRIGGER action 3
;     (puerta sur, sin trigger todavia -> $FF, $FF hasta que exista).
;
; Tecla M (debug): incrementa CurrentObjective sin chequear tipo. Skip libre,
; util para probar la cadena entera mientras los hitos 7 y 9 no tienen
; mecanica real.
; ==============================================================================

MILESTONE_TYPE_PICKUP   EQU 1
MILESTONE_TYPE_TRIGGER  EQU 2
MILESTONE_TYPE_SPECIAL  EQU 3

MilestoneTable:
    DEFB MILESTONE_TYPE_PICKUP,   1     ; #1 llave del bosque
    DEFB MILESTONE_TYPE_PICKUP,   2     ; #2 llave de las ruinas
    DEFB MILESTONE_TYPE_PICKUP,   3     ; #3 llave del cementerio
    DEFB MILESTONE_TYPE_PICKUP,   4     ; #4 llave del reloj
    DEFB MILESTONE_TYPE_TRIGGER,  1     ; #5 puerta del ayuntamiento
    DEFB MILESTONE_TYPE_PICKUP,   5     ; #6 llave de la iglesia (dinamica)
    DEFB MILESTONE_TYPE_SPECIAL,  0     ; #7 encerrar monsters (stub: tecla M)
    DEFB MILESTONE_TYPE_PICKUP,   6     ; #8 llave de la puerta sur (dinamica)
    DEFB MILESTONE_TYPE_SPECIAL,  0     ; #9 puerta sur (stub: tecla M)

MilestoneResolveTable:
    DEFB MILESTONE_TYPE_PICKUP,   1     ; #1
    DEFB MILESTONE_TYPE_PICKUP,   2     ; #2
    DEFB MILESTONE_TYPE_PICKUP,   3     ; #3
    DEFB MILESTONE_TYPE_PICKUP,   4     ; #4
    DEFB MILESTONE_TYPE_TRIGGER,  1     ; #5 town hall door
    DEFB MILESTONE_TYPE_PICKUP,   5     ; #6 church key (en town hall)
    DEFB MILESTONE_TYPE_TRIGGER,  2     ; #7 church door (apunta a la iglesia)
    DEFB MILESTONE_TYPE_PICKUP,   6     ; #8 south gate key
    DEFB MILESTONE_TYPE_TRIGGER,  3     ; #9 south door (sin trigger todavia)

; ==============================================================================
; CheckMilestonePickup - Avanza CurrentObjective si el pickup recogido coincide
; ==============================================================================
; IN:  A = key id (1..6) recien recogida
; Preserva: AF, BC, DE, HL (el caller esta en medio del bucle de pickups).
; ==============================================================================
CheckMilestonePickup:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    LD B, A                             ; B = key id recibida
    LD A, (CurrentObjective)
    CP 9
    JR NC, .cmpDone                     ; sin hitos pendientes
    ADD A, A                            ; *2 (entry size)
    LD L, A
    LD H, 0
    LD DE, MilestoneTable
    ADD HL, DE
    LD A, (HL)                          ; tipo
    CP MILESTONE_TYPE_PICKUP
    JR NZ, .cmpDone
    INC HL
    LD A, (HL)                          ; ref esperada
    CP B
    JR NZ, .cmpDone
    LD A, (CurrentObjective)
    INC A
    LD (CurrentObjective), A
    CALL ResolveObjectiveScreen
.cmpDone:
    POP AF
    POP BC
    POP DE
    POP HL
    RET

; ==============================================================================
; CheckMilestoneTrigger - Avanza CurrentObjective si el trigger coincide
; ==============================================================================
; IN:  A = action id (1=townhall, 2=churchdoor, ...)
; Preserva: AF, BC, DE, HL.
; ==============================================================================
CheckMilestoneTrigger:
    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF
    LD B, A
    LD A, (CurrentObjective)
    CP 9
    JR NC, .cmtDone
    ADD A, A
    LD L, A
    LD H, 0
    LD DE, MilestoneTable
    ADD HL, DE
    LD A, (HL)
    CP MILESTONE_TYPE_TRIGGER
    JR NZ, .cmtDone
    INC HL
    LD A, (HL)
    CP B
    JR NZ, .cmtDone
    LD A, (CurrentObjective)
    INC A
    LD (CurrentObjective), A
    CALL ResolveObjectiveScreen
.cmtDone:
    POP AF
    POP BC
    POP DE
    POP HL
    RET

; ==============================================================================
; CheckMilestoneDebugKey - Tecla M: skip de hito (debug). Siempre avanza.
; ==============================================================================
CheckMilestoneDebugKey:
    LD A, $7F                           ; semi-fila SPACE-SS-M-N-B
    IN A, ($FE)
    BIT 2, A                            ; M = bit 2 (0 = pulsada)
    JR NZ, .cmdkNotPressed
    LD A, (MilestoneKeyDebounce)
    OR A
    RET NZ
    LD A, 1
    LD (MilestoneKeyDebounce), A
    LD A, (CurrentObjective)
    CP 9
    RET NC
    INC A
    LD (CurrentObjective), A
    JP ResolveObjectiveScreen
.cmdkNotPressed:
    XOR A
    LD (MilestoneKeyDebounce), A
    RET

MilestoneKeyDebounce: DEFB 0

; ==============================================================================
; ResolveObjectiveScreen - Calcula (sx, sy) del hito actual y la cachea
; ==============================================================================
; Lee MilestoneResolveTable[CurrentObjective] -> {tipo, ref}, traduce a un
; ptr de sprite, y busca su (mapX, mapY) en PickupTable.
;   PICKUP   -> ptr via KeyLockTable[ref-1]
;   TRIGGER  -> ptr via scan de BumpTriggerTable por action=ref
;   SPECIAL  -> no resuelto ($FF, $FF). El resolver no debe ver SPECIAL aqui
;               porque MilestoneResolveTable no usa SPECIAL para los hitos
;               actuales; queda como salvaguarda.
; Salida: ObjectiveScreenX/Y = (mapX, mapY) o $FF si no resuelto.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
ResolveObjectiveScreen:
    LD A, (CurrentObjective)
    CP 9
    JR NC, .rosNoTarget
    ADD A, A
    LD L, A
    LD H, 0
    LD DE, MilestoneResolveTable
    ADD HL, DE
    LD A, (HL)                          ; tipo
    INC HL
    LD B, (HL)                          ; B = ref
    CP MILESTONE_TYPE_PICKUP
    JR Z, .rosPickup
    CP MILESTONE_TYPE_TRIGGER
    JR Z, .rosTrigger
    JR .rosNoTarget                     ; SPECIAL u otro: sin coords
.rosPickup:
    LD A, B
    CALL KeyIdToPtr                     ; DE = ptr del sprite key
    JR .rosFindPos
.rosTrigger:
    LD A, B
    CALL ActionToTriggerPtr             ; DE = ptr (0 si no encontrado)
    LD A, D
    OR E
    JR Z, .rosNoTarget
.rosFindPos:
    CALL FindPickupScreen               ; B = mapX, C = mapY (o $FF, $FF)
    LD A, B
    LD (ObjectiveScreenX), A
    LD A, C
    LD (ObjectiveScreenY), A
    RET
.rosNoTarget:
    LD A, $FF
    LD (ObjectiveScreenX), A
    LD (ObjectiveScreenY), A
    RET

; ==============================================================================
; KeyIdToPtr - Convierte key id (1..6) en ptr al BgGfx via KeyLockTable
; ==============================================================================
; IN:  A = key id (1..6)
; OUT: DE = ptr
; Destruye: AF, HL.
; ==============================================================================
KeyIdToPtr:
    DEC A
    ADD A, A                            ; *2 (DEFW size)
    LD L, A
    LD H, 0
    LD DE, KeyLockTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    RET

; ==============================================================================
; ActionToTriggerPtr - Busca un action en BumpTriggerTable y devuelve su ptr
; ==============================================================================
; IN:  A = action id (1, 2, ...)
; OUT: DE = ptr al BgGfx del trigger (0 si no encontrado)
;      Z flag set si no encontrado.
; Destruye: AF, BC, HL.
; ==============================================================================
ActionToTriggerPtr:
    LD C, A                             ; C = action id buscada
    LD HL, BumpTriggerTable
.attLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL                              ; HL -> required_key
    LD A, D
    OR E
    JR Z, .attNotFound                  ; ptr 0 = fin de tabla
    INC HL                              ; HL -> action
    LD A, (HL)
    INC HL                              ; HL -> next entry
    CP C
    JR NZ, .attLoop
    OR 1                                ; clear Z (encontrado)
    RET
.attNotFound:
    LD D, 0
    LD E, 0
    XOR A                               ; set Z
    RET

; ==============================================================================
; FindPickupScreen - Localiza un sprite en PickupTable y devuelve (mapX, mapY)
; ==============================================================================
; PickupTable layout (per-entry, 7 bytes):
;   mapX, mapY, ptr_lo, ptr_hi, charX, charY, variant
; Terminator: $FF (single byte).
;
; IN:  DE = ptr a buscar
; OUT: B = mapX, C = mapY si encontrado (NZ).
;      B = C = $FF si no encontrado (Z).
; Destruye: AF, HL. Preserva DE.
; ==============================================================================
FindPickupScreen:
    LD HL, PickupTable
.fpsLoop:
    LD A, (HL)
    CP $FF
    JR Z, .fpsNotFound
    PUSH HL
    INC HL                              ; -> mapY
    INC HL                              ; -> ptr_lo
    LD A, (HL)
    CP E
    JR NZ, .fpsNoMatch
    INC HL                              ; -> ptr_hi
    LD A, (HL)
    CP D
    JR NZ, .fpsNoMatch
    POP HL                              ; back to entry start (mapX)
    LD B, (HL)                          ; B = mapX
    INC HL
    LD C, (HL)                          ; C = mapY
    OR 1                                ; clear Z (NZ = encontrado)
    RET
.fpsNoMatch:
    POP HL
    PUSH BC
    LD BC, 7
    ADD HL, BC
    POP BC
    JR .fpsLoop
.fpsNotFound:
    LD B, $FF
    LD C, $FF
    XOR A                               ; set Z
    RET

; ==============================================================================
; DrawMilestoneDebug - Pinta hito + (sx, sy) en el HUD (4 chars, cols 23-26)
; ==============================================================================
; col 23: digito hito (0..9)
; col 24: espacio
; col 25: sx en hex (0..F) o '?' si $FF
; col 26: sy en hex (0..F) o '?' si $FF
; ==============================================================================
DrawMilestoneDebug:
    ; col 23: digito hito
    LD A, (CurrentObjective)
    ADD A, '0'
    LD E, 23
    CALL DrawDebugCharRow0
    ; col 24: espacio (separador)
    LD A, ' '
    LD E, 24
    CALL DrawDebugCharRow0
    ; col 25: sx
    LD A, (ObjectiveScreenX)
    CP $FF
    JR NZ, .dmdSxOk
    LD A, '?'
    JR .dmdSxDraw
.dmdSxOk:
    CALL NibbleToHex
.dmdSxDraw:
    LD E, 25
    CALL DrawDebugCharRow0
    ; col 26: sy
    LD A, (ObjectiveScreenY)
    CP $FF
    JR NZ, .dmdSyOk
    LD A, '?'
    JR .dmdSyDraw
.dmdSyOk:
    CALL NibbleToHex
.dmdSyDraw:
    LD E, 26
    JP DrawDebugCharRow0

; ==============================================================================
; NibbleToHex - Convierte nibble (A=0..15) en char ASCII '0'..'9' o 'A'..'F'
; ==============================================================================
NibbleToHex:
    AND $0F
    CP 10
    JR C, .nthDigit
    ADD A, 'A' - 10
    RET
.nthDigit:
    ADD A, '0'
    RET

; ==============================================================================
; DrawDebugCharRow0 - Pinta char ASCII en row 0 col E del HUD (8x8 desde ROM)
; ==============================================================================
; IN: A = ASCII, E = col (0-31)
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DrawDebugCharRow0:
    LD B, E                             ; B = col (preservar)
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; *8
    LD DE, $3C00
    ADD HL, DE                          ; HL = ptr glyph
    EX DE, HL                           ; DE = glyph
    LD H, $40
    LD L, B                             ; HL = $4000 + col, scan 0
    PUSH BC
    LD B, 8
.ddcLoop:
    LD A, (DE)
    LD (HL), A
    INC DE
    INC H
    DJNZ .ddcLoop
    POP BC
    LD H, $58
    LD L, B                             ; HL = $5800 + col
    LD (HL), $47                        ; bright white ink, paper black
    RET
