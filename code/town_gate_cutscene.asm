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
TGCS_T_SHAKE           EQU 40      ; Shake 2D rabioso (~1.6s a 25 Hz; antes 90 = 3.6s)
TGCS_T_FINGER_PULSE    EQU 20      ; Finger quieto antes de erase
TGCS_T_ARM_HOLD        EQU 25      ; Arm quieto tras finger erase
TGCS_T_PLAYER_TURN     EQU 50      ; Player IDLE mirando jugador
TGCS_T_EXIT_STEP       EQU 2       ; Frames entre cada paso de Y++ en slide-out
TGCS_T_END_HOLD        EQU 150     ; "The End" antes de wipe
TGCS_T_BLACK_HOLD      EQU 30      ; Pantalla negra antes de credits

; --- Posiciones (pixel) ---
TGCS_ANCHOR1_X         EQU 120     ; char (15,10) — destino del walk + lock
TGCS_ANCHOR1_Y         EQU 80
TGCS_END_CHARX         EQU 11      ; "The End" sprite (11,4)
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
TGP_WAIT_NASTIES       EQU 16     ; pre-LOCK wait para que terminen puffs
TGP_WALK_TO_ANCHOR     EQU 17     ; walk autonomo desde bump pos hasta anchor1

TGCS_T_PUFF_WAIT       EQU 100    ; safety timeout. La transicion real es por
                                  ; check dinamico de "todos los nasties dead".
                                  ; ProcessEnemies hace 2 slots/frame; con 4
                                  ; nasties + 3 monsters + 1 death = 8 slots,
                                  ; cada puff tarda ~50 frames. 100 = margen.

; Walk autonomo a anchor1 (post WAIT_NASTIES, pre LOCK)
TGCS_WALK_TARGET_X     EQU TGCS_ANCHOR1_X    ; 120
TGCS_WALK_TARGET_Y     EQU TGCS_ANCHOR1_Y    ; 80
TGCS_WALK_ANIM_PERIOD  EQU 4                 ; toggle anim frame cada N game frames

; --- Rect del PART1 del arco (lintel + arco superior) para el bump-trigger ---
; El arco ahora esta partido en 3 sprites: part1 (lintel/arco superior),
; part2 (pilar izq), part3 (pilar der). Trigger solo dispara con part1.
; Placement: DEFB 247, 10, 13 → pixel (10*8, (13+2)*8) = (80, 120).
; Tamano part1 96x32 (12x4 chars) → rect (80-175, 120-151).
;
; Tambien usado para el redraw on-top-of-player durante el slide-down:
; mientras el player overlapea verticalmente con part1 (POSY <= 151), part1
; se re-pinta encima cada step → player visualmente "detras" del lintel.
TGCS_ARCH_PX_LEFT      EQU 80        ; 10 * 8
TGCS_ARCH_PX_TOP       EQU 120       ; (13 + 2) * 8
TGCS_ARCH_PX_RIGHT     EQU 175       ; 80 + 96 - 1
TGCS_ARCH_PX_BOTTOM    EQU 151       ; 120 + 32 - 1

; --- Posicion de la puerta (closed v2 + open) en char ---
; El closed v2 (id 246) vive en PickupTable a (14, 17). El open (id 250)
; comparte posicion y tamano (4x5 chars). Cuando el cutscene erase el closed,
; dibuja el open in-place via DrawBgGfxSprite.
TGCS_DOOR_CHARX        EQU 14
TGCS_DOOR_CHARY        EQU 17
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
; StartTownGateCutscene - llamada desde el handler del bump-trigger action 3
; ==============================================================================
; 1. Consume key, abre puerta, KillAllActiveNasties (puff anim).
; 2. Player se queda en su posicion de bump (no snap a anchor1 todavia).
; 3. Entra en TGP_WAIT_NASTIES. Cuando todos los nasties hayan muerto
;    (check dinamico), transicion a TGP_WALK_TO_ANCHOR donde el player
;    camina autonomamente desde bump pos hasta anchor1 con anim correcta.
;    Tras llegar, transicion a TGP_LOCK (gesto rabia).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
StartTownGateCutscene:
    XOR A
    LD (CurrentKey), A
    CALL TownGateOpenDoor               ; closed v2 → open al disparar trigger
    CALL KillAllActiveNasties           ; nasties → puff (animan en WAIT_NASTIES)
    CALL SFX_TownGate_OnStart
    LD A, TGP_WAIT_NASTIES
    LD (TownGatePhase), A
    LD A, TGCS_T_PUFF_WAIT
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
    CP TGP_WAIT_NASTIES
    JP Z, .tgPhWaitNasties              ; pre-LOCK wait, ProcessEnemies sigue corriendo
    CP TGP_WALK_TO_ANCHOR
    JP Z, .tgPhWalkToAnchor              ; player camina autonomo a anchor1
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
    DEC A                               ; phase 10 (PLAYER_HIDE) deprecated
    DEC A                               ; phase 11 (PLAYER_FRAMED) deprecated
    DEC A
    JP Z, .tgPhPlayerExit
    DEC A
    JP Z, .tgPhEndHold
    DEC A
    JP Z, .tgPhBlack
    ; TGP_CREDITS o cualquier valor mayor: loop infinito, no-op.
    RET

; ---- Phase WAIT_NASTIES: espera a que terminen los puffs antes de WALK ----
; ProcessEnemies sigue corriendo en MainLoop (rama especial) → cada nasty
; STATE_DYING avanza su anim puff y queda TYPE_NONE al terminar. Cuando
; todos muertos (check dinamico), transicion a WALK_TO_ANCHOR.
.tgPhWaitNasties:
    CALL TownGateAllNastiesDeadCheck
    JR Z, .tgWaitNastiesDone
    CALL TownGateDecTimer               ; safety timeout
    RET NZ
.tgWaitNastiesDone:
    XOR A
    LD (TownGateExitWalkFrame), A       ; reset toggle anim 0/1
    LD (TownGateTimer), A               ; reuse Timer como contador anim period
    LD A, TGP_WALK_TO_ANCHOR
    LD (TownGatePhase), A
    RET

; ---- Phase WALK_TO_ANCHOR: player camina autonomo en 2 fases ----
; Fase 1: movimiento vertical hasta alinear Y con TGCS_WALK_TARGET_Y
;         (sprite WALK_N o WALK_S segun direccion).
; Fase 2: movimiento horizontal hasta alinear X con TGCS_WALK_TARGET_X
;         (sprite WALK_E o WALK_W segun direccion).
; Al llegar (ambos ejes alineados): pose static WALK_N+1 + transicion a LOCK.
; Toggle frame anim 0/1 cada TGCS_WALK_ANIM_PERIOD frames.
.tgPhWalkToAnchor:
    LD IX, EntityTable
    ; --- Fase 1: Y ---
    LD A, (IX+ENT_POSY)
    CP TGCS_WALK_TARGET_Y
    JR Z, .tgwtaTryX                    ; Y aligned, pasar a fase 2
    JR C, .tgwtaMoveS                   ; cur_Y < target → S (Y++)
    ; cur_Y > target → N (Y--)
    DEC (IX+ENT_POSY)
    LD A, (IX+ENT_POSY)
    LD (PlayerDrawY), A
    LD B, SPRID_WALK_N
    JR .tgwtaApplyAnim
.tgwtaMoveS:
    INC (IX+ENT_POSY)
    LD A, (IX+ENT_POSY)
    LD (PlayerDrawY), A
    LD B, SPRID_WALK_S
    JR .tgwtaApplyAnim
    ; --- Fase 2: X (solo si Y ya aligned) ---
.tgwtaTryX:
    LD A, (IX+ENT_POSX)
    CP TGCS_WALK_TARGET_X
    JP Z, .tgwtaArrived                 ; ambos aligned
    JR C, .tgwtaMoveE                   ; cur_X < target → E (X++)
    DEC (IX+ENT_POSX)
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_DRAWX), A
    LD B, SPRID_WALK_W
    JR .tgwtaApplyAnim
.tgwtaMoveE:
    INC (IX+ENT_POSX)
    LD A, (IX+ENT_POSX)
    LD (IX+ENT_DRAWX), A
    LD B, SPRID_WALK_E
.tgwtaApplyAnim:
    ; B = sprite base. Toggle frame 0/1 cada TGCS_WALK_ANIM_PERIOD.
    LD A, (TownGateTimer)
    INC A
    LD (TownGateTimer), A
    CP TGCS_WALK_ANIM_PERIOD
    JR C, .tgwtaSameFrame
    XOR A
    LD (TownGateTimer), A
    LD A, (TownGateExitWalkFrame)
    XOR 1
    LD (TownGateExitWalkFrame), A
.tgwtaSameFrame:
    LD A, (TownGateExitWalkFrame)
    ADD A, B
    LD (IX+ENT_SPRITEID), A
    JP TownGateRedrawPlayer             ; tail call

.tgwtaArrived:
    ; Llegado a anchor1: pose static WALK_N+1 + transicion a LOCK.
    LD A, SPRID_WALK_N + 1              ; frame 2o de Walk North (mirando arriba)
    LD (IX+ENT_SPRITEID), A
    LD A, SPRID_WALK_N
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    CALL TownGateRedrawPlayer
    LD A, TGCS_T_LOCK
    LD (TownGateTimer), A
    LD A, TGP_LOCK
    LD (TownGatePhase), A
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

; ---- Phase 9: player IDLE mirando jugador, luego inicia walk-down ----
; Sin teleport ni anchor2: cambia sprite a WALK_S in-place y entra directo
; en PLAYER_EXIT desde anchor1. Tras el redraw final del IDLE→WALK_S,
; ejecuta RestoreOldAttr en anchor1 para limpiar los player attrs (porque
; el slide-down ya no los va a re-pintar — usa clipped XOR sin attrs).
; Phases 10 (PLAYER_HIDE) y 11 (PLAYER_FRAMED) quedan dead-code.
.tgPhPlayerTurn:
    CALL TownGateDecTimer
    RET NZ
    LD IX, EntityTable
    LD A, SPRID_WALK_S
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    LD (TownGateExitStepCnt), A
    LD A, 1
    LD (TownGateExitWalkFrame), A
    CALL TownGateRedrawPlayer           ; turn IDLE → WALK_S + paint attrs anchor1
    LD IX, EntityTable
    LD D, (IX+ENT_OLDY)                 ; anchor1 Y (= POSY tras redraw)
    LD E, (IX+ENT_OLDX)
    CALL RestoreOldAttr                 ; clear player attrs en anchor1
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
; TownGateOpenDoor - erase puerta cerrada v2 (id 246) + dibuja open (id 250)
; ==============================================================================
; 1. Erase del closed v2 (in PickupTable) via RedrawPickupByPtr (XOR self-cancel
;    al haberse dibujado ya en el render normal de la sala).
; 2. Direct-write del open (NO en PickupTable, hardcodeado en char 14,17) via
;    DrawBgGfxSprite (que decodifica RLE + pinta attrs).
; Bank 3 para ambos (sprites baseline town).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
TownGateOpenDoor:
    LD DE, BgGfx_town_gate_door_closed_v2
    CALL RedrawPickupByPtr               ; XOR-erase del closed
    ; Fall-through a TownGateRedrawOpenDoor

; ==============================================================================
; TownGateRedrawOpenDoor - direct-write del open door en (14, 17)
; ==============================================================================
; Usado al final del slide-out: el player paint sus attrs sobre cols 14-16, y
; RestoreOldAttr restaura desde CleanAttrMap (no desde el door). Re-emitir
; el open door restaura attrs originales en sus 4 cols + pixels.
; ==============================================================================
TownGateRedrawOpenDoor:
    LD HL, BgGfx_town_gate_door_open
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    LD B, TGCS_DOOR_CHARX
    LD C, TGCS_DOOR_CHARY
    XOR A
    LD (BgSpriteIsHouse), A
    LD (CurrentTintVar), A
    JP DrawBgGfxSprite

; ==============================================================================
; TownGateAllNastiesDeadCheck - Z si todos los nasty slots son TYPE_NONE
; ==============================================================================
; Itera slots SLOT_NASTY0..SLOT_NASTY0+NUM_NASTIES-1. Devuelve Z si todos
; TYPE_NONE, NZ si alguno todavia activo. Usado por TGP_WAIT_NASTIES para
; transicion dinamica a LOCK al terminar todos los puffs.
; Destruye: A, BC, DE, IX.
; ==============================================================================
TownGateAllNastiesDeadCheck:
    LD IX, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.tgandcLoop:
    LD A, (IX+ENT_TYPE)
    OR A
    RET NZ                              ; algun nasty aun activo
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .tgandcLoop
    XOR A                               ; Z = todos TYPE_NONE
    RET

; ==============================================================================
; TownGatePlayerXOR_BiClip - XOR player pixels skipping rows en rect de part1
; ==============================================================================
; Clip bidireccional: salta filas cuyo pixel_y este en [TGCS_ARCH_PX_TOP,
; TGCS_ARCH_PX_BOTTOM] (= [120, 151] = rect vertical de part1). Filas arriba
; y abajo se dibujan normal (XOR).
;
; Resultado: el player nunca tiene pixels VRAM dentro del rect de part1.
; - Encima del arco (POSY+20 < 120): full draw.
; - Entrando por arriba (POSY 100..119): rows superiores visibles, rows
;   inferiores que pasan tras el lintel skipped.
; - Totalmente dentro (POSY 120..131): nada drawn.
; - Saliendo por abajo (POSY 132..151): rows inferiores visibles, top tras
;   lintel skipped.
; - Bajo del arco (POSY >= 152): full draw.
;
; IN: D = Y, E = X (asume aligned a 8). IY = sprite ptr CON header.
;     Bank 6 paginado al entrar (caller).
; Player es 16w x 21h. Aligned X (no shift). XOR-write.
; Destruye: AF, BC, DE, HL, IY.
; ==============================================================================
PLAYER_H_PX              EQU 21

TownGatePlayerXOR_BiClip:
    INC IY
    INC IY                              ; skip header
    PUSH DE
    CALL CalcPixelAddr                  ; HL = VRAM at (D, E)
    POP DE
    LD B, PLAYER_H_PX                   ; B = row counter
    LD C, D                             ; C = current pixel Y
.tgpxbcRow:
    LD A, C
    CP 192
    JR NC, .tgpxbcAdvance               ; pixel_y >= 192: off-screen, skip
                                        ; (sin este clip, NextPixelLine lleva
                                        ; HL a $5800+ = area de attrs → XOR
                                        ; corrompe attrs como flashes raros).
    CP TGCS_ARCH_PX_TOP                 ; < 120 ?
    JR C, .tgpxbcDraw                   ; arriba del arco: dibujar
    CP TGCS_ARCH_PX_BOTTOM + 1          ; >= 152 ?
    JR NC, .tgpxbcDraw                  ; abajo del arco: dibujar
    ; In [120, 151] → skip pixels en esta row
    JR .tgpxbcAdvance
.tgpxbcDraw:
    ; OJO: sprites de sprite_data.asm NO estan CPL'd (a diferencia de BG en
    ; bg_gfx.asm). DrawSprite los XOR directos. Aqui igual: sin CPL.
    LD A, (IY+0)
    XOR (HL)
    LD (HL), A
    INC HL
    LD A, (IY+1)
    XOR (HL)
    LD (HL), A
    DEC HL                              ; back to row start
.tgpxbcAdvance:
    INC IY
    INC IY                              ; sprite ptr → next row (2 bytes wide)
    INC C                               ; pixel Y += 1
    PUSH BC
    CALL NextPixelLine                  ; HL → next pixel row in VRAM
    POP BC
    DJNZ .tgpxbcRow
    RET

; ==============================================================================
; TownGatePlayerSlideErase / SlideDraw - wrappers con paging bank 6
; ==============================================================================
; Usados en TownGateExitStep en lugar de TownGateRedrawPlayer. No tocan attrs
; (los player attrs se pintaron en phase 9 y se limpian al salir de phase 9
; con un RestoreOldAttr; las attrs del area por la que pasa el player se
; quedan como BG, suficiente para que los pixels visibles se vean blancos).
; ==============================================================================
TownGatePlayerSlideErase:
    LD IX, EntityTable
    PUSH IX
    CALL GetOldSpriteAddr               ; OldSprAddr = ptr (paginates bank 6, restaura bank 0)
    POP IX
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD IY, (OldSprAddr)
    LD D, (IX+ENT_OLDY)
    LD A, (IX+ENT_OLDX)
    LD E, A
    CALL TownGatePlayerXOR_BiClip
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

TownGatePlayerSlideDraw:
    LD IX, EntityTable
    PUSH IX
    CALL GetSpriteAddr                  ; SpriteAddrTemp = ptr
    POP IX
    LD A, (CurrentPaging)
    AND $F8
    OR 6
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD IY, (SpriteAddrTemp)
    LD A, (PlayerDrawY)
    LD D, A
    LD A, (IX+ENT_DRAWX)
    LD E, A
    CALL TownGatePlayerXOR_BiClip
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; Update OLD = current
    LD A, (IX+ENT_DRAWX)
    LD (IX+ENT_OLDX), A
    LD A, (PlayerDrawY)
    LD (IX+ENT_OLDY), A
    LD A, (IX+ENT_SPRITEID)
    LD (IX+ENT_OLDSPRID), A
    RET

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
    ; Clipped XOR: pixels del player NUNCA se escriben dentro del rect
    ; vertical de part1 (rows 120-151). Eliminacion limpia del solapamiento.
    ; Sin RestoreOldAttr ni SetEntityAttr en cada step → no hay clobber de
    ; part1 attrs ni de door attrs.
    CALL TownGatePlayerSlideErase
    JP TownGatePlayerSlideDraw          ; tail call

; ==============================================================================
; TownGateDrawTheEnd - dibuja el sprite "The End" (id 243) en (10,4)
; ==============================================================================
; Bank 3. El sprite "the end" (88x72) esta RLE-comprimido (bit 7 de
; width_bytes set), asi que NO podemos usar DrawBgSpriteXOR (no decodifica
; RLE — produce distorsion). Usamos DrawBgGfxSprite, la rutina normal de
; render BG: decodifica RLE + pinta pixels (direct write) + attrs.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
TownGateDrawTheEnd:
    LD HL, BgGfx_the_end
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    LD B, TGCS_END_CHARX
    LD C, TGCS_END_CHARY
    XOR A
    LD (BgSpriteIsHouse), A
    LD (CurrentTintVar), A              ; sin tint
    JP DrawBgGfxSprite

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
