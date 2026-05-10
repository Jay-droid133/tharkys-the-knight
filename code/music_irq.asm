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

    ; --- Tick SFX + MUSICA (slot 1, siempre visible). ---
    ; SFX countdown (Beep, PlayerHit) tickea aqui para inmunizar la duracion
    ; al wall-clock (commit 1759338: "TIC del compass no se estira en
    ; transiciones").
    ;
    ; La MUSICA tambien tickea aqui (avance de nota + re-arm AY). Asi el ritmo
    ; sigue exacto durante DrawScreen/transiciones de pantalla, donde MainLoop
    ; queda bloqueado varios frames y antes la nota actual se "alargaba" hasta
    ; que MainLoop volvia y hacia catchup.
    ;
    ; Concurrencia AY: TODAS las escrituras al AY desde MainLoop estan
    ; envueltas en DI/EI (auditoria en ay_sound_thunks.asm + sfx_player_hit_ay
    ; .asm). Por tanto el handler IRQ nunca cae a media secuencia
    ; select($FFFD)+data($BFFD) y no corrompe el index del AY.
    ;
    ; Inline tick: equivale a CALL UpdateMusicTick pero ahorra el stub (-3 B).
    CALL AY_UpdatePlayerHit
    CALL UpdateMusicImpl.upmiTickOnce
    CALL UpdateMusicImpl.upmiPostLoop
    CALL BellTickIrq                ; decay de la campana (movido aqui desde
                                    ; bank 4 para no perderse en transiciones)

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

; --- State (13 B) ---
; Driver poly: tracks in-game (Tension/Sunrise/Death) usan poly2 (canales A+C,
; B reservado a SFX). Tracks game-end (EndGame/GameOver) usan poly3 (A+B+C, sin
; SFX en escena). El modo se setea en StartMusicImpl segun track id; dicta el
; stride de tabla (5 vs 7 B/nota) y qué canales re-armar cada frame.
MusicPtr:           DEFW 0      ; Ptr a la nota actual en la tabla activa
MusicTimer:         DEFB 0      ; Frames restantes en la nota actual (0 = inactivo)
MusicTableStart:    DEFW 0      ; Ptr al inicio de la tabla activa (para loop)
MusicLoop:          DEFB 0      ; 1 = al terminator reiniciar; 0 = mute y parar
MusicMode:          DEFB 0      ; 2 = poly2 (5 B/entry, A+C), 3 = poly3 (7 B/entry, A+B+C)
MusicPeriodA:       DEFW 0      ; Period activo canal A (0 = mute A en re-arm)
MusicPeriodB:       DEFW 0      ; Period activo canal B (solo poly3; 0 = mute)
MusicPeriodC:       DEFW 0      ; Period activo canal C (0 = mute C en re-arm)

; ==============================================================================
; TRACK TABLES (polifonicas)
; ==============================================================================
; Period AY = 1750000 / (16 * frequency). Duraciones en frames a 25fps (1f=40ms).
;
; Formato Poly2 (5 B/entry): periodA(2) + periodC(2) + duration(1)
;   Tracks 0/1/4 (Tension/Sunrise/Death). Canal B libre para SFX.
; Formato Poly3 (7 B/entry): periodA(2) + periodB(2) + periodC(2) + duration(1)
;   Tracks 2/3 (EndGame/GameOver). Sin SFX en escena → 3 voces simultaneas.
;
; period=$0000 en un canal = ese canal en silencio durante la nota (vol mute).
; Terminator: entry completa con todo a 0 (5 B en poly2, 7 B en poly3).
;
; Por ahora todas las melodias siguen monofonicas (voz original en A, B/C en
; silencio) hasta que el converter genere las versiones polifonicas reales.
; ==============================================================================

; --- Track 0: TensionMusic (poly2, A=C duplicado mientras no haya converter) ---
; Generado por tools/music_converter.html desde music/tension.mid
; 5 notas (C3 D3 D#3 C3 F#3), ~3.24s @ 25fps. Bajada una octava (period x2)
; respecto al MIDI original para registro mas grave/atmosferico.
; A y C tocan la misma nota → mono dual estéreo (ambos altavoces).
TensionMusicTable:
    DEFW $0344 : DEFW $0344 : DEFB 21   ; A+C=C3
    DEFW $02E8 : DEFW $02E8 : DEFB  4   ; A+C=D3
    DEFW $02C0 : DEFW $02C0 : DEFB 13   ; A+C=D#3
    DEFW $0344 : DEFW $0344 : DEFB 12   ; A+C=C3
    DEFW $0250 : DEFW $0250 : DEFB 31   ; A+C=F#3
    DEFW 0     : DEFW 0     : DEFB  0   ; fin

; --- Track 1: SunriseMusic (poly2, A=C duplicado mientras no haya converter) ---
; Generado por tools/music_converter.html desde music/amanecer.mid (Mono),
; traducido a Poly2 duplicando period en A y C. Gate < 100% para acortar la
; cola de cada nota y evitar que se solapen entre transiciones de pantalla.
; 51 entries (notas + rests), ~11.24s @ 25fps.
SunriseMusicTable:
    DEFW $0117 : DEFW $0117 : DEFB   7   ; A+C=G4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $014C : DEFW $014C : DEFB   7   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $0174 : DEFW $0174 : DEFB   7   ; A+C=D4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $01A2 : DEFW $01A2 : DEFB   7   ; A+C=C4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $0174 : DEFW $0174 : DEFB   7   ; A+C=D4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $014C : DEFW $014C : DEFB   6   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   4   ; REST
    DEFW $0139 : DEFW $0139 : DEFB   1   ; A+C=F4
    DEFW $0000 : DEFW $0000 : DEFB   2   ; REST
    DEFW $0117 : DEFW $0117 : DEFB   7   ; A+C=G4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $014C : DEFW $014C : DEFB   6   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $0174 : DEFW $0174 : DEFB   7   ; A+C=D4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $01A2 : DEFW $01A2 : DEFB   7   ; A+C=C4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $0174 : DEFW $0174 : DEFB   4   ; A+C=D4
    DEFW $0000 : DEFW $0000 : DEFB   3   ; REST
    DEFW $014C : DEFW $014C : DEFB   3   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   3   ; REST
    DEFW $0174 : DEFW $0174 : DEFB   3   ; A+C=D4
    DEFW $0000 : DEFW $0000 : DEFB   3   ; REST
    DEFW $014C : DEFW $014C : DEFB   3   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   3   ; REST
    DEFW $0139 : DEFW $0139 : DEFB   1   ; A+C=F4
    DEFW $0000 : DEFW $0000 : DEFB   1   ; REST
    DEFW $0117 : DEFW $0117 : DEFB   6   ; A+C=G4
    DEFW $0000 : DEFW $0000 : DEFB   4   ; REST
    DEFW $014C : DEFW $014C : DEFB   7   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $0117 : DEFW $0117 : DEFB   7   ; A+C=G4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $00F9 : DEFW $00F9 : DEFB   7   ; A+C=A4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $014C : DEFW $014C : DEFB   7   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $00F9 : DEFW $00F9 : DEFB   7   ; A+C=A4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $0117 : DEFW $0117 : DEFB   7   ; A+C=G4
    DEFW $0000 : DEFW $0000 : DEFB   5   ; REST
    DEFW $014C : DEFW $014C : DEFB   7   ; A+C=E4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $0174 : DEFW $0174 : DEFB   7   ; A+C=D4
    DEFW $0000 : DEFW $0000 : DEFB   6   ; REST
    DEFW $01A2 : DEFW $01A2 : DEFB  19   ; A+C=C4
    DEFW 0     : DEFW 0     : DEFB   0   ; fin

; --- Track 2: EndGameMusic (poly3, voz en A) ---
; Fanfarria de victoria, mayor, ~6s. Borrador inicial — iterar via converter.
EndGameMusicTable:
    DEFW $022E : DEFW 0 : DEFW 0 : DEFB  4    ; A=G3
    DEFW $022E : DEFW 0 : DEFW 0 : DEFB  4    ; A=G3
    DEFW $022E : DEFW 0 : DEFW 0 : DEFB  4    ; A=G3
    DEFW $01A2 : DEFW 0 : DEFW 0 : DEFB 12    ; A=C4 (negra punteada)
    DEFW $014C : DEFW 0 : DEFW 0 : DEFB  8    ; A=E4
    DEFW $01A2 : DEFW 0 : DEFW 0 : DEFB  4    ; A=C4
    DEFW $014C : DEFW 0 : DEFW 0 : DEFB 16    ; A=E4 (blanca)
    DEFW $0117 : DEFW 0 : DEFW 0 : DEFB  4    ; A=G4
    DEFW $014C : DEFW 0 : DEFW 0 : DEFB  4    ; A=E4
    DEFW $01A2 : DEFW 0 : DEFW 0 : DEFB  4    ; A=C4
    DEFW $0117 : DEFW 0 : DEFW 0 : DEFB 30    ; A=G4 (final largo)
    DEFW 0     : DEFW 0 : DEFW 0 : DEFB  0    ; fin

; --- Track 3: GameOverMusic (poly3, voz en A) ---
; Descenso menor, somber, ~2.5s. Borrador inicial — iterar via converter.
GameOverMusicTable:
    DEFW $01F1 : DEFW 0 : DEFW 0 : DEFB 10    ; A=A3
    DEFW $022E : DEFW 0 : DEFW 0 : DEFB 10    ; A=G3
    DEFW $0272 : DEFW 0 : DEFW 0 : DEFB 10    ; A=F3
    DEFW $0297 : DEFW 0 : DEFW 0 : DEFB 10    ; A=E3
    DEFW $02E9 : DEFW 0 : DEFW 0 : DEFB 12    ; A=D3
    DEFW $0344 : DEFW 0 : DEFW 0 : DEFB 24    ; A=C3 (resolucion grave)
    DEFW 0     : DEFW 0 : DEFW 0 : DEFB  0    ; fin

; --- Track 4: DeathMusic (poly2, LOOPABLE, A=C duplicado mientras no haya converter) ---
; Originalmente A2-C3-B2-C3 (~1.92s/loop @ 25fps). Transpuesto -9 semitonos
; para alinear la 1a nota con la nota grave de MonstersMusic (C2 = $0688):
; melodia ahora en C2-D#2-D2-D#2 manteniendo los intervalos originales (+3,
; -1, +1) -> continuidad timbrica entre el "po-po-popo-po" de la noche y la
; muerte del player.
; NOTA: el rest final (7f) lo añado a mano — el converter lo trunca al
; emitir end-of-track. Los 3 anteriores son 7,6,7 → uso moda=7f.
DeathMusicTable:
    DEFW $0688 : DEFW $0688 : DEFB  6   ; A+C=C2  (era A2)
    DEFW 0     : DEFW 0     : DEFB  7   ; REST
    DEFW $057E : DEFW $057E : DEFB  6   ; A+C=D#2 (era C3)
    DEFW 0     : DEFW 0     : DEFB  6   ; REST
    DEFW $05D2 : DEFW $05D2 : DEFB  6   ; A+C=D2  (era B2)
    DEFW 0     : DEFW 0     : DEFB  7   ; REST
    DEFW $057E : DEFW $057E : DEFB  6   ; A+C=D#2 (era C3)
    DEFW 0     : DEFW 0     : DEFB  7   ; REST (manual fix)
    DEFW 0     : DEFW 0     : DEFB  0   ; terminator -> driver reinicia (MusicLoop=1)

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
; UpdateMusicImpl - catchup wall-clock. LEGACY: ya no se llama desde MainLoop.
; ==============================================================================
; Hoy el tick vive en MusicIrqHandler (CALL .upmiTickOnce + CALL .upmiPostLoop
; cada 2 IRQs). Esta rutina catchup se mantiene como fallback por si alguna
; vez queremos forzar avance N frames desde codigo.
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
    ; --- Re-arm AY si musica activa ---
    ; Sin esto, la nota actual queda muda tras (a) cualquier write a R8/R9/R10
    ; que la mute, o (b) tras pasar por un rest. Re-escribimos vol + period de
    ; cada canal con period activo != 0. SFX en canal B (poly2 only) bloquean
    ; el re-arm de B; en poly3 no hay SFX activos (game-end), siempre re-armar.
    LD A, (MusicTimer)
    OR A
    RET Z                           ; musica inactiva → no tocar AY
    ; --- Re-arm canal A: R0/R1 + R8 si MusicPeriodA != 0 ---
    LD HL, (MusicPeriodA)
    LD A, H
    OR L
    JR Z, .upmiSkipA
    PUSH HL
    LD A, 8
    LD E, 12
    CALL AY_WriteRegSlot1           ; R8 = vol A medio-alto
    POP HL
    LD E, L
    LD A, 0
    CALL AY_WriteRegSlot1           ; R0 = period A lo
    LD HL, (MusicPeriodA)
    LD E, H
    LD A, 1
    CALL AY_WriteRegSlot1           ; R1 = period A hi
.upmiSkipA:
    ; --- Re-arm canal C: R4/R5 + R10 si MusicPeriodC != 0 ---
    LD HL, (MusicPeriodC)
    LD A, H
    OR L
    JR Z, .upmiSkipC
    PUSH HL
    LD A, 10
    LD E, 12
    CALL AY_WriteRegSlot1           ; R10 = vol C medio-alto
    POP HL
    LD E, L
    LD A, 4
    CALL AY_WriteRegSlot1           ; R4 = period C lo
    LD HL, (MusicPeriodC)
    LD E, H
    LD A, 5
    CALL AY_WriteRegSlot1           ; R5 = period C hi
.upmiSkipC:
    ; --- Re-arm canal B: solo en poly3 y solo si no hay SFX en curso ---
    LD A, (MusicMode)
    CP 3
    RET NZ                          ; poly2: B reservado a SFX, no tocar
    LD A, (BeepDurationFrames)
    OR A
    RET NZ
    LD A, (PlayerHitFrames)
    OR A
    RET NZ
    LD HL, (MusicPeriodB)
    LD A, H
    OR L
    RET Z
    PUSH HL
    LD A, 9
    LD E, 12
    CALL AY_WriteRegSlot1           ; R9 = vol B medio-alto
    POP HL
    LD E, L
    LD A, 2
    CALL AY_WriteRegSlot1           ; R2 = period B lo
    LD HL, (MusicPeriodB)
    LD E, H
    LD A, 3
    JP AY_WriteRegSlot1             ; tail-call: R3 = period B hi

.upmiTickOnce:
    LD A, (MusicTimer)
    OR A
    RET Z                           ; inactivo
    DEC A
    LD (MusicTimer), A
    RET NZ                          ; aun en la nota actual
    ; Hora de la siguiente nota (fall-through a MusicAdvanceNote)

; ==============================================================================
; MusicAdvanceNote - lee siguiente nota y aplica al AY. Despacha por MusicMode.
; ==============================================================================
; Poly2 entry (5 B): periodA(2) + periodC(2) + duration(1)
; Poly3 entry (7 B): periodA(2) + periodB(2) + periodC(2) + duration(1)
; period=$0000 en un canal = mute (vol=0) durante esa nota.
; duration=$00 (con todos los periods=0) = terminator → loop o stop.
; ==============================================================================
MusicAdvanceNote:
    LD A, (MusicMode)
    CP 3
    JR Z, MusicAdvancePoly3
    ; fall-through a MusicAdvancePoly2

; --- Poly2 (5 B/entry): periodA, periodC, duration -----------------------------
MusicAdvancePoly2:
    LD HL, (MusicPtr)
    ; Leer periodA (HL+0..1)
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD (MusicPeriodA), DE
    ; Leer periodC (HL+2..3) y guardarlo via BC para no clobbearlo
    LD C, (HL)
    INC HL
    LD B, (HL)
    INC HL
    LD (MusicPeriodC), BC
    ; Duration (HL+4)
    LD A, (HL)
    INC HL
    OR A
    JR Z, .map2End                  ; duration=0 → terminator
    LD (MusicPtr), HL
    CALL ApplyMusicSpeedShift       ; A in/out: A = duration ajustada
    LD (MusicTimer), A
    ; --- Aplicar canal A: si period != 0 escribir R0/R1 + R8=vol; si =0, R8=0 ---
    LD HL, (MusicPeriodA)
    LD A, H
    OR L
    JR NZ, .map2NoteA
    LD A, 8
    LD E, 0
    CALL AY_WriteRegSlot1           ; mute A
    JR .map2DoC
.map2NoteA:
    PUSH HL
    LD A, 8
    LD E, 12
    CALL AY_WriteRegSlot1           ; R8 = vol A
    POP HL
    LD E, L
    LD A, 0
    CALL AY_WriteRegSlot1           ; R0
    LD HL, (MusicPeriodA)
    LD E, H
    LD A, 1
    CALL AY_WriteRegSlot1           ; R1
.map2DoC:
    ; --- Aplicar canal C: igual logica con R4/R5 + R10 ---
    LD HL, (MusicPeriodC)
    LD A, H
    OR L
    JR NZ, .map2NoteC
    LD A, 10
    LD E, 0
    JP AY_WriteRegSlot1             ; tail-call: mute C
.map2NoteC:
    PUSH HL
    LD A, 10
    LD E, 12
    CALL AY_WriteRegSlot1           ; R10 = vol C
    POP HL
    LD E, L
    LD A, 4
    CALL AY_WriteRegSlot1           ; R4
    LD HL, (MusicPeriodC)
    LD E, H
    LD A, 5
    JP AY_WriteRegSlot1             ; tail-call: R5
.map2End:
    JP MusicEndOfTable

; --- Poly3 (7 B/entry): periodA, periodB, periodC, duration --------------------
MusicAdvancePoly3:
    LD HL, (MusicPtr)
    ; periodA
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD (MusicPeriodA), DE
    ; periodB
    LD C, (HL)
    INC HL
    LD B, (HL)
    INC HL
    LD (MusicPeriodB), BC
    ; periodC
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD (MusicPeriodC), DE
    ; duration
    LD A, (HL)
    INC HL
    OR A
    JR Z, .map3End
    LD (MusicPtr), HL
    CALL ApplyMusicSpeedShift
    LD (MusicTimer), A
    ; --- Canal A: R0/R1 + R8 ---
    LD HL, (MusicPeriodA)
    LD A, H
    OR L
    JR NZ, .map3NoteA
    LD A, 8
    LD E, 0
    CALL AY_WriteRegSlot1
    JR .map3DoB
.map3NoteA:
    PUSH HL
    LD A, 8
    LD E, 12
    CALL AY_WriteRegSlot1
    POP HL
    LD E, L
    LD A, 0
    CALL AY_WriteRegSlot1
    LD HL, (MusicPeriodA)
    LD E, H
    LD A, 1
    CALL AY_WriteRegSlot1
.map3DoB:
    ; --- Canal B: R2/R3 + R9 ---
    LD HL, (MusicPeriodB)
    LD A, H
    OR L
    JR NZ, .map3NoteB
    LD A, 9
    LD E, 0
    CALL AY_WriteRegSlot1
    JR .map3DoC
.map3NoteB:
    PUSH HL
    LD A, 9
    LD E, 12
    CALL AY_WriteRegSlot1
    POP HL
    LD E, L
    LD A, 2
    CALL AY_WriteRegSlot1
    LD HL, (MusicPeriodB)
    LD E, H
    LD A, 3
    CALL AY_WriteRegSlot1
.map3DoC:
    ; --- Canal C: R4/R5 + R10 ---
    LD HL, (MusicPeriodC)
    LD A, H
    OR L
    JR NZ, .map3NoteC
    LD A, 10
    LD E, 0
    JP AY_WriteRegSlot1             ; tail-call
.map3NoteC:
    PUSH HL
    LD A, 10
    LD E, 12
    CALL AY_WriteRegSlot1
    POP HL
    LD E, L
    LD A, 4
    CALL AY_WriteRegSlot1
    LD HL, (MusicPeriodC)
    LD E, H
    LD A, 5
    JP AY_WriteRegSlot1             ; tail-call
.map3End:
    JP MusicEndOfTable

; --- ApplyMusicSpeedShift: A=duration in/out. SRL N veces, clamp a 1 ----------
; MusicSpeedShift = 0 → no-op. Mantiene el comportamiento "tempo / 2^N".
ApplyMusicSpeedShift:
    LD B, A
    LD A, (MusicSpeedShift)
    OR A
    LD A, B
    RET Z
    LD A, (MusicSpeedShift)
.amssLoop:
    SRL B
    DEC A
    JR NZ, .amssLoop
    LD A, B
    OR A
    RET NZ
    LD A, 1                         ; underflow → 1 frame minimo
    RET

; --- MusicEndOfTable: terminator. Loop o stop ---------------------------------
MusicEndOfTable:
    LD A, (MusicLoop)
    OR A
    JR Z, .meotStop
    LD HL, (MusicTableStart)
    LD (MusicPtr), HL
    JP MusicAdvanceNote             ; reentrar (no-recursivo: solo lee 1 nota)
.meotStop:
    XOR A
    LD (MusicTimer), A
    LD H, A
    LD L, A
    LD (MusicPeriodA), HL
    LD (MusicPeriodB), HL
    LD (MusicPeriodC), HL
    ; Mute los 3 canales (poly3 puede tener B activo; poly2 solo A/C)
    LD A, 8
    LD E, 0
    CALL AY_WriteRegSlot1           ; R8 = 0
    LD A, 10
    LD E, 0
    CALL AY_WriteRegSlot1           ; R10 = 0
    LD A, (MusicMode)
    CP 3
    RET NZ
    LD A, 9
    LD E, 0
    JP AY_WriteRegSlot1             ; R9 = 0 (solo poly3)

; ==============================================================================
; BELL DECAY (movido desde ay_sound.asm bank 4)
; ==============================================================================
; Variables del decay manual de la campana (con pan estereo):
;   BellVolL/C/R: volumen actual de cada canal (0-15). Set por
;     AY_PlayBellChimeImpl (bank 4); decae aqui cada N frames.
;   BellDecayTimer: frames hasta el siguiente decremento.
; Cuando los 3 vols son 0, la campana esta silenciada (RET Z en BellTickIrq).
;
; BellTickIrq: llamado desde MusicIrqHandler cada 25 Hz (cada 2 IRQs). Es
; equivalente al .aubTickOnce de bank 4 pero usa AY_WriteRegSlot1 (visible
; desde el handler IRQ sin paginar).
; ==============================================================================
BellVolL:        DEFB 0
BellVolC:        DEFB 0
BellVolR:        DEFB 0
BellDecayTimer:  DEFB 0

BELL_DECAY_RATE EQU 2               ; 2 frames a 25fps (cada 2 ticks IRQ)

BellTickIrq:
    ; ¿alguno de los 3 canales aun suena?
    LD A, (BellVolL)
    LD B, A
    LD A, (BellVolC)
    OR B
    LD B, A
    LD A, (BellVolR)
    OR B
    RET Z                           ; los 3 a 0 -> silenciada

    LD HL, BellDecayTimer
    DEC (HL)
    RET NZ                          ; aun no toca decrementar

    LD A, BELL_DECAY_RATE
    LD (BellDecayTimer), A

    ; Decrementar canal A (R8) si > 0
    LD A, (BellVolL)
    OR A
    JR Z, .btiSkipA
    DEC A
    LD (BellVolL), A
    LD E, A
    LD A, 8
    CALL AY_WriteRegSlot1
.btiSkipA:
    ; Decrementar canal B (R9) si > 0
    LD A, (BellVolC)
    OR A
    JR Z, .btiSkipB
    DEC A
    LD (BellVolC), A
    LD E, A
    LD A, 9
    CALL AY_WriteRegSlot1
.btiSkipB:
    ; Decrementar canal C (R10) si > 0
    LD A, (BellVolR)
    OR A
    RET Z
    DEC A
    LD (BellVolR), A
    LD E, A
    LD A, 10
    JP AY_WriteRegSlot1             ; tail call
