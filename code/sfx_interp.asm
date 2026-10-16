; ==============================================================================
; sfx_interp.asm - Generic AY SFX interpreter (slot 1, always visible)
; ==============================================================================
; Walks an opcode stream emitted by tools/build_sfx.py from
; code/sfx_library.json. Single active SFX. While playing, AySfxChannelMask
; lists reserved channels (bit 0=A, 1=B, 2=C, 3=Noise) so the music driver
; can suppress its own writes on those channels (hook to be added later in
; MusicAdvanceNote).
;
; Public API:
;   AY_PlaySFX   A = SFX id (0..AYSFX_COUNT-1)        — start
;   AY_StopSFX                                      — external halt
;   AY_UpdateSFX                                    — per-tick (called from IRQ)
;
; AY writes: direct OUT to $FFFD/$BFFD (no paging — slot 1 always visible).
; Caller manages DI/EI: AY_PlaySFX/AY_StopSFX DI around their writes; AY_UpdateSFX
; runs inside MusicIrqHandler (IFF=0 already).
;
; Opcode IDs must match tools/build_sfx.py OPCODES dict. Args are arranged
; so HL walks the stream forwards with INC HL between bytes.
; ==============================================================================

SFXCMD_END        EQU $00
SFXCMD_WAIT       EQU $01    ; frames(1)
SFXCMD_TONE       EQU $02    ; ch(1) period(2)
SFXCMD_VOL        EQU $03    ; ch(1) v(1)
SFXCMD_MIXER      EQU $04    ; mask(1)
SFXCMD_NOISE      EQU $05    ; period(1)
SFXCMD_ENV_SHAPE  EQU $06    ; shape(1)
SFXCMD_ENV_PERIOD EQU $07    ; period(2)
SFXCMD_SWEEP_TONE EQU $08    ; ch(1) from(2) delta(2) frames(1)
SFXCMD_SWEEP_VOL  EQU $09    ; ch(1) from_fp(2) delta(2) frames(1)   8.8 fp

; --- State (10 B) ---
AySfxPtr:           DEFW 0    ; current cmd ptr (0 = inactive)
AySfxChannelMask:   DEFB 0    ; reserved channels (bit 0=A 1=B 2=C 3=N)
AySfxWait:          DEFB 0    ; frames remaining in current WAIT / SWEEP
AySfxSweepKind:     DEFB 0    ; 0=none, 1=tone, 2=vol
AySfxSweepCh:       DEFB 0    ; channel 0/1/2
AySfxSweepCur:      DEFW 0    ; current value (16-bit; 8.8 fp for vol sweep)
AySfxSweepDelta:    DEFW 0    ; signed delta per frame
AySfxPriority:      DEFB 0    ; prio del SFX activo (de AySfxPriorityTable; 0 = inactivo)

; Copia del SFX que suena (AY_PlaySFX la rellena desde SFX_DATA_BANK). AY_UpdateSFX
; corre en la IRQ y no puede paginar: por eso el programa activo vive aqui.
AY_SFX_BUF_SIZE     EQU 112
SFX_DATA_BANK       EQU 6       ; bank de sfx_data.asm (main.asm, PAGE 6)
AySfxBuf:           DEFS AY_SFX_BUF_SIZE

; ==============================================================================
; AY_PlaySFX - Start a SFX by id. Stops any active SFX first.
; ==============================================================================
; IN: A = SFX id. >= AYSFX_COUNT -> no-op. Destroys: A, BC, DE, HL.
;
; Tablas y datos viven en bank SFX_DATA_BANK (sfx_data.asm). Con DI se pagina, se
; decide por prioridad (si hay SFX activo y su prio > la del nuevo, el nuevo
; se descarta; igual prio -> preempta, latest-wins: el popo no pisa al tic,
; el pickup pisa al popo y el hit pisa a todos), se copia el SFX a AySfxBuf y
; se restaura la paginacion del caller (puede ser bank 7: bank_cutscene).
; En la ventana no hay PUSH ni CALL: la pila normal (slot 3) no se ve.
; ==============================================================================
AY_PlaySFX:
    CP AYSFX_COUNT
    RET NC
    DI
    LD E, A
    LD D, 0                         ; DE = id
    LD A, (CurrentPaging)
    LD (.psPaging), A
    AND $F8
    OR SFX_DATA_BANK
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank de los SFX (tablas + datos)
    LD HL, AySfxPriorityTable
    ADD HL, DE
    LD A, (HL)
    LD (.psPrio), A                 ; prio del nuevo
    LD B, A
    LD HL, (AySfxPtr)
    LD A, H
    OR L
    JR Z, .psAccept                 ; nada sonando
    LD A, (AySfxPriority)
    LD C, A
    LD A, B
    CP C
    JR C, .psDrop                   ; nuevo < activo: descartar
.psAccept:
    LD HL, AySfxChannelMaskTable
    ADD HL, DE
    LD A, (HL)
    LD (.psMask), A
    LD HL, AySfxLenTable
    ADD HL, DE
    LD C, (HL)
    LD B, 0                         ; BC = bytes del SFX
    LD HL, AySfxTable
    ADD HL, DE
    ADD HL, DE
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A                         ; HL = SFX (bank SFX_DATA_BANK)
    LD DE, AySfxBuf
    LDIR
    LD A, 1
    JR .psRestore
.psDrop:
    XOR A
.psRestore:
    LD (.psAccepted), A
    LD A, (.psPaging)
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; paginacion del caller
    LD A, (.psAccepted)
    OR A
    JR Z, .psEnd
    CALL _sfxStopInternal           ; calla el SFX anterior (con su mascara)
    LD A, (.psMask)
    LD (AySfxChannelMask), A
    LD A, (.psPrio)
    LD (AySfxPriority), A
    LD HL, AySfxBuf
    LD (AySfxPtr), HL
.psEnd:
    EI
    RET
.psPaging:   DEFB 0
.psPrio:     DEFB 0
.psMask:     DEFB 0
.psAccepted: DEFB 0

; ==============================================================================
; AY_StopSFX - External halt entry (e.g. on player death, scene change).
; ==============================================================================
AY_StopSFX:
    DI
    CALL _sfxStopInternal
    EI
    RET

; --- Internal: mute reserved channels + clear state. Caller wraps DI/EI. ---
; Destroys: A, BC, DE, HL.
_sfxStopInternal:
    LD A, (AySfxChannelMask)
    OR A
    JR Z, .ssiClear
    LD D, A                         ; D = mask (shift through bits 0..2)
    LD C, 8                         ; C = AY R8/R9/R10 (vol A/B/C)
.ssiMuteLoop:
    SRL D
    JR NC, .ssiSkip
    LD A, C
    LD E, 0
    CALL _sfxWriteAy
.ssiSkip:
    INC C
    LD A, C
    CP 11
    JR C, .ssiMuteLoop
.ssiClear:
    XOR A
    LD H, A
    LD L, A
    LD (AySfxPtr), HL                 ; mark inactive
    LD (AySfxChannelMask), A
    LD (AySfxWait), A
    LD (AySfxSweepKind), A
    LD (AySfxPriority), A             ; prio activa = 0 (drop floor)
    RET

; ==============================================================================
; AY_UpdateSFX - Per-tick advance. Called from MusicIrqHandler (IFF=0, 25 Hz).
; ==============================================================================
; If AySfxWait > 0: decrement, apply active sweep if any.
; If AySfxWait = 0: fetch and execute next commands until WAIT/SWEEP/END.
; Destroys: A, BC, DE, HL.
; ==============================================================================
AY_UpdateSFX:
    LD HL, (AySfxPtr)
    LD A, H
    OR L
    RET Z                           ; inactive

    LD A, (AySfxWait)
    OR A
    JP Z, _sfxFetchCmds

    DEC A
    LD (AySfxWait), A
    LD A, (AySfxSweepKind)
    DEC A
    JR Z, _sfxApplyToneSweep
    DEC A
    JR Z, _sfxApplyVolSweep
    RET                             ; pure WAIT, no sweep

_sfxApplyToneSweep:
    LD HL, (AySfxSweepCur)
    LD DE, (AySfxSweepDelta)
    ADD HL, DE
    LD (AySfxSweepCur), HL
    LD A, (AySfxSweepCh)
    LD B, A
    JP _sfxWriteToneAyIrq           ; tail call

_sfxApplyVolSweep:
    LD HL, (AySfxSweepCur)
    LD DE, (AySfxSweepDelta)
    ADD HL, DE
    LD (AySfxSweepCur), HL
    LD A, (AySfxSweepCh)
    ADD A, 8                        ; R8/9/10
    LD E, H                         ; hi byte (8.8 fp) = current volume
    JP _sfxWriteAy                  ; tail call

; ==============================================================================
; _sfxFetchCmds - Execute commands until something yields (WAIT/SWEEP/END).
; ==============================================================================
; HL preloaded with AySfxPtr (set by caller via memory; we reload).
; Destroys: A, BC, DE, HL.
; ==============================================================================
_sfxFetchCmds:
    XOR A
    LD (AySfxSweepKind), A            ; cleared until a SWEEP cmd sets it
    LD HL, (AySfxPtr)
.fcNext:
    LD A, (HL)
    INC HL
    CP SFXCMD_END
    JR Z, .fcCmdEnd
    CP SFXCMD_WAIT
    JR Z, .fcCmdWait
    CP SFXCMD_TONE
    JR Z, .fcCmdTone
    CP SFXCMD_VOL
    JR Z, .fcCmdVol
    CP SFXCMD_MIXER
    JR Z, .fcCmdMixer
    CP SFXCMD_NOISE
    JR Z, .fcCmdNoise
    CP SFXCMD_ENV_SHAPE
    JR Z, .fcCmdEnvShape
    CP SFXCMD_ENV_PERIOD
    JP Z, .fcCmdEnvPeriod
    CP SFXCMD_SWEEP_TONE
    JP Z, .fcCmdSweepTone
    CP SFXCMD_SWEEP_VOL
    JP Z, .fcCmdSweepVol
    ; Unknown opcode: bail safely (treat as END).
.fcCmdEnd:
    JP _sfxStopInternal             ; tail call: mute reserved + clear state

.fcCmdWait:
    LD A, (HL)
    INC HL
    LD (AySfxWait), A
    LD (AySfxPtr), HL
    RET

.fcCmdTone:
    LD A, (HL)                      ; ch
    INC HL
    LD B, A                         ; B = ch (for tone write helper)
    LD E, (HL)                      ; period lo
    INC HL
    LD D, (HL)                      ; period hi
    INC HL
    PUSH HL
    EX DE, HL                       ; HL = period
    CALL _sfxWriteToneAyIrq
    POP HL
    JR .fcNext

.fcCmdVol:
    LD A, (HL)                      ; ch
    INC HL
    ADD A, 8                        ; R8/9/10
    LD C, A
    LD E, (HL)                      ; v
    INC HL
    PUSH HL
    LD A, C
    CALL _sfxWriteAy
    POP HL
    JR .fcNext

.fcCmdMixer:
    LD E, (HL)
    INC HL
    PUSH HL
    LD A, 7
    CALL _sfxWriteAy
    POP HL
    JR .fcNext

.fcCmdNoise:
    LD E, (HL)
    INC HL
    PUSH HL
    LD A, 6
    CALL _sfxWriteAy
    POP HL
    JR .fcNext

.fcCmdEnvShape:
    LD E, (HL)
    INC HL
    PUSH HL
    LD A, 13
    CALL _sfxWriteAy
    POP HL
    JR .fcNext

.fcCmdEnvPeriod:
    LD E, (HL)                      ; lo
    INC HL
    LD B, (HL)                      ; hi (stash in B)
    INC HL
    PUSH HL
    PUSH BC
    LD A, 11
    CALL _sfxWriteAy                ; R11 = lo
    POP BC
    LD E, B
    LD A, 12
    CALL _sfxWriteAy                ; R12 = hi
    POP HL
    JP .fcNext

.fcCmdSweepTone:
    ; ch, from(2), delta(2), frames
    LD A, (HL)                      ; ch
    INC HL
    LD (AySfxSweepCh), A
    LD B, A                         ; B = ch for initial AY write
    LD E, (HL)                      ; from lo
    INC HL
    LD D, (HL)                      ; from hi
    INC HL
    LD (AySfxSweepCur), DE
    PUSH HL
    EX DE, HL                       ; HL = initial period
    CALL _sfxWriteToneAyIrq         ; audible from frame 1
    POP HL
    LD E, (HL)                      ; delta lo
    INC HL
    LD D, (HL)                      ; delta hi
    INC HL
    LD (AySfxSweepDelta), DE
    LD A, (HL)                      ; frames
    INC HL
    LD (AySfxWait), A
    LD A, 1
    LD (AySfxSweepKind), A
    LD (AySfxPtr), HL
    RET

.fcCmdSweepVol:
    ; ch, from_fp(2 = 8.8), delta(2), frames
    LD A, (HL)                      ; ch
    INC HL
    LD (AySfxSweepCh), A
    LD E, (HL)                      ; from_fp lo
    INC HL
    LD D, (HL)                      ; from_fp hi (= initial volume)
    INC HL
    LD (AySfxSweepCur), DE
    PUSH HL
    LD A, (AySfxSweepCh)
    ADD A, 8
    LD E, D                         ; volume = hi byte of fp
    CALL _sfxWriteAy
    POP HL
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD (AySfxSweepDelta), DE
    LD A, (HL)
    INC HL
    LD (AySfxWait), A
    LD A, 2
    LD (AySfxSweepKind), A
    LD (AySfxPtr), HL
    RET

; ==============================================================================
; AY write helpers (no DI/EI — caller manages)
; ==============================================================================

; _sfxWriteAy: A = reg (0..13), E = value. Destroys A, BC.
_sfxWriteAy:
    LD BC, $FFFD
    OUT (C), A
    LD BC, $BFFD
    OUT (C), E
    RET

; _sfxWriteToneAyIrq: HL = 12-bit period, B = ch (0/1/2). Writes R(2*ch), R(2*ch+1).
; Destroys: A, BC, DE, HL.
_sfxWriteToneAyIrq:
    LD A, B
    ADD A, A                        ; lo register (R0/R2/R4)
    PUSH BC
    PUSH HL
    LD E, L
    CALL _sfxWriteAy
    POP HL
    POP BC
    LD A, B
    ADD A, A
    INC A                           ; hi register
    LD E, H
    JP _sfxWriteAy                  ; tail

; ==============================================================================
; SFX data tables: generadas por tools/build_sfx.py (code/sfx_data.asm) e
; incluidas en bank SFX_DATA_BANK (main.asm, bloque PAGE 6). AY_PlaySFX copia
; el SFX que empieza a AySfxBuf (abajo): la IRQ solo lee slot 1.
; ==============================================================================
