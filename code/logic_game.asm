; ==============================================================================
; LOGICA DEL JUEGO - Sistema de Movimiento estilo Sabre Wulf
; ==============================================================================
; Caracteristicas implementadas:
; - Posicion 16-bit (subpixel) para movimiento suave
; - Velocidades distintas corriendo vs peleando (como Sabre Wulf)
; - 8 direcciones via teclado QAOP
; - Direccion de ataque retenida al moverse Norte/Sur
; - Animacion con delays configurables por estado
; - Limites de pantalla
; ==============================================================================

; ==============================================================================
; ReadInput - Lee teclado y genera direccion + fuego
; ==============================================================================
; Esquema de teclado ZX Spectrum:
;   Q = Arriba, A = Abajo, O = Izquierda, P = Derecha, SPACE = Fuego
; Salida: InputDirection y InputFire actualizados
; ==============================================================================
ReadInput:
    XOR A
    LD (InputDirection), A      ; Limpiar direccion
    LD (InputFire), A           ; Limpiar fuego

    ; --- Leer Q (Arriba) ---
    ; Fila Q,W,E,R,T = puerto $FBFE, bit 0 = Q
    LD BC, $FBFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noUp
    LD A, (InputDirection)
    OR DIR_N
    LD (InputDirection), A
.noUp:

    ; --- Leer A (Abajo) ---
    ; Fila A,S,D,F,G = puerto $FDFE, bit 0 = A
    LD BC, $FDFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noDown
    LD A, (InputDirection)
    OR DIR_S
    LD (InputDirection), A
.noDown:

    ; --- Leer O (Izquierda) ---
    ; Fila P,O,I,U,Y = puerto $DFFE, bit 1 = O
    LD BC, $DFFE
    IN A, (C)
    BIT 1, A
    JR NZ, .noLeft
    LD A, (InputDirection)
    OR DIR_W
    LD (InputDirection), A
.noLeft:

    ; --- Leer P (Derecha) ---
    ; Fila P,O,I,U,Y = puerto $DFFE, bit 0 = P
    LD BC, $DFFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noRight
    LD A, (InputDirection)
    OR DIR_E
    LD (InputDirection), A
.noRight:

    ; --- Leer SPACE (Fuego) ---
    ; Fila SPACE,SS,M,N,B = puerto $7FFE, bit 0 = SPACE
    LD BC, $7FFE
    IN A, (C)
    BIT 0, A
    JR NZ, .noFire
    LD A, 1
    LD (InputFire), A
.noFire:

    ; --- Cancelar direcciones opuestas simultaneas ---
    LD A, (InputDirection)
    LD B, A

    ; Si N y S a la vez, cancelar ambos
    AND DIR_N | DIR_S
    CP DIR_N | DIR_S
    JR NZ, .noVertCancel
    LD A, B
    AND ~(DIR_N | DIR_S) & $FF
    LD B, A
.noVertCancel:

    ; Si E y W a la vez, cancelar ambos
    LD A, B
    AND DIR_E | DIR_W
    CP DIR_E | DIR_W
    JR NZ, .noHorizCancel
    LD A, B
    AND ~(DIR_E | DIR_W) & $FF
    LD B, A
.noHorizCancel:

    LD A, B
    LD (InputDirection), A
    RET

; ==============================================================================
; UpdateLogic - Actualiza movimiento y animacion del jugador
; ==============================================================================
UpdateLogic:
    CALL UpdatePlayerState
    CALL UpdatePlayerMovement
    CALL UpdatePlayerAnimation
    RET

; ==============================================================================
; UpdatePlayerState - Determina estado (idle/running/fighting) y direccion
; ==============================================================================
UpdatePlayerState:
    LD A, (InputDirection)
    LD B, A                     ; B = direccion del input
    LD A, (InputFire)
    LD C, A                     ; C = fuego

    ; Si no hay direccion ni fuego -> idle
    LD A, B
    OR C
    JR NZ, .notIdle

    ; --- Estado IDLE ---
    LD A, STATE_IDLE
    LD (PlayerState), A
    LD A, DIR_NONE
    LD (PlayerDir), A
    RET

.notIdle:
    ; Guardar direccion del input como direccion de movimiento
    LD A, B
    LD (PlayerDir), A

    ; Actualizar ultima direccion horizontal si hay componente E/W
    AND DIR_E | DIR_W
    JR Z, .noHorizUpdate
    LD (PlayerLastHDir), A
.noHorizUpdate:

    ; Determinar si esta peleando o corriendo
    LD A, C
    OR A
    JR Z, .stateRunning

    ; --- Estado FIGHTING ---
    ; Sabre Wulf: al pelear N/S, se retiene la ultima dir horizontal
    LD A, STATE_FIGHTING
    LD (PlayerState), A
    LD (PlayerFire), A          ; Marcar fuego activo
    RET

.stateRunning:
    LD A, STATE_RUNNING
    LD (PlayerState), A
    XOR A
    LD (PlayerFire), A          ; Fuego inactivo
    RET

; ==============================================================================
; UpdatePlayerMovement - Aplica velocidad 16-bit a la posicion
; ==============================================================================
; Como en Sabre Wulf:
; - Posiciones en 16 bits (Hi=pixel, Lo=subpixel)
; - Velocidad se suma/resta segun direccion
; - Velocidad distinta corriendo vs peleando
; ==============================================================================
UpdatePlayerMovement:
    LD A, (PlayerDir)
    OR A
    RET Z                       ; Sin movimiento si DIR_NONE

    ; Obtener velocidades segun estado
    CALL GetCurrentSpeed        ; DE = speedX, HL = speedY

    ; --- Movimiento Horizontal ---
    LD A, (PlayerDir)
    BIT 2, A                    ; Bit 2 = DIR_E
    JR Z, .noEast
    CALL MoveEast
.noEast:
    LD A, (PlayerDir)
    BIT 3, A                    ; Bit 3 = DIR_W
    JR Z, .noWest
    CALL MoveWest
.noWest:

    ; --- Movimiento Vertical ---
    LD A, (PlayerDir)
    BIT 0, A                    ; Bit 0 = DIR_N
    JR Z, .noNorth
    CALL MoveNorth
.noNorth:
    LD A, (PlayerDir)
    BIT 1, A                    ; Bit 1 = DIR_S
    JR Z, .noSouth
    CALL MoveSouth
.noSouth:
    RET

; ==============================================================================
; GetCurrentSpeed - Devuelve velocidades segun estado
; Salida: DE = velocidad X, HL = velocidad Y (guardadas en SpeedCache)
; ==============================================================================
GetCurrentSpeed:
    LD A, (PlayerState)
    CP STATE_FIGHTING
    JR Z, .fightSpeed

    ; Velocidad de correr
    LD DE, SPEED_RUN_X
    LD HL, SPEED_RUN_Y
    JR .storeSpeed

.fightSpeed:
    LD DE, SPEED_FIGHT_X
    LD HL, SPEED_FIGHT_Y

.storeSpeed:
    LD (SpeedCacheX), DE
    LD (SpeedCacheY), HL
    RET

; --- Variables temporales de velocidad ---
SpeedCacheX:    DEFW 0
SpeedCacheY:    DEFW 0

; ==============================================================================
; MoveEast - Sumar velocidad X a la posicion
; ==============================================================================
MoveEast:
    LD DE, (SpeedCacheX)        ; DE = velocidad X (16-bit)
    LD A, (PlayerXLo)
    ADD A, E
    LD (PlayerXLo), A
    LD A, (PlayerXHi)
    ADC A, D
    ; Comprobar limite derecho
    CP SCREEN_MAX_X
    JR C, .okEast
    LD A, SCREEN_MAX_X          ; Clamp al limite
    XOR A
    LD (PlayerXLo), A           ; Limpiar subpixel al hacer clamp
    LD A, SCREEN_MAX_X
.okEast:
    LD (PlayerXHi), A
    RET

; ==============================================================================
; MoveWest - Restar velocidad X de la posicion
; ==============================================================================
MoveWest:
    LD DE, (SpeedCacheX)
    LD A, (PlayerXLo)
    SUB E
    LD (PlayerXLo), A
    LD A, (PlayerXHi)
    SBC A, D
    ; Comprobar limite izquierdo
    JR NC, .okWest
    XOR A                       ; Clamp a 0
    LD (PlayerXLo), A
    LD (PlayerXHi), A
    RET
.okWest:
    LD (PlayerXHi), A
    RET

; ==============================================================================
; MoveSouth - Sumar velocidad Y a la posicion
; ==============================================================================
MoveSouth:
    LD DE, (SpeedCacheY)
    LD A, (PlayerYLo)
    ADD A, E
    LD (PlayerYLo), A
    LD A, (PlayerYHi)
    ADC A, D
    CP SCREEN_MAX_Y
    JR C, .okSouth
    XOR A
    LD (PlayerYLo), A
    LD A, SCREEN_MAX_Y
.okSouth:
    LD (PlayerYHi), A
    RET

; ==============================================================================
; MoveNorth - Restar velocidad Y de la posicion
; ==============================================================================
MoveNorth:
    LD DE, (SpeedCacheY)
    LD A, (PlayerYLo)
    SUB E
    LD (PlayerYLo), A
    LD A, (PlayerYHi)
    SBC A, D
    JR NC, .okNorth
    XOR A
    LD (PlayerYLo), A
    LD (PlayerYHi), A
    RET
.okNorth:
    LD (PlayerYHi), A
    RET

; ==============================================================================
; UpdatePlayerAnimation - Selecciona animacion segun estado/direccion
; ==============================================================================
; Estilo Sabre Wulf: tabla de acciones indexada por estado+direccion.
; Cada entrada define: puntero base en SpriteFrameTable, num frames, delay.
; Al cambiar de animacion se reinicia el frame.
; ==============================================================================
UpdatePlayerAnimation:
    ; Determinar animacion segun estado y direccion
    LD A, (PlayerState)
    CP STATE_FIGHTING
    JR Z, .animFight
    CP STATE_RUNNING
    JR Z, .animRun

    ; --- IDLE ---
    LD HL, ANIM_IDX_IDLE
    LD B, 2                     ; 2 frames idle
    LD C, ANIM_DELAY_IDLE
    JR .applyAnim

.animFight:
    ; Pelear usa la ultima dir horizontal retenida (como Sabre Wulf)
    LD A, (PlayerLastHDir)
    CP DIR_W
    JR Z, .fightW
    LD HL, ANIM_IDX_FIGHT_E
    JR .fightSet
.fightW:
    LD HL, ANIM_IDX_FIGHT_W
.fightSet:
    LD B, 2                     ; 2 frames fight
    LD C, ANIM_DELAY_RUN
    JR .applyAnim

.animRun:
    LD A, (PlayerDir)
    ; Prioridad: si hay componente E/W, usar esa animacion
    BIT 2, A                    ; DIR_E?
    JR NZ, .runE
    BIT 3, A                    ; DIR_W?
    JR NZ, .runW
    BIT 0, A                    ; DIR_N?
    JR NZ, .runN
    ; DIR_S o fallback
    LD HL, ANIM_IDX_WALK_S
    JR .runSet
.runE:
    LD HL, ANIM_IDX_WALK_E
    JR .runSet
.runW:
    LD HL, ANIM_IDX_WALK_W
    JR .runSet
.runN:
    LD HL, ANIM_IDX_WALK_N
.runSet:
    LD B, 3                     ; 3 frames walk
    LD C, ANIM_DELAY_RUN

.applyAnim:
    ; HL = offset en SpriteFrameTable, B = num frames, C = delay
    ; Comprobar si cambio la animacion
    LD A, (PlayerAnimBase)
    CP L
    JR NZ, .newAnim
    LD A, (PlayerAnimBase+1)
    CP H
    JR Z, .sameAnim

.newAnim:
    ; Animacion nueva -> reiniciar
    LD (PlayerAnimBase), HL
    LD A, B
    LD (PlayerAnimNumFrames), A
    XOR A
    LD (PlayerAnimFrame), A
    LD A, C
    LD (PlayerAnimDelay), A
    RET

.sameAnim:
    ; Decrementar delay
    LD A, (PlayerAnimDelay)
    DEC A
    JR NZ, .noAdvance

    ; Avanzar frame
    LD A, C
    LD (PlayerAnimDelay), A
    LD A, (PlayerAnimFrame)
    INC A
    CP B
    JR C, .frameOk
    XOR A
.frameOk:
    LD (PlayerAnimFrame), A
    RET

.noAdvance:
    LD (PlayerAnimDelay), A
    RET

; ==============================================================================
; GetCurrentSpriteAddr - Devuelve puntero al sprite actual
; ==============================================================================
; Salida: IX = puntero a los datos bitmap del sprite
; ==============================================================================
GetCurrentSpriteAddr:
    LD HL, (PlayerAnimBase)     ; HL = offset en la tabla
    LD A, (PlayerAnimFrame)
    ADD A, A                    ; * 2 (cada entrada es DEFW)
    LD E, A
    LD D, 0
    ADD HL, DE                  ; HL = offset del frame actual
    LD DE, SpriteFrameTable
    ADD HL, DE                  ; HL = direccion en SpriteFrameTable
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = puntero al sprite
    PUSH DE
    POP IX                      ; IX = puntero al sprite
    RET

; ==============================================================================
; DrawPlayer - Dibuja el sprite del jugador con animacion
; ==============================================================================
DrawPlayer:
    ; --- Restaurar atributos de tile en posicion anterior ---
    LD A, (PlayerOldYHi)
    AND $F8
    LD D, A
    LD A, (PlayerOldXHi)
    AND $F8
    LD E, A
    CALL RestoreTileAttrs

    ; --- Borrar sprite anterior ---
    LD A, (PlayerOldYHi)
    AND $F8
    LD D, A
    LD A, (PlayerOldXHi)
    AND $F8
    LD E, A
    CALL EraseSprite

    ; --- Guardar posicion actual como "old" ---
    LD A, (PlayerXHi)
    LD (PlayerOldXHi), A
    LD A, (PlayerYHi)
    LD (PlayerOldYHi), A

    ; --- Obtener sprite actual segun animacion ---
    CALL GetCurrentSpriteAddr   ; IX = datos del sprite

    ; --- Dibujar sprite en posicion actual ---
    LD A, (PlayerYHi)
    AND $F8
    LD D, A
    LD A, (PlayerXHi)
    AND $F8
    LD E, A
    CALL DrawSprite             ; Dibuja 16x16 con XOR

    ; --- Poner atributo blanco en las 2x2 celdas del sprite ---
    LD A, (PlayerYHi)
    AND $F8
    LD D, A
    LD A, (PlayerXHi)
    AND $F8
    LD E, A
    LD A, WHITE | $40           ; Bright blanco
    CALL SetSpriteAttr
    RET

; --- Variables de posicion anterior del player ---
PlayerOldXHi:   DEFB START_PLAYER_X
PlayerOldYHi:   DEFB START_PLAYER_Y
