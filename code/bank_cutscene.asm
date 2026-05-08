; ==============================================================================
; bank_cutscene.asm - Cutscene del banco (M9 propuesto)
; ==============================================================================
; ESTADO: DRAFT — este archivo NO esta INCLUDE'd en main.asm. Cero impacto
; en el binario hasta wire-up.
;
; Placement decidido (verificado con tools/memory_map.py): **bank 0**
; (slot 3 default). Razones:
;   - Slot 1 (bank 5) tiene 294 B libres — no cabe.
;   - Bank 2 (slot 2) tiene 2 B libres — full.
;   - Bank 0 tiene 1404 B libres → margen ~150-400 B tras meter el cuerpo.
;   - Todos los helpers que llama el cutscene son: bank 0 (no cross-bank),
;     slot 1 always-vis, o slot 2 always-vis → CERO thunks necesarios.
;
; INCLUDE va entre sound.asm y PAGE 1 en main.asm (zona bank 0 default).
;
; Diseno doc: docs/bank_cutscene.md.
;
; Disparada al chocar contra la puerta del banco (sprite Bank id 39, en
; sala (8,8)) llevando el cheque (BankCheck id 44, key id 7).
;
; Phase machine indexada por BankCutscenePhase. Cuando != 0, MainLoop salta
; el bloque normal de gameplay y llama UpdateBankCutscene cada frame.
;
; Esquema de fases:
;   0  IDLE              no en cutscene
;   1  LOCK              snap player a anchor, facing N, pausa breve
;   2  KNOCKS_1          3 toques (sub-state HIT/GAP)
;   3  WAIT_1            espera silenciosa tras grupo 1
;   4  KNOCKS_2          3 toques mas
;   5  WAIT_2            espera tras grupo 2
;   6  TURN_TO_CAM       player gira a S (cara camara)
;   7  TURN_TO_DOOR      player vuelve a N
;   8  KNOCKS_3          6 toques
;   9  WAIT_3            pausa antes de aparecer la mano
;  10  PRE_HAND          hold corto; la puerta NO se abre (mano sale por la
;                        rendija de la puerta cerrada)
;  11  HAND_IN           aparece mano (frame 0) sobre la puerta cerrada
;  12  HAND_NO_NO        anim swaps frame 0/1, BCS_NO_SWAPS_TOTAL veces
;  13  HAND_OUT          erase mano
;  14  KEY_DROP          BankKeySpawned=1 + RedrawPickupByPtr
;  15  PLAYER_TURN_CAM   player mira a camara un instante
;  16  DONE              sentinel; setear phase=IDLE devuelve control
;  17  WAIT_NASTIES      pre-LOCK: nasties + death animan puff antes de LOCK
;                        (mismo patron que TGP_WAIT_NASTIES de town_gate;
;                        MainLoop ramifica especial para mantener
;                        ProcessEnemies + ProcessDeath corriendo).
;
; NOTA visual: la mano se dibuja con XOR sobre la puerta cerrada del banco.
; Hereda los attrs de la facade (no pinta los suyos), asi que XOR self-cancel
; en HAND_OUT deja la facade intacta. Por eso el draft inline +
; DrawBgSprite16XorAtPixel es el match exacto: cero gestion de attrs.
;
; Patron de placement: bank 0 (slot 3 default). Helpers en bank 0 (mismo
; bank, sin thunks), slot 1 (always-vis), slot 2 (always-vis). Las CALLs a
; LoadBgSpriteToBuffer (slot 1) restauran bank 0 al volver via su patron
; estandar — el body en bank 0 reaparece tras el RET sin problemas.
; ==============================================================================

; ==============================================================================
; Phase enum
; ==============================================================================
BCP_IDLE                EQU 0
BCP_LOCK                EQU 1
BCP_KNOCKS_1            EQU 2
BCP_WAIT_1              EQU 3
BCP_KNOCKS_2            EQU 4
BCP_WAIT_2              EQU 5
BCP_TURN_TO_CAM         EQU 6
BCP_TURN_TO_DOOR        EQU 7
BCP_KNOCKS_3            EQU 8
BCP_WAIT_3              EQU 9
BCP_PRE_HAND            EQU 10      ; antes BCP_DOOR_OPEN; ahora puerta no se abre
BCP_HAND_IN             EQU 11
BCP_HAND_NO_NO          EQU 12
BCP_HAND_OUT            EQU 13
BCP_KEY_DROP            EQU 14
BCP_PLAYER_TURN_CAM     EQU 15
BCP_DONE                EQU 16
BCP_WAIT_NASTIES        EQU 17
BCP_DOOR_CLOSED         EQU 18      ; pausa con puerta visible cerrada antes del key drop

; Sub-states del knock-loop (BankCutsceneSubState)
BCS_KNOCK_HIT           EQU 0
BCS_KNOCK_GAP           EQU 1

; ==============================================================================
; Timings (frames a 50 Hz). Ajustables sin tocar logica.
; ==============================================================================
BCS_T_LOCK              EQU 30      ; 1.2s lock inicial
BCS_T_KNOCK_HIT         EQU 4       ; cada hit (door shake + sfx) — was 6
BCS_T_KNOCK_GAP         EQU 5       ; gap entre toques — was 8
BCS_T_GROUP_WAIT        EQU 50      ; 2s espera silenciosa tras cada grupo
BCS_T_TURN_CAM          EQU 40      ; 1.6s mid-cutscene mirando camara
BCS_T_TURN_BACK         EQU 10      ; transicion rapida de vuelta
BCS_T_PRE_HAND          EQU 30      ; pausa tras los 6 toques antes de la mano
BCS_T_PRE_HAND_HOLD     EQU 20      ; hold corto antes de hacer aparecer la mano
BCS_T_HAND_IN           EQU 20      ; pause tras aparecer mano
BCS_T_NO_FRAME          EQU 12      ; cada swap de "no no"
BCS_T_HAND_HOLD         EQU 15      ; pausa tras ultimo swap
; (BCS_T_HAND_OUT eliminado: ahora HAND_OUT erase + key spawn van juntos.)
BCS_T_DOOR_CLOSED_HOLD  EQU 30      ; pausa con puerta cerrada antes del key drop
BCS_T_KEY_HOLD          EQU 30      ; pausa tras drop antes de turn-cam
BCS_T_PLAYER_TURN_FINAL EQU 30      ; 1.2s mirando camara antes de devolver control
BCS_T_PUFF_WAIT         EQU 100     ; safety timeout WAIT_NASTIES (transicion real
                                    ; es por check dinamico de "all nasties dead").

; Cuentas
BCS_GROUP1_KNOCKS       EQU 3
BCS_GROUP2_KNOCKS       EQU 3
BCS_GROUP3_KNOCKS       EQU 6
BCS_NO_SWAPS_TOTAL      EQU 8       ; 4 "no" × 2 swaps = 8 transiciones

; ==============================================================================
; Sala + posiciones (placeholders; verificar in-game)
; ==============================================================================
BCS_BANK_ROOM_X         EQU 8       ; sala del banco (norte del ayuntamiento)
BCS_BANK_ROOM_Y         EQU 8

; Anchor del player durante la cinematica (centrado bajo la puerta)
BCS_PLAYER_ANCHOR_X     EQU 120
BCS_PLAYER_ANCHOR_Y     EQU 80

; Posicion de la puerta del banco — confirmada por el usuario en el editor:
; Cell (8,8), char (15, 4). Asumo tamaño 2x2 chars (16x16 px) — mismo
; tamaño que el sprite de la mano. Si el sprite real BankDoorOpen es
; mas grande (e.g. 3x3 o 4x4), ajustar BCS_DOOR_CHAR_W/H.
;
; Bank facade en char (12, 0), 64x48 px → (12-19, 0-5). Door en (15, 4)
; cae en la mitad inferior central de la facade. Pixel coords con
; BG_Y_OFFSET=2: top-left = (15*8, (4+2)*8) = (120, 48).
BCS_DOOR_CHARX          EQU 15
BCS_DOOR_CHARY          EQU 4
BCS_DOOR_CHAR_W         EQU 2       ; ancho en chars (16 px)
BCS_DOOR_CHAR_H         EQU 2       ; alto en chars (16 px)

; AABB en pixels (derivado de char coords)
BCS_DOOR_PX_LEFT        EQU 120     ; 15*8
BCS_DOOR_PX_RIGHT       EQU 135     ; 120 + 16 - 1
BCS_DOOR_PX_TOP         EQU 48      ; (4+2)*8
BCS_DOOR_PX_BOTTOM      EQU 63      ; 48 + 16 - 1
BCS_DOOR_TOLERANCE      EQU 4       ; mismo margen que CheckTownGateTriggerBg

; Posicion de la mano cuando asoma (centrada en el hueco de la puerta)
BCS_HAND_PX_X           EQU 120     ; mismo X que la puerta (16x16 sprite)
BCS_HAND_PX_Y           EQU 48      ; mismo Y que la puerta

; Posicion (char) donde se dibuja BankKey al final — placeholder
; (suelo justo delante de la puerta)
BCS_KEY_DROP_CHARX      EQU 15
BCS_KEY_DROP_CHARY      EQU 7

; Trigger requirements
BCS_REQUIRED_KEY        EQU 7       ; BankCheck (slot 7 en KeyLockTable, NUEVO)

; ==============================================================================
; CheckBankTriggerBg - bump-trigger del banco (BG sprite, no en PickupTable)
; ==============================================================================
; Llamada cada frame desde MainLoop tras CheckBumpTriggers (gemelo de
; CheckTownGateTriggerBg). Mismo test AABB ±BCS_DOOR_TOLERANCE.
;
; Dispara: BankCutscenePhase==0, CurrentKey==7 (BankCheck), sala (8,8),
; player AABB (16x21) overlapea rect de la puerta. HIT → StartBankCutscene
; + CheckMilestoneTrigger(4) (avanza M9).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
CheckBankTriggerBg:
    LD A, (BankCutscenePhase)
    OR A
    RET NZ                              ; ya en cutscene
    LD A, (CurrentKey)
    CP BCS_REQUIRED_KEY
    RET NZ                              ; sin cheque
    LD A, (CurrentScreenX)
    CP BCS_BANK_ROOM_X
    RET NZ
    LD A, (CurrentScreenY)
    CP BCS_BANK_ROOM_Y
    RET NZ
    ; --- Horizontal AABB ---
    LD A, (EntityTable + ENT_POSX)
    LD C, A                             ; C = player_left
    ADD A, 16
    LD D, A                             ; D = player_right
    LD A, BCS_DOOR_PX_LEFT
    SUB BCS_DOOR_TOLERANCE
    JR NC, .cbtNoUnderL
    XOR A
.cbtNoUnderL:
    CP D
    RET NC
    LD A, BCS_DOOR_PX_RIGHT
    ADD A, BCS_DOOR_TOLERANCE
    JR NC, .cbtNoOverR
    LD A, $FF
.cbtNoOverR:
    CP C
    RET C
    ; --- Vertical AABB (player rect 16x21) ---
    LD A, (EntityTable + ENT_POSY)
    LD C, A
    ADD A, 21
    LD D, A
    LD A, BCS_DOOR_PX_TOP
    SUB BCS_DOOR_TOLERANCE
    JR NC, .cbtNoUnderT
    XOR A
.cbtNoUnderT:
    CP D
    RET NC
    LD A, BCS_DOOR_PX_BOTTOM
    ADD A, BCS_DOOR_TOLERANCE
    JR NC, .cbtNoOverB
    LD A, $FF
.cbtNoOverB:
    CP C
    RET C
    ; HIT
    CALL StartBankCutscene
    LD A, 4                             ; action 4 = BankDoor
    JP CheckMilestoneTrigger            ; tail call

; ==============================================================================
; StartBankCutscene - llamada desde el handler del bump-trigger action 4
; ==============================================================================
; 1. Consume cheque (CurrentKey = 0).
; 2. Snap player a anchor frente a la puerta, facing N.
; 3. Entra en BCP_LOCK con timer = BCS_T_LOCK.
; 4. KillAllActiveNasties + KillDeathIfActive (mismo paradigma town_gate)
;    para limpiar la pantalla durante la cutscene.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
StartBankCutscene:
    XOR A
    LD (CurrentKey), A                  ; consume cheque
    LD (BankCutsceneKnockIdx), A
    LD (BankCutsceneSubState), A
    LD (BankCutsceneNoIdx), A
    LD (BankCutsceneHandFrame), A
    CALL KillAllActiveNasties           ; nasties → STATE_DYING + puff anim
    CALL KillDeathIfActive               ; muerte (slot 11) → puff y despawn
    ; Guardar la posicion actual del player como ORIG (a donde se retira
    ; entre grupos de toques). El snap a DOOR se hace al entrar a LOCK
    ; (post WAIT_NASTIES). El player se queda en su pos original durante
    ; WAIT_NASTIES — solo cambiamos el sprite a facing N para preparar.
    LD A, (EntityTable + ENT_POSX)
    LD (BankCutsceneOrigX), A
    LD A, (EntityTable + ENT_POSY)
    LD (BankCutsceneOrigY), A
    CALL BankCutsceneFacingNRedraw
    CALL SFX_Bank_OnStart
    ; Entrar en WAIT_NASTIES: MainLoop ramifica para mantener
    ; ProcessEnemies + ProcessDeath corriendo (animan puffs). Cuando
    ; todos los slots TYPE_NONE → transicion a LOCK + arranca la cutscene.
    LD A, BCS_T_PUFF_WAIT
    LD (BankCutsceneTimer), A
    LD A, BCP_WAIT_NASTIES
    LD (BankCutscenePhase), A
    RET

; ==============================================================================
; BankCutsceneSnapPlayer - teleport player a anchor + facing N
; ==============================================================================
BankCutsceneSnapPlayer:
    LD IX, EntityTable
    LD (IX+ENT_POSX), BCS_PLAYER_ANCHOR_X
    LD (IX+ENT_DRAWX), BCS_PLAYER_ANCHOR_X
    LD (IX+ENT_POSY), BCS_PLAYER_ANCHOR_Y
    LD A, BCS_PLAYER_ANCHOR_Y
    LD (PlayerDrawY), A
    LD A, SPRID_WALK_N + 1              ; pose static (mirando arriba)
    LD (IX+ENT_SPRITEID), A
    LD A, SPRID_WALK_N
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    JP TownGateRedrawPlayer

; ==============================================================================
; UpdateBankCutscene - llamada cada frame desde MainLoop si phase != 0
; ==============================================================================
; Dispatch por BankCutscenePhase. Cada fase: trabajo de tick, decremento
; timer, transicion a la siguiente. Imitando town_gate sin nasty wait pre-LOCK
; porque aqui asumimos que en sala (8,8) no hay nasties que esperar (lo
; resuelve KillAllActiveNasties de StartBankCutscene).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
UpdateBankCutscene:
    LD A, (BankCutscenePhase)
    CP BCP_WAIT_NASTIES                 ; pre-LOCK (ramificado en MainLoop)
    JP Z, .bcPhWaitNasties
    CP BCP_DOOR_CLOSED                  ; post-hand pause con puerta cerrada
    JP Z, .bcPhDoorClosed
    DEC A
    JP Z, .bcPhLock
    DEC A
    JP Z, .bcPhKnocks1
    DEC A
    JP Z, .bcPhWait1
    DEC A
    JP Z, .bcPhKnocks2
    DEC A
    JP Z, .bcPhWait2
    DEC A
    JP Z, .bcPhTurnToCam
    DEC A
    JP Z, .bcPhTurnToDoor
    DEC A
    JP Z, .bcPhKnocks3
    DEC A
    JP Z, .bcPhWait3
    DEC A
    JP Z, .bcPhPreHand
    DEC A
    JP Z, .bcPhHandIn
    DEC A
    JP Z, .bcPhHandNoNo
    DEC A
    JP Z, .bcPhHandOut
    DEC A
    JP Z, .bcPhKeyDrop
    DEC A
    JP Z, .bcPhPlayerTurnCam
    ; BCP_DONE: setear phase=IDLE y devolver control. La cutscene termina.
    XOR A
    LD (BankCutscenePhase), A
    RET

; ---- Phase 17: WAIT_NASTIES ----
; Espera a que terminen los puffs de nasties + death antes de entrar a LOCK.
; ProcessEnemies + ProcessDeath se mantienen corriendo desde MainLoop
; ramifica especial. Re-llama a KillAllActiveNasties cada frame para cazar
; nasties que estaban en STATE_SPAWNING al disparar trigger.
;
; Transicion: cuando TownGateAllNastiesDeadCheck devuelve Z (todos los
; slots NASTY = TYPE_NONE) → setup LOCK con timer + RET. Si tarda demasiado
; (timeout BCS_T_PUFF_WAIT), tambien transiciona (safety net).
.bcPhWaitNasties:
    CALL KillAllActiveNasties           ; cazar spawnings recien terminados
    CALL TownGateAllNastiesDeadCheck    ; reusa label (slot 1 always-vis)
    JR Z, .bcWaitNastiesDone
    CALL BankCutsceneDecTimer           ; safety timeout
    RET NZ
.bcWaitNastiesDone:
    CALL BankCutsceneSnapToDoor         ; player se acerca a la puerta para LOCK + KNOCKS_1
    LD A, BCS_T_LOCK
    LD (BankCutsceneTimer), A
    LD A, BCP_LOCK
    LD (BankCutscenePhase), A
    RET

; ---- Phase 1: lock + facing UP ----
.bcPhLock:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Iniciar grupo 1: 3 toques (knock type SOFT).
    XOR A
    LD (BankCutsceneKnockIdx), A
    LD (BankCutsceneKnockType), A       ; 0 = soft
    LD A, BCS_KNOCK_HIT
    LD (BankCutsceneSubState), A
    LD A, BCS_T_KNOCK_HIT
    LD (BankCutsceneTimer), A
    CALL BankCutsceneEmitKnockHit       ; primer toque inmediato
    LD A, BCP_KNOCKS_1
    LD (BankCutscenePhase), A
    RET

; ---- Phase 2: 3 toques (KNOCKS_1) ----
; Estructura comun para los 3 grupos: BankCutsceneTickKnockGroup hace
; el trabajo (tick timer + transicion HIT/GAP, increment KnockIdx).
; Devuelve A = 1 si grupo terminado, 0 si sigue.
.bcPhKnocks1:
    LD A, BCS_GROUP1_KNOCKS
    CALL BankCutsceneTickKnockGroup
    OR A
    RET Z                               ; sigue
    ; grupo 1 terminado → retirarse a ORIG + wait
    CALL BankCutsceneSnapToOrig
    LD A, BCS_T_GROUP_WAIT
    LD (BankCutsceneTimer), A
    LD A, BCP_WAIT_1
    LD (BankCutscenePhase), A
    RET

; ---- Phase 3: WAIT_1 (espera silenciosa) ----
.bcPhWait1:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Iniciar grupo 2: snap a DOOR + setup knock loop (type SOFT).
    CALL BankCutsceneSnapToDoor
    XOR A
    LD (BankCutsceneKnockIdx), A
    LD (BankCutsceneKnockType), A       ; 0 = soft
    LD A, BCS_KNOCK_HIT
    LD (BankCutsceneSubState), A
    LD A, BCS_T_KNOCK_HIT
    LD (BankCutsceneTimer), A
    CALL BankCutsceneEmitKnockHit
    LD A, BCP_KNOCKS_2
    LD (BankCutscenePhase), A
    RET

; ---- Phase 4: 3 toques (KNOCKS_2) ----
.bcPhKnocks2:
    LD A, BCS_GROUP2_KNOCKS
    CALL BankCutsceneTickKnockGroup
    OR A
    RET Z
    ; grupo 2 terminado → retirarse a ORIG + wait
    CALL BankCutsceneSnapToOrig
    LD A, BCS_T_GROUP_WAIT
    LD (BankCutsceneTimer), A
    LD A, BCP_WAIT_2
    LD (BankCutscenePhase), A
    RET

; ---- Phase 5: WAIT_2 ----
.bcPhWait2:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Player gira a S (cara camara).
    LD IX, EntityTable
    LD A, SPRID_IDLE                    ; idle = sprite mirando S
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    CALL TownGateRedrawPlayer
    LD A, BCS_T_TURN_CAM
    LD (BankCutsceneTimer), A
    LD A, BCP_TURN_TO_CAM
    LD (BankCutscenePhase), A
    RET

; ---- Phase 6: player mirando camara mid-cutscene ----
.bcPhTurnToCam:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Player vuelve a N (cara puerta).
    LD IX, EntityTable
    LD A, SPRID_WALK_N + 1              ; pose static walk-N
    LD (IX+ENT_SPRITEID), A
    LD A, SPRID_WALK_N
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    CALL TownGateRedrawPlayer
    LD A, BCS_T_TURN_BACK
    LD (BankCutsceneTimer), A
    LD A, BCP_TURN_TO_DOOR
    LD (BankCutscenePhase), A
    RET

; ---- Phase 7: transicion rapida de vuelta a N → arrancar grupo 3 ----
.bcPhTurnToDoor:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Snap a DOOR (player se acerca otra vez para los 6 toques finales).
    CALL BankCutsceneSnapToDoor
    XOR A
    LD (BankCutsceneKnockIdx), A
    LD A, 1
    LD (BankCutsceneKnockType), A       ; 1 = loud (grupo 3 = 6 knocks)
    XOR A
    LD (BankCutsceneSubState), A        ; HIT
    LD A, BCS_T_KNOCK_HIT
    LD (BankCutsceneTimer), A
    CALL BankCutsceneEmitKnockHit
    LD A, BCP_KNOCKS_3
    LD (BankCutscenePhase), A
    RET

; ---- Phase 8: 6 toques (KNOCKS_3) ----
.bcPhKnocks3:
    LD A, BCS_GROUP3_KNOCKS
    CALL BankCutsceneTickKnockGroup
    OR A
    RET Z
    LD A, BCS_T_PRE_HAND
    LD (BankCutsceneTimer), A
    LD A, BCP_WAIT_3
    LD (BankCutscenePhase), A
    RET

; ---- Phase 9: pausa tras toques antes de la aparicion de la mano ----
; La puerta NO se abre — la mano sale por la rendija de la puerta cerrada.
; SFX_Bank_OnDoorCreak puede sugerir un crujido leve (placeholder RET hoy).
.bcPhWait3:
    CALL BankCutsceneDecTimer
    RET NZ
    CALL SFX_Bank_OnDoorCreak
    LD A, BCS_T_PRE_HAND_HOLD
    LD (BankCutsceneTimer), A
    LD A, BCP_PRE_HAND
    LD (BankCutscenePhase), A
    RET

; ---- Phase 10: hold corto antes de la mano ----
; Aqui hacemos el "swap" puerta cerrada → mano: XOR-cancel del sprite
; bank_door_closed (chars (15,4) en sala (8,8)) → area en negro → drawhand
; sobre area limpia. Mismo patron que TownGateOpenDoor con el closed_v2.
.bcPhPreHand:
    CALL BankCutsceneDecTimer
    RET NZ
    XOR A
    LD (BankCutsceneHandFrame), A
    LD (BankCutsceneNoIdx), A
    CALL BankCutsceneOpenDoorWithHandAttrs  ; XOR pixels (puerta off) + attrs invertidos
    CALL BankCutsceneDrawHand           ; frame 0 sobre area en negro
    CALL SFX_Bank_OnHandIn
    LD A, BCS_T_HAND_IN
    LD (BankCutsceneTimer), A
    LD A, BCP_HAND_IN
    LD (BankCutscenePhase), A
    RET

; ---- Phase 11: hand visible + pause antes de "no no" ----
.bcPhHandIn:
    CALL BankCutsceneDecTimer
    RET NZ
    LD A, BCS_T_NO_FRAME
    LD (BankCutsceneTimer), A
    LD A, BCP_HAND_NO_NO
    LD (BankCutscenePhase), A
    RET

; ---- Phase 12: anim "no no" — swaps frame 0/1, 8 veces (4 "no" cycles) ----
.bcPhHandNoNo:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Swap frame: erase actual + draw el otro.
    CALL BankCutsceneEraseHand          ; erase frame actual (XOR self-cancel)
    LD A, (BankCutsceneHandFrame)
    XOR 1
    LD (BankCutsceneHandFrame), A
    CALL BankCutsceneDrawHand           ; draw frame nuevo
    CALL SFX_Bank_OnNoSwap              ; cada swap suena (placeholder)
    ; Increment swap idx, check completion.
    LD A, (BankCutsceneNoIdx)
    INC A
    LD (BankCutsceneNoIdx), A
    CP BCS_NO_SWAPS_TOTAL
    JR C, .bcNoNoMoreSwaps
    ; Todos los swaps hechos — pausa antes de erase mano.
    LD A, BCS_T_HAND_HOLD
    LD (BankCutsceneTimer), A
    ; Avanzar phase implicitamente al siguiente (HAND_OUT pasa por
    ; eraseHand pero queremos un frame de hold antes — gestionado abajo).
    LD A, BCP_HAND_OUT
    LD (BankCutscenePhase), A
    RET
.bcNoNoMoreSwaps:
    LD A, BCS_T_NO_FRAME
    LD (BankCutsceneTimer), A
    RET

; ---- Phase 13: erase mano → spawn llave de la ciudad → pausa antes del giro ----
; Reutiliza TownGateKeySpawned + BgGfx_town_gate_key (el sprite que antes
; soltaba la iglesia; ahora su placement vive en sala (8,8) por placement
; del editor y lo revela esta cinematica via RedrawPickupByPtr — XOR-show
; del pickup dormant).
; ---- Phase 13: HAND_OUT — erase mano + cierre visible de la puerta ----
; Beat dedicado para el cierre de puerta: el player ve la mano irse y la
; puerta cerrarse como evento, ANTES del drop de la llave. Tras esto, una
; pausa BCS_T_DOOR_CLOSED_HOLD permite "asentar" el cierre antes del clink
; de la llave.
.bcPhHandOut:
    CALL BankCutsceneDecTimer           ; HAND_HOLD: pausa con mano visible
    RET NZ
    CALL BankCutsceneEraseHand          ; erase XOR self-cancel
    CALL BankCutsceneCloseDoorRestoreAttrs ; SET pixels + restaurar attrs originales
    CALL SFX_Bank_OnHandOut             ; SFX cierre de puerta (placeholder hoy)
    LD A, BCS_T_DOOR_CLOSED_HOLD
    LD (BankCutsceneTimer), A
    LD A, BCP_DOOR_CLOSED
    LD (BankCutscenePhase), A
    RET

; ---- Phase 18: DOOR_CLOSED — pausa con puerta cerrada → spawn de la llave ----
.bcPhDoorClosed:
    CALL BankCutsceneDecTimer
    RET NZ
    ; --- Spawn de la llave de la ciudad ---
    LD A, 1
    LD (TownGateKeySpawned), A
    LD HL, SFX_KeyDrop
    CALL PlaySFX
    LD DE, BgGfx_town_gate_key
    CALL RedrawPickupByPtr
    ; Pausa KEY_HOLD con la llave visible antes de que el player gire.
    LD A, BCS_T_KEY_HOLD
    LD (BankCutsceneTimer), A
    LD A, BCP_KEY_DROP
    LD (BankCutscenePhase), A
    RET

; ---- Phase 14: pausa con la llave visible → giro a camara ----
.bcPhKeyDrop:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Player gira a camara final.
    LD IX, EntityTable
    LD A, SPRID_IDLE
    LD (IX+ENT_SPRITEID), A
    LD (IX+ENT_ANIMBASE), A
    XOR A
    LD (IX+ENT_ANIMTIMER), A
    CALL TownGateRedrawPlayer
    CALL SFX_Bank_OnPlayerTurn
    LD A, BCS_T_PLAYER_TURN_FINAL
    LD (BankCutsceneTimer), A
    LD A, BCP_PLAYER_TURN_CAM
    LD (BankCutscenePhase), A
    RET

; ---- Phase 15: player mirando camara antes de devolver control ----
.bcPhPlayerTurnCam:
    CALL BankCutsceneDecTimer
    RET NZ
    ; Setear DONE → siguiente UpdateBankCutscene cae al fallthrough y pone IDLE.
    LD A, BCP_DONE
    LD (BankCutscenePhase), A
    RET

; ==============================================================================
; BankCutsceneTickKnockGroup - tick comun del knock-loop
; ==============================================================================
; IN:  A = total knocks del grupo (BCS_GROUP1_KNOCKS / GROUP2 / GROUP3).
; OUT: A = 1 si grupo terminado, 0 si sigue. Caller decide phase next.
;
; Estado:
;   BankCutsceneSubState: 0=HIT, 1=GAP
;   BankCutsceneTimer:    decrementa por frame
;   BankCutsceneKnockIdx: knocks emitidos hasta ahora
;
; Logica:
;   - Tick timer. Si != 0, return 0.
;   - Si SubState=HIT y timer=0 → switch a GAP, set timer = T_KNOCK_GAP.
;   - Si SubState=GAP y timer=0:
;       - increment KnockIdx
;       - if KnockIdx >= total: return 1 (grupo terminado)
;       - else: switch a HIT, emit knock, set timer = T_KNOCK_HIT.
;
; Destruye: A, BC, DE, HL.
; ==============================================================================
BankCutsceneTickKnockGroup:
    LD B, A                             ; B = total knocks
    LD A, (BankCutsceneTimer)
    DEC A
    LD (BankCutsceneTimer), A
    OR A
    JR Z, .bctkgTimer0
    XOR A                               ; sigue, no terminado
    RET
.bctkgTimer0:
    LD A, (BankCutsceneSubState)
    OR A
    JR NZ, .bctkgGap0
    ; HIT acabo: switch a GAP.
    LD A, BCS_KNOCK_GAP
    LD (BankCutsceneSubState), A
    LD A, BCS_T_KNOCK_GAP
    LD (BankCutsceneTimer), A
    XOR A
    RET
.bctkgGap0:
    ; GAP acabo: increment KnockIdx, comparar con B (total).
    LD A, (BankCutsceneKnockIdx)
    INC A
    LD (BankCutsceneKnockIdx), A
    CP B
    JR C, .bctkgNextHit                 ; aun queda al menos 1 toque
    ; grupo terminado.
    LD A, 1
    RET
.bctkgNextHit:
    LD A, BCS_KNOCK_HIT
    LD (BankCutsceneSubState), A
    LD A, BCS_T_KNOCK_HIT
    LD (BankCutsceneTimer), A
    CALL BankCutsceneEmitKnockHit
    XOR A
    RET

; ==============================================================================
; BankCutsceneEmitKnockHit - SFX + (TODO) door shake del toque actual
; ==============================================================================
; Llamado al inicio de cada hit. Por ahora: solo SFX placeholder.
; TODO: door shake — XOR-redraw del Bank facade con offset ±1 px en eje X.
; Destruye: A, BC, DE, HL.
; ==============================================================================
BankCutsceneEmitKnockHit:
    JP SFX_Bank_OnKnock                 ; tail-call

; ==============================================================================
; BCS_DOOR_HAND_ATTR  — attrs durante la fase de mano (paper=000 black,
; ink=111 white, bright=1). Inversion respecto a $78 (paper bright white,
; ink black) que es el attr base del door sprite. Hace que la mano (XOR
; pixels) se vea bright white sobre fondo negro = "mano emerge de la
; oscuridad de la rendija".
BCS_DOOR_HAND_ATTR      EQU $47

; Direcciones de attrs en VRAM para los 4 chars (15-16, 4-5).
; Display row = char_row + BG_Y_OFFSET (2). attr_addr = $5800 + row*32 + col.
; Char (15, 4) → display row 6 → $5800 + 192 + 15 = $58CF.
; Char (16, 4) → $58D0. (15, 5) → $58EF. (16, 5) → $58F0.
BCS_DOOR_ATTR_ADDR_TL   EQU $58CF       ; top-left

; ==============================================================================
; BankCutsceneOpenDoorWithHandAttrs - XOR-cancel pixels de bank_door_closed
; + sobreescribir los 4 attrs de los chars (15-16, 4-5) con el attr "hand mode"
; (paper black, ink bright white). El hand sprite drawing posterior dejara
; pixels visibles bright white sobre fondo negro.
;
; CRITICO: usar DrawBgSpriteXOR (XOR), NO DrawBgGfxSprite (LD destructivo).
; DrawBgGfxSprite hace `LD (HL), A` que reescribe pixels en lugar de XOR —
; dos llamadas no cancelan, solo re-pintan.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
BankCutsceneOpenDoorWithHandAttrs:
    LD HL, BgGfx_bank_door_closed
    LD A, 3                             ; bank 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    LD B, BCS_DOOR_CHARX                ; 15
    LD C, BCS_DOOR_CHARY                ; 4
    CALL DrawBgSpriteXOR                ; XOR-cancel pixels (attrs intactos $78)
    ; Sobreescribir attrs a "hand mode" = $47.
    LD A, BCS_DOOR_HAND_ATTR
    LD HL, BCS_DOOR_ATTR_ADDR_TL        ; $58CF (15, 4 display row 6)
    LD (HL), A
    INC HL                              ; $58D0 (16, 4)
    LD (HL), A
    LD HL, BCS_DOOR_ATTR_ADDR_TL + 32   ; $58EF (15, 5)
    LD (HL), A
    INC HL                              ; $58F0 (16, 5)
    LD (HL), A
    RET

; ==============================================================================
; BankCutsceneCloseDoorRestoreAttrs - usa DrawBgGfxSprite (SET pixels + PAINT
; attrs originales del sprite, $78). Esto restaura tanto los pixels de la
; puerta cerrada como los attrs originales (paper bright white, ink black).
;
; Asume que VRAM en el area de la puerta esta a 0 (post-EraseHand).
; DrawBgGfxSprite SET pixels = mismo resultado que XOR sobre 0.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
BankCutsceneCloseDoorRestoreAttrs:
    LD HL, BgGfx_bank_door_closed
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    LD B, BCS_DOOR_CHARX
    LD C, BCS_DOOR_CHARY
    XOR A
    LD (BgSpriteIsHouse), A
    ; CurrentTintVar = $FF (no tint). El sprite door tiene tintPaper=7 y attr
    ; paper=7 — si CurrentTintVar fuera 0, ApplyTintSwap pondria paper=0 → todo
    ; negro. Con $FF (= "sin tint") la attr queda intacta a su valor original.
    LD A, $FF
    LD (CurrentTintVar), A
    JP DrawBgGfxSprite                  ; SET pixels + PAINT attrs ($78) sin tint

; ==============================================================================
; BankCutsceneDrawHand - draw mano frame actual en (BCS_HAND_PX_X, Y)
; ==============================================================================
; DrawBgSprite16XorAtPixel lee el sprite de BgSpriteBuffer (NO de HL).
; Antes de llamarlo, LDIR los 34 bytes del frame (header 2 + pixel 32) a
; BgSpriteBuffer — mismo patron que DrawSmokeFrameXor en church_cutscene.
; Esto es critico aqui porque la llamada previa (BankCutsceneRedrawClosedDoor)
; deja el sprite de la puerta en BgSpriteBuffer, no la mano.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
BankCutsceneDrawHand:
    LD A, (BankCutsceneHandFrame)
    OR A
    JR NZ, .bcdhFrame1
    LD HL, BgGfx_BankHandFrame0
    JR .bcdhCopy
.bcdhFrame1:
    LD HL, BgGfx_BankHandFrame1
.bcdhCopy:
    LD DE, BgSpriteBuffer
    LD BC, 34                           ; header 2 + pixel data 32 = 34 bytes
    LDIR
    LD D, BCS_HAND_PX_Y
    LD E, BCS_HAND_PX_X
    JP DrawBgSprite16XorAtPixel         ; tail-call (lee BgSpriteBuffer)

; ==============================================================================
; BankCutsceneEraseHand - XOR self-cancel del frame actual
; ==============================================================================
; Mismo draw — XOR self-cancela. NO incrementa BankCutsceneHandFrame.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
BankCutsceneEraseHand:
    JP BankCutsceneDrawHand             ; tail-call (XOR self-cancel)

; ==============================================================================
; Player redraw helpers — REUSADOS de town_gate_cutscene.asm (slot 1, always-vis):
;   TownGateRedrawPlayer:    erase old + draw new (cambio sprite/posicion).
;   TownGateDrawPlayerHere:  draw + attrs en (ENT_DRAWX, PlayerDrawY).
;   TownGateErasePlayer:     XOR-erase en (ENT_OLDX, ENT_OLDY) + RestoreOldAttr.
; Son rutinas puras del estado del player (no tocan ninguna var de town_gate),
; asi que invocarlas desde aqui (bank 0) ahorra ~85 B sin cambiar comportamiento.
; ==============================================================================

; ==============================================================================
; BankCutsceneDecTimer - decrementa BankCutsceneTimer, devuelve Z si llego a 0
; ==============================================================================
BankCutsceneDecTimer:
    LD A, (BankCutsceneTimer)
    DEC A
    LD (BankCutsceneTimer), A
    OR A
    RET

; ==============================================================================
; SFX stubs — placeholders RET. Rellenar con AY_PlayBeep / PlaySFX cuando
; se diseñen los timbres.
; ==============================================================================
SFX_Bank_OnStart:
    RET
; Knock: dispatch entre soft (grupos 1, 2) y loud (grupo 3) segun
; BankCutsceneKnockType (set por la fase de entrada al grupo). Duracion
; comun 4 frames (~160ms).
SFX_Bank_OnKnock:
    LD A, (BankCutsceneKnockType)
    OR A
    JR NZ, .sokLoud
    LD B, 4
    JP AY_PlayKnockSoft                 ; tail-call (grupos 1, 2: 3 knocks)
.sokLoud:
    LD B, 4
    JP AY_PlayKnockLoud                 ; tail-call (grupo 3: 6 knocks)
SFX_Bank_OnDoorCreak:                   ; antes SFX_Bank_OnDoorOpen
    ; TODO: crujido leve para sugerir que la puerta cede mientras la mano
    ; sale por la rendija (la puerta nunca se abre del todo).
    RET
; Cuando la puerta del banco se abre (PRE_HAND), reusamos el mismo crujido
; de puerta vieja que la iglesia (.cbtActChurchDoor en screen_system.asm).
SFX_Bank_OnHandIn:
    LD HL, SFX_ChurchDoorOpen
    JP PlaySFX                          ; tail-call
SFX_Bank_OnNoSwap:
    ; TODO: tone alterno (alto/bajo) por swap para reforzar "no no".
    RET
; Cuando la puerta del banco se cierra (HAND_OUT, tras erase mano + redraw
; door), reusamos el mismo crujido de puerta vieja que la iglesia. La
; iglesia tambien comparte SFX_ChurchDoorOpen para abrir y cerrar (ver
; CloseChurchDoor en church_cutscene.asm:610).
SFX_Bank_OnHandOut:
    LD HL, SFX_ChurchDoorOpen
    JP PlaySFX                          ; tail-call
SFX_Bank_OnPlayerTurn:
    RET

; ==============================================================================
; Sprites de la mano "No no" — 16x16 px (2x2 chars), 2 frames
; ==============================================================================
; Importado de References/nono01.aseprite via tools/import_smoke.py-style
; pipeline. Formato compatible con DrawBgSprite16XorAtPixel:
;   - Header 2B: height_px=16, width_bytes=2.
;   - Pixel data 32B: 16 filas x 2 bytes, CPL'd (engine re-CPL al draw).
;
; Mismo bank que el cuerpo del cutscene (bank 0 default). Tamaño total 68 B.
; Frame 0 = mano hacia un lado, Frame 1 = espejada → swap rápido = "no no".
; ==============================================================================
BgGfx_BankHandFrame0:
    DEFB 16, 2                              ; height_px, width_bytes
    DEFB $F9,$FF, $F8,$FF, $FC,$7F, $FE,$FF
    DEFB $F9,$BF, $F8,$9F, $E4,$8F, $E3,$CF
    DEFB $F3,$0F, $FC,$1F, $F8,$1F, $FC,$3F
    DEFB $FF,$FF, $F0,$17, $F0,$0F, $FF,$FF

BgGfx_BankHandFrame1:
    DEFB 16, 2                              ; height_px, width_bytes
    DEFB $FF,$CF, $FF,$8F, $FF,$1F, $F9,$BF
    DEFB $F8,$DF, $E4,$9F, $E3,$8F, $F3,$CF
    DEFB $FE,$0F, $F0,$1F, $F8,$3F, $F8,$7F
    DEFB $FF,$FF, $E0,$2F, $E0,$1F, $FF,$FF

; ==============================================================================
; Variables del cutscene — declaradas en code/variables.asm (bank 2, HOT-vis):
;   BankCutscenePhase, BankCutsceneTimer, BankCutsceneSubState,
;   BankCutsceneKnockIdx, BankCutsceneNoIdx, BankCutsceneHandFrame,
;   BankCheckSpawned.
; (TownGateKeySpawned ya existia; reusado por la fase KEY_DROP de aqui en vez
; de crear un BankKeySpawned separado — el sprite town_gate_key ahora se
; placea en sala (8,8) y lo revela esta cinematica.)
; Aqui solo el codigo + sprites; declaracion de simbolos via labels externos.
; ==============================================================================
