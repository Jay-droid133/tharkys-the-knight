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
;   2. Variables internas (BellVolL/C/R, BellDecayTimer, MusicPtr,
;      MusicTimer) no se leen/escriben desde fuera del modulo. Cuando
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
; SP alterno (slot 1) durante el page switch para no enmascarar IRQs. DI corto
; SOLO alrededor del Impl (que hace varios OUTs AY que deben ser atomicos
; respecto al handler IRQ que tambien escribe AY). Ver project_paging_alt_stack.
AY_UpdateBell:
    LD (.aubSavedSP), SP
    LD SP, PagingAltStackTop
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 4 (sin DI; SP alterno)
    DI                              ; cierra ventana antes de los OUTs AY del Impl
    CALL AY_UpdateBellImpl
    EI
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 (sin DI; SP alterno)
    LD SP, (.aubSavedSP)
    RET
.aubSavedSP: DEFW 0

; --- PrefetchMusic: rellena el buffer slot 1 desde EndGameMusicTable en bank 7 ---
; Llamado desde MainLoop al inicio del frame (slot 3 = bank 0 por invariante).
; Vive en bank 2 (slot 2 always-visible) en lugar de slot 1 porque slot 1 esta
; lleno y el unico hueco contiguo a music_irq ($7FC0-$8000) esta reservado para
; BankCutsceneAltStack via EQU — si poniamos el codigo ahi, los PUSH del
; alt-stack durante la cutscene M9 lo machacaban → crash a BASIC al volver a
; ejecutar PrefetchMusic.
;
; Patron critico: NO hace PUSH/POP/CALL mientras bank 7 esta paginado, solo
; OUT + LDIR (todos accesos a slot 1/bank 7 fisicos). Asi un IRQ entrante no
; corrompe nada: sus PUSH/POP a slot 3 = bank 7 RAM son balanceados y el
; handler IRQ (slot 1) no depende de bank 0.
;
; Restore hardcoded a bank 0: MainLoop invariante "slot 3 = bank 0 al inicio
; del frame". Si en el futuro el invariante cambia, salvar/restaurar via
; CurrentPaging shadow (cuesta ~10 B mas).
PrefetchMusic:
    LD A, (MusicNeedPrefetch)
    OR A
    RET Z                       ; no hay nada que prefetch
    XOR A
    LD (MusicNeedPrefetch), A   ; clear eagerly (idempotente si IRQ vuelve a setearla)
    ; --- Switch slot 3 -> bank 7 ---
    LD A, 7
    LD (CurrentPaging), A       ; update shadow
    LD BC, $7FFD
    OUT (C), A                  ; OUT bank 7
    ; --- LDIR 7 B de MusicBank7Ptr al buffer slot 1 ---
    LD HL, (MusicBank7Ptr)
    LD DE, MusicPrefetchBuf
    LD BC, 7
    LDIR
    LD (MusicBank7Ptr), HL      ; cursor avanzado (proxima entry)
    ; --- Switch slot 3 -> bank 0 (caller default) ---
    XOR A
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; --- AY_PlayBellChime: medianoche/iglesia, cold ---
; D = pan (-1=izq, 0=centro, +1=der). Preservar D atraviesa el thunk porque
; el patron page-switch no toca DE.
; SP alterno + DI corto solo en el Impl (mismo patron que AY_UpdateBell).
AY_PlayBellChime:
    LD (.apbcSavedSP), SP
    LD SP, PagingAltStackTop
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    DI
    CALL AY_PlayBellChimeImpl
    EI
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD SP, (.apbcSavedSP)
    RET
.apbcSavedSP: DEFW 0

; --- AY_OverrideBellPeriod: cambia el period de los 3 canales (A, B, C) ---
; HL = nuevo period (12-bit). Para octava arriba de la campana ($0258): HL=$012C.
; Para octava abajo: HL=$04B0. Direct port writes, no necesita paging.
; Llamar despues de AY_PlayBellChime para modificar la frecuencia de la chime
; en curso sin tocar la decay (que sigue gestionada por AY_UpdateBell).
AY_OverrideBellPeriod:
    DI
    ; R0 = period low (canal A)
    LD E, L
    LD A, 0
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    ; R1 = period high (canal A)
    LD E, H
    LD A, 1
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    ; R2/R3 (canal B)
    LD E, L
    LD A, 2
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    LD E, H
    LD A, 3
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    ; R4/R5 (canal C)
    LD E, L
    LD A, 4
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    LD E, H
    LD A, 5
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    EI
    RET

; --- AY_PlayToneBlocking: tono limpio en canal A, bloqueante ---
; HL = period (12-bit), B = duracion (10ms units).
; Self-contained en bank 2 (slot 2 fijo): no necesita page switch porque
; los I/O ports de la AY ($FFFD/$BFFD) son bank-agnostic. Asi evitamos
; el bug del stack viviendo en slot 3 (las PUSH/POP perderian el dato si
; cambiaramos de bank en slot 3 entre el push y el pop).
AY_PlayToneBlocking:
    DI
    ; --- Escribir registros AY directamente (sin pasar por AY_WriteReg en bank 4) ---
    ; R1 = period high (lo escribimos primero para no tener que stashear H)
    LD E, H                     ; E = period high
    LD A, 1
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    ; R0 = period low
    LD E, L                     ; E = period low
    LD A, 0
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    ; R9 = 0 (silenciar canal B por si campana dejo residuo)
    LD A, 9
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    XOR A
    OUT (C), A
    ; R10 = 0 (silenciar canal C)
    LD A, 10
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    XOR A
    OUT (C), A
    ; R7 = $3E (mixer: solo tono A activo)
    LD A, 7
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    LD A, $3E
    OUT (C), A
    ; R8 = 13 (volumen A alto)
    LD A, 8
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    LD A, 13
    OUT (C), A
    ; --- Busy loop B × ~12.4ms ---
.aypbOuter:
    LD HL, $0680                ; ~1664 inner iters
.aypbInner:
    DEC HL
    LD A, H
    OR L
    JR NZ, .aypbInner
    DJNZ .aypbOuter
    ; --- Silenciar canal A (volumen 0) ---
    LD A, 8
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    XOR A
    OUT (C), A
    EI
    RET

; --- StartMusic: dispatcher generico. A = track_id (0..3) ---
; Un solo thunk para todas las pistas: anadir tracks futuros = 0 bytes en bank 2.
; Track ids: 0=Tension, 1=Sunrise, 2=EndGame, 3=GameOver. Ids desconocidos = no-op.
;
; OJO: el track_id NO puede pasarse por registro a traves del page switch (el
; Impl en bank 4 no lo veria con seguridad si A se clobbea). Tampoco por PUSH/POP
; (stack vive en slot 3, el page switch corrompe el dato — ver
; project_ay_thunk_stack_bug.md). Lo pasamos via byte estatico en bank 2.
StartMusic:
    LD (MusicTrackArg), A
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    CALL StartMusicImpl
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    EI
    RET

; Stash del arg para el dispatcher. Vive en bank 2 (slot 2 fijo), accesible
; desde el Impl en bank 4 sin trampa de paging.
MusicTrackArg: DEFB 0

; Multiplicador de tempo del driver: 0=normal, 1=doble (SRL una vez la
; duracion de cada nota), 2=cuadruple. Aplicado en MusicAdvanceNote al
; cargar duration. StartMusicImpl lo resetea a 0 en cada arranque; el
; juego lo modifica para acelerar (p.ej. DeathGhostMode -> 1).
; Vive en bank 2 (always-visible) para que driver (bank 4) y juego
; (bank 0/2) puedan leer/escribir sin paging.
MusicSpeedShift: DEFB 0

; --- Catchup contra wall-clock (evita estiramiento de notas/decay tras
; transiciones de pantalla u otros frames lentos) ---
; MainLoop calcula al inicio de cada iteracion cuantos game frames (25fps =
; 2 ticks de IRQ a 50Hz) han pasado desde el iter anterior, y lo deja en
; FramesElapsed. UpdateMusic y AY_UpdateBell hacen N iteraciones segun ese
; valor (= "catchup completo": ritmo preservado en wall-clock).
; TickRemainder acumula la mitad-frame impar (1 tick) entre iteraciones para
; no perderla — sin esto un iter de 3 ticks daria 1 frame y un iter de 1
; tick daria 0, drift acumulando.
FramesElapsed:  DEFB 0          ; Frames de juego a avanzar este iter (0..N)
TickRemainder:  DEFB 0          ; Ticks de IRQ pendientes (0 o 1, mod 2)
