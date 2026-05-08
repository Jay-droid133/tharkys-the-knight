; ==============================================================================
; RANDOM PICKUPS — rutinas Give (slot 1, cold path)
; ==============================================================================
; Sistema: cada plantilla puede llevar hasta RANDOM_SLOT_MAX placements con id
; RANDOM_SLOT_MARKER (210). Al entrar a una sala se elige un slot via RNG y se
; rolea su contenido (life / health / stamina / nada) por probabilidad. El
; pickup elegido aparece en pantalla; al recogerlo se llama a la Give
; correspondiente desde CheckPickupCollect.
;
; Las Give routines tambien cubren placements explicitos de life/health/stamina
; si en el futuro se ponen pickups fijos en el editor.
;
; Vive en slot 1 (cold path): solo se invoca al recoger un pickup raro.
; Bank 0/2 quedan limpios.
; ==============================================================================

; ==============================================================================
; GiveLife - +1 vida, clamp a PLAYER_LIVES_MAX
; ==============================================================================
; HUD se refresca solo: DrawLivesHUD se llama cada frame en MainLoop y detecta
; el cambio via cache .dlhLast.
; ==============================================================================
GiveLife:
    LD A, (PlayerLives)
    CP PLAYER_LIVES_MAX
    RET NC                              ; ya en max (>= MAX) -> no-op
    INC A
    LD (PlayerLives), A
    RET

; ==============================================================================
; GiveHealth - +PICKUP_HEALTH_AMT, clamp a HEALTH_MAX
; ==============================================================================
; HUD se refresca solo via DrawHealthStaminaHUD (lee PlayerHealth cada frame).
; ==============================================================================
GiveHealth:
    LD A, (PlayerHealth)
    ADD A, PICKUP_HEALTH_AMT
    JR C, .ghCap                        ; overflow 8-bit -> definitivo cap
    CP HEALTH_MAX + 1
    JR C, .ghStore                      ; A <= HEALTH_MAX
.ghCap:
    LD A, HEALTH_MAX
.ghStore:
    LD (PlayerHealth), A
    RET

; ==============================================================================
; GiveStamina - +PICKUP_STAMINA_AMT, clamp a STAMINA_MAX
; ==============================================================================
GiveStamina:
    LD A, (PlayerStamina)
    ADD A, PICKUP_STAMINA_AMT
    JR C, .gsCap
    CP STAMINA_MAX + 1
    JR C, .gsStore
.gsCap:
    LD A, STAMINA_MAX
.gsStore:
    LD (PlayerStamina), A
    RET

; ==============================================================================
; ROULETTE — datos
; ==============================================================================
; RouletteOrder: secuencia de type ids que recorre el ciclado. Tunable por
; el usuario — añadir/quitar/reordenar entries y rebuild. La longitud se
; calcula sola via ROULETTE_ORDER_LEN.
RouletteOrder:
    DEFB ROUL_LIFE
    DEFB ROUL_MUSHROOM
    DEFB ROUL_HEALTH
    DEFB ROUL_CARACOL
    DEFB ROUL_COMPASS
    DEFB ROUL_MUSHROOM
    DEFB ROUL_STAMINA
    DEFB ROUL_RAYO
    DEFB ROUL_CARACOL
RouletteOrderEnd:
ROULETTE_ORDER_LEN  EQU RouletteOrderEnd - RouletteOrder

; RouletteTypePtrs: tabla de lookup type id → BgGfx ptr. Indexada por
; (type-1)*2 — el id 0 esta sin usar (no aparece en RouletteOrder).
RouletteTypePtrs:
    DEFW BgGfx_life                                     ; ROUL_LIFE     = 1
    DEFW BgGfx_health_pickup                            ; ROUL_HEALTH   = 2
    DEFW BgGfx_stamina_pickup                           ; ROUL_STAMINA  = 3
    DEFW BgGfx_pickup_ray                               ; ROUL_RAYO     = 4
    DEFW BgGfx_pickup_snail                             ; ROUL_CARACOL  = 5
    DEFW BgGfx_pickup_mushroom                          ; ROUL_MUSHROOM = 6
    DEFW BgGfx_pickup_compass                           ; ROUL_COMPASS  = 7

; ==============================================================================
; GetRoulettePtrByIdx - dado RouletteIdx, devuelve HL = ptr al sprite actual
; ==============================================================================
; IN:  A = RouletteIdx (0..ROULETTE_ORDER_LEN-1)
; OUT: HL = BgGfx ptr al sprite del tipo activo
; ==============================================================================
GetRoulettePtrByIdx:
    LD HL, RouletteOrder
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = type id (1..5)
    DEC A                                   ; idx 0-based para tabla ptrs
    LD H, 0
    LD L, A
    ADD HL, HL                              ; idx*2 (entries de 2 bytes)
    LD DE, RouletteTypePtrs
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL                               ; HL = ptr
    RET

; ==============================================================================
; LoadSynthSpriteAndExtractAttr - HL=ptr → set RandomSynthPtr, load buffer,
;                                 store first attr byte en RandomSynthAttr.
; ==============================================================================
LoadSynthSpriteAndExtractAttr:
    LD (RandomSynthPtr), HL
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    CALL SkipPixelData                      ; IX @ tintPaper
    INC IX                                  ; @ attr_h
    INC IX                                  ; @ attr_w
    INC IX                                  ; @ attr_data
    LD A, (IX+0)
    LD (RandomSynthAttr), A
    RET

; ==============================================================================
; UpdateRoulette - tick del ciclado de la ruleta (slot 1, MainLoop)
; ==============================================================================
; Llamado cada frame. Si RouletteActive=0, no-op. Si el synth fue recogido
; ($FE en MapX), no-op. En cada paso: erase sprite actual, avanza idx,
; carga sprite nuevo, dibuja, repaint attrs.
; ==============================================================================
UpdateRoulette:
    LD A, (RouletteActive)
    OR A
    RET Z
    LD A, (RandomSynthMapX)
    CP $FE
    RET Z                                   ; recogido / inactivo: no ciclar

    ; Tick frame counter
    LD HL, RouletteFrameCounter
    DEC (HL)
    RET NZ                                  ; aun no toca avanzar

    ; --- Counter expirado: ciclar al siguiente tipo ---
    LD A, ROULETTE_CYCLE_FRAMES
    LD (RouletteFrameCounter), A

    ; Erase sprite actual (XOR redraw del sprite actualmente en RandomSynthPtr).
    LD HL, (RandomSynthPtr)
    LD A, 3
    CALL LoadBgSpriteToBuffer
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR

    ; Avanzar idx con wrap
    LD A, (RouletteIdx)
    INC A
    CP ROULETTE_ORDER_LEN
    JR C, .urWrapOk
    XOR A
.urWrapOk:
    LD (RouletteIdx), A

    ; Lookup nuevo tipo, cargar sprite, extraer attr
    CALL GetRoulettePtrByIdx                ; HL = nuevo ptr
    CALL LoadSynthSpriteAndExtractAttr

    ; Dibujar sprite nuevo
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR

    ; Repaint attrs en VRAM
    JP PaintSynthPickupAttrs                ; tail call

; ==============================================================================
; ApplyRayoBuff - speed boost 1.5x durante 15s + player CYAN | $40
; ==============================================================================
; "Last wins": llamar de nuevo resetea timer + override estado actual.
; ==============================================================================
ApplyRayoBuff:
    LD A, SPEED_BUFF_RAYO_RUN
    LD (PlayerSpeedRun), A
    LD A, SPEED_BUFF_RAYO_FIGHT
    LD (PlayerSpeedFight), A
    LD HL, SPEED_BUFF_RAYO_FRAMES
    LD (SpeedBuffTimer), HL
    LD A, SPEED_BUFF_TYPE_RAYO
    LD (SpeedBuffType), A
    LD A, SPEED_BUFF_RAYO_ATTR
    LD (EntityTable + ENT_ATTR), A
    RET

; ==============================================================================
; ApplyMushroomBuff - bloquea ataque durante MUSHROOM_LOCK_FRAMES + player MAGENTA
; ==============================================================================
; Concurrencia: convive con speed buffs (rayo/caracol). El color magenta
; gana mientras el mushroom timer > 0 (UpdateMushroomBuff corre tras
; UpdateSpeedBuff y sobreescribe ENT_ATTR).
; ==============================================================================
ApplyMushroomBuff:
    LD HL, MUSHROOM_LOCK_FRAMES
    LD (MushroomLockTimer), HL
    LD A, MUSHROOM_LOCK_ATTR
    LD (EntityTable + ENT_ATTR), A
    RET

; ==============================================================================
; UpdateMushroomBuff - tick 16-bit timer; reaplica color cada frame; expira al 0
; ==============================================================================
; Llamado desde MainLoop tras UpdateSpeedBuff. Si timer=0, no-op rapido.
; Mientras timer>0: reescribe player ENT_ATTR a magenta cada frame (gana
; sobre cualquier color de speed buff). Al expirar: si hay speed buff
; activo, lo deja con su color (UpdateSpeedBuff ya lo escribio este frame);
; si no, restaura WHITE | $40.
; ==============================================================================
UpdateMushroomBuff:
    LD HL, (MushroomLockTimer)
    LD A, H
    OR L
    RET Z                               ; sin debuff
    DEC HL
    LD (MushroomLockTimer), HL
    LD A, H
    OR L
    JR NZ, .umbActive
    ; --- Justo expirado: restaurar segun estado de speed buff ---
    LD A, (SpeedBuffType)
    OR A
    RET NZ                              ; speed buff activo: ya pinto color, no tocar
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
    RET
.umbActive:
    LD A, MUSHROOM_LOCK_ATTR
    LD (EntityTable + ENT_ATTR), A
    RET

; ==============================================================================
; ApplyCaracolBuff - speed slow 0.5x durante 10s + player GREEN | $40
; ==============================================================================
ApplyCaracolBuff:
    LD A, SPEED_BUFF_CARACOL_RUN
    LD (PlayerSpeedRun), A
    LD A, SPEED_BUFF_CARACOL_FIGHT
    LD (PlayerSpeedFight), A
    LD HL, SPEED_BUFF_CARACOL_FRAMES
    LD (SpeedBuffTimer), HL
    LD A, SPEED_BUFF_TYPE_CARACOL
    LD (SpeedBuffType), A
    LD A, SPEED_BUFF_CARACOL_ATTR
    LD (EntityTable + ENT_ATTR), A
    RET

; ==============================================================================
; UpdateSpeedBuff - tick 16-bit timer; reaplica color cada frame; expira al 0
; ==============================================================================
; Llamado desde MainLoop tras DrawHealthStaminaHUD. Si SpeedBuffType=NONE,
; no-op rapido. Mientras buff activo: reescribe player ENT_ATTR cada frame
; (defensivo contra otros sistemas que puedan tocar el attr). Al expirar:
; restaura speeds default + ENT_ATTR a WHITE | $40 + type a NONE.
; ==============================================================================
UpdateSpeedBuff:
    LD A, (SpeedBuffType)
    OR A
    RET Z                               ; sin buff activo
    ; Tick 16-bit timer.
    LD HL, (SpeedBuffTimer)
    DEC HL
    LD (SpeedBuffTimer), HL
    LD A, H
    OR L
    JR Z, .usbExpire
    ; Buff aun activo: re-aplicar color player segun tipo.
    LD A, (SpeedBuffType)
    CP SPEED_BUFF_TYPE_RAYO
    JR NZ, .usbCaracol
    LD A, SPEED_BUFF_RAYO_ATTR
    JR .usbWriteAttr
.usbCaracol:
    LD A, SPEED_BUFF_CARACOL_ATTR
.usbWriteAttr:
    LD (EntityTable + ENT_ATTR), A
    RET
.usbExpire:
    ; Buff terminado: reset speeds, type, color player.
    LD A, SPEED_RUN
    LD (PlayerSpeedRun), A
    LD A, SPEED_FIGHT
    LD (PlayerSpeedFight), A
    XOR A
    LD (SpeedBuffType), A
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
    RET

; ==============================================================================
; UpdateRandomPickup - room-enter hook
; ==============================================================================
; Llamado por MainLoop entre CheckScreenTransition y DrawScreen, cada frame.
; Early-out si ScreenDirty=0 (no transition).
;
; En transition:
;   1. Recorre el BG stream de la sala actual (CurrentScreenAddr) buscando
;      placements id=RANDOM_SLOT_MARKER. Acumula (charX, charY) en RandomSlotList.
;   2. Si count > 0: RNG slot, RNG tipo. Si tipo != none, rellena
;      RandomSyntheticEntry con la pickup elegida en la posicion del slot.
;      Si tipo == none o count == 0, marca inactiva ($FE).
;
; Buffer format (CurrentScreenAddr → CurrentScreenBuffer): entries de 4 bytes
; fijos (id, charX, charY, v) terminados con id=$FF.
;
; Destruye AF, BC, DE, HL.
; ==============================================================================
UpdateRandomPickup:
    LD A, (ScreenDirty)
    OR A
    RET Z

    ; --- Default: synthetic entry inactiva (sera reactivada si roll spawneara) ---
    LD A, $FE
    LD (RandomSynthMapX), A
    XOR A
    LD (RouletteActive), A          ; reset roulette state en cada transicion

    ; --- Scan BG stream, build SlotList ---
    XOR A
    LD (RandomSlotCount), A
    LD HL, (CurrentScreenAddr)
.urpScanLoop:
    LD A, (HL)                          ; A = id
    CP $FF
    JR Z, .urpScanDone
    CP RANDOM_SLOT_MARKER
    JR NZ, .urpSkipEntry
    ; Es marker. Cap reached?
    LD A, (RandomSlotCount)
    CP RANDOM_SLOT_MAX
    JR NC, .urpSkipEntry
    ; SlotList[count*2] = charX, [count*2+1] = charY
    INC HL                              ; HL @ charX
    LD B, (HL)                          ; B = charX
    INC HL                              ; HL @ charY
    LD C, (HL)                          ; C = charY
    PUSH HL                             ; save HL @ charY
    ADD A, A                            ; A = count*2
    LD L, A
    LD H, 0
    LD DE, RandomSlotList
    ADD HL, DE
    LD (HL), B                          ; charX
    INC HL
    LD (HL), C                          ; charY
    LD HL, RandomSlotCount
    INC (HL)
    POP HL                              ; HL @ charY
    INC HL                              ; HL @ v
    INC HL                              ; HL @ next id
    JR .urpScanLoop
.urpSkipEntry:
    ; Skip entry: 4 bytes (id, charX, charY, v).
    INC HL : INC HL : INC HL : INC HL
    JR .urpScanLoop
.urpScanDone:

    ; --- count == 0 -> rotar cache (rolled=NONE) y RET ---
    LD A, (RandomSlotCount)
    OR A
    JP Z, .urpZeroAndRotate

    ; --- Cache lookup: ¿newSid coincide con prev? ---
    ; Calcular newSid y comparar contra RP_PrevSid. Hit = volviendo a la sala
    ; inmediatamente anterior; restauramos slot+tipo. Miss = roll fresco.
    LD A, (CurrentScreenY)
    RLCA : RLCA : RLCA : RLCA           ; Y*16
    LD HL, CurrentScreenX
    ADD A, (HL)                         ; A = newSid
    LD B, A                             ; B = newSid (preservar)
    LD A, (RP_PrevSid)
    CP B
    JR NZ, .urpCacheMiss
    ; HIT prev. Validar slot < count.
    LD A, (RP_PrevSlot)
    LD C, A                             ; C = cached slot
    LD A, (RandomSlotCount)
    CP C
    JR Z, .urpCacheMiss                 ; slot >= count: invalid → fresh
    JR C, .urpCacheMiss
    ; Restaurar: usar cached slot + cached rolled.
    LD A, C
    LD (RP_TmpSlot), A
    LD A, (RP_PrevRolled)
    LD (RP_TmpRolled), A
    LD A, C                             ; A = slot
    JP .urpReadSlotAndDispatchCache

.urpCacheMiss:
    LD A, (RandomSlotCount)
    ; --- Pick slot via R mod count ---
    LD B, A                             ; B = count
    LD A, R
.urpModLoop:
    SUB B
    JR NC, .urpModLoop
    ADD A, B                            ; A = R mod count, [0..count-1]
    LD (RP_TmpSlot), A                  ; guardar slot para rotación

    ; --- Read SlotList[A*2] = (charX, charY) ---
    ADD A, A
    LD E, A
    LD D, 0
    LD HL, RandomSlotList
    ADD HL, DE
    LD A, (HL)                          ; charX
    LD (RandomSynthCharX), A
    INC HL
    LD A, (HL)                          ; charY
    LD (RandomSynthCharY), A

    ; --- Roll type usando R XOR SYS_FRAMES ---
    IF DEBUG_FORCE_COMPASS
        ; DEBUG: bypass del roll - siempre compass para test rápido del power-up.
        ; Pone DEBUG_FORCE_COMPASS=0 en constants.asm para volver a distribución normal.
        JP .urpDoCompass
    ENDIF
    IF DEBUG_FORCE_MUSHROOM
        ; DEBUG: bypass del roll - siempre mushroom para probar el debuff.
        JP .urpDoMushroom
    ENDIF
    IF DEBUG_FORCE_ROULETTE
        ; DEBUG: bypass del roll - siempre roulette para probar RouletteOrder.
        JP .urpDoRoulette
    ENDIF
    LD A, R
    LD HL, $5C78
    XOR (HL)
    CP PROB_LIFE_END
    JR C, .urpDoLife
    CP PROB_HEALTH_END
    JR C, .urpDoHealth
    CP PROB_STAMINA_END
    JR C, .urpDoStamina
    CP PROB_RAYO_END
    JR C, .urpDoRayo
    CP PROB_CARACOL_END
    JR C, .urpDoCaracol
    CP PROB_ROULETTE_END
    JR C, .urpDoRoulette
    CP PROB_MUSHROOM_END
    JR C, .urpDoMushroom
    CP PROB_COMPASS_END
    JR C, .urpDoCompass
    JP .urpZeroAndRotate                ; tipo nada, RandomSynthMapX ya esta a $FE

; ==============================================================================
; .urpReadSlotAndDispatchCache — path del cache HIT
; ==============================================================================
; Entrada: A = slot cached, RP_TmpRolled = tipo cached (ya setado).
; Lee SlotList[A*2] → CharX/Y, luego dispatcha al .urpDoXxx correspondiente.
; ROLLED_NONE → JP .urpZeroAndRotate (no spawn pero rota cache).
; ==============================================================================
.urpReadSlotAndDispatchCache:
    ADD A, A
    LD E, A
    LD D, 0
    LD HL, RandomSlotList
    ADD HL, DE
    LD A, (HL)
    LD (RandomSynthCharX), A
    INC HL
    LD A, (HL)
    LD (RandomSynthCharY), A

    LD A, (RP_TmpRolled)
    OR A
    JP Z, .urpZeroAndRotate             ; ROLLED_NONE (consumido) → no spawn
    DEC A
    JP Z, .urpDoLife                    ; ROLLED_LIFE
    DEC A
    JP Z, .urpDoHealth
    DEC A
    JP Z, .urpDoStamina
    DEC A
    JP Z, .urpDoRayo
    DEC A
    JP Z, .urpDoCaracol
    DEC A
    JP Z, .urpDoRoulette
    DEC A
    JP Z, .urpDoMushroom
    JP .urpDoCompass                    ; ROLLED_COMPASS (resto)

.urpDoLife:
    LD A, ROLLED_LIFE
    LD (RP_TmpRolled), A
    LD HL, BgGfx_life
    JR .urpActivate
.urpDoHealth:
    LD A, ROLLED_HEALTH
    LD (RP_TmpRolled), A
    LD HL, BgGfx_health_pickup
    JR .urpActivate
.urpDoStamina:
    LD A, ROLLED_STAMINA
    LD (RP_TmpRolled), A
    LD HL, BgGfx_stamina_pickup
    JR .urpActivate
.urpDoRayo:
    LD A, ROLLED_RAYO
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_ray
    JR .urpActivate
.urpDoCaracol:
    LD A, ROLLED_CARACOL
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_snail
    JR .urpActivate
.urpDoMushroom:
    LD A, ROLLED_MUSHROOM
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_mushroom
    JR .urpActivate
.urpDoCompass:
    LD A, ROLLED_COMPASS
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_compass
    JR .urpActivate
.urpDoRoulette:
    ; Activar modo roulette: idx=0, counter=full, sprite del primer tipo del orden.
    LD A, ROLLED_ROULETTE
    LD (RP_TmpRolled), A
    LD A, 1
    LD (RouletteActive), A
    XOR A
    LD (RouletteIdx), A
    LD A, ROULETTE_CYCLE_FRAMES
    LD (RouletteFrameCounter), A
    XOR A                               ; A = 0 (idx) para GetRoulettePtrByIdx
    CALL GetRoulettePtrByIdx            ; HL = ptr al primer tipo
.urpActivate:
    ; --- Set ptr/attr + cargar sprite + activar entry sintetica ---
    CALL LoadSynthSpriteAndExtractAttr
    LD A, (CurrentScreenX)
    LD (RandomSynthMapX), A             ; activa la entry
    LD A, (CurrentScreenY)
    LD (RandomSynthMapY), A
    LD A, $FF
    LD (RandomSynthTint), A             ; sin tint
    JR .urpRotateAndRet                 ; saltar ZeroAndRotate (TmpSlot/TmpRolled
                                        ; ya están set por .urpDoXxx — no resetear)

; ==============================================================================
; .urpRotateAndRet — al terminar UpdateRandomPickup, rotar cache y RET.
; ==============================================================================
; prev ← cur (data de la sala que dejamos).
; cur  ← (newSid, RP_TmpSlot, RP_TmpRolled) (data de la sala donde estamos).
;
; .urpZeroAndRotate: entrada con rolled=NONE (sin spawn). Setea TmpSlot=0 y
; TmpRolled=0 antes de rotar. NO se llega aquí desde .urpActivate (skipped).
; ==============================================================================
.urpZeroAndRotate:
    XOR A
    LD (RP_TmpSlot), A
    LD (RP_TmpRolled), A
.urpRotateAndRet:
    ; prev ← cur
    LD A, (RP_CurSid)    : LD (RP_PrevSid), A
    LD A, (RP_CurSlot)   : LD (RP_PrevSlot), A
    LD A, (RP_CurRolled) : LD (RP_PrevRolled), A
    ; cur ← (newSid, TmpSlot, TmpRolled)
    LD A, (CurrentScreenY)
    RLCA : RLCA : RLCA : RLCA           ; Y*16
    LD HL, CurrentScreenX
    ADD A, (HL)                         ; A = newSid
    LD (RP_CurSid), A
    LD A, (RP_TmpSlot)   : LD (RP_CurSlot), A
    LD A, (RP_TmpRolled) : LD (RP_CurRolled), A
    RET

; ==============================================================================
; PaintSynthPickupAttrs - Pinta attrs hardcoded del random pickup en VRAM
; ==============================================================================
; Se llama desde:
;   - .pkDrawDone (DrawScreen): tras dibujar pixels del synth.
;   - MainLoop tras RefreshPickupAttrs: para repintar attrs si un enemigo paso
;     por encima y los borro.
;
; Bypass total de tint swap + day/night remap → siempre brillan:
;   life          = $47 (white bright, paper black)
;   health_pickup = $42 (red bright,   paper black)
;   stamina_pickup= $45 (cyan bright,  paper black)
;
; Pickup es 16x16 = 2x2 char attrs.
; Early-out si RandomSynthMapX = $FE (no activo).
; Destruye AF, BC, DE, HL.
; ==============================================================================
PaintSynthPickupAttrs:
    LD A, (RandomSynthMapX)
    CP $FE
    RET Z                               ; no activo
    ; --- Attr byte: leido del sprite al activar (RandomSynthAttr en RAM) ---
    ; Respeta el color que el usuario puso en el BG editor. Bypass del remap
    ; dia/noche garantizado al escribir directo a VRAM (sin DrawBgAttrOnly).
    LD A, (RandomSynthAttr)
    LD C, A                             ; C = attr byte
    ; --- Calcular VRAM addr fila 0 = ATTR_BASE + (charY+BG_Y_OFFSET)*32 + charX ---
    LD A, (RandomSynthCharY)
    ADD A, BG_Y_OFFSET
    LD H, 0
    LD L, A
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; *32
    LD A, (RandomSynthCharX)
    ADD A, L
    LD L, A
    JR NC, .pspaNoCarry
    INC H
.pspaNoCarry:
    LD DE, ATTR_BASE
    ADD HL, DE                          ; HL = VRAM addr fila 0, col 0
    ; --- Escribir 4 attrs (2x2) ---
    LD (HL), C
    INC HL
    LD (HL), C                          ; fila 0
    LD A, L
    ADD A, 31                           ; +32 a fila siguiente, -1 (al col 0)
    LD L, A
    JR NC, .pspaNoCarry2
    INC H
.pspaNoCarry2:
    LD (HL), C
    INC HL
    LD (HL), C                          ; fila 1
    RET

; ==============================================================================
; CheckRandomSyntheticPickup - colision + collect del pickup sintetico
; ==============================================================================
; Llamada por CheckPickupCollect tras procesar PickupTable. Si la entry
; sintetica esta activa, hace AABB contra el player. Si hay hit:
;   - SFX_Pickup
;   - Erase XOR + restore attrs
;   - Mark inactiva ($FE)
;   - Dispatch GiveLife/GiveHealth/GiveStamina segun RandomSynthPtr
; ==============================================================================
CheckRandomSyntheticPickup:
    LD A, (RandomSynthMapX)
    CP $FE
    RET Z                               ; inactiva
    ; Sanity: solo procesar si estamos en su sala (deberia ser asi tras hook).
    LD B, A
    LD A, (CurrentScreenX)
    CP B
    RET NZ
    LD A, (RandomSynthMapY)
    LD B, A
    LD A, (CurrentScreenY)
    CP B
    RET NZ

    ; --- Cargar sprite a BgSpriteBuffer (header + pixels + attrs) ---
    LD HL, (RandomSynthPtr)
    LD A, 3                             ; bank 3
    CALL LoadBgSpriteToBuffer

    ; --- Calcular pk_left, pk_top, pk_width_px, pk_height_px ---
    LD HL, BgSpriteBuffer
    LD A, (HL)                          ; height_px
    LD (.crsPkH+1), A
    INC HL
    LD A, (HL)
    AND $7F                             ; width_bytes (sin flag RLE)
    ADD A, A
    ADD A, A
    ADD A, A                            ; width_px = bytes*8
    LD (.crsPkW+1), A
    LD A, (RandomSynthCharX)
    ADD A, A
    ADD A, A
    ADD A, A                            ; pk_left = charX*8
    LD (.crsPkLeft+1), A
    LD A, (RandomSynthCharY)
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A                            ; pk_top = (charY+BG_Y_OFFSET)*8
    LD (.crsPkTop+1), A

    ; --- AABB: player_right > pk_left AND player_left < pk_right
    ;          AND player_bottom > pk_top AND player_top < pk_bottom ---
    LD A, (EntityTable + ENT_POSX)
    LD (.crsPlX+1), A
.crsPlX:
    LD A, 0                             ; player_left (self-mod)
    ADD A, 16                           ; player_right
.crsPkLeft:
    LD B, 0
    CP B
    RET C                               ; player_right <= pk_left -> miss
    RET Z
.crsPkW:
    LD A, 0                             ; pk_width
    ADD A, B                            ; pk_right
    LD B, A
    LD A, (.crsPlX+1)
    CP B
    RET NC                              ; player_left >= pk_right -> miss

    LD A, (EntityTable + ENT_POSY)
    LD (.crsPlY+1), A
.crsPlY:
    LD A, 0                             ; player_top
    ADD A, 21                           ; player_bottom (player es 21 alto)
.crsPkTop:
    LD B, 0
    CP B
    RET C
    RET Z
.crsPkH:
    LD A, 0                             ; pk_height
    ADD A, B                            ; pk_bottom
    LD B, A
    LD A, (.crsPlY+1)
    CP B
    RET NC                              ; miss

    ; --- HIT detectado, pero saltar si player ya esta al maximo del recurso ---
    ; Identificar tipo via ptr y comparar contra cap. Si A >= cap, RET (sin
    ; SFX ni erase): el pickup queda visible para futuros pasos cuando el
    ; jugador haya gastado el recurso.
    ; Rayo/caracol no son recursos cap-able: siempre aplican (last wins).
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_life
    OR A
    SBC HL, DE
    JR Z, .crsCheckLife
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_health_pickup
    OR A
    SBC HL, DE
    JR Z, .crsCheckHealth
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_stamina_pickup
    OR A
    SBC HL, DE
    JR Z, .crsCheckStamina
    JR .crsApplyHit                     ; rayo/caracol: siempre apply
.crsCheckLife:
    LD A, (PlayerLives)
    CP PLAYER_LIVES_MAX
    RET NC
    JR .crsApplyHit
.crsCheckHealth:
    LD A, (PlayerHealth)
    CP HEALTH_MAX
    RET NC
    JR .crsApplyHit
.crsCheckStamina:
    LD A, (PlayerStamina)
    CP STAMINA_MAX
    RET NC
.crsApplyHit:
    ; --- HIT confirmado: SFX + erase + attrs + apply effect + mark inactive ---
    LD HL, SFX_Pickup
    CALL PlaySFX

    ; Erase: XOR redraw (sprite ya esta en BgSpriteBuffer)
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    POP BC                              ; B=charX, C=charY

    ; Restore attrs: D=height_chars, E=width_chars
    LD HL, BgSpriteBuffer
    LD A, (HL)                          ; height_px
    RRCA : RRCA : RRCA
    AND $1F
    LD D, A
    INC HL
    LD A, (HL)
    AND $7F
    LD E, A
    CALL RestorePickupAttrs

    ; Mark inactive
    LD A, $FE
    LD (RandomSynthMapX), A

    ; Invalidar memoria cache: pickup consumido en esta sala. Al volver
    ; (cache hit en prev) restauraremos rolled=NONE → no respawnea.
    XOR A
    LD (RP_CurRolled), A                ; ROLLED_NONE

    ; Dispatch effect por ptr (life/health/stamina/rayo/caracol)
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_life
    OR A
    SBC HL, DE
    JP Z, GiveLife
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_health_pickup
    OR A
    SBC HL, DE
    JP Z, GiveHealth
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_stamina_pickup
    OR A
    SBC HL, DE
    JP Z, GiveStamina
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_pickup_ray
    OR A
    SBC HL, DE
    JP Z, ApplyRayoBuff
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_pickup_snail
    OR A
    SBC HL, DE
    JP Z, ApplyCaracolBuff
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_pickup_compass
    OR A
    SBC HL, DE
    JP Z, ApplyMagicCompassBuff
    JP ApplyMushroomBuff                ; fallthrough: si no es ningun otro, debe ser mushroom
