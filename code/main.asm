; ==============================================================================
; PROYECTO ZX SPECTRUM 128K
; Archivo Principal - Punto de entrada
; ==============================================================================

    DEVICE ZXSPECTRUM128

    ; Inclusión de definiciones
    INCLUDE "constants.asm"
    INCLUDE "macros.asm"
    ; EQUs de variables ubicadas en low-RAM ($5D00+). No emiten bytes;
    ; el zero-fill + defaults se hace en Inicio: antes del primer uso.
    INCLUDE "variables_lo.asm"

    ; ==========================================================================
    ; ORG $6000 - codigo one-shot de boot
    ; ==========================================================================
    ; Inicio: vive aqui (slot 1, bank 5). $6000-$7FFF es CONTENDED, asi que
    ; el código aqui paga ~5-10% de penalty durante la zona activa de pantalla.
    ; No importa porque solo se ejecuta UNA vez al arrancar (boot path).
    ; Termina con JP MainLoop para saltar al loop principal en $8000.
    ;
    ; Espacio disponible: $6000-$7FFF = 8 KB. Hoy usamos ~100 B; el resto
    ; (~7.9 KB) queda libre para futuras movidas de codigo frio one-shot.
    ; ==========================================================================
    ORG $6000

Inicio:
    DI                      ; Deshabilitar interrupciones
    LD SP, SP_ADDRESS       ; Inicializar la pila (Stack Pointer)

    ; Inicializar paginacion 128K (bank 0 en slot 3, estado conocido)
    CALL InitPaging
    CALL AY_Init                ; silenciar AY al arrancar

    ; Configuración inicial (Borde negro, etc.)
    LD A, BLACK             ; A = 0 (Negro)
    OUT (254), A            ; Cambia el color del borde a negro
    LD (CurrentBorderColor), A  ; Guardar para preservar durante SFX

    ; Limpiar TODA la pantalla (pixeles + atributos) antes de nada
    ; Los pixeles del loader del .tap quedan en VRAM si no se borran
    LD HL, SCREEN_BASE
    LD DE, SCREEN_BASE + 1
    LD BC, 6911             ; 6144 pixeles + 768 atributos - 1
    XOR A                   ; A = 0
    LD (HL), A
    LDIR

    ; Zero-fill del area de variables low-RAM ($5D00..LOW_RAM_END).
    ; Esas variables son EQU (no se emiten en .tap), asi que el loader
    ; deja la zona con valores indeterminados; aqui las dejamos a 0.
    LD HL, LOW_RAM_BASE
    LD DE, LOW_RAM_BASE + 1
    LD BC, LOW_RAM_SIZE - 1
    XOR A
    LD (HL), A
    LDIR

    ; Defaults no-cero para low-RAM: MonsterLastSeenRoom = $FF,$FF,$FF
    ; (el resto de low-RAM ya quedo a 0 con el LDIR de arriba).
    LD A, $FF
    LD (MonsterLastSeenRoom), A
    LD (MonsterLastSeenRoom + 1), A
    LD (MonsterLastSeenRoom + 2), A

    ; Inicializar sistema de pantallas
    CALL InitGameState      ; Reset variables de gameplay (idempotente)
    CALL InitScreenSystem   ; Configura pantalla inicial y calcula puntero
    CALL InitEntities       ; Inicializar tabla de entidades (player en slot 0)
    CALL UpdateRemapTables  ; Aplicar remap para la hora de inicio
    CALL UpdateNastyTable   ; Seleccionar tabla de nasties para la fase inicial
    CALL ResolveObjectiveScreen ; Cachear (sx, sy) del primer hito
    ; (DrawClockSprite y DrawSwordModeHUD se llaman desde el MainLoop, no aqui)

    IM 1                    ; Modo de interrupciones 1 (por defecto en Spectrum 48k)
    EI                      ; Habilitar interrupciones
    LD A, 1                 ; Marcar fin de Inicio: las rutinas de paginacion
    LD (StartupComplete), A ; pueden hacer EI con seguridad a partir de aqui
    JP MainLoop             ; saltar al loop principal en $8000

    ; --- Cutscene final M9 (town_gate_cutscene.asm) ---
    ; Vive aqui en $6000+ (slot 1, siempre visible). Penalty ~5-10% por
    ; contention pero solo durante la cinematica final, una vez por partida —
    ; invisible. CALLs internos a rutinas de bank 0 (RestoreOldAttr,
    ; RedrawPickupByPtr, DrawBgGfxSprite, CheckMilestoneTrigger) funcionan sin
    ; envoltura: bank 0 sigue paginado por defecto y las CALLs cruzan slots
    ; sin tocar paginacion. El intento previo en bank 4 fallo porque slot 3
    ; cambiaba de bank durante el page switch — aqui ese problema no existe.
    INCLUDE "town_gate_cutscene.asm"

    ; --- Cutscene de captura en iglesia M7 (church_cutscene.asm) ---
    ; Mismo patron: vive en $6000+ (siempre visible). Solo se ejecuta durante
    ; la trampa de la iglesia (atrapar 3 monstruos). Tablas de datos
    ; (StatueIdTable, ChurchTrapBitMask, etc.) se referencian desde bank 0
    ; (logic_game, milestones) — al estar en slot 1, se leen sin paginar.
    INCLUDE "church_cutscene.asm"

    ; --- Rutinas de paginacion (paging.asm) ---
    ; Movido a slot 1 (siempre visible) en vez de bank 2 para defender el
    ; presupuesto de bank 2 — bank 2 esta al 100% lleno y derramando a bank 0
    ; slot 3. paging.asm tiene que vivir en memoria siempre visible porque
    ; sus rutinas (LoadBgSpriteToBuffer, etc.) hacen el OUT de page switch:
    ; si vivieran en slot 3, la siguiente instruccion tras el OUT seria de
    ; otro bank → crash. Antes vivia en bank 2; ahora en slot 1, mismo
    ; criterio (siempre visible) pero contended.
    ; Coste runtime: ~5-10% mas lento durante zona activa de pantalla.
    ; Las rutinas se llaman en transiciones de sala / sprite loads, no en
    ; el inner loop, asi que el overhead es invisible.
    INCLUDE "paging.asm"

    ; --- Tumbas persistentes (tombstones.asm) ---
    ; TombStore + DrawTombstonesInRoom. Usan inline page switch como
    ; LoadBgSpriteToBuffer para acceder al storage en bank 7 ($E000+).
    ; Cold path: muerte del player + carga de pantalla. Coste invisible.
    INCLUDE "tombstones.asm"

    ; --- SFX hit del player no bloqueante (sfx_player_hit_ay.asm) ---
    ; AY hardware envelope, direct OUTs sin paging. ~35 B en slot 1.
    INCLUDE "sfx_player_hit_ay.asm"

    ; ==========================================================================
    ; ORG $8000 - codigo principal (no-contended)
    ; ==========================================================================
    ORG ORIGIN_ADDRESS

; ==============================================================================
; MAIN LOOP - Fiel a Sabre Wulf (round-robin per-entity)
; ==============================================================================
; El original NO separa render de logica. Cada entidad hace todo junto:
;   erase viejo → AI/movimiento → draw nuevo
; Player: siempre se procesa completo cada frame (tras HALT).
; Enemigos: round-robin, MAX_ENEMIES_PER_FRAME por frame. Los no procesados
; no se mueven NI se redibujan → sin flicker por desfase render/logica.
; ==============================================================================
MainLoop:
    ; --- Marcar inicio de frame (referencia para sync al final) ---
    LD A, ($5C78)               ; SYS_FRAMES low byte (50Hz, ISR IM1)
    LD (.frameStart), A

    ; === DEATH BORDER FLASH + ANIM PLAYER: tick por frame, incluso en GameOver ===
    CALL UpdateDeathBorder
    CALL UpdateDeathAnim

    ; === GAME OVER: pantalla estatica, no gameplay ni HUD ===
    LD A, (GameOver)
    OR A
    JR Z, .notGameOver
    CP 2
    JR NC, .gameOverWaitInput   ; ya pintado, esperar SPACE
    ; GameOver==1: pintar pantalla esta vez y bumpear a 2
    CALL PaintGameOverScreen
    LD A, 2
    LD (GameOver), A
    JP .frameSync
.gameOverWaitInput:
    LD BC, $7FFE                ; fila SPACE-SS-M-N-B
    IN A, (C)
    BIT 0, A                    ; SPACE = bit 0 (active low)
    JP NZ, .frameSync           ; SPACE no pulsado: seguir esperando
    ; SPACE pulsado: reset total -> JP Inicio
    DI
    LD SP, SP_ADDRESS
    JP Inicio
.notGameOver:

    ; === PRE-RENDER: gestionar pantalla (NOP en frames normales) ===
    CALL CheckScreenTransition  ; Detectar cambio de pantalla (~100T normal)
    CALL DrawScreen             ; Redibujar BG si necesario (~20T normal)
    CALL RemapScreenAttrs       ; Remap attrs si cambio de fase (~fast)

    ; === CUTSCENE final (M9, puerta sur): si activa, saltar gameplay ===
    ; Excepcion: TGP_WAIT_NASTIES (16) deja correr ProcessEnemies para que los
    ; puffs de nasties recien matados se animen antes del LOCK pause.
    LD A, (TownGatePhase)
    OR A
    JR Z, .townGateNotActive
    CP 16                       ; TGP_WAIT_NASTIES
    JP Z, .townGateWaitNasties
    JP .townGateCutsceneActive
.townGateNotActive:

    ; === CUTSCENE de la iglesia (paso 7): si activa, saltar gameplay ===
    LD A, (ChurchCutscenePhase)
    OR A
    JP NZ, .cutsceneActive

    ; === PLAYER: siempre cada frame, completo (erase+logic+draw) ===
    CALL EraseDeadSprites       ; Cleanup puff terminadas (~20T normal)
    CALL ReadInput              ; Leer teclado (QAOP + SPACE)
    CALL UpdateRespawnBlink     ; Tick del parpadeo prep/grace + zero input en phase 1
    CALL ProcessPlayer          ; Erase + logic + draw player (todo junto)
    CALL DrawPendingTomb        ; Pinta tumba in-place tras erase del sprite muerte
    CALL CheckWellPickup        ; Recuperar salud/stamina si pisa un pozo
    CALL CheckPickupCollect     ; Detectar pickups (borrado diferido al siguiente frame)
    CALL CheckBumpTriggers      ; Sprites trigger por colisión (puerta iglesia/ayuntamiento)
    CALL CheckTownGateTriggerBg ; Cutscene final: arco sur (BG sprite, no en PickupTable)

    ; Limpiar flag de pantalla recien dibujada (tras renderizar player)
    XOR A
    LD (ScreenJustRedrawn), A

    ; Flow field BFS: DESACTIVADO por coste (~1M T-states = 7 frames stutter).
    ; La infraestructura vive en monster_ai.asm y bank 6 (FlowField + BfsQueue).
    ; Para reactivar: amortizar el BFS en K iteraciones por frame (TODO).
    ; CALL MaiMaybeRecomputeFlow

    ; === ENEMIGOS: round-robin, erase+logic+draw por entidad ===
    CALL ProcessEnemies         ; Round-robin: hasta MAX_ENEMIES_PER_FRAME
    CALL ProcessDeath           ; La muerte (slot 11): erase+AI+draw fuera del round-robin
    CALL RefreshPickupAttrs     ; Re-pinta attrs de pickups tras erase de enemigos
    CALL UpdatePickupFlash      ; Parpadeo de pickups recién spawnados (church_key)

    ; === SISTEMAS GLOBALES ===
    CALL TrySpawnNasty          ; Spawn check (tiene su propio timer)
    CALL TryRespawnMonsters     ; Rellenar slots monster vacios (siempre 3)
    CALL UpdateDeathTimer       ; Tick contador 10s + spawn la muerte si toca
    CALL CheckPlayerEnemyCollision ; Colision player vs enemigos
    CALL CheckDeathTouchPlayer  ; La muerte toca al player → drena HP + despawn
    CALL AY_UpdatePlayerHit     ; Tick sweep del SFX hit (no-op si inactivo)
    JR .afterGameplay
.cutsceneActive:
    CALL UpdateChurchCutscene   ; Avanza phase machine de la cutscene
    JR .afterGameplay
.townGateCutsceneActive:
    CALL UpdateTownGateCutscene ; Phase machine del cutscene final (M9)
    JR .afterGameplay
.townGateWaitNasties:
    ; Pre-LOCK wait: deja correr ProcessEnemies para que los puffs de
    ; nasties recien matados se animen. Skip ProcessPlayer (player frozen
    ; en anchor1, ya dibujado en StartTownGateCutscene). Skip pickup
    ; collect/bump triggers (ya en cutscene, no re-disparar nada).
    CALL EraseDeadSprites
    CALL ProcessEnemies
    CALL ProcessDeath
    CALL UpdateTownGateCutscene ; tick wait timer; transiciona a LOCK al expirar
.afterGameplay:
    ; Skip HUD durante TGP_BLACK / TGP_CREDITS / GameOver
    LD A, (GameOver)
    OR A
    JR NZ, .skipHUD
    LD A, (TownGatePhase)
    CP 14                       ; TGP_BLACK = 14, TGP_CREDITS = 15
    JR NC, .skipHUD
    CALL DrawClockHUD           ; Reloj: cara + agujas (HUD fijo, no flicker)
    CALL DrawKeyHUD             ; Llave actual (slot 3×2 en cols 20-22, rows 22-23)
    CALL DrawLivesHUD           ; Vidas (5 iconos 1×1 en row 1 cols 26-30)
    CALL DrawPlazaClock         ; Reloj de plaza (si existe en esta room)
    CALL DrawHealthStaminaHUD   ; Barras salud/stamina en decoraciones
    CALL DrawSwordModeHUD       ; Debug: indicador modo espada
    CALL DrawNoclipHUD          ; Debug: indicador NoclipMode (N)
    CALL DrawDayCycleHUD        ; Indicador de dia (D1, D2, D3...)
    CALL DrawPlayerSpeedHUD     ; Debug: velocidad player (fila 0, col 2)
    CALL DrawEnemySpeedHUD      ; Debug: velocidad nasties (V1, V2...)
    CALL DrawZoneCountHUD       ; Debug: ZoneCellCount en hex (cols 11-12)
    CALL DrawCompass            ; Brujula del hito actual (cols 23-24, rows 0-1)
.skipHUD:
    ; === Updates + debug: pausados durante cualquier cutscene ===
    LD A, (ChurchCutscenePhase)
    OR A
    JR NZ, .skipUpdates
    LD A, (TownGatePhase)
    OR A
    JR NZ, .skipUpdates
    CALL UpdateWellCooldown     ; Tick cooldown del pozo + repintar blanco si activo
    CALL UpdateGameClock        ; Avanzar reloj de juego
    CALL UpdateEnemySpeed       ; Ajustar velocidad nasties segun ciclo
    CALL UpdateBellChimes       ; Campanadas de medianoche (si activas)
    CALL UpdateBellsDoneTimer   ; Cadena post-campanadas: ventanas off → monster spawn
    CALL UpdateStatueBlink      ; Parpadeo ON-OFF de la estatua que se enciende
    CALL AY_UpdateBell          ; Decay manual del volumen de la campana
    CALL UpdateTensionMusic     ; Motivo de tension entre lights-off y monster spawn
    CALL UpdateScareTimer       ; Countdown pausa+huida (bells/dawn)
    CALL CheckDebugKeys         ; Tecla T: ciclar momento del dia (debug)
    CALL CheckMilestoneDebugKey ; Tecla M: skip de hito (debug)
    CALL CheckCurrentKeyCycleKey ; Tecla K: cicla CurrentKey 0..6 (debug)
.skipUpdates:

    ; Incrementar contador de frames
    LD A, (GameFrameCounter)
    INC A
    LD (GameFrameCounter), A

    ; --- Frame sync: esperar hasta que pasen 2 ticks desde el inicio ---
.frameSync:
    HALT                        ; Dormir hasta siguiente interrupt
    LD A, (.frameStart)
    LD B, A
    LD A, ($5C78)
    SUB B                       ; A = ticks transcurridos (byte wrap OK)
    CP 2
    JR C, .frameSync            ; < 2 ticks: seguir esperando

    JP MainLoop
.frameStart: DEFB 0

    ; Inclusión de módulos
    INCLUDE "variables.asm"
    ; paging.asm: movido a slot 1 ($6000+) — vive en memoria siempre visible
    ; (igual que bank 2) pero deja bank 2 mas libre. Ver INCLUDE arriba.
    ; monster_ai.asm DEBE vivir en bank 2 fijo ($8000-$BFFF) porque sus
    ; rutinas pagan bank 6 en slot 3 y se ejecutarian ellas mismas si
    ; estuvieran en bank 0. Incluir aqui temprano (detras de paging.asm)
    ; garantiza que aterricen antes de $C000.
    INCLUDE "monster_ai.asm"
    ; ay_sound_thunks: 5 entry thunks (bank 2 → bank 4) para AY routines.
    ; Inclusion temprana garantiza aterrizaje en bank 2 con margen.
    INCLUDE "ay_sound_thunks.asm"
    INCLUDE "engine_graphics.asm"
    INCLUDE "logic_game.asm"
    INCLUDE "screen_system.asm"
    INCLUDE "screen_data.asm"
    ; bg_gfx.asm: movido a bank 3 (ver PAGE 3 abajo)
    ; sprite_data.asm + shift_tables.asm: movidos a bank 6. DrawSprite
    ; lee ambos simultaneamente (sprite + tablas de shift), por lo que
    ; deben vivir en el mismo banco paginado.
    INCLUDE "day_cycle.asm"
    INCLUDE "hud_clock.asm"
    INCLUDE "milestones.asm"
    ; town_gate_cutscene.asm: incluido arriba en $6000+ (slot 1).
    INCLUDE "sound.asm"
    ; ay_sound.asm: movido a bank 4 (ver PAGE 4 abajo). MainLoop entra via
    ; los thunks en ay_sound_thunks.asm.

    ; Guardar fin del bank 0 para reportarlo al final
Bank0End    EQU $

    ; ==========================================================================
    ; BANK 1 - Definiciones de rooms (screen_rooms.asm)
    ; ==========================================================================
    ; Se pagina en slot 3 ($C000-$FFFF) solo al cargar una nueva pantalla.
    ; El lector copia los datos a CurrentScreenBuffer en RAM fija y repagina
    ; bank 0 antes de que el engine los use.
    ; ==========================================================================
    PAGE 1
    ORG $C000
    INCLUDE "screen_rooms.asm"
Bank1End    EQU $
    PAGE 0

    ; ==========================================================================
    ; BANK 3 - Graficos de BG sprites (bg_gfx.asm): baseline town + forest
    ; ==========================================================================
    ; Se pagina en slot 3 cuando hay que leer datos/pixeles de un BG sprite.
    ; LoadBgSpriteToBuffer consulta BgGfxPtrById[id].bank y pagina el bank
    ; correcto antes de leer desde $C000-$FFFF.
    ; ==========================================================================
    PAGE 3
    ORG $C000
    INCLUDE "bg_gfx.asm"
Bank3End    EQU $
    PAGE 0

    ; ==========================================================================
    ; BANK 4 - Graficos de BG sprites (bg_gfx_b.asm): variantes ruins + cemetery
    ; ==========================================================================
    ; Mismo mecanismo que bank 3 pero con sprites cuyo nombre termina en
    ; " ruins" o " cemetery". Split automatico por el level editor.
    ; ==========================================================================
    PAGE 4
    ORG $C000
    INCLUDE "bg_gfx_b.asm"
    ; ay_sound.asm vive aqui (bank 4, no-contended). MainLoop entra via thunks
    ; en ay_sound_thunks.asm. ay_sound es self-contained: cero CALL/JP a
    ; rutinas externas, asi que NO hay cross-bank surface dentro del impl.
    INCLUDE "ay_sound.asm"
Bank4End    EQU $
    PAGE 0

    ; ==========================================================================
    ; BANK 7 - Graficos de BG sprites (bg_gfx_c.asm): variantes forest
    ; ==========================================================================
    ; Mismo mecanismo que bank 3/4. Bank 7 estaba reservado para el shadow
    ; screen del Spectrum 128 pero el juego no usa double-buffering, asi que
    ; se reaprovecha como almacen de bg_gfx. Si en el futuro se quisiera
    ; activar shadow screen habria que recolocar este bank.
    ; ==========================================================================
    PAGE 7
    ORG $C000
    INCLUDE "bg_gfx_c.asm"
Bank7End    EQU $
    PAGE 0

    ; ==========================================================================
    ; BANK 6 - Monster AI data pack (screen_gaps.asm)
    ; ==========================================================================
    ; Precomputado por tools/build_screen_gaps.py desde level_data.json.
    ; Contiene ScreenGapsTable (256 punteros) + registros por room con los
    ; "openings" validos (huecos de borde no culs-de-sac).
    ; Reservado tambien para future: flow field buffer + BFS queue.
    ;
    ; sprite_data.asm movido aqui para liberar ~4 KB en bank 0. Acceso vía
    ; GetSpriteAddr / GetOldSpriteAddr / GetSpriteDims / DrawSprite, que ya
    ; paginan bank 6 internamente (ver logic_game.asm y engine_graphics.asm).
    ; shift_tables.asm tambien vive aqui: DrawSprite lo lee junto con los
    ; pixeles del sprite, por eso ambos comparten bank para ser visibles a
    ; la vez durante el blit shifted.
    ; ==========================================================================
    PAGE 6
    ORG $C000
    INCLUDE "screen_gaps.asm"
    INCLUDE "monster_ai_bank6.asm"
    INCLUDE "sprite_data.asm"
    INCLUDE "shift_tables.asm"
Bank6End    EQU $
    PAGE 0

    ; ==========================================================================
    ; GENERACIÓN DE ARCHIVOS BINARIOS (Emuladores y depuradoras)
    ; ==========================================================================
    CSPECTMAP "juego.map"
    SAVETAP "juego.tap", Inicio
    SAVESNA "juego.sna", Inicio

    DISPLAY "========================================"
    DISPLAY "Fin bank 1 (PC): ", Bank1End
    DISPLAY "Bytes bank 1 usados: ", Bank1End - $C000
    DISPLAY "Fin bank 3 (PC): ", Bank3End
    DISPLAY "Bytes bank 3 usados: ", Bank3End - $C000
    DISPLAY "Fin bank 4 (PC): ", Bank4End
    DISPLAY "Bytes bank 4 usados: ", Bank4End - $C000
    DISPLAY "Fin bank 6 (PC): ", Bank6End
    DISPLAY "Bytes bank 6 usados: ", Bank6End - $C000
    DISPLAY "Fin bank 7 (PC): ", Bank7End
    DISPLAY "Bytes bank 7 usados: ", Bank7End - $C000
    DISPLAY "----------------------------------------"
    DISPLAY "Fin de codigo actual (PC): ", Bank0End
    DISPLAY "RAM Libre en Upper block: ", 65536 - Bank0End
    DISPLAY "========================================"
