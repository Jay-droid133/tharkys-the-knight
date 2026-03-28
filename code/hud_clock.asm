; ==============================================================================
; HUD CLOCK - Reloj analógico (filas 22-23, cols 13-18)
; ==============================================================================
; Sprite BgGfx_hud_clock: 48×16px (6 bytes ancho, 2 filas de chars)
; Centrado en HUD: col inicio = 13, cols de esfera = 15-16
; Agujas: borran bits (AND ~mask) → marcas negras sobre esfera blanca
; Centro esfera: pixel (7,7) relativo al bloque 2×2 de la esfera
; VRAM fila 22: scan S → H=$50|S, col13→L=$CD .. col18→L=$D2
; VRAM fila 23: scan S → H=$50|S, col13→L=$ED .. col18→L=$F2
; ==============================================================================

; --- Variables ---
GameSubMinute:      DEFB 0
GameMinutes:        DEFB 0
GameHours:          DEFB 6      ; empieza a las 06:00 (DY)
SubMinuteMax:       DEFB 21     ; frames por minuto (21 ≈ 10 min/día)
ClockDebounce:      DEFB 0      ; debounce teclas 1/2/3

; --- Horas de inicio de cada fase ---
PhaseStartHour:
    DEFB 6, 17, 19, 20, 22, 4, 5

; --- Tabla de transiciones automáticas (hora, fase) ---
PhaseTable:
    DEFB 6,  0      ; 06:00 → DY
    DEFB 17, 1      ; 17:00 → C1
    DEFB 19, 2      ; 19:00 → C2
    DEFB 20, 3      ; 20:00 → N1
    DEFB 22, 4      ; 22:00 → N2
    DEFB 4,  5      ; 04:00 → A1
    DEFB 5,  6      ; 05:00 → A2

; ==============================================================================
; DATOS DE LÍNEAS DE AGUJAS
; Cada entrada: DEFB H, L, mask ... $00 (terminador)
; Las agujas borran bits (AND ~mask) sobre la esfera blanca
; Centro esfera: pixel (7,7) → col15, bit0, scan7, fila22 → $57CF
; ==============================================================================

; --- Aguja de minutos (radio 6) ---
MinHandPtrs:
    DEFW MinHand_0, MinHand_1, MinHand_2,  MinHand_3
    DEFW MinHand_4, MinHand_5, MinHand_6,  MinHand_7
    DEFW MinHand_8, MinHand_9, MinHand_10, MinHand_11

MinHand_0:  ; 12 en punto
    DEFB $56,$CF,$01, $55,$CF,$01, $54,$CF,$01
    DEFB $53,$CF,$01, $52,$CF,$01, $51,$CF,$01, $00
MinHand_1:  ; 1 en punto
    DEFB $56,$D0,$80, $55,$D0,$80, $54,$D0,$40
    DEFB $53,$D0,$40, $52,$D0,$20, $00
MinHand_2:  ; 2 en punto
    DEFB $56,$D0,$80, $56,$D0,$40, $55,$D0,$20
    DEFB $55,$D0,$10, $54,$D0,$08, $00
MinHand_3:  ; 3 en punto
    DEFB $57,$D0,$80, $57,$D0,$40, $57,$D0,$20
    DEFB $57,$D0,$10, $57,$D0,$08, $57,$D0,$04, $00
MinHand_4:  ; 4 en punto
    DEFB $50,$F0,$80, $50,$F0,$40, $51,$F0,$20
    DEFB $51,$F0,$10, $52,$F0,$08, $00
MinHand_5:  ; 5 en punto
    DEFB $50,$F0,$80, $51,$F0,$80, $52,$F0,$40
    DEFB $53,$F0,$40, $54,$F0,$20, $00
MinHand_6:  ; 6 en punto
    DEFB $50,$EF,$01, $51,$EF,$01, $52,$EF,$01
    DEFB $53,$EF,$01, $54,$EF,$01, $55,$EF,$01, $00
MinHand_7:  ; 7 en punto
    DEFB $50,$EF,$02, $51,$EF,$02, $52,$EF,$04
    DEFB $53,$EF,$04, $54,$EF,$08, $00
MinHand_8:  ; 8 en punto
    DEFB $50,$EF,$02, $50,$EF,$04, $51,$EF,$08
    DEFB $51,$EF,$10, $52,$EF,$20, $00
MinHand_9:  ; 9 en punto
    DEFB $57,$CF,$02, $57,$CF,$04, $57,$CF,$08
    DEFB $57,$CF,$10, $57,$CF,$20, $57,$CF,$40, $00
MinHand_10: ; 10 en punto
    DEFB $56,$CF,$02, $56,$CF,$04, $55,$CF,$08
    DEFB $55,$CF,$10, $54,$CF,$20, $00
MinHand_11: ; 11 en punto
    DEFB $56,$CF,$02, $55,$CF,$02, $54,$CF,$04
    DEFB $53,$CF,$04, $52,$CF,$08, $00

; --- Aguja de horas (radio 4) ---
HourHandPtrs:
    DEFW HourHand_0, HourHand_1, HourHand_2,  HourHand_3
    DEFW HourHand_4, HourHand_5, HourHand_6,  HourHand_7
    DEFW HourHand_8, HourHand_9, HourHand_10, HourHand_11

HourHand_0:
    DEFB $56,$CF,$01, $55,$CF,$01, $54,$CF,$01, $53,$CF,$01, $00
HourHand_1:
    DEFB $56,$D0,$80, $55,$D0,$80, $54,$D0,$40, $00
HourHand_2:
    DEFB $56,$D0,$80, $56,$D0,$40, $55,$D0,$20, $00
HourHand_3:
    DEFB $57,$D0,$80, $57,$D0,$40, $57,$D0,$20, $57,$D0,$10, $00
HourHand_4:
    DEFB $50,$F0,$80, $50,$F0,$40, $51,$F0,$20, $00
HourHand_5:
    DEFB $50,$F0,$80, $51,$F0,$80, $52,$F0,$40, $00
HourHand_6:
    DEFB $50,$EF,$01, $51,$EF,$01, $52,$EF,$01, $53,$EF,$01, $00
HourHand_7:
    DEFB $50,$EF,$02, $51,$EF,$02, $52,$EF,$04, $00
HourHand_8:
    DEFB $50,$EF,$02, $50,$EF,$04, $51,$EF,$08, $00
HourHand_9:
    DEFB $57,$CF,$02, $57,$CF,$04, $57,$CF,$08, $57,$CF,$10, $00
HourHand_10:
    DEFB $56,$CF,$02, $56,$CF,$04, $55,$CF,$08, $00
HourHand_11:
    DEFB $56,$CF,$02, $55,$CF,$02, $54,$CF,$04, $00

; ==============================================================================
; UpdateGameClock
; ==============================================================================
UpdateGameClock:
    LD HL, GameSubMinute
    INC (HL)
    LD A, (SubMinuteMax)
    CP (HL)
    RET NZ

    XOR A
    LD (GameSubMinute), A
    LD HL, GameMinutes
    INC (HL)
    LD A, (HL)
    CP 60
    RET NZ

    XOR A
    LD (GameMinutes), A
    LD HL, GameHours
    INC (HL)
    LD A, (HL)
    CP 24
    JR NZ, .checkPhase
    XOR A
    LD (GameHours), A

.checkPhase:
    LD A, (GameHours)
    LD HL, PhaseTable
    LD B, 7
.phaseLoop:
    CP (HL)
    JR Z, .phaseFound
    INC HL
    INC HL
    DJNZ .phaseLoop
    RET
.phaseFound:
    INC HL
    LD A, (HL)
    CALL SetTimeOfDay
    RET

; ==============================================================================
; SetClockToPhaseHour
; ==============================================================================
SetClockToPhaseHour:
    LD HL, PhaseStartHour
    LD C, A
    LD B, 0
    ADD HL, BC
    LD A, (HL)
    LD (GameHours), A
    XOR A
    LD (GameMinutes), A
    LD (GameSubMinute), A
    RET

; ==============================================================================
; DrawClockHUD - Redibuja cara (cols 15-16) + agujas cada frame
; ==============================================================================
DrawClockHUD:
    CALL DrawClockFaceOnly  ; restaura pixels de la esfera (cols 15-16 únicamente)

    ; --- Aguja de horas ---
    LD A, (GameHours)
    CP 12
    JR C, .hourOk
    SUB 12
.hourOk:
    LD HL, HourHandPtrs
    CALL DrawHandLine

    ; --- Aguja de minutos ---
    LD A, (GameMinutes)
    LD B, 0
.divMin:
    CP 5
    JR C, .minOk
    SUB 5
    INC B
    JR .divMin
.minOk:
    LD A, B
    LD HL, MinHandPtrs
    CALL DrawHandLine

    ; --- Punto central (borra el pixel = marca negra) ---
    LD HL, $57CF
    RES 0, (HL)

    RET

; ==============================================================================
; DrawClockFaceOnly - Redibuja solo la esfera (cols 15-16, filas 22-23)
; ==============================================================================
; Salta los bytes de decoración (bytes 0-1 y 4-5 de cada fila del sprite)
; ==============================================================================
DrawClockFaceOnly:
    LD IX, BgGfx_hud_clock + 2  ; saltar cabecera

    LD H, $50
    LD L, $CF               ; col 15, scan 0, fila 22
    LD C, 8
.fc22:
    INC IX : INC IX         ; saltar bytes 0-1 (decoración izquierda)
    PUSH HL
    PUSH BC
    LD A, (IX) : INC IX : CPL : LD (HL), A : INC HL  ; byte 2 → col 15
    LD A, (IX) : INC IX : CPL : LD (HL), A            ; byte 3 → col 16
    INC IX : INC IX         ; saltar bytes 4-5 (decoración derecha)
    POP BC
    POP HL
    INC H
    DEC C
    JR NZ, .fc22

    LD H, $50
    LD L, $EF               ; col 15, scan 0, fila 23
    LD C, 8
.fc23:
    INC IX : INC IX
    PUSH HL
    PUSH BC
    LD A, (IX) : INC IX : CPL : LD (HL), A : INC HL
    LD A, (IX) : INC IX : CPL : LD (HL), A
    INC IX : INC IX
    POP BC
    POP HL
    INC H
    DEC C
    JR NZ, .fc23

    ; Atributos de la esfera
    LD A, $07
    LD ($5ACF), A
    LD ($5AD0), A
    LD ($5AEF), A
    LD ($5AF0), A
    RET

; ==============================================================================
; DrawClockSprite - Copia BgGfx_hud_clock al HUD (filas 22-23, cols 13-18)
; ==============================================================================
; Aplica CPL a cada byte (datos almacenados invertidos, como en DrawBgGfxSprite)
; ==============================================================================
DrawClockSprite:
    LD IX, BgGfx_hud_clock + 2  ; saltar cabecera height_px, width_bytes

    ; --- Filas 0-7 del sprite → fila 22, scans 0-7 ---
    LD H, $50
    LD L, $CD               ; col 13, scan 0
    LD C, 8
.r22:
    PUSH HL
    PUSH BC
    LD B, 6
.b22:
    LD A, (IX)
    CPL
    LD (HL), A
    INC IX
    INC HL
    DJNZ .b22
    POP BC
    POP HL
    INC H                   ; siguiente scan line
    DEC C
    JR NZ, .r22

    ; --- Filas 8-15 del sprite → fila 23, scans 0-7 ---
    LD H, $50
    LD L, $ED               ; col 13, scan 0
    LD C, 8
.r23:
    PUSH HL
    PUSH BC
    LD B, 6
.b23:
    LD A, (IX)
    CPL
    LD (HL), A
    INC IX
    INC HL
    DJNZ .b23
    POP BC
    POP HL
    INC H
    DEC C
    JR NZ, .r23

    ; --- Atributos del sprite (2 filas × 6 cols) ---
    INC IX                  ; saltar attr_h
    INC IX                  ; saltar attr_w
    LD HL, $5ACD            ; ATTR_BASE + 22*32 + 13
    LD B, 6
.a22:
    LD A, (IX)
    LD (HL), A
    INC IX
    INC HL
    DJNZ .a22
    LD HL, $5AED            ; ATTR_BASE + 23*32 + 13
    LD B, 6
.a23:
    LD A, (IX)
    LD (HL), A
    INC IX
    INC HL
    DJNZ .a23

    RET

; ==============================================================================
; DrawHandLine - Borra pixels de la aguja (AND ~mask = marca negra)
; ==============================================================================
; Entrada: A = posición (0-11), HL = tabla de punteros
; ==============================================================================
DrawHandLine:
    ADD A, A
    LD C, A
    LD B, 0
    ADD HL, BC
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A             ; HL = puntero a datos de línea

.pixLoop:
    LD A, (HL)          ; VRAM H ($00 = fin)
    OR A
    RET Z
    LD D, A
    INC HL
    LD A, (HL)          ; VRAM L
    INC HL
    LD E, A
    LD A, (HL)          ; mask
    INC HL
    PUSH HL
    CPL                 ; ~mask
    LD H, D
    LD L, E
    AND (HL)            ; borrar bit: (HL) AND ~mask
    LD (HL), A
    POP HL
    JR .pixLoop

; ==============================================================================
; CheckClockSpeedKeys - Teclas 1/2/3 (debug)
; ==============================================================================
CheckClockSpeedKeys:
    LD A, $F7
    IN A, ($FE)
    CPL
    AND $07

    LD B, A
    LD A, (ClockDebounce)
    LD C, A
    LD A, B
    LD (ClockDebounce), A
    LD A, B

    LD A, C
    CPL
    AND B
    RET Z

    BIT 0, A
    JR Z, .try2
    LD A, 1
    LD (SubMinuteMax), A
    RET
.try2:
    BIT 1, A
    JR Z, .try3
    LD A, 5
    LD (SubMinuteMax), A
    RET
.try3:
    LD A, 21
    LD (SubMinuteMax), A
    RET
