; ==============================================================================
; minimap_timed.asm - entry desde pickup MAP (id 184)
; ==============================================================================
; Vive en bank 5 (slot 1, always-visible). Movido aqui desde minimap.asm
; porque cuando vivia al final de bank 0 (slot 3) los simbolos de la mitad
; alta caian en la zona del stack normal (SP_ADDRESS=$FF58, peak ~$FE80).
; Los PUSH del juego durante gameplay corrompian mmRowTablePtr/mmRowTable
; y al recoger el pickup MAP el render se congelaba a mitad.
;
; Variante de ShowMinimap (M-key) pensada para el random pickup MAP_PICKUP_*:
;   - Muestra el minimapa MAP_PICKUP_DURATION_FRAMES (250 = 5 s @ 50 Hz).
;   - Tics beeper: 7 tics en frames 50/100/150/175/200/225/250 (3 lentos +
;     4 rapidos, smtTicFrames).
;   - Cualquier tecla cancela, pero solo tras un release inicial — para que
;     la tecla que el player llevara apretada al recoger el pickup no cierre
;     la pantalla en el primer frame.
;   - Encima del minimap, sprite 16x16 centrado horizontalmente que alterna
;     cam (179) ↔ cam_no (187) cada ~320 ms.
;
; Mismo SP swap + page-bank 0 que ShowMinimap. Comparte smRenderMap (render)
; y smMinimapCleanup (epilogo). Ambos viven en minimap.asm (bank 0); este
; archivo los llama via slot 3 paginado con _PageBank0.
;
; A diferencia de la entry M, aqui NO se llama PauseAy: al recoger el pickup
; MAP, .crsSpecialSfx acaba de disparar AY_PlayCompassPickup. Pausar el AY
; cortaria ese SFX en seco y al ResumeAy del cleanup el sweep se reanudaria
; — el usuario lo percibia como "el pickup suena al cerrar". Dejar el AY
; activo permite que el SFX termine naturalmente durante los primeros frames
; del minimapa. La musica de fondo sigue sonando los 5 s; los tics beeper
; conviven sobre el bit 4 de $FE sin tocar canales AY.
; ==============================================================================

ShowMinimapTimed:
    DI
    LD (smSavedSP), SP
    LD SP, PagingAltStackTop
    CALL _PageBank0
    ; NO smPreWaitRel — no entramos via tecla, el edge-detect del loop hace
    ; ese trabajo (smtHasReleased).

    PUSH HL
    PUSH DE
    PUSH BC
    PUSH AF

    DI                          ; render atomico vs IRQ (cleanup hara EI)

    CALL smRenderMap

    EI                          ; reactivar para HALT del loop

    ; --- Init estado del loop ---
    XOR A
    LD (smtFrame), A
    LD (smtTicIdx), A
    LD (smtHasReleased), A
    LD A, $FF
    LD (smtOverlayBit), A       ; fuerza primer pintado del overlay

.smtLoop:
    HALT                        ; espera 1 frame (50 Hz IRQ)

    ; --- Periodo de gracia: ignorar input los primeros MIN_VIEW_FRAMES ---
    ; Defensa contra joystick drift / direcciones pulsadas por inercia que
    ; cerraban el mapa antes de que el player pudiera leerlo. Durante la
    ; gracia, smtHasReleased se queda en 0 (estado inicial) — al salir de
    ; gracia el player tiene que liberar antes que su siguiente pulsacion
    ; cuente como cierre.
    LD A, (smtFrame)
    CP MAP_PICKUP_MIN_VIEW_FRAMES
    JR C, .smtAfterInput

    ; --- Input edge detection (cualquier tecla tras un release) ---
    CALL smtAnyKeyDown          ; A != 0 si alguna tecla pulsada
    JR Z, .smtNoKey
    LD A, (smtHasReleased)
    OR A
    JR Z, .smtAfterInput        ; aun no liberó → ignorar pulsación
    JP smMinimapCleanup         ; release+press → cerrar
.smtNoKey:
    LD A, 1
    LD (smtHasReleased), A
.smtAfterInput:

    ; --- Avanzar frame counter ---
    LD HL, smtFrame
    INC (HL)
    LD A, (HL)
    LD B, A                     ; B = frame actual (1..250)

    ; --- ¿Toca tic? smtTicFrames[smtTicIdx] == B? ---
    LD A, (smtTicIdx)
    CP 7                        ; idx >= 7 → ya disparamos los 7 tics
    JR NC, .smtCheckEnd
    LD E, A
    LD D, 0
    LD HL, smtTicFrames
    ADD HL, DE
    LD A, (HL)
    CP B
    JR NZ, .smtCheckEnd
    PUSH BC
    CALL FireBuffNormal         ; beeper tic (~10 ms, no bloquea IRQ)
    POP BC
    LD HL, smtTicIdx
    INC (HL)

.smtCheckEnd:
    CALL UpdateOverlayAnim      ; alterna cam (179) ↔ cam_no (187) c/ ~320 ms
    LD A, (smtFrame)
    CP MAP_PICKUP_DURATION_FRAMES
    JR C, .smtLoop
    JP smMinimapCleanup         ; timeout 5 s → cerrar

; --- Datos del loop timed (slot 1 bank 5, fuera de stack peak) -----------------
; smtTicFrames: cada DEFB es el frame absoluto en el que disparar el N-esimo
; tic. Primeros 3 cada 50 frames (1 s); ultimos 4 cada 25 frames (0.5 s).
smtTicFrames:
    DEFB MAP_PICKUP_TICK_SLOW_PERIOD * 1                            ; 50
    DEFB MAP_PICKUP_TICK_SLOW_PERIOD * 2                            ; 100
    DEFB MAP_PICKUP_TICK_SLOW_PERIOD * 3                            ; 150
    DEFB MAP_PICKUP_SLOW_PHASE_FRAMES + MAP_PICKUP_TICK_FAST_PERIOD * 1  ; 175
    DEFB MAP_PICKUP_SLOW_PHASE_FRAMES + MAP_PICKUP_TICK_FAST_PERIOD * 2  ; 200
    DEFB MAP_PICKUP_SLOW_PHASE_FRAMES + MAP_PICKUP_TICK_FAST_PERIOD * 3  ; 225
    DEFB MAP_PICKUP_SLOW_PHASE_FRAMES + MAP_PICKUP_TICK_FAST_PERIOD * 4  ; 250

smtFrame:        DEFB 0
smtTicIdx:       DEFB 0
smtHasReleased:  DEFB 0
smtOverlayBit:   DEFB $FF        ; bit 4 de smtFrame en la pasada anterior; $FF = aun no pintado

; ------------------------------------------------------------------------------
; UpdateOverlayAnim - alterna sprite cam (179) ↔ cam_no (187) sobre el minimap.
; ------------------------------------------------------------------------------
; Sprite 16x16 centrado horizontalmente sobre el minimap (char col 15-16, row
; 2-3 = pixel y 16..31). Alterna frame cada ~320 ms (bit 4 de smtFrame, 16
; frames @ 50 Hz). Repinta tanto pixels como attrs (179 / 187).
;
; Tail-call a PaintIcon16x16 (splash_wait.asm, slot 1 always-visible).
; Destruye: AF, BC, DE, HL.
; ------------------------------------------------------------------------------
UpdateOverlayAnim:
    LD A, (smtFrame)
    AND $10                     ; bit 4 → toggle cada 16 frames
    LD HL, smtOverlayBit
    CP (HL)
    RET Z                       ; sin cambio
    LD (HL), A

    PUSH AF                     ; salvar phase para la fase blink attrs

    ; --- Cam overlay (cam 179 ↔ cam_no 187) ---
    OR A
    JR Z, .uoaFrameA
.uoaFrameB:
    LD DE, MinimapOverlayPixels + 32        ; sprite 187 pixels
    LD HL, MinimapOverlayAttrs + 4          ; sprite 187 attrs
    JR .uoaApply
.uoaFrameA:
    LD DE, MinimapOverlayPixels             ; sprite 179 pixels
    LD HL, MinimapOverlayAttrs              ; sprite 179 attrs
.uoaApply:
    ; --- Pintar attrs (4 B en layout TL, TR, BL, BR) ---
    PUSH DE                                 ; save pixels src
    LD DE, MINIMAP_OVERLAY_ATTR_TL
    LD BC, 2
    LDIR                                    ; HL += 2 (TL, TR)
    LD DE, MINIMAP_OVERLAY_ATTR_BL
    LD BC, 2
    LDIR                                    ; (BL, BR)
    POP DE                                  ; restore pixels src
    ; --- Pintar pixels (32 B row-major en VRAM) ---
    LD HL, MINIMAP_OVERLAY_PX_ADDR
    CALL PaintIcon16x16                     ; (slot 1, NextPixelLine bank 2)

    ; --- Blink attrs: player + milestone (goal) alternan bright ↔ dim ---
    ; phase A (bit clear) → bright ($78 player, $50 goal) — los del render normal.
    ; phase B (bit set)   → dim    ($38 player, $10 goal) — bright off, mismo paper.
    ; Sin cambio del paper visual, solo el bit 6 (bright) parpadea — efecto
    ; "pulse" sutil sincronizado con la animacion de la camara.
    POP AF                                  ; restore phase (NZ = phase B)
    OR A
    JR NZ, .uoaBlinkDim
.uoaBlinkBright:
    LD BC, (MM_GOAL << 8) | MM_PLAYER       ; B=$50 goal, C=$78 player
    JR .uoaBlinkApply
.uoaBlinkDim:
    LD BC, $1038                            ; B=$10 goal dim, C=$38 player dim
.uoaBlinkApply:
    ; --- Player attr cell ---
    LD A, (mmPlayerY)
    LD D, A
    LD A, (mmPlayerX)
    LD E, A
    CALL ComputeMinimapAttrAddr
    LD (HL), C                              ; player attr
    ; --- Goal attr cell (si hay milestone) ---
    LD A, (mmObjY)
    CP $FF
    RET Z                                   ; sin milestone activo
    LD D, A
    LD A, (mmObjX)
    LD E, A
    CALL ComputeMinimapAttrAddr
    LD (HL), B                              ; goal attr
    RET

; ------------------------------------------------------------------------------
; ComputeMinimapAttrAddr - traduce (X, Y) en char del minimap a addr VRAM attr.
; ------------------------------------------------------------------------------
; IN:  D = Y (0..15), E = X (0..15)
; OUT: HL = MINIMAP_ATTR_BASE + Y*32 + X
; Destruye: AF, DE, HL.
; ------------------------------------------------------------------------------
ComputeMinimapAttrAddr:
    LD H, 0
    LD L, D
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; HL = Y * 32
    LD D, 0
    ADD HL, DE                              ; HL = Y*32 + X
    LD DE, MINIMAP_ATTR_BASE
    ADD HL, DE
    RET

; --- Constantes del overlay (calculadas a mano) -------------------------------
; Centrado horizontalmente sobre el minimap (que ocupa char col 8..23):
;   col char 15..16 → 2 chars wide centrados (col med = 15.5)
;   row char 0..1   → pegado al borde superior de la pantalla
; Pixel addr top-left: vram_pixel_addr(col=15, y=0)
;   third=0, sub_y=0, cell_y=0 → H=$40, L=(0<<5)|15=$0F → $400F
MINIMAP_OVERLAY_PX_ADDR  EQU $4000 | 15            ; = $400F
MINIMAP_OVERLAY_ATTR_TL  EQU $5800 + 0 * 32 + 15   ; = $580F
MINIMAP_OVERLAY_ATTR_BL  EQU MINIMAP_OVERLAY_ATTR_TL + 32  ; = $582F

; --- Datos pre-extraidos por tools/build_minimap_overlay.py -------------------
; Layout: [0..31]=179 px, [32..63]=187 px, [64..67]=179 attrs, [68..71]=187 attrs.
MinimapOverlayPixels:
    INCBIN "minimap_overlay.bin", 0, 64
MinimapOverlayAttrs:
    INCBIN "minimap_overlay.bin", 64, 8

; ------------------------------------------------------------------------------
; smtAnyKeyDown - polling no-bloqueante de Kempston + 8 filas teclado.
; ------------------------------------------------------------------------------
; OUT: A=0/Z idle, A!=0/NZ alguna tecla o joystick pulsado.
; Destruye: A, BC.
;
; Kempston: si bus flotante ($1F→$FF) ignorar. Resto: WIRED-OR de las 8 half-
; rows con CPL para que bit=1 sea "pulsada"; AND $1F descarta CAPS/SYM y bits
; no usados. RET tan pronto haya un hit (corto-circuit).
; ------------------------------------------------------------------------------
smtAnyKeyDown:
    IN A, ($1F)
    AND $1F
    CP $1F
    JR Z, .akKbd                ; bus flotante → ignorar
    OR A
    RET NZ                      ; Kempston pulsado
.akKbd:
    LD BC, $FEFE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $FDFE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $FBFE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $F7FE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $EFFE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $DFFE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $BFFE : IN A, (C) : CPL : AND $1F : RET NZ
    LD BC, $7FFE : IN A, (C) : CPL : AND $1F
    RET
