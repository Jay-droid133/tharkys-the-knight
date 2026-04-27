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

    ; Necesita redraw? screen cambio o PrevDist == $FF
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
    RET NZ                              ; sin cambios -> nada que hacer

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
    LD A, (.dcDistance)
    LD (PreviousObjectiveDistance), A
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

; Sprites importados de References/flechas02 (16x16, esfera roja con flecha)
Sprite_Compass_N:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $61,$86, $63,$C6, $C7,$E3, $CF,$F3
    DEFB $C1,$83, $C1,$83, $61,$86, $61,$86
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_NE:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $60,$06, $67,$E6, $C3,$E3, $C1,$E3
    DEFB $C3,$E3, $C7,$63, $6E,$26, $64,$06
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_E:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $60,$86, $60,$C6, $C0,$E3, $CF,$F3
    DEFB $CF,$F3, $C0,$E3, $60,$C6, $60,$86
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_SE:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $64,$06, $6E,$26, $C7,$63, $C3,$E3
    DEFB $C1,$E3, $C3,$E3, $67,$E6, $60,$06
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_S:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $61,$86, $61,$86, $C1,$83, $C1,$83
    DEFB $CF,$F3, $C7,$E3, $63,$C6, $61,$86
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_SW:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $60,$26, $64,$76, $C6,$E3, $C7,$C3
    DEFB $C7,$83, $C7,$C3, $67,$E6, $60,$06
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_W:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $61,$06, $63,$06, $C7,$03, $CF,$F3
    DEFB $CF,$F3, $C7,$03, $63,$06, $61,$06
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_NW:
    DEFB $03,$C0, $0F,$F0, $1C,$38, $30,$0C
    DEFB $60,$06, $67,$E6, $C7,$C3, $C7,$83
    DEFB $C7,$C3, $C6,$E3, $64,$76, $60,$26
    DEFB $30,$0C, $1C,$38, $0F,$F0, $03,$C0

Sprite_Compass_X:
    DEFB $00,$00, $7C,$3E, $70,$0E, $38,$1C
    DEFB $1C,$38, $0E,$70, $07,$E0, $03,$C0
    DEFB $03,$C0, $07,$E0, $0E,$70, $1C,$38
    DEFB $38,$1C, $70,$0E, $7C,$3E, $00,$00
