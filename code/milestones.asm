; ==============================================================================
; CADENA DE HITOS (CurrentObjective + resolucion de coordenadas)
; ==============================================================================
; CurrentObjective vive en variables.asm. Valor:
;   0..10 = hito que el jugador esta buscando ahora mismo (1..11 humano)
;   11    = todos los hitos completados (juego ganado)
;
; ----------------------------------------------------------------------------
; MilestoneTable: 11 entradas x 2 bytes {tipo, ref} - regla de AVANCE.
;   tipo 1 (PICKUP)  -> ref es key id 1..7 (ver KeyLockTable). Avanza al
;                       recoger el sprite cuyo behavior coincide.
;   tipo 2 (TRIGGER) -> ref es action id (1=townhall, 2=churchdoor, 3=towngate,
;                       4=bankdoor). Avanza al disparar el trigger correspondiente.
;   tipo 3 (SPECIAL) -> ref ignorado. Solo avanza con la tecla M (debug stub).
;
; MilestoneResolveTable: 11 x 2 bytes {tipo, ref} - regla de RESOLUCION
; (a que pantalla apunta la brujula). Igual que MilestoneTable salvo:
;   - Hito 7 (SPECIAL para advance): se resuelve como TRIGGER action 2
;     (puerta de la iglesia), donde se "encerrara" a los monsters.
;   - Hito 9 (TRIGGER 4 banco): TODO añadir trigger 4 a BumpTriggerTable o
;     hacer special-case para resolver $FF, $FF hasta que exista.
;   - Hito 11 (TRIGGER 3): puerta sur, sin trigger en BumpTriggerTable
;     todavia -> $FF, $FF (la cinematica final tiene CheckTownGateTriggerBg
;     custom AABB y no esta en BumpTriggerTable).
;
; Cambio respecto a la version 9-hitos: insertados 2 hitos intermedios
; (#8 cheque del banco, #9 cinematica del banco) entre #7 (encerrar monsters)
; y los antiguos #8/#9 (que pasan a #10/#11). Ver docs/bank_cutscene.md.
;
; Tecla M (debug): incrementa CurrentObjective sin chequear tipo. Skip libre,
; util para probar la cadena entera mientras los hitos 7, 9, 11 no tienen
; mecanica real (todos los SPECIAL/TRIGGER customs estan en cinematicas).
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
    DEFB MILESTONE_TYPE_PICKUP,   7     ; #8 NUEVO: cheque del banco (dinamica)
    DEFB MILESTONE_TYPE_TRIGGER,  4     ; #9 NUEVO: cinematica del banco
    DEFB MILESTONE_TYPE_PICKUP,   6     ; #10 (was #8): llave de la ciudad (dinamica)
    DEFB MILESTONE_TYPE_TRIGGER,  3     ; #11 (was #9): puerta sur (cutscene final)

MilestoneResolveTable:
    DEFB MILESTONE_TYPE_PICKUP,   1     ; #1
    DEFB MILESTONE_TYPE_PICKUP,   2     ; #2
    DEFB MILESTONE_TYPE_PICKUP,   3     ; #3
    DEFB MILESTONE_TYPE_PICKUP,   4     ; #4
    DEFB MILESTONE_TYPE_TRIGGER,  1     ; #5 town hall door
    DEFB MILESTONE_TYPE_PICKUP,   5     ; #6 church key (en town hall)
    DEFB MILESTONE_TYPE_TRIGGER,  2     ; #7 church door (apunta a la iglesia)
    DEFB MILESTONE_TYPE_PICKUP,   7     ; #8 NUEVO: cheque (resolverá a la iglesia tras drop)
    DEFB MILESTONE_TYPE_TRIGGER,  4     ; #9 NUEVO: bank trigger (sin entrada en BumpTriggerTable -> $FF)
    DEFB MILESTONE_TYPE_PICKUP,   6     ; #10 (was #8): bank key (dropped por cinematica del banco)
    DEFB MILESTONE_TYPE_TRIGGER,  3     ; #11 (was #9): south door (sin trigger -> $FF)

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
    CP 11                               ; chain extendida a 11 hitos (era 9)
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
    CALL CancelMagicCompass             ; magic compass: cancela al cumplir hito
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
    CP 11
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
    CALL CancelMagicCompass             ; magic compass: cancela al cumplir hito
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
    CP 11
    RET NC
    INC A
    LD (CurrentObjective), A
    CALL ResolveObjectiveScreen
    LD A, $FF
    LD (PreviousObjectiveDistance), A   ; brujula: primer cruce -> blanco
    CALL CancelMagicCompass             ; magic compass: cancela al saltar hito
    RET
.cmdkNotPressed:
    XOR A
    LD (MilestoneKeyDebounce), A
    RET

MilestoneKeyDebounce: DEFB 0

; ==============================================================================
; CheckCurrentKeyCycleKey - Tecla K: cicla CurrentKey 0->1->...->7->0 (debug)
; ==============================================================================
; Para probar cerraduras / triggers sin tener que jugar la cadena entera.
; El HUD de llave (DrawKeyHUD) ya lee CurrentKey cada frame -> feedback
; inmediato del valor actual.
;
; Rango: 1..6 son keys clasicas (forest/ruins/cemetery/clock/church/towngate),
; 7 es BankCheck (cheque del banco, slot 7 en KeyLockTable). Util para
; probar el bump trigger del banco sin tener que completar M7 antes.
;
; NOTA: ciclar K dentro de la sala de un lock NO permite abrir ese lock
; (el CollisionMap se construye al ENTRAR a la sala con el CurrentKey
; del momento; cambiarlo despues no rebuild walls). Para probar locks,
; ciclar K en una sala distinta y luego cruzar al room del lock.
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
    CP 8
    JR C, .ckcSet                       ; 1..7 dentro de rango (7 = BankCheck)
    XOR A                               ; 8 -> wrap a 0
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
    CP 11
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
    CP 4
    JR Z, .rosBankRoom                  ; M9 bank trigger: sin entry en BumpTriggerTable
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
.rosBankRoom:
    ; M9 (post-cheque): apunta al banco. CheckBankTriggerBg dispara la
    ; cinematica al chocar contra BgGfx_bank_door_closed en sala (8,8).
    LD A, BCS_BANK_ROOM_X
    LD (ObjectiveScreenX), A
    LD A, BCS_BANK_ROOM_Y
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

    ; Necesita redraw? screen cambio, PrevDist == $FF, wobble activo, o
    ; magic compass activo (que necesita redibujar para el blink y para
    ; reflejar la dir del path al cambiar de sala).
    LD A, (CurrentScreenX)
    LD B, A
    LD A, (LastCompassScreenX)
    CP B
    JP NZ, .dcRedrawNewScreen
    LD A, (CurrentScreenY)
    LD B, A
    LD A, (LastCompassScreenY)
    CP B
    JP NZ, .dcRedrawNewScreen
    LD A, (PreviousObjectiveDistance)
    CP $FF
    JR Z, .dcRedraw
    LD A, (CompassWobbleCounter)
    OR A
    JR NZ, .dcRedraw
    ; Modo magic compass: forzar redraw cada frame mientras esté activo
    ; (el blink + el path direction se manejan en .dcMagicCheck).
    LD A, (MagicCompassTimer)
    LD B, A
    LD A, (MagicCompassTimer + 1)
    OR B
    RET Z                               ; sin cambios + sin wobble + sin magic
    JR .dcRedraw

.dcRedrawNewScreen:
    ; Cambio de sala: el BFS del magic compass YA se recalculo
    ; sincronicamente en CheckScreenTransition.doTransition (via
    ; ForceComputeMagicCompassPath), asi que PathDir ya refleja la sala
    ; nueva. No marcamos PathDirty aqui — eso dispararia un BFS amortizado
    ; redundante que recalcularia el mismo path durante 3-4 frames.
    ;
    ; Invalidar cache del sprite dibujado: aunque el PathDir no cambio, los
    ; pixels del HUD pueden haberse pisado durante el redraw de la sala —
    ; hay que volver a dibujar el sprite minimo una vez.
    LD A, $FF
    LD (LastMagicCompassDrawn), A
    ; fall through a .dcRedraw

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
    ; SKIP el wobble si magic compass activa: en magic mode siempre dibujo
    ; Sprite_Compass_Magic (no oscila); el wobble logic solo gastaría CPU
    ; durante 9 frames post-transición sin efecto visible. Ese ahorro libera
    ; presupuesto del frame para que las agujas del reloj HUD no parpadeen
    ; cuando el frame de transición está apretado.
    LD A, (MagicCompassTimer)
    LD B, A
    LD A, (MagicCompassTimer + 1)
    OR B
    JR Z, .dcWobbleStartNormal           ; magic inactivo → wobble normal
    XOR A
    LD (CompassWobbleCounter), A         ; magic activo → fuerza counter=0, no override
    JR .dcWobbleEnd
.dcWobbleStartNormal:
    ; Patron (9 frames totales, 1 frame por fase, 9 fases):
    ;   prev2 -> prev -> target -> next -> next2 -> prev -> target -> prev -> target
    ; La X (idx 4) no vibra. Si el target cambia mid-wobble, se mantiene la
    ; cuenta atras y los prev/next/prev2/next2 se recalculan respecto al
    ; nuevo idx.
    ; Counter == 0 -> sin override, idx = target.
    LD A, (.dcSpriteIdx)
    CP 4
    JR NZ, .dcWobbleNotX
    ; X -> sin wobble. Forzar counter a 0 para que el early-exit del proximo
    ; frame no redibuje innecesariamente.
    XOR A
    LD (CompassWobbleCounter), A
    JR .dcWobbleEnd
.dcWobbleNotX:
    ; Si pantalla cambio, arrancar wobble (counter = 9)
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
    LD A, 9
    LD (CompassWobbleCounter), A
.dcWobbleResolve:
    LD A, (CompassWobbleCounter)
    OR A
    JR Z, .dcWobbleEnd                  ; counter 0 -> idx queda como target
    DEC A
    LD (CompassWobbleCounter), A
                                        ; A = phase 0..8 (1 frame por fase)
    LD HL, WobblePhaseTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                          ; 0=prev2, 1=prev, 2=target, 3=next, 4=next2
    CP 2
    JR Z, .dcWobbleEnd                  ; target -> no override
    ; A in {0,1,3,4}. Compactar a offset {0,1,2,3} dentro de WobbleTable
    ; (entry 4 bytes: prev2, prev, next, next2). 0,1 quedan; 3,4 -> 2,3.
    CP 3
    JR C, .dcWobbleOffsetReady
    DEC A
.dcWobbleOffsetReady:
    LD E, A
    LD A, (.dcSpriteIdx)
    ADD A, A                            ; idx*2
    ADD A, A                            ; idx*4 (stride 4 bytes por entry)
    ADD A, E                            ; +offset
    LD HL, CompassWobbleTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (.dcSpriteIdx), A                ; override

.dcWobbleEnd:

    ; --- Magic compass override: ¿activo y fuera de sala destino? ---
    ; Si sí, dibuja Sprite_Compass_Magic + pinta attrs custom (3 chars white
    ; sin bright + char activo white bright; en warning el char activo
    ; parpadea bright on/off a ~6 Hz).
    ; En sala destino (idx 4) o sin path ($FF), cae al render normal — la X
    ; blanca se mantiene tal cual.
    LD A, (MagicCompassTimer)
    LD B, A
    LD A, (MagicCompassTimer + 1)
    OR B
    JR Z, .dcMagicOff
    LD A, (.dcSpriteIdx)
    CP 4
    JR Z, .dcMagicOff                   ; en sala destino → X blanca normal
    LD A, (MagicCompassPathDir)
    CP $FF
    JR Z, .dcMagicOff                   ; sin path → render normal
    ; --- MAGIC HUD ---
    ; Cache: el sprite Sprite_Compass_Magic es siempre el mismo; sólo se
    ; redibuja cuando cambia PathDir (o no estaba dibujado todavía). El
    ; resto de frames basta con repintar los 4 attrs (ultra-barato), lo que
    ; libera CPU durante el wobble post-transición y evita que las agujas
    ; del reloj queden parcialmente actualizadas en frames con poco margen.
    LD A, (MagicCompassPathDir)
    LD B, A
    LD A, (LastMagicCompassDrawn)
    CP B
    JR Z, .dcMagicAttrsOnly             ; mismo path → solo attrs
    LD DE, Sprite_Compass_Magic
    CALL DrawCompassSprite
    LD A, (MagicCompassPathDir)
    LD (LastMagicCompassDrawn), A
.dcMagicAttrsOnly:
    CALL PaintMagicCompassAttrs
    JR .dcDrawDone

.dcMagicOff:
    ; Saliendo del modo magic (o no entrando): invalidar cache para que el
    ; próximo frame magic redibuje el sprite Sprite_Compass_Magic limpio.
    LD A, $FF
    LD (LastMagicCompassDrawn), A

    ; --- Color normal ---
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

.dcDrawDone:

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
    ; --- Solo si el knockback es DIRECTO del player ---
    ; Un kb heredado via billar (monstruo empuja a monstruo) no debe servir
    ; para encerrar al receptor: el bit ENTF_KB_DIRECT se set al golpear con
    ; espada y se clear cuando se hereda kb por colision.
    BIT ENTF_KB_DIRECT, (IX+ENT_FLAGS)
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
    ; --- En zona de trampa: comprobar si este monstruo es el esperado ---
    ; Type idx del monstruo = (ANIMBASE - SPRID_MONSTER_0) / 8.
    LD A, (IX+ENT_ANIMBASE)
    SUB SPRID_MONSTER_0
    SRL A
    SRL A
    SRL A                                   ; A = type idx 0..2
    LD B, A
    ; Type esperado = ChurchTrapOrderTable[NextChurchTrapStep].
    LD A, (NextChurchTrapStep)
    CP 3
    JR NC, .cctBlockAsWall                  ; ya capturados los 3 -> bloquear
    LD HL, ChurchTrapOrderTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = type esperado
    CP B
    JR NZ, .cctBlockAsWall                  ; tipo no esperado -> wall
    ; --- TRAMPA: tipo correcto, disparar TriggerChurchTrap ---
    CALL TriggerChurchTrap
    LD A, 1
    RET
.cctBlockAsWall:
    ; Tipo no esperado en zona de trampa: bloquear como si fuera pared.
    ; Caller (.moKbPreBorderOk) salta a .moKbWallBlock con A=2.
    LD A, 2
    RET
.cctNoTrap:
    XOR A
    RET

; Orden de captura: step idx -> type idx. Zombi=0, Ghost=2, Skeleton=1.
ChurchTrapOrderTable:
    DEFB 0, 2, 1

; ==============================================================================
; HighlightExpectedStatue - pinta la estatua del monstruo "esperado" en
; blanco brillante sobre paper negro ($47).
; ==============================================================================
; Llamada desde DrawScreen tras pintar BG y antes de SaveCleanAttrs.
; - No-op fuera de la sala de la iglesia.
; - No-op si todos los monstruos atrapados (NextChurchTrapStep >= 3).
; - Localiza la estatua del type esperado en CurrentScreenBuffer y
;   sobreescribe sus 2x3 chars con $47. Las otras dos estatuas (las que
;   aun no toca) conservan sus attrs originales del sprite.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
; HighlightExpectedStatue: pinta la estatua del esperado en blanco brillante
; ($47). Wrapper sobre PaintExpectedStatueAttr.
HighlightExpectedStatue:
    LD A, $47
    JR PaintExpectedStatueAttr

; PaintExpectedStatueAttr: pinta la estatua del esperado con el attr en A.
; Usado por HighlightExpectedStatue ($47, ON) y por UpdateStatueBlink que
; alterna entre $47 (ON) y $00 (OFF, statue invisible) durante el blink.
PaintExpectedStatueAttr:
    LD (.hesAttr), A
    ; --- Solo en la sala de la iglesia ---
    LD A, (CurrentScreenX)
    CP CHURCH_TRAP_SCREEN_X
    RET NZ
    LD A, (CurrentScreenY)
    CP CHURCH_TRAP_SCREEN_Y
    RET NZ
    ; --- Solo tras abrir la iglesia 1a vez ---
    ; Antes de abrir la puerta todas las estatuas mantienen sus attrs
    ; originales del sprite. Usamos ChurchEverOpened (sticky) en lugar de
    ; ChurchDoorOpen porque durante la cutscene de captura la puerta se
    ; cierra y queremos que el highlight de la siguiente estatua se aplique
    ; al terminar el humo, NO esperar a que el jugador re-abra la puerta.
    LD A, (ChurchEverOpened)
    OR A
    RET Z
    ; --- Solo si quedan monstruos por atrapar ---
    LD A, (NextChurchTrapStep)
    CP 3
    RET NC
    ; --- Type esperado -> statue id ---
    LD HL, ChurchTrapOrderTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; type idx esperado
    LD HL, StatueIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = statue id
    OR A
    RET Z
    LD (.hesTargetId), A
    ; --- Buscar la estatua en CurrentScreenBuffer (4B per entry) ---
    LD HL, (CurrentScreenAddr)
.hesLoop:
    LD A, (HL)
    CP $FF
    RET Z                                   ; estatua no en esta sala
    LD B, A
    LD A, (.hesTargetId)
    CP B
    JR Z, .hesFound
    LD DE, 4
    ADD HL, DE
    JR .hesLoop
.hesFound:
    INC HL
    LD A, (HL)                              ; charX
    LD B, A
    INC HL
    LD A, (HL)                              ; charY (sin BG_Y_OFFSET)
    ADD A, BG_Y_OFFSET                      ; con offset HUD
    LD C, A                                 ; C = charY (post-HUD)
    ; --- Calcular addr en ATTR_BASE: $5800 + charY*32 + charX ---
    LD H, 0
    LD L, C
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; HL = charY * 32
    LD E, B
    LD D, 0
    ADD HL, DE                              ; + charX
    LD DE, $5800
    ADD HL, DE                              ; HL = attr addr top-left
    ; --- Pintar 2 chars de ancho x 3 de alto = 6 cells con el attr ---
    ; Por diseno nada del juego pasa por encima de las estatuas, asi que
    ; no hace falta sincronizar CleanAttrMap.
    LD A, (.hesAttr)
    LD B, 3                                 ; 3 filas de chars
.hesRow:
    LD (HL), A
    INC HL
    LD (HL), A                              ; (charX+1)
    LD DE, 31
    ADD HL, DE                              ; siguiente fila col 0
    DJNZ .hesRow
    RET
.hesAttr:     DEFB 0
.hesTargetId: DEFB 0

; ==============================================================================
; Statue blink: parpadeo ON/OFF al activarse el highlight de una estatua.
; ==============================================================================
; StatueBlinkCounter cuenta atras desde STATUE_BLINK_FRAMES. Cada N ticks
; alterna entre ON ($47) y OFF ($00 = invisible). Al llegar a 0, settle ON.
; Patron (32 frames de blink, 2 ticks por fase, 16 fases ON-OFF-...-ON-OFF
; + ON final settle): 8 ciclos de ON-OFF en total.
; ==============================================================================
STATUE_BLINK_FRAMES   EQU 32

StartStatueBlink:
    ; Arranca el blink y pinta inmediatamente la primera frame ON. Debe
    ; llamarse en lugar de HighlightExpectedStatue en los puntos donde
    ; queremos efecto "se enciende": ApplyChurchTrapDone, UpdateBellsDoneTimer
    ; (caso A), .cbtActChurchDoor (caso B).
    LD A, STATUE_BLINK_FRAMES
    LD (StatueBlinkCounter), A
    JP HighlightExpectedStatue              ; initial ON paint

UpdateStatueBlink:
    ; Llamada cada frame desde MainLoop. No-op si counter == 0.
    LD A, (StatueBlinkCounter)
    OR A
    RET Z
    DEC A
    LD (StatueBlinkCounter), A
    JR NZ, .usbInProgress
    ; Counter recien llego a 0: settle ON
    JP HighlightExpectedStatue
.usbInProgress:
    ; counter actual en A (1..31). Phase = (counter / 2) bit 0:
    ;   bit 0 = 1 -> ON, bit 0 = 0 -> OFF. Cambio de fase cada 2 ticks.
    SRL A
    AND $01
    JR Z, .usbOff
    LD A, $47
    JP PaintExpectedStatueAttr
.usbOff:
    XOR A
    JP PaintExpectedStatueAttr

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

; Fase SMOKE: 3 frames de humo XOR-dibujados encima de los restos.
;   tick 0  -> dibujar restos (1 vez) + dibujar smoke[0]
;   tick 4  -> erase smoke[0], dibujar smoke[1]
;   tick 8  -> erase smoke[1], dibujar smoke[2]
;   tick 12 -> erase smoke[2], pasar a DONE
CHURCH_CUTSCENE_SMOKE_PER_FRAME     EQU 2       ; ticks por sub-frame
CHURCH_CUTSCENE_SMOKE_TOTAL         EQU 12      ; 3 sub-frames * 4 = 12 ticks

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
    ; --- 3. Parar blink y forzar estatua en ON ($47) ---
    ; Si la cutscene arrancase con un blink mid-frame OFF ($00), los pixels
    ; del shake y del humo se renderizarian invisibles (ink black sobre
    ; paper black). Forzando ON aqui garantizamos que la animacion de
    ; temblor se vea con ink blanco brillante sobre paper negro.
    XOR A
    LD (StatueBlinkCounter), A              ; parar blink
    PUSH IX
    CALL HighlightExpectedStatue            ; pintar $47
    ; --- 3.5. Despawn Death + stop musica si estaba activa ---
    ; Si el player tardo mas de 6s en entrar al cutscene, Death pudo haber
    ; spawneado en la iglesia. MainLoop salta la AI durante el cutscene, asi
    ; que su sprite quedaria congelado en pantalla. La quitamos aqui.
    CALL SilentKillDeath                    ; erase sprite + clear flag + reset timer
    LD A, $FF
    CALL StartMusic                         ; sentinel STOP (idempotente si no sonaba)
    ; Si este es el 3er monster (esqueleto, NextChurchTrapStep=2 antes del INC
    ; en ApplyChurchTrapDone), parar tambien el secuencer ad-hoc de
    ; MonstersMusic — tras esta cutscene ya no quedan monsters en juego.
    LD A, (NextChurchTrapStep)
    CP 2
    CALL Z, StopMonstersMusic
    POP IX
    ; --- 4. Activar cutscene (phase 1 LOOK, frame 0) ---
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
    DEC A
    JP Z, .ucsSmokePhase
    ; Phase 4 (DONE): aplicar efectos finales y terminar cutscene.
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
    ; Shake "horizontal" via byte-shift del sprite (no XOR, no jitter de
    ; posicion). Se queda dentro del rectangulo de chars de la estatua y
    ; respeta los attrs originales -- evita el "cuadrado" que dejaba el
    ; XOR shift sub-char al destapar la zona donde el wall ya no existe.
    ;
    ; Jitter -1 / 0 / +1 bits, pseudo-random via R + frame counter.
    ; Distribucion 50% sin shift, 25% left, 25% right (lookup table).
    LD A, R
    AND $03
    LD HL, .ucsShakeJitterTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD B, A                                 ; B = jitter (preservar sobre el pick de tabla)
    ; Pick statue table: primer mitad = entera, segunda mitad = rota.
    LD A, (ChurchCutsceneFrame)
    CP CHURCH_CUTSCENE_SHAKE_FRAMES / 2
    LD HL, StatueIdTable
    JR C, .ucsShakeTablePicked
    LD HL, StatueBrokenIdTable
.ucsShakeTablePicked:
    LD A, B                                 ; restore jitter para la llamada
    CALL ChurchCutsceneShakeStatueByteShift
    ; Border flicker blanco/negro cada frame (efecto "alarma"). No tocamos
    ; CurrentBorderColor: si suena un SFX se restaura a negro al terminar,
    ; y al salir de la fase forzamos borde a negro explicitamente.
    LD A, (ChurchCutsceneFrame)
    AND $01
    JR Z, .ucsShakeBorderBlack
    LD A, WHITE
    JR .ucsShakeBorderOut
.ucsShakeBorderBlack:
    XOR A                                   ; BLACK
.ucsShakeBorderOut:
    OUT (254), A
    LD HL, ChurchCutsceneFrame
    INC (HL)
    RET
.ucsShakeJitterTable:
    DEFB 0, $FF, 0, 1                       ; map(R&3) -> jitter (0=no, FF=-1, 1=+1)
.ucsShakeStatueDone:
    ; Restaurar borde a negro tras el flicker antes de cualquier SFX.
    XOR A
    OUT (254), A
    ; Erase final via direct write (todo a 0) + SFX + transicion a SMOKE.
    ; (No XOR: el ultimo frame del shake dejo pixels arbitrarios; un erase
    ; directo a 0 garantiza que no queden residuos.)
    CALL ChurchCutsceneEraseStatueDirect
    LD HL, SFX_EnemyDeath
    CALL PlaySFX
    LD A, 3
    LD (ChurchCutscenePhase), A
    XOR A
    LD (ChurchCutsceneFrame), A             ; reset para SMOKE
    RET

; ---- Phase 3: humo desvaneciendose sobre los restos ----
; Tick 0 (entry): dibujar restos del monster + smoke[0] (XOR).
; Tick 8 / 16: erase smoke prev + draw smoke next (XOR de ambos).
; Tick 24: erase smoke[2], pasar a fase 4 (DONE).
; Entre transiciones, solo incrementa frame counter.
.ucsSmokePhase:
    LD A, (ChurchCutsceneFrame)
    OR A
    JR Z, .ucsSmokeEntry
    CP CHURCH_CUTSCENE_SMOKE_PER_FRAME              ; tick 4
    JR Z, .ucsSmokeStep1
    CP CHURCH_CUTSCENE_SMOKE_PER_FRAME * 2          ; tick 8
    JR Z, .ucsSmokeStep2
    CP CHURCH_CUTSCENE_SMOKE_TOTAL                  ; tick 12
    JR Z, .ucsSmokeEnd
    JR .ucsSmokeIncFrame
.ucsSmokeEntry:
    ; Dibujar restos en la base de la estatua (permanecen tras la cutscene)
    LD A, (ChurchCutsceneTypeIdx)
    CALL DrawRemainsForType
    ; Dibujar smoke[0] (XOR)
    XOR A
    CALL DrawSmokeFrameXor
    JR .ucsSmokeIncFrame
.ucsSmokeStep1:
    XOR A
    CALL DrawSmokeFrameXor                  ; erase smoke[0]
    LD A, 1
    CALL DrawSmokeFrameXor                  ; draw smoke[1]
    JR .ucsSmokeIncFrame
.ucsSmokeStep2:
    LD A, 1
    CALL DrawSmokeFrameXor                  ; erase smoke[1]
    LD A, 2
    CALL DrawSmokeFrameXor                  ; draw smoke[2]
    JR .ucsSmokeIncFrame
.ucsSmokeEnd:
    LD A, 2
    CALL DrawSmokeFrameXor                  ; erase smoke[2]
    CALL ClearSmokeAttrs                    ; 2x2 chars -> paper/ink black
    LD A, 4
    LD (ChurchCutscenePhase), A
    XOR A
    LD (ChurchCutsceneFrame), A
    RET
.ucsSmokeIncFrame:
    LD HL, ChurchCutsceneFrame
    INC (HL)
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
; ChurchCutsceneShakeStatueByteShift - shake "horizontal" sin tocar attrs
; IN: HL = ptr a tabla de IDs de estatua (StatueIdTable o StatueBrokenIdTable),
;     A  = jitter signed (-1, 0, +1) en bits.
; ==============================================================================
; IN: A = jitter signed (-1, 0, +1) en bits.
; Carga el sprite de la estatua, shiftea sus 16-bit rows en memoria (por
; reg D/E) y vuelca los bytes resultantes a VRAM en (StatueOrigX,
; StatueOrigY). DIRECT WRITE -- sobreescribe pixels en su sitio sin tocar
; los chars adyacentes ni los attrs. Cada frame reemplaza pixels con la
; version shifted, sin XOR.
;
; Por que esto evita el "cuadrado" del XOR: el sprite jamas sale de su
; rectangulo de 2x3 chars, asi que sus attrs originales (set al pintar la
; sala) siguen siendo visualmente correctos. El wall que tapaba la
; estatua se perdio cuando la estatua se pinto la primera vez con
; DrawBgGfxSprite (direct write), pero como nunca destapamos el rectangulo
; de la estatua, el wall perdido no se ve.
;
; Pixels que caen "fuera" al shiftear (LSB en shift left, MSB en shift right)
; se descartan. La estatua tipicamente tiene padding lateral asi que un
; shift de 1 bit no pierde pixels visibles.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
ChurchCutsceneShakeStatueByteShift:
    LD (.csbsJitter), A
    ; HL = tabla de IDs (entera o rota) elegida por el caller. Indexar por TypeIdx.
    LD A, (ChurchCutsceneTypeIdx)
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    OR A
    RET Z                                   ; sin estatua
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
    ; BgSpriteBuffer ahora tiene [height=24, width=2, pixel_CPL × 48 bytes, ...]
    LD IX, BgSpriteBuffer
    LD A, (IX+0)                            ; height (24 para statues 16x24)
    OR A
    RET Z
    LD B, A                                 ; B = row counter
    INC IX
    INC IX                                  ; IX -> pixel data
    ; Calcular addr VRAM en (origX, origY)
    LD A, (ChurchCutsceneStatueOrigY)
    LD D, A
    LD A, (ChurchCutsceneStatueOrigX)
    LD E, A
    CALL CalcPixelAddr                      ; HL = VRAM addr
.csbsRow:
    PUSH BC
    PUSH HL                                 ; save inicio fila VRAM
    ; Leer 2 pixel bytes del buffer (CPL'd) -> un-CPL en D/E
    LD A, (IX+0)
    CPL
    LD D, A                                 ; D = byte0 (8 cols izquierda, original)
    LD A, (IX+1)
    CPL
    LD E, A                                 ; E = byte1 (8 cols derecha, original)
    ; Aplicar jitter (D|E como entero 16-bit, MSB izquierda)
    LD A, (.csbsJitter)
    OR A
    JR Z, .csbsWrite                        ; sin shift
    JP M, .csbsLeft                         ; A < 0 -> shift left
    ; A > 0 -> shift right by 1 (pixels visualmente a la derecha)
    SRL D
    RR E
    JR .csbsWrite
.csbsLeft:
    SLA E
    RL D
.csbsWrite:
    LD A, D
    LD (HL), A
    INC HL
    LD A, E
    LD (HL), A
    POP HL
    CALL NextPixelLine                      ; HL = siguiente pixel row
    INC IX
    INC IX                                  ; siguiente row del buffer (2 bytes)
    POP BC
    DJNZ .csbsRow
    RET
.csbsJitter: DEFB 0

; ==============================================================================
; ChurchCutsceneEraseStatueDirect - escribe 0s sobre los 24 rows x 2 bytes
; donde estaba la estatua. Usa direct write (no XOR), lo que da un erase
; final limpio independientemente de lo que dibujara el ultimo shake frame.
; Llamada al final de la fase SHAKE en sustitucion del XOR-erase antiguo.
; Destruye: AF, BC, HL.
; ==============================================================================
ChurchCutsceneEraseStatueDirect:
    LD A, (ChurchCutsceneStatueOrigY)
    LD D, A
    LD A, (ChurchCutsceneStatueOrigX)
    LD E, A
    CALL CalcPixelAddr
    LD B, 24                                ; statues son 24 px de alto
.csedRow:
    XOR A                                   ; A=0 cada iter (NextPixelLine corrompe A)
    LD (HL), A
    INC HL
    LD (HL), A
    DEC HL                                  ; volver a inicio fila
    PUSH BC
    CALL NextPixelLine
    POP BC
    DJNZ .csedRow
    RET

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

; church-cutscene block (lines 1489-2181 originales) movido a code/church_cutscene.asm
; e incluido en $6000+ desde main.asm (slot 1, siempre visible).

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
; CompassWobbleTable - Indexada por idx target (0..8). 4 bytes por entry:
;   {prev2_idx, prev_idx, next_idx, next2_idx} en sentido horario (clockwise).
; Mapping clockwise: N(1) -> NE(2) -> E(5) -> SE(8) -> S(7) -> SW(6) -> W(3) -> NW(0) -> N(1)
; prev2/next2 son dos posiciones counter-/clockwise respectivamente.
; idx 4 (X) no vibra; entry rellena con 4,4,4,4 como fallback inocuo.
; ==============================================================================
CompassWobbleTable:
    DEFB 6, 3, 1, 2                     ; 0 NW: prev2=SW, prev=W,  next=N,  next2=NE
    DEFB 3, 0, 2, 5                     ; 1 N : prev2=W,  prev=NW, next=NE, next2=E
    DEFB 0, 1, 5, 8                     ; 2 NE: prev2=NW, prev=N,  next=E,  next2=SE
    DEFB 7, 6, 0, 1                     ; 3 W : prev2=S,  prev=SW, next=NW, next2=N
    DEFB 4, 4, 4, 4                     ; 4 X : (no wobble)
    DEFB 1, 2, 8, 7                     ; 5 E : prev2=N,  prev=NE, next=SE, next2=S
    DEFB 8, 7, 3, 0                     ; 6 SW: prev2=SE, prev=S,  next=W,  next2=NW
    DEFB 5, 8, 6, 3                     ; 7 S : prev2=E,  prev=SE, next=SW, next2=W
    DEFB 2, 5, 7, 6                     ; 8 SE: prev2=NE, prev=E,  next=S,  next2=SW

; ==============================================================================
; WobblePhaseTable - 9 fases del wobble (1 frame cada una, 9 frames total).
; Indexada por (counter-1) -> 0..8. Valor:
;   0 = prev2, 1 = prev, 2 = target, 3 = next, 4 = next2.
; Con counter inicial 9 y decremento por frame:
;   counter 9 -> phase 8 -> prev2  (primer estado al entrar a la sala)
;   counter 8 -> phase 7 -> prev
;   counter 7 -> phase 6 -> target
;   counter 6 -> phase 5 -> next
;   counter 5 -> phase 4 -> next2
;   counter 4 -> phase 3 -> prev
;   counter 3 -> phase 2 -> target
;   counter 2 -> phase 1 -> prev
;   counter 1 -> phase 0 -> target (estado final, settle)
; ==============================================================================
WobblePhaseTable:
    DEFB 2, 1, 2, 1, 4, 3, 2, 1, 0

; Sprites importados de References/flechas02 (16x16, esfera roja con flecha)
Sprite_Compass_N:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $61,$86, $61,$86, $01,$80, $C3,$C3
    DEFB $C3,$C3, $07,$E0, $67,$E6, $63,$C6
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_NE:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $60,$66, $01,$E0, $C7,$C3
    DEFB $CF,$C3, $0F,$80, $67,$86, $63,$06
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_E:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $66,$06, $0F,$80, $CF,$F3
    DEFB $CF,$F3, $0F,$80, $66,$06, $60,$06
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_SE:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $63,$06, $67,$86, $0F,$80, $CF,$C3
    DEFB $C7,$C3, $01,$E0, $60,$66, $60,$06
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_S:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $63,$C6, $67,$E6, $07,$E0, $C3,$C3
    DEFB $C3,$C3, $01,$80, $61,$86, $61,$86
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_SW:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$C6, $61,$E6, $01,$F0, $C3,$F3
    DEFB $C3,$E3, $07,$80, $66,$06, $60,$06
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_W:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $60,$66, $01,$F0, $CF,$F3
    DEFB $CF,$F3, $01,$F0, $60,$66, $60,$06
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_NW:
    DEFB $03,$40, $0A,$D0, $1A,$58, $30,$0C
    DEFB $60,$06, $66,$06, $07,$80, $C3,$E3
    DEFB $C3,$F3, $01,$F0, $61,$E6, $60,$C6
    DEFB $30,$0C, $1C,$38, $0D,$B0, $01,$80

Sprite_Compass_X:
    DEFB $00,$00, $7C,$3E, $70,$0E, $38,$1C
    DEFB $1C,$38, $0E,$70, $07,$E0, $03,$C0
    DEFB $03,$C0, $07,$E0, $0E,$70, $1C,$38
    DEFB $38,$1C, $70,$0E, $7C,$3E, $00,$00
