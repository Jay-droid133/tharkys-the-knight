; ==============================================================================
; sfx_test.asm - Audicion de SFX (solo en builds con -DSFXTEST)
; ==============================================================================
; tools/perf/sfx_audition.py genera sfx_test_list.asm, compila con -DSFXTEST y
; graba el audio en zxrun (--wav). Inicio salta aqui en vez de a MainLoop:
; se para la musica y se tocan, uno a uno, los SFX de SfxTestList con ~0,8 s
; de silencio detras de cada uno. SfxTestStep = numero del SFX que suena (el
; script lo muestrea cada frame para cortar el WAV por SFX).
;
; Entrada de SfxTestList (3 bytes): tipo, a1, a2
;   0 = beeper (PlaySFX):        a1 a2 = puntero al SFX_* (DEFW)
;   1 = AY (AY_PlaySFX):         a1 = AYSFX_*, a2 = 0
;   2 = tic de beeper:           a1 = half-cycles, a2 = periodo (como BeeperTick)
;   $FF = fin
; ==============================================================================
SfxTest:
    XOR A
    LD (MusicTimer), A              ; driver de musica parado (como en Inicio)
    LD (MusicTrackInBank7), A
    LD (MusicNeedPrefetch), A
    LD (DrumEnabled), A
    CALL AY_Init                    ; AY callado
    LD HL, SfxTestList
.stNext:
    LD A, (SfxTestStep)
    INC A
    LD (SfxTestStep), A
    LD A, (HL)
    CP $FF
    JR Z, .stDone
    PUSH HL
    INC HL
    LD E, (HL)                      ; a1
    INC HL
    LD D, (HL)                      ; a2
    OR A
    JR Z, .stBeeper
    DEC A
    JR Z, .stAy
    LD B, E                         ; tic: B = half-cycles, E = periodo
    LD E, D
    CALL SfxTestBeeperTick
    JR .stWait
.stBeeper:
    EX DE, HL
    CALL PlaySFX
    JR .stWait
.stAy:
    LD A, E
    CALL AY_PlaySFX
.stWait:
    LD B, 40
.stHalt:
    HALT
    DJNZ .stHalt
    POP HL
    INC HL
    INC HL
    INC HL
    JR .stNext
.stDone:
    HALT
    JR .stDone

; Copia de BeeperTick (beeper_ticks.asm, bank 4) para tocar los tics sin paginar.
SfxTestBeeperTick:
    LD A, (CurrentBorderColor)
    AND $07
    LD D, A
.sbtLoop:
    LD A, D
    XOR $10
    LD D, A
    OUT ($FE), A
    LD C, E
.sbtInner:
    DEC C
    JR NZ, .sbtInner
    DJNZ .sbtLoop
    LD A, D
    AND $07
    OUT ($FE), A
    RET

SfxTestStep: DEFB 0

    INCLUDE "sfx_test_list.asm"
