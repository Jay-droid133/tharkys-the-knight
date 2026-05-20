; ==============================================================================
; beeper_ticks.asm - Tics audibles vía beeper ($FE bit 4)
; ==============================================================================
; Tres fuentes de tics que se reparten 4 slots fijos dentro de un ciclo de
; 25 frames (= 1 s) para no pisarse nunca:
;
;   Frame  0: buff normal  (o buff warning si NO hay normal activo)
;   Frame  6: compass      (normal o warning)
;   Frame 12: buff warning (sólo si coexiste con un buff normal)
;   Frame 18: compass warning (2ª ocurrencia → 0.5 s entre tics)
;
; Comportamiento resultante:
;   - Solo buff normal:                    tic cada 1 s.
;   - Solo buff warning:                   tic cada 0.5 s (slots 0+12).
;   - Buff normal + warning coexistiendo:  intercalado 1 s offset 0.5 s.
;   - Solo compass normal:                 tic cada 1 s.
;   - Solo compass warning:                tic cada 0.5 s (slots 6+18).
;   - Todo combinado:                      tic cada 0.24 s aprox, sin solape.
;
; Buffs positivos contemplados: rayo (SpeedBuffTimer + SpeedBuffType==1),
; espada (EspadaTimer), escudo (EscudoTimer). Cada uno se considera "warning"
; cuando su timer < BUFF_WARNING_FRAMES (= 75 frames = 3 s).
;
; Compass: se considera activa si MagicCompassTimer != 0 y no es permanente.
; Warning cuando MagicCompassTimer < MAGIC_COMPASS_WARNING_FRAMES.
;
; UpdateBeeperTicks se llama una vez por frame desde MainLoop. Es bloqueante
; durante el beep (~10 ms) — los IRQs siguen activos, así que el handler de
; música no se ve afectado más allá de un jitter inferior a 1 ms por nota.
; ==============================================================================

; --- Estado (slot 1 bank 5, always-visible) -----------------------------------
BeeperPhase:    DEFB 0          ; 0..24, frame del ciclo de 25 (= 1 s)

; ==============================================================================
; UpdateBeeperTicks - llamar una vez por frame desde MainLoop.
; ==============================================================================
; Destruye: AF, BC, DE, HL.
; ==============================================================================
UpdateBeeperTicks:
    ; --- Gate: silencio absoluto si TimeFrozen != 0 ---
    ; TimeFrozen=1 (church trap) y =2 (muerte del player) congelan el reloj y
    ; toda la atmósfera. No deben sonar tics. NO avanzamos BeeperPhase tampoco
    ; para que al volver el control el ciclo continúe donde estaba.
    LD A, (TimeFrozen)
    OR A
    RET NZ

    ; --- Avanzar phase módulo 25 ---
    LD HL, BeeperPhase
    LD A, (HL)
    INC A
    CP 25
    JR C, .ubtStore
    XOR A
.ubtStore:
    LD (HL), A
    ; A = phase actual; despacho por slot
    CP 6
    JR Z, .ubtSlot6
    JR C, .ubtSlot0orSkip            ; phase 0..5: solo phase 0 dispara
    CP 12
    JR Z, .ubtSlot12
    JR C, .ubtNoFire                 ; phase 7..11: nada
    CP 18
    JR Z, .ubtSlot18
.ubtNoFire:
    RET

; --- Slot 0: buff normal (o buff warning solo) -------------------------------
.ubtSlot0orSkip:
    OR A
    RET NZ                           ; phase 1..5: no fire
    CALL ComputeBuffState            ; B = bits: 1=has_normal, 2=has_warning
    LD A, B
    AND $01
    JR NZ, .ubtFireBuffNormal
    LD A, B
    AND $02
    RET Z                            ; ni normal ni warning → nada
    JP FireBuffWarning               ; tail
.ubtFireBuffNormal:
    JP FireBuffNormal                ; tail

; --- Slot 6: compass (normal o warning) --------------------------------------
.ubtSlot6:
    ; Permanente: blink visual sin sonido (tail-call al setter).
    LD A, (MagicCompassPermanent)
    OR A
    JP NZ, FireCompassPermanentBlink
    CALL IsCompassActive
    RET Z                            ; compass inactiva
    CALL IsCompassWarning
    JR NZ, .ubt6Warning
    JP FireCompassNormal             ; tail
.ubt6Warning:
    JP FireCompassWarning            ; tail

; --- Slot 12: buff warning ----------------------------------------------------
; Dispara si hay warning, da igual si coexiste con normal o no. Casos:
;   - normal solo:        slot 0 fire normal, slot 12 no (no hay warning).
;   - warning solo:       slot 0 fire warning, slot 12 fire warning → 0.5 s.
;   - normal + warning:   slot 0 fire normal, slot 12 fire warning → intercalado.
.ubtSlot12:
    CALL ComputeBuffState
    LD A, B
    AND $02
    RET Z                            ; sin warning → nada
    JP FireBuffWarning               ; tail

; --- Slot 18: compass warning (2ª ocurrencia, para 0.5 s) --------------------
.ubtSlot18:
    CALL IsCompassActive
    RET Z
    CALL IsCompassWarning
    RET Z                            ; compass activa pero NO en warning
    JP FireCompassWarning            ; tail

; ==============================================================================
; ComputeBuffState - examina buffs positivos y devuelve bits en B.
; ==============================================================================
; OUT: B bit 0 = al menos 1 buff positivo activo NO en warning.
;      B bit 1 = al menos 1 buff positivo en warning.
;      Ambos bits pueden estar set si hay buffs en estados distintos.
; Destruye: A, BC, HL.
; ==============================================================================
ComputeBuffState:
    LD B, 0
    ; --- SpeedBuff: solo cuenta si SpeedBuffType == 1 (rayo positivo) ---
    LD A, (SpeedBuffType)
    CP 1
    JR NZ, .cbsSkipSpeed
    LD HL, SpeedBuffTimer
    CALL CheckOneBuff
.cbsSkipSpeed:
    LD HL, EspadaTimer
    CALL CheckOneBuff
    LD HL, EscudoTimer
    CALL CheckOneBuff
    RET

; CheckOneBuff: HL apunta al timer 16-bit. Si != 0 setea bit en B según
; sea normal (timer >= BUFF_WARNING_FRAMES) o warning (1..BUFF_WARNING_FRAMES-1).
; Destruye: A; preserva HL.
;
; OJO: hay que chequear hi y lo POR SEPARADO. Una versión anterior hacía
; OR C (= hi | lo) y luego OR A para detectar "hi != 0", pero eso comparaba
; hi|lo en lugar del hi byte → cualquier timer con lo > 0 se marcaba normal,
; aunque hi fuera 0 y lo < 75. Resultado: warnings NUNCA se disparaban.
CheckOneBuff:
    INC HL                           ; HL+1 = hi byte
    LD A, (HL)
    DEC HL                           ; restore HL al lo byte
    OR A
    JR NZ, .cobNormal                ; hi != 0 → timer >= 256 → activo, normal
    LD A, (HL)                       ; A = lo byte
    OR A
    RET Z                            ; timer == 0 → buff inactivo
    CP BUFF_WARNING_FRAMES
    JR NC, .cobNormal                ; lo >= 75 → normal
    ; lo < 75 y hi == 0 → warning
    LD A, B
    OR $02
    LD B, A
    RET
.cobNormal:
    LD A, B
    OR $01
    LD B, A
    RET

; ==============================================================================
; IsCompassActive - flags NZ si compass debe sonar (no permanente y timer>0).
; ==============================================================================
; OUT: Z si NO debe sonar (timer=0 o permanent); NZ si suena.
; Destruye: A, C.
; ==============================================================================
IsCompassActive:
    LD A, (MagicCompassPermanent)
    OR A
    JR Z, .icaCheckTimer
    XOR A                            ; permanente → Z (no sonar)
    RET
.icaCheckTimer:
    LD A, (MagicCompassTimer)
    LD C, A
    LD A, (MagicCompassTimer + 1)
    OR C
    RET                              ; Z si timer == 0; NZ si > 0

; ==============================================================================
; IsCompassWarning - flags NZ si MagicCompassTimer < MAGIC_COMPASS_WARNING_FRAMES.
; ==============================================================================
; Asume que IsCompassActive ya dió NZ (timer > 0).
; OUT: NZ si está en warning; Z si normal.
; Destruye: A.
; ==============================================================================
IsCompassWarning:
    LD A, (MagicCompassTimer + 1)
    OR A
    JR NZ, .icwNotWarning            ; hi != 0 → timer > 255, NO warning
    LD A, (MagicCompassTimer)
    CP MAGIC_COMPASS_WARNING_FRAMES
    JR NC, .icwNotWarning            ; lo >= threshold → normal
    OR 1                             ; NZ
    RET
.icwNotWarning:
    XOR A                            ; Z
    RET

; ==============================================================================
; Fire wrappers: cada uno carga (B = halfcycles, E = period) y llama BeeperTick.
; Si en el futuro hace falta gating extra (mute música, etc.), aquí va.
; ==============================================================================
FireBuffNormal:
    LD B, BEEPER_TICK_HALFCYCLES
    LD E, BEEPER_BUFF_NORMAL_E
    JP BeeperTick

FireBuffWarning:
    LD B, BEEPER_TICK_HALFCYCLES
    LD E, BEEPER_BUFF_WARNING_E
    JP BeeperTick

FireCompassNormal:
    LD A, MAGIC_COMPASS_TICK_DURATION
    LD (MagicCompassTickActiveFrames), A    ; sincroniza blink HUD con tic
    LD B, BEEPER_TICK_HALFCYCLES
    LD E, BEEPER_COMPASS_NORMAL_E
    JP BeeperTick

FireCompassWarning:
    LD A, MAGIC_COMPASS_TICK_DURATION
    LD (MagicCompassTickActiveFrames), A    ; sincroniza blink HUD con tic
    LD B, BEEPER_TICK_HALFCYCLES
    LD E, BEEPER_COMPASS_WARNING_E
    JP BeeperTick

; --- Compass permanente: solo blink visual, sin sonido beeper ---
; Llamado desde .ubtSlot6 cuando MagicCompassPermanent != 0. Mismo ritmo
; visual que FireCompassNormal pero sin tocar el beeper.
FireCompassPermanentBlink:
    LD A, MAGIC_COMPASS_TICK_DURATION
    LD (MagicCompassTickActiveFrames), A
    RET

; ==============================================================================
; BeeperTick - emite B half-cycles de un tono de período E en el beeper.
; ==============================================================================
; IN:  B = número de half-cycles (toggles del bit 4 de $FE). 20 ≈ 10 ms.
;      E = período (factor DJNZ; ~13×E + ~30 T-states/half-cycle).
; Destruye: AF, BC, DE.
;
; NO usa DI: los IRQs siguen activos. El handler de música corre durante el
; beep (los OUT de música a $FFFD/$BFFD no afectan a $FE), produce a lo sumo
; un jitter pequeño en la onda que es inaudible.
; ==============================================================================
BeeperTick:
    LD A, (CurrentBorderColor)
    AND $07                          ; preservar bits 0..2 (color de borde)
    LD D, A                          ; D = estado actual (speaker OFF inicio)
.btLoop:
    LD A, D
    XOR $10                          ; flip bit 4 (speaker)
    LD D, A                          ; ¡guardar nuevo estado! Sin esto, cada
                                     ;   iter haría XOR sobre el mismo D y el
                                     ;   speaker se quedaba pegado en ON → no
                                     ;   hay onda, solo un click inicial/final.
    OUT ($FE), A
    LD A, E
    LD C, A
.btInner:
    DEC C
    JR NZ, .btInner
    DJNZ .btLoop
    LD A, D
    AND $07                          ; speaker OFF al terminar (border intacto)
    OUT ($FE), A
    RET
