; ==============================================================================
; STANDALONE thunks + helpers - Slot 1
; ==============================================================================
; Solo se ensambla con --define STANDALONE. Slot 1 always-visible.
;
; F5: StandaloneF1Setup INLINEADO en main.asm boot (slot 1 $6000+) para liberar
; bytes aqui. Aqui solo viven:
;   - DecompressSplashTrampoline: cross-bank decompress (slot 3 paga bank 1)
;   - SafeHaltAndPrefetch: HALT + PrefetchMusic + repage bank 4 (necesario en
;     wait loops de F1Body para que la musica EndGame no se cuelgue durante
;     menu/historia — PrefetchMusic pagina bank 7 y al volver deja bank 0; sin
;     este helper, el body en bank 4 desaparece de slot 3 -> crash).
;   - StandaloneSavedSP: DEFW para el SP swap inlined en main.asm.
; ==============================================================================

; ==============================================================================
; DecompressSplashTrampoline - cross-bank decompress de bg_splash.zx0 (sprite 257)
; ==============================================================================
; Llamado por F1Body (bank 4) cuando toca pintar 257 sobre VRAM. Pagina bank 1
; (blob + dzx0_standard), descomprime a $4000, repagina bank 4 (caller).
; SP ya apunta al alt_stack (set por inline F1Setup en main.asm).
; ==============================================================================
DecompressSplashTrampoline:
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD HL, bg_splash_zx0_data
    LD DE, $4000
    CALL dzx0_standard
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; ==============================================================================
; SafeHaltAndPrefetch - HALT + PrefetchMusic + repage bank 4 (F5)
; ==============================================================================
; Wait loops en F1Body (bank 4) deben hacer prefetch periodico para que la
; musica EndGame no se cuelgue (buffer slot 1 se vacia ~16 notas). PrefetchMusic
; pagina bank 7 internamente y al RET deja bank 0 -> si caller esta en bank 4,
; pierde acceso a su propio codigo. Este helper vive en slot 1 (always visible),
; hace el prefetch y repagina bank 4 antes del RET.
; Destruye: AF, BC.
;
; Body como MACRO para emitir bytes IDENTICOS en dos sitios: aqui en slot 1
; (callable address SafeHaltAndPrefetch) y un backup en bank 4 (junto a F1Body).
; El cutscene final hace PUSHes al BankCutsceneAltStack en $7FC0-$7FFF (pico
; medido ~22 B → SP llega a $7FEA), corrompiendo los bytes de esta rutina en
; slot 1 desde $7FEA en adelante. F1Body (en reboot post-creditos) restaura via
; LDIR desde el backup bank 4 a slot 1 antes de la primera CALL.
; ==============================================================================
    MACRO SAFE_HALT_AND_PREFETCH_BODY
        HALT
        CALL PrefetchMusic              ; pagina bank 7, repagina bank 0
        LD A, (CurrentPaging)
        AND $F8
        OR 4
        LD (CurrentPaging), A
        LD BC, $7FFD
        OUT (C), A
        RET
    ENDM

SafeHaltAndPrefetch:
    SAFE_HALT_AND_PREFETCH_BODY
SafeHaltAndPrefetch_End:
SAFE_HALT_AND_PREFETCH_SIZE EQU SafeHaltAndPrefetch_End - SafeHaltAndPrefetch

; ==============================================================================
; StandaloneSavedSP - SP normal salvado por el inline F1Setup en main.asm
; ==============================================================================
StandaloneSavedSP: DEFW 0
