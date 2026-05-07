; ==============================================================================
; MAGIC COMPASS - Power-up que muestra ruta exacta sala-a-sala
; ==============================================================================
; Recogido por el player (sprite ID34, "compass pickup", BgGfx_pickup_compass).
; Mientras MagicCompassTimer>0:
;   - DrawCompass override: flecha apunta a la salida correcta de la sala
;     actual (BFS reverse desde ObjectiveScreen hasta CurrentScreen via
;     RoomCompGapsTable, respetando componentes walkable internas).
;   - Atributo HUD: paper amarillo, blink ~3 Hz (6 Hz en últimos 5 s).
;   - SFX (canal B): jingle al recoger + tick heartbeat 1/s (2/s en warning).
; Cancela en muerte y al cumplir hito (CurrentObjective avanza).
; Refresh al recoger otra (timer reset a MAGIC_COMPASS_FRAMES).
; Convive con rayo/caracol/mushroom (ortogonal: solo afecta HUD/SFX).
;
; BFS sala-a-sala con estado (sid, comp_local) — comp_local es la zona
; walkable interna (re-indexada por tamaño desc). Esto evita cul-de-sacs
; internos: dos gaps de la misma sala solo conectan internamente si
; comparten comp. Cada gap individual tiene su comp en RoomCompGapsTable.
; La asociación gap-físico↔comp se preserva via el coord (cuando dos gaps
; del mismo side existen en distintas comps, mantienen distintos coords).
;
; Vive en slot 1 ($6000+, no contended). Cero coste en bank 0/2.
; ==============================================================================

; ==============================================================================
; ApplyMagicCompassBuff - Activa el power-up (refresh-on-pickup)
; ==============================================================================
; Llamado desde el dispatcher de pickup (CheckRandomSyntheticPickup +
; CheckPickupCollect). Refresh: si ya estaba activo, reinicia timer.
; Destruye: AF, HL.
; ==============================================================================
ApplyMagicCompassBuff:
    LD HL, MAGIC_COMPASS_FRAMES
    LD (MagicCompassTimer), HL
    LD A, 1
    LD (MagicCompassPathDirty), A       ; recalcular path en próximo update
    XOR A
    LD (MagicCompassTickActiveFrames), A ; arranca con bright off (sin tick sonando)
    LD A, MAGIC_COMPASS_TICK_NORMAL
    LD (MagicCompassTickCounter), A
    ; Arrancar jingle: idx=0, frames=1 → primera nota se dispara YA en update
    XOR A
    LD (MagicCompassJingleIdx), A
    LD A, 1
    LD (MagicCompassJingleFrames), A
    RET

; ==============================================================================
; CancelMagicCompass - Cancela el efecto (muerte / hito cumplido / llegar al
; hito / timeout). Cleanup exhaustivo para que ni el jingle ni el tick AY
; sigan sonando un frame extra y para que el HUD no quede con cache stale.
; ==============================================================================
; Entry points:
;   CancelMagicCompass    - chequea timer; RET Z si ya inactivo. Llamado por
;                           muerte / hito cumplido / llegar a sala destino,
;                           sites que no saben si la brujula estaba activa.
;   _DoCancelMagicCompass - fall-through directo, sin check de timer. Usado
;                           por el branch del timeout natural (Timer ya es 0
;                           tras el DEC, asi que el check daria RET Z falso
;                           positivo y se saltaria el cleanup).
; ==============================================================================
CancelMagicCompass:
    LD A, (MagicCompassTimer)
    LD B, A
    LD A, (MagicCompassTimer + 1)
    OR B
    RET Z                                ; ya inactivo
    ; fall through al cleanup compartido
_DoCancelMagicCompass:
    XOR A
    LD (MagicCompassTimer), A
    LD (MagicCompassTimer + 1), A
    LD (MagicCompassTickCounter), A
    LD (MagicCompassTickActiveFrames), A ; mata bright residual del tick
    LD (MagicCompassBfsState), A         ; aborta BFS in-progress (queue stale)
    LD A, $FF
    LD (MagicCompassPathDir), A          ; borra dir cached → render normal
    LD (LastMagicCompassDrawn), A        ; invalida cache de sprite HUD
    LD (MagicCompassJingleIdx), A        ; detiene jingle (si estaba sonando)
    LD (PreviousObjectiveDistance), A    ; fuerza redraw del HUD el siguiente
                                         ; frame: DrawCompass detecta $FF y
                                         ; entra a .dcRedraw, sustituyendo el
                                         ; sprite_compass_magic stale por la
                                         ; brujula clasica (8 flechas + X).
    RET

; ==============================================================================
; UpdateMagicCompass - Tick por frame (timer, blink, AY tick, jingle, path)
; ==============================================================================
UpdateMagicCompass:
    CALL .umcUpdateJingle

    LD HL, (MagicCompassTimer)
    LD A, H
    OR L
    RET Z                                ; inactivo

    DEC HL
    LD (MagicCompassTimer), HL

    LD A, H
    OR L
    JR NZ, .umcStillActive
    ; Timeout natural: Timer acaba de pasar a 0. Cleanup completo (saltando
    ; el check del entry point publico, que daria RET Z falso positivo).
    JP _DoCancelMagicCompass             ; tail call: cleanup + force HUD redraw
.umcStillActive:

    ; ¿Llegamos a la sala del hito? Si sí, cancelar el power-up entero —
    ; no esperamos a coger el pickup. Esto detiene tick AY, jingle y libera
    ; el HUD compass al estado clásico (X blanca normal vía DrawCompass).
    LD A, (ObjectiveScreenX)
    CP $FF
    JR Z, .umcNotAtTarget                ; sin objetivo resuelto → skip
    LD HL, CurrentScreenX
    CP (HL)
    JR NZ, .umcNotAtTarget
    LD A, (ObjectiveScreenY)
    LD HL, CurrentScreenY
    CP (HL)
    JR NZ, .umcNotAtTarget
    JP CancelMagicCompass                ; tail call — RET incluido
.umcNotAtTarget:

    ; Decrementar TickActiveFrames si > 0 (controla la duración visual del bright)
    LD HL, MagicCompassTickActiveFrames
    LD A, (HL)
    OR A
    JR Z, .umcAfterTickActive
    DEC (HL)
.umcAfterTickActive:

    LD HL, MagicCompassTickCounter
    LD A, (HL)
    OR A
    JR Z, .umcTickFire
    DEC (HL)
    JR Z, .umcTickFire
    JR .umcAfterTick

.umcTickFire:
    CALL .umcIsWarning
    OR A
    LD A, MAGIC_COMPASS_TICK_NORMAL
    JR Z, .umcTickReload
    LD A, MAGIC_COMPASS_TICK_WARNING
.umcTickReload:
    LD (MagicCompassTickCounter), A
    ; Activar bright visual durante la duración del beep
    LD A, MAGIC_COMPASS_TICK_DURATION
    LD (MagicCompassTickActiveFrames), A
    LD HL, MAGIC_COMPASS_TICK_PERIOD
    LD B, MAGIC_COMPASS_TICK_DURATION
    CALL AY_PlayBeep

.umcAfterTick:
    ; Si el BFS ya está en progreso (amortizado en chunks), continuar.
    LD A, (MagicCompassBfsState)
    OR A
    JR NZ, .umcRunBfs
    ; Sino, ¿hay un BFS pendiente?
    LD A, (MagicCompassPathDirty)
    OR A
    RET Z
    XOR A
    LD (MagicCompassPathDirty), A
.umcRunBfs:
    JP ComputeMagicCompassPath           ; tail call (init si state=0, resume si state=1)

.umcIsWarning:
    LD A, (MagicCompassTimer + 1)
    OR A
    JR NZ, .umcwNormal
    LD A, (MagicCompassTimer)
    CP MAGIC_COMPASS_WARNING_FRAMES + 1
    JR NC, .umcwNormal
    LD A, 1
    RET
.umcwNormal:
    XOR A
    RET

.umcUpdateJingle:
    LD A, (MagicCompassJingleIdx)
    CP $FF
    RET Z

    LD HL, MagicCompassJingleFrames
    DEC (HL)
    RET NZ

    LD A, (MagicCompassJingleIdx)
    ADD A, A
    ADD A, A
    LD E, A
    LD D, 0
    LD HL, MagicCompassJingleTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, (HL)
    LD (MagicCompassJingleFrames), A
    INC HL
    LD A, (HL)
    PUSH AF
    EX DE, HL
    LD A, (MagicCompassJingleFrames)
    LD B, A
    CALL AY_PlayBeep
    POP AF
    OR A
    JR NZ, .umcujMore
    LD A, $FF
    LD (MagicCompassJingleIdx), A
    RET
.umcujMore:
    LD A, (MagicCompassJingleIdx)
    INC A
    LD (MagicCompassJingleIdx), A
    RET

; ==============================================================================
; PaintMagicCompassAttrs - Pinta los 4 chars del HUD compass en modo magic
; ==============================================================================
; Color base lo decide el editor (sprite id 36, attrBytes). El runtime lo
; lee de MagicCompassBaseAttrs (auto-importado por import_magic_compass_hud.py
; con bit 6 BRIGHT clearado) y aplica BRIGHT solo al char correspondiente
; a la PathDir. Durante los últimos 5 s ese bright parpadea on/off a ~6 Hz.
;
; Mapping diagonal de las 4 esquinas del 2x2:
;   col1   col2
;     W      N    (row 1, top)     ← idx 0 (1,1) | idx 1 (2,1)
;     S      E    (row 2, bottom)  ← idx 2 (1,2) | idx 3 (2,2)
;
;   PathDir 0 (N) → idx 1 → offset +1
;   PathDir 1 (S) → idx 2 → offset +$20
;   PathDir 2 (W) → idx 0 → offset +0
;   PathDir 3 (E) → idx 3 → offset +$21
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
PaintMagicCompassAttrs:
    ; Pintar 4 chars con MagicCompassBaseAttrs (orden: 1,1 / 2,1 / 1,2 / 2,2)
    LD DE, MagicCompassBaseAttrs
    LD HL, $5800 + COMPASS_CHARROW * $20 + COMPASS_COL
    LD A, (DE)
    LD (HL), A
    INC HL
    INC DE
    LD A, (DE)
    LD (HL), A
    INC DE
    LD HL, $5800 + (COMPASS_CHARROW + 1) * $20 + COMPASS_COL
    LD A, (DE)
    LD (HL), A
    INC HL
    INC DE
    LD A, (DE)
    LD (HL), A

    ; Si sin path no hay char activo: solo base attrs (ya pintados).
    LD A, (MagicCompassPathDir)
    CP $FF
    RET Z

    ; Si el tick no está sonando, char activo se queda con base attr.
    ; Eso da el efecto visual "OFF" entre pitidos.
    LD A, (MagicCompassTickActiveFrames)
    OR A
    RET Z

    ; Tick sonando: override del char activo a MAGIC_COMPASS_ACTIVE_ATTR
    ; ($47 = white bright). Los pixels del sprite los pinta el editor;
    ; para que la silueta no se "invierta" al cambiar paper/ink, diseña
    ; el char correspondiente con paper black + ink negro (la silueta vive
    ; en los píxeles encendidos, que pasan a ink white bright en el flash).
    LD A, (MagicCompassPathDir)
    LD E, A
    LD D, 0
    LD HL, .pmcaDirToOffset
    ADD HL, DE
    LD A, (HL)
    LD E, A
    LD D, 0
    LD HL, $5800 + COMPASS_CHARROW * $20 + COMPASS_COL
    ADD HL, DE                           ; HL = addr del char activo (attr area)
    LD A, MAGIC_COMPASS_ACTIVE_ATTR
    LD (HL), A
    RET

.pmcaDirToOffset:
    DEFB $01                             ; 0 (N) → col 2 row 1 → +1
    DEFB $20                             ; 1 (S) → col 1 row 2 → +$20
    DEFB $00                             ; 2 (W) → col 1 row 1 → +0
    DEFB $21                             ; 3 (E) → col 2 row 2 → +$21

MagicCompassJingleTable:
    DEFW $00C0
    DEFB 4, 1                            ; nota 1: ~570 Hz, 160 ms
    DEFW $00A0
    DEFB 4, 1                            ; nota 2: ~684 Hz
    DEFW $0070
    DEFB 6, 0                            ; nota 3: ~970 Hz, 240 ms (last)

; ==============================================================================
; ComputeMagicCompassPath - BFS reverse con state (sid, comp_local)
; ==============================================================================
; Algoritmo:
;   1. queue.push((target_sid, target_comp=0)). Mark visited.
;      target_comp = 0 (heurística: el pickup vive en la comp principal).
;   2. While queue not empty:
;        (R, R_comp) = queue.pop()
;        For each gap in RoomCompGaps[R]:
;          If gap.comp != R_comp: skip.
;          V = neighbor of R via gap.side.
;          Find V's gap with side=opposite(gap.side) AND coord=gap.coord.
;          V_comp = that gap's comp.
;          If (V, V_comp) visited: skip.
;          If V == current_sid AND V_comp == player_current_comp:
;            dir_player = opposite(gap.side); STORE; RETURN.
;          Mark visited; queue.push((V, V_comp)).
;
; player_current_comp se determina via LastEntrySide:
;   - LastEntrySide = side por el que el player entró a current_sid.
;   - player_comp = comp del gap de current_sid en LastEntrySide.
;   - Si LastEntrySide = $FF (boot/respawn), comp = 0 (fallback).
;
; OUT: MagicCompassPathDir = 0=N, 1=E, 2=S, 3=W; o $FF si sin path.
; ==============================================================================
ComputeMagicCompassPath:
    ; ¿BFS in-progress? Si sí, saltar init y reanudar.
    LD A, (MagicCompassBfsState)
    OR A
    JP NZ, .cmcpResume

    ; --- INIT (solo cuando arranca un BFS nuevo) ---
    LD A, (CurrentScreenY)
    RLCA : RLCA : RLCA : RLCA            ; Y*16
    LD HL, CurrentScreenX
    ADD A, (HL)
    LD (.cmcpCurSid), A

    LD A, (ObjectiveScreenX)
    CP $FF
    JP Z, .cmcpNoPath
    LD A, (ObjectiveScreenY)
    RLCA : RLCA : RLCA : RLCA
    LD HL, ObjectiveScreenX
    ADD A, (HL)
    LD (.cmcpTgtSid), A

    LD B, A                              ; B = target sid
    LD A, (.cmcpCurSid)
    CP B
    JP Z, .cmcpNoPath                    ; current==target → X blanca

    ; --- Determinar player_current_comp via LastEntrySide ---
    LD A, (LastEntrySide)
    CP $FF
    JR NZ, .cmcpHaveEntry
    XOR A                                ; fallback: comp 0
    JR .cmcpStoreCurComp
.cmcpHaveEntry:
    ; Buscar el gap de current_sid en side LastEntrySide. Su comp = player comp.
    LD B, A                              ; B = LastEntrySide
    LD A, (.cmcpCurSid)
    CALL .cmcpFindGapBySide              ; OUT: A = comp (0..2), o $FF si no encontrado
    CP $FF
    JR NZ, .cmcpStoreCurComp
    XOR A                                ; fallback comp 0
.cmcpStoreCurComp:
    LD (.cmcpCurComp), A

    ; --- Clear visited bitmap (96 bytes = 768 bits = 256 sids × 3 comps) ---
    LD HL, MagicCompassVisited
    LD DE, MagicCompassVisited + 1
    LD BC, 95
    XOR A
    LD (HL), A
    LDIR

    ; --- Inicializar cola con (target, comp 0) ---
    XOR A
    LD (MagicCompassBfsHead), A
    LD (MagicCompassBfsTail), A
    LD A, (.cmcpTgtSid)
    LD HL, MagicCompassBfsQueue
    LD (HL), A                           ; queue[0].sid = target
    INC HL
    XOR A
    LD (HL), A                           ; queue[0].comp = 0
    LD HL, MagicCompassBfsHead
    INC (HL)                             ; head = 1

    ; visited[(target, 0)] = 1
    LD A, (.cmcpTgtSid)
    LD B, 0
    CALL .cmcpMarkVisited

    ; INIT done → marcar in-progress y caer al loop con counter de iteraciones.
    LD A, 1
    LD (MagicCompassBfsState), A

.cmcpResume:
    ; Cargar contador de iteraciones para este chunk de frame.
    LD A, MAGIC_COMPASS_BFS_ITERS_PER_FRAME
    LD (.cmcpItersLeft), A

    ; --- BFS loop ---
.cmcpLoop:
    ; Yield si se acabó el chunk de iteraciones del frame.
    LD A, (.cmcpItersLeft)
    OR A
    JP Z, .cmcpYield
    DEC A
    LD (.cmcpItersLeft), A

    ; queue empty?
    LD A, (MagicCompassBfsHead)
    LD B, A
    LD A, (MagicCompassBfsTail)
    CP B
    JP Z, .cmcpNoPath

    ; Pop: read queue[tail*2] = (sid, comp); tail++
    LD E, A
    INC A
    AND 63
    LD (MagicCompassBfsTail), A
    LD A, E
    ADD A, A                             ; *2 (entries de 2 bytes)
    LD E, A
    LD D, 0
    LD HL, MagicCompassBfsQueue
    ADD HL, DE
    LD A, (HL)                           ; sid
    LD (.cmcpR), A
    INC HL
    LD A, (HL)
    LD (.cmcpRComp), A

    ; Iterate RoomCompGaps[R]
    LD A, (.cmcpR)
    LD L, A
    LD H, 0
    ADD HL, HL                           ; *2 (DEFW ptrs)
    LD DE, RoomCompGapsTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                           ; DE = record ptr
    EX DE, HL                            ; HL = record

    LD A, (HL)                           ; count
    OR A
    JP Z, .cmcpLoop                      ; no gaps → next pop
    LD B, A                              ; B = remaining count
    INC HL                               ; HL @ first {side_comp, coord}

.cmcpGapLoop:
    ; Read side_comp byte
    LD A, (HL)
    LD (.cmcpGapSideComp), A
    INC HL
    LD A, (HL)
    LD (.cmcpGapCoord), A
    INC HL
    PUSH BC                              ; save count
    PUSH HL                              ; save record ptr

    ; Match comp?
    LD A, (.cmcpGapSideComp)
    SRL A
    SRL A                                ; A = comp (bits 2-3 → bits 0-1)
    AND $03
    LD C, A                              ; C = gap comp
    LD A, (.cmcpRComp)
    CP C
    JP NZ, .cmcpGapNext

    ; Compute V = neighbor of R in gap.side
    LD A, (.cmcpGapSideComp)
    AND $03                              ; A = side
    LD C, A                              ; C = side
    LD A, (.cmcpR)
    LD B, A                              ; B = R sid
    CALL .cmcpComputeNeighbor            ; IN: B=R, C=side; OUT: A=V (or $FF if invalid)
    CP $FF
    JP Z, .cmcpGapNext
    LD (.cmcpV), A

    ; Find V's gap with side=opposite(gap.side) AND coord=gap.coord
    LD A, C                              ; side
    XOR $01                              ; opposite (N↔S, W↔E using XOR 1 — N=0,S=1,W=2,E=3)
    LD C, A                              ; C = opp_side
    LD A, (.cmcpGapCoord)
    LD B, A                              ; B = coord
    LD A, (.cmcpV)
    CALL .cmcpFindMatchingGap            ; OUT: A = V_comp (0..2) or $FF if no match
    CP $FF
    JP Z, .cmcpGapNext
    LD (.cmcpVComp), A

    ; Check V == current_sid AND V_comp == player_current_comp
    LD A, (.cmcpV)
    LD B, A
    LD A, (.cmcpCurSid)
    CP B
    JR NZ, .cmcpNotCurrent
    LD A, (.cmcpVComp)
    LD B, A
    LD A, (.cmcpCurComp)
    CP B
    JR NZ, .cmcpNotCurrent
    ; FOUND: dir_player = opposite of gap.side. We already have it as opp_side
    ; logic: opposite of side means the direction the player at current goes
    ; to reach R. We computed opp_side earlier (used to find V's gap).
    ; gap.side from R's perspective = direction to V. Player at V goes
    ; opposite(gap.side) = opp_side to reach R.
    LD A, (.cmcpGapSideComp)
    AND $03                              ; gap.side
    XOR $01                              ; player's direction (opposite)
    LD (MagicCompassPathDir), A
    XOR A
    LD (MagicCompassBfsState), A         ; BFS terminado
    POP HL
    POP BC
    RET

.cmcpNotCurrent:
    ; Visited check (B=sid, C=comp)
    LD A, (.cmcpV)
    LD B, A
    LD A, (.cmcpVComp)
    LD C, A
    CALL .cmcpCheckVisitedBC             ; OUT: Z=not visited, NZ=visited
    JP NZ, .cmcpGapNext

    ; Mark visited (A=sid, B=comp)
    LD A, (.cmcpVComp)
    LD B, A
    LD A, (.cmcpV)
    CALL .cmcpMarkVisited

    ; Push (V, V_comp) to queue
    LD A, (MagicCompassBfsHead)
    ADD A, A                             ; *2
    LD E, A
    LD D, 0
    LD HL, MagicCompassBfsQueue
    ADD HL, DE
    LD A, (.cmcpV)
    LD (HL), A
    INC HL
    LD A, (.cmcpVComp)
    LD (HL), A
    LD A, (MagicCompassBfsHead)
    INC A
    AND 63
    LD (MagicCompassBfsHead), A

.cmcpGapNext:
    POP HL
    POP BC
    DEC B
    JP NZ, .cmcpGapLoop
    JP .cmcpLoop

.cmcpNoPath:
    XOR A
    LD (MagicCompassBfsState), A         ; BFS terminado (sin path)
    LD A, $FF
    LD (MagicCompassPathDir), A
    RET

.cmcpYield:
    ; Acabamos el chunk de iteraciones de este frame. State queda en 1, así
    ; que el siguiente frame UpdateMagicCompass llamará a esta rutina de
    ; nuevo y caerá en .cmcpResume (skip init, recargar contador, continuar).
    RET

; ==============================================================================
; .cmcpFindGapBySide - Para sala A, busca el gap en side B más cercano al
; LastEntryCoord; devuelve su comp.
; ==============================================================================
; IN:  A = sid, B = side (0..3)
; OUT: A = comp (0..2) si encontrado; $FF si no hay gap en ese side.
;
; Cuando hay múltiples gaps del mismo side en distintas comps (e.g. (5,12)
; con E@3 comp 1 y E@11 comp 0), el coord físico del char donde entró el
; player desambigua: tomamos el gap con coord más cercano al LastEntryCoord.
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
.cmcpFindGapBySide:
    LD (.fgbsTargetSid), A
    LD A, B
    LD (.fgbsTargetSide), A
    LD A, $FF
    LD (.fgbsBestComp), A
    LD A, 255
    LD (.fgbsBestDist), A                ; init bestDist = 255 (max)

    LD A, (.fgbsTargetSid)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, RoomCompGapsTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL                            ; HL = record
    LD A, (HL)
    OR A
    JR Z, .fgbsDone
    LD B, A                              ; count
    INC HL
.fgbsLoop:
    LD A, (HL)                           ; side_comp
    INC HL
    LD C, (HL)                           ; coord
    INC HL
    LD D, A                              ; D = side_comp
    AND $03
    LD E, A
    LD A, (.fgbsTargetSide)
    CP E
    JR NZ, .fgbsNext

    ; Compute |coord - LastEntryCoord|
    LD A, (LastEntryCoord)
    SUB C
    JR NC, .fgbsAbsOk
    NEG
.fgbsAbsOk:
    LD E, A                              ; E = distance
    LD A, (.fgbsBestDist)
    CP E
    JR C, .fgbsNext                      ; bestDist < E → not better
    JR Z, .fgbsNext                      ; ties: keep first
    ; New best
    LD A, E
    LD (.fgbsBestDist), A
    LD A, D
    SRL A
    SRL A
    AND $03
    LD (.fgbsBestComp), A

.fgbsNext:
    DJNZ .fgbsLoop
.fgbsDone:
    LD A, (.fgbsBestComp)
    RET

; ==============================================================================
; .cmcpComputeNeighbor - Calcula V dado R y side, con bounds check
; ==============================================================================
; IN:  B = R sid, C = side (0=N,1=S,2=W,3=E)
; OUT: A = V sid (0..255) si valid; A = $FF si neighbor sale del mapa.
; Destruye: AF.
; ==============================================================================
.cmcpComputeNeighbor:
    LD A, C
    OR A
    JR NZ, .ccnNotN
    ; N: V = R - 16, valid if R >= 16
    LD A, B
    CP 16
    JR C, .ccnInvalid
    SUB 16
    RET
.ccnNotN:
    DEC A
    JR NZ, .ccnNotS
    ; S: V = R + 16, valid if R < 240
    LD A, B
    CP 240
    JR NC, .ccnInvalid
    ADD A, 16
    RET
.ccnNotS:
    DEC A
    JR NZ, .ccnE
    ; W: V = R - 1, valid if R % 16 != 0
    LD A, B
    AND $0F
    JR Z, .ccnInvalid
    LD A, B
    DEC A
    RET
.ccnE:
    ; E: V = R + 1, valid if R % 16 != 15
    LD A, B
    AND $0F
    CP 15
    JR Z, .ccnInvalid
    LD A, B
    INC A
    RET
.ccnInvalid:
    LD A, $FF
    RET

; ==============================================================================
; .cmcpFindMatchingGap - Busca en sala A un gap (side=B, coord=C)
; ==============================================================================
; Devuelve la comp del gap matching (side AND coord). Permite resolver la
; correspondencia gap-físico cuando hay múltiples gaps del mismo side en
; comps distintas.
; IN:  A = sid, B = coord, C = side
; OUT: A = comp (0..2) si encontrado; $FF si no match.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
.cmcpFindMatchingGap:
    LD (.cfmgSid), A
    LD A, B
    LD (.cfmgCoord), A
    LD A, C
    LD (.cfmgSide), A
    LD A, (.cfmgSid)
    LD L, A
    LD H, 0
    ADD HL, HL
    LD DE, RoomCompGapsTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL                            ; HL = record
    LD A, (HL)
    OR A
    JR Z, .cfmgNotFound
    LD B, A
    INC HL
.cfmgLoop:
    LD A, (HL)                           ; side_comp
    INC HL
    LD C, (HL)                           ; coord
    INC HL
    LD D, A                              ; D = side_comp
    AND $03                              ; side
    LD E, A
    LD A, (.cfmgSide)
    CP E
    JR NZ, .cfmgSkip
    LD A, (.cfmgCoord)
    CP C
    JR NZ, .cfmgSkip
    ; Match. Extract comp.
    LD A, D
    SRL A
    SRL A
    AND $03
    RET
.cfmgSkip:
    DJNZ .cfmgLoop
.cfmgNotFound:
    LD A, $FF
    RET

; ==============================================================================
; Visited bitmap helpers — 768 bits = 96 bytes (256 sids × 3 comps)
; ==============================================================================
; Bit index = sid*3 + comp (0..767). Byte = bit_idx / 8. Bit pos = bit_idx % 8.
; bit_idx en 16-bit: HL.
;
; .cmcpMarkVisited     - IN: A=sid, B=comp. Set bit. Destruye AF, BC, HL.
; .cmcpCheckVisitedBC  - IN: B=sid, C=comp. OUT: Z=not visited, NZ=visited.
; ==============================================================================
.cmcpMarkVisited:
    ; bit_idx = sid*3 + comp; HL = bit_idx
    LD H, 0
    LD L, A                              ; HL = sid
    PUSH HL
    ADD HL, HL                           ; HL = sid*2
    POP DE
    ADD HL, DE                           ; HL = sid*3
    LD E, B
    LD D, 0
    ADD HL, DE                           ; HL = sid*3 + comp
    ; bit pos = HL & 7; byte idx = HL >> 3
    LD A, L
    AND $07
    LD C, A                              ; C = bit pos
    SRL H
    RR L
    SRL H
    RR L
    SRL H
    RR L                                 ; HL = HL/8 (byte idx)
    LD DE, MagicCompassVisited
    ADD HL, DE                           ; HL = byte addr
    LD A, 1
    INC C
.cmvShift:
    DEC C
    JR Z, .cmvDone
    ADD A, A
    JR .cmvShift
.cmvDone:
    OR (HL)
    LD (HL), A
    RET

.cmcpCheckVisitedBC:
    ; bit_idx = sid*3 + comp; HL = bit_idx
    LD H, 0
    LD L, B                              ; HL = sid
    PUSH HL
    ADD HL, HL
    POP DE
    ADD HL, DE                           ; HL = sid*3
    LD E, C
    LD D, 0
    ADD HL, DE                           ; HL = sid*3 + comp
    LD A, L
    AND $07
    LD C, A
    SRL H
    RR L
    SRL H
    RR L
    SRL H
    RR L
    LD DE, MagicCompassVisited
    ADD HL, DE
    LD A, 1
    INC C
.ccvShift:
    DEC C
    JR Z, .ccvDone
    ADD A, A
    JR .ccvShift
.ccvDone:
    AND (HL)
    RET

; --- Locals de ComputeMagicCompassPath (deben quedar DENTRO del scope global
; ComputeMagicCompassPath; no insertar globals entre ellas y la rutina). ---
.cmcpCurSid:        DEFB 0
.cmcpTgtSid:        DEFB 0
.cmcpCurComp:       DEFB 0
.cmcpR:             DEFB 0
.cmcpRComp:         DEFB 0
.cmcpV:             DEFB 0
.cmcpVComp:         DEFB 0
.cmcpGapSideComp:   DEFB 0
.cmcpGapCoord:      DEFB 0
.cfmgSid:           DEFB 0
.cfmgCoord:         DEFB 0
.cfmgSide:          DEFB 0
.fgbsTargetSid:     DEFB 0
.fgbsTargetSide:    DEFB 0
.fgbsBestComp:      DEFB 0
.fgbsBestDist:      DEFB 0
.cmcpItersLeft:     DEFB 0       ; chunked BFS: iteraciones que quedan en este frame

; ==============================================================================
; Sprite_Compass_Magic - 32 bytes raw (16x16 px) del HUD compass mágico.
; ==============================================================================
; Auto-importado desde sprite ID 36 ("magic compass HUD") de bg_sprites.json
; via tools/import_magic_compass_hud.py (des-CPL'd para encajar el formato
; raw que espera DrawCompassSprite).
; ==============================================================================
    INCLUDE "sprite_magic_compass_hud.inc"

; ==============================================================================
; Storage scratch — vive en slot 1, accesible directo desde el código BFS
; ==============================================================================
; Visited bitmap: 96 bytes (768 bits = 256 sids × 3 comps).
; Cola FIFO: 128 bytes (64 entries × 2 bytes (sid, comp)).
; head/tail viven en variables_lo (LOW_RAM).
MagicCompassBfsQueue:    DEFS 128
MagicCompassVisited:     DEFS 96
