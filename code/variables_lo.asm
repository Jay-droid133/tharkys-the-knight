; ==============================================================================
; LOW-RAM VARIABLES — ubicadas en $5D00+ via EQU (no emiten bytes al .tap)
; ==============================================================================
; Reubicacion fase A del plan de ampliacion de bank 2 (mem/expand-bank2):
; mover los buffers/scratch que solo se acceden en cold paths a la zona libre
; del bank 5 ($5800-$7FFF). $4000-$5AFF es VRAM; $5B00-$5CCB es system area
; del 128 (printer buffer + system vars). Empezamos en $5D00 con margen.
;
; IMPORTANTE: los simbolos son EQU, asi que NO se emite ningun byte al .tap.
; El loader deja la zona con valores indeterminados; Inicio: hace zero-fill
; de [LOW_RAM_BASE, LOW_RAM_END) y luego pone los defaults no-cero.
;
; Solo entran aqui variables cuya frecuencia de acceso es practicamente nula
; durante el inner loop. La memoria de $5D00-$7FFF es CONTENDED, asi que
; cualquier variable hot debe seguir en bank 2 ($8000-$BFFF, no-contended).
; ==============================================================================

LOW_RAM_BASE        EQU $5D00

; --- Zone cell list: solo se construye al cambiar de sala (BuildZoneCellList) ---
; y se lee en SpawnOneNasty. Cold path (transition + spawn).
ZoneCellCount       EQU LOW_RAM_BASE
ZoneCellList        EQU ZoneCellCount + 1            ; DEFS 255 * 2

; --- BFS rescue de la muerte: solo se dispara cuando StuckCounter llega a 6 ---
DBfsQueue           EQU ZoneCellList + 510           ; DEFS 108
DBfsQHead           EQU DBfsQueue + 108              ; DEFW
DBfsQTail           EQU DBfsQHead + 2                ; DEFW
DBfsBestDir         EQU DBfsQTail + 2                ; DEFB
DBfsBestDepth       EQU DBfsBestDir + 1
DBfsBestManh        EQU DBfsBestDepth + 1
DBfsPlayerCx        EQU DBfsBestManh + 1
DBfsPlayerCy        EQU DBfsPlayerCx + 1
DBfsCurCx           EQU DBfsPlayerCy + 1
DBfsCurCy           EQU DBfsCurCx + 1
DBfsCurFirstDir     EQU DBfsCurCy + 1
DBfsCurDepth        EQU DBfsCurFirstDir + 1
DBfsTryCx           EQU DBfsCurDepth + 1
DBfsTryCy           EQU DBfsTryCx + 1
DBfsTryDir          EQU DBfsTryCy + 1

; --- Pending erase list: la usa EraseDeadSprites; cuenta>0 es muy raro ---
PendingEraseCount   EQU DBfsTryDir + 1
PendingEraseSlots   EQU PendingEraseCount + 1        ; DEFS 3 * 5

; --- Monster AI v2 cold state: solo se accede en transicion / scared ---
RoomHistory         EQU PendingEraseSlots + 15       ; DEFB 0,0,0
MonsterLastSeenRoom EQU RoomHistory + 3              ; DEFB $FF,$FF,$FF (init explicito)
MonsterLastSeenX    EQU MonsterLastSeenRoom + 3
MonsterLastSeenY    EQU MonsterLastSeenX + 3
MonsterShakeOrigX   EQU MonsterLastSeenY + 3
MonsterShakeOrigY   EQU MonsterShakeOrigX + 3

; --- Cutscene de iglesia: solo accede cuando ChurchCutscenePhase != 0 ---
; ChurchCutscenePhase se queda en bank 2 (lo lee MainLoop cada frame).
ChurchCutsceneFrame      EQU MonsterShakeOrigY + 3
ChurchCutsceneSlot       EQU ChurchCutsceneFrame + 1
ChurchCutsceneTypeIdx    EQU ChurchCutsceneSlot + 1
ChurchCutsceneStatueOrigX EQU ChurchCutsceneTypeIdx + 1
ChurchCutsceneStatueOrigY EQU ChurchCutsceneStatueOrigX + 1
ChurchCutsceneStatueLastX EQU ChurchCutsceneStatueOrigY + 1
ChurchCutsceneStatueLastY EQU ChurchCutsceneStatueLastX + 1
ChurchCutsceneLookCount  EQU ChurchCutsceneStatueLastY + 1

; --- Cutscene final (M9): solo se accede cuando TownGatePhase != 0 ---
; TownGatePhase vive en variables.asm (HOT, lo lee MainLoop cada frame).
TownGateTimer            EQU ChurchCutsceneLookCount + 1
TownGateShakeOffsX       EQU TownGateTimer + 1            ; signed -1 / 0 / +1
TownGateShakeOffsY       EQU TownGateShakeOffsX + 1
TownGateExitStepCnt      EQU TownGateShakeOffsY + 1       ; frames hasta sig. step
TownGateExitWalkFrame    EQU TownGateExitStepCnt + 1      ; toggle 0/1 anim WALK_S
TownGateEndDrawn         EQU TownGateExitWalkFrame + 1    ; 1 = "The End" sprite ya pintado este episodio (one-shot al pasar POSY arch top)

; --- Random pickups: estado de la sala actual ---
; Solo se accede en room-enter (UpdateRandomPickup). Cold path.
;
; Mecanismo: los markers (id RANDOM_SLOT_MARKER=210) viven en el BG stream de
; cada room (screen_rooms.asm) — pintados en plantillas, propagados a siblings
; via auto-sync de la library. El engine los trata como ghost: skipea render
; en sprLoop y collision en bcmLoop. UpdateRandomPickup, en cada transicion:
;   1. Recorre el BG stream de la sala actual (CurrentScreenAddr) buscando
;      id=210. Acumula (charX, charY) en RandomSlotList.
;   2. RNG sobre count: elige un slot.
;   3. RNG sobre PROB_*_END: rolea tipo (life/health/stamina/none).
;   4. Si type != none: rellena RandomSyntheticEntry con la pickup elegida en
;      la posicion del slot. Si type == none o count == 0: marca inactiva ($FE).
;
; pkDrawLoop renderiza RandomSyntheticEntry como pickup adicional al final.
; CheckPickupCollect testea AABB y dispatcha al GiveX al final.

; SlotList: hasta RANDOM_SLOT_MAX pares (charX, charY) de markers encontrados
; en la sala actual. SlotCount = cuantos slots validos hay.
RandomSlotCount         EQU TownGateEndDrawn + 1            ; 0..RANDOM_SLOT_MAX
RandomSlotList          EQU RandomSlotCount + 1             ; RANDOM_SLOT_MAX * 2 = 8 bytes (charX,charY)

; RandomSyntheticEntry: 7 bytes con formato de PickupTable entry. Vive en RAM
; para que pkDrawLoop/cpLoop puedan modificarla. mapX=$FE = inactivo.
RandomSynthMapX         EQU RandomSlotList + (4 * 2)        ; mapX (=$FE inactivo)
RandomSynthMapY         EQU RandomSynthMapX + 1
RandomSynthPtr          EQU RandomSynthMapY + 1             ; DEFW (BgGfx_<type>)
RandomSynthCharX        EQU RandomSynthPtr + 2
RandomSynthCharY        EQU RandomSynthCharX + 1
RandomSynthTint         EQU RandomSynthCharY + 1            ; 255 = sin tint
; Attr byte raw extraido del sprite al activar el synth. Lo usa
; PaintSynthPickupAttrs para pintar los 4 chars del 2x2 sin pasar por el
; remap dia/noche → respeta el color que el usuario puso en el BG editor.
RandomSynthAttr         EQU RandomSynthTint + 1

; --- Roulette: estado del ciclado del random pickup tipo "ruleta" ---
; RouletteActive=1 mientras el synth pickup esta en modo roulette (cicla
; tipos cada ROULETTE_CYCLE_FRAMES). UpdateRoulette tickea el counter y al
; expirar avanza idx en RouletteOrder, recarga sprite + attr del nuevo tipo.
RouletteActive          EQU RandomSynthAttr + 1            ; 0=off, 1=on
RouletteIdx             EQU RouletteActive + 1             ; 0..ROULETTE_ORDER_LEN-1
RouletteFrameCounter    EQU RouletteIdx + 1                ; tick-down

; --- Magic Compass: power-up que muestra ruta exacta sala-a-sala ---
; Recogido por el player (ID34, "compass pickup"). Mientras MagicCompassTimer>0:
;   - DrawCompass override: flecha apunta a la salida correcta (BFS reverse
;     desde ObjectiveScreen hasta CurrentScreen via ScreenGapsTable).
;   - Atributo HUD: paper amarillo, blink ~3 Hz (6 Hz en los ultimos 5s).
;   - SFX: jingle al recoger + tick heartbeat 1/s (2/s en warning).
; Cancela en muerte y al cumplir hito (CurrentObjective avanza).
; Refresh al recoger otra (timer reset a MAGIC_COMPASS_FRAMES).
; Convive con rayo/caracol/mushroom (ortogonal: solo afecta HUD/SFX).
;
; Cold-ish: leido cada frame mientras activo, no-op en frames inactivos.
; 8 bytes total. Variables_lo.asm justifica la zona contended porque el
; coste real son 3 lecturas/frame (timer + path_dir + blink_phase) ~= 30 T.
MagicCompassTimer       EQU RouletteFrameCounter + 1       ; DEFW. 0 = inactivo
MagicCompassPathDir     EQU MagicCompassTimer + 2          ; 0=N,1=S,2=W,3=E,$FF=no path
MagicCompassPathCoord   EQU MagicCompassPathDir + 1        ; char col (N/S) o row (W/E) del gap elegido. $FF si sin path.
MagicCompassPathDirty   EQU MagicCompassPathCoord + 1      ; 1 = recalcular en update
MagicCompassTickActiveFrames EQU MagicCompassPathDirty + 1 ; frames restantes del tick "audible".
                                                            ; Se setea a MAGIC_COMPASS_TICK_DURATION en
                                                            ; cada disparo de tick y decrementa cada frame.
                                                            ; >0 = pitido sonando = char activo bright ON.
                                                            ; =0 = silencio = bright OFF.
MagicCompassTickCounter EQU MagicCompassTickActiveFrames + 1 ; frames hasta sig. AY tick
MagicCompassJingleIdx   EQU MagicCompassTickCounter + 1    ; 0..N-1 activo, $FF inactivo
MagicCompassJingleFrames EQU MagicCompassJingleIdx + 1     ; frames hasta sig. nota

; --- Magic compass BFS multi-componente ---
; El BFS opera con state (sid, comp_local). Comp_local 0..2 indica zona
; walkable interna de la sala (re-indexada por tamaño descendente — comp 0
; = la principal). Aquí solo viven head/tail + LastEntrySide; el grueso
; del scratch (visited bitmap + cola) está en slot 1 ($7000+) declarado
; junto al código del BFS para no empujar LOW_RAM_END > $6000.
MagicCompassBfsHead      EQU MagicCompassJingleFrames + 1   ; uint8 wrap mod 64
MagicCompassBfsTail      EQU MagicCompassBfsHead + 1        ; uint8 wrap mod 64

; LastEntrySide: side por el que el player entró a la sala actual (0=N,1=S,
; 2=W,3=E, $FF=sin entrada / boot / respawn). CheckScreenTransition lo set al
; cruzar borde. ComputeMagicCompassPath lo lee para decidir el comp inicial
; del player al iniciar el BFS reverse. Cold path (1 lectura por transición).
LastEntrySide            EQU MagicCompassBfsTail + 1        ; uint8
; LastEntryCoord: coord aproximado del char por el que entró el player.
;   - Cruzó N o S → POSX / 8 (charX, 0..29).
;   - Cruzó W o E → (POSY - 16) / 8 (charY top-left, 0..19).
; Necesario para desambiguar cuando una sala tiene múltiples gaps en el
; mismo side pero distintos comps (e.g. (5,12) con E@3 comp 1 y E@11 comp 0).
LastEntryCoord           EQU LastEntrySide + 1              ; uint8
; LastMagicCompassDrawn: cache del PathDir del último frame que dibujó el
; sprite Sprite_Compass_Magic. $FF = sprite no dibujado (magic inactiva o
; pantalla recién cargada). Permite saltarse el re-vuelco de 32 bytes pixel
; cada frame mientras magic está activa: si el path no cambió, solo pintamos
; los 4 attrs. Reduce CPU durante el wobble (9 frames post-transición) y
; libera presupuesto del frame para que las agujas del reloj no parpadeen.
LastMagicCompassDrawn    EQU LastEntryCoord + 1             ; uint8 ($FF=invalid)
; MagicCompassBfsState: 0 = BFS idle. 1 = BFS in progress (queue+visited
; persistidos entre frames). El BFS se amortiza en chunks de
; MAGIC_COMPASS_BFS_ITERS_PER_FRAME (8) iteraciones para evitar gastar
; >10000 T-states de golpe en un único frame post-transición — eso quitaría
; presupuesto al renderizado del HUD y haría parpadear las agujas del reloj.
MagicCompassBfsState     EQU LastMagicCompassDrawn + 1      ; uint8

; ==============================================================================
; Random pickup memory — anti-reroll por cambio de sala
; ==============================================================================
; Recuerda el spawn de la sala inmediatamente anterior. Al volver a esa sala,
; se restaura el mismo slot + tipo (no rerollea). Si el pickup fue consumido,
; cur.rolled = ROLLED_NONE y al volver tampoco respawnea (anti-farm).
;
; CRÍTICO: estas vars van AL FINAL de low-RAM (después de MagicCompassBfsState)
; para NO shiftear MagicCompass* — el intento previo (commit d8580f3) las
; insertó en medio y rompió por interacción aún no diagnosticada.
;
; Init en Inicio: cur.sid = prev.sid = $FF (no hits espurios al boot, ya que
; sala $00 = (0,0) sería un sid válido y un default 0 daría hit falso).
; Slot/Rolled se quedan en 0 (zero-fill cubre).
; ==============================================================================
RP_CurSid           EQU MagicCompassBfsState + 1        ; sid actual ($FF=vacío)
RP_CurSlot          EQU RP_CurSid + 1                   ; slot index (0..count-1)
RP_CurRolled        EQU RP_CurSlot + 1                  ; ROLLED_* (0..8)
RP_PrevSid          EQU RP_CurRolled + 1                ; sid anterior ($FF=vacío)
RP_PrevSlot         EQU RP_PrevSid + 1
RP_PrevRolled       EQU RP_PrevSlot + 1
RP_TmpSlot          EQU RP_PrevRolled + 1               ; scratch para rotación
RP_TmpRolled        EQU RP_TmpSlot + 1                  ; scratch para rotación

; --- Variant memory: HEALTH/STAMINA recuerdan la variante exacta entre salas ---
; Cuando el roll cae en HEALTH o STAMINA, PickRandomVariantPtr elige una variante
; visual (HealthVariantPtrs / StaminaVariantPtrs). Sin memoria, revisitar la sala
; muestra otra variante → "respiración" visual. Con memoria, revisitar muestra
; exactamente la misma variante mientras el pickup no se haya recogido.
;
; Para tipos NO-variante (life/rayo/caracol/mushroom/compass/roulette): el campo
; se rota pero nunca se lee. Stale values son inocuos.
RP_CurVariant       EQU RP_TmpRolled + 1                ; variant idx persistido en cache cur
RP_PrevVariant      EQU RP_CurVariant + 1               ; variant idx persistido en cache prev
RP_TmpVariant       EQU RP_PrevVariant + 1              ; scratch (PickRandomVariantPtr lo escribe)

; --- Player color cycler ---
; Frame counter para el cycler de color player. Incrementa cada frame; el
; slot activo del cycle es (PlayerColorCyclerFrame / COLOR_CYCLER_PERIOD) mod N
; donde N es el numero de buffs/debuffs activos. Wrap natural a 256 frames.
PlayerColorCyclerFrame  EQU RP_TmpVariant + 1

; --- Buff timers nuevos (fase 3 del revamp pickups) ---
; ESPADA: ataque sin coste de stamina + sin cooldown durante ESPADA_BUFF_FRAMES.
; ESCUDO: invulnerabilidad contra nasti/monster contact (knockback persiste)
;         durante ESCUDO_BUFF_FRAMES.
; Ambos 16-bit (igual que SpeedBuffTimer / MushroomLockTimer). Cycler lee
; estos timers para decidir si pintar RED (espada) o YELLOW (escudo) en el
; player attr. Gates en logic_game.asm consultan el timer correspondiente.
EspadaTimer             EQU PlayerColorCyclerFrame + 1      ; DEFW. 0 = inactivo
EscudoTimer             EQU EspadaTimer + 2                 ; DEFW. 0 = inactivo

; --- Random pickup synth: attrs por celda del 2x2 ---
; RandomSynthAttr (arriba) = TL. Aquí los 3 restantes para preservar el
; patrón per-celda que el usuario pinta en el BG editor (p.ej. col1 bright,
; col2 dim). Sin esto PaintSynthPickupAttrs aplicaría TL a las 4 celdas y
; perdería la info de TR/BL/BR. Van al final para no shiftear MagicCompass*.
RandomSynthAttrTR   EQU EscudoTimer + 2
RandomSynthAttrBL   EQU RandomSynthAttrTR + 1
RandomSynthAttrBR   EQU RandomSynthAttrBL + 1

LOW_RAM_END         EQU LastEntrySide + 1
LOW_RAM_SIZE        EQU LOW_RAM_END - LOW_RAM_BASE
