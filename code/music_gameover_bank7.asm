; ==============================================================================
; music_gameover_bank7.asm - GameOverMusicTable en bank 7 (slot 3 paginado)
; ==============================================================================
; Misma infra que music_endgame_bank7.asm: PrefetchMusic en bank 2 rellena el
; buffer slot 1 antes de que el IRQ lo consuma. Igual que EndGame:
;   - LOOPABLE (MusicLoop = 1): al terminator → .meotLoopBank7 → reset cursor
;     + prefetch → primera nota desde principio. Loop perceptible (~3.64s).
;     Suena hasta que el player pulsa SPACE en la pantalla de Game Over.
;
; Formato: Poly3 (A+B+C), 7 B/entry. Voz duplicada en A+C para mono dual.
; Generado por tools/music_converter.html desde music/smoothie.mid.
; Tempo: 100% | Notes: 31 | Bytes: 224 | Duration: 3.64s @ 25fps
; ==============================================================================

GameOverMusicTable_Bank7:
    DEFW $022E : DEFW $0000 : DEFW $022E : DEFB   1   ; A=G3 B=REST C=G3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   5   ; A=REST B=REST C=REST
    DEFW $022E : DEFW $0000 : DEFW $022E : DEFB   2   ; A=G3 B=REST C=G3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   1   ; A=REST B=REST C=REST
    DEFW $022E : DEFW $0000 : DEFW $022E : DEFB   2   ; A=G3 B=REST C=G3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $01F1 : DEFW $0000 : DEFW $01F1 : DEFB   1   ; A=A3 B=REST C=A3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $01D5 : DEFW $0000 : DEFW $01D5 : DEFB   1   ; A=A#3 B=REST C=A#3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $01F1 : DEFW $0000 : DEFW $01F1 : DEFB   1   ; A=A3 B=REST C=A3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   5   ; A=REST B=REST C=REST
    DEFW $01A2 : DEFW $0000 : DEFW $01A2 : DEFB   3   ; A=C4 B=REST C=C4
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  10   ; A=REST B=REST C=REST
    DEFW $01D5 : DEFW $0000 : DEFW $01D5 : DEFB   1   ; A=A#3 B=REST C=A#3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $01F1 : DEFW $0000 : DEFW $01F1 : DEFB   1   ; A=A3 B=REST C=A3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $022E : DEFW $0000 : DEFW $022E : DEFB   1   ; A=G3 B=REST C=G3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   5   ; A=REST B=REST C=REST
    DEFW $022E : DEFW $0000 : DEFW $022E : DEFB   3   ; A=G3 B=REST C=G3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  10   ; A=REST B=REST C=REST
    DEFW $01F1 : DEFW $0000 : DEFW $01F1 : DEFB   1   ; A=A3 B=REST C=A3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $01D5 : DEFW $0000 : DEFW $01D5 : DEFB   1   ; A=A#3 B=REST C=A#3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   2   ; A=REST B=REST C=REST
    DEFW $01F1 : DEFW $0000 : DEFW $01F1 : DEFB   1   ; A=A3 B=REST C=A3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   5   ; A=REST B=REST C=REST
    DEFW $01A2 : DEFW $0000 : DEFW $01A2 : DEFB   3   ; A=C4 B=REST C=C4
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  10   ; A=REST B=REST C=REST
    DEFW $022E : DEFW $0000 : DEFW $022E : DEFB   3   ; A=G3 B=REST C=G3
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB   9   ; REST que alinea el loop a 8 beats
                                                       ; (91 + 9 = 100 frames = 8 beats @ 120 BPM 25fps)
    DEFW 0     : DEFW 0     : DEFW 0     : DEFB   0   ; fin (terminator -> loop)
