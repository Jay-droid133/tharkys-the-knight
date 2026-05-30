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
; Notas transpuestas +1 octava respecto al MIDI original (canal B central):
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
; Voz en canal B (centro del estereo ABC del 128K +2/+3) — el jingle suena
; centrado en HW real en vez de ladeado al altavoz izquierdo (canal A).
; ==============================================================================

StartGameMusicTable_Bank7:
    DEFW $0000 : DEFW $00A6 : DEFW $0000 : DEFB  6   ; B=E5 (doblada: 3->6, sin rest inicial)
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $0000 : DEFW $00BA : DEFW $0000 : DEFB  3   ; B=D5
    DEFW $0000 : DEFW $00D1 : DEFW $0000 : DEFB  3   ; B=C5
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $0000 : DEFW $00DD : DEFW $0000 : DEFB  3   ; B=B4
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $0000 : DEFW $00D1 : DEFW $0000 : DEFB  3   ; B=C5
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $0000 : DEFW $0117 : DEFW $0000 : DEFB  3   ; B=G4
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  3   ; rest 3f
    DEFW $0000 : DEFW $00D1 : DEFW $0000 : DEFB  3   ; B=C5
    DEFW $0000 : DEFW $0000 : DEFW $0000 : DEFB  6   ; tail rest 6f (cola limpia)
    DEFW 0     : DEFW 0     : DEFW 0     : DEFB  0   ; terminator -> .meotStop

; ==============================================================================
; Guard: bank 7 no debe extenderse dentro de la zona de tombstones.
; ==============================================================================
; Si una tabla nueva (o cualquier crecimiento del codigo bank 7) hace que el PC
; cruce TOMBSTONE_ADDR, TombStore machacara silenciosamente bytes de la tabla
; tras la 1a muerte del player. Bug recurrente: paso con CheckBankTriggerBg
; ($E000 -> $FA00) y con GameOverMusicTable ($FA00 -> $FB00). Ver
; tombstones.asm para la historia. ASSERT lo caza al compilar antes de que
; vuelva a colarse.
    ASSERT $ <= TOMBSTONE_ADDR
