; ==============================================================================
; music_startgame_bank7.asm - StartGameMusicTable en bank 7 (slot 3 paginado)
; ==============================================================================
; Jingle corto que suena tras pulsar tecla/boton en el splash. Interrumpe el
; loop de EndGame inmediatamente, suena ~2s, y al terminar el splash se cierra
; y arranca el gameplay. Patron clasico Spectrum "press any key" intro.
;
; Misma infra que EndGame/GameOver: track bank-7 + prefetch buffer slot 1
; (ver music_irq.asm PrefetchMusic + ay_sound.asm .smArmStartGameBank7).
; Track ID 5. One-shot (MusicLoop=0). Al consumir el terminator, .meotStop
; setea MusicEnded=1 que Inicio polea para liberar el splash.
;
; Fuente: music/StartGame.mid (MIDI mono, 7 notas, ~1.7s @ 120 BPM).
; Notas transpuestas +1 octava respecto al MIDI original (canal A):
;   E5, D5, C5, B4, C5, G4, C5.
;
; Period AY = 1750000 / (16 * freq):
;   E5 (659.3Hz) = $00A6    G4 (392.0Hz) = $0117
;   D5 (587.3Hz) = $00BA    B4 (493.9Hz) = $00DD
;   C5 (523.3Hz) = $00D1
;
; Total: ~51 frames @ 25Hz = ~2.04s. 14 entries * 7 B = 98 B.
;
; Formato Poly3: periodA(2), periodB(2), periodC(2), duration(1).
; Mono = solo canal A activo (B y C a 0).
; ==============================================================================

StartGameMusicTable_Bank7:
    DEFW $00A6 : DEFW $0000 : DEFW $0000 : DEFB  6   ; A=E5 (doblada: 3->6, sin rest inicial)
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $00BA : DEFW $0000 : DEFW $0000 : DEFB  3   ; A=D5
    DEFW $00D1 : DEFW $0000 : DEFW $0000 : DEFB  3   ; A=C5
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $00DD : DEFW $0000 : DEFW $0000 : DEFB  3   ; A=B4
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $00D1 : DEFW $0000 : DEFW $0000 : DEFB  3   ; A=C5
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $0117 : DEFW $0000 : DEFW $0000 : DEFB  3   ; A=G4
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $00D1 : DEFW $0000 : DEFW $0000 : DEFB  3   ; A=C5
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  6   ; tail rest 6f (cola limpia)
    DEFW 0     : DEFW 0     : DEFW 0     : DEFB  0   ; terminator -> .meotStop
