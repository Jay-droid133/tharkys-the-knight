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

; ==============================================================================
; DRUM SEQUENCER (pitch sweep en canal tone B, paralelo a la música)
; ==============================================================================
; Aprovecha el gap libre entre el final del INCLUDE previo (minimap_timed
; termina en $78C0) y el ORG $7A00 de la IM2 table.
;
; Hoy lo usa solo GameOver: 4 hits por loop en los offbeats 1.& y 3.& de cada
; bar. Cada hit dispara un TONE descendente rápido en canal B — el clásico
; "whomp" de drum machines tempranas. Inicia agudo (~A5 = 855 Hz) y baja a
; ~F3 (~125 Hz) en 5 frames (200 ms), terminando bajo la voz de la melodía.
;
; Estado:
;   DrumEnabled=0  → RET inmediato.
;   DrumHitTimer>0 → sostén/sweep en curso. Cada frame: period += STEP, escribe
;                    R2/R3 + refresh R9=15. Al llegar a 0: mute R9.
;   DrumLoopFrame == (DrumCursor).frame → trigger: init period inicial,
;                    escribe R2/R3 + R9=15, set timer.
;
; Por qué NO compite con la música:
; - GameOver tiene periodB=$0000 en toda la tabla (REST en la voz B), así que
;   el music advance solo escribe R9=0 cuando lee una nueva nota (no toca
;   R2/R3). Refrescamos R9=15 cada frame del hit para anular ese mute.
; - upmiPostLoop solo re-arms R2/R3 si periodB!=0; nunca lo hace en GameOver.
; - El mixer R7 queda en $38 (default AY_Init: tonos ABC enable, ruidos off);
;   NO lo tocamos.
;
; Destruye: AF, BC, HL, E. Llamado desde IRQ handler que ya hizo PUSH AF/BC/
; DE/HL — clobber libre.
; ==============================================================================
DrumTickIrq:
    LD A, (DrumEnabled)
    OR A
    RET Z

    ; --- Sostén/sweep del hit en curso ---
    LD A, (DrumHitTimer)
    OR A
    JR Z, .dtiNoHit
    DEC A
    LD (DrumHitTimer), A
    JR Z, .dtiHitEnd
    ; Sweep: DrumKickPeriod += STEP, escribe R2/R3
    LD HL, (DrumKickPeriod)
    LD BC, DRUM_SWEEP_STEP
    ADD HL, BC
    LD (DrumKickPeriod), HL
    LD E, L
    LD A, 2
    CALL AY_WriteRegSlot1           ; R2 = period lo (más grave)
    LD HL, (DrumKickPeriod)
    LD E, H
    LD A, 3
    CALL AY_WriteRegSlot1           ; R3 = period hi
    ; Refresh R9=15: protección contra music advance que pone B a 0
    LD A, 9
    LD E, 15
    CALL AY_WriteRegSlot1
    JR .dtiCheckTrigger
.dtiHitEnd:
    LD A, 9
    LD E, 0
    CALL AY_WriteRegSlot1
.dtiNoHit:

.dtiCheckTrigger:
    LD HL, (DrumCursor)
    LD A, (HL)
    CP $FF
    JR Z, .dtiAdvanceFrame          ; tabla agotada → solo contar
    LD B, A                         ; B = frame trigger
    LD A, (DrumLoopFrame)
    CP B
    JR NZ, .dtiAdvanceFrame
    ; --- ¡Hit! Init sweep: period = START + escribe R2/R3 + R9=15 ---
    INC HL
    LD A, (HL)                      ; duration
    LD (DrumHitTimer), A
    INC HL
    LD (DrumCursor), HL
    LD HL, DRUM_SWEEP_START
    LD (DrumKickPeriod), HL
    LD E, L
    LD A, 2
    CALL AY_WriteRegSlot1
    LD HL, (DrumKickPeriod)
    LD E, H
    LD A, 3
    CALL AY_WriteRegSlot1
    LD A, 9
    LD E, 15
    CALL AY_WriteRegSlot1
.dtiAdvanceFrame:
    LD A, (DrumLoopFrame)
    INC A
    CP GAMEOVER_LOOP_FRAMES
    JR NZ, .dtiSaveFrame
    XOR A
.dtiSaveFrame:
    LD (DrumLoopFrame), A
    RET

; ==============================================================================
; ResetDrumLoop - reset al loop restart del bank-7 track (.meotLoopBank7)
; ==============================================================================
; Gate interno: caller llama sin chequear DrumEnabled. Destruye AF, HL.
; ==============================================================================
ResetDrumLoop:
    LD A, (DrumEnabled)
    OR A
    RET Z
    LD HL, GameOverDrumTable
    LD (DrumCursor), HL
    XOR A
    LD (DrumLoopFrame), A
    LD (DrumHitTimer), A
    RET

; --- Vector table (257 bytes all $7B) ---
; Cualquier byte del data bus da vector = $7B7B (Im2Vector).
; Globales en vez de locales para que el scope no cuelgue de la ultima
; etiqueta del INCLUDE previo (trampa de sjasmplus, ver memoria
; project_sjasmplus_local_scope).
    ORG $7A00
Im2Table:
    DEFS 257, $7B                       ; $7A00-$7B00 inclusive

; --- Vector target: JP MusicIrqHandler ---
    ORG $7B7B
Im2Vector:
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
    ; Gate global: AySilenced=1 pausa AY (música + SFX + bell) sin perder
    ; state del driver. Usado por pantallas modales (minimap) — al ResumeAy
    ; cada componente continúa donde quedó.
    LD A, (AySilenced)
    OR A
    JR NZ, .mihEpilogue

    ; Inline tick: equivale a CALL UpdateMusicTick pero ahorra el stub (-3 B).
    CALL AY_UpdateSFX               ; sistema data-driven (sfx_interp.asm).
                                    ; AY_UpdatePlayerHit legacy eliminado Fase 5c
                                    ; (no quedaban callers tras la migracion).
    CALL UpdateMusicImpl.upmiTickOnce
    CALL UpdateMusicImpl.upmiPostLoop
    CALL BellTickIrq                ; decay de la campana (movido aqui desde
                                    ; bank 4 para no perderse en transiciones)
    CALL DrumTickIrq                ; drum sequencer (sweep tonal canal B,
                                    ; solo GameOver). DESPUÉS del music tick
                                    ; para refrescar R9=15 si advance lo bajó.

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
AySilenced:         DEFB 0      ; 1 = MusicIrqHandler skipea AY_UpdateSFX +
                                ;     ticks de música + bell. Usado por pantallas
                                ;     modales (minimap). Driver y SFX preservan
                                ;     state; al ResumeAy continúan donde estaban.
MusicChannelVol:    DEFB 12     ; volumen por nota en canales activos (0..15).
                                ; Default 12 = ~75% AY. EndGame lo sube a 14 al
                                ; armarse para destacar sobre los SFX del juego.
                                ; Otros tracks lo resetean a 12 al armarse.
MusicEnded:         DEFB 0      ; Flag set por .meotStop al consumir terminator
                                ; de una pista no-loopable. Cleared por
                                ; StartMusicImpl al armar pista nueva. Usado por
                                ; Inicio (boot path) para esperar a que el jingle
                                ; StartGame termine antes de cerrar el splash.

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

; --- Track 2: EndGameMusic ---
; Tabla movida a bank 7 (code/music_endgame_bank7.asm) — 1078 B no caben en
; slot 1. Acceso via prefetch: MainLoop pagina bank 7 + LDIR 7 B al buffer en
; slot 1; el IRQ tick consume desde el buffer reseteando MusicPtr en cada
; advance. Las otras 4 tracks (Tension/Sunrise/GameOver/Death) siguen en
; slot 1 (cortas, no necesitan paginacion).
;
; Bytes en slot 1 para este sistema: 14 (state) + 1 (scratch) = 15 B.
; Ahorro neto: 1085 (poly3 raw) - 15 (state) - ~110 (codigo prefetch) = ~960 B
; libres en slot 1 vs tener la tabla aqui. Margen suficiente para futuras
; canciones del mismo orden de magnitud sin volver a tocar la arquitectura.
MusicTrackInBank7:  DEFB 0      ; 1 = la track activa vive en bank 7 (= track 2 hoy)
MusicNeedPrefetch:  DEFB 0      ; 1 = el buffer fue consumido; MainLoop debe rellenar
MusicBank7Ptr:      DEFW 0      ; cursor en bank 7 (apunta a la PROXIMA entry no leida)
MusicPrefetchBuf:   DEFS 7, 0   ; entry copiada (max 7 B = poly3). MusicPtr -> aqui

; ==============================================================================
; DRUM SEQUENCER STATE + DATA (rutinas al inicio del archivo, antes del ORG)
; ==============================================================================
DrumEnabled:        DEFB 0      ; 1 = drum sequencer activo (set por StartMusic)
DrumCursor:         DEFW 0      ; ptr a la próxima entry de la tabla activa
DrumLoopFrame:      DEFB 0      ; frame actual dentro del loop (0..GAMEOVER_LOOP_FRAMES-1)
DrumHitTimer:       DEFB 0      ; frames restantes del hit en curso (0 = inactivo)
DrumKickPeriod:     DEFW 0      ; period AY actual del sweep (R2/R3, 12 bits útiles)

GAMEOVER_LOOP_FRAMES EQU 100    ; 2 bars @ 120 BPM 25fps (mismo que comment de la tabla)
DRUM_HIT_DURATION    EQU 4      ; ~160 ms (más seco/tight para mayor punch)

; --- Sweep "punchy": ataque sub-grave → sub-bass profundo en 4 frames ---
; Period AY = 1750000 / (16 * freq). Start a $0300 (~146 Hz, D3) — attack
; bien por debajo de la voz melódica (G3=196 Hz). Sweep desciende a sub-bass
; profundo.
;   Frame 0 (trigger): $0300 = 146 Hz (~D3, attack sub-grave)
;   Frame 1:           $0440 =  99 Hz (~G2)
;   Frame 2:           $0580 =  75 Hz (~D2)
;   Frame 3:           $06C0 =  63 Hz (~B1, sub-bass profundo)
;   Frame 4: mute
; Cobertura ~1.2 octavas en 160 ms.
DRUM_SWEEP_START     EQU $0300  ; period inicial (R2/R3)
DRUM_SWEEP_STEP      EQU $0140  ; +$0140 por frame de sostén

; --- GameOverDrumTable: 4 hits en offbeats 1.& y 3.& de cada bar ---
; Frames calculados a 25fps con 100 frames/loop (8 beats @ 120 BPM):
;   bar.beat.sixteenth → frame = (bar-1)*50 + (beat-1)*12.5 + (sub-1)*3.125
;   1.1.3 = 6.25  → 6     (offbeat de beat 1 en bar 1)
;   1.3.3 = 31.25 → 31    (offbeat de beat 3 en bar 1)
;   2.1.3 = 56.25 → 56    (offbeat de beat 1 en bar 2)
;   2.3.3 = 81.25 → 81    (offbeat de beat 3 en bar 2)
; Format: {frame_offset, hit_duration_frames}, terminador $FF.
GameOverDrumTable:
    DEFB   6, DRUM_HIT_DURATION  ; 1.1.3
    DEFB  31, DRUM_HIT_DURATION  ; 1.3.3
    DEFB  56, DRUM_HIT_DURATION  ; 2.1.3
    DEFB  81, DRUM_HIT_DURATION  ; 2.3.3
    DEFB $FF                     ; terminator

; --- Track 3: GameOverMusic ---
; Tabla movida a bank 7 (code/music_gameover_bank7.asm). Misma infra de
; prefetch que EndGame: PrefetchMusic pagina bank 7 + LDIR al buffer cada
; vez que el IRQ consume una nota. Ver music_endgame_bank7.asm y
; ay_sound.asm .smArmGameOverBank7. Acompañada por GameOverDrumTable
; (drum sequencer sweep tonal canal B — ver bloque DRUM SEQUENCER al
; principio del archivo).

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
; PauseAy / ResumeAy - silencio temporal del AY para pantallas modales.
; ==============================================================================
; PauseAy: setea AySilenced=1 y escribe vol=0 a los 3 canales. El IRQ handler
; chequea AySilenced al inicio y skipea AY_UpdateSFX + tick música + bell, así
; que el state del driver/SFX queda intacto durante la pausa.
;
; ResumeAy: clear AySilenced. El driver continúa la nota en curso (MusicTimer
; sigue decrementando porque el INC $5C78 / divisor del IRQ NO se gatea); en
; el próximo MusicAdvanceNote se re-arman vols+periods y la música suena otra
; vez. SFX activos siguen su sweep desde el frame donde se pausó.
;
; Destruye: AF, BC, DE.
; ==============================================================================
PauseAy:
    LD A, 1
    LD (AySilenced), A
    DI
    LD A, 8
    LD E, 0
    CALL AY_WriteRegSlot1           ; R8 = 0 (vol A)
    LD A, 9
    LD E, 0
    CALL AY_WriteRegSlot1           ; R9 = 0 (vol B)
    LD A, 10
    LD E, 0
    CALL AY_WriteRegSlot1           ; R10 = 0 (vol C)
    EI
    RET

ResumeAy:
    XOR A
    LD (AySilenced), A
    RET

; Helper: carga el volumen por nota actual (MusicChannelVol) en E.
; Usado por los re-arms y advances de poly2/poly3 antes del CALL AY_WriteReg.
; PRESERVA A: los callers precargan A con el numero de registro AY (8/9/10)
; ANTES del CALL — si LoadMusicVolE clobbeara A, AY_WriteRegSlot1 escribiria
; en el registro equivocado y el track quedaria mudo.
LoadMusicVolE:
    PUSH AF
    LD A, (MusicChannelVol)
    LD E, A
    POP AF
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
    CALL LoadMusicVolE
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
    CALL LoadMusicVolE
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
    LD A, (AySfxChannelMask)        ; nuevo: chequea reserva data-driven
    AND $02                         ; bit 1 = canal B reservado por un SFX
    RET NZ
    LD HL, (MusicPeriodB)
    LD A, H
    OR L
    RET Z
    PUSH HL
    LD A, 9
    CALL LoadMusicVolE
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
;
; Si la track activa vive en bank 7 (MusicTrackInBank7=1), MusicPtr se resetea
; al buffer slot 1 antes de cada consume. El proximo PrefetchMusic en MainLoop
; rellenara el buffer con la siguiente entry desde bank 7. Asi el codigo Poly3
; existente se reutiliza tal cual: lee 7 B, los aplica al AY, "avanza" MusicPtr
; +7 (queda fuera del buffer pero da igual: la proxima entrada lo resetea).
; ==============================================================================
MusicAdvanceNote:
    LD A, (MusicTrackInBank7)
    OR A
    JR Z, .manNotBank7
    ; bank-7 track: apuntar MusicPtr al buffer y pedir refill para la proxima
    LD HL, MusicPrefetchBuf
    LD (MusicPtr), HL
    LD A, 1
    LD (MusicNeedPrefetch), A
.manNotBank7:
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
    CALL LoadMusicVolE
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
    CALL LoadMusicVolE
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
    JP Z, .map3End                  ; JP en lugar de JR: el cuerpo poly3 crecio
                                    ; con los CALL LoadMusicVolE y .map3End
                                    ; quedo fuera del rango -128..+127 de JR
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
    CALL LoadMusicVolE
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
    CALL LoadMusicVolE
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
    CALL LoadMusicVolE
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
    LD A, (MusicTrackInBank7)
    OR A
    JR NZ, .meotLoopBank7
    ; slot-1 track: reset MusicPtr al inicio y reentry inmediato.
    LD HL, (MusicTableStart)
    LD (MusicPtr), HL
    JP MusicAdvanceNote             ; reentrar (no-recursivo: solo lee 1 nota)
.meotLoopBank7:
    ; bank-7 track: prefetch SÍNCRONO inline + aplicar la entry del loop este
    ; mismo IRQ tick. Antes hacíamos MusicTimer=1 (esperar 40ms al siguiente
    ; music-tick para que MainLoop refilara) — eso introducía un gap de
    ; 40ms en el ritmo al loop, perceptible. Ahora:
    ;   1. Cargar bank-7 ptr del loop start.
    ;   2. Paginar bank 7 inline (sin PUSH/POP/CALL — el stack vive en slot 3
    ;      = bank 0, queda "tapado" mientras bank 7 está paginado; mientras
    ;      no toquemos stack, ningún byte cambia y restaurar bank 0 lo deja
    ;      intacto. IRQ ya está DI'd, sin nested interrupts).
    ;   3. LDIR 7 bytes de bank 7 al MusicPrefetchBuf (slot 1, always-vis).
    ;   4. Paginar bank 0 de vuelta (stack accesible).
    ;   5. Setup MusicPtr=MusicPrefetchBuf, clear NeedPrefetch.
    ;   6. ResetDrumLoop (drums sync, gate interno).
    ;   7. JP MusicAdvancePoly3 para aplicar periods+timer del loop YA.
    ; Resultado: la nota post-loop suena exactamente en el music-tick del
    ; terminator, sin tail audible ni gap rítmico.
    LD HL, (MusicTableStart)            ; HL = bank-7 ptr (lectura slot 1, safe)
    LD A, (CurrentPaging)
    LD (.meotSavedPaging), A
    AND $F8
    OR 7
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                          ; slot 3 = bank 7 — NO tocar stack ahora
    LD DE, MusicPrefetchBuf
    LD BC, 7
    LDIR                                ; copia loop start entry al buffer
    LD (MusicBank7Ptr), HL              ; HL avanzado = siguiente entry post-loop
    LD A, (.meotSavedPaging)
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                          ; slot 3 = bank 0 — stack accesible
    LD HL, MusicPrefetchBuf
    LD (MusicPtr), HL                   ; dispatch leerá del buffer
    ; NO clearear MusicNeedPrefetch: MusicAdvanceNote ya lo seteo a 1, y eso es
    ; lo que queremos — PrefetchMusic (slot 1, llamado desde MainLoop entre IRQs)
    ; refilla el buffer con la SIGUIENTE entry (MusicBank7Ptr ya avanzado) para
    ; que el proximo music-tick lea REST 6 (no C3 de nuevo). Sin esto, MusicAdvance
    ; Note resetea MusicPtr=buf y vuelve a leer C3 -> primera nota tras loop dura
    ; 2 ciclos = 160ms en vez de 80ms. Bug reportado: "primera nota se alarga".
    CALL ResetDrumLoop                  ; drum sync (no-op si DrumEnabled=0)
    JP MusicAdvancePoly3                ; aplicar la loop entry YA, sin gap

.meotSavedPaging: DEFB 0
.meotStop:
    ; Signal end-of-track al boot path / cualquier waiter (Inicio polea esto
    ; para liberar el splash tras el jingle StartGame). Cleared en StartMusic.
    LD A, 1
    LD (MusicEnded), A
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
    ; Decrementar canal B (R9) si > 0.
    ; Skip el write si un SFX tiene reservado canal B (mismo gate que
    ; upmiPostLoop). Sin esto, el decay de la campana pisaba el SFX en
    ; los ~1.2s tras la última campanada (síntoma: pickup/hit mudo si
    ; los disparas mientras los residuos de medianoche decaen).
    LD A, (BellVolC)
    OR A
    JR Z, .btiSkipB
    DEC A
    LD (BellVolC), A
    LD HL, AySfxChannelMask
    BIT 1, (HL)                     ; bit 1 = canal B reservado por SFX
    JR NZ, .btiSkipB                ; SFX activo en B → no tocar R9
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

; PrefetchMusic vive en bank 2 (ay_sound_thunks.asm) — slot 1 esta lleno y el
; unico hueco a final de slot 1 ($7FC0-$8000) esta reservado por
; BankCutsceneAltStack. Aqui se quedan solo los datos (state vars) cerca del
; resto del driver.
