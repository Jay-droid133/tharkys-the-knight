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
GiveLifeBody:
    LD A, (PlayerLives)
    CP PLAYER_LIVES_MAX
    RET NC                              ; ya en max (>= MAX) -> no-op
    INC A
    LD (PlayerLives), A
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo del icono HUD para confirmar pickup
    LD (PickupFlashLife), A
    RET

; ==============================================================================
; GiveHealth - +PICKUP_HEALTH_AMT, clamp a HEALTH_MAX
; ==============================================================================
; HUD se refresca solo via DrawHealthStaminaHUD (lee PlayerHealth cada frame).
; ==============================================================================
GiveHealthBody:
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
; GiveStamina - +PICKUP_STAMINA_AMT, clamp a STAMINA_MAX. Cura seta y reverse.
; ==============================================================================
GiveStaminaBody:
    LD A, (PlayerStamina)
    ADD A, PICKUP_STAMINA_AMT
    JR C, .gsCap
    CP STAMINA_MAX + 1
    JR C, .gsStore
.gsCap:
    LD A, STAMINA_MAX
.gsStore:
    LD (PlayerStamina), A
    LD HL, 0
    LD (MushroomLockTimer), HL          ; cura el debuff de la seta al beber stamina
    LD (ReverseTimer), HL               ; y el debuff de controles invertidos
    RET

; ==============================================================================
; ROULETTE — datos (fase 5: por categorias)
; ==============================================================================
; La ruleta cicla 6 caras en orden fijo:
;   ESPECIAL -> MALO -> RECURSO -> MALO -> STATS -> MALO -> (wrap)
; 50% de las caras son MALO -> tension al recoger sin mirar. Cada cara pica
; un item RANDOM dentro de su categoria cada tick (~480ms).
ROULETTE_ORDER_LEN  EQU 6

; Secuencia de las 6 caras (CAT_* enum):
RouletteCatOrder:
    DEFB CAT_ESPECIAL                       ; cara 0
    DEFB CAT_MALO                           ; cara 1
    DEFB CAT_RECURSO                        ; cara 2
    DEFB CAT_MALO                           ; cara 3
    DEFB CAT_STATS                          ; cara 4
    DEFB CAT_MALO                           ; cara 5

; Items por categoria (formato: DEFB count, ROUL_* items...):
RouletteCatEspecial:
    DEFB 4
    DEFB ROUL_LIFE, ROUL_COMPASS, ROUL_ESCUDO_RAYO, ROUL_MAP
RouletteCatMalo:
    DEFB 3
    DEFB ROUL_MUSHROOM, ROUL_CARACOL, ROUL_REVERSE
RouletteCatRecurso:
    DEFB 2
    DEFB ROUL_HEALTH, ROUL_STAMINA
RouletteCatStats:
    DEFB 3
    DEFB ROUL_RAYO, ROUL_ESPADA, ROUL_ESCUDO

; Lookup CAT_* -> cat table ptr (DEFW):
RouletteCatItemTables:
    DEFW RouletteCatEspecial                ; CAT_ESPECIAL = 0
    DEFW RouletteCatMalo                    ; CAT_MALO = 1
    DEFW RouletteCatRecurso                 ; CAT_RECURSO = 2
    DEFW RouletteCatStats                   ; CAT_STATS = 3

; RouletteTypePtrs: lookup ROUL_* (1..11) -> BgGfx canonical ptr.
; HEALTH/STAMINA usan variant pick (PickRandomVariantPtr), no esta tabla.
RouletteTypePtrs:
    DEFW BgGfx_life                                     ; ROUL_LIFE        = 1
    DEFW BgGfx_health_pickup                            ; ROUL_HEALTH      = 2 (unused: variants)
    DEFW BgGfx_stamina_pickup                           ; ROUL_STAMINA     = 3 (unused: variants)
    DEFW BgGfx_pickup_ray                               ; ROUL_RAYO        = 4
    DEFW BgGfx_pickup_snail                             ; ROUL_CARACOL     = 5
    DEFW BgGfx_pickup_mushroom                          ; ROUL_MUSHROOM    = 6
    DEFW BgGfx_pickup_compass                           ; ROUL_COMPASS     = 7
    DEFW BgGfx_pickup_sword                             ; ROUL_ESPADA      = 8
    DEFW BgGfx_pickup_shield                            ; ROUL_ESCUDO      = 9
    DEFW BgGfx_pickup_shield_ray                        ; ROUL_ESCUDO_RAYO = 10
    DEFW BgGfx_pickup_reverse                           ; ROUL_REVERSE     = 11
    DEFW BgGfx_pickup_map                               ; ROUL_MAP         = 12

; ==============================================================================
; GetRoulettePtrByIdx - dado RouletteIdx (0..5), pica un item random de la cat
; ==============================================================================
; IN:  A = RouletteIdx (0..5)
; OUT: HL = BgGfx ptr al sprite picado.
;      Side: RouletteDisplayedType <- ROUL_* picado (para .crsApplyRouletteHit).
; Destruye: AF, BC, DE, HL.
;
; Logica:
;   1. cat = RouletteCatOrder[idx]
;   2. table = RouletteCatItemTables[cat]    (DEFB count, DEFB items...)
;   3. R mod count -> pick. Si pick == ROUL_COMPASS y MagicCompassPermanent
;      activo, re-pica (loop). RouletteCatEspecial tiene 2 items non-compass
;      => terminacion garantizada.
;   4. Store ROUL_* en RouletteDisplayedType.
;   5. Si ROUL_HEALTH / ROUL_STAMINA -> PickRandomVariantPtr (variante random).
;      Resto -> lookup canonical en RouletteTypePtrs.
;
; .grpiCount / .grpiItems: scratch DEFB/DEFW al final de la rutina (bank 7).
; ==============================================================================
GetRoulettePtrByIdx:
    ; --- 1. Resolve cat ptr ---
    LD HL, RouletteCatOrder
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = cat (0..3)
    ADD A, A
    LD E, A
    LD HL, RouletteCatItemTables
    ADD HL, DE
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A                                 ; HL = cat table (count + items)
    LD A, (HL)
    LD (.grpiCount), A                      ; save count en scratch
    INC HL
    LD (.grpiItems), HL                     ; save items ptr en scratch

.grpiPick:
    LD A, (.grpiCount)
    LD B, A
    LD A, R
.grpiMod:
    SUB B
    JR NC, .grpiMod
    ADD A, B                                ; A = R mod count
    LD E, A
    LD D, 0
    LD HL, (.grpiItems)
    ADD HL, DE
    LD A, (HL)                              ; A = ROUL_* picado

    ; --- Skip compass si lasting permanent ---
    LD HL, MagicCompassPermanent
    BIT 0, (HL)
    JR Z, .grpiPicked
    CP ROUL_COMPASS
    JR Z, .grpiPick                         ; compass + permanent -> re-pica

.grpiPicked:
    LD (RouletteDisplayedType), A           ; persistir para dispatcher al recoger

    ; --- Lookup sprite ptr ---
    CP ROUL_HEALTH
    JR Z, .grpiHealth
    CP ROUL_STAMINA
    JR Z, .grpiStamina
    ; Resto: canonical en RouletteTypePtrs[A-1]
    DEC A
    LD H, 0
    LD L, A
    ADD HL, HL
    LD DE, RouletteTypePtrs
    ADD HL, DE
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A                                 ; HL = sprite ptr
    RET
.grpiHealth:
    LD HL, HealthVariantPtrs
    JP PickRandomVariantPtr
.grpiStamina:
    LD HL, StaminaVariantPtrs
    JP PickRandomVariantPtr

; Scratch usado por GetRoulettePtrByIdx (vive en bank 7 con el body):
.grpiCount: DEFB 0
.grpiItems: DEFW 0

; ==============================================================================
; LoadSynthSpriteAndExtractAttr - HL=ptr → set RandomSynthPtr, load buffer,
;                                 store los 4 attr bytes (TL,TR,BL,BR) del 2x2.
; ==============================================================================
; Antes guardaba solo attr[0] (TL) y PaintSynthPickupAttrs lo replicaba a las
; 4 celdas, perdiendo el patrón per-celda del BG editor (ej: col1 bright,
; col2 dim). Ahora extraemos los 4 → preservación 1:1.
; ==============================================================================
LoadSynthSpriteAndExtractAttr:
    LD (RandomSynthPtr), HL
    LD A, 3
    CALL LoadBgSpriteToBuffer_B7
    LD IX, BgSpriteBuffer
    CALL SkipPixelData_B7                      ; IX @ tintPaper
    INC IX                                  ; @ attr_h
    INC IX                                  ; @ attr_w
    INC IX                                  ; @ attr_data[0] = TL
    LD A, (IX+0)
    LD (RandomSynthAttr), A                 ; TL
    LD A, (IX+1)
    LD (RandomSynthAttrTR), A
    LD A, (IX+2)
    LD (RandomSynthAttrBL), A
    LD A, (IX+3)
    LD (RandomSynthAttrBR), A
    RET

; ==============================================================================
; AdvanceRouletteIdx / SkipCompassIfNeeded - INC con wrap mod ROULETTE_ORDER_LEN
; ==============================================================================
; Tras fase 5 (ruleta por categorias), el skip-compass vive en GetRoulettePtrByIdx
; (re-pica dentro de la cat si sale COMPASS + permanent). Aqui solo queda el
; INC + wrap. SkipCompassIfNeeded mantiene su nombre por compatibilidad con
; .urpDoRoulette init (caller).
;
; IN:  A = idx actual (0..ROULETTE_ORDER_LEN-1)
; OUT: A = idx avanzado (mod 6). Para SkipCompassIfNeeded: A sin cambios.
; Destruye: AF.
; ==============================================================================
AdvanceRouletteIdx:
    INC A
    CP ROULETTE_ORDER_LEN
    RET C
    XOR A
    RET
SkipCompassIfNeeded:
    ; No-op: el skip-compass vive en GetRoulettePtrByIdx (re-pick within cat).
    RET

; ==============================================================================
; UpdateRoulette - tick del ciclado de la ruleta (slot 1, MainLoop)
; ==============================================================================
; Llamado cada frame. Si RouletteActive=0, no-op. Si el synth fue recogido
; ($FE en MapX), no-op. En cada paso: erase sprite actual, avanza idx,
; carga sprite nuevo, dibuja, repaint attrs.
; ==============================================================================
UpdateRouletteBody:
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
    CALL LoadBgSpriteToBuffer_B7
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR_B7

    ; Avanzar idx con wrap (AdvanceRouletteIdx skipea ROUL_COMPASS si la
    ; brujula permanente esta activa — no se ve un solo frame de compass).
    LD A, (RouletteIdx)
    CALL AdvanceRouletteIdx
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
    CALL DrawBgSpriteXOR_B7

    ; Repaint attrs en VRAM
    JP PaintSynthPickupAttrsBody            ; tail call (intra-body)

; ==============================================================================
; UpdatePlayerColorCyclerBody - cycler de color player segun buffs activos
; ==============================================================================
; Llamado desde MainLoop cada frame via thunk slot 1 (UpdatePlayerColorCycler).
; Lee timers de buffs/debuffs activos (16-bit cada uno), cuenta cuantos hay,
; cycla entre sus colores cada COLOR_CYCLER_PERIOD frames.
;
; Prioridades (en orden):
;   1. PlayerHitTimer > 0  -> no tocar color (RED damage flash gana)
;   2. >=1 buff activo     -> cyclar entre sus colores
;   3. AttackCooldown > 0  -> no tocar color (BLUE sword cooldown persiste)
;   4. Default             -> escribir WHITE | $40
;
; Orden fijo en el ciclo (afecta cual se ve primero): SpeedBuff (RAYO/CARACOL)
; primero, luego MushroomBuff (SETA). Fase 3/4 anadira ESPADA / ESCUDO / REVERSE.
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
UpdatePlayerColorCyclerBody:
    ; NOTA: el check de PlayerHitTimer vive en el thunk slot 1, NO aqui.
    ; PlayerHitTimer esta en bank 0 (slot 3) y desde bank 7 body slot 3 = bank 7
    ; -> lectura corrupta. El thunk gates el call antes de paginar.

    ; --- Pass 1: contar timers activos ---
    LD B, 0                                 ; B = count
    LD A, (SpeedBuffTimer)
    LD C, A
    LD A, (SpeedBuffTimer+1)
    OR C
    JR Z, .upcc_noSpeed
    INC B
.upcc_noSpeed:
    LD A, (MushroomLockTimer)
    LD C, A
    LD A, (MushroomLockTimer+1)
    OR C
    JR Z, .upcc_noMush
    INC B
.upcc_noMush:
    LD A, (EspadaTimer)
    LD C, A
    LD A, (EspadaTimer+1)
    OR C
    JR Z, .upcc_noEspada
    INC B
.upcc_noEspada:
    LD A, (EscudoTimer)
    LD C, A
    LD A, (EscudoTimer+1)
    OR C
    JR Z, .upcc_noEscudo
    INC B
.upcc_noEscudo:
    LD A, (ReverseTimer)
    LD C, A
    LD A, (ReverseTimer+1)
    OR C
    JR Z, .upcc_noReverse
    INC B
.upcc_noReverse:

    LD A, B
    OR A
    JR NZ, .upcc_haveBuffs

    ; --- Sin buffs. Prioridad 3: cooldown de espada = MAGENTA bright ---
    LD A, (AttackCooldown)
    OR A
    JR Z, .upcc_default
    LD A, MAGENTA | $40                     ; $43 magenta bright (cooldown)
    LD (EntityTable + ENT_ATTR), A
    RET

.upcc_default:
    ; --- Default: WHITE | $40 ---
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
    RET

.upcc_haveBuffs:
    ; --- Increment frame counter (wrap natural a 256) ---
    LD HL, PlayerColorCyclerFrame
    INC (HL)

    ; --- Slot = (frame / COLOR_CYCLER_PERIOD) mod B ---
    LD A, (HL)
    LD D, 0                                 ; D = quotient (frame / PERIOD)
.upcc_divLoop:
    SUB COLOR_CYCLER_PERIOD
    JR C, .upcc_divDone
    INC D
    JR .upcc_divLoop
.upcc_divDone:
    ; D = floor(frame / PERIOD). Mod B:
    LD A, D
.upcc_modLoop:
    SUB B
    JR NC, .upcc_modLoop
    ADD A, B                                ; A = slot (0..B-1)
    LD D, A                                 ; D = target slot

    ; --- Pass 2: iterar buffs en orden fijo, aplicar color del slot-th ---
    LD C, 0                                 ; running count

    ; SpeedBuff (RAYO o CARACOL)
    LD A, (SpeedBuffTimer)
    LD E, A
    LD A, (SpeedBuffTimer+1)
    OR E
    JR Z, .upcc_skipSpeed
    LD A, D
    CP C
    JR Z, .upcc_applySpeed
    INC C
.upcc_skipSpeed:

    ; MushroomBuff (SETA)
    LD A, (MushroomLockTimer)
    LD E, A
    LD A, (MushroomLockTimer+1)
    OR E
    JR Z, .upcc_skipMush
    LD A, D
    CP C
    JR Z, .upcc_applyMush
    INC C
.upcc_skipMush:

    ; Espada
    LD A, (EspadaTimer)
    LD E, A
    LD A, (EspadaTimer+1)
    OR E
    JR Z, .upcc_skipEspada
    LD A, D
    CP C
    JR Z, .upcc_applyEspada
    INC C
.upcc_skipEspada:

    ; Escudo
    LD A, (EscudoTimer)
    LD E, A
    LD A, (EscudoTimer+1)
    OR E
    JR Z, .upcc_skipEscudo
    LD A, D
    CP C
    JR Z, .upcc_applyEscudo
    INC C
.upcc_skipEscudo:

    ; Reverse
    LD A, (ReverseTimer)
    LD E, A
    LD A, (ReverseTimer+1)
    OR E
    JR Z, .upcc_skipReverse
    LD A, D
    CP C
    JR Z, .upcc_applyReverse
    INC C
.upcc_skipReverse:

    RET                                     ; unreachable si pass 1 fue correcto

.upcc_applyEspada:
    LD A, ESPADA_BUFF_ATTR                  ; $42 red bright
    JR .upcc_writeAttr

.upcc_applyEscudo:
    LD A, ESCUDO_BUFF_ATTR                  ; $46 yellow bright
    JR .upcc_writeAttr

.upcc_applyReverse:
    LD A, REVERSE_BUFF_ATTR                 ; $41 blue bright
    JR .upcc_writeAttr

.upcc_applySpeed:
    LD A, (SpeedBuffType)
    CP SPEED_BUFF_TYPE_RAYO
    LD A, SPEED_BUFF_RAYO_ATTR              ; $45 cyan bright
    JR Z, .upcc_writeAttr
    LD A, SPEED_BUFF_CARACOL_ATTR           ; $44 green bright
    JR .upcc_writeAttr

.upcc_applyMush:
    LD A, MUSHROOM_LOCK_ATTR                ; $43 magenta bright

.upcc_writeAttr:
    LD (EntityTable + ENT_ATTR), A
    RET

; ==============================================================================
; ApplyRayoBuff - speed boost 1.5x durante 15s (color via cycler)
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
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo del icono HUD para confirmar pickup
    LD (PickupFlashRayo), A
    ; (color player lo pinta UpdatePlayerColorCycler segun timer activo)
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
    ; Antagonista 'last wins': SETA cancela ESPADA (ambos tocan can-attack).
    LD HL, 0
    LD (EspadaTimer), HL
    ; (color player lo pinta UpdatePlayerColorCycler segun timer activo)
    ; Comer toxina alimenta: +PICKUP_HEALTH_AMT HP (mismo que pickup salud).
    ; El debuff se mantiene; risk/reward — comer una seta cuando estas apurado
    ; te salva del hambre pero te jode el ataque 5 s.
    JP GiveHealthBody                   ; tail-call (mismo bank 7)

; ==============================================================================
; UpdateMushroomBuff - tick 16-bit timer; reaplica color cada frame; expira al 0
; ==============================================================================
; Llamado desde MainLoop tras UpdateSpeedBuff. Si timer=0, no-op rapido.
; Mientras timer>0: reescribe player ENT_ATTR a magenta cada frame (gana
; sobre cualquier color de speed buff). Al expirar: si hay speed buff
; activo, lo deja con su color (UpdateSpeedBuff ya lo escribio este frame);
; si no, restaura WHITE | $40.
; ==============================================================================
UpdateMushroomBuffBody:
    LD HL, (MushroomLockTimer)
    LD A, H
    OR L
    RET Z                               ; sin debuff
    DEC HL
    LD (MushroomLockTimer), HL
    RET                                 ; (color lo pinta el cycler segun timer)

; ==============================================================================
; ApplyEspadaBuff - ESPADA (no consume stamina + ataca a 0 + cancela cooldown)
; ==============================================================================
; Duracion: ESPADA_BUFF_FRAMES (12s). Player rojo bright (color via cycler).
; Antagonista 'last wins' con SETA — cancela MushroomLockTimer al activarse.
; Gates en logic_game.asm: SelectSwordMode fuerza mode 2, stamina drain skip,
; AttackCooldown set skip.
; ==============================================================================
ApplyEspadaBuff:
    LD HL, ESPADA_BUFF_FRAMES
    LD (EspadaTimer), HL
    LD HL, 0
    LD (MushroomLockTimer), HL          ; antagonista last wins
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo del icono HUD para confirmar pickup
    LD (PickupFlashEspada), A
    RET

; ==============================================================================
; UpdateEspadaBuffBody - tick 16-bit EspadaTimer
; ==============================================================================
UpdateEspadaBuffBody:
    LD HL, (EspadaTimer)
    LD A, H
    OR L
    RET Z
    DEC HL
    LD (EspadaTimer), HL
    RET                                 ; (color via cycler, gates via logic_game)

; ==============================================================================
; ApplyEscudoBuff - ESCUDO (invuln nasti/monster, knockback persiste)
; ==============================================================================
; Duracion: ESCUDO_BUFF_FRAMES (15s). Player amarillo bright (color via cycler).
; Gate en CheckPlayerEnemyCollision: skip HP decrement si EscudoTimer > 0.
; ==============================================================================
ApplyEscudoBuff:
    LD HL, ESCUDO_BUFF_FRAMES
    LD (EscudoTimer), HL
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo del icono HUD para confirmar pickup
    LD (PickupFlashEscudo), A
    RET

; ==============================================================================
; UpdateEscudoBuffBody - tick 16-bit EscudoTimer
; ==============================================================================
UpdateEscudoBuffBody:
    LD HL, (EscudoTimer)
    LD A, H
    OR L
    RET Z
    DEC HL
    LD (EscudoTimer), HL
    RET

; ==============================================================================
; ApplyEscudoRayoBuff - combo ESCUDO + RAYO (atajo)
; ==============================================================================
; Es un solo pickup raro (categoria 'Especiales') que setea ambos timers a su
; duracion completa. El cycler ve dos timers activos -> cycla CYAN + YELLOW.
; ==============================================================================
ApplyEscudoRayoBuff:
    LD HL, ESCUDO_BUFF_FRAMES
    LD (EscudoTimer), HL
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo iconos HUD (rayo lo setea ApplyRayoBuff)
    LD (PickupFlashEscudo), A
    JP ApplyRayoBuff                    ; tail call intra-body (set RAYO timer + type + flash)

; ==============================================================================
; ApplyReverseBuff - REVERSE (controles Q<->A, O<->P invertidos durante 7s)
; ==============================================================================
; Player azul oscuro bright (color via cycler). Sin antagonistas — REVERSE
; no comparte eje con ningun otro buff (toca solo input direction).
; Gate en ReadInput de logic_game.asm: swap bits N<->S y E<->W si timer > 0.
; ==============================================================================
ApplyReverseBuff:
    LD HL, REVERSE_BUFF_FRAMES
    LD (ReverseTimer), HL
    ; Toxina alimenta (ver ApplyMushroomBuff).
    JP GiveHealthBody                   ; tail-call (mismo bank 7)

; ==============================================================================
; UpdateReverseBuffBody - tick 16-bit ReverseTimer
; ==============================================================================
UpdateReverseBuffBody:
    LD HL, (ReverseTimer)
    LD A, H
    OR L
    RET Z
    DEC HL
    LD (ReverseTimer), HL
    RET                                 ; (color via cycler, gate via ReadInput)

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
    ; (color player lo pinta UpdatePlayerColorCycler segun timer activo)
    ; Toxina alimenta (ver ApplyMushroomBuff).
    JP GiveHealthBody                   ; tail-call (mismo bank 7)

; ==============================================================================
; UpdateSpeedBuff - tick 16-bit timer; reaplica color cada frame; expira al 0
; ==============================================================================
; Llamado desde MainLoop tras DrawHealthStaminaHUD. Si SpeedBuffType=NONE,
; no-op rapido. Mientras buff activo: reescribe player ENT_ATTR cada frame
; (defensivo contra otros sistemas que puedan tocar el attr). Al expirar:
; restaura speeds default + ENT_ATTR a WHITE | $40 + type a NONE.
; ==============================================================================
UpdateSpeedBuffBody:
    LD A, (SpeedBuffType)
    OR A
    RET Z                               ; sin buff activo
    ; Tick 16-bit timer.
    LD HL, (SpeedBuffTimer)
    DEC HL
    LD (SpeedBuffTimer), HL
    LD A, H
    OR L
    RET NZ                              ; buff aun activo (color via cycler)
    ; Buff terminado: reset speeds + clear type. Color lo pinta el cycler.
    LD A, SPEED_RUN
    LD (PlayerSpeedRun), A
    LD A, SPEED_FIGHT
    LD (PlayerSpeedFight), A
    XOR A
    LD (SpeedBuffType), A
    ; --- Snap PlayerPOSY/POSX a mod 4 = 0 (fail-safe alignment) ----------
    ; Razón: durante SPEED_RUN=4 vanilla, Y/X mod 8 oscilan SOLO en {0, 4}.
    ; Los buffs RAYO (6 px/frame) y CARACOL (2 px/frame) pueden dejar Y/X
    ; en mod 8 ∈ {2, 6} — valores que el juego no espera. En esos offsets
    ; el attr-paint del player (calc EntityAttrH = (Y%8 + 21 + 7) / 8) cubre
    ; 4 char rows con solo 1-3 px de cobertura en el último, pisando la
    ; fila superior del BG sprite justo debajo de los pies (síntoma "punta
    ; de pies invade attrs del BG"). Las transiciones de sala preservan Y
    ; literalmente, así que el bug sobrevive cualquier cantidad de cruces
    ; hasta que se vuelva a alinear. Snap a mod 4 = 0 (= AND $FC) restaura
    ; el set seguro {0, 4} en el siguiente paso de SPEED_RUN.
    LD A, (EntityTable + ENT_POSY)
    AND $FC
    LD (EntityTable + ENT_POSY), A
    LD A, (EntityTable + ENT_POSX)
    AND $FC
    LD (EntityTable + ENT_POSX), A
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
UpdateRandomPickupBody:
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

    ; --- Cache lookup: ¿newSid coincide con cur (same-room) o con prev? ---
    ; same-room: ScreenDirty=1 sin transicion real (e.g. tras cerrar minimap).
    ;   Copiamos Cur->Prev y caemos al flow hit-prev para restore identico.
    ; hit-prev: volviendo a la sala inmediatamente anterior; restauramos
    ;   slot+tipo. Miss = roll fresco.
    LD A, (CurrentScreenY)
    RLCA : RLCA : RLCA : RLCA           ; Y*16
    LD HL, CurrentScreenX
    ADD A, (HL)                         ; A = newSid
    LD B, A                             ; B = newSid (preservar)
    LD A, (RP_CurSid)
    CP B
    JR Z, .urpSameRoom
    LD A, (RP_PrevSid)
    CP B
    JR NZ, .urpCacheMiss
.urpHitPrev:
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

.urpSameRoom:
    ; ScreenDirty=1 pero seguimos en la misma sala (tras cerrar minimap).
    ; Copia Cur -> Prev para que el flow hit-prev de abajo restaure el state
    ; identico. Tras .urpRotateAndRet, prev y cur quedan iguales (idempotente).
    LD A, (RP_CurSid)     : LD (RP_PrevSid), A
    LD A, (RP_CurSlot)    : LD (RP_PrevSlot), A
    LD A, (RP_CurRolled)  : LD (RP_PrevRolled), A
    LD A, (RP_CurVariant) : LD (RP_PrevVariant), A
    JR .urpHitPrev

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
    IF DEBUG_FORCE_MAP
        ; DEBUG: bypass del roll - siempre MAP para probar el minimapa timed.
        JP .urpDoMap
    ENDIF
    IF DEBUG_FORCE_COLOR_CHANGER
        ; DEBUG: rotar entre RAYO/CARACOL/MUSHROOM al 33% para testar el color
        ; cycler. R XOR SYS_FRAMES da pseudo-random uniform 0..255, partido en
        ; 3 bandas de 85.3 c/u.
        LD A, R
        LD HL, $5C78
        XOR (HL)
        CP 85
        JP C, .urpDoRayo
        CP 170
        JP C, .urpDoCaracol
        JP .urpDoMushroom
    ENDIF
    IF DEBUG_FORCE_NEW_BUFFS
        ; DEBUG: rotar entre ESPADA/ESCUDO/ESCUDO_RAYO al 33% para testar
        ; fase 3 (buffs nuevos).
        LD A, R
        LD HL, $5C78
        XOR (HL)
        CP 85
        JP C, .urpDoEspada
        CP 170
        JP C, .urpDoEscudo
        JP .urpDoEscudoRayo
    ENDIF
    IF DEBUG_FORCE_REVERSE
        ; DEBUG: forzar siempre REVERSE para testar fase 4.
        JP .urpDoReverse
    ENDIF
    IF DEBUG_FORCE_TICK_PICKUPS
        ; DEBUG: solo buffs positivos + compass (25% cada uno) para probar
        ; los tics del beeper (beeper_ticks.asm).
        LD A, R
        LD HL, $5C78
        XOR (HL)
        CP 64
        JP C, .urpDoRayo
        CP 128
        JP C, .urpDoEspada
        CP 192
        JP C, .urpDoEscudo
        JP .urpDoCompass
    ENDIF
    IF DEBUG_FORCE_LIFE
        ; DEBUG: forzar siempre LIFE para testar HUD flash de vidas extras.
        JP .urpDoLife
    ENDIF
    LD A, R
    LD HL, $5C78
    XOR (HL)
    ; Bands cumulativos. Orden de chequeo en codigo NO afecta las
    ; probabilidades — solo importa los valores de PROB_*_END. Aqui van
    ; agrupados por categoria (Recursos, Especiales, Buffs, Debuffs, Meta).
    ; JP C (no JR C) por rango con cache hit dispatch.
    ; --- Recursos ---
    CP PROB_HEALTH_END         : JP C, .urpDoHealth
    CP PROB_STAMINA_END        : JP C, .urpDoStamina
    ; --- Especiales ---
    CP PROB_LIFE_END           : JP C, .urpDoLife
    CP PROB_COMPASS_END        : JP C, .urpDoCompass
    CP PROB_ESCUDORAYO_END     : JP C, .urpDoEscudoRayo
    CP PROB_MAP_END            : JP C, .urpDoMap
    ; --- Buffs ---
    CP PROB_RAYO_END           : JP C, .urpDoRayo
    CP PROB_ESPADA_END         : JP C, .urpDoEspada
    CP PROB_ESCUDO_END         : JP C, .urpDoEscudo
    ; --- Debuffs ---
    CP PROB_MUSHROOM_END       : JP C, .urpDoMushroom
    CP PROB_CARACOL_END        : JP C, .urpDoCaracol
    CP PROB_REVERSE_END        : JP C, .urpDoReverse
    ; --- Meta ---
    CP PROB_ROULETTE_END       : JP C, .urpDoRoulette
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
    JR Z, .urpDoHealthFromCache         ; ROLLED_HEALTH: reusa variant cacheada
    DEC A
    JR Z, .urpDoStaminaFromCache        ; ROLLED_STAMINA: reusa variant cacheada
    DEC A
    JP Z, .urpDoRayo
    DEC A
    JP Z, .urpDoCaracol
    DEC A
    JP Z, .urpDoRoulette
    DEC A
    JP Z, .urpDoMushroom
    DEC A
    JP Z, .urpDoCompass                 ; ROLLED_COMPASS
    DEC A
    JP Z, .urpDoEspada                  ; ROLLED_ESPADA
    DEC A
    JP Z, .urpDoEscudo                  ; ROLLED_ESCUDO
    DEC A
    JP Z, .urpDoEscudoRayo              ; ROLLED_ESCUDO_RAYO
    DEC A
    JP Z, .urpDoReverse                 ; ROLLED_REVERSE
    JP .urpDoMap                        ; ROLLED_MAP (resto)

; ==============================================================================
; .urpDoHealthFromCache / .urpDoStaminaFromCache - cache hit path
; ==============================================================================
; Llamadas solo desde .urpReadSlotAndDispatchCache. Restauran la variante exacta
; que el player vio la última vez en esta sala (vía RP_PrevVariant) en lugar de
; re-rollear con PickRandomVariantPtr. El usuario ve consistencia visual.
;
; Comparten .urpDoVariantFromCache: HL ya cargado con la tabla, A con ROLLED_*.
; ==============================================================================
.urpDoHealthFromCache:
    LD A, ROLLED_HEALTH
    LD HL, HealthVariantPtrs
    JR .urpDoVariantFromCache
.urpDoStaminaFromCache:
    LD A, ROLLED_STAMINA
    LD HL, StaminaVariantPtrs
.urpDoVariantFromCache:
    LD (RP_TmpRolled), A
    LD A, (RP_PrevVariant)
    LD (RP_TmpVariant), A               ; restore: la próxima rotación lo lleva a Cur
    CALL LookupVariantPtrByIdx          ; HL = tabla, A = idx → HL = sprite ptr
    JP .urpActivate

.urpDoLife:
    LD A, ROLLED_LIFE
    LD (RP_TmpRolled), A
    LD HL, BgGfx_life
    JP .urpActivate
.urpDoHealth:
    LD A, ROLLED_HEALTH
    LD (RP_TmpRolled), A
    LD HL, HealthVariantPtrs             ; variantes 72/74/75/254
    CALL PickRandomVariantPtr             ; OUT: HL = sprite ptr (raw)
    JP .urpActivate
.urpDoStamina:
    LD A, ROLLED_STAMINA
    LD (RP_TmpRolled), A
    LD HL, StaminaVariantPtrs            ; variantes 73/255
    CALL PickRandomVariantPtr
    JP .urpActivate
.urpDoRayo:
    LD A, ROLLED_RAYO
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_ray
    JP .urpActivate
.urpDoCaracol:
    LD A, ROLLED_CARACOL
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_snail
    JP .urpActivate
.urpDoMushroom:
    LD A, ROLLED_MUSHROOM
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_mushroom
    JP .urpActivate
.urpDoCompass:
    LD A, ROLLED_COMPASS
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_compass
    JP .urpActivate
.urpDoEspada:
    LD A, ROLLED_ESPADA
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_sword
    JP .urpActivate
.urpDoEscudo:
    LD A, ROLLED_ESCUDO
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_shield
    JP .urpActivate
.urpDoEscudoRayo:
    LD A, ROLLED_ESCUDO_RAYO
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_shield_ray
    JP .urpActivate
.urpDoReverse:
    LD A, ROLLED_REVERSE
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_reverse
    JP .urpActivate
.urpDoMap:
    LD A, ROLLED_MAP
    LD (RP_TmpRolled), A
    LD HL, BgGfx_pickup_map
    JP .urpActivate
.urpDoRoulette:
    ; Activar modo roulette: idx random, counter=full, sprite del tipo elegido.
    ; El idx inicial se aleatoriza con R mod ROULETTE_ORDER_LEN para que cada
    ; activacion empiece en un punto distinto del ciclo (antes siempre LIFE).
    ; Tras el primer tick, UpdateRoulette sigue el orden preestablecido normal.
    LD A, ROLLED_ROULETTE
    LD (RP_TmpRolled), A
    LD A, 1
    LD (RouletteActive), A
    ; --- Random initial idx: R mod ROULETTE_ORDER_LEN ---
    LD A, R
    LD B, ROULETTE_ORDER_LEN
.urpRouletteModLoop:
    SUB B
    JR NC, .urpRouletteModLoop
    ADD A, B                            ; A = R mod ORDER_LEN (0..N-1)
    CALL SkipCompassIfNeeded            ; si idx cae en COMPASS y lasting activo, avanza
    LD (RouletteIdx), A
    LD B, A                             ; B = idx para GetRoulettePtrByIdx
    LD A, ROULETTE_CYCLE_FRAMES
    LD (RouletteFrameCounter), A
    LD A, B
    CALL GetRoulettePtrByIdx            ; HL = ptr al tipo random elegido
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
    LD A, (RP_CurSid)     : LD (RP_PrevSid), A
    LD A, (RP_CurSlot)    : LD (RP_PrevSlot), A
    LD A, (RP_CurRolled)  : LD (RP_PrevRolled), A
    LD A, (RP_CurVariant) : LD (RP_PrevVariant), A
    ; cur ← (newSid, TmpSlot, TmpRolled, TmpVariant)
    LD A, (CurrentScreenY)
    RLCA : RLCA : RLCA : RLCA           ; Y*16
    LD HL, CurrentScreenX
    ADD A, (HL)                         ; A = newSid
    LD (RP_CurSid), A
    LD A, (RP_TmpSlot)    : LD (RP_CurSlot), A
    LD A, (RP_TmpRolled)  : LD (RP_CurRolled), A
    LD A, (RP_TmpVariant) : LD (RP_CurVariant), A
    RET

; ==============================================================================
; PaintSynthPickupAttrs - Pinta attrs hardcoded del random pickup en VRAM
; ==============================================================================
; Se llama desde:
;   - .pkDrawDone (DrawScreen): tras dibujar pixels del synth.
;   - MainLoop tras RefreshPickupAttrs: para repintar attrs si un enemigo paso
;     por encima y los borro.
;
; Bypass total del day/night remap → respeta exactamente el patrón per-celda
; que el BG editor exporta (ej: col1 bright + col2 dim). Lee los 4 attrs
; ya extraídos por LoadSynthSpriteAndExtractAttr (RandomSynthAttr=TL,
; RandomSynthAttrTR, RandomSynthAttrBL, RandomSynthAttrBR) y los pinta
; 1:1 en VRAM.
;
; Pickup es 16x16 = 2x2 char attrs.
; Early-out si RandomSynthMapX = $FE (no activo).
; Destruye AF, BC, DE, HL.
; ==============================================================================
PaintSynthPickupAttrsBody:
    LD A, (RandomSynthMapX)
    CP $FE
    RET Z                               ; no activo
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
    ; --- Fila 0: TL, TR ---
    LD A, (RandomSynthAttr)             ; TL
    LD (HL), A
    INC HL
    LD A, (RandomSynthAttrTR)
    LD (HL), A
    ; --- Avanzar a fila 1 col 0: +32 desde col 1 → +31 ---
    LD A, L
    ADD A, 31
    LD L, A
    JR NC, .pspaNoCarry2
    INC H
.pspaNoCarry2:
    ; --- Fila 1: BL, BR ---
    LD A, (RandomSynthAttrBL)
    LD (HL), A
    INC HL
    LD A, (RandomSynthAttrBR)
    LD (HL), A
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
CheckRandomSyntheticPickupBody:
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
    CALL LoadBgSpriteToBuffer_B7

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
    ; Identificar tipo via RP_CurRolled (semantico, no por ptr) y comparar
    ; contra cap. Si A >= cap, RET (sin SFX ni erase): el pickup queda
    ; visible para cuando el jugador haya gastado el recurso.
    ; Rayo/caracol/mushroom/compass no son cap-able: siempre aplican.
    ;
    ; Antes esto se hacia comparando RandomSynthPtr contra BgGfx_health_pickup
    ; / BgGfx_stamina_pickup. Ahora hay variantes (ids 72/74/254 health,
    ; 73/255 stamina) elegidas al azar por .urpDoHealth/.urpDoStamina; el
    ; ptr varia pero RP_CurRolled mantiene la semantica.
    LD A, (RP_CurRolled)
    CP ROLLED_LIFE
    JR Z, .crsCheckLife
    CP ROLLED_HEALTH
    JR Z, .crsCheckHealth
    CP ROLLED_STAMINA
    JR Z, .crsCheckStamina
    JR .crsApplyHit                     ; rayo/caracol/mushroom/compass: siempre apply
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
    ; --- HIT confirmado: SFX por categoria + erase + attrs + apply + inactive ---
    ; SFX tier:
    ;   Especiales (LIFE/COMPASS/ESCUDO_RAYO) -> AY sweep agudo (compass pickup)
    ;   Debuffs    (SETA/CARACOL/REVERSE)     -> SFX_BadPickup (ding descendente)
    ;   Resto                                 -> SFX_Pickup (ding ascendente)
    LD A, (RP_CurRolled)
    CP ROLLED_ROULETTE
    JR Z, .crsCheckRouletteSfx
    ; --- Dispatch directo via ROLLED_* ---
    ; Debuffs: SETA + CARACOL + REVERSE
    CP ROLLED_MUSHROOM      : JR Z, .crsBadSfx
    CP ROLLED_CARACOL       : JR Z, .crsBadSfx
    CP ROLLED_REVERSE       : JR Z, .crsBadSfx
    ; Especiales: LIFE + COMPASS + ESCUDO_RAYO + MAP
    CP ROLLED_LIFE          : JR Z, .crsSpecialSfx
    CP ROLLED_COMPASS       : JR Z, .crsSpecialSfx
    CP ROLLED_ESCUDO_RAYO   : JR Z, .crsSpecialSfx
    CP ROLLED_MAP           : JR Z, .crsSpecialSfx
    JR .crsGoodSfx
.crsCheckRouletteSfx:
    ; --- Dispatch via tipo actualmente mostrado por la ruleta (ROUL_*) ---
    LD A, (RouletteDisplayedType)
    CP ROUL_MUSHROOM        : JR Z, .crsBadSfx
    CP ROUL_CARACOL         : JR Z, .crsBadSfx
    CP ROUL_REVERSE         : JR Z, .crsBadSfx
    CP ROUL_LIFE            : JR Z, .crsSpecialSfx
    CP ROUL_COMPASS         : JR Z, .crsSpecialSfx
    CP ROUL_ESCUDO_RAYO     : JR Z, .crsSpecialSfx
    CP ROUL_MAP             : JR Z, .crsSpecialSfx
.crsGoodSfx:
    LD HL, SFX_Pickup
    CALL PlaySFX_B7
    JR .crsAfterSfx
.crsSpecialSfx:
    ; AY_PlayCompassPickup vive en slot 1 (always-visible). CALL directo desde
    ; bank 7 body — la rutina toca solo AY hw + state slot 1, no requiere paging.
    ; Esta es la unica call al SFX desde el random pickup. ApplyMagicCompassBuff
    ; (que se dispatcha despues via ROLLED_COMPASS) ya NO dispara AY_Play* —
    ; un segundo AY_PlaySFX back-to-back enmudecia el canal silenciosamente.
    CALL AY_PlayCompassPickup
    JR .crsAfterSfx
.crsBadSfx:
    LD HL, SFX_BadPickup
    CALL PlaySFX_B7
.crsAfterSfx:

    ; Erase: XOR redraw (sprite ya esta en BgSpriteBuffer)
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR_B7
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
    CALL RestorePickupAttrs_B7

    ; Mark inactive
    LD A, $FE
    LD (RandomSynthMapX), A

    ; Dispatch semantico via RP_CurRolled. Guardamos su valor ANTES de
    ; resetear (la lista de variantes de health/stamina hace que el ptr
    ; ya no sea univoco para identificar el tipo).
    LD A, (RP_CurRolled)
    LD B, A                             ; B = rolled type saved
    ; Invalidar memoria cache: pickup consumido en esta sala. Al volver
    ; (cache hit en prev) restauraremos rolled=NONE → no respawnea.
    XOR A
    LD (RP_CurRolled), A                ; ROLLED_NONE

    ; Dispatch effect via saved rolled type
    LD A, B
    CP ROLLED_ROULETTE      : JR Z, .crsApplyRouletteHit
    CP ROLLED_LIFE          : JP Z, GiveLifeBody
    CP ROLLED_HEALTH        : JP Z, GiveHealthBody
    CP ROLLED_STAMINA       : JP Z, GiveStaminaBody
    CP ROLLED_RAYO          : JP Z, ApplyRayoBuff
    CP ROLLED_CARACOL       : JP Z, ApplyCaracolBuff
    CP ROLLED_COMPASS       : JP Z, ApplyMagicCompassBuff_B7
    CP ROLLED_MUSHROOM      : JP Z, ApplyMushroomBuff
    CP ROLLED_ESPADA        : JP Z, ApplyEspadaBuff
    CP ROLLED_ESCUDO        : JP Z, ApplyEscudoBuff
    CP ROLLED_ESCUDO_RAYO   : JP Z, ApplyEscudoRayoBuff
    CP ROLLED_REVERSE       : JP Z, ApplyReverseBuff
    CP ROLLED_MAP           : JP Z, ApplyMapPickup_B7
    JP ApplyMushroomBuff                ; fallthrough defensivo

.crsApplyRouletteHit:
    ; ROLLED_ROULETTE: el "tipo final" es el que esta mostrandose cuando el
    ; player recoge. GetRoulettePtrByIdx lo persiste cada tick en
    ; RouletteDisplayedType. Aqui se lee y dispatcha por ROUL_*.
    ; Ojo: ROUL_* != ROLLED_* en varios slots -> dispatch directo por ROUL_*.
    LD A, (RouletteDisplayedType)
    CP ROUL_LIFE          : JP Z, GiveLifeBody
    CP ROUL_HEALTH        : JP Z, GiveHealthBody
    CP ROUL_STAMINA       : JP Z, GiveStaminaBody
    CP ROUL_RAYO          : JP Z, ApplyRayoBuff
    CP ROUL_CARACOL       : JP Z, ApplyCaracolBuff
    CP ROUL_MUSHROOM      : JP Z, ApplyMushroomBuff
    CP ROUL_COMPASS       : JP Z, ApplyMagicCompassBuff_B7
    CP ROUL_ESPADA        : JP Z, ApplyEspadaBuff
    CP ROUL_ESCUDO        : JP Z, ApplyEscudoBuff
    CP ROUL_ESCUDO_RAYO   : JP Z, ApplyEscudoRayoBuff
    CP ROUL_REVERSE       : JP Z, ApplyReverseBuff
    CP ROUL_MAP           : JP Z, ApplyMapPickup_B7
    RET                                 ; tipo desconocido: no-op

; ==============================================================================
; Variantes random de health/stamina pickup
; ==============================================================================
; Cuando el roll selecciona health o stamina, .urpDoHealth/.urpDoStamina
; eligen una variante visual al azar. Asi el random pickup tiene mas
; variedad. El efecto (cura salud/stamina) es el mismo regardless de
; variante — solo cambia el sprite que se ve.
;
; Formato tabla: DEFB count, ids... (1 byte por id)
; Cada id se resuelve a sprite ptr via BgGfxPtrById en runtime.
; ==============================================================================
; --- Variants tables: DEFW de ptrs directos (no BgGfxPtrById lookup) ---
; Razon: BgGfxPtrById[id] puede apuntar a versiones RLE-comprimidas por
; compress_bg_rle.py, y DrawBgSpriteXOR no decodifica RLE -> rendering corrupto.
; Las labels BgGfx_*_pickup* injectadas por inject_pickup_sprites.py SI son
; raw, asi que usamos esos labels directamente.
HealthVariantPtrs:
    DEFB 5                              ; 5 variantes (1 byte count)
    DEFW BgGfx_health_pickup            ; canonical (id 254, pan)
    DEFW BgGfx_health_pickup_72         ; variant id 72 (queso)
    DEFW BgGfx_health_pickup_3          ; variant id 74 (chorizo)
    DEFW BgGfx_health_pickup_4          ; variant id 75 (leche)
    DEFW BgGfx_health_pickup_5          ; variant id 85 (pollo)

StaminaVariantPtrs:
    DEFB 4                              ; 4 variantes
    DEFW BgGfx_stamina_pickup           ; canonical (id 255, jarra de vino)
    DEFW BgGfx_stamina_pickup_2         ; variant id 73 (taza de cafe)
    DEFW BgGfx_stamina_pickup_3         ; variant id 79 (pocion)
    DEFW BgGfx_stamina_pickup_4         ; variant id 84 (copa de brandy)

; ==============================================================================
; PickRandomVariantPtr / LookupVariantPtrByIdx
; ==============================================================================
; PickRandomVariantPtr: elige variante random Y la persiste en RP_TmpVariant.
;   IN:  HL = ptr a tabla "DEFB count, DEFW ptr1, DEFW ptr2, ..."
;   OUT: HL = sprite ptr de la variante elegida.
;   Side: RP_TmpVariant ← idx elegido (0..count-1), para que la cache pueda
;         rotarlo y reusarlo al revisitar la sala.
;
; LookupVariantPtrByIdx: lookup directo SIN random (para cache hit que ya tiene
;                       el idx que quiere reusar).
;   IN:  HL = ptr a tabla, A = idx (0..count-1)
;   OUT: HL = sprite ptr de la variante[idx].
;   Side: ninguno (NO toca RP_TmpVariant — el caller lo gestiona).
;
; Destruye: AF, BC, DE (ambas rutinas).
; ==============================================================================
PickRandomVariantPtr:
    LD A, (HL)                          ; A = count
    LD B, A
    LD A, R
.pvpModLoop:
    SUB B
    JR NC, .pvpModLoop
    ADD A, B                            ; A = R mod count (0..count-1)
    LD (RP_TmpVariant), A               ; persistir para cache rotation
    ; fall through a LookupVariantPtrByIdx (HL aun apunta al count byte, A = idx)
LookupVariantPtrByIdx:
    INC HL                              ; HL @ first DEFW
    ADD A, A                            ; idx*2 (DEFW = 2 B)
    LD E, A
    LD D, 0
    ADD HL, DE                          ; HL @ entry elegida
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A                             ; HL = sprite ptr
    RET

