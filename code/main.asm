; ==============================================================================
; PROYECTO ZX SPECTRUM 128K
; Archivo Principal - Punto de entrada
; ==============================================================================

    DEVICE ZXSPECTRUM128

    ; Inclusión de definiciones
    INCLUDE "constants.asm"
    INCLUDE "macros.asm"

    ; Origen del programa en RAM
    ORG ORIGIN_ADDRESS

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

    ; Inicializar sistema de pantallas
    CALL InitScreenSystem   ; Configura pantalla inicial y calcula puntero
    CALL InitEntities       ; Inicializar tabla de entidades (player en slot 0)
    CALL UpdateRemapTables  ; Aplicar remap para la hora de inicio
    CALL UpdateNastyTable   ; Seleccionar tabla de nasties para la fase inicial
    CALL ResolveObjectiveScreen ; Cachear (sx, sy) del primer hito
    ; (DrawClockSprite y DrawSwordModeHUD se llaman desde el MainLoop, no aqui)

    IM 1                    ; Modo de interrupciones 1 (por defecto en Spectrum 48k)
    EI                      ; Habilitar interrupciones

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

    ; === PRE-RENDER: gestionar pantalla (NOP en frames normales) ===
    CALL CheckScreenTransition  ; Detectar cambio de pantalla (~100T normal)
    CALL DrawScreen             ; Redibujar BG si necesario (~20T normal)
    CALL RemapScreenAttrs       ; Remap attrs si cambio de fase (~fast)

    ; === PLAYER: siempre cada frame, completo (erase+logic+draw) ===
    CALL EraseDeadSprites       ; Cleanup puff terminadas (~20T normal)
    CALL ReadInput              ; Leer teclado (QAOP + SPACE)
    CALL ProcessPlayer          ; Erase + logic + draw player (todo junto)
    CALL CheckWellPickup        ; Recuperar salud/stamina si pisa un pozo
    CALL CheckPickupCollect     ; Detectar pickups (borrado diferido al siguiente frame)
    CALL CheckBumpTriggers      ; Sprites trigger por colisión (puerta iglesia/ayuntamiento)

    ; Limpiar flag de pantalla recien dibujada (tras renderizar player)
    XOR A
    LD (ScreenJustRedrawn), A

    ; Flow field BFS: DESACTIVADO por coste (~1M T-states = 7 frames stutter).
    ; La infraestructura vive en monster_ai.asm y bank 6 (FlowField + BfsQueue).
    ; Para reactivar: amortizar el BFS en K iteraciones por frame (TODO).
    ; CALL MaiMaybeRecomputeFlow

    ; === ENEMIGOS: round-robin, erase+logic+draw por entidad ===
    CALL ProcessEnemies         ; Round-robin: hasta MAX_ENEMIES_PER_FRAME
    CALL RefreshPickupAttrs     ; Re-pinta attrs de pickups tras erase de enemigos
    CALL UpdatePickupFlash      ; Parpadeo de pickups recién spawnados (church_key)

    ; === SISTEMAS GLOBALES ===
    CALL TrySpawnNasty          ; Spawn check (tiene su propio timer)
    CALL TryRespawnMonsters     ; Rellenar slots monster vacios (siempre 3)
    CALL CheckPlayerEnemyCollision ; Colision player vs enemigos
    CALL DrawClockHUD           ; Reloj: cara + agujas (HUD fijo, no flicker)
    CALL DrawKeyHUD             ; Llave actual (slot 3×2 en cols 20-22, rows 22-23)
    CALL DrawPlazaClock         ; Reloj de plaza (si existe en esta room)
    CALL DrawHealthStaminaHUD   ; Barras salud/stamina en decoraciones
    CALL DrawSwordModeHUD       ; Debug: indicador modo espada
    CALL DrawNoclipHUD          ; Debug: indicador NoclipMode (N)
    CALL DrawDayCycleHUD        ; Indicador de dia (D1, D2, D3...)
    CALL DrawPlayerSpeedHUD     ; Debug: velocidad player (fila 0, col 2)
    CALL DrawEnemySpeedHUD      ; Debug: velocidad nasties (V1, V2...)
    CALL DrawCompass            ; Brujula del hito actual (cols 23-24, rows 0-1)
    CALL UpdateWellCooldown     ; Tick cooldown del pozo + repintar blanco si activo
    CALL UpdateGameClock        ; Avanzar reloj de juego
    CALL UpdateEnemySpeed       ; Ajustar velocidad nasties segun ciclo
    CALL UpdateBellChimes       ; Campanadas de medianoche (si activas)
    CALL UpdateBellsDoneTimer   ; Cadena post-campanadas: ventanas off → monster spawn
    CALL AY_UpdateBell          ; Decay manual del volumen de la campana
    CALL UpdateScareTimer       ; Countdown pausa+huida (bells/dawn)
    CALL CheckDebugKeys         ; Tecla T: ciclar momento del dia (debug)
    CALL CheckMilestoneDebugKey ; Tecla M: skip de hito (debug)

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
    INCLUDE "paging.asm"
    ; monster_ai.asm DEBE vivir en bank 2 fijo ($8000-$BFFF) porque sus
    ; rutinas pagan bank 6 en slot 3 y se ejecutarian ellas mismas si
    ; estuvieran en bank 0. Incluir aqui temprano (detras de paging.asm)
    ; garantiza que aterricen antes de $C000.
    INCLUDE "monster_ai.asm"
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
    INCLUDE "sound.asm"
    INCLUDE "ay_sound.asm"

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
