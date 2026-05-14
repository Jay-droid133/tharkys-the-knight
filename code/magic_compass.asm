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
    ; Desactivar el jingle viejo (3 notas via .umcUpdateJingle): el chime de
    ; recogida lo hace ahora un sweep AY tipo PlayerHit (mas chuleria). Idx
    ; queda en $FF para que el ticker viejo sea no-op pero quede por si en
    ; el futuro se quiere reactivar.
    LD A, $FF
    LD (MagicCompassJingleIdx), A
    ; SFX al recoger: sweep ascendente AY canal B. Lasting tiene PIN extra.
    LD A, (MagicCompassPermanent)
    OR A
    JP NZ, AY_PlayLastingPickup         ; lasting: sweep largo + PIN (~1.12s)
    JP AY_PlayCompassPickup             ; random: sweep corto (~640ms)

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
    LD A, (MagicCompassPermanent)
    OR A
    RET NZ                               ; lasting compass: nunca cancelar
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
    LD (MagicCompassPathCoord), A        ; borra coord cached (gap hint sprite)
    LD (LastMagicCompassDrawn), A        ; invalida cache de sprite HUD
    LD (MagicCompassJingleIdx), A        ; detiene jingle (si estaba sonando)
    LD (PreviousObjectiveDistance), A    ; fuerza redraw del HUD el siguiente
                                         ; frame: DrawCompass detecta $FF y
                                         ; entra a .dcRedraw, sustituyendo el
                                         ; sprite_compass_magic stale por la
                                         ; brujula clasica (8 flechas + X).
    RET

; ==============================================================================
; RefreshMagicCompassForNewObjective - Recompute path tras avance de hito
; ==============================================================================
; Llamado desde CheckMilestonePickup/Trigger/DebugKey tras CancelMagicCompass.
;
; Caso normal (random pickup, no Permanent): CancelMagicCompass ya zappeo el
; timer a 0; aqui retornamos inmediatamente sin tocar nada (no-op).
;
; Caso lasting compass (Permanent=1): CancelMagicCompass retorno sin tocar el
; estado, asi que el timer sigue activo. El BFS anterior dejo MagicCompassPathDir
; en $FF (current_sid == target_sid en el momento del pickup), lo que hace que
; DrawCompass cayera en .dcMagicOff y renderizara la brujula clasica. Sin
; recompute aqui, la brujula clasica persistia hasta el siguiente cambio de
; sala (donde CheckScreenTransition llama a ForceComputeMagicCompassPath).
;
; Recompute sincrono = brujula magica vuelve a apuntar al NUEVO objetivo en el
; mismo frame del pickup. Coste: ~10K T-states (~14% del frame), una sola vez
; por avance de hito; gameplay normal no afectado.
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
RefreshMagicCompassForNewObjective:
    LD A, (MagicCompassTimer)
    LD B, A
    LD A, (MagicCompassTimer + 1)
    OR B
    RET Z                                ; magic inactiva: no-op
    LD A, $FF
    LD (LastMagicCompassDrawn), A        ; invalida cache HUD
    JP ForceComputeMagicCompassPath      ; tail call: BFS sincrono al nuevo goal

; ==============================================================================
; ForceComputeMagicCompassPath - Corre el BFS COMPLETO sincronicamente.
; ==============================================================================
; Llamado desde CheckScreenTransition al cruzar borde con magic activa.
; Garantiza que MagicCompassPathDir refleja la sala NUEVA antes de que el
; HUD se redibuje y antes de que UpdateMagicCompass pueda disparar el primer
; tick post-cruce. Sin esto, el BFS amortizado tarda 3-4 frames en converger
; y los primeros ticks de la nueva sala muestran el flash apuntando a la
; direccion vieja (de la sala anterior).
;
; Coste: ~10000 T-states una sola vez por cruce (~14% de un frame). El frame
; del cruce ya es el mas pesado por DrawScreen, asi que nos comemos el spike
; solo en transiciones — nunca en frames de gameplay normal.
;
; Estrategia: setea BfsState=0 (descartando cualquier BFS in-progress de la
; sala anterior, que tendria current_sid stale) y loop CALL/check hasta
; BfsState vuelva a 0 (= terminado, sea con path o sin path). Cada call
; ejecuta un chunk de MAGIC_COMPASS_BFS_ITERS_PER_FRAME iteraciones; el
; overhead extra de los chunks (~30 T-states por loop) es despreciable.
;
; Destruye: AF, BC, DE, HL.
; ==============================================================================
ForceComputeMagicCompassPath:
    XOR A
    LD (MagicCompassBfsState), A         ; descarta BFS amortizado in-progress
.fcmcpLoop:
    CALL ComputeMagicCompassPath         ; ejecuta un chunk; setea state=0 al
                                         ; terminar (.cmcpFound o .cmcpNoPath)
    LD A, (MagicCompassBfsState)
    OR A
    JR NZ, .fcmcpLoop                    ; aun en progreso → otro chunk
    XOR A
    LD (MagicCompassPathDirty), A        ; ya recalculado, no necesita rerun
    ; Forzar tick INMEDIATO en la nueva sala: TickCounter=0 hace que
    ; UpdateMagicCompass dispare .umcTickFire en el siguiente frame, sin
    ; esperar a que el contador llegue a 0 de forma natural (que podia
    ; tardar hasta 50 frames = 1 segundo). El player ve flash + suena AY
    ; al instante de cruzar, con la flecha correcta.
    ; TickActiveFrames=0 mata cualquier flash residual del tick que estaba
    ; en curso en la sala anterior — evita 1-2 frames de bright apuntando
    ; a la dir vieja entre el cruce y el nuevo tick.
    LD (MagicCompassTickCounter), A
    LD (MagicCompassTickActiveFrames), A
    RET

; ==============================================================================
; UpdateMagicCompass - Tick por frame (timer, blink, AY tick, path)
; ==============================================================================
; (Jingle viejo de 3 notas eliminado — el SFX de pickup ahora usa _AY_PlaySweep
; via AY_PlayCompassPickup/AY_PlayLastingPickup, no necesita ticker).
; ==============================================================================
UpdateMagicCompass:
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
    ; Disparar wobble del HUD compass clasico como senal visual de que el
    ; power-up se acabo: 9 frames de oscilacion antes de quedarse en la
    ; flecha del target. .dcWobbleStartNormal en DrawCompass aplica los
    ; overrides per-frame; idx==4 (X) sigue sin oscilar (early-skip ya en
    ; el codigo del wobble).
    LD A, 9
    LD (CompassWobbleCounter), A
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
    ; Activar bright visual durante la duración del beep (parpadeo del char
    ; activo del HUD). Para la lasting compass, conservamos este flash —
    ; le da vida visual a la brujula sin molestar — pero silenciamos el
    ; audio mas abajo.
    LD A, MAGIC_COMPASS_TICK_DURATION
    LD (MagicCompassTickActiveFrames), A
    ; Lasting compass: silenciar el AY tick. El "tick tick" eternamente
    ; cada segundo molesta cuando llevas la lasting compass mucho tiempo.
    ; Para la magic compass normal (no Permanent) se queda igual: el tick
    ; es informativo y la brujula expira en 30 s.
    LD A, (MagicCompassPermanent)
    OR A
    JR NZ, .umcAfterTick                 ; lasting → skip beep
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

; .umcUpdateJingle ELIMINADO. Junto con MagicCompassJingleTable libera ~50 B
; en slot 1, evitando overflow de las variables del BFS sobre la tabla IM 2
; del IRQ handler ($7A00). El SFX de pickup ahora usa _AY_PlaySweep via
; AY_PlayCompassPickup/AY_PlayLastingPickup (sfx_player_hit_ay.asm).

; ==============================================================================
; PaintMagicCompassAttrs - Pinta los 4 chars del HUD compass en modo magic
; ==============================================================================
; Color base lo decide el editor (sprite id 36, attrBytes). El runtime lo lee
; de MagicCompassBaseAttrs (auto-importado por import_magic_compass_hud.py).
;
; El blink del char activo (sincronizado con MagicCompassTickActiveFrames) ya
; no vive aqui — ahora lo hace DrawCompassGapHint, que oculta/muestra el sprite
; de flecha 16x16/16x24 sobre el gap real. El HUD 2x2 queda estatico.
;
; Destruye: AF, DE, HL.
; ==============================================================================
PaintMagicCompassAttrs:
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
    RET

; MagicCompassJingleTable ELIMINADO (12 B). Pickup chime ahora via _AY_PlaySweep.
; .pmcaDirToOffset ELIMINADO (4 B) — blink del char activo desplazado al gap hint.

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
; ComputeMagicCompassPath — wrapper que pagina bank 7 alrededor del BFS.
;
; Tanto las tablas RoomCompGaps_XX como ahora el body _ComputeMagicCompassPath_Inner
; (+ sus helpers .cmcp* / .cfmg* / .fgbs* y locales DEFB) viven en bank 7
; (magic_compass_bfs_bank7.asm). Se movieron alli en mayo 2026 cuando los
; thunks de bank_cutscene_thunks.asm anadieron ~135 B a slot 1 y empujaron el
; BFS sobre $7A00 (la tabla IM2 sobreescribia el codigo BFS con $7B -> BFS
; retornaba basura -> magic compass siempre PathDir=$FF). Mover ~690 B a
; bank 7 dejo margen amplio en slot 1.
;
; Stack consistency: el caller (UpdateMagicCompass en slot 1) ENTRA con bank 0
; paginated. El wrapper pagina bank 7, CALL _Inner (PUSH PC en bank 7 stack).
; _Inner ejecuta todo (CALL/RET/PUSH/POP) con bank 7 stack consistente.
; Tras RET, el wrapper pagina bank 0 antes de su propio RET, asi que el caller
; recupera su return PC del bank 0 stack (donde fue pushed originalmente).
;
; Mantiene DI durante todo el chunk BFS (~4000 T = 1/15 frame). Riesgo de
; perder ~3 IRQ por segundo de compass activo, aceptable.
; ==============================================================================
ComputeMagicCompassPath:
    DI
    ; --- Page bank 7 in slot 3 ---
    LD A, (CurrentPaging)
    AND $F8
    OR 7
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    CALL _ComputeMagicCompassPath_Inner

    ; --- Page bank 0 back ---
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    LD A, (StartupComplete)
    OR A
    RET Z                                ; aún en Inicio: dejar DI
    EI
    RET

; _ComputeMagicCompassPath_Inner — movido a magic_compass_bfs_bank7.asm.
;
; A continuacion habria seguido todo el BFS body + helpers + locales DEFB,
; pero ahora vive en bank 7. El label `_ComputeMagicCompassPath_Inner` se
; resuelve a una direccion $C000+ que solo es visible cuando bank 7 esta
; paginated; el wrapper de arriba se ocupa de eso.

; Resto del archivo eliminado (movido a magic_compass_bfs_bank7.asm).
; Aqui solo quedan los includes finales que NO viven en bank 7:

    IF 0
; Lo que sigue era el contenido viejo de _ComputeMagicCompassPath_Inner.
_ComputeMagicCompassPath_Inner_OLD:
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
    ; Save gap coord para que DrawCompassGapHint pueda dibujar en el gap concreto
    LD A, (.cmcpGapCoord)
    LD (MagicCompassPathCoord), A
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
    LD (MagicCompassPathCoord), A
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
    ENDIF                            ; fin del IF 0 que envuelve el _OLD body

; ==============================================================================
; Sprite_Compass_Magic - 32 bytes raw (16x16 px) del HUD compass mágico.
; ==============================================================================
; Auto-importado desde sprite ID 36 ("magic compass HUD") de bg_sprites.json
; via tools/import_magic_compass_hud.py (des-CPL'd para encajar el formato
; raw que espera DrawCompassSprite).
; ==============================================================================
    INCLUDE "sprite_magic_compass_hud.inc"

; ==============================================================================
; Storage scratch — printer-buffer area $5B00..$5BDF (bank 5, slot 1 always-on)
; ==============================================================================
; Visited bitmap: 96 bytes (768 bits = 256 sids × 3 comps).
; Cola FIFO: 128 bytes (64 entries × 2 bytes (sid, comp)).
; head/tail viven en variables_lo (LOW_RAM).
;
; Por qué $5B00 (EQU, no DEFS):
;   * Históricamente estos arrays vivían al final de magic_compass.asm como
;     DEFS, lo que los colocaba en $795C..$7A3B. Los últimos 60 bytes de
;     `Visited` solapaban la tabla IM 2 ($7A00..$7B00 con $7B), y cuando el
;     BFS inicializaba `Visited` con LDIR reescribía $7A00..$7A3B con basura.
;     En hardware real funcionaba sólo por accidente del bus flotante:
;     durante IRQ ack el bus pone $FF, así que el vector se leía de $7AFF /
;     $7B00 (zona intacta) → $7B7B → handler ok. Pero en emuladores cuyo bus
;     toma valores en $00..$3B (chips/zx.h sin parche de bus flotante,
;     posiblemente otros) saltaba a un vector basura y colgaba el juego al
;     recoger la brújula mágica.
;   * Solución: reubicar las dos tablas a $5B00 (printer buffer). Es bank 5,
;     mismo slot 1, mismo coste de acceso. La zona $5B00..$5DFF está excluida
;     del .tap por SAVETAP y el juego nunca usa rutinas de PRINT ROM ni
;     paginación a 48K. Como son scratch RAM (BFS las inicializa antes de
;     usarlas), no necesitamos preservar su contenido entre cargas.
;   * Coste: 0 bytes en .tap, +224 bytes libres en slot 1 (de 64 → ~288 libres).
;
; Documentación canónica: docs/magic_compass.md (sección "BFS scratch RAM").
MagicCompassBfsQueue:    EQU $5B00        ; 128 B → $5B00..$5B7F
MagicCompassVisited:     EQU $5B80        ; 96 B  → $5B80..$5BDF
