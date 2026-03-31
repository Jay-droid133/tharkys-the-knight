; ==============================================================================
; PROYECTO ZX SPECTRUM 48K
; Archivo Principal - Punto de entrada
; ==============================================================================

    DEVICE ZXSPECTRUM48

    ; Inclusión de definiciones
    INCLUDE "constants.asm"
    INCLUDE "macros.asm"

    ; Origen del programa en RAM
    ORG ORIGIN_ADDRESS

Inicio:
    DI                      ; Deshabilitar interrupciones
    LD SP, SP_ADDRESS       ; Inicializar la pila (Stack Pointer)

    ; Configuración inicial (Borde negro, etc.)
    LD A, BLUE              ; A = 1 (Azul oscuro)
    OUT (254), A            ; Cambia el color del borde a azul oscuro
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
    CALL DrawClockSprite    ; Dibujar decoración del reloj (solo se repite en cambio de pantalla)

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
    HALT                    ; Esperar al barrido de pantalla (sincronizar a 50 FPS)

    ; === PRE-RENDER: gestionar pantalla (NOP en frames normales) ===
    CALL CheckScreenTransition  ; Detectar cambio de pantalla (~100T normal)
    CALL DrawScreen             ; Redibujar BG si necesario (~20T normal)
    CALL RemapScreenAttrs       ; Remap attrs si cambio de fase (~fast)

    ; === PLAYER: siempre cada frame, completo (erase+logic+draw) ===
    CALL EraseDeadSprites       ; Cleanup puff terminadas (~20T normal)
    CALL ReadInput              ; Leer teclado (QAOP + SPACE)
    CALL ProcessPlayer          ; Erase + logic + draw player (todo junto)

    ; Limpiar flag de pantalla recien dibujada (tras renderizar player)
    XOR A
    LD (ScreenJustRedrawn), A

    ; === ENEMIGOS: round-robin, erase+logic+draw por entidad ===
    CALL ProcessEnemies         ; Round-robin: hasta MAX_ENEMIES_PER_FRAME

    ; === SISTEMAS GLOBALES ===
    CALL TrySpawnNasty          ; Spawn check (tiene su propio timer)
    CALL CheckPlayerEnemyCollision ; Colision player vs enemigos
    CALL DrawClockHUD           ; Reloj: cara + agujas (HUD fijo, no flicker)
    CALL UpdateGameClock        ; Avanzar reloj de juego
    CALL UpdateBellChimes       ; Campanadas de medianoche (si activas)
    CALL CheckDebugKeys         ; Tecla T: ciclar momento del dia (debug)

    ; Incrementar contador de frames
    LD A, (GameFrameCounter)
    INC A
    LD (GameFrameCounter), A

    JR MainLoop

    ; Inclusión de módulos
    INCLUDE "variables.asm"
    INCLUDE "engine_graphics.asm"
    INCLUDE "logic_game.asm"
    INCLUDE "screen_system.asm"
    INCLUDE "screen_data.asm"
    INCLUDE "bg_gfx.asm"
    INCLUDE "sprite_data.asm"
    INCLUDE "shift_tables.asm"
    INCLUDE "day_cycle.asm"
    INCLUDE "hud_clock.asm"
    INCLUDE "sound.asm"

    ; ==========================================================================
    ; GENERACIÓN DE ARCHIVOS BINARIOS (Emuladores y depuradoras)
    ; ==========================================================================
    CSPECTMAP "juego.map"
    SAVETAP "juego.tap", Inicio
    SAVESNA "juego.sna", Inicio

    DISPLAY "========================================"
    DISPLAY "Fin de codigo actual (PC): ", $
    DISPLAY "RAM Libre en Upper block: ", 65536-$
    DISPLAY "========================================"
