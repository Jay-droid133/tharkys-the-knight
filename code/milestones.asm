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
    LD A, $FF
    LD (PreviousObjectiveDistance), A   ; brujula: primer cruce -> blanco
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
    LD A, $FF
    LD (PreviousObjectiveDistance), A   ; brujula: primer cruce -> blanco
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
    CALL ResolveObjectiveScreen
    LD A, $FF
    LD (PreviousObjectiveDistance), A   ; brujula: primer cruce -> blanco
    RET
.cmdkNotPressed:
    XOR A
    LD (MilestoneKeyDebounce), A
    RET

MilestoneKeyDebounce: DEFB 0

; ==============================================================================
; CheckCurrentKeyCycleKey - Tecla K: cicla CurrentKey 0->1->...->6->0 (debug)
; ==============================================================================
; Para probar cerraduras / triggers sin tener que jugar la cadena entera.
; El HUD de llave (DrawKeyHUD) ya lee CurrentKey cada frame -> feedback
; inmediato del valor actual.
; ==============================================================================
CheckCurrentKeyCycleKey:
    LD A, $BF                           ; semi-fila ENTER-L-K-J-H
    IN A, ($FE)
    BIT 2, A                            ; K = bit 2 (0 = pulsada)
    JR NZ, .ckcNotPressed
    LD A, (CurrentKeyCycleDebounce)
    OR A
    RET NZ
    LD A, 1
    LD (CurrentKeyCycleDebounce), A
    LD A, (CurrentKey)
    INC A
    CP 7
    JR C, .ckcSet                       ; 1..6 dentro de rango
    XOR A                               ; 7 -> wrap a 0
.ckcSet:
    LD (CurrentKey), A
    RET
.ckcNotPressed:
    XOR A
    LD (CurrentKeyCycleDebounce), A
    RET

CurrentKeyCycleDebounce: DEFB 0

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
; BRUJULA - HUD compass (16x16 px = 2 cols x 2 char rows)
; ==============================================================================
; Posicion relocatable via constantes (cambiar en un solo sitio).
; Ocupa COMPASS_COL..COMPASS_COL+1 en char rows COMPASS_CHARROW..+1 (top
; third). El brujula se redibuja solo cuando:
;   - cambias de pantalla (LastCompassScreen != Current)
;   - acabas de avanzar de hito (PreviousObjectiveDistance == $FF)
; En reposo es un no-op barato (solo unas comparaciones).
;
; Color (atributo de las 4 celdas):
;   PreviousObjectiveDistance == $FF (primer cruce)        -> BLANCO
;   distancia_nueva  <  distancia_anterior (te acercas)    -> VERDE
;   distancia_nueva  >  distancia_anterior (te alejas)     -> ROJO
;   distancia_nueva  == distancia_anterior (lateral)       -> BLANCO
;
; Sprite (pixel data): 9 placeholders 16x16 inline. Sustituibles luego.
; ==============================================================================

COMPASS_COL     EQU 24
COMPASS_CHARROW EQU 0           ; char row 0 del third superior

; ==============================================================================
; DrawCompass - Llamada cada frame; redibuja solo si hay cambio
; ==============================================================================
DrawCompass:
    ; Sin objetivo resuelto -> limpiar y salir
    LD A, (ObjectiveScreenX)
    CP $FF
    JP Z, ClearCompass

    ; Necesita redraw? screen cambio, PrevDist == $FF, o wobble activo.
    LD A, (CurrentScreenX)
    LD B, A
    LD A, (LastCompassScreenX)
    CP B
    JR NZ, .dcRedraw
    LD A, (CurrentScreenY)
    LD B, A
    LD A, (LastCompassScreenY)
    CP B
    JR NZ, .dcRedraw
    LD A, (PreviousObjectiveDistance)
    CP $FF
    JR Z, .dcRedraw
    LD A, (CompassWobbleCounter)
    OR A
    RET Z                               ; sin cambios y sin wobble -> nada

.dcRedraw:
    ; --- dx = ObjectiveScreenX - CurrentScreenX (signed) ---
    LD A, (ObjectiveScreenX)
    LD B, A
    LD A, (CurrentScreenX)
    LD C, A
    LD A, B
    SUB C                               ; A = dx (signed)
    ; abs(dx) -> H, sign(dx)+1 -> L
    JP P, .dcDxNonNeg
    NEG
    LD H, A                             ; abs(dx)
    LD L, 0                             ; sign+1 = 0 (negativo)
    JR .dcDxDone
.dcDxNonNeg:
    LD H, A
    OR A
    JR NZ, .dcDxPositive
    LD L, 1                             ; dx == 0
    JR .dcDxDone
.dcDxPositive:
    LD L, 2
.dcDxDone:
    PUSH HL                             ; stack: [H=abs_dx, L=signdx+1]

    ; --- dy = ObjectiveScreenY - CurrentScreenY (signed) ---
    LD A, (ObjectiveScreenY)
    LD B, A
    LD A, (CurrentScreenY)
    LD C, A
    LD A, B
    SUB C
    JP P, .dcDyNonNeg
    NEG
    LD H, A
    LD L, 0
    JR .dcDyDone
.dcDyNonNeg:
    LD H, A
    OR A
    JR NZ, .dcDyPositive
    LD L, 1
    JR .dcDyDone
.dcDyPositive:
    LD L, 2
.dcDyDone:
    ; HL = [abs_dy, signdy+1], stack top = [abs_dx, signdx+1]
    POP DE                              ; D = abs_dx, E = signdx+1
    ; idx = (signdy+1)*3 + (signdx+1)
    LD A, L
    ADD A, A
    ADD A, L                            ; A = (signdy+1)*3
    ADD A, E                            ; A = idx (0..8)
    LD (.dcSpriteIdx), A
    ; distance = abs_dx + abs_dy
    LD A, D
    ADD A, H
    LD (.dcDistance), A

    ; --- Wobble: oscilacion al entrar a una pantalla ---
    ; Patron (6 frames totales, 1 frame por fase, 6 fases):
    ;   prev -> target -> next -> target -> prev -> target
    ; La X (idx 4) no vibra. Si el target cambia mid-wobble, se mantiene la
    ; cuenta atras y los prev/next se recalculan respecto al nuevo idx.
    ; Counter == 0 -> sin override, idx = target.
    ; Para velocidades mayores ya no se puede ir mas rapido. Para ralentizar:
    ;   LD A, 12 + SRL A (1x)         -> 12 frames, 2 fr/fase
    ;   LD A, 24 + SRL A : SRL A (2x) -> 24 frames, 4 fr/fase
    LD A, (.dcSpriteIdx)
    CP 4
    JR NZ, .dcWobbleNotX
    ; X -> sin wobble. Forzar counter a 0 para que el early-exit del proximo
    ; frame no redibuje innecesariamente.
    XOR A
    LD (CompassWobbleCounter), A
    JR .dcWobbleEnd
.dcWobbleNotX:
    ; Si pantalla cambio, arrancar wobble (counter = 24)
    LD A, (CurrentScreenX)
    LD B, A
    LD A, (LastCompassScreenX)
    CP B
    JR NZ, .dcWobbleStart
    LD A, (CurrentScreenY)
    LD B, A
    LD A, (LastCompassScreenY)
    CP B
    JR Z, .dcWobbleResolve              ; misma pantalla -> usar counter actual
.dcWobbleStart:
    LD A, 6
    LD (CompassWobbleCounter), A
.dcWobbleResolve:
    LD A, (CompassWobbleCounter)
    OR A
    JR Z, .dcWobbleEnd                  ; counter 0 -> idx queda como target
    DEC A
    LD (CompassWobbleCounter), A
                                        ; A = phase 0..5 (1 frame por fase)
    LD HL, WobblePhaseTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                          ; 0 = prev, 1 = target, 2 = next
    CP 1
    JR Z, .dcWobbleEnd                  ; target -> no override
    ; A es 0 (prev) o 2 (next). Convertir a offset 0/1 dentro de WobbleTable.
    SRL A                               ; 0 -> 0, 2 -> 1
    LD E, A
    LD A, (.dcSpriteIdx)
    ADD A, A                            ; idx*2 (stride 2 bytes por entry)
    ADD A, E                            ; +0 prev, +1 next
    LD HL, CompassWobbleTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (.dcSpriteIdx), A                ; override

.dcWobbleEnd:

    ; --- Color ---
    ; idx 4 = X (estamos sobre el target) -> siempre blanco, sin comparar
    LD A, (.dcSpriteIdx)
    CP 4
    JR Z, .dcWhite
    LD A, (PreviousObjectiveDistance)
    CP $FF
    JR Z, .dcWhite
    LD B, A
    LD A, (.dcDistance)
    CP B
    JR Z, .dcWhite                      ; igual = blanco
    JR C, .dcGreen                      ; nueva < prev = te acercas
    LD A, RED | $40                     ; nueva > prev = te alejas
    JR .dcColorDone
.dcGreen:
    LD A, GREEN | $40
    JR .dcColorDone
.dcWhite:
    LD A, WHITE | $40
.dcColorDone:
    LD (.dcAttr), A

    ; --- Sprite ptr de CompassSprites[idx] ---
    LD A, (.dcSpriteIdx)
    ADD A, A                            ; *2
    LD L, A
    LD H, 0
    LD DE, CompassSprites
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                          ; DE = sprite ptr (32 bytes)
    CALL DrawCompassSprite

    ; --- Attrs ---
    LD A, (.dcAttr)
    CALL SetCompassAttrs

    ; --- Cachear estado ---
    ; PreviousObjectiveDistance solo se guarda cuando el wobble termino. Si
    ; lo guardasemos cada frame, los frames 2..N del wobble compararian la
    ; distancia actual contra si misma -> "igual" -> blanco -> el color
    ; (verde acercas, rojo alejas) se perderia tras el primer frame.
    ; Asi PrevDist mantiene el valor de la pantalla anterior durante todo
    ; el wobble y la comparacion sigue siendo correcta.
    LD A, (CompassWobbleCounter)
    OR A
    JR NZ, .dcSkipPrevDistSave
    LD A, (.dcDistance)
    LD (PreviousObjectiveDistance), A
.dcSkipPrevDistSave:
    LD A, (CurrentScreenX)
    LD (LastCompassScreenX), A
    LD A, (CurrentScreenY)
    LD (LastCompassScreenY), A
    RET

.dcSpriteIdx: DEFB 0
.dcDistance:  DEFB 0
.dcAttr:      DEFB 0

; ==============================================================================
; DrawCompassSprite - Vuelca 32 bytes (16x16 px) de DE a la posicion de la brujula
; ==============================================================================
; IN: DE = ptr a 16 filas x 2 bytes
; Asume top third (H=$40). Char rows COMPASS_CHARROW y COMPASS_CHARROW+1.
; Destruye: AF, B, HL.
; ==============================================================================
DrawCompassSprite:
    ; Char row 0 (rows 0-7 del sprite)
    LD H, $40
    LD L, COMPASS_CHARROW * $20 + COMPASS_COL
    LD B, 8
.dcsRow0:
    LD A, (DE)
    LD (HL), A
    INC DE
    INC HL
    LD A, (DE)
    LD (HL), A
    INC DE
    DEC HL
    INC H
    DJNZ .dcsRow0
    ; Char row 1 (rows 8-15 del sprite)
    LD H, $40
    LD L, (COMPASS_CHARROW + 1) * $20 + COMPASS_COL
    LD B, 8
.dcsRow1:
    LD A, (DE)
    LD (HL), A
    INC DE
    INC HL
    LD A, (DE)
    LD (HL), A
    INC DE
    DEC HL
    INC H
    DJNZ .dcsRow1
    RET

; ==============================================================================
; SetCompassAttrs - Pinta las 4 celdas (2x2) con el byte de atributo en A
; ==============================================================================
SetCompassAttrs:
    LD HL, $5800 + COMPASS_CHARROW * $20 + COMPASS_COL
    LD (HL), A
    INC HL
    LD (HL), A
    LD HL, $5800 + (COMPASS_CHARROW + 1) * $20 + COMPASS_COL
    LD (HL), A
    INC HL
    LD (HL), A
    RET

; ==============================================================================
; ClearCompass - Borra el bloque 2x2 de la brujula (cuando no hay objetivo)
; ==============================================================================
ClearCompass:
    LD H, $40
    LD L, COMPASS_CHARROW * $20 + COMPASS_COL
    LD B, 8
    XOR A
.ccRow0:
    LD (HL), A
    INC HL
    LD (HL), A
    DEC HL
    INC H
    DJNZ .ccRow0
    LD H, $40
    LD L, (COMPASS_CHARROW + 1) * $20 + COMPASS_COL
    LD B, 8
    XOR A
.ccRow1:
    LD (HL), A
    INC HL
    LD (HL), A
    DEC HL
    INC H
    DJNZ .ccRow1
    XOR A                               ; attr 0 (negro/negro, invisible)
    LD HL, $5800 + COMPASS_CHARROW * $20 + COMPASS_COL
    LD (HL), A
    INC HL
    LD (HL), A
    LD HL, $5800 + (COMPASS_CHARROW + 1) * $20 + COMPASS_COL
    LD (HL), A
    INC HL
    LD (HL), A
    RET

; ==============================================================================
; CHURCH TRAP (paso 7 - encerrar a los 3 monsters en la iglesia)
; ==============================================================================
; Mecanica: la puerta de la iglesia, una vez abierta (ChurchDoorOpen=1), se
; convierte en una trampa de un solo sentido. El player ataca a los monstruos
; haciendo que el knockback les empuje hacia las celdas trampa (CHURCH_TRAP_
; CELL_LO_X/HI_X, CHURCH_TRAP_CELL_Y) en la pantalla de la iglesia. Cuando un
; monstruo cae alli con la puerta abierta:
;   - Bit slot en MonsterTrappedFlags
;   - Despawn del monstruo (puff)
;   - Puerta se re-cierra (sprite + flag)
;   - Si quedan monstruos: respawn de la church_key en AltKeyN
;   - Si los 3 atrapados: spawn de la town_gate_key + avance hito 7 -> 8
;
; Las constantes CHURCH_TRAP_* y CHURCH_KEY_ALT*_* viven en screen_data.asm,
; auto-generadas por el level editor segun la posicion de la puerta y los
; markers AltKey1/AltKey2.
; ==============================================================================

; ==============================================================================
; CheckChurchTrap - llamada tras .moKbYOk en UpdateMonster
; ==============================================================================
; IN:  IX = entity ptr del monster (tras knockback aplicado)
; OUT: A = 0 si no trampa, NZ si trampa disparada (caller debe abortar update).
; Destruye: AF, BC.
; ==============================================================================
CheckChurchTrap:
    ; --- Solo en pantalla de la iglesia ---
    LD A, (CurrentScreenX)
    CP CHURCH_TRAP_SCREEN_X
    JR NZ, .cctNoTrap
    LD A, (CurrentScreenY)
    CP CHURCH_TRAP_SCREEN_Y
    JR NZ, .cctNoTrap
    ; --- Solo con la puerta abierta ---
    LD A, (ChurchDoorOpen)
    OR A
    JR Z, .cctNoTrap
    ; --- Y de la celda trampa: charY del monstruo en [trap-2..trap] ---
    ; (acepta sprites de 16, 21 o 24 px de alto)
    LD A, (IX+ENT_POSY)
    SRL A
    SRL A
    SRL A                                   ; A = top charY del monster
    LD B, A
    LD A, CHURCH_TRAP_CELL_Y + BG_Y_OFFSET
    SUB B                                   ; A = trap_charY - mon_charY
    CP 3
    JR NC, .cctNoTrap                       ; fuera de rango Y
    ; --- X de la celda trampa: charX del monstruo en [LO_X-1..LO_X+1] ---
    LD A, (IX+ENT_POSX)
    SRL A
    SRL A
    SRL A
    LD B, A                                 ; B = left charX del monster
    LD A, CHURCH_TRAP_CELL_LO_X
    INC A                                   ; A = LO_X + 1
    SUB B                                   ; A = LO_X+1 - charX
    CP 3
    JR NC, .cctNoTrap                       ; fuera de rango X
    ; --- TRAMPA: ejecutar TriggerChurchTrap ---
    CALL TriggerChurchTrap
    LD A, 1
    OR A
    RET
.cctNoTrap:
    XOR A
    RET

; ==============================================================================
; CUTSCENE - parametros ajustables
; ==============================================================================
; Fase LOOK_MONSTER: el monster mira de un lado a otro alternando sprite.
; POSX/POSY fijos (sin jitter) -> cero contaminacion de attrs con la puerta.
CHURCH_CUTSCENE_LOOK_FRAMES         EQU 25      ; ~1s total
CHURCH_CUTSCENE_LOOK_PERIOD         EQU 6       ; frames entre cambios de sprite

; Fase SHAKE_STATUE: la estatua tiembla con jitter pixel-preciso.
CHURCH_CUTSCENE_SHAKE_FRAMES        EQU 28      ; ~1.1s total
CHURCH_CUTSCENE_SHAKE_AMP           EQU 2       ; jitter +/- AMP px en X e Y

; Posicion del monster atrapado durante la cutscene. CELL_Y es la fila
; base del vano (auto-derivada por el editor). El monster (3 chars de
; alto) se coloca con su top 3 chars arriba de CELL_Y para que quede
; centrado dentro del vano de la puerta.
;   POSX = LO_X * 8                            (charX absoluto = LO_X)
;   POSY = (CELL_Y - 3 + BG_Y_OFFSET) * 8      (charY absoluto = CELL_Y - 1)
CHURCH_TRAP_AREA_POSX   EQU CHURCH_TRAP_CELL_LO_X * 8
CHURCH_TRAP_AREA_POSY   EQU (CHURCH_TRAP_CELL_Y - 3 + BG_Y_OFFSET) * 8

; ==============================================================================
; TriggerChurchTrap - arranca la cutscene de la iglesia
; ==============================================================================
; IN: IX = monster atrapado.
; Mueve al monster al centro del vano y activa la cutscene. Los efectos
; reales (despawn, cierre puerta, respawn key, advance hito) se aplican
; en ApplyChurchTrapEffects al final del cutscene.
; ==============================================================================
TriggerChurchTrap:
    ; --- 1. Calcular slot 0..2 ---
    PUSH IX
    POP HL
    LD DE, EntityTable + (SLOT_MONSTER0 * ENT_SIZE)
    OR A
    SBC HL, DE
    SRL L
    SRL L
    SRL L
    SRL L                                   ; L = slot 0..2
    LD A, L
    LD (ChurchCutsceneSlot), A
    ; --- 1b. Calcular type idx (0=zombi, 1=skel, 2=ghost) y guardarlo ---
    LD A, (IX+ENT_ANIMBASE)
    SUB SPRID_MONSTER_0
    SRL A
    SRL A
    SRL A                                   ; A = type idx
    LD (ChurchCutsceneTypeIdx), A
    ; --- 2. Mover monster al centro del vano ---
    LD A, CHURCH_TRAP_AREA_POSX
    LD (IX+ENT_POSX), A
    LD A, CHURCH_TRAP_AREA_POSY
    LD (IX+ENT_POSY), A
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    LD (IX+ENT_DIR), 0                      ; clear stun timer
    ; --- 3. Activar cutscene (phase 1 LOOK, frame 0) ---
    LD A, 1
    LD (ChurchCutscenePhase), A
    XOR A
    LD (ChurchCutsceneFrame), A
    LD A, CHURCH_CUTSCENE_LOOK_PERIOD
    LD (ChurchCutsceneLookCount), A
    RET

; ==============================================================================
; UpdateChurchCutscene - llamada cada frame desde MainLoop
; ==============================================================================
; Si phase = 0 → no-op. Si activa: incrementa frame counter y, al llegar
; a CHURCH_CUTSCENE_TOTAL_FRAMES, dispara ApplyChurchTrapEffects + termina.
; (MVP1: solo freeze + reposicion; sin shake. MVP2 anadira jitter visible.)
; ==============================================================================
UpdateChurchCutscene:
    LD A, (ChurchCutscenePhase)
    OR A
    RET Z
    DEC A
    JR Z, .ucsLookPhase
    DEC A
    JR Z, .ucsShakeStatuePhase
    ; Phase 3 (DONE): aplicar efectos finales y terminar cutscene.
    CALL ApplyChurchTrapDone
    XOR A
    LD (ChurchCutscenePhase), A
    LD (ChurchCutsceneFrame), A
    RET

; ---- Phase 1: monster mira de un lado a otro (no jitter de posicion) ----
.ucsLookPhase:
    ; Frame counter (para detectar fin de fase)
    LD HL, ChurchCutsceneFrame
    INC (HL)
    ; Toggle countdown (cualquier valor, no necesita ser potencia de 2)
    LD HL, ChurchCutsceneLookCount
    DEC (HL)
    JR NZ, .ucsLookCheckEnd
    LD A, CHURCH_CUTSCENE_LOOK_PERIOD
    LD (HL), A
    CALL ChurchCutsceneToggleMonsterDir
.ucsLookCheckEnd:
    LD A, (ChurchCutsceneFrame)
    CP CHURCH_CUTSCENE_LOOK_FRAMES
    RET C                                   ; sigue mirando
    ; Fin del look: BORRAR monster ANTES de cerrar la puerta. Si no, los
    ; pixels del monster que asoman bajo el vano (chars no cubiertos por
    ; la puerta cerrada) quedan visibles durante toda la fase SHAKE.
    CALL EraseChurchTrappedMonster
    CALL CloseChurchDoor
    CALL ChurchCutsceneInitStatueShake
    LD A, 2
    LD (ChurchCutscenePhase), A
    XOR A
    LD (ChurchCutsceneFrame), A
    RET

; ---- Phase 2: la estatua tiembla con jitter pixel-preciso ----
.ucsShakeStatuePhase:
    LD A, (ChurchCutsceneFrame)
    CP CHURCH_CUTSCENE_SHAKE_FRAMES
    JR NC, .ucsShakeStatueDone
    ; Frame normal: erase en LastX/Y, jitter, draw en NewX/Y, save Last=New
    CALL ChurchCutsceneEraseStatueAtLast
    ; Jitter X
    LD A, R
    AND $03
    SUB CHURCH_CUTSCENE_SHAKE_AMP
    LD B, A
    ; Jitter Y
    LD A, R
    RRCA
    RRCA
    AND $03
    SUB CHURCH_CUTSCENE_SHAKE_AMP
    LD C, A
    ; New = Orig + jitter
    LD A, (ChurchCutsceneStatueOrigX)
    ADD A, B
    LD (ChurchCutsceneStatueLastX), A
    LD A, (ChurchCutsceneStatueOrigY)
    ADD A, C
    LD (ChurchCutsceneStatueLastY), A
    ; Draw at new
    CALL ChurchCutsceneDrawStatueAtLast
    LD HL, ChurchCutsceneFrame
    INC (HL)
    RET
.ucsShakeStatueDone:
    ; Erase final + SFX + transicion
    CALL ChurchCutsceneEraseStatueAtLast
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
    LD A, 3
    LD (ChurchCutscenePhase), A
    RET

; ==============================================================================
; ChurchCutsceneToggleMonsterDir - alterna sprite del monster L <-> R
; ==============================================================================
; ENT_SPRITEID alterna entre ANIMBASE+0 (frente derecha frame 0) y
; ANIMBASE+4 (frente izquierda frame 0). Tras cambiar, redibuja.
; ==============================================================================
ChurchCutsceneToggleMonsterDir:
    ; IX = trapped monster
    LD A, (ChurchCutsceneSlot)
    INC A
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD DE, EntityTable
    ADD HL, DE
    PUSH HL
    POP IX
    ; Toggle SPRITEID entre +0 y +4 respecto a ANIMBASE
    LD A, (IX+ENT_SPRITEID)
    SUB (IX+ENT_ANIMBASE)
    XOR 4
    LD B, A
    LD A, (IX+ENT_ANIMBASE)
    ADD A, B
    LD (IX+ENT_SPRITEID), A
    JP RedrawTrappedMonster

; ==============================================================================
; ChurchCutsceneInitStatueShake - prepara state para fase SHAKE_STATUE
; ==============================================================================
; Busca la estatua del tipo atrapado en CurrentScreenBuffer, computa su pixel
; original y lo guarda en Orig/Last X/Y. La estatua ya esta dibujada en su
; posicion char-aligned (la pinto DrawScreen al entrar a la pantalla).
; ==============================================================================
ChurchCutsceneInitStatueShake:
    LD A, (ChurchCutsceneTypeIdx)
    LD HL, StatueIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = statue id
    OR A
    RET Z                                   ; sin estatua
    LD (.cisTargetId), A
    ; Buscar en CurrentScreenBuffer
    LD HL, (CurrentScreenAddr)
.cisLoop:
    LD A, (HL)
    CP $FF
    RET Z                                   ; no encontrada (no se hace shake)
    LD B, A
    LD A, (.cisTargetId)
    CP B
    JR Z, .cisFound
    LD DE, 4
    ADD HL, DE
    JR .cisLoop
.cisFound:
    INC HL
    LD A, (HL)                              ; charX
    ; Pixel X = charX * 8
    ADD A, A
    ADD A, A
    ADD A, A
    LD (ChurchCutsceneStatueOrigX), A
    LD (ChurchCutsceneStatueLastX), A
    INC HL
    LD A, (HL)                              ; charY
    ; Pixel Y = (charY + BG_Y_OFFSET) * 8
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A
    LD (ChurchCutsceneStatueOrigY), A
    LD (ChurchCutsceneStatueLastY), A
    RET
.cisTargetId: DEFB 0

; ==============================================================================
; ChurchCutsceneEraseStatueAtLast / DrawStatueAtLast - XOR redraw a (Last X/Y)
; ==============================================================================
; Igual que el monster shake, XOR redraw es reversible: la primera llamada
; borra, la segunda redibuja. Cargamos sprite por TypeIdx.
; ==============================================================================
ChurchCutsceneEraseStatueAtLast:
ChurchCutsceneDrawStatueAtLast:
    LD A, (ChurchCutsceneTypeIdx)
    LD HL, StatueIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = statue id
    OR A
    RET Z
    ; Lookup ptr+bank en BgGfxPtrById (id*3)
    LD L, A
    LD H, 0
    LD D, H
    LD E, L
    ADD HL, HL
    ADD HL, DE                              ; HL = id*3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                              ; DE = sprite ptr
    INC HL
    LD A, (HL)                              ; A = bank
    EX DE, HL                               ; HL = sprite ptr
    CALL LoadBgSpriteToBuffer               ; preserva BC
    ; Cargar pixel X/Y desde state y dibujar pixel-preciso
    LD A, (ChurchCutsceneStatueLastY)
    LD D, A
    LD A, (ChurchCutsceneStatueLastX)
    LD E, A
    JP DrawBgSprite16XorAtPixel

; ==============================================================================
; RedrawTrappedMonster - erase old + draw new tras cambiar POSX/POSY
; ==============================================================================
; Replica el flujo basico de ProcessOneEnemy.peCalcAndDraw sin AI ni attr
; handling (el shake es +/-AMP px en torno a centro fijo; attrs no cambian
; suficiente para corromper visualmente).
; IN: IX = entity ptr.
; ==============================================================================
RedrawTrappedMonster:
    ; --- Erase viejo en (OLDX, OLDY) ---
    CALL GetOldSpriteAddr                   ; OldSprAddr setado
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    PUSH IX
    LD IX, (OldSprAddr)
    CALL DrawSprite
    POP IX
    ; --- Restaurar attrs del fondo en pos vieja desde CleanAttrMap ---
    ; (Igual que .peCalcAndDraw del flujo normal de gameplay.)
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    CALL RestoreOldAttr
    ; --- Repintar attrs de pickups sobre el area (puerta abierta etc.) ---
    ; En gameplay normal RefreshPickupAttrs corre tras ProcessEnemies para
    ; reponer attrs de pickups que el flujo de entidades pisa con
    ; CleanAttrMap (que no incluye pickups). Aqui lo necesitamos por la
    ; misma razon: la puerta abierta es un pickup y sus celdas pueden
    ; estar bajo el monster.
    PUSH IX
    CALL RefreshPickupAttrs
    POP IX
    ; --- Compute new draw pos ---
    CALL CalcDrawX
    CALL ComputeEnemyDrawY
    ; --- Pintar attr nuevo ANTES del sprite (evita flash con color BG) ---
    CALL GetSpriteAddr                      ; SpriteAddrTemp setado
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL CalcEntityAttrSize
    POP IX
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    LD A, (IX+ENT_ATTR)
    CALL SetEntityAttr
    ; --- Draw nuevo en (DRAWX, EnemyDrawY) ---
    LD A, (EnemyDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    PUSH IX
    LD IX, (SpriteAddrTemp)
    CALL DrawSprite
    POP IX
    ; --- Save OLD = current ---
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (EnemyDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

; ==============================================================================
; EraseChurchTrappedMonster - borra el sprite del monster atrapado in-place
; ==============================================================================
; Llamada al final de la fase LOOK (antes de CloseChurchDoor) para que
; durante la fase SHAKE la puerta cerrada no muestre pixels residuales
; del monster por debajo del marco. Auto-carga IX desde
; ChurchCutsceneSlot.
; Destruye: AF, BC, DE, HL, IX (callsite debe asumir IX no preservado).
; ==============================================================================
EraseChurchTrappedMonster:
    LD A, (ChurchCutsceneSlot)
    INC A                                   ; SLOT_MONSTER0 = 1
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; * ENT_SIZE (16)
    LD DE, EntityTable
    ADD HL, DE
    PUSH HL
    POP IX
    CALL GetOldSpriteAddr                   ; OldSprAddr setado
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    LD IX, (OldSprAddr)
    JP DrawSprite                           ; XOR-erase + RET tail-call

; ==============================================================================
; ApplyChurchTrapEffects - efectos finales tras el cutscene
; ==============================================================================
; - Marca slot atrapado en MonsterTrappedFlags.
; - Despawn monster (ENT_TYPE=0).
; - Cierra puerta (CloseChurchDoor patchea ptr + ScreenDirty=1).
; - Si <3 atrapados: respawnea church_key en AltN.
; - Si 3 atrapados: spawnea town_gate_key + avanza hito 7 -> 8.
; ==============================================================================
ApplyChurchTrapDone:
    ; Get IX = monster atrapado (a partir del entity slot guardado)
    LD A, (ChurchCutsceneSlot)
    INC A                                   ; SLOT_MONSTER0 = 1
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; * ENT_SIZE (16)
    LD DE, EntityTable
    ADD HL, DE
    PUSH HL
    POP IX
    ; Set bit por TIPO en MonsterTrappedFlags (TypeIdx ya calculado y
    ; guardado en TriggerChurchTrap).
    LD A, (ChurchCutsceneTypeIdx)
    LD HL, ChurchTrapBitMask
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD HL, MonsterTrappedFlags
    OR (HL)
    LD (HL), A
    ; (Erase ya ejecutado al final de fase LOOK por EraseChurchTrappedMonster.)
    ; Despawn monster: TYPE = 0 (ANIMBASE preservado para que TryRespawn lo
    ; vea y, via .rmTrapBits indexado por type, decida saltarlo).
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), 0
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; (CloseChurchDoor y EraseStatueAtSlot ya se ejecutaron en fases
    ; anteriores del cutscene.)
    ; Decidir spawn: 3 atrapados?
    LD A, (MonsterTrappedFlags)
    AND $07
    CP $07
    JR Z, .actdAllTrapped
    ; <3 atrapados: respawn church_key en AltN
    LD A, 1
    LD (ChurchKeySpawned), A
    LD HL, ChurchKeyAltSpawnIdx
    INC (HL)                                ; idx pasa a 1 o 2
    CALL RespawnChurchKeyAtAlt
    ; Dibujar surgical en su nueva posicion
    LD DE, BgGfx_church_key
    JP RedrawPickupByPtr
.actdAllTrapped:
    LD A, 1
    LD (TownGateKeySpawned), A
    LD DE, BgGfx_town_gate_key
    CALL RedrawPickupByPtr
    LD A, (CurrentObjective)
    CP 7
    RET NZ
    INC A
    LD (CurrentObjective), A
    CALL ResolveObjectiveScreen
    LD A, $FF
    LD (PreviousObjectiveDistance), A
    RET

ChurchTrapBitMask: DEFB $01, $02, $04

; ==============================================================================
; STATUES - 3 estatuas en la iglesia, una por TIPO de monster
; ==============================================================================
; Mapeo (indexado por monster type idx = (ANIMBASE - SPRID_MONSTER_0) / 8):
;   idx 0 (SPRID_MONSTER_0 = zombi)    -> statue_zombi (213)
;   idx 1 (SPRID_MONSTER_1 = skeleton) -> statue_skeleton (212)
;   idx 2 (SPRID_MONSTER_2 = ghost)    -> statue_ghost (211)
; Indexar por tipo y no por slot porque ShuffleMonsterTypes baraja la
; asignacion slot->tipo al inicio: el "slot 0" no tiene tipo fijo.
; MonsterTrappedFlags pasa a indexarse por tipo tambien.
; ==============================================================================
StatueIdTable:
    DEFB 213        ; type idx 0: statue_zombi
    DEFB 225        ; type idx 1: statue_skeleton
    DEFB 211        ; type idx 2: statue_ghost

; ==============================================================================
; CheckStatueHidden - es esta entry de BG una estatua oculta?
; ==============================================================================
; IN:  A = sprite id
; OUT: NZ si es estatua y su slot esta atrapado (skip drawing).
;      Z si no es estatua o esta visible (draw normalmente).
; Destruye: AF, BC, HL.
; ==============================================================================
CheckStatueHidden:
    LD HL, StatueIdTable
    LD B, 3
    LD C, 0                                 ; slot index 0..2
.cshLoop:
    CP (HL)
    JR Z, .cshMatch
    INC HL
    INC C
    DJNZ .cshLoop
    XOR A                                   ; not statue -> Z (visible)
    RET
.cshMatch:
    ; A es statue id. C = slot. Comprobar bit en MonsterTrappedFlags.
    LD A, C
    LD HL, ChurchTrapBitMask
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; bit mask
    LD HL, MonsterTrappedFlags
    AND (HL)
    RET                                     ; NZ si bit set (hidden), Z si no

; ==============================================================================
; EraseStatueAtSlot - borra (XOR) la estatua del slot N en la pantalla actual
; ==============================================================================
; IN: A = slot (0..2)
; Solo tiene efecto si la estatua esta colocada en la pantalla actual.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
EraseStatueAtSlot:
    ; Get statue ID from table
    LD HL, StatueIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = statue id
    OR A
    RET Z                                   ; ID 0 = no estatua (no exportada)
    LD (.eseTargetId), A
    ; Scan CurrentScreenBuffer (formato 4B: id, charX, charY, variant; $FF = end)
    LD HL, (CurrentScreenAddr)
.eseLoop:
    LD A, (HL)
    CP $FF
    RET Z                                   ; no encontrada en esta pantalla
    LD B, A                                 ; B = current id
    LD A, (.eseTargetId)
    CP B
    JR Z, .eseFound
    LD DE, 4
    ADD HL, DE
    JR .eseLoop
.eseFound:
    ; HL en id. Avanzar a charX, charY.
    INC HL
    LD B, (HL)                              ; B = charX
    INC HL
    LD C, (HL)                              ; C = charY
    ; Cargar sprite via BgGfxPtrById[id]: id*3 -> ptr (DEFW), bank (DEFB).
    LD A, (.eseTargetId)
    LD L, A
    LD H, 0
    LD D, H
    LD E, L
    ADD HL, HL                              ; *2
    ADD HL, DE                              ; *3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                              ; DE = ptr
    INC HL
    LD A, (HL)                              ; A = bank
    PUSH BC
    EX DE, HL                               ; HL = ptr
    CALL LoadBgSpriteToBuffer               ; preserva BC
    POP BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR                    ; XOR-erase
    RET
.eseTargetId: DEFB 0

; ==============================================================================
; DrawBgSprite16XorAtPixel - draw 16px-wide BG sprite at arbitrary pixel pos
; ==============================================================================
; Especializado para sprites de 2 bytes de ancho (16 px, como las 3 estatuas).
; Permite posicion sub-char en X (shift bits) Y (scan line).
;
; IN: BgSpriteBuffer pre-cargado con el sprite completo (header incluido).
;     D = pixel Y (0-191, post-HUD ya aplicado).
;     E = pixel X (0-255).
; Para shift>0, escribe 3 bytes por scan line; para shift=0 escribe 2.
; Solo XOR de pixels (no toca attrs).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
DrawBgSprite16XorAtPixel:
    LD IX, BgSpriteBuffer
    LD A, (IX+0)                            ; height_px
    OR A
    RET Z
    LD (.dbsHeight), A
    INC IX
    INC IX                                  ; -> pixel data
    ; Shift = E & 7 ; aligned X = E & ~7
    LD A, E
    AND $07
    LD (.dbsShift), A
    LD A, E
    AND $F8
    LD E, A
    CALL CalcPixelAddr                      ; HL = VRAM addr
.dbsRow:
    PUSH HL                                 ; save row start
    ; --- Byte 0 del sprite ---
    LD A, (IX+0)
    CPL                                     ; un-invert
    LD D, A                                 ; D = sprite byte
    LD E, 0                                 ; E = bits que caen al siguiente byte
    LD A, (.dbsShift)
    OR A
    JR Z, .dbsNoShift0
    LD B, A
.dbsShift0Loop:
    SRL D
    RR E
    DJNZ .dbsShift0Loop
.dbsNoShift0:
    LD A, D
    XOR (HL)
    LD (HL), A                              ; write VRAM byte 0 (sin prev carry)
    INC HL
    LD C, E                                 ; C = carry para siguiente byte
    ; --- Byte 1 del sprite ---
    LD A, (IX+1)
    CPL
    LD D, A
    LD E, 0
    LD A, (.dbsShift)
    OR A
    JR Z, .dbsNoShift1
    LD B, A
.dbsShift1Loop:
    SRL D
    RR E
    DJNZ .dbsShift1Loop
.dbsNoShift1:
    LD A, D
    OR C                                    ; combinar con carry de byte 0
    XOR (HL)
    LD (HL), A
    INC HL
    LD C, E                                 ; carry para byte final
    ; --- Byte final (solo si shift>0) ---
    LD A, (.dbsShift)
    OR A
    JR Z, .dbsNoFinal
    LD A, C
    XOR (HL)
    LD (HL), A
.dbsNoFinal:
    POP HL                                  ; restore row start
    CALL NextPixelLine
    INC IX                                  ; advance sprite ptr by 2 (width)
    INC IX
    LD A, (.dbsHeight)
    DEC A
    LD (.dbsHeight), A
    JR NZ, .dbsRow
    RET
.dbsHeight: DEFB 0
.dbsShift:  DEFB 0

; ==============================================================================
; CloseChurchDoor - cierra la puerta: erase OPEN + draw CLOSED in-place
; ==============================================================================
; Estamos por definicion en la pantalla de la iglesia (la trampa solo dispara
; aqui), asi que el redraw quirurgico siempre es valido. Pasos:
;   1. FindPickupEntryByPtr(BgGfx_old_church_door_open) -> HL = mapX byte
;   2. Leer charX/charY de la entry
;   3. Cargar OPEN al BgSpriteBuffer + DrawBgSpriteXOR -> borra pixels open
;   4. Patch ptr de la entry a BgGfx_old_church_door_closed
;   5. Cargar CLOSED + DrawBgSpriteXOR + DrawBgAttrOnly -> dibuja closed
;   6. ChurchDoorOpen = 0
; ==============================================================================
CloseChurchDoor:
    ; SFX del cierre (mismo crujido que el SFX_ChurchDoorOpen, sirve para
    ; ambos sentidos). Suena ANTES del cambio visual.
    LD HL, SFX_ChurchDoorOpen
    CALL PlaySFX
    LD DE, BgGfx_old_church_door_open
    CALL FindPickupEntryByPtr               ; HL = mapX byte si Z
    JR NZ, .ccdFlag                         ; entry no encontrada -> solo flag
    ; Leer charX (HL+4) y charY (HL+5) en BC
    PUSH HL                                 ; save mapX ptr
    LD BC, 4
    ADD HL, BC
    LD B, (HL)                              ; B = charX
    INC HL
    LD C, (HL)                              ; C = charY
    POP HL                                  ; HL = mapX ptr
    ; --- Erase OPEN sprite: cargar al buffer + XOR redraw ---
    PUSH HL
    PUSH BC
    LD HL, BgGfx_old_church_door_open
    LD A, 3
    CALL LoadBgSpriteToBuffer               ; preserva BC
    POP BC
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR                    ; borra
    POP BC
    POP HL
    ; --- Patch ptr: open -> closed ---
    INC HL : INC HL                         ; -> ptr_lo
    LD A, LOW BgGfx_old_church_door_closed
    LD (HL), A
    INC HL
    LD A, HIGH BgGfx_old_church_door_closed
    LD (HL), A
    ; --- Draw CLOSED: cargar + XOR redraw + attrs ---
    PUSH BC
    LD HL, BgGfx_old_church_door_closed
    LD A, 3
    CALL LoadBgSpriteToBuffer
    POP BC
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    POP BC
    LD IX, BgSpriteBuffer
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgAttrOnly
.ccdFlag:
    XOR A
    LD (ChurchDoorOpen), A
    RET

; ==============================================================================
; RespawnChurchKeyAtAlt - patch PickupTable entry de church_key con coords AltN
; ==============================================================================
; Lee ChurchKeyAltSpawnIdx (1 o 2) y patchea con CHURCH_KEY_ALT[1|2]_* coords.
; ==============================================================================
RespawnChurchKeyAtAlt:
    LD A, (ChurchKeyAltSpawnIdx)
    CP 1
    JR Z, .rcaAlt1
    CP 2
    JR Z, .rcaAlt2
    RET                                     ; estado raro, no hacer nada
.rcaAlt1:
    LD B, CHURCH_KEY_ALT1_SCREEN_X
    LD C, CHURCH_KEY_ALT1_SCREEN_Y
    LD D, CHURCH_KEY_ALT1_CHAR_X
    LD A, CHURCH_KEY_ALT1_CHAR_Y
    JR .rcaPatch
.rcaAlt2:
    LD B, CHURCH_KEY_ALT2_SCREEN_X
    LD C, CHURCH_KEY_ALT2_SCREEN_Y
    LD D, CHURCH_KEY_ALT2_CHAR_X
    LD A, CHURCH_KEY_ALT2_CHAR_Y
.rcaPatch:
    LD (.rcaCharY), A
    PUSH BC                                 ; preservar B=mapX, C=mapY
    PUSH DE                                 ; preservar D=charX
    LD DE, BgGfx_church_key
    CALL FindPickupEntryByPtr               ; HL = mapX byte
    POP DE
    POP BC
    JR NZ, .rcaSkip
    LD (HL), B                              ; mapX = AltN_SCREEN_X
    INC HL
    LD (HL), C                              ; mapY = AltN_SCREEN_Y
    INC HL : INC HL : INC HL                ; skip ptr_lo, ptr_hi
    LD (HL), D                              ; charX = AltN_CHAR_X
    INC HL
    LD A, (.rcaCharY)
    LD (HL), A                              ; charY = AltN_CHAR_Y
.rcaSkip:
    RET
.rcaCharY: DEFB 0

; ==============================================================================
; FindPickupEntryByPtr - busca entry en PickupTable por sprite ptr
; ==============================================================================
; Recorre TODAS las entries (active = mapX != $FE, inactive = mapX == $FE),
; comparando ptr_lo/ptr_hi con DE.
; IN:  DE = ptr buscado.
; OUT: HL = puntero al byte mapX de la entry. Z si encontrado, NZ si no.
; Destruye: AF.
; ==============================================================================
FindPickupEntryByPtr:
    LD HL, PickupTable
.fpeLoop:
    LD A, (HL)
    CP $FF
    JR Z, .fpeNotFound
    PUSH HL
    INC HL : INC HL                         ; -> ptr_lo
    LD A, (HL)
    CP E
    JR NZ, .fpeNoMatch
    INC HL
    LD A, (HL)
    CP D
    JR NZ, .fpeNoMatch
    POP HL
    XOR A                                   ; Z = encontrado
    RET
.fpeNoMatch:
    POP HL
    PUSH BC
    LD BC, 7
    ADD HL, BC
    POP BC
    JR .fpeLoop
.fpeNotFound:
    OR 1                                    ; NZ
    RET

; ==============================================================================
; SPRITES PLACEHOLDER (16x16 px = 16 filas x 2 bytes = 32 bytes c/u)
; ==============================================================================
; Indice (CompassSprites[idx]):
;   0 = NW    1 = N    2 = NE
;   3 = W     4 = X    5 = E
;   6 = SW    7 = S    8 = SE
; ==============================================================================
CompassSprites:
    DEFW Sprite_Compass_NW
    DEFW Sprite_Compass_N
    DEFW Sprite_Compass_NE
    DEFW Sprite_Compass_W
    DEFW Sprite_Compass_X
    DEFW Sprite_Compass_E
    DEFW Sprite_Compass_SW
    DEFW Sprite_Compass_S
    DEFW Sprite_Compass_SE

; ==============================================================================
; CompassWobbleTable - Indexada por idx target (0..8). 2 bytes por entry:
;   {prev_idx, next_idx} en sentido horario (clockwise).
; Mapping clockwise: N(1) -> NE(2) -> E(5) -> SE(8) -> S(7) -> SW(6) -> W(3) -> NW(0) -> N(1)
; idx 4 (X) no vibra; entry rellena con 4,4 como fallback inocuo.
; ==============================================================================
CompassWobbleTable:
    DEFB 3, 1                           ; 0 NW: prev=W, next=N
    DEFB 0, 2                           ; 1 N : prev=NW, next=NE
    DEFB 1, 5                           ; 2 NE: prev=N, next=E
    DEFB 6, 0                           ; 3 W : prev=SW, next=NW
    DEFB 4, 4                           ; 4 X : (no wobble)
    DEFB 2, 8                           ; 5 E : prev=NE, next=SE
    DEFB 7, 3                           ; 6 SW: prev=S, next=W
    DEFB 8, 6                           ; 7 S : prev=SE, next=SW
    DEFB 5, 7                           ; 8 SE: prev=E, next=S

; ==============================================================================
; WobblePhaseTable - 6 fases del wobble (1 frame cada una, 6 frames total).
; Indexada por (counter-1) -> 0..5. Valor:
;   0 = prev sprite, 1 = target sprite, 2 = next sprite.
; Con counter inicial 6 y decremento por frame:
;   counter 6 -> phase 5 -> prev   (primer estado al entrar a la sala)
;   counter 5 -> phase 4 -> target
;   counter 4 -> phase 3 -> next
;   counter 3 -> phase 2 -> target
;   counter 2 -> phase 1 -> prev
;   counter 1 -> phase 0 -> target (estado final, settle)
; ==============================================================================
WobblePhaseTable:
    DEFB 1, 0, 1, 2, 1, 0

; Sprites importados de References/flechas02 (16x16, esfera roja con flecha)
Sprite_Compass_N:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $61,$86, $01,$80, $41,$87, $A3,$C6
    DEFB $A3,$C4, $47,$E7, $07,$E0, $63,$C6
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_NE:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $00,$60, $41,$E7, $A7,$C6
    DEFB $AF,$C4, $4F,$87, $07,$80, $63,$06
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_E:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $06,$00, $4F,$87, $AF,$F6
    DEFB $AF,$F4, $4F,$87, $06,$00, $60,$06
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_SE:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $63,$06, $07,$80, $4F,$87, $AF,$C6
    DEFB $A7,$C4, $41,$E7, $00,$60, $60,$06
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_S:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $63,$C6, $07,$E0, $47,$E7, $A3,$C6
    DEFB $A3,$C4, $41,$87, $01,$80, $61,$86
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_SW:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$C6, $01,$E0, $41,$F7, $A3,$F6
    DEFB $A3,$E4, $47,$87, $06,$00, $60,$06
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_W:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $00,$60, $41,$F7, $AF,$F6
    DEFB $AF,$F4, $41,$F7, $00,$60, $60,$06
    DEFB $31,$CC, $1B,$98, $08,$50, $03,$80

Sprite_Compass_NW:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $06,$00, $47,$87, $A3,$E6
    DEFB $A3,$F4, $41,$F7, $01,$E0, $60,$C6
    DEFB $30,$0C, $1B,$98, $08,$50, $03,$80

Sprite_Compass_X:
    DEFB $00,$00, $7C,$3E, $70,$0E, $38,$1C
    DEFB $1C,$38, $0E,$70, $07,$E0, $03,$C0
    DEFB $03,$C0, $07,$E0, $0E,$70, $1C,$38
    DEFB $38,$1C, $70,$0E, $7C,$3E, $00,$00
