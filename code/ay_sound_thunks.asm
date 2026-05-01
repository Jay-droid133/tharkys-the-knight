; ==============================================================================
; ay_sound_thunks.asm - Bank 2 entry thunks para ay_sound.asm (vive en bank 4)
; ==============================================================================
; Las 5 funciones publicas de ay_sound.asm tienen aqui un thunk que paga bank 4
; en slot 3, CALLs el Impl, restaura bank 0, y RETurnea. Los thunks viven en
; bank 2 ($8000-$BFFF, slot 2) que es siempre visible — el page switch de
; slot 3 no mueve el suelo bajo nuestros pies.
;
; Por que ay_sound es seguro mover (a diferencia de town_gate_cutscene que
; fallo en el intento previo):
;   1. Self-contained: NO hace ningun CALL/JP a codigo fuera de ay_sound.asm.
;      Solo se llama a si mismo (AY_WriteReg, TmAdvanceNote). Cero
;      CALL_BANK0 internos, cero superficie de cross-bank.
;   2. Variables internas (BellVolL/C/R, BellDecayTimer, TensionMusicPtr,
;      TensionMusicTimer) no se leen/escriben desde fuera del modulo. Cuando
;      el Impl corre, bank 4 esta paginado → vars accesibles. Externamente
;      nadie las toca, asi que no hay corrupcion.
;
; Patron de cada thunk (pareja DI/EI con page switch):
;   - DI durante la ventana: el SP vive en slot 3 ($FF58); cambiar de bank
;     mientras una IRQ podria pushear/popear corromperia el stack.
;   - CALL <Impl>: pareja CALL/RET sucede con bank 4 paginado, asi que el
;     return addr pusheado sale del mismo bank 4 RAM al hacer RET.
;   - Tras el RET del Impl, restaura bank 0 (el bank "default" de MainLoop).
;   - EI antes del RET final: StartupComplete ya esta a 1 cuando se invocan
;     estos thunks (todos requieren el juego ya inicializado), excepto AY_Init
;     que se llama en boot — ahi DI sigue en efecto, EI seria prematuro.
;     Para AY_Init, hacemos EI condicional via StartupComplete.
; ==============================================================================

; --- AY_Init: solo en boot, requiere EI condicional via StartupComplete ---
AY_Init:
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL AY_InitImpl
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (StartupComplete)
    OR A
    RET Z                       ; aun en Inicio -> dejar DI
    EI
    RET

; --- AY_UpdateBell: cada frame ---
AY_UpdateBell:
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL AY_UpdateBellImpl
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    EI
    RET

; --- UpdateTensionMusic: cada frame ---
UpdateTensionMusic:
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL UpdateTensionMusicImpl
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    EI
    RET

; --- AY_PlayBellChime: medianoche/iglesia, cold ---
; D = pan (-1=izq, 0=centro, +1=der). Preservar D atraviesa el thunk porque
; el patron page-switch no toca DE.
AY_PlayBellChime:
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL AY_PlayBellChimeImpl
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    EI
    RET

; --- StartTensionMusic: cuando se dispara la fase de tension, cold ---
StartTensionMusic:
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL StartTensionMusicImpl
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    EI
    RET
