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

    ; Reset music driver state. En GameOver, input -> JP Inicio salta sin
    ; pasar por cleanup formal; el IRQ retiene MusicTimer != 0 y al re-EI
    ; ticka la nota siguiente del buffer prefetched de GameOver → nota
    ; residual antes del primer StartMusic legitimo de la nueva partida.
    ; MusicTimer=0 + MusicTrackInBank7=0 + MusicNeedPrefetch=0 dejan al
    ; driver totalmente idle: AY ya muteado por AY_Init.
    ;
    ; DrumEnabled=0 silencia el drum sequencer canal B del GameOver: sin
    ; esto, el primer IRQ tick tras EI ve DrumEnabled=1 y dispara un hit
    ; del kick antes de que StartMusic de la nueva partida lo limpie.
    ; BellVols=0 evita que BellTickIrq reescriba R8/9/10 con un decay
    ; residual si el player murio durante/poco despues de medianoche.
    XOR A
    LD (MusicTimer), A
    LD (MusicTrackInBank7), A
    LD (MusicNeedPrefetch), A
    LD (DrumEnabled), A
    LD (DrumHitTimer), A
    LD (BellVolL), A
    LD (BellVolC), A
    LD (BellVolR), A
    LD (BellDecayTimer), A

    ; Configuración inicial (Borde negro, etc.)
    LD A, BLACK             ; A = 0 (Negro)
    OUT (254), A            ; Cambia el color del borde a negro
    LD (CurrentBorderColor), A  ; Guardar para preservar durante SFX

    ; --------------------------------------------------------------------------
    ; Zero-fill low-RAM ($5D00..LOW_RAM_END) + defaults ANTES de SplashWait.
    ; Originalmente se hacía después del splash, pero eso dejaba la zona con
    ; valores indeterminados durante SplashWait. Si por casualidad un puntero
    ; uninitialized apuntaba cerca de slot 1 ($706F+), alguna rutina IRQ-driven
    ; leía bytes de código como datos y pintaba basura en el centro del splash
    ; (síntoma observado en Spectaculator tras boot con cierto RAM state).
    ; Moviéndolo aquí (con DI activo, antes de EI) el splash arranca siempre
    ; con un estado conocido — fix defensivo contra boot-state-dependent bugs.
    ; --------------------------------------------------------------------------
    LD HL, LOW_RAM_BASE
    LD DE, LOW_RAM_BASE + 1
    LD BC, LOW_RAM_SIZE - 1
    XOR A
    LD (HL), A
    LDIR

    ; Defaults no-cero para low-RAM: MonsterLastSeenRoom = $FF,$FF,$FF
    ; RandomSynthMapX = $FE (inactivo: no hay random pickup spawneado al boot).
    ; MagicCompassJingleIdx = $FF (inactivo). MagicCompassPathDir = $FF (no path).
    ; (el resto de low-RAM ya quedo a 0 con el LDIR de arriba).
    LD A, $FF
    LD (MonsterLastSeenRoom), A
    LD (MonsterLastSeenRoom + 1), A
    LD (MonsterLastSeenRoom + 2), A
    LD (MagicCompassJingleIdx), A
    LD (MagicCompassPathDir), A
    LD (LastEntrySide), A               ; sin entry side al boot → BFS fallback comp 0
    LD (LastEntryCoord), A              ; sin coord (irrelevant si LastEntrySide=$FF)
    LD (LastMagicCompassDrawn), A       ; sprite no dibujado todavía
    XOR A
    LD (MagicCompassBfsState), A        ; BFS idle al boot
    LD A, $FE
    LD (RandomSynthMapX), A

    ; Random pickup memory: cur/prev sids = $FF (sala $00 = (0,0) es válida,
    ; un default 0 daría hit espurio al primer cruce). Slot/Rolled defaults a 0
    ; tras zero-fill (Slot 0 + ROLLED_NONE = "no spawn" si llegase a leer).
    LD A, $FF
    LD (RP_CurSid), A
    LD (RP_PrevSid), A

    ; --------------------------------------------------------------------------
    ; Habilitar IM 2 + EI antes del SplashWait para que la música pueda tickar
    ; durante la espera. Normalmente esto se hacía al final de Inicio; lo
    ; subimos aquí porque el splash no devuelve control hasta la pulsación y
    ; sin IM 2 + EI el driver de música no recibiría ticks del IRQ 50 Hz.
    ; StartupComplete=1 permite a las rutinas de paginación que se llamen
    ; durante SplashWait (StartMusic, PrefetchMusic) hacer EI con seguridad.
    ; IM 2 / EI se hacen SIEMPRE (no solo en boot fresco): GameOver → input →
    ; JP Inicio reentra con DI y sin IM 2 si no rehacemos esto cada vez.
    ; --------------------------------------------------------------------------
    ; I = pagina de Im2Table (bank 2, no-contended, always-visible). NUNCA
    ; volver a un valor $40-$7F: I en RAM contended = ULA snow en hardware
    ; real (48K/128K/+2). Ver im2_table.asm + docs/ula_snow_investigation.md.
    LD A, high Im2Table
    LD I, A
    IM 2
    LD A, 1
    LD (StartupComplete), A
    EI

    ; --------------------------------------------------------------------------
    ; Splash + EndGame solo en el PRIMER arranque (boot desde cinta). Reinicios
    ; post-GameOver (JP Inicio) saltan este bloque y van directo al gameplay.
    ; SplashAlreadyShown vive en bank 5 slot 1 (no en low-RAM EQU), así que
    ; sobrevive al zero-fill de Inicio.
    ; --------------------------------------------------------------------------
    LD A, (SplashAlreadyShown)
    OR A
    JR NZ, .skipSplashBlock

    ; --- Standalone: F1Setup INLINE aqui (slot 1 standalone area apretado;
    ; el inline libera ~23 B alli para SafeHaltAndPrefetch). El flow completo
    ; (loading wait, cards, 257, StartMusic 2, menu, historia, iconos) corre
    ; dentro de F1Body en bank 4. main.asm salta directo al jingle.
    ; Patron alt_stack: SP normal vive en slot 3 = bank 0 default; durante
    ; F1Body paginamos bank 4 en slot 3 -> stack normal queda oculto. SP a
    ; PagingAltStackTop (slot 1 always-visible) protege las IRQs.
    IFDEF STANDALONE
    LD (StandaloneSavedSP), SP
    LD SP, PagingAltStackTop
    LD BC, $7FFD
    LD A, $14                       ; ROM 48 + bank 4 (preserva config InitPaging $10)
    LD (CurrentPaging), A
    OUT (C), A
    CALL StandaloneF1Body
    LD BC, $7FFD                    ; F1Body destruye BC, re-cargar
    LD A, $10                       ; ROM 48 + bank 0 (default)
    LD (CurrentPaging), A
    OUT (C), A
    LD SP, (StandaloneSavedSP)
    JR .saStandaloneJingle
    ENDIF

    ; --- Arrancar EndGame (track 2, loopable) durante el splash --------------
    ; Track 2 vive en bank 7; PrefetchMusic en el loop de SplashWait rellena
    ; el buffer slot 1 conforme el IRQ consume notas.
    LD A, 2
    CALL StartMusic

    ; Si el BASIC del TAP de release cargó SCREEN$ con bg257, aquí está visible
    ; en VRAM. Pintamos 'PRESS ANY KEY / BUTTON' en fila 22 y esperamos
    ; pulsación. Si arrancamos desde SNA (dev), VRAM tiene basura pero el flujo
    ; sigue siendo válido: pulsas una tecla y continúa.
    CALL SplashWait
.saStandaloneJingle:

    ; --- Tras la pulsación, interrumpir EndGame y lanzar el jingle StartGame --
    ; StartMusic 5 sobreescribe el state del driver: EndGame se corta en seco
    ; y arranca el jingle (track 5, mono canal A, one-shot, ~2s). El splash
    ; (bg257 + iconos) sigue visible — NO limpiamos VRAM todavia. Al consumir
    ; el terminator, .meotStop setea MusicEnded=1.
    LD A, 5
    CALL StartMusic

    ; --- Prefetch ANTES del primer HALT: garantiza que el buffer slot 1 tiene
    ; la primera entry de la tabla cuando el IRQ inminente tickee MusicTimer
    ; 1->0 y dispare MusicAdvanceNote. Sin esto habria 1-2 frames de delay
    ; (~80ms) entre la pulsación y la primera nota audible.
    CALL PrefetchMusic

    ; --- Esperar a que el jingle termine (boot bloqueado, splash visible) ----
    ; HALT espera 1 IRQ (50 Hz). PrefetchMusic refilla el buffer slot 1 desde
    ; bank 7 cuando el handler IRQ lo pide. UpdateSplashAnim mantiene los
    ; iconos tecla/boton animados durante el jingle (mismo patron que
    ; SplashWait). Cero coste runtime tras la espera.
.spwJingleWait:
    HALT
    CALL PrefetchMusic
    CALL UpdateSplashAnim
    LD A, (MusicEnded)
    OR A
    JR Z, .spwJingleWait

    ; Release-gate antes de entregar control al MainLoop: si la ultima pulsacion
    ; de la intro (skip story, confirm menu o splash press) sigue activa al
    ; terminar el jingle, esperar a que se suelte. Sin esto, MainLoop arranca
    ; con input "ghost" → el player se mueve/dispara solo en frame 0.
.spwIntroEndRelease:
    HALT
    CALL UpdateSplashAnim
    CALL SplashCheckInput
    JR NZ, .spwIntroEndRelease

    ; Marcar splash como mostrado para que reinicios via JP Inicio lo salten.
    LD A, 1
    LD (SplashAlreadyShown), A
.skipSplashBlock:

    ; Limpiar TODA la pantalla (pixeles + atributos) antes de nada
    ; Los pixeles del loader del .tap quedan en VRAM si no se borran
    LD HL, SCREEN_BASE
    LD DE, SCREEN_BASE + 1
    LD BC, 6911             ; 6144 pixeles + 768 atributos - 1
    XOR A                   ; A = 0
    LD (HL), A
    LDIR

    ; (zero-fill low-RAM + defaults se hacen ahora ANTES de SplashWait — ver
    ; bloque arriba en Inicio. Si vivían aquí, durante el splash las vars EQU
    ; tenían valores indeterminados → pointer espurio → basura visible.)

    ; Inicializar sistema de pantallas
    CALL InitGameState      ; Reset variables de gameplay (idempotente)
    CALL InitScreenSystem   ; Configura pantalla inicial y calcula puntero
    CALL InitEntities       ; Inicializar tabla de entidades (player en slot 0)
    CALL UpdateRemapTables  ; Aplicar remap para la hora de inicio
    CALL UpdateNastyTable   ; Seleccionar tabla de nasties para la fase inicial
    CALL ResolveObjectiveScreen ; Cachear (sx, sy) del primer hito
    ; (DrawClockSprite y DrawSwordModeHUD se llaman desde el MainLoop, no aqui)

    ; IM 2 + EI + StartupComplete=1 ya quedaron seteados arriba (antes del
    ; SplashWait, para que la música EndGame pudiera tickar durante la espera
    ; de la pulsación). I=$7A apunta a la vector table en music_irq.asm:
    ; cualquier byte del data bus produce vector = $7B7B donde hay un JP
    ; MusicIrqHandler. El handler reemplaza la rutina ROM de $0038: incrementa
    ; $5C78 manualmente y tickea la musica cada 2 IRQs (= 25 Hz).
    IFDEF SFXTEST
    JP SfxTest              ; audicion de SFX (tools/perf/sfx_audition.py)
    ENDIF
    JP MainLoop             ; saltar al loop principal en $8000

    ; --- Splash wait one-shot post-load (splash_wait.asm) ---
    ; SplashWait + datos pre-renderizados (198 B del prompt + ~50 B de código).
    ; Llamado desde Inicio antes del clear de VRAM para mostrar 'PRESS ANY KEY /
    ; BUTTON' en fila 22 sobre el SCREEN$ bg257 cargado por el BASIC del TAP
    ; release (ver tools/build_tap_with_splash.py). En boot desde SNA (dev) la
    ; VRAM tiene basura pero el flujo sigue siendo válido: pulsa una tecla y
    ; continua. Cero coste runtime tras la pulsación.
    INCLUDE "splash_wait.asm"

    ; --- Cutscene final M9 (town_gate_cutscene.asm) ---
    ; Vive aqui en $6000+ (slot 1, siempre visible). Penalty ~5-10% por
    ; contention pero solo durante la cinematica final, una vez por partida —
    ; invisible. CALLs internos a rutinas de bank 0 (RestoreOldAttr,
    ; RedrawPickupByPtr, DrawBgGfxSprite, CheckMilestoneTrigger) funcionan sin
    ; envoltura: bank 0 sigue paginado por defecto y las CALLs cruzan slots
    ; sin tocar paginacion. El intento previo en bank 4 fallo porque slot 3
    ; cambiaba de bank durante el page switch — aqui ese problema no existe.
    ; --- RoomCompGapsTable: gaps per-sala con info de comp (slot 1) ---
    ; CRITICO: este INCLUDE va PRIMERO en el bloque slot 1 para que
    ; RoomCompGapsTable (~512 B de pointers) quede al INICIO de slot 1
    ; (~$6000+), MUY lejos del ORG $7B7B de Im2Vector (music_irq.asm).
    ; Historia: cuando la tabla IM 2 vivia en $7A00 (hoy en bank 2,
    ; im2_table.asm, fix ULA snow), cruzarla sobrescribia los ultimos
    ; pointers (sids ~217-255) con $7B -> deref a $7B7B en bank 7 =
    ; garbage -> BFS itera basura -> "transiciones eternas con compass
    ; activo" (sintoma del project_slot1_overflow_canary).
    ;
    ; Bug raiz cazado tras la sesion de SP alterno: dab8de0 anadio 82 B
    ; a slot 1 que desplazaron RoomCompGapsTable lo justo para cruzar
    ; $7A00 (entonces la IM2 table). Mover este INCLUDE al inicio
    ; garantiza margen ~5 KB; hoy ademas el ASSERT $ <= $7B7B de
    ; music_irq.asm caza cualquier overflow en build.
    INCLUDE "room_routes.asm"

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
    ; LEGACY: sera reemplazado por sfx_interp.asm cuando la migracion termine.
    INCLUDE "sfx_player_hit_ay.asm"

    ; --- SFX generico data-driven (sfx_interp.asm + sfx_data.asm) ---
    ; Interprete + tabla de SFX compilada desde code/sfx_library.json por
    ; tools/build_sfx.py. Fase 2: coexiste con sfx_player_hit_ay (legacy).
    ; UpdateSFX se hookea en MusicIrqHandler en Fase 3 (al migrar primer SFX).
    INCLUDE "sfx_interp.asm"

    ; --- Random pickups: thunks slot 1 (random_pickups.asm body en bank 7) ---
    ; Movido a bank 7 para liberar slot 1 (~1.1 KB neto). Aqui solo viven los
    ; 9 entry thunks que paginan bank 7 + SP swap a alt_stack compartido con
    ; bank_cutscene, mas 3 _B7 wrappers nuevos (SkipPixelData/RestorePickupAttrs/
    ; ApplyMagicCompassBuff). Body en INCLUDE en PAGE 7 mas abajo.
    INCLUDE "random_pickups_thunks.asm"

    ; --- Thunk de la cinemática Game Over (slot 1 always-visible) ---
    ; ~45 B. Wrapper que carga el sprite, pagina bank 7, llama al body en
    ; bank 7, restaura bank 0. El body (game_over_tomb.asm) vive en bank 7.
    ;
    ; Orden: lo dejamos aquí (antes de magic_compass.asm) por simetría histórica.
    ; Originalmente este orden era OBLIGATORIO porque el tail de magic_compass.asm
    ; (BfsQueue+Visited como DEFS, 224 B) se extendía hasta $7A3B y solapaba con
    ; la tabla IM 2 (entonces en $7A00..$7B00; hoy en bank 2). Si el thunk iba detrás caía
    ; en zona pisada por la IM 2. Ese problema YA NO EXISTE — el BFS scratch
    ; ahora vive en $5B00..$5BDF (EQU, ver magic_compass.asm), pero el orden se
    ; mantiene por estabilidad.
    INCLUDE "game_over_tomb_thunk.asm"

    ; --- Bank cutscene: thunks slot 1 + body en bank 7 (M9) ---
    ; OBSERVACION CRITICA: estos thunks tienen que ir ANTES de magic_compass.asm
    ; (NO despues de music_irq) porque slot 1 esta apretado y meterlos al final
    ; deborda el slot a $8000+ (slot 2 = bank 2) -> crash al BASIC.
    ;
    ; Aqui empujan magic_compass.asm ~140 B hacia $7A00, pero gracias a la
    ; fusion de DrawBankDoorSprite_B7 dentro de DrawBgGfxSprite_B7 (ahorra 18 B)
    ; y al stripping de los thunks al minimo, magic_compass termina en ~$79F0.
    ; (La tabla IM2 ya no vive en $7A00 sino en bank 2 -- el limite real del
    ; flujo slot 1 es el ORG $7B7B de Im2Vector, con ASSERT en music_irq.asm.)
    INCLUDE "bank_cutscene_thunks.asm"

    ; --- Magic compass: power-up que muestra ruta sala-a-sala (slot 1) ---
    ; ApplyMagicCompassBuff/UpdateMagicCompass/CancelMagicCompass + BFS reverse
    ; con state (sid, comp_local) via RoomCompGapsTable (vive en slot 1, no
    ; necesita paginar bank 6). Evita cul-de-sacs internos.
    ;
    ; Scratch BFS (Queue 128 B + Visited 96 B = 224 B) está EQU'd a $5B00 /
    ; $5B80 (printer buffer, bank 5, always-on en slot 1). Antes vivían como
    ; DEFS al final del archivo y solapaban la IM 2 table (entonces en
    ; $7A00..$7A3B; hoy vive en bank 2); en
    ; hardware funcionaba por el bus flotante (IRQ ack lee $FF → vector $7B7B)
    ; pero en emuladores con bus indefinido el vector caía en basura y colgaba.
    ; SAVETAP excluye $5B00..$5DFF de la cinta, así que 0 bytes de coste en .tap.
    INCLUDE "magic_compass.asm"

    ; --- Tics beeper: THUNKS slot 1 (body en bank 4) ---
    ; El body (beeper_ticks.asm, ~252 B) se movio a bank 4 (PAGE 4) para liberar
    ; slot 1 y dar sitio a minimap.asm. Aqui solo los thunks UpdateBeeperTicks
    ; (1x/frame desde MainLoop) y FireBuffNormalTick (desde ShowMinimapTimed).
    ; Slots fijos 0/6/12/18 del ciclo de 25 frames (logica en el body).
    INCLUDE "beeper_ticks_thunks.asm"

    ; --- MINIMAP SPRITES: movido a BANK 4 (PAGE 4) ---
    ; Tablas de datos (MinimapSpriteData/Index/FrameSprites, ~488 B) movidas a
    ; bank 4 para dar sitio a minimap.asm en slot 1. Solo las lee smRenderMap, que
    ; ahora bufferea MapTable y pagina bank 4 durante el render (corre bajo DI).
    ; Ver minimap.asm smRenderMap + minimap_stack_fix_handoff.md.

    ; --- Debug unlock (B-U-G) + pausa ENTER: THUNK slot 1 (body en bank 4) ---
    ; El body (debug_unlock.asm) se movio a bank 4 (PAGE 4) para liberar ~194 B
    ; de slot 1 y dar sitio a minimap.asm. Aqui solo el thunk
    ; DebugFramePoll (alt-stack bank-4, ~36 B). Ver debug_unlock_thunk.asm.
    INCLUDE "debug_unlock_thunk.asm"

    ; --- Pickup MAP: ShowMinimapTimed + overlay (slot 1) ---
    ; Vive en slot 1 (bank 5, always-visible) porque cuando vivia al final
    ; del bank 0 las variables del loop (smtFrame, smtOverlayBit, etc.) y los
    ; helpers del render (smDrawOuterFrame, mmRowTablePtr, mmRowTable, ...)
    ; caian en $FE80+, justo en el rango que el stack normal del gameplay
    ; (SP_ADDRESS=$FF58) sobreescribe al hacer PUSH. Resultado: al recoger el
    ; pickup MAP, el render del minimap leia mmRowTablePtr corrupto y se
    ; congelaba a mitad. Slot 1 es always-visible, el stack normal nunca lo
    ; toca. Llama a smRenderMap/smMinimapCleanup (bank 0) tras paginar.
    INCLUDE "minimap_timed.asm"

    ; --- MINIMAP render core (M-key entry + smRenderMap/smDrawOuterFrame/...) ---
    ; MOVIDO desde bank 0 (slot 3) a slot 1: al final de bank 0 sus rutinas caian
    ; en $FE80-$FF58, la zona que el stack del gameplay (SP_ADDRESS=$FF58) + los
    ; IRQs machacan con cada PUSH -> codigo corrupto -> crash no-determinista al
    ; abrir el mapa (pickup MAP). Slot 1 es always-visible, el stack nunca lo toca.
    ; Su unica dep bank-0 (MapTable) se lee con bank 0 paginado en slot 3 — los
    ; callers (ShowMinimap/ShowMinimapTimed) ya hacen _PageBank0. Ver
    ; minimap_stack_fix_handoff.md. Sitio liberado moviendo debug_unlock +
    ; beeper_ticks a bank 4.
    INCLUDE "minimap.asm"

    ; --- Freeze cluster: SilentKillDeath / FreezeMonstersFacingCorpse /
    ; FreezeOneMonster / TryBackoffX/Y / CheckMonsterOverlap /
    ; KillAllActiveMonsters ---
    ; Movido desde bank 2 al hueco que libero la tabla IM 2 al mudarse a
    ; bank 2 (fix ULA snow, ver im2_table.asm). Slot 1 always-visible ->
    ; los CALL de day_cycle/milestones/logic_game no necesitan thunks.
    ; Codigo frio (player death / day cycle). El ASSERT $ <= $7B7B en
    ; music_irq.asm caza cualquier crecimiento que amenace Im2Vector.
    INCLUDE "freeze_cluster.asm"
    INCLUDE "cold_slot1.asm"      ; InitEntities, ShuffleMonsterTypes (frio, desde bank 0)

    ; (room_routes.asm movido al inicio del bloque slot 1 — ver comentario
    ; arriba sobre la colision historica con la IM2 table, hoy en bank 2).

    ; --- Music IRQ handler + driver musica (slot 1) ---
    ; JP del vector en $7B7B (ASSERT-guarded), handler en $7B7E; la tabla IM 2
    ; vive en bank 2 (im2_table.asm, fix ULA snow). State + tablas + tick
    ; al final del archivo. Ver music_irq.asm. Independiza el ritmo musical de
    ; la latencia de MainLoop sin paginar slot 3 desde el handler.
    INCLUDE "music_irq.asm"

    ; --- Mini-thunk slot 1: salida de credits cutscene a Inicio. ---
    ; Vive DESPUES de music_irq.asm para no empujar el flujo previo (drum/bell)
    ; hacia el ORG $7B7B de Im2Vector (el ASSERT en music_irq.asm lo caza en
    ; build; ver town_gate_exit_thunk.asm + project_org_retrograde_overlap).
    INCLUDE "town_gate_exit_thunk.asm"

    ; --- Standalone splash thunk (solo con --define STANDALONE) ---
    ; Body + descompresor + blob viven en bank 1 (INCLUDE en PAGE 1 mas abajo).
    ; Aqui solo el thunk de slot 1 (~25 B) que pagina + alt_stack.
    IFDEF STANDALONE
    INCLUDE "standalone_splash_thunk.asm"
    ENDIF

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
    LD B, A                     ; B = tick actual

    ; --- Catchup wall-clock: cuantos game frames (25fps) han pasado desde el
    ; iter anterior? `.frameStart` aun tiene el tick del iter previo. Si una
    ; transicion de pantalla tardo 4 ticks (= 2 frames), avanzamos 2 frames
    ; en MusicTimer/BellDecayTimer en vez de 1, preservando ritmo.
    LD A, B
    LD HL, .frameStart
    SUB (HL)                    ; A = elapsed = now - last (8-bit wrap OK)
    LD (HL), B                  ; .frameStart = now (para frameSync de este iter)
    LD HL, TickRemainder
    ADD A, (HL)                 ; A = elapsed + remainder pendiente
    LD C, A
    AND $01
    LD (HL), A                  ; new remainder = total mod 2
    SRL C                       ; C = total / 2 = game frames
    LD A, C
    LD (FramesElapsed), A

    ; === DEATH BORDER FLASH + ANIM PLAYER: tick por frame, incluso en GameOver ===
    CALL UpdateDeathBorder
    CALL UpdateDeathAnim
    ; Music tick: ahora vive en MusicIrqHandler (slot 1, cada 2 IRQs = 25 Hz).
    ; Auditoria de concurrencia AY confirmada: todos los AY writes desde
    ; MainLoop estan envueltos en DI/EI (ay_sound_thunks + sfx_player_hit_ay).
    ; UpdateMusicImpl sigue vivo como catchup-fallback no llamado por defecto.
    ; Bank-7 music prefetch: si la track activa (EndGame) vive en bank 7, esto
    ; pagina bank 7 y rellena el buffer de slot 1 antes de que el IRQ lo
    ; consuma. Early-out instantaneo si la track no es bank-7. Ver
    ; music_irq.asm PrefetchMusic.
    CALL PrefetchMusic

    ; --- Debug unlock + pausa: poll cada frame ANTES de los gates de juego ---
    ; DebugFramePoll lee B/U/G (unlock), ENTER (toggle pausa) y tickea el flash
    ; blanco. Vive en slot 1 (debug_unlock.asm). Tiene que correr SIEMPRE — si
    ; lo gatearamos por GameOver/pausa, no se podria despausar.
    CALL DebugFramePoll

    ; === GAME OVER: pantalla estatica, no gameplay ni HUD ===
    LD A, (GameOver)
    OR A
    JR Z, .notGameOver
    CP 2
    JR NC, .gameOverWaitInput   ; ya pintado, esperar input (tecla/joystick)
    ; GameOver==1: pintar pantalla esta vez y bumpear a 2
    CALL PaintGameOverScreen
    LD A, 2
    LD (GameOver), A
    JP .frameSync
.gameOverWaitInput:
    CALL UpdateGameOverAnim     ; Death moonwalkea por la pantalla negra
    CALL SplashCheckInput       ; cualquier tecla o Kempston -> NZ
    JP Z, .frameSync            ; nada pulsado: seguir esperando
    ; input detectado: reset total -> JP Inicio
    DI
    LD SP, SP_ADDRESS
    JP Inicio
.notGameOver:

    ; ==========================================================================
    ; TICK A (hibrido 50 Hz): primer sub-frame del par de 25 fps.
    ; Player a media velocidad + redraw (posicion a 50 Hz), 1 enemigo del
    ; round-robin y el HUD (movido aqui desde .afterGameplay). Cuerpo y gates
    ; en slot 1 (music_irq.asm, hueco pre-vector): en pausa o cutscene el
    ; gameplay del tick A se salta pero el HUD se sigue pintando (igual que
    ; hacia .afterGameplay). El HALT marca la frontera del sub-frame; el
    ; frameSync final sigue cerrando el par a 2 ticks.
    ; ==========================================================================
    IF HYBRID_50HZ
    CALL TickA                  ; gates + player 50 Hz + 1 enemigo + Muerte + HUD
    ENDIF
    ; --- Frontera de sub-frame: HALT CONDICIONAL ---
    ; Si el tick A ya invadio el frame 2 (picos de la Muerte: DeathBfsRescue
    ; reintenta CADA frame mientras esta atascada, ~10-40k T por disparo),
    ; esperar otro IRQ estiraria el par a 3 frames -> juego entero al 66%
    ; ("la Muerte ralentiza al player"). En ese caso saltamos directos al
    ; tick B: el par degrada al comportamiento pre-hibrido (un bloque de
    ; trabajo, 2 frames, player a 25 Hz ese par) en vez de perder un frame.
    IF HYBRID_50HZ
    LD A, (.frameStart)
    LD B, A
    LD A, ($5C78)
    SUB B                       ; 0 = seguimos dentro del frame 1 del par
    JR NZ, .tickB
    HALT                        ; frontera normal (2o IRQ del par)
.tickB:
    ENDIF

    ; ==========================================================================
    ; TICK B: el frame de 25 fps de siempre (logica completa).
    ; ==========================================================================
    ; === PAUSA (ENTER): si activa, saltar gameplay -> player/enemies/timers
    ; congelados. AY se silencia en MusicIrqHandler. (HUD ya pintado en tick A.)
    LD A, (PauseActive)
    OR A
    JP NZ, .afterGameplay

    ; === PRE-RENDER: gestionar pantalla (NOP en frames normales) ===
    CALL CheckScreenTransition  ; Detectar cambio de pantalla (~100T normal)
    ; (perf) Gate del roll: el body early-outea con !ScreenDirty, pero el
    ; thunk a bank 7 (SP swap + doble page switch) se pagaba igual cada
    ; frame. Chequear aqui la misma variable evita el viaje entero.
    LD A, (ScreenDirty)
    OR A
    CALL NZ, UpdateRandomPickup ; Random pickup roll (solo en transicion)
    ; Lasting compass gating: solo el caso del roll DIRECTO a COMPASS necesita
    ; invalidacion aqui (synth ptr == BgGfx_pickup_compass → pickup redundante).
    ; El caso de la ruleta ya esta cubierto upstream: AdvanceRouletteIdx /
    ; SkipCompassIfNeeded (random_pickups.asm) saltan la entry ROUL_COMPASS
    ; del RouletteOrder cuando MagicCompassPermanent != 0 — la ruleta cicla
    ; 8 estados (de 9) sin mostrar un solo frame de compass.
    LD A, (MagicCompassPermanent)
    OR A
    JR Z, .lcSkipRPGate
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_pickup_compass
    OR A
    SBC HL, DE
    JR NZ, .lcSkipRPGate
    LD A, $FE
    LD (RandomSynthMapX), A
.lcSkipRPGate:
    CALL DrawScreen             ; Redibujar BG si necesario (~20T normal)
    CALL RemapScreenAttrs       ; Remap attrs si cambio de fase (~fast)

    ; === CUTSCENE final (M11, puerta sur): si activa, saltar gameplay ===
    ; Excepcion: TGP_WAIT_NASTIES (16) deja correr ProcessEnemies para que los
    ; puffs de nasties recien matados se animen antes del LOCK pause.
    LD A, (TownGatePhase)
    OR A
    JR Z, .townGateNotActive
    CP 16                       ; TGP_WAIT_NASTIES
    JP Z, .townGateWaitNasties
    JP .townGateCutsceneActive
.townGateNotActive:

    ; === CUTSCENE banco (M9 nuevo): si activa, saltar gameplay ===
    ; Excepcion: BCP_WAIT_NASTIES (17) deja correr ProcessEnemies + ProcessDeath
    ; para que los puffs de nasties recien matados se animen antes del LOCK.
    LD A, (BankCutscenePhase)
    OR A
    JR Z, .bankCutsceneNotActive
    CP 17                       ; BCP_WAIT_NASTIES
    JP Z, .bankCutsceneWaitNasties
    JP .bankCutsceneActive
.bankCutsceneNotActive:

    ; === CUTSCENE de la iglesia (M7): si activa, saltar gameplay ===
    LD A, (ChurchCutscenePhase)
    OR A
    JP NZ, .cutsceneActive

    ; === PLAYER: siempre cada frame, completo (erase+logic+draw) ===
    CALL EraseDeadSprites       ; Cleanup puff terminadas (~20T normal)
    CALL ReadInput              ; Leer teclado (QAOP + SPACE)
    CALL UpdateRespawnBlink     ; Tick del parpadeo prep/grace + zero input en phase 1
    CALL ProcessPlayer          ; Erase + logic + draw player (mitad B del movimiento)
    IF HYBRID_50HZ
    CALL SnapPlayerOnStop       ; Parado y desalineado (mod 4) por el hibrido -> snap
    ENDIF
    CALL DrawPendingTomb        ; Pinta tumba in-place tras erase del sprite muerte
    CALL CheckWellPickup        ; Recuperar salud/stamina si pisa un pozo
    CALL CheckPickupCollect     ; Detectar pickups (borrado diferido al siguiente frame)
    ; (perf) CheckBumpTriggers + CheckLockBump van juntos tras un gate que
    ; salta ambos scans en salas sin puertas/locks y mantiene el tick de
    ; BumpInhibitFrames (ver screen_system.asm). Dims de los sprites ahora
    ; salen de BumpLockCache (0 page switches por frame).
    CALL CheckBumpAndLocks      ; Bump-triggers + SFX denegado de locks sin llave
    CALL CheckTownGateTriggerBg ; Cutscene final: arco sur (BG sprite, no en PickupTable)
    CALL CheckBankTriggerBg     ; Cutscene banco: facade BG en sala (8,8) con cheque

    ; Limpiar flag de pantalla recien dibujada (tras renderizar player)
    XOR A
    LD (ScreenJustRedrawn), A

    ; Flow field BFS: DESACTIVADO por coste (~1M T-states = 7 frames stutter).
    ; La infraestructura vive en monster_ai.asm y bank 6 (FlowField + BfsQueue).
    ; Para reactivar: amortizar el BFS en K iteraciones por frame (TODO).
    ; CALL MaiMaybeRecomputeFlow

    ; === ENEMIGOS: round-robin, erase+logic+draw por entidad ===
    ; (hibrido: 1 aqui + 1 en tick A = 2 por par, mismo throughput de siempre.
    ; ProcessDeath vive en el tick A por balance de sub-frames — ver TickAGameplay)
    IF HYBRID_50HZ
    LD A, 1
    LD (EnemyBudget), A
    CALL ProcessEnemies         ; Round-robin: 1 enemigo en este sub-frame
    ELSE
    LD A, 2
    LD (EnemyBudget), A
    CALL ProcessEnemies         ; Round-robin: 2 enemigos por vuelta
    CALL ProcessDeath           ; La muerte (slot 11): fuera del round-robin
    ENDIF
    CALL RefreshPickupAttrs     ; Re-pinta attrs de pickups tras erase de enemigos
    CALL UpdateSynthAndRoulette ; Attrs synth + ciclo ruleta (gates: solo con random pickup activo)
    CALL UpdatePickupFlash      ; Parpadeo de pickups recién spawnados (church_key)

    ; === SISTEMAS GLOBALES ===
    CALL UpdatePostTrapPause    ; Tick pausa cinematografica tras cutscene de iglesia
    CALL TrySpawnNasty          ; Spawn check (tiene su propio timer)
    CALL TryRespawnMonsters     ; Rellenar slots monster vacios (siempre 3)
    CALL UpdateDeathTimer       ; Tick contador 10s + spawn la muerte si toca
    CALL CheckPlayerEnemyCollision ; Colision player vs enemigos
    CALL CheckDeathTouchPlayer  ; La muerte toca al player → drena HP + despawn
    ; AY_UpdatePlayerHit ya NO se llama desde MainLoop — el tick SFX
    ; corre desde el IRQ handler (music_irq.asm) a 25 Hz, inmune a la
    ; latencia de MainLoop (transiciones lentas estiraban el beep antes).
    ; Lasting compass: refrescar timer cada frame para que la magic compass
    ; nunca expire. Hook minimo (12 B en bank 2, 0 B en slot 1) que NO toca
    ; UpdateMagicCompass — el flujo (jingle, BFS, tick, HUD) corre normal.
    LD A, (MagicCompassPermanent)
    OR A
    JR Z, .lcCallUpdate
    LD HL, MAGIC_COMPASS_FRAMES
    LD (MagicCompassTimer), HL
.lcCallUpdate:
    CALL UpdateMagicCompass     ; Tick magic compass (timer + blink + AY tick + jingle + BFS)
    CALL UpdateBeeperTicks      ; Tic beeper: buff/compass según slot del ciclo 25f
    JR .afterGameplay
.cutsceneActive:
    CALL UpdateChurchCutscene   ; Avanza phase machine de la cutscene
    JR .afterGameplay
.bankCutsceneActive:
    CALL UpdateBankCutscene     ; Phase machine del cutscene del banco (M9 nuevo)
    JR .afterGameplay
.bankCutsceneWaitNasties:
    ; Pre-LOCK wait: deja correr ProcessEnemies + ProcessDeath para que los
    ; puffs de nasties recien matados se animen. Skip ProcessPlayer (player
    ; ya snap'd a anchor por StartBankCutscene). Skip pickup collect / bump
    ; triggers (ya en cutscene, no re-disparar nada).
    CALL EraseDeadSprites
    LD A, 2                     ; cutscene: tick A no procesa enemigos -> 2 aqui
    LD (EnemyBudget), A
    CALL ProcessEnemies
    CALL ProcessDeath
    CALL UpdateBankCutscene     ; tick wait timer; transiciona a LOCK al expirar
    JR .afterGameplay
.townGateCutsceneActive:
    CALL UpdateTownGateCutscene ; Phase machine del cutscene final (M11)
    JR .afterGameplay
.townGateWaitNasties:
    ; Pre-LOCK wait: deja correr ProcessEnemies para que los puffs de
    ; nasties recien matados se animen. Skip ProcessPlayer (player frozen
    ; en anchor1, ya dibujado en StartTownGateCutscene). Skip pickup
    ; collect/bump triggers (ya en cutscene, no re-disparar nada).
    CALL EraseDeadSprites
    LD A, 2                     ; cutscene: tick A no procesa enemigos -> 2 aqui
    LD (EnemyBudget), A
    CALL ProcessEnemies
    CALL ProcessDeath
    CALL UpdateTownGateCutscene ; tick wait timer; transiciona a LOCK al expirar
.afterGameplay:
    ; (Con HYBRID_50HZ el HUD se pinta en el tick A del par. Sin el, aqui, al
    ; final como siempre: pintarlo antes retrasa los sprites y el haz los
    ; pilla a medias -- parpadeo de dia 12,5 % -> 15,7 % medido.)
    IF !HYBRID_50HZ
    CALL DrawHudBlock
    ENDIF
    ; === Updates + debug: pausados durante cualquier cutscene o pausa ENTER ===
    LD A, (PauseActive)
    OR A
    JR NZ, .skipUpdates
    LD A, (ChurchCutscenePhase)
    OR A
    JR NZ, .skipUpdates
    LD A, (TownGatePhase)
    OR A
    JR NZ, .skipUpdates
    LD A, (BankCutscenePhase)
    OR A
    JR NZ, .skipUpdates
    CALL UpdateWellCooldown     ; Tick cooldown del pozo + repintar blanco si activo
    CALL UpdateGameClock        ; Avanzar reloj de juego
    CALL UpdateEnemySpeed       ; Ajustar velocidad nasties segun ciclo
    CALL UpdateBellChimes       ; Campanadas de medianoche (si activas)
    CALL UpdateBellsDoneTimer   ; Cadena post-campanadas: ventanas off → monster spawn
    CALL UpdateMonstersMusic    ; Secuencer "po-po-popo-po" (canal B AY) durante la noche
    CALL UpdateStatueBlink      ; Parpadeo ON-OFF de la estatua que se enciende
    ; AY_UpdateBell removido: bell decay tickea ahora en MusicIrqHandler
    ; (BellTickIrq, slot 1) cada 25 Hz, inmune a la latencia de MainLoop /
    ; DrawScreen. Antes la campanada se "alargaba" o "apagaba raro" en
    ; transiciones porque el catchup desde MainLoop daba saltos.
    CALL UpdateScareTimer       ; Countdown pausa+huida (bells/dawn)
    CALL CheckDebugKeys         ; Tecla T: ciclar momento del dia (debug)
    CALL CheckMilestoneDebugKey ; Tecla H: skip de hito (debug)
    CALL CheckCurrentKeyCycleKey ; Tecla K: cicla CurrentKey 0..6 (debug)
    CALL CheckMinimapKey        ; Tecla M: overlay de minimap
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
    ; Tabla de vectores IM 2 — DEBE vivir en bank 2 (unica RAM no-contended
    ; siempre visible; con I apuntando a RAM contended el hardware real nieva:
    ; fix ULA snow, ver im2_table.asm). ALIGN 256 en esta frontera de INCLUDEs
    ; minimiza el padding. Inicio hace LD A, high Im2Table.
    INCLUDE "im2_table.asm"
    INCLUDE "logic_game.asm"
    INCLUDE "screen_system.asm"
    INCLUDE "screen_data.asm"
    ; bg_gfx.asm: movido a bank 3 (ver PAGE 3 abajo)
    ; sprite_data.asm + shift_tables.asm: movidos a bank 6. DrawSprite
    ; lee ambos simultaneamente (sprite + tablas de shift), por lo que
    ; deben vivir en el mismo banco paginado.
    INCLUDE "day_cycle.asm"
    INCLUDE "hud_clock.asm"
    INCLUDE "hud_extras.asm"
    INCLUDE "milestones.asm"
    ; town_gate_cutscene.asm: incluido arriba en $6000+ (slot 1).
    INCLUDE "sound.asm"
    ; ay_sound.asm: movido a bank 4 (ver PAGE 4 abajo). MainLoop entra via
    ; los thunks en ay_sound_thunks.asm.

    ; bank_cutscene.asm: movido a bank 7 (PAGE 7) para liberar ~1.6 KB en
    ; bank 0. Los entry points (CheckBankTriggerBg / UpdateBankCutscene)
    ; viven como thunks en slot 1 (bank_cutscene_thunks.asm, ya incluido
    ; arriba).

    ; minimap.asm: MOVIDO a slot 1 (bloque arriba) — al final de bank 0 sus
    ; rutinas caian en la zona del stack ($FE80-$FF58) y se corrompian (crash
    ; al abrir el mapa). Ver minimap_stack_fix_handoff.md.

    ; --- Audicion de SFX: solo con -DSFXTEST (tools/perf/sfx_audition.py) ---
    IFDEF SFXTEST
    INCLUDE "sfx_test.asm"
    ENDIF

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
    ; --- Standalone splash body (solo con --define STANDALONE) ---
    ; Contiene wrapper DecompressSplashBody + dzx0_standard + INCBIN del blob
    ; (~4.1 KB). Llamado via thunk DecompressSplash en slot 1.
    IFDEF STANDALONE
    INCLUDE "standalone_splash_body.asm"
    ENDIF
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
    ; credits_font: font 8x8 custom (472 B) usado solo por la fase CREDITS del
    ; town gate cutscene. Workaround a la font ROM en $3D00 (no fiable durante
    ; el cutscene en bank 7). LoadCreditsFontToBuffer (thunk slot 1) lo copia
    ; a BgSpriteBuffer una vez al entrar la fase.
    INCLUDE "credits_font.asm"
    ; --- debug_unlock body (movido desde slot 1; entra via thunk DebugFramePoll
    ; en debug_unlock_thunk.asm). Codigo puro, deps siempre-visibles, sin CALLs
    ; a bank 0. Libera ~194 B en slot 1 para minimap.asm. ---
    INCLUDE "debug_unlock.asm"
    ; --- beeper_ticks body (movido desde slot 1; entra via thunks UpdateBeeperTicks
    ; + FireBuffNormalTick en beeper_ticks_thunks.asm). Codigo puro, lee solo vars
    ; bank 2 + puertos, sin CALLs a bank 0. Libera ~252 B en slot 1. ---
    INCLUDE "beeper_ticks.asm"
    ; --- minimap_sprites data (movido desde slot 1). Solo DEFB (sin entry points);
    ; lo lee smRenderMap tras paginar bank 4 (bufferea MapTable antes). Libera
    ; ~488 B en slot 1 para minimap.asm. Generado por build_minimap_sprites.py. ---
    INCLUDE "minimap_sprites.asm"
    ; --- Standalone main body (solo con --define STANDALONE) ---
    ; F1Body + cards + render + glyphs (~440 B). Refactor B previo a F4: bank 1
    ; con 102 B libres no cabia F3-F5. Bank 4 tiene 4533 B libres ahora albergan
    ; tambien el body, dejando bank 1 solo con blob + dzx0_standard. Caller
    ; (StandaloneF1Setup en slot 1) pagina bank 4 antes del CALL F1Body.
    IFDEF STANDALONE
    INCLUDE "standalone_main_b4.asm"
    ENDIF
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
    ; --- Per-room gaps data (auto-generado, ~2000 B) ---
    ; Movido aqui desde slot 1 para liberar el overflow. magic_compass.asm
    ; pagina bank 7 antes de leer RoomCompGaps_XX, restaura bank 0 al
    ; terminar el chunk BFS. La pointer table (RoomCompGapsTable) sigue
    ; en slot 1 — sus valores son addresses en $C000+ que solo se
    ; deberefencian con bank 7 paginado.
    INCLUDE "room_routes_bank7.asm"
    ; --- Game Over tumba 2x — body (~538 B) ---
    ; Cold path one-shot. Llamado via thunk en slot 1 (game_over_tomb_thunk.asm).
    ; El body NO debe llamar a LoadBgSpriteToBuffer (esa rutina restaura bank 0
    ; al final → bank 7 desapareceria con el body ejecutandose). El thunk hace
    ; la carga del sprite ANTES de paginar bank 7 y llamar al body.
    INCLUDE "game_over_tomb.asm"

    ; --- Bank cutscene body (M9, ~1.7 KB con wrappers) ---
    ; Movido aqui desde bank 0 para descongestionar el main code (que estaba
    ; a 3 B libres). Los entry points (CheckBankTriggerBg / UpdateBankCutscene)
    ; viven como thunks en slot 1 (bank_cutscene_thunks.asm). El body usa
    ; _PageBank0 / _PageBank7 (slot 1, always-visible) para envolver cada
    ; CALL externo: el body no puede llamar directamente a rutinas bank 0
    ; porque slot 3 esta paginado a bank 7 mientras el body ejecuta.
    INCLUDE "bank_cutscene.asm"

    ; --- Magic compass BFS Inner body (~690 B, slot 1 -> bank 7 move) ---
    ; _ComputeMagicCompassPath_Inner + helpers + locales DEFB. Antes vivian
    ; al final de magic_compass.asm en slot 1, pero los thunks de
    ; bank_cutscene_thunks.asm los empujaron sobre $7A00 (la tabla IM2, que
    ; entonces vivia ahi, los sobreescribia con $7B; hoy esta en bank 2).
    ; Movido aqui para preservar magic compass.
    ; ComputeMagicCompassPath en slot 1 pagina bank 7 antes de CALL _Inner;
    ; el wrapper se encarga del paging. Sin SP swap necesario porque el body
    ; permanece visible toda su ejecucion.
    INCLUDE "magic_compass_bfs_bank7.asm"

    ; --- Town gate cutscene body (~1200 B, slot 1 -> bank 7 move) ---
    ; Body movible: phase machine + anim helpers + DrawTheEnd + DrawCredits +
    ; PrintStringFontAt + DrawCharFontAt + SFX stubs + TownGateCreditsData.
    ; Entry thunks (CheckTownGateTriggerBg / UpdateTownGateCutscene) viven en
    ; bank_cutscene_thunks.asm (slot 1) con SP swap igual que bank_cutscene.
    ; Comparten alt_stack porque las 2 cinematicas son mutuamente exclusivas
    ; (M11 vs M9). Funciones que se quedan en slot 1 (town_gate_cutscene.asm):
    ; KillDeathIfActive, TownGate*Player*, BiClip, SlideErase/Draw,
    ; AllNastiesDeadCheck — usadas por bank_cutscene o paginan slot 3.
    INCLUDE "town_gate_cutscene_bank7.asm"

    ; --- Random pickups body (~1.26 KB, slot 1 -> bank 7 move) ---
    ; Antes vivia en slot 1 entre $6BF7..$70E4. Movido aqui para liberar slot 1
    ; (RoomCompGapsTable y el resto del flujo compiten por el espacio de
    ; slot 1 antes del ORG $7B7B de Im2Vector).
    ; Los 9 entry points externos (UpdateRandomPickup, UpdateRoulette, ...) viven
    ; como thunks en slot 1 (random_pickups_thunks.asm). El body usa _B7 wrappers
    ; (LoadBgSpriteToBuffer_B7, DrawBgSpriteXOR_B7, SkipPixelData_B7,
    ; RestorePickupAttrs_B7, ApplyMagicCompassBuff_B7) para envolver cada CALL
    ; externo. Los SFX van por AY_PlaySFX (slot 1), sin wrapper. Internamente
    ; las dispatch tail-JPs (GiveLife etc.) usan los Body suffix (intra-bank,
    ; no thunk).
    INCLUDE "random_pickups.asm"

    ; --- EndGameMusicTable (~1085 B) ---
    ; Datos puros (no codigo). Accedidos via PrefetchMusic en slot 1, que
    ; pagina bank 7, hace LDIR de 7 B al buffer slot 1, y repagina bank 0.
    ; Sin thunk: no se llama codigo aqui — solo se lee. Ver music_irq.asm
    ; PrefetchMusic + ay_sound.asm .smArmEndGameBank7.
    INCLUDE "music_endgame_bank7.asm"

    ; --- GameOverMusicTable (~224 B) ---
    ; Misma infra que EndGame. One-shot (MusicLoop=0). Ver ay_sound.asm
    ; .smArmGameOverBank7.
    INCLUDE "music_gameover_bank7.asm"

    ; --- StartGameMusicTable (~105 B) ---
    ; Jingle corto post-splash (press any key intro). One-shot, mono canal A.
    ; Ver ay_sound.asm .smArmStartGameBank7. Track ID 5.
    INCLUDE "music_startgame_bank7.asm"
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
    ; --- SFX AY: tablas y programas (generado por tools/build_sfx.py desde
    ; sfx_library.json). Antes vivian en slot 1; AY_PlaySFX pagina este bank
    ; (SFX_DATA_BANK) y copia el SFX que empieza a AySfxBuf (slot 1), que es lo
    ; unico que lee la IRQ. Bank 6 y no 4: en la build standalone bank 4 va lleno. ---
SfxDataStart:
    INCLUDE "sfx_data.asm"
Bank6End    EQU $
    PAGE 0

    ; ==========================================================================
    ; GENERACIÓN DE ARCHIVOS BINARIOS (Emuladores y depuradoras)
    ; ==========================================================================
    CSPECTMAP "juego.map"
    IFDEF STANDALONE
    ; Pre-cargar bg-185 en VRAM ($4000-$5AFF, slot 1 bank 5) para replicar
    ; comportamiento clasico de carga del Spectrum: la SCREEN$ se mantiene
    ; visible hasta que el codigo la sobreescriba. SAVESNA captura estos
    ; bytes directamente en VRAM -> el SNA arranca con 185 en pantalla.
    ; SAVETAP los emite como CODE block load_addr=$4000 (= LOAD ""SCREEN$).
    ; 6912 B en zona VRAM = NO consume bank RAM (es parte de la 48K base).
    ORG $4000
    INCBIN "bg_185.scr"
    SAVETAP "juego_standalone.tap", Inicio
    SAVESNA "juego_standalone.sna", Inicio
    ELSE
    SAVETAP "juego.tap", Inicio
    SAVESNA "juego.sna", Inicio
    ENDIF

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
    ; Zona de corrupcion por stack: SP=$FF58 vive en slot 3 y los IRQs hacen
    ; PUSH durante todo el frame — datos/codigo de bank 0 por encima de ~$FE80
    ; se corrompen en runtime (caso real: minimap_sprites, ver
    ; project_slot3_stack_corruption). El tail de bank 0 esta hoy a ~22 B del
    ; limite; este ASSERT caza el overflow en build en vez de con un crash.
    ASSERT Bank0End <= $FE80
