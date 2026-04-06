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
