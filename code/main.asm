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
    XOR A                   ; A = 0 (Negro)
    OUT (254), A            ; Cambia el color del borde a negro

    ; Limpiar TODA la pantalla (pixeles + atributos) antes de nada
    ; Los pixeles del loader del .tap quedan en VRAM si no se borran
    LD HL, SCREEN_BASE
    LD DE, SCREEN_BASE + 1
    LD BC, 6911             ; 6144 pixeles + 768 atributos - 1
    LD (HL), A              ; A=0
    LDIR

    ; Inicializar sistema de pantallas
    CALL InitScreenSystem   ; Configura pantalla inicial y calcula puntero

    IM 1                    ; Modo de interrupciones 1 (por defecto en Spectrum 48k)
    EI                      ; Habilitar interrupciones

MainLoop:
    HALT                    ; Esperar al barrido de pantalla (sincronizar a 50 FPS)

    ; Bucle principal estilo Sabre Wulf: Input -> Logica -> Pantalla -> Dibujo
    CALL ReadInput          ; Leer teclado (QAOP + SPACE)
    CALL UpdateLogic        ; Actualizar estado, movimiento y animacion
    CALL CheckScreenTransition  ; Detectar y ejecutar cambio de pantalla
    CALL DrawScreen         ; Dibujar pantalla si es necesario (flick-screen)
    CALL DrawPlayer         ; Dibujar jugador sobre la pantalla
    CALL DrawDebugInfo      ; DEBUG: mostrar coordenadas de pantalla

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
    INCLUDE "sprite_data.asm"

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
