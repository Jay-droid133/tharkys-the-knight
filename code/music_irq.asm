; ==============================================================================
; MUSIC_IRQ - IM 2 handler para tick de musica a 25 Hz
; ==============================================================================
; Vive en slot 1 ($7A00+, contended pero siempre visible).
;
; Por que existe: la latencia de MainLoop (especialmente en transiciones de
; pantalla, ~200 ms) provocaba que la musica avanzara N notas en una sola
; iteracion, escribiendo solo el ultimo period al AY. El usuario percibia
; notas "saltadas" o ritmo desplazado. Con IM 2 + handler propio, el tick de
; musica ocurre cada 2 IRQs (= 25 Hz) independientemente de la carga del
; MainLoop. Las escrituras AY caen en el wall-clock exacto, ritmo intacto.
;
; IM 2 setup (Inicio):
;   I = $7A
;   Tabla 257 bytes en $7A00-$7B00, todos $7B (cualquier byte del data bus
;     da vector = $7B7B).
;   $7B7B: JP MusicIrqHandler.
;
; Race condition con AY desde MainLoop: las rutinas que escriben AY desde
; gameplay (StartMusic thunk, AY_PlayBeep, AY_PlayBellChime, etc.) ya hacen
; DI/EI alrededor de sus AY OUTs, asi que no son interrumpidas. Las
; escrituras AY desde el IRQ handler no necesitan DI extra (CPU ya tiene
; interrupts deshabilitados al entrar al handler).
; ==============================================================================

; --- Vector table (257 bytes all $7B) ---
; Cualquier byte del data bus da vector = $7B7B (.im2Vector).
    ORG $7A00
.im2Table:
    DEFS 257, $7B                       ; $7A00-$7B00 inclusive

; --- Vector target: JP MusicIrqHandler ---
    ORG $7B7B
.im2Vector:
    JP MusicIrqHandler

; --- IRQ handler proper ---
; Cada IRQ:
;   1. INC $5C78 (system frames counter — ROM IRQ no se ejecuta con IM 2).
;   2. Toggle MusicIrqDivisor: solo tickea musica cada 2 IRQs (= 25 Hz).
;   3. Si toca tick: paga bank 4, llama UpdateMusicIrqImpl, restaura paging.
;   4. EI + RET.
;
; Coste: ~80 T-states en frame skip (no tick), ~250 T-states en frame tick.
; Per-second: ~12500 T = 0.36% del CPU. Despreciable.
MusicIrqHandler:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    ; --- Increment $5C78 ---
    LD HL, $5C78
    INC (HL)
    JR NZ, .mihNoWrap
    INC HL
    INC (HL)
.mihNoWrap:

    ; --- Toggle divisor (25 Hz) ---
    LD HL, MusicIrqDivisor
    LD A, (HL)
    XOR 1
    LD (HL), A
    JR Z, .mihEpilogue

    ; --- Page bank 4. Guardamos el valor antiguo de paging en variable
    ; ESTATICA en slot 1 (siempre visible), NO en el stack: el stack vive en
    ; slot 3 y al paginar bank 4 cambia de fisico, asi que un PUSH antes del
    ; page-switch + POP despues lee bank 4 RAM con basura. Ver
    ; project_ay_thunk_stack_bug.md para el mismo bug en thunks. ---
    LD A, (CurrentPaging)
    LD (IrqSavedPaging), A
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; --- BASELINE: solo paging-dance, SIN tick de musica todavia. ---
    ; Validamos que IM 2 + paging dentro del IRQ no crashea. La musica
    ; no suena en este commit (UpdateMusic tampoco se llama desde MainLoop).
    ; El refactor posterior movera la musica a slot 1 y reemplazara este
    ; bloque por una CALL directa al tick (sin paging).

    ; --- Restaurar paging desde la variable estatica ---
    LD A, (IrqSavedPaging)
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

.mihEpilogue:
    POP HL
    POP DE
    POP BC
    POP AF
    EI
    RET

; --- Estado del divisor (1 byte) ---
MusicIrqDivisor: DEFB 0
; --- Stash del paging anterior para que el handler pueda restaurarlo
; sin pasar por el stack (que vive en slot 3 y cambia de fisico al paginar). ---
IrqSavedPaging:  DEFB 0
