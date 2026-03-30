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

MainLoop:
    HALT                    ; Esperar al barrido de pantalla (sincronizar a 50 FPS)

    ; Bucle principal estilo Sabre Wulf: Input -> Transicion -> Pantalla -> Entidades
    CALL ReadInput              ; Leer teclado (QAOP + SPACE)
    CALL CheckScreenTransition  ; Detectar y ejecutar cambio de pantalla
    CALL DrawScreen             ; Dibujar pantalla si es necesario (flick-screen)
    CALL ProcessEntities        ; Per-entity: erase -> update -> draw (ANTES de HUD)
    CALL CheckPlayerEnemyCollision ; Colision player vs enemigos
    CALL DrawClockHUD           ; Reloj: cara + agujas
    ;CALL DrawDebugInfo          ; DEBUG: desactivado, corrompe XOR en tercio superior
    CALL UpdateGameClock        ; Avanzar reloj de juego (transiciones automáticas)
    CALL CheckDebugKeys         ; DEBUG: tecla T cicla fase del día
    CALL CheckClockSpeedKeys    ; DEBUG: teclas 1/2/3 cambian velocidad del día
    CALL DrawRoomInfo           ; DEBUG: muestra coords e índice del room
    CALL DrawTimeIndicator      ; DEBUG: muestra momento del día en HUD

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
