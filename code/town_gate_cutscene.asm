; ==============================================================================
; town_gate_cutscene.asm - Cutscene final del juego (M9, puerta sur)
; ==============================================================================
; Disparada al chocar contra Town Gate Door Closed (id 240) con TownGateKey.
; Phase machine indexada por TownGatePhase. Cuando != 0, MainLoop salta el
; bloque de gameplay y llama UpdateTownGateCutscene cada frame.
;
; Esquema de fases:
;   1 LOCK         player snap a anchor1 (15,8) facing UP, pausa
;   2 ARM_IN       arm aparece, pausa
;   3 FINGER_IN    finger aparece (instantaneo), entra en SHAKE
;   4 SHAKE        shake 2D random ±1 H/V de arm + finger
;   5 FINGER_PULSE finger quieto antes de erase
;   6 FINGER_OUT   1 frame de gap tras erase
;   7 ARM_HOLD     arm quieto antes de erase
;   8 ARM_OUT      1 frame de gap tras erase
;   9 PLAYER_TURN  player gira a IDLE (mirando jugador)
;  10 PLAYER_HIDE  1 frame con player oculto
;  11 PLAYER_FRAMED player teleport a anchor2 (15,18), enmarcado en puerta
;  12 PLAYER_EXIT  walk-S animado con clip al borde inferior, hasta off-screen
;  13 END_HOLD     "The End" sprite hold
;  14 BLACK        wipe a negro + hold
;  15 CREDITS      pantalla estatica de creditos (loop infinito)
;
; Todos los timings y posiciones via EQU al inicio: ajustables sin tocar
; logica. Hooks SFX por fase como stubs RET, listos para llenar despues.
; ==============================================================================

; --- Timings (frames a 50Hz). Ajustables sin recompilar logica ---
TGCS_T_LOCK            EQU 60      ; Lock + facing UP, pausa breve
TGCS_T_ARM_IN          EQU 30      ; Arm aparece, pausa antes de finger
TGCS_T_FINGER_IN       EQU 1       ; Finger instantaneo, transicion a SHAKE
TGCS_T_SHAKE           EQU 90      ; Shake 2D rabioso
TGCS_T_FINGER_PULSE    EQU 20      ; Finger quieto antes de erase
TGCS_T_ARM_HOLD        EQU 25      ; Arm quieto tras finger erase
TGCS_T_PLAYER_TURN     EQU 50      ; Player IDLE mirando jugador
TGCS_T_PLAYER_FRAMED   EQU 60      ; Player premece en la puerta
TGCS_T_EXIT_STEP       EQU 2       ; Frames entre cada paso de Y++ en slide-out
TGCS_T_END_HOLD        EQU 150     ; "The End" antes de wipe
TGCS_T_BLACK_HOLD      EQU 30      ; Pantalla negra antes de credits

; --- Posiciones (pixel) ---
TGCS_ANCHOR1_X         EQU 120     ; char (15,10)
TGCS_ANCHOR1_Y         EQU 80
TGCS_ANCHOR2_X         EQU 120     ; char (15,20)
TGCS_ANCHOR2_Y         EQU 160
TGCS_END_CHARX         EQU 10      ; "The End" sprite (10,4)
TGCS_END_CHARY         EQU 4
TGCS_PLAYER_BOTTOM_Y   EQU 192     ; phase 12 termina cuando POSY=192 (player rect entero off-screen)

; --- Posiciones de arm + finger (deben coincidir con screen_data PickupTable) ---
; PickupTable los tiene en char (17,6) y (17,5). DrawBgSpriteXOR suma
; BG_Y_OFFSET=2 antes del *8, asi que la pixel Y final renderizada es
; (charY + 2) * 8. Aqui guardamos esa pixel Y final directamente — el
; shake usa DrawBgSpriteAnyXorAtPixel sin offset implicito.
;   arm:    char (17,6) → pixel (136, (6+2)*8 = 64)
;   finger: char (17,5) → pixel (136, (5+2)*8 = 56)
TGCS_ARM_PX_X          EQU 136
TGCS_ARM_PX_Y          EQU 64
TGCS_FINGER_PX_X       EQU 136
TGCS_FINGER_PX_Y       EQU 56

; --- Phase enum ---
TGP_IDLE               EQU 0
TGP_LOCK               EQU 1
TGP_ARM_IN             EQU 2
TGP_FINGER_IN          EQU 3
TGP_SHAKE              EQU 4
TGP_FINGER_PULSE       EQU 5
TGP_FINGER_OUT         EQU 6
TGP_ARM_HOLD           EQU 7
TGP_ARM_OUT            EQU 8
TGP_PLAYER_TURN        EQU 9
TGP_PLAYER_HIDE        EQU 10
TGP_PLAYER_FRAMED      EQU 11
TGP_PLAYER_EXIT        EQU 12
TGP_END_HOLD           EQU 13
TGP_BLACK              EQU 14
TGP_CREDITS            EQU 15

; --- Rect del arco (BG sprite) para el bump-trigger custom ---
; Placement en screen_rooms.asm Room_T7_Y15: DEFB 183, 11, 13 (char x,y).
; DrawScreen suma BG_Y_OFFSET=2 a charY → pixel Y = (13+2)*8 = 120.
; Tamano sprite 88x72 → rect (88-175, 120-191).
TGCS_ARCH_PX_LEFT      EQU 88        ; 11 * 8
TGCS_ARCH_PX_TOP       EQU 120       ; (13 + 2) * 8
TGCS_ARCH_PX_RIGHT     EQU 175       ; 88 + 88 - 1
TGCS_ARCH_PX_BOTTOM    EQU 191       ; 120 + 72 - 1
TGCS_ARCH_TOLERANCE    EQU 4         ; mismo margen que CheckBumpTriggers
TGCS_ARCH_ROOM_X       EQU 7
TGCS_ARCH_ROOM_Y       EQU 15
TGCS_ARCH_KEY_ID       EQU 6         ; TownGateKey

; ==============================================================================
; CheckTownGateTriggerBg - bump-trigger del arco (BG sprite, no en PickupTable)
; ==============================================================================
; Llamado cada frame desde MainLoop tras CheckBumpTriggers. Hace el mismo test
; AABB ±tolerance que CheckBumpTriggers haria si el arco fuese pickup, pero
; con todos los parametros hardcodeados (un unico trigger de este tipo).
;
; Condiciones para disparar: TownGatePhase==0 (no en cutscene), CurrentKey==
; TownGateKey, sala (7,15), AABB del player (16x16) overlapea rect del arco
; extendido +-4 px. HIT → StartTownGateCutscene + CheckMilestoneTrigger(3).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
CheckTownGateTriggerBg:
    LD A, (TownGatePhase)
    OR A
    RET NZ                              ; ya en cutscene
    LD A, (CurrentKey)
    CP TGCS_ARCH_KEY_ID
    RET NZ                              ; sin la key correcta
    LD A, (CurrentScreenX)
    CP TGCS_ARCH_ROOM_X
    RET NZ
    LD A, (CurrentScreenY)
    CP TGCS_ARCH_ROOM_Y
    RET NZ
    ; --- Horizontal AABB ---
    LD A, (EntityTable + ENT_POSX)
    LD C, A                             ; C = player_left
    ADD A, 16
    LD D, A                             ; D = player_right
    LD A, TGCS_ARCH_PX_LEFT
    SUB TGCS_ARCH_TOLERANCE             ; arch_left_ext (con clamp 0)
    JR NC, .ctgtNoUnderL
    XOR A
.ctgtNoUnderL:
    CP D
    RET NC                              ; ext_left >= player_right
    LD A, TGCS_ARCH_PX_RIGHT
    ADD A, TGCS_ARCH_TOLERANCE          ; arch_right_ext (con clamp 255)
    JR NC, .ctgtNoOverR
    LD A, $FF
.ctgtNoOverR:
    CP C
    RET C                               ; ext_right < player_left
    ; --- Vertical AABB ---
    ; OJO: el rect de colision del player es 16x21 (Y+0..Y+20, ver puntos
    ; inferiores en logic_game.asm IsPointBlocked sobre el player). Usar +16
    ; aqui dejaria un gap de 4-5 px frente al borde del arco al chocar desde
    ; el norte (no dispararia el trigger). Por eso usamos +21 para coincidir
    ; con la altura real del rect.
    LD A, (EntityTable + ENT_POSY)
    LD C, A                             ; C = player_top
    ADD A, 21
    LD D, A                             ; D = player_bottom (excl, rect real 21px)
    LD A, TGCS_ARCH_PX_TOP
    SUB TGCS_ARCH_TOLERANCE
    JR NC, .ctgtNoUnderT
    XOR A
.ctgtNoUnderT:
    CP D
    RET NC
    LD A, TGCS_ARCH_PX_BOTTOM
    ADD A, TGCS_ARCH_TOLERANCE
    JR NC, .ctgtNoOverB
    LD A, $FF
.ctgtNoOverB:
    CP C
    RET C
    ; HIT
    CALL StartTownGateCutscene
    LD A, 3                             ; action 3 = TownGate (avance M9)
    JP CheckMilestoneTrigger            ; tail call

; ==============================================================================
; TownGateWipeAllEnemies - erase XOR + clear de nastys/monsters/death
; ==============================================================================
; Itera slots 1..NUM_ENTITIES-1 (slot 0 = player, lo dejamos). Para cada
; entidad activa que NO sea TYPE_OBJECT/PLAYER: erase via OldSprite XOR +
; RestoreOldAttr + TYPE_NONE. Igual al pattern de despawn limpio en
; .peScaredDespawn de logic_game.asm.
;
; Llamado desde StartTownGateCutscene antes del snap del player. Asi el
; mundo queda en silencio durante el cutscene final, sin enemigos
; congelados (skip de ProcessEnemies durante cutscene los dejaria pintados
; en su ultima posicion para siempre).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
TownGateWipeAllEnemies:
    LD IX, EntityTable + ENT_SIZE       ; slot 1 (skip player)
    LD B, NUM_ENTITIES - 1
.tgwaeLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .tgwaeNext                    ; TYPE_NONE: nada que borrar
    CP TYPE_OBJECT
    JR Z, .tgwaeNext                    ; objetos coleccionables: respetar
    CP TYPE_PLAYER
    JR Z, .tgwaeNext                    ; (defensivo)
    PUSH BC                             ; preservar B (loop counter)
    PUSH IX                             ; preservar slot ptr
    CALL GetOldSpriteAddr               ; OldSprAddr setado, IX intacto
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    LD IX, (OldSprAddr)
    CALL DrawSprite                     ; XOR erase
    POP IX                              ; recuperar slot ptr
    LD D, (IX+ENT_OLDY)
    LD E, (IX+ENT_OLDX)
    CALL RestoreOldAttr                 ; restaurar attrs del fondo
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), STATE_IDLE
    POP BC
.tgwaeNext:
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .tgwaeLoop
    ; Limpiar tambien la cola de pending erases para que EraseDeadSprites
    ; no intente procesar slots que ya hemos borrado (frame en curso).
    XOR A
    LD (PendingEraseCount), A
    RET

; ==============================================================================
; StartTownGateCutscene - llamada desde el handler del bump-trigger action 3
; ==============================================================================
; Wipe enemigos (silencio dramatico) + snap player a anchor1 mirando UP.
; Set TownGatePhase=1 + TownGateTimer=TGCS_T_LOCK. Consume la TownGateKey.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
StartTownGateCutscene:
    XOR A
    LD (CurrentKey), A
    CALL TownGateWipeAllEnemies
    ; Erase player en su posicion actual (XOR redraw del sprite viejo)
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
    ; Snap player a anchor1, sprite WALK_N
    LD A, TGCS_ANCHOR1_X
    LD (IX+ENT_POSX), A
    LD (IX+ENT_DRAWX), A
    LD A, TGCS_ANCHOR1_Y
    LD (IX+ENT_POSY), A
    LD (PlayerDrawY), A
    LD A, SPRID_WALK_N
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    ; Draw player en su nueva pose + attrs
    CALL TownGateDrawPlayerHere
    CALL SFX_TownGate_OnStart
    LD A, TGP_LOCK
    LD (TownGatePhase), A
    LD A, TGCS_T_LOCK
    LD (TownGateTimer), A
    RET

; ==============================================================================
; UpdateTownGateCutscene - llamada cada frame desde MainLoop si phase != 0
; ==============================================================================
; Dispatch por TownGatePhase. Cada fase: trabajo de tick, decremento timer,
; transicion a la siguiente.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
UpdateTownGateCutscene:
    LD A, (TownGatePhase)
    DEC A
    JP Z, .tgPhLock
    DEC A
    JP Z, .tgPhArmIn
    DEC A
    JP Z, .tgPhFingerIn
    DEC A
    JP Z, .tgPhShake
    DEC A
    JP Z, .tgPhFingerPulse
    DEC A
    JP Z, .tgPhFingerOut
    DEC A
    JP Z, .tgPhArmHold
    DEC A
    JP Z, .tgPhArmOut
    DEC A
    JP Z, .tgPhPlayerTurn
    DEC A
    JP Z, .tgPhPlayerHide
    DEC A
    JP Z, .tgPhPlayerFramed
    DEC A
    JP Z, .tgPhPlayerExit
    DEC A
    JP Z, .tgPhEndHold
    DEC A
    JP Z, .tgPhBlack
    ; TGP_CREDITS o cualquier valor mayor: loop infinito, no-op.
    RET

; ---- Phase 1: lock + facing UP ----
.tgPhLock:
    CALL TownGateDecTimer
    RET NZ
    LD DE, BgGfx_arm
    CALL RedrawPickupByPtr
    CALL SFX_TownGate_OnArmIn
    LD A, TGCS_T_ARM_IN
    LD (TownGateTimer), A
    LD A, TGP_ARM_IN
    LD (TownGatePhase), A
    RET

; ---- Phase 2: arm visible, pausa antes de finger ----
.tgPhArmIn:
    CALL TownGateDecTimer
    RET NZ
    LD DE, BgGfx_finger
    CALL RedrawPickupByPtr
    CALL SFX_TownGate_OnFingerIn
    LD A, TGCS_T_FINGER_IN
    LD (TownGateTimer), A
    LD A, TGP_FINGER_IN
    LD (TownGatePhase), A
    RET

; ---- Phase 3: finger visible, transicion a SHAKE ----
.tgPhFingerIn:
    CALL TownGateDecTimer
    RET NZ
    XOR A
    LD (TownGateShakeOffsX), A
    LD (TownGateShakeOffsY), A
    CALL SFX_TownGate_OnShake
    LD A, TGCS_T_SHAKE
    LD (TownGateTimer), A
    LD A, TGP_SHAKE
    LD (TownGatePhase), A
    RET

; ---- Phase 4: shake 2D ±1 H/V ----
.tgPhShake:
    CALL TownGateShakeStep
    CALL TownGateDecTimer
    RET NZ
    ; Restaurar arm + finger a la posicion original (erase shifted + redraw aligned)
    CALL TownGateShakeRestore
    CALL SFX_TownGate_OnFingerPulse
    LD A, TGCS_T_FINGER_PULSE
    LD (TownGateTimer), A
    LD A, TGP_FINGER_PULSE
    LD (TownGatePhase), A
    RET

; ---- Phase 5: finger quieto antes de erase ----
.tgPhFingerPulse:
    CALL TownGateDecTimer
    RET NZ
    LD DE, BgGfx_finger
    CALL RedrawPickupByPtr              ; XOR self-cancel = erase
    CALL SFX_TownGate_OnFingerOut
    LD A, 1
    LD (TownGateTimer), A
    LD A, TGP_FINGER_OUT
    LD (TownGatePhase), A
    RET

; ---- Phase 6: 1 frame de gap tras finger erase ----
.tgPhFingerOut:
    CALL TownGateDecTimer
    RET NZ
    LD A, TGCS_T_ARM_HOLD
    LD (TownGateTimer), A
    LD A, TGP_ARM_HOLD
    LD (TownGatePhase), A
    RET

; ---- Phase 7: arm quieto antes de erase ----
.tgPhArmHold:
    CALL TownGateDecTimer
    RET NZ
    LD DE, BgGfx_arm
    CALL RedrawPickupByPtr              ; XOR self-cancel = erase
    CALL SFX_TownGate_OnArmOut
    LD A, 1
    LD (TownGateTimer), A
    LD A, TGP_ARM_OUT
    LD (TownGatePhase), A
    RET

; ---- Phase 8: 1 frame de gap tras arm erase ----
.tgPhArmOut:
    CALL TownGateDecTimer
    RET NZ
    ; Player gira a IDLE (mirando jugador, sprite al sur)
    LD IX, EntityTable
    LD A, SPRID_IDLE
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    CALL TownGateRedrawPlayer
    CALL SFX_TownGate_OnPlayerTurn
    LD A, TGCS_T_PLAYER_TURN
    LD (TownGateTimer), A
    LD A, TGP_PLAYER_TURN
    LD (TownGatePhase), A
    RET

; ---- Phase 9: player IDLE mirando jugador ----
.tgPhPlayerTurn:
    CALL TownGateDecTimer
    RET NZ
    ; Erase player en anchor1 (XOR del sprite actual via OLDX/OLDY)
    CALL TownGateErasePlayer
    LD A, 1
    LD (TownGateTimer), A
    LD A, TGP_PLAYER_HIDE
    LD (TownGatePhase), A
    RET

; ---- Phase 10: 1 frame con player oculto ----
.tgPhPlayerHide:
    CALL TownGateDecTimer
    RET NZ
    ; Erase puerta cerrada → revela puerta abierta del fondo
    CALL TownGateEraseDoor
    ; Snap player a anchor2 + sprite WALK_S + draw
    LD IX, EntityTable
    LD A, TGCS_ANCHOR2_X
    LD (IX+ENT_POSX), A
    LD (IX+ENT_DRAWX), A
    LD A, TGCS_ANCHOR2_Y
    LD (IX+ENT_POSY), A
    LD (PlayerDrawY), A
    LD A, SPRID_WALK_S
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    CALL TownGateDrawPlayerHere
    CALL SFX_TownGate_OnPlayerFramed
    LD A, TGCS_T_PLAYER_FRAMED
    LD (TownGateTimer), A
    LD A, TGP_PLAYER_FRAMED
    LD (TownGatePhase), A
    RET

; ---- Phase 11: player enmarcado en la puerta abierta ----
.tgPhPlayerFramed:
    CALL TownGateDecTimer
    RET NZ
    XOR A
    LD (TownGateExitStepCnt), A
    LD A, 1
    LD (TownGateExitWalkFrame), A
    CALL SFX_TownGate_OnPlayerExit
    LD A, TGP_PLAYER_EXIT
    LD (TownGatePhase), A
    RET

; ---- Phase 12: walk-S con slide-out ----
.tgPhPlayerExit:
    CALL TownGateExitStep
    LD IX, EntityTable
    LD A, (IX+ENT_POSY)
    CP TGCS_PLAYER_BOTTOM_Y
    RET C                               ; sigue visible (Y < 168)
    ; Player completamente off-screen. Dibujar "The End" sprite.
    CALL TownGateDrawTheEnd
    CALL SFX_TownGate_OnTheEnd
    LD A, TGCS_T_END_HOLD
    LD (TownGateTimer), A
    LD A, TGP_END_HOLD
    LD (TownGatePhase), A
    RET

; ---- Phase 13: "The End" hold ----
.tgPhEndHold:
    CALL TownGateDecTimer
    RET NZ
    CALL TownGateWipeBlack
    LD A, TGCS_T_BLACK_HOLD
    LD (TownGateTimer), A
    LD A, TGP_BLACK
    LD (TownGatePhase), A
    RET

; ---- Phase 14: pantalla negra hold ----
.tgPhBlack:
    CALL TownGateDecTimer
    RET NZ
    CALL TownGateDrawCredits
    CALL SFX_TownGate_OnCredits
    LD A, TGP_CREDITS
    LD (TownGatePhase), A
    RET

; ==============================================================================
; TownGateDecTimer - decrementa TownGateTimer, devuelve Z si llego a 0
; ==============================================================================
TownGateDecTimer:
    LD A, (TownGateTimer)
    DEC A
    LD (TownGateTimer), A
    OR A
    RET

; ==============================================================================
; TownGateDrawPlayerHere - draw + attrs del player en (DRAWX, PlayerDrawY)
; ==============================================================================
; Asume IX = EntityTable. Pinta sprite + attrs y guarda OLDX/OLDY/OLDSPRID.
; Destruye: AF, BC, DE, HL.
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
    ; Attrs
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
    ; Save old = current
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (PlayerDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

; ==============================================================================
; TownGateRedrawPlayer - erase old + draw new (cambio de sprite/posicion)
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
; TownGateEraseDoor - XOR-erase de la puerta cerrada (id 240)
; ==============================================================================
; La puerta esta en PickupTable; RedrawPickupByPtr llamado dos veces no
; sirve (no es idempotente: solo dibuja). Cargamos sprite y XOR-redraw a su
; posicion. Como ya estaba dibujada, XOR self-cancel = erase.
; ==============================================================================
TownGateEraseDoor:
    LD DE, BgGfx_town_gate_door_closed
    JP RedrawPickupByPtr

; ==============================================================================
; TownGateShakeStep - shake 2D random ±1 H/V de arm + finger
; ==============================================================================
; 1. Erase last drawn (XOR draw en TownGateShakeOffsX/Y actuales).
;    Primera iteracion: offsets son (0,0), erase a la posicion exacta donde
;    los dibujo RedrawPickupByPtr en phases 2/3 (XOR self-cancel).
; 2. Compute new offset random.
; 3. Draw at new offset.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
TownGateShakeStep:
    CALL TownGateDrawArmShifted          ; erase last (XOR cancel)
    CALL TownGateDrawFingerShifted
    ; Compute new offsets via R y GameFrameCounter (lookup en .tgssJitterTable)
    LD A, R
    AND $03
    LD HL, .tgssJitterTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (TownGateShakeOffsX), A
    LD A, (GameFrameCounter)
    AND $03
    LD HL, .tgssJitterTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD (TownGateShakeOffsY), A
    CALL TownGateDrawArmShifted          ; draw at new offset
    JP TownGateDrawFingerShifted
.tgssJitterTable:
    DEFB 0, $FF, 0, 1                    ; map(R&3) -> {0, -1, 0, +1}

; ==============================================================================
; TownGateShakeRestore - cierra SHAKE: erase last shifted + redraw aligned
; ==============================================================================
; Garantiza que arm/finger queden en su posicion char-aligned exacta
; (la de RedrawPickupByPtr) para las fases siguientes (finger pulse, erases).
; ==============================================================================
TownGateShakeRestore:
    CALL TownGateDrawArmShifted          ; erase last shifted
    CALL TownGateDrawFingerShifted
    XOR A
    LD (TownGateShakeOffsX), A
    LD (TownGateShakeOffsY), A
    LD DE, BgGfx_arm
    CALL RedrawPickupByPtr               ; restore at PickupTable position
    LD DE, BgGfx_finger
    JP RedrawPickupByPtr

; ==============================================================================
; TownGateDrawArmShifted - XOR draw del arm en (TGCS_ARM_PX_X+offX, +offY)
; ==============================================================================
; Carga sprite al BgSpriteBuffer + DrawBgSpriteAnyXorAtPixel.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
TownGateDrawArmShifted:
    LD HL, BgGfx_arm
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD A, (TownGateShakeOffsX)
    LD B, A
    LD A, TGCS_ARM_PX_X
    ADD A, B
    LD E, A
    LD A, (TownGateShakeOffsY)
    LD B, A
    LD A, TGCS_ARM_PX_Y                 ; ya es pixel Y final, sin BG offset
    ADD A, B
    LD D, A
    JP DrawBgSpriteAnyXorAtPixel

; ==============================================================================
; TownGateDrawFingerShifted - XOR draw del finger en (TGCS_FINGER_PX_X+offX, +offY)
; ==============================================================================
TownGateDrawFingerShifted:
    LD HL, BgGfx_finger
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD A, (TownGateShakeOffsX)
    LD B, A
    LD A, TGCS_FINGER_PX_X
    ADD A, B
    LD E, A
    LD A, (TownGateShakeOffsY)
    LD B, A
    LD A, TGCS_FINGER_PX_Y              ; ya es pixel Y final, sin BG offset
    ADD A, B
    LD D, A
    JP DrawBgSpriteAnyXorAtPixel

; ==============================================================================
; DrawBgSpriteAnyXorAtPixel - generaliza DrawBgSprite16XorAtPixel a N bytes
; ==============================================================================
; IN: BgSpriteBuffer pre-cargado (header height/width + pixel data CPL'd).
;     D = pixel Y (0..191, no aplica BG_Y_OFFSET — el caller suma si aplica).
;     E = pixel X (0..255).
; XOR de pixels (no toca attrs). Soporta width 1..N bytes.
; Para shift > 0 escribe (width+1) bytes por scan line; para shift = 0 escribe
; width bytes. Igual que DrawBgSprite16XorAtPixel pero con loop por width.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
DrawBgSpriteAnyXorAtPixel:
    LD IX, BgSpriteBuffer
    LD A, (IX+0)                        ; height_px
    OR A
    RET Z
    LD (.dbsaHeight), A
    LD A, (IX+1)                        ; width_bytes (bit 7 RLE → ignorar)
    AND $7F
    LD (.dbsaWidth), A
    INC IX
    INC IX                              ; -> pixel data
    LD A, E
    AND $07
    LD (.dbsaShift), A
    LD A, E
    AND $F8
    LD E, A
    CALL CalcPixelAddr                  ; HL = VRAM addr
.dbsaRow:
    PUSH HL
    LD A, (.dbsaWidth)
    LD B, A                             ; B = width counter
    LD C, 0                             ; C = carry from prev byte
.dbsaByte:
    LD A, (IX+0)
    CPL                                 ; un-invert
    LD D, A                             ; D = sprite byte
    LD E, 0                             ; E = bits que caen al next byte
    LD A, (.dbsaShift)
    OR A
    JR Z, .dbsaNoShift
    PUSH BC
    LD B, A
.dbsaShiftLoop:
    SRL D
    RR E
    DJNZ .dbsaShiftLoop
    POP BC
.dbsaNoShift:
    LD A, D
    OR C                                ; combinar con carry previo
    XOR (HL)
    LD (HL), A
    INC HL
    LD C, E                             ; nuevo carry para siguiente byte
    INC IX
    DJNZ .dbsaByte
    ; Byte final (carry) si shift > 0
    LD A, (.dbsaShift)
    OR A
    JR Z, .dbsaNoFinal
    LD A, C
    XOR (HL)
    LD (HL), A
.dbsaNoFinal:
    POP HL
    CALL NextPixelLine
    LD A, (.dbsaHeight)
    DEC A
    LD (.dbsaHeight), A
    JR NZ, .dbsaRow
    RET
.dbsaHeight: DEFB 0
.dbsaWidth:  DEFB 0
.dbsaShift:  DEFB 0

; ==============================================================================
; TownGateExitStep - 1 step del slide-out. Cada TGCS_T_EXIT_STEP frames
; ==============================================================================
; avanza POSY +1 y alterna animacion de WALK_S. Dibujo via DrawSprite que
; clipea a 192 internamente. La parte que cae en HUD (rows 22-23) se ve
; sobreescrita por DrawClockHUD/DrawKeyHUD/etc en el mismo frame, asi que
; visualmente la mitad inferior del player desaparece tras la HUD.
; ==============================================================================
TownGateExitStep:
    LD A, (TownGateExitStepCnt)
    INC A
    LD (TownGateExitStepCnt), A
    CP TGCS_T_EXIT_STEP
    RET C                               ; aun no toca step
    XOR A
    LD (TownGateExitStepCnt), A
    ; Avanzar POSY +1, alternar frame WALK_S (toggle base+0 / base+1)
    LD IX, EntityTable
    LD A, (IX+ENT_POSY)
    INC A
    LD (IX+ENT_POSY), A
    LD (PlayerDrawY), A
    LD A, (TownGateExitWalkFrame)
    XOR 1                               ; toggle 0/1
    LD (TownGateExitWalkFrame), A
    LD B, A
    LD A, SPRID_WALK_S
    ADD A, B
    LD (IX+ENT_SPRITEID), A
    JP TownGateRedrawPlayer

; ==============================================================================
; TownGateDrawTheEnd - dibuja el sprite "The End" (placeholder id 183) en (10,4)
; ==============================================================================
; Usa DrawBgGfxSprite (path normal de pickups + chars). Bank 3 para id 183.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
TownGateDrawTheEnd:
    LD HL, BgGfx_town_gate              ; id 183 = placeholder "The End"
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    LD B, TGCS_END_CHARX
    LD C, TGCS_END_CHARY
    PUSH BC
    CALL DrawBgSpriteXOR
    POP BC
    LD IX, BgSpriteBuffer
    XOR A
    LD (BgSpriteIsHouse), A
    JP DrawBgAttrOnly

; ==============================================================================
; TownGateWipeBlack - rellena VRAM (pixels + attrs) con 0
; ==============================================================================
; LDIR a $4000-$57FF (pixels) y $5800-$5AFF (attrs) con 0. Tras esto, el
; HUD se redibujara (DrawClockHUD etc se llaman cada frame en MainLoop) y
; quedara visible sobre fondo negro.
; ==============================================================================
TownGateWipeBlack:
    LD HL, $4000
    LD DE, $4001
    LD BC, $17FF
    LD (HL), 0
    LDIR
    LD HL, $5800
    LD DE, $5801
    LD BC, $02FF
    LD (HL), $00                        ; ink black, paper black
    LDIR
    RET

; ==============================================================================
; TownGateDrawCredits - renderiza la pantalla estatica de creditos
; ==============================================================================
; Itera TownGateCreditsData: cada entry es {row, col, "texto", 0}, terminada
; en $FF. Imprime via PrintStringFontAt. Attrs en $5800+ se dejan a $47
; (white ink, black paper, bright) para todo el area de texto.
; ==============================================================================
TownGateDrawCredits:
    ; Pintar attrs $5800-$5AFF con $47 (white ink, black paper, bright)
    LD HL, $5800
    LD DE, $5801
    LD BC, $02FF
    LD (HL), $47
    LDIR
    ; Iterar credits
    LD HL, TownGateCreditsData
.tgdcLoop:
    LD A, (HL)
    CP $FF
    RET Z
    LD D, A                             ; D = row
    INC HL
    LD A, (HL)
    LD E, A                             ; E = col
    INC HL                              ; HL → string
    CALL PrintStringFontAt
    JR .tgdcLoop                        ; HL ya avanzado tras el 0

; ==============================================================================
; PrintStringFontAt - imprime cadena ASCII (terminada en 0) en (D=row, E=col)
; ==============================================================================
; Usa font del ROM en $3C00 (ASCII * 8 = 8 bytes por char). Avanza HL al
; siguiente byte tras el 0 (para que el caller siga iterando).
; Destruye: AF, BC, DE, HL.
; OUT: HL apunta al byte tras el 0 terminador.
; ==============================================================================
PrintStringFontAt:
.psfaCharLoop:
    LD A, (HL)
    INC HL
    OR A
    RET Z                               ; fin de string
    PUSH HL
    PUSH DE
    CALL DrawCharFontAt                 ; D=row, E=col, A=char
    POP DE
    POP HL
    INC E                               ; siguiente columna
    JR .psfaCharLoop

; ==============================================================================
; DrawCharFontAt - dibuja un char ASCII en (D=row, E=col) usando font ROM
; ==============================================================================
; D = row (0..23), E = col (0..31), A = ASCII char.
; Calcula VRAM addr para (row, col) usando el formato Spectrum:
;   y = row * 8, x = col * 8
;   pixelAddr = $4000 + (third * $0800) + (charRow_in_third * $20) + (col)
; El char se renderiza con direct write (sobrescribe pixels y attr).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
DrawCharFontAt:
    PUSH DE
    ; HL = $3C00 + char * 8
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, $3C00
    ADD HL, BC
    POP DE
    ; Calcular VRAM addr para (row, col) char-aligned: y = row*8
    PUSH HL                             ; save font ptr
    LD A, D
    ADD A, A
    ADD A, A
    ADD A, A                            ; A = row * 8 = pixel Y
    LD D, A
    LD A, E
    ADD A, A
    ADD A, A
    ADD A, A                            ; A = col * 8 = pixel X
    LD E, A
    CALL CalcPixelAddr                  ; HL = VRAM addr
    EX DE, HL                           ; DE = VRAM addr
    POP HL                              ; HL = font ptr
    LD B, 8
.dcfaLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                               ; siguiente scan line (within char)
    DJNZ .dcfaLoop
    RET

; ==============================================================================
; SFX hooks por fase. Stubs RET. Llenar despues sin tocar logica.
; ==============================================================================
SFX_TownGate_OnStart:           RET
SFX_TownGate_OnArmIn:           RET
SFX_TownGate_OnFingerIn:        RET
SFX_TownGate_OnShake:           RET
SFX_TownGate_OnFingerPulse:     RET
SFX_TownGate_OnFingerOut:       RET
SFX_TownGate_OnArmOut:          RET
SFX_TownGate_OnPlayerTurn:      RET
SFX_TownGate_OnPlayerFramed:    RET
SFX_TownGate_OnPlayerExit:      RET
SFX_TownGate_OnTheEnd:          RET
SFX_TownGate_OnCredits:         RET

; ==============================================================================
; TownGateCreditsData - Placeholder. Formato {row, col, "texto", 0}, terminator $FF
; ==============================================================================
TownGateCreditsData:
    DEFB 4, 10
    DEFM "JUEGO TITULO", 0
    DEFB 7, 8
    DEFM "DESIGN AND CODE", 0
    DEFB 8, 11
    DEFM "JJ MORENO", 0
    DEFB 11, 12
    DEFM "GRAPHICS", 0
    DEFB 12, 11
    DEFM "JJ MORENO", 0
    DEFB 15, 13
    DEFM "MUSIC", 0
    DEFB 16, 14
    DEFM "---", 0
    DEFB 19, 9
    DEFM "SPECIAL THANKS", 0
    DEFB 22, 12
    DEFM "THE END", 0
    DEFB $FF
