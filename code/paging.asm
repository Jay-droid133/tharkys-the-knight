; ==============================================================================
; PAGING - Control de bancos RAM del Spectrum 128K
; ==============================================================================
; Port $7FFD (write-only):
;   bits 0-2: banco RAM en slot 3 ($C000-$FFFF)
;   bit 3:    pantalla (0=normal, 1=shadow)
;   bit 4:    ROM (0=128 editor, 1=48 BASIC)
;   bit 5:    disable paging (permanent lock — NO tocar)
;
; Bancos disponibles:
;   Bank 0: mapeado en $C000-$FFFF por defecto. Contiene parte del juego actual.
;           NO tocar mientras se ejecuta codigo desde $C000+.
;   Bank 1: libre para datos nuevos (contended)
;   Bank 2: fijo en $8000-$BFFF, no paginable (no-contended)
;   Bank 3: libre para datos nuevos (contended)
;   Bank 4: libre para datos nuevos (no-contended)
;   Bank 5: pantalla en $4000-$5AFF (contended)
;   Bank 6: libre para datos nuevos (no-contended)
;   Bank 7: libre (no-contended), usar con cuidado (shadow screen)
; ==============================================================================

; Rutinas de paginacion — se ejecutan SIEMPRE desde bank 2 ($8000-$BFFF)
; para no machacarse a si mismas al cambiar de banco.

; ==============================================================================
; PageBankSlot3 - Cambia el banco en slot 3 ($C000-$FFFF)
; ==============================================================================
; Entrada: A = banco (0-7)
; Preserva: HL, DE, IX, IY
; Destruye: A, BC
; ==============================================================================
PageBankSlot3:
    AND $07                     ; asegurar solo bits 0-2
    LD B, A                     ; guardar banco nuevo
    LD A, (CurrentPaging)
    AND $F8                     ; limpiar bits de banco
    OR B                        ; poner nuevo banco
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; ==============================================================================
; InitPaging - Estado inicial de paginacion al arrancar
; ==============================================================================
; Llamar en el startup antes de cualquier acceso paginado.
; Deja bank 0 en slot 3 (que es el default del Spectrum 128K al boot).
; ==============================================================================
InitPaging:
    LD A, $10                   ; bank 0, screen normal, ROM 48, paging enabled
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; ==============================================================================
; LoadRoomToBuffer - Copia un Room_Txx desde bank 1 a CurrentScreenBuffer
; ==============================================================================
; IN:  HL = puntero al Room_Txx (direccion en $C000-$FFFF, en bank 1)
; OUT: CurrentScreenBuffer relleno con los bytes del room (terminador $0000).
;      Paginacion restaurada a bank 0.
; Destruye: A, BC, DE, HL
;
; Formato del room: secuencia de entries de 5 B { DEFW BgPtr, DEFB x,y,v }
; hasta encontrar un BgPtr = $0000 que marca el final. Copiamos los 2 bytes
; del puntero, y si no es $0000 tambien los 3 bytes de coords, hasta terminador.
; ==============================================================================
LoadRoomToBuffer:
    ; El stack vive en slot 3 ($FF58). Paginar con CALL a PageBankSlot3
    ; corromperia el stack: CALL empuja la direccion de retorno en bank X,
    ; el OUT cambia el slot a bank Y, RET popearia de bank Y → garbage.
    ; Por eso INLINEAMOS el page-switch aqui, sin CALL intermedios.
    ;
    ; Entre los dos OUT no se debe tocar el stack: nada de CALLs, PUSHes
    ; ni interrupciones (DI). Solo LDs al buffer.
    LD A, I                         ; P/V = IFF2 (interrupts previos)
    PUSH AF                         ; push en bank 0 (slot 3 sigue bank 0)
    DI
    ; --- Page bank 1 en slot 3 (inline) ---
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 1
    ; --- Copy loop (HL = Room_Txx en bank 1, DE = buffer) ---
    LD DE, CurrentScreenBuffer
.lrbLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD C, A                         ; C = low byte del ptr
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    OR C                            ; terminador si ambos = 0
    JR Z, .lrbDone
    ; Copiar 3 bytes mas (x, y, v)
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    JR .lrbLoop
.lrbDone:
    ; --- Page bank 0 en slot 3 (inline) ---
    LD A, (CurrentPaging)
    AND $F8                         ; bank 0
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 → stack accesible otra vez
    ; Restaurar IFF original: si estaba deshabilitado (startup), no hacer EI
    POP AF                          ; pop desde bank 0 (el que pusimos al entrar)
    RET PO                          ; P/V odd = IFF2 era 0 → dejar DI
    EI
    RET
