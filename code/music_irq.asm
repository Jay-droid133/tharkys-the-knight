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
;   3. Si toca tick: CALL UpdateMusicTick (en slot 1, sin paginar nada).
;   4. EI + RET.
;
; Atomicidad: el handler NO toca slot 3, asi que los PUSH/POP del propio
; handler operan sobre el mismo bank fisico de principio a fin —
; inmune al race con MainLoop que paga slots sin DI.
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

    ; --- Tick de musica + tick SFX (ambos viven en slot 1, siempre visibles). ---
    ; No paginamos nada: el handler queda atomico respecto a slot 3,
    ; eliminando el race con codigo de MainLoop que escribe CurrentPaging
    ; sin DI. SFX tickea aqui tambien (no desde MainLoop) para inmunizarse
    ; a la latencia de MainLoop (transiciones lentas estiraban el beep).
    CALL UpdateMusicTick
    CALL AY_UpdatePlayerHit

.mihEpilogue:
    POP HL
    POP DE
    POP BC
    POP AF
    EI
    RET

; --- Estado del divisor (1 byte) ---
MusicIrqDivisor: DEFB 0

; ==============================================================================
; MUSIC DRIVER STATE + TABLES + TICK (movido de bank 4 a slot 1)
; ==============================================================================
; Vive aqui porque el IRQ handler debe acceder a este codigo/datos sin paginar
; (paginar slot 3 dentro del IRQ rompe los PUSH/POP del propio handler — ver
; project_ay_thunk_stack_bug.md). Slot 1 = $6000-$7FFF siempre visible, asi
; que tanto el handler IRQ como StartMusicImpl (en bank 4) llegan aqui sin
; problemas: bank 4 paga slot 3, slot 1 sigue intacto.
;
; Tracks (mismo dispatcher que antes, vive en bank 4 / ay_sound.asm):
;   0    = Tension     (TensionMusicTable)
;   1    = Sunrise     (SunriseMusicTable)
;   2    = EndGame     (EndGameMusicTable)  LOOPABLE
;   3    = GameOver    (GameOverMusicTable)
;   4    = Death       (DeathMusicTable)    LOOPABLE
;   $FF  = STOP, $FE = restart, $FD = stop-if-loopable
; ==============================================================================

; --- State (8 B) ---
MusicPtr:           DEFW 0      ; Ptr a la nota actual en la tabla activa
MusicTimer:         DEFB 0      ; Frames restantes en la nota actual (0 = inactivo)
MusicTableStart:    DEFW 0      ; Ptr al inicio de la tabla activa (para loop)
MusicLoop:          DEFB 0      ; 1 = al terminator reiniciar; 0 = mute y parar
MusicCurrentPeriod: DEFW 0      ; Period activo (0 = rest o inactivo). Usado para
                                ; re-armar R2/R3 + R9 cada frame y recuperar la
                                ; musica tras un beep/sweep que clobbeo el canal B.

; ==============================================================================
; TRACK TABLES
; ==============================================================================
; Period AY = 1750000 / (16 * frequency). Duraciones en frames a 25fps (1f=40ms).
; Format por entry (3 B): period_lo, period_hi, duration. Terminator: $00,$00,$00.

; --- Track 0: TensionMusic ---
; 4 notas en registro grave de organo (A2 - C3 - A2 - D3, ~1.5s total).
TensionMusicTable:
    DEFW $03E2                      ; A2  ~110 Hz
    DEFB 9                          ; ~360ms
    DEFW $0344                      ; C3  ~131 Hz
    DEFB 9
    DEFW $03E2                      ; A2
    DEFB 9
    DEFW $02E9                      ; D3  ~147 Hz (climax mas alto)
    DEFB 11                         ; ~440ms sostenido
    DEFW 0
    DEFB 0                          ; fin

; --- Track 1: SunriseMusic ---
; Arpegio ascendente C major + resolucion, ~5s. Borrador inicial — iterar.
SunriseMusicTable:
    DEFW $0344                      ; C3  ~131 Hz
    DEFB 6
    DEFW $0297                      ; E3  ~165 Hz
    DEFB 6
    DEFW $022E                      ; G3  ~196 Hz
    DEFB 6
    DEFW $01A2                      ; C4  ~262 Hz
    DEFB 6
    DEFW $014C                      ; E4  ~330 Hz
    DEFB 12                         ; sostenido
    DEFW $01A2                      ; C4
    DEFB 6
    DEFW $022E                      ; G3
    DEFB 6
    DEFW $01A2                      ; C4
    DEFB 6
    DEFW $014C                      ; E4
    DEFB 6
    DEFW $0117                      ; G4  ~392 Hz climax
    DEFB 30                         ; ~1.2s final brillante
    DEFW 0
    DEFB 0

; --- Track 2: EndGameMusic ---
; Fanfarria de victoria, mayor, ~6s. Borrador inicial — iterar.
EndGameMusicTable:
    DEFW $022E                      ; G3
    DEFB 4                          ; corchea
    DEFW $022E                      ; G3
    DEFB 4
    DEFW $022E                      ; G3
    DEFB 4
    DEFW $01A2                      ; C4
    DEFB 12                         ; negra punteada
    DEFW $014C                      ; E4
    DEFB 8
    DEFW $01A2                      ; C4
    DEFB 4
    DEFW $014C                      ; E4
    DEFB 16                         ; blanca
    DEFW $0117                      ; G4
    DEFB 4
    DEFW $014C                      ; E4
    DEFB 4
    DEFW $01A2                      ; C4
    DEFB 4
    DEFW $0117                      ; G4
    DEFB 30                         ; final largo brillante
    DEFW 0
    DEFB 0

; --- Track 3: GameOverMusic ---
; Descenso menor, somber, ~2.5s. Borrador inicial — iterar.
GameOverMusicTable:
    DEFW $01F1                      ; A3  ~220 Hz
    DEFB 10
    DEFW $022E                      ; G3
    DEFB 10
    DEFW $0272                      ; F3
    DEFB 10
    DEFW $0297                      ; E3
    DEFB 10
    DEFW $02E9                      ; D3
    DEFB 12
    DEFW $0344                      ; C3 (resolucion grave)
    DEFB 24                         ; final sostenido ~960ms
    DEFW 0
    DEFB 0

; --- Track 4: DeathMusic (LOOPABLE) ---
; Tipo tiburon staccato: 2 notas graves alternadas. Cada beat = 12 frames
; (480ms): nota 6f sonando + 6f silencio. Tempo agil. 4 loops = 8 notas =
; 96 frames = 3.84s — sincronizado con DEATH_GHOST_FRAMES.
DeathMusicTable:
    DEFW $0536                      ; E2  ~82 Hz   (grave)
    DEFB 6                          ; ~240ms suena
    DEFW $0000                      ; REST
    DEFB 6                          ; ~240ms silencio
    DEFW $04E9                      ; F2  ~87 Hz   (semitone arriba)
    DEFB 6
    DEFW $0000                      ; REST
    DEFB 6
    DEFW 0
    DEFB 0                          ; terminator -> driver reinicia (MusicLoop=1)

; ==============================================================================
; AY_WriteRegSlot1 - copia de AY_WriteReg en slot 1
; ==============================================================================
; Necesaria porque desde el IRQ handler (slot 1) NO podemos llamar a la
; AY_WriteReg de bank 4: bank 4 puede no estar paginado en slot 3, y aunque
; lo estuviera, paginarlo desde el IRQ trae el race que estamos eliminando.
; Identica a AY_WriteReg (bank 4): A=registro, E=valor; clobbea BC y A.
; ==============================================================================
AY_WriteRegSlot1:
    LD BC, $FFFD
    OUT (C), A                      ; seleccionar registro
    LD BC, $BFFD
    OUT (C), E                      ; escribir valor
    RET

; ==============================================================================
; UpdateMusicTick - 1 tick + post-loop re-arm. Llamado desde el IRQ handler.
; ==============================================================================
; Atajo IRQ: hace exactamente UN tick y luego cae al re-arm. Comparte codigo
; con UpdateMusicImpl (ambos viven aqui en slot 1).
; ==============================================================================
UpdateMusicTick:
    CALL UpdateMusicImpl.upmiTickOnce
    JP UpdateMusicImpl.upmiPostLoop

; ==============================================================================
; UpdateMusicImpl - catchup wall-clock. LEGACY: ya no se llama desde MainLoop.
; ==============================================================================
; Mantenido por si en algun momento queremos tickear desde codigo (ej. para
; forzar avance N frames). UpdateMusicTick reusa .upmiTickOnce + .upmiPostLoop
; de aqui directamente.
; ==============================================================================
UpdateMusicImpl:
    LD A, (FramesElapsed)
    OR A
    JR Z, .upmiPostLoop
    LD B, A
.upmiLoop:
    PUSH BC
    CALL .upmiTickOnce
    POP BC
    DJNZ .upmiLoop
.upmiPostLoop:
    ; --- Re-arm AY si musica activa, sin SFX clobbeando canal B ---
    ; Tras un beep/sweep AY el cutoff mute R9. Sin esto la nota actual quedaba
    ; muda hasta el siguiente cambio de nota (hasta 1.2s con notas largas).
    ; Re-escribimos R9 + R2/R3 cada frame que la musica este activa, salvo:
    ;   - musica inactiva (MusicTimer=0)
    ;   - en rest (MusicCurrentPeriod=0)
    ;   - SFX canal B en curso (BeepDurationFrames o PlayerHitFrames > 0).
    LD A, (MusicTimer)
    OR A
    RET Z
    LD A, (MusicCurrentPeriod)
    LD B, A
    LD A, (MusicCurrentPeriod + 1)
    OR B
    RET Z
    LD A, (BeepDurationFrames)
    OR A
    RET NZ
    LD A, (PlayerHitFrames)
    OR A
    RET NZ
    ; Re-armar: R9 = vol, luego R2/R3 = period
    LD A, 9
    LD E, 12
    CALL AY_WriteRegSlot1
    LD HL, (MusicCurrentPeriod)
    LD E, L
    LD A, 2
    CALL AY_WriteRegSlot1
    LD A, 3
    LD E, H
    JP AY_WriteRegSlot1             ; tail-call

.upmiTickOnce:
    LD A, (MusicTimer)
    OR A
    RET Z                           ; inactivo
    DEC A
    LD (MusicTimer), A
    RET NZ                          ; aun en la nota actual
    ; Hora de la siguiente nota (fall-through a MusicAdvanceNote)

; ==============================================================================
; MusicAdvanceNote - lee 3 bytes de la tabla y aplica al AY.
; ==============================================================================
; Format de entry (3 B): period_lo, period_hi, duration.
; period=$0000, duration=$NN  -> rest (mute R8) durante NN frames
; period=$0000, duration=$00  -> terminador (silencia canal y para o reinicia)
;
; OJO: AY_WriteRegSlot1 clobbea B y C (LD BC, ports). Stashear period en D/E.
; ==============================================================================
MusicAdvanceNote:
    LD HL, (MusicPtr)
    LD E, (HL)                      ; E = pitch_lo
    INC HL
    LD D, (HL)                      ; D = pitch_hi
    INC HL
    LD A, (HL)                      ; duration
    INC HL
    OR A
    JR Z, .manEnd                   ; duration = 0 -> fin de tabla
    LD (MusicPtr), HL
    ; --- Aplicar MusicSpeedShift: SRL duration N veces (0=normal). Clamp a 1
    ; post-shift para que duration=0 siga indicando solo terminator. ---
    LD B, A                         ; B = duration original
    LD A, (MusicSpeedShift)
    OR A
    JR Z, .manSpeedDone
.manSpeedLoop:
    SRL B
    DEC A
    JR NZ, .manSpeedLoop
    LD A, B
    OR A
    JR NZ, .manSpeedDone            ; B>0 tras shift: ok
    LD B, 1                         ; underflow: clamp a 1 frame minimo
.manSpeedDone:
    LD A, B
    LD (MusicTimer), A
    ; ¿es rest? (period == 0 y duration != 0)
    LD A, E
    OR D
    JR Z, .manRest
    ; Nota normal: guardar period activo (para re-arm post-beep)
    ; + re-armar vol R9 (por si venimos de un rest que la mute) + escribir
    ; period en R2/R3 (canal B).
    LD (MusicCurrentPeriod), DE     ; ED 53 — guardar period activo
    PUSH DE
    LD A, 9
    LD E, 12
    CALL AY_WriteRegSlot1           ; R9 = vol B medio-alto
    POP DE
    LD A, 2                         ; R2 = period B low
    CALL AY_WriteRegSlot1           ; escribe E (pitch_lo); D preservado
    LD A, 3                         ; R3 = period B high
    LD E, D                         ; recargar E con pitch_hi
    JP AY_WriteRegSlot1             ; tail-call
.manRest:
    ; Silencio durante MusicTimer frames; el tick seguira llamando.
    ; Period activo = 0 -> el re-arm ignora rests (no escribe nada).
    LD HL, 0
    LD (MusicCurrentPeriod), HL
    LD A, 9
    LD E, 0
    JP AY_WriteRegSlot1             ; tail-call (mute R9)
.manEnd:
    ; Terminator: si la pista es loopable, reiniciar; si no, silenciar y parar.
    LD A, (MusicLoop)
    OR A
    JR Z, .manEndStop
    ; Loop: restaurar MusicPtr al inicio de la tabla y leer la primera nota.
    LD HL, (MusicTableStart)
    LD (MusicPtr), HL
    JP MusicAdvanceNote             ; reentrar al primer nota (no-recursivo: solo lee 3B)
.manEndStop:
    XOR A
    LD (MusicTimer), A              ; flag inactivo
    LD H, A
    LD L, A
    LD (MusicCurrentPeriod), HL     ; clear period guardado (no re-arm)
    LD A, 9
    LD E, 0
    JP AY_WriteRegSlot1             ; tail-call
