; ==============================================================================
; DEBUG UNLOCK + PAUSA — secuencia B-U-G + tecla ENTER (slot 1)
; ==============================================================================
; Vive en bank 5 (slot 1, $4000-$7FFF, siempre visible) para que pueda llamarse
; desde MainLoop (bank 2) sin paginar y para que las lecturas IN/OUT esten en
; un area no contendida con el codigo principal.
;
; Entry point unico: DebugFramePoll (3 B en el call-site). Se llama 1 vez por
; frame desde MainLoop ANTES del gate de pausa, para que:
;   - El usuario pueda despausar (ENTER) aun estando pausado.
;   - El unlock B-U-G funcione tambien durante pausa o cutscenes.
;   - El flash del border tickee siempre (asi termina aunque entres en cutscene
;     justo despues de desbloquear).
;
; Variables: BugProgress, DebugUnlocked, BugKeyDebounce, DebugFlashTimer,
;   BorderFlashSavedColor, PauseActive, PauseKeyDebounce — todas en variables.asm.
;
; Secuencia B-U-G:
;   1. Estado 0: esperando B. Al pulsar B → estado 1 + debounce.
;   2. Estado 1: esperando U. Al pulsar U → estado 2 + debounce.
;   3. Estado 2: esperando G. Al pulsar G → estado 3 + DebugUnlocked=1 + flash.
;   4. Estado 3: sticky, no se procesa mas (la rutina retorna early).
; Debounce global: tras cualquier press, NINGUNA de B/U/G puede estar pulsada
; antes de avanzar al siguiente paso. Asi una pulsacion larga no avanza estados
; en cadena. Otras teclas (no-BUG) no resetean — la secuencia tolera ruido.
;
; Filas de teclado leidas:
;   B    → $7FFE bit 4    (fila SPACE-SS-M-N-B)
;   U    → $DFFE bit 3    (fila P-O-I-U-Y)
;   G    → $FDFE bit 4    (fila A-S-D-F-G)
;   ENTER → $BFFE bit 0   (fila ENTER-L-K-J-H)
; ==============================================================================

; ==============================================================================
; DebugFramePoll - llamado 1×/frame desde MainLoop (top, antes del gate pausa)
; ==============================================================================
DebugFramePoll:
    CALL TickBorderFlash        ; Decrementar timer + override border si activo
    ; BUG sequence: solo si aun no desbloqueado
    LD A, (DebugUnlocked)
    OR A
    CALL Z, CheckBugSequence
    ; Pausa: siempre (incluso con debug bloqueado)
    JP CheckPauseKey

; ==============================================================================
; CheckBugSequence - state machine de la secuencia B → U → G
; Solo se llama si DebugUnlocked = 0.
; ==============================================================================
CheckBugSequence:
    ; --- Debounce: si habia tecla pulsada el frame previo, esperar liberacion ---
    LD A, (BugKeyDebounce)
    OR A
    JR Z, .noDebounce
    ; Alguna tecla BUG estaba pulsada. Comprobar si TODAS estan ya sueltas.
    LD A, $7F
    IN A, ($FE)
    BIT 4, A                    ; B?
    RET Z                       ; B aun pulsada
    LD A, $DF
    IN A, ($FE)
    BIT 3, A                    ; U?
    RET Z
    LD A, $FD
    IN A, ($FE)
    BIT 4, A                    ; G?
    RET Z
    ; Todas sueltas: limpiar debounce
    XOR A
    LD (BugKeyDebounce), A
    RET                         ; espera al siguiente frame para advance

.noDebounce:
    ; Sin debounce: leer la tecla esperada por el estado actual.
    LD A, (BugProgress)
    OR A
    JR Z, .waitB
    DEC A
    JR Z, .waitU
    DEC A
    JR Z, .waitG
    RET                         ; estado >= 3: nada que hacer

.waitB:
    LD A, $7F
    IN A, ($FE)
    BIT 4, A                    ; B = bit 4 (0 = pulsada)
    RET NZ
    LD A, 1
    LD (BugProgress), A
    LD (BugKeyDebounce), A
    RET

.waitU:
    LD A, $DF
    IN A, ($FE)
    BIT 3, A                    ; U = bit 3
    RET NZ
    LD A, 2
    LD (BugProgress), A
    LD A, 1
    LD (BugKeyDebounce), A
    RET

.waitG:
    LD A, $FD
    IN A, ($FE)
    BIT 4, A                    ; G = bit 4
    RET NZ
    ; G pulsada: completar unlock + arrancar flash
    LD A, 3
    LD (BugProgress), A
    LD A, 1
    LD (DebugUnlocked), A
    LD (BugKeyDebounce), A
    ; Fall-through a StartBorderFlash

; ==============================================================================
; StartBorderFlash - inicia el flash blanco de 50 frames (~1 s).
; Guarda el border actual para restaurarlo despues. Pinta WHITE de inmediato.
; ==============================================================================
StartBorderFlash:
    LD A, (CurrentBorderColor)
    LD (BorderFlashSavedColor), A
    LD A, 50                    ; ~1 s @ 50 Hz
    LD (DebugFlashTimer), A
    LD A, 7                     ; WHITE
    OUT ($FE), A
    LD (CurrentBorderColor), A  ; para que SFX/etc no restauren el viejo
    RET

; ==============================================================================
; TickBorderFlash - decrementa DebugFlashTimer y restaura border al expirar.
; Mientras activo, fuerza WHITE cada frame (defensa contra SFX que tocan border).
; No-op si timer = 0.
; ==============================================================================
TickBorderFlash:
    LD A, (DebugFlashTimer)
    OR A
    RET Z
    DEC A
    LD (DebugFlashTimer), A
    JR Z, .expired
    ; Aun activo: re-forzar blanco
    LD A, 7
    OUT ($FE), A
    RET
.expired:
    LD A, (BorderFlashSavedColor)
    OUT ($FE), A
    LD (CurrentBorderColor), A
    RET

; ==============================================================================
; CheckPauseKey - tecla ENTER togglea PauseActive. Debounce por flanco.
; Al activar pausa, llama PauseAy (silencia AY canales A/B/C). Al desactivar,
; ResumeAy (proximo tick re-arma vols, musica retoma mid-track). Beeper queda
; mudo automaticamente porque MainLoop saltea UpdateBeeperTicks bajo pausa.
; PauseAy / ResumeAy viven en music_irq.asm (slot 1, mismo bank que aqui).
; ==============================================================================
CheckPauseKey:
    LD A, $BF
    IN A, ($FE)                 ; fila ENTER-L-K-J-H
    BIT 0, A                    ; ENTER = bit 0
    JR Z, .pressed
    ; ENTER liberada: limpiar debounce
    XOR A
    LD (PauseKeyDebounce), A
    RET
.pressed:
    LD A, (PauseKeyDebounce)
    OR A
    RET NZ                      ; ya procesada esta pulsacion
    LD A, 1
    LD (PauseKeyDebounce), A
    LD A, (PauseActive)
    XOR 1
    LD (PauseActive), A
    OR A
    JP NZ, PauseAy              ; toggle ON  -> silenciar AY
    JP ResumeAy                 ; toggle OFF -> reanudar AY
