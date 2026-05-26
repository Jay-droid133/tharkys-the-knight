; ==============================================================================
; STANDALONE SPLASH body (bank 1) - solo blob ZX0 + descompresor
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Refactor B: el body completo
; (cards + render + glyphs) se movio a code/standalone_main_b4.asm (bank 4).
; Bank 1 queda con: blob bg-185 comprimido + dzx0_standard co-located.
;
; Co-location: dzx0_standard se llama con HL = bg_splash_zx0_data; ambos viven
; en bank 1 (cuando se descomprime via DecompressSplashTrampoline en slot 1).
; ==============================================================================

    INCLUDE "dzx0_standard.asm"

bg_splash_zx0_data:
    INCBIN "bg_splash.zx0"
bg_splash_zx0_end:
