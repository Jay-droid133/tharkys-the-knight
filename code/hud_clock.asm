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

; ==============================================================================
; SPRITE DATA - almacenado aquí, fuera del bg_gfx.asm (el editor no lo toca)
; ==============================================================================
BgGfx_hud_clock:    ; BG44 · Hud Clock · 48×16px
    DEFB 16, 6    ; height_px, width_bytes
    DEFB $79, $E0, $F8, $1F, $07, $9E
    DEFB $CF, $FB, $E1, $87, $DF, $F3
    DEFB $C6, $1E, $C0, $03, $78, $63
    DEFB $F0, $0E, $80, $01, $70, $0F
    DEFB $71, $CC, $80, $01, $33, $8E
    DEFB $03, $EC, $00, $00, $37, $C0
    DEFB $3A, $6C, $00, $00, $36, $5C
    DEFB $6E, $CC, $40, $02, $33, $76
    DEFB $02, $0C, $40, $02, $30, $40
    DEFB $63, $3C, $00, $00, $3C, $C6
    DEFB $C9, $FC, $00, $00, $3F, $93
    DEFB $CC, $3C, $80, $01, $3C, $33
    DEFB $F8, $1E, $80, $01, $78, $1F
    DEFB $7C, $3E, $C0, $03, $7C, $3E
    DEFB $0F, $F7, $E1, $87, $EF, $F0
    DEFB $07, $E3, $F8, $1F, $C7, $E0
    DEFB 2, 6    ; attr_h, attr_w
    DEFB $38, $78, $47, $07, $78, $38
    DEFB $38, $78, $47, $07, $78, $38

; --- Variables ---
GameSubMinute:      DEFB 0
GameMinutes:        DEFB 0      ; Empieza a las 18:00 (crepusculo temprano)
GameHours:          DEFB 18     ; Crepusculo temprano
SubMinuteMax:       DEFB 21     ; frames por minuto (21 ≈ 10 min/día)
ClockDebounce:      DEFB 0      ; debounce teclas 1/2/3

; --- Horas de inicio de cada fase ---
PhaseStartHour:
    DEFB 7, 18, 20, 22, 0, 5, 6

; --- Tabla de transiciones automáticas (hora, fase) ---
PhaseTable:
    DEFB 7,  0      ; 07:00 → DY
    DEFB 18, 1      ; 18:00 → C1
    DEFB 20, 2      ; 20:00 → C2
    DEFB 22, 3      ; 22:00 → N1
    DEFB 0,  4      ; 00:00 → N2
    DEFB 5,  5      ; 05:00 → A1
    DEFB 6,  6      ; 06:00 → A2

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
    DEFB $46,$0F,$01, $45,$0F,$01, $44,$0F,$01
    DEFB $43,$0F,$01, $42,$0F,$01, $41,$0F,$01, $00
MinHand_1:  ; 1 en punto
    DEFB $46,$10,$80, $45,$10,$80, $44,$10,$40
    DEFB $43,$10,$40, $42,$10,$20, $00
MinHand_2:  ; 2 en punto
    DEFB $46,$10,$80, $46,$10,$40, $45,$10,$20
    DEFB $45,$10,$10, $44,$10,$08, $00
MinHand_3:  ; 3 en punto
    DEFB $47,$10,$80, $47,$10,$40, $47,$10,$20
    DEFB $47,$10,$10, $47,$10,$08, $47,$10,$04, $00
MinHand_4:  ; 4 en punto
    DEFB $40,$30,$80, $40,$30,$40, $41,$30,$20
    DEFB $41,$30,$10, $42,$30,$08, $00
MinHand_5:  ; 5 en punto
    DEFB $40,$30,$80, $41,$30,$80, $42,$30,$40
    DEFB $43,$30,$40, $44,$30,$20, $00
MinHand_6:  ; 6 en punto
    DEFB $40,$2F,$01, $41,$2F,$01, $42,$2F,$01
    DEFB $43,$2F,$01, $44,$2F,$01, $45,$2F,$01, $00
MinHand_7:  ; 7 en punto
    DEFB $40,$2F,$02, $41,$2F,$02, $42,$2F,$04
    DEFB $43,$2F,$04, $44,$2F,$08, $00
MinHand_8:  ; 8 en punto
    DEFB $40,$2F,$02, $40,$2F,$04, $41,$2F,$08
    DEFB $41,$2F,$10, $42,$2F,$20, $00
MinHand_9:  ; 9 en punto
    DEFB $47,$0F,$02, $47,$0F,$04, $47,$0F,$08
    DEFB $47,$0F,$10, $47,$0F,$20, $47,$0F,$40, $00
MinHand_10: ; 10 en punto
    DEFB $46,$0F,$02, $46,$0F,$04, $45,$0F,$08
    DEFB $45,$0F,$10, $44,$0F,$20, $00
MinHand_11: ; 11 en punto
    DEFB $46,$0F,$02, $45,$0F,$02, $44,$0F,$04
    DEFB $43,$0F,$04, $42,$0F,$08, $00

; --- Aguja de horas (radio 4) ---
HourHandPtrs:
    DEFW HourHand_0, HourHand_1, HourHand_2,  HourHand_3
    DEFW HourHand_4, HourHand_5, HourHand_6,  HourHand_7
    DEFW HourHand_8, HourHand_9, HourHand_10, HourHand_11

HourHand_0:
    DEFB $46,$0F,$01, $45,$0F,$01, $44,$0F,$01, $43,$0F,$01, $00
HourHand_1:
    DEFB $46,$10,$80, $45,$10,$80, $44,$10,$40, $00
HourHand_2:
    DEFB $46,$10,$80, $46,$10,$40, $45,$10,$20, $00
HourHand_3:
    DEFB $47,$10,$80, $47,$10,$40, $47,$10,$20, $47,$10,$10, $00
HourHand_4:
    DEFB $40,$30,$80, $40,$30,$40, $41,$30,$20, $00
HourHand_5:
    DEFB $40,$30,$80, $41,$30,$80, $42,$30,$40, $00
HourHand_6:
    DEFB $40,$2F,$01, $41,$2F,$01, $42,$2F,$01, $43,$2F,$01, $00
HourHand_7:
    DEFB $40,$2F,$02, $41,$2F,$02, $42,$2F,$04, $00
HourHand_8:
    DEFB $40,$2F,$02, $40,$2F,$04, $41,$2F,$08, $00
HourHand_9:
    DEFB $47,$0F,$02, $47,$0F,$04, $47,$0F,$08, $47,$0F,$10, $00
HourHand_10:
    DEFB $46,$0F,$02, $46,$0F,$04, $45,$0F,$08, $00
HourHand_11:
    DEFB $46,$0F,$02, $45,$0F,$02, $44,$0F,$04, $00

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
    ; --- Check 00:30 → spawnear monstruos ---
    LD A, (GameHours)
    OR A
    JR NZ, .noMonsterSpawn          ; No es hora 0
    LD A, (HL)                      ; HL = GameMinutes
    CP 30
    JR NZ, .noMonsterSpawn
    CALL SpawnMonsters
.noMonsterSpawn:
    LD A, (GameMinutes)
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
    PUSH AF
    CALL SetTimeOfDay
    POP AF
    OR A                                ; Fase 0 = DY (amanecer 7:00)?
    RET NZ
    ; Nuevo dia: incrementar ciclo
    LD HL, DayCycleCount
    INC (HL)
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
    LD HL, $470F            ; fila 0, col 15, scan 7
    RES 0, (HL)

    RET

; ==============================================================================
; DrawClockFaceOnly - Redibuja solo la esfera (cols 15-16, filas 22-23)
; ==============================================================================
; Salta los bytes de decoración (bytes 0-1 y 4-5 de cada fila del sprite)
; ==============================================================================
DrawClockFaceOnly:
    LD IX, BgGfx_hud_clock + 2  ; saltar cabecera

    LD H, $40
    LD L, $0F               ; col 15, scan 0, fila 0
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

    LD H, $40
    LD L, $2F               ; col 15, scan 0, fila 1
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

    ; Atributos de la esfera (filas 0-1, cols 15-16)
    LD A, $47              ; col 15: bright white
    LD ($580F), A
    LD ($582F), A
    LD A, $07              ; col 16: white
    LD ($5810), A
    LD ($5830), A
    RET

; ==============================================================================
; DrawClockSprite - Copia BgGfx_hud_clock al HUD (filas 22-23, cols 13-18)
; ==============================================================================
; Aplica CPL a cada byte (datos almacenados invertidos, como en DrawBgGfxSprite)
; ==============================================================================
DrawClockSprite:
    LD IX, BgGfx_hud_clock + 2  ; saltar cabecera height_px, width_bytes

    ; --- Filas 0-7 del sprite → fila 0, scans 0-7 ---
    LD H, $40
    LD L, $0D               ; col 13, scan 0
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

    ; --- Filas 8-15 del sprite → fila 1, scans 0-7 ---
    LD H, $40
    LD L, $2D               ; col 13, scan 0
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
    ; Layout: [dec0][dec1][sfera_L][sfera_R][dec2][dec3]
    ; Decoracion (cols 0,1,4,5): remap paper via ApplyDayCycleRemap
    ; Esfera (cols 2,3): sin remap (gestionada por DrawClockFaceOnly)
    INC IX                  ; saltar attr_h
    INC IX                  ; saltar attr_w
    XOR A
    LD (BgSpriteIsHouse), A ; clock no es house
    ; --- Fila 0 (row 0, cols 13-18) ---
    LD HL, $580D
    LD A, (IX+0)  : CALL ApplyDayCycleRemap : LD (HL), A : INC HL
    LD A, (IX+1)  : CALL ApplyDayCycleRemap : LD (HL), A : INC HL
    LD A, (IX+2)  :                           LD (HL), A : INC HL  ; esfera
    LD A, (IX+3)  :                           LD (HL), A : INC HL  ; esfera
    LD A, (IX+4)  : CALL ApplyDayCycleRemap : LD (HL), A : INC HL
    LD A, (IX+5)  : CALL ApplyDayCycleRemap : LD (HL), A
    ; --- Fila 1 (row 1, cols 13-18) ---
    LD HL, $582D
    LD A, (IX+6)  : CALL ApplyDayCycleRemap : LD (HL), A : INC HL
    LD A, (IX+7)  : CALL ApplyDayCycleRemap : LD (HL), A : INC HL
    LD A, (IX+8)  :                           LD (HL), A : INC HL  ; esfera
    LD A, (IX+9)  :                           LD (HL), A : INC HL  ; esfera
    LD A, (IX+10) : CALL ApplyDayCycleRemap : LD (HL), A : INC HL
    LD A, (IX+11) : CALL ApplyDayCycleRemap : LD (HL), A
    RET

; ==============================================================================
; DrawHealthStaminaHUD - Barra de salud (izq) y stamina (der) en decoraciones
; ==============================================================================
; Borra scanlines de arriba hacia abajo segun nivel (0-16).
; Decoraciones: 2 cols × 16 scanlines (8 en row 22 + 8 en row 23).
; Datos del sprite estan CPL'd → borrar = poner $FF en VRAM.
; ==============================================================================
DrawHealthStaminaHUD:
    ; --- Salud (izquierda: cols 13-14, sprite bytes 0-1 por scanline) ---
    LD A, (PlayerHealth)
    LD C, A                             ; C = nivel (0-16)
    LD HL, $400D                        ; Col 13, row 0, scan 0
    LD DE, $402D                        ; Col 13, row 1, scan 0
    LD IX, BgGfx_hud_clock + 2          ; Sprite data (skip header), offset 0
    CALL .drawBar

    ; --- Stamina (derecha: cols 17-18, sprite bytes 4-5 por scanline) ---
    LD A, (PlayerStamina)
    LD C, A
    LD HL, $4011                        ; Col 17, row 0, scan 0
    LD DE, $4031                        ; Col 17, row 1, scan 0
    LD IX, BgGfx_hud_clock + 2 + 4      ; Sprite data, offset 4 (cols 4-5)
    CALL .drawBar

    ; --- Flash de recuperacion del pozo ---
    LD A, (WellFlashTimer)
    OR A
    JR Z, .noFlash
    DEC A
    LD (WellFlashTimer), A
    ; Flash: alternar blanco/normal cada 4 frames
    AND $04
    JR Z, .noFlash
    ; Flash blanco brillante en ambas barras + player verde
    LD A, WHITE | $40
    LD ($580D), A
    LD ($580E), A
    LD ($582D), A
    LD ($582E), A
    LD ($5811), A
    LD ($5812), A
    LD ($5831), A
    LD ($5832), A
    LD A, GREEN | $40
    LD (EntityTable + ENT_ATTR), A
    RET
.noFlash:
    ; Restaurar color player si estaba en flash verde
    LD A, (EntityTable + ENT_ATTR)
    CP GREEN | $40
    JR NZ, .noFlashPlayer
    LD A, WHITE | $40
    LD (EntityTable + ENT_ATTR), A
.noFlashPlayer:
    ; --- Attrs segun nivel (normal) ---
    ; Salud
    LD A, (PlayerHealth)
    CALL .levelToColor
    LD ($580D), A
    LD ($580E), A
    LD ($582D), A
    LD ($582E), A
    ; Stamina
    LD A, (PlayerStamina)
    CALL .levelToColor
    LD ($5811), A
    LD ($5812), A
    LD ($5831), A
    LD ($5832), A
    RET

; --- Subrutina: redibujar decoracion completa y blanquear parte vacia ---
; C = nivel (0-16), HL = base col row 0, DE = base col row 1
; IX = puntero al primer byte de la decoracion en sprite data
; Redibuja 16 scanlines: las C inferiores con datos del sprite,
; las (16-C) superiores con $00 (vacio/negro)
.drawBar:
    LD A, L
    LD (.dbCol), A                      ; Guardar columna base row 0
    LD A, E
    LD (.dbCol1), A                     ; Guardar columna base row 1
    LD B, 16                            ; 16 scanlines totales
    LD D, 0                             ; D = scanline index (0 = arriba)
    ; Calcular umbral: scanlines 0..(15-C) = vacio, (16-C)..15 = lleno
    LD A, 16
    SUB C
    LD E, A                             ; E = primera scanline llena
.dbLoop:
    ; Calcular direccion VRAM
    LD A, D
    CP 8
    JR NC, .dbCalcR1
    ; Char row 0
    LD H, A
    SET 6, H
    LD A, (.dbCol)
    LD L, A
    JR .dbWrite
.dbCalcR1:
    ; Char row 1
    SUB 8
    LD H, A
    SET 6, H
    LD A, (.dbCol1)
    LD L, A
.dbWrite:
    ; D < E → vacio (blanquear), D >= E → lleno (sprite data)
    LD A, D
    CP E
    JR NC, .dbFull
    ; Vacio: escribir negro
    LD (HL), $00
    INC HL
    LD (HL), $00
    JR .dbAdvanceSpr
.dbFull:
    ; Lleno: copiar sprite data sin CPL (ya almacenado invertido)
    LD A, (IX+0)
    LD (HL), A
    INC HL
    LD A, (IX+1)
    LD (HL), A
.dbAdvanceSpr:
    ; Avanzar puntero sprite (siempre, 6 bytes por scanline)
    PUSH DE
    LD DE, 6
    ADD IX, DE
    POP DE
    INC D
    DJNZ .dbLoop
    RET

.dbCol:  DEFB 0
.dbCol1: DEFB 0

; --- Subrutina: nivel (A) → color attr (ink=color, paper=negro, bright) ---
.levelToColor:
    CP 12
    JR NC, .lcGreen
    CP 7
    JR NC, .lcCyan
    CP 3
    JR NC, .lcYellow
    LD A, RED | $40                     ; 0-2: rojo
    RET
.lcYellow:
    LD A, YELLOW | $40                  ; 3-6: amarillo
    RET
.lcCyan:
    LD A, CYAN | $40                    ; 7-11: cyan
    RET
.lcGreen:
    LD A, GREEN | $40                   ; 12-16: verde
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
