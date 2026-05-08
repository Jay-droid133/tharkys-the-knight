; ==============================================================================
; VARIABLES EN RAM MANTENIDAS POR EL JUEGO
; ==============================================================================

GameFrameCounter:   DEFB 0      ; Contador que incrementa cada frame (0-255)
GameState:          DEFB 0      ; Estado: 0=Menu, 1=InGame, 2=GameOver

; Flag de fin-de-Inicio. Las rutinas de paginacion lo consultan para decidir
; si tras su DI deben volver a EI (ya en main loop) o dejarlo deshabilitado
; (todavia en Inicio). Sustituye al patron LD A,I/PUSH AF que es vulnerable
; al bug del Z80 (race con IRQ durante LD A,I -> P/V mal -> EI saltado ->
; HALT permanente). Set a 1 justo tras el EI final de Inicio.
StartupComplete:    DEFB 0

; ==============================================================================
; TABLA DE ENTIDADES (estilo Sabre Wulf)
; ==============================================================================
; 17 slots × 16 bytes = 272 bytes.
; Slot 0: Player. Slots 1-6: Inmortales. Slots 7-10: Nasties. Slot 11: Muerte.
; Slot 12: libre. Slots 13-16: Objetos.
; Cada entidad: SpriteID, Type, State, PosX, PosY, Attr, DeltaX, DeltaY,
;               AnimBase, AnimTimer, Dir, Flags, OldX, OldY, OldSprID, DrawX
; ==============================================================================
EntityTable:        DEFS NUM_ENTITIES * ENT_SIZE

; --- Input crudo ---
InputDirection:     DEFB 0      ; Direccion leida del teclado este frame
InputFire:          DEFB 0      ; Fuego leido del teclado este frame

; --- Debug: noclip (tecla N togglea) ---
NoclipMode:         DEFB 0      ; 0 = colision normal, 1 = sin colision (atraviesa todo)

; --- Sistema de llaves/candados (6 sets sucesivos) ---
; 0=ninguna, 1=Forest, 2=Ruins, 3=Cemetery, 4=ClockTower, 5=Church, 6=TownGate.
; Solo una llave a la vez: se consume al abrir el candado correspondiente.
CurrentKey:         DEFB 0
; Stash temporal: behavior del pickup tocado (0=normal, 1-7=key id, 8-13=lock id+7)
PickupCurBehavior:  DEFB 0

; --- Flags de progresión por puzzle (lineales, no se resetean) ---
; ChurchKeySpawned: 0 = pickup latente oculto / 1 = visible y recogible.
;                   Se activa al tocar BgGfx_town_hall_door con ClockTower Key.
; ChurchDoorOpen:   0 = puerta cerrada (bloquea) / 1 = abierta (deja pasar,
;                   habilita la mecánica de muerte de monstruos).
;                   Se activa al abrir BgGfx_church_door_closed con Church Key.
ChurchKeySpawned:   DEFB 0
ChurchDoorOpen:     DEFB 0
; ChurchEverOpened: 1 desde la 1a vez que se abrio la iglesia (sticky, no se
; limpia al cerrarla por la trampa). Usado por HighlightExpectedStatue para
; saber si el "sello" ya esta roto y debe pintar el highlight de la estatua
; aunque la puerta este cerrada en este momento (ej. durante la cutscene
; de captura, justo antes de respawnear la church_key).
ChurchEverOpened:   DEFB 0

; TimeFrozen: 0 = corre normal. !=0 -> UpdateGameClock retorna sin avanzar.
; Solo afecta al reloj de juego (GameSubMinute/Minutes/Hours) y por extension
; al ciclo dia/noche. Spawn de monstruos, AI, campanadas, todo lo demas
; funciona normal porque usa timers de frame (SYS_FRAMES) independientes.
;   Valores:
;     1 = congelado con parpadeo de la esfera (church trap, feedback visual).
;         Set: al abrir la puerta de la iglesia 1a vez (.cbtActChurchDoor).
;         Clear: ApplyChurchTrapDone (todos los bits MonsterTrappedFlags set).
;     2 = congelado sin parpadeo (muerte del player — el border yellow/red
;         es ya feedback suficiente).
;         Set: OnPlayerHealthDepleted.
;         Clear: urb1LastBeat (control vuelve en phase 2 del respawn).
TimeFrozen:         DEFB 0

; BlockedExitSoundFlag: debounce del SFX "no puedes salir" (SFX_BlockedExit).
; 1 = ya sono en este "intento" (jugador presionando S contra el borde sur).
; Se limpia cuando el jugador suelta S o se aleja del borde -> proximo intento
; volvera a sonar. Sin debounce sonaria cada frame y haria ruido continuo.
BlockedExitSoundFlag: DEFB 0

; NoSwordSoundFlag: debounce del SFX corto de error cuando el player intenta
; atacar con la seta activa (mushroom debuff bloquea InputFire). 1 = ya sono
; durante esta pulsacion. Se limpia al soltar fire -> proxima pulsacion
; volvera a sonar. Sin debounce sonaria cada frame mientras se mantiene fire.
NoSwordSoundFlag: DEFB 0

; BellsTriggered: 0 = campanadas no sonaron aun / 1 = ya sonaron.
; Setea ON cuando se dispara StartBellChimes desde cualquier path
; (medianoche natural en day_cycle.asm O abrir iglesia primera vez).
; Sirve para:
;   - Evitar que .bellsFirst dispare bells dos veces (idempotente).
;   - Evitar que TriggerChurchMidnight salte reloj atras si ya es noche
;     cerrada (caso "abrir iglesia tras medianoche natural" -> no-op).
BellsTriggered:     DEFB 0

; --- Cadena de hitos (CurrentObjective) ---
; Byte = objetivo actual (0..8). 9 = todos los hitos completados.
; Tabla y logica de avance en milestones.asm.
CurrentObjective:   DEFB 0
; Pantalla (sx, sy) del hito actual cacheada por ResolveObjectiveScreen.
; $FF = no resuelto (target sin colocar). Se recalcula al avanzar de hito.
ObjectiveScreenX:   DEFB $FF
ObjectiveScreenY:   DEFB $FF
; Estado de la brujula (HUD). PreviousObjectiveDistance = $FF significa
; "primer cruce con este hito, sin distancia anterior" -> render blanco.
; LastCompassScreenX/Y = ultima pantalla en la que se renderizo (para
; detectar transicion sin redibujar cada frame).
PreviousObjectiveDistance: DEFB $FF
LastCompassScreenX: DEFB $FF
LastCompassScreenY: DEFB $FF
; Wobble: al entrar a una pantalla nueva la brujula vibra entre las cuatro
; direcciones contiguas (clockwise: prev2/prev/next/next2) antes de quedarse
; fija en la real.
; Counter en [0..9]; 0 = sin wobble. Decrementa 1 por frame en DrawCompass.
; La X (idx=4) NO vibra: si el target es X, el counter no se setea.
CompassWobbleCounter: DEFB 0

; --- Trampa de la iglesia (paso 7) ---
; MonsterTrappedFlags: bit 0 = slot 0 atrapado, bit 1 = slot 1, bit 2 = slot 2.
; Cuando los 3 estan atrapados (= %00000111), avanza CurrentObjective 7 -> 8.
MonsterTrappedFlags: DEFB 0
; Orden fijo de captura (la iglesia "pide" un monstruo concreto cada vez):
; step 0 = zombi, step 1 = ghost, step 2 = skeleton, step 3 = todos atrapados.
; Usado por CheckChurchTrap (solo el tipo esperado dispara la trampa; los
; demas rebotan como wall) y por la rutina de resaltado de estatua.
NextChurchTrapStep:  DEFB 0
; Frames restantes del blink ON-OFF de la estatua que se acaba de "encender".
; 0 = sin blink activo. Driver: UpdateStatueBlink (llamado cada frame).
StatueBlinkCounter:  DEFB 0
; ChurchKeyAltSpawnIdx: 0 = inicial (town hall, lo coloca el editor),
; 1 = AltKey1 (tras 1er trap), 2 = AltKey2 (tras 2o trap). >= 3 = no respawn
; (los 3 monstruos atrapados, spawnea south key en su lugar).
ChurchKeyAltSpawnIdx: DEFB 0
; TownGateKeySpawned: 0 = pickup latente / 1 = visible. Se activa al cerrar
; la trampa con el 3er monstruo. Misma logica de DormantPickupTable que la
; church_key en su tiempo.
TownGateKeySpawned: DEFB 0

; --- Bank cutscene (M9 propuesto) — flags de pickups latentes ---
; BankCheckSpawned: cheque que reemplaza a TownGateKey como drop tras la
; trampa de la iglesia. Player debe llevar el cheque al banco.
; BankKeySpawned:  llave de la ciudad que aparece tras la cinematica del
; banco (visualmente BankKey en vez del antiguo town_gate_key).
BankCheckSpawned:   DEFB 0
BankKeySpawned:     DEFB 0
; Cutscene de la iglesia. 0 = inactiva, gameplay normal. >=1 = activa,
; gameplay pausado (player frozen, otros monsters frozen, reloj pausado).
;   1 = SHAKE     (monster tiembla en el vano)
;   2 = DOOR_CLOSE (puerta se cierra)
;   3 = STATUE_ERASE (estatua del slot desaparece - placeholder, sin sprites aun)
;   4 = DONE      (un frame de limpieza)
ChurchCutscenePhase:    DEFB 0      ; 0=off, 1=LOOK_MONSTER, 2=SHAKE_STATUE, 3=DONE
; ChurchCutsceneFrame/Slot/TypeIdx/StatueOrigX/Y/LastX/Y/LookCount: en variables_lo.asm

; Pausa cinematografica tras la 3a captura del cutscene de iglesia. Cuenta
; de 50 a 0 (2s @ 25fps). En frame 25 (1s) aparece town_gate_key + avance
; milestone. En frame 0 (2s) los nasties pueden volver a spawnear. Durante
; el periodo, TrySpawnNasty hace early-RET via guard.
PostTrapPauseTimer:     DEFB 0

; Cutscene final del juego (M9, puerta sur). 0 = inactiva (gameplay normal).
; >=1 = activa (gameplay pausado, MainLoop salta a UpdateTownGateCutscene).
; Lectura cada frame en MainLoop: queda en bank 2 (HOT). Resto del estado
; (timer, shake offsets, exit step counter) en variables_lo.asm.
TownGatePhase:          DEFB 0

; Cutscene del banco (M9 nuevo, antes de town_gate). 0 = inactiva. >=1 = activa
; (MainLoop salta a UpdateBankCutscene). HOT (lectura cada frame en gating).
; Resto del estado se queda aqui en bank 2 — son ~5 B mas de cold-during-cutscene
; (Timer, SubState, KnockIdx, NoIdx, HandFrame). variables_lo.asm tiene un
; problema latente con LOW_RAM_END y prefiero no tocarlo.
BankCutscenePhase:      DEFB 0
BankCutsceneTimer:      DEFB 0
BankCutsceneSubState:   DEFB 0      ; 0=HIT, 1=GAP dentro de un grupo de toques
BankCutsceneKnockIdx:   DEFB 0      ; toques emitidos en el grupo actual
BankCutsceneNoIdx:      DEFB 0      ; swaps "no no" emitidos
BankCutsceneHandFrame:  DEFB 0      ; frame actual de la mano (0/1)
; ArmRevealed / FingerRevealed: pickups latentes que NUNCA se "spawnean"
; via flag (siempre 0). El cutscene los dibuja con RedrawPickupByPtr aunque
; el flag siga 0; el resto del codigo (DrawScreen, CheckPickupCollect)
; consulta IsPickupDormant y los trata como inactivos. Asi no se pueden
; recoger ni quedan pintados al re-renderizar la pantalla.
ArmRevealed:    DEFB 0
FingerRevealed: DEFB 0

; Pickup flash: cuando un pickup spawnea (vía bump-trigger u otra acción),
; el sprite parpadea on/off con XOR redraw para llamar la atención.
; UpdatePickupFlash hace un toggle cada PICKUP_FLASH_PERIOD frames durante
; PickupFlashToggles toggles restantes. Termina visible (toggles par).
PickupFlashToggles: DEFB 0      ; toggles restantes (0 = sin parpadeo activo)
PickupFlashFrames:  DEFB 0      ; frames hasta el próximo toggle
PICKUP_FLASH_PERIOD EQU 3       ; frames entre toggles (~60ms a 50Hz, ~16Hz)

; --- Movimiento del player (fiel a Sabre Wulf turns_per_player_move) ---
PlayerMoveTimer:    DEFB 1      ; Countdown: mueve cuando llega a 0, reset a PLAYER_MOVE_TURNS

; --- Velocidad efectiva del player (modificable por buffs rayo/caracol) ---
; Defaults inicializados en Inicio: a SPEED_RUN/SPEED_FIGHT. UpdateSpeedBuff
; los modifica al recoger pickup rayo (1.5x) o caracol (0.5x) durante 15s.
; UpdatePlayerMovement los lee cada frame (hot path).
PlayerSpeedRun:     DEFB 4      ; SPEED_RUN default (placeholder, overrides en Inicio)
PlayerSpeedFight:   DEFB 2      ; SPEED_FIGHT default
; SpeedBuffTimer: 0 = sin buff. >0 = frames restantes (16-bit, max 65535).
; 15s @ 25fps = 375 frames cabe en 16 bits. Tick en UpdateSpeedBuff cada frame.
SpeedBuffTimer:     DEFW 0
; SpeedBuffType: 0=none, 1=rayo, 2=caracol. Determina color del player attr
; aplicado por UpdateSpeedBuff cada frame mientras el buff esta activo.
SpeedBuffType:      DEFB 0

; --- Mushroom debuff: bloquea ataque durante MUSHROOM_LOCK_FRAMES ---
; >0 = bloqueo activo. Tickea en UpdateMushroomBuff cada frame. ReadInput
; mascara InputFire a 0 si != 0. Player attr = magenta bright mientras dura.
MushroomLockTimer:  DEFW 0

; --- Render Y del player: POSY + offset si hay celda ocupada justo encima ---
PlayerDrawY:        DEFB 0
EnemyDrawY:         DEFB 0       ; Y renderizado por ProcessOneEnemy (monster +1 si techo pegado, resto = POSY)

; --- Player lives ---
PlayerLives:        DEFB PLAYER_LIVES_INIT
GameOver:           DEFB 0          ; 1 = game over (gameplay congelado, pantalla GAME OVER)

; --- Game over moonwalk anim ---
; En GameOver=2, MainLoop llama UpdateGameOverAnim cada frame. Death se desliza
; por la pantalla negra haciendo moonwalk: facing R + slide L → facing L + slide R.
; Init en PaintGameOverScreen. Reset (todo a 0) en InitGameState.
GameOverAnimX:        DEFB 0        ; X actual del sprite (0..224)
GameOverAnimDir:      DEFB 0        ; 0 = facing R (slide L), 1 = facing L (slide R)
GameOverAnimFrame:    DEFB 0        ; 0 = primer frame del par, 1 = segundo
GameOverAnimFrameTimer: DEFB 0      ; Tick para R0↔R1 swap
GameOverAnimLastSpr:  DEFW 0        ; Ptr al sprite dibujado en frame anterior (0 = ninguno)
GameOverAnimLastX:    DEFB 0        ; X dibujado en frame anterior

; --- Death border flash: tras morir, 2s amarillo + 3s rojo ---
; DeathBorderPhase: 0=inactivo, 1=yellow (anim muerte), 2=red (player invisible).
; Phase 1 dispara UpdateDeathAnim cada frame (override SPRITEID a death anim).
; Phase 2 cambia SPRITEID a SPRID_PLAYER_BLANK (XOR no-op = invisible).
DeathBorderPhase:   DEFB 0
DeathBorderTimer:   DEFB 0          ; Frames restantes en la fase actual
PlayerDeathAnimTimer: DEFB 0        ; Tick de la anim de muerte (frames hasta avanzar)
PlayerDeathAnimFrame: DEFB 0        ; Indice del frame actual (0..PLAYER_DEATH_ANIM_FRAMES)

; --- Respawn blink machine: 0=off, 1=countdown 3-2-1, 2=grace fast blink ---
; Ambas fases invulnerables. Phase 1 input gateado (sin control); phase 2 con control.
PlayerRespawnPhase:    DEFB 0
PlayerRespawnTimer:    DEFB 0       ; Phase 1: frames hasta siguiente beat. Phase 2: frames hasta fin de gracia.
PlayerRespawnBlinkTimer: DEFB 0     ; Phase 1: frames de flash off restantes. Phase 2: frames hasta siguiente toggle.
PlayerRespawnVisible:  DEFB 1       ; 1 = sprite normal, 0 = override a BLANK (invisible)
PlayerRespawnBeatIdx:  DEFB 0       ; Phase 1: 0..2 indica que beat toca (3 = no quedan)

; --- Monsters frozen during player death sequence ---
; Set en FreezeMonstersFacingCorpse (al morir el player). Limpiado en
; urb1LastBeat (cuando vuelve el control). ProcessOneEnemy gatea TYPE_MONSTER
; saltando la AI y solo refresca el draw via .peCalcAndDraw.
MonstersFrozen:     DEFB 0
CorpseX:            DEFB 0           ; Snapshot de PlayerPOSX al morir (= centro del cadaver)
CorpseY:            DEFB 0

; --- Tombstones (storage en bank 7 $E000, 200 entradas x 4 bytes) ---
; Counter en bank 2 (siempre visible). Reset en InitGameState (fresh game).
TombstoneCount:     DEFB 0
; Set en UpdateDeathBorder al cerrar el yellow (sprite muerte erase). Consumido
; por DrawPendingTomb tras ProcessPlayer → tumba aparece in-place sin re-entrar
; a la sala.
TombDrawPending:    DEFB 0

; --- Spawn system ---
SpawnTimer:         DEFB SPAWN_INTERVAL  ; Countdown para intentar spawn de nasty
; LastSpawnDirSigns: bit 7 = signo DELTAX, bit 6 = signo DELTAY de la ultima
; nasty spawneada. SpawnOneNasty compara y voltea DELTAY si coincide, para
; evitar que dos nasties consecutivas vayan en la misma direccion.
LastSpawnDirSigns:  DEFB 0
; ZoneCellCount/ZoneCellList: en variables_lo.asm ($5D00). Solo se accede en
; transicion (BuildZoneCellList) y en spawn (SpawnOneNasty), nunca en inner loop.

; --- La muerte (TYPE_DEATH, slot 11) ---
; DeathScreenTimer cuenta frames en sala actual. Al llegar a DEATH_SPAWN_FRAMES
; (250 = 10s a 25fps) y si DeathSpawned=0 -> SpawnDeath. Reset a 0 en DrawScreen
; al entrar a sala. Pausa cuando TimeFrozen=1 (no aparece en cinemáticas).
; DeathSubPixelAcc: acumulador 1/2 para mover 1px cada 2 frames (mitad nasti).
DeathScreenTimer:   DEFW 0      ; 16-bit para soportar > 255 frames (DEATH_SPAWN_FRAMES)
; DeathInhibitInRoom: 1 = Death no puede spawnear en esta sala. Se setea al
; abrir la puerta de la iglesia (primer paso de la cinematica de captura).
; Se limpia al cambiar de sala (screen_system reset).
DeathInhibitInRoom: DEFB 0
DeathSpawned:       DEFB 0
DeathSubPixelAcc:   DEFB 0
; Stuck detection + mini-BFS rescue (option 3 pathfinding):
;   PrevX/Y comparado contra POSX/Y tras llamar a UpdateMonster -> si no
;   cambio, incrementa StuckCounter. Al llegar a DEATH_STUCK_THRESHOLD se
;   dispara DeathBfsRescue, que hace un BFS local depth DEATH_BFS_MAX_DEPTH
;   y aplica un paso forzado en la direccion del mejor cell encontrado.
DeathPrevX:         DEFB 0
DeathPrevY:         DEFB 0
DeathStuckCounter:  DEFB 0
; Ghost mode: si Death lleva DEATH_GHOST_FRAMES (15s) sin movimiento, se
; activa este flag y la AI cambia a chase directo ignorando colision con BG.
; El timer es 16-bit y NO se resetea cuando dispara BFS (a diferencia de
; DeathStuckCounter), solo cuando Death realmente mueve.
DeathGhostStuckTimer: DEFW 0
DeathGhostMode:     DEFB 0
; DBfsQueue + DBfsQHead/Tail + scratch (BestDir/Depth/Manh, PlayerCx/Cy,
; CurCx/Cy/FirstDir/Depth, TryCx/Cy/Dir): en variables_lo.asm. Solo se acceden
; cuando StuckCounter dispara DeathBfsRescue (cold path).

; --- Round-robin de enemigos (estilo Sabre Wulf) ---
EnemyStepIdx:       DEFB 0      ; Posicion actual en el round-robin (0 a NUM_MONSTERS+NUM_NASTIES-1)

; --- Render/Logic split: buffer de enemigos procesados este frame ---
FrameEnemyCount:    DEFB 0      ; Cuantos enemigos se renderizaron este frame
FrameEnemySlots:    DEFS MAX_ENEMIES_PER_FRAME * 2  ; Punteros IX (DEFW) de cada enemigo

; PendingEraseCount/PendingEraseSlots: en variables_lo.asm. EraseDeadSprites
; los lee cada frame pero count=0 99% del tiempo (un solo byte read).

; ==============================================================================
; SISTEMA DE PANTALLAS
; ==============================================================================

; --- Posicion actual en el mapa de pantallas (grid 16x16) ---
CurrentScreenX:     DEFB START_SCREEN_X  ; Columna actual (0-15)
CurrentScreenY:     DEFB START_SCREEN_Y  ; Fila actual (0-15)

; --- Puntero a los datos de la pantalla actual ---
CurrentScreenAddr:  DEFW 0      ; Direccion en memoria de los datos de la pantalla actual

; --- Flag de transicion ---
ScreenTransition:   DEFB 0      ; 0=sin transicion, 1=N, 2=S, 4=E, 8=W
LastScreenTransition: DEFB 0    ; Ultima transicion real (persiste entre frames)
LastEntryPosX:      DEFB 120    ; Posicion X del player al entrar en la room
LastEntryPosY:      DEFB 90     ; Posicion Y del player al entrar en la room

; --- Flags de redibujado ---
ScreenDirty:        DEFB 1      ; 1=hay que redibujar la pantalla completa
AttrsDirty:         DEFB 0      ; 1=solo remap attrs (cambio de fase, sin cambio de room)

; --- Flag de transicion reciente (skip restore en primer frame) ---
ScreenJustRedrawn:  DEFB 0      ; 1=pantalla recien dibujada, no restaurar attrs

; --- Pickup attrs dirty + rect cache ---
; RefreshPickupAttrs reaplica los attrs de cada pickup en la sala. Antes
; corria cada frame con LoadBgSpriteToBuffer + DrawBgAttrOnly por pickup
; (5-6% del budget en salas como la iglesia con la puerta 4x5). Ahora se
; salta cuando ningun erase de entidad solapa con un pickup (PickupAttrsDirty=0).
; PickupRectCache se rebuilda en DrawScreen y al respawnear pickups: 4 bytes
; por entrada (charX, charY, charXEnd, charYEnd) inclusivos.
MAX_PICKUPS_CACHED  EQU 8
PickupAttrsDirty:   DEFB 1
NumPickupsCached:   DEFB 0
PickupRectCache:    DEFS 4 * MAX_PICKUPS_CACHED

; ==============================================================================
; MAPA DE COLISION (pre-computado al cargar pantalla)
; ==============================================================================
; 32 columnas × 22 filas = 704 bytes. 0=libre, 1=bloqueado.
; Coordenadas en char-space del room (sin BG_Y_OFFSET).
; Se construye en BuildCollisionMap al cargar cada pantalla.
; ==============================================================================
CollisionMap:       DEFS 32 * 22

; ==============================================================================
; CURRENT SCREEN BUFFER (copia de Room_Txx desde bank 1)
; ==============================================================================
; Los datos de rooms viven en bank 1 ($C000-$FFFF paginable). Al cargar una
; pantalla, LoadRoomToBuffer pagina bank 1, copia los bytes del room actual
; hasta el terminador $0000, y repagina bank 0. El engine siempre lee desde
; este buffer (RAM fija), asi no hace falta tocar paginacion en el hot path.
; Tamaño: suficiente para el room mas grande. Entries = 5 B (ptr+x+y+v) + 2 B
; terminador. 1024 bytes permite ~200 entries (widow fills can be numerous).
; ==============================================================================
CurrentScreenBuffer: DEFS 1024

; ==============================================================================
; BG SPRITE BUFFER (copia del sprite BG activo desde bank 3)
; ==============================================================================
; Los graficos de BG sprites viven en bank 3 ($C000-$FFFF paginable). Cada
; vez que hay que dibujar (o leer el header) de un BG sprite, LoadBgSpriteToBuffer
; pagina bank 3, copia BG_SPRITE_BUFFER_SIZE bytes al buffer, y repagina bank 0.
; El draw routine opera sobre el buffer.
;
; Tamaño: 832 B (post-fase RAM). El sprite RLE-decoded mas grande tras
; splittear cabin_house (era 1080 B → 2x540 B) y the_end (891 B → 396+495 B)
; es tall_house: 2 (H+W) + 704 (88x8 pixels) + 1 (tint) + 2 (AH+AW) + 88
; (11x8 attrs) = 797 B en buffer. 832 B da 35 B de margen.
;
; OJO: si el sprite RLE-decoded mas grande crece por encima de 830 B,
; LoadBgSpriteToBuffer (paging.asm) sobrescribe lo que hay despues del
; buffer en bank 2 (variables siguientes), y el render lee bytes basura
; al final. La RLE fallback hace LDIR de (BG_SPRITE_BUFFER_SIZE - 2)
; bytes ciegamente, asi que el buffer tiene que ser >= max sprite.
;
; Si en algun futuro hay un sprite RLE >830 B, splittealo con Slice en
; el BG editor (mismo patron que cabin_house_part1/2 y the_end_part1/2).
; ==============================================================================
BG_SPRITE_BUFFER_SIZE EQU 832
BgSpriteBuffer:     DEFS BG_SPRITE_BUFFER_SIZE

; Pixel data del reloj de plaza (16 scan lines x 2 bytes = 32 B).
; Copiado desde bank 3 una vez por pantalla via LoadPlazaClockPixels.
; DrawPlazaClock (cada frame) lo lee desde aqui sin paginar.
PlazaClockPixels:   DEFS 32

; ==============================================================================
; BUFFER DE ATRIBUTOS LIMPIOS (copia del fondo sin sprites)
; ==============================================================================
; 768 bytes. Se rellena tras DrawScreen + RemapScreenAttrs.
; Usado para restaurar atributos tras borrar sprites con color.
; ==============================================================================
CleanAttrMap:       DEFS ATTR_SIZE

; ==============================================================================
; SISTEMA DE POZOS (recuperacion)
; ==============================================================================
CurrentEnemySpeed:  DEFB 1      ; Velocidad base nasties (escala por ciclo: 1,1,2,2)
CurrentEnemyAnimDelay: DEFB 8   ; Delay animacion nasties (escala por ciclo, base ENEMY_ANIM_DELAY)

WellActive:         DEFB 0      ; 1=hay pozo en esta pantalla, 0=no
WellPosX:           DEFB 0      ; X pixel del pozo
WellPosY:           DEFB 0      ; Y pixel del pozo
WellFlashTimer:     DEFB 0      ; Countdown flash HUD tras recuperar (0=inactivo)
WellCooldownTimer:  DEFW 0      ; Frames restantes de cooldown tras usar pozo
                                ; (0=listo; se pinta blanco mientras > 0)
WellOrigAttr0:      DEFB 0      ; Attr original de la celda inferior-izq del pozo
WellOrigAttr1:      DEFB 0      ; Attr original de la celda inferior-der del pozo

PlazaClockActive:   DEFB 0      ; 1=hay reloj de plaza en esta pantalla
PlazaClockCharX:    DEFB 0      ; charX del reloj (con BG_Y_OFFSET ya aplicado en Y)
PlazaClockCharY:    DEFB 0      ; charY del reloj (con BG_Y_OFFSET)
PlazaScanAddrs:     DEFS 32     ; 16 words: dir VRAM por scan line de la esfera

; --- Paginacion 128K ---
; Port $7FFD es write-only, guardamos el valor actual en esta variable sombra
; Bits 0-2: RAM bank en slot 3 ($C000-$FFFF)
; Bit 3: pantalla (0=normal bank 5; 1=shadow no usado, bank 7 reaprovechado para bg_gfx_c)
; Bit 4: ROM (0=128 editor, 1=48 BASIC)
; Bit 5: disable paging (NO tocar)
CurrentPaging:      DEFB $10    ; default: bank 0 en slot 3, pantalla normal, ROM 48


; ==============================================================================
; SISTEMA DE SONIDO
; ==============================================================================
CurrentBorderColor: DEFB BLACK      ; Color actual del borde (preservado durante SFX)
PlayerPrevState:    DEFB 0          ; Estado previo del player (detectar transicion a fighting)
FootstepToggle:     DEFB 0          ; Alterna 0/1 cada frame de animacion: suena solo en 1
PlayerCurrentSpeed: DEFB 2          ; Velocidad actual del player (debug HUD)

; ==============================================================================
; MONSTER AI v2 — estado por monster + RoomHistory (fase 2)
; ==============================================================================
; 3 monsters activos. Slots parallelos — indice = 0,1,2 relativo a SLOT_MONSTER0.
; Total: 3*4 + 3 = 15 bytes.
; ==============================================================================

; Screen donde el monster "vive" actualmente (screen_id = Y*16+X, 0..255).
; Si == CurrentScreenId => monster esta en la room del player.
MonsterRoomId:       DEFB 0, 0, 0

; Cuenta atras en frames. 0 = sin accion pendiente. Si > 0 => cuenta hasta
; migrar (linger normal) o volver por el borde (pushed). El flag MAI_FLAG_PUSHED
; decide cual.
MonsterLingerTimer:  DEFB 0, 0, 0

; Ultimo borde de entrada/salida (MAI_SIDE_N/S/W/E). Usado para reaparecer
; por el borde correcto cuando expira el timer, o para guardar el gap de
; salida al amanecer (Regla 7 / STATE_LEAVING).
MonsterEntryBorder:  DEFB 0, 0, 0

; Coord char (0-31) del gap de salida al amanecer (Regla 7). Parejado con
; MonsterEntryBorder[slot] cuando MAI_FLAG_LEAVING esta set.
MonsterExitCoord:    DEFB 0, 0, 0

; Flags combinados (bits 0-2 definidos en constants.asm).
MonsterAiFlags:      DEFB 0, 0, 0

; RoomHistory + MonsterLastSeenRoom/X/Y + MonsterShakeOrigX/Y: en variables_lo.asm.
; Solo se leen en transicion de sala / STATE_SCARED. MonsterLastSeenRoom requiere
; init $FF en Inicio: (resto = 0 por el zero-fill general).
