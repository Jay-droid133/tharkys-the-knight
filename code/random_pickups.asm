; ==============================================================================
; RANDOM PICKUPS — rutinas Give (slot 1, cold path)
; ==============================================================================
; Sistema: cada plantilla puede llevar hasta RANDOM_SLOT_MAX placements con id
; RANDOM_SLOT_MARKER (210). Al entrar a una sala se elige un slot via RNG y se
; rolea su contenido (life / health / stamina / nada) por probabilidad. El
; pickup elegido aparece en pantalla; al recogerlo se llama a la Give
; correspondiente desde CheckPickupCollect.
;
; Las Give routines tambien cubren placements explicitos de life/health/stamina
; si en el futuro se ponen pickups fijos en el editor.
;
; Vive en slot 1 (cold path): solo se invoca al recoger un pickup raro.
; Bank 0/2 quedan limpios.
; ==============================================================================

; ==============================================================================
; GiveLife - +1 vida, clamp a PLAYER_LIVES_MAX
; ==============================================================================
; HUD se refresca solo: DrawLivesHUD se llama cada frame en MainLoop y detecta
; el cambio via cache .dlhLast.
; ==============================================================================
GiveLife:
    LD A, (PlayerLives)
    CP PLAYER_LIVES_MAX
    RET NC                              ; ya en max (>= MAX) -> no-op
    INC A
    LD (PlayerLives), A
    RET

; ==============================================================================
; GiveHealth - +PICKUP_HEALTH_AMT, clamp a HEALTH_MAX
; ==============================================================================
; HUD se refresca solo via DrawHealthStaminaHUD (lee PlayerHealth cada frame).
; ==============================================================================
GiveHealth:
    LD A, (PlayerHealth)
    ADD A, PICKUP_HEALTH_AMT
    JR C, .ghCap                        ; overflow 8-bit -> definitivo cap
    CP HEALTH_MAX + 1
    JR C, .ghStore                      ; A <= HEALTH_MAX
.ghCap:
    LD A, HEALTH_MAX
.ghStore:
    LD (PlayerHealth), A
    RET

; ==============================================================================
; GiveStamina - +PICKUP_STAMINA_AMT, clamp a STAMINA_MAX
; ==============================================================================
GiveStamina:
    LD A, (PlayerStamina)
    ADD A, PICKUP_STAMINA_AMT
    JR C, .gsCap
    CP STAMINA_MAX + 1
    JR C, .gsStore
.gsCap:
    LD A, STAMINA_MAX
.gsStore:
    LD (PlayerStamina), A
    RET

; ==============================================================================
; UpdateRandomPickup - room-enter hook
; ==============================================================================
; Llamado por MainLoop entre CheckScreenTransition y DrawScreen, cada frame.
; Early-out si ScreenDirty=0 (no transition).
;
; En transition:
;   1. Recorre el BG stream de la sala actual (CurrentScreenAddr) buscando
;      placements id=RANDOM_SLOT_MARKER. Acumula (charX, charY) en RandomSlotList.
;   2. Si count > 0: RNG slot, RNG tipo. Si tipo != none, rellena
;      RandomSyntheticEntry con la pickup elegida en la posicion del slot.
;      Si tipo == none o count == 0, marca inactiva ($FE).
;
; Buffer format (CurrentScreenAddr → CurrentScreenBuffer): entries de 4 bytes
; fijos (id, charX, charY, v) terminados con id=$FF.
;
; Destruye AF, BC, DE, HL.
; ==============================================================================
UpdateRandomPickup:
    LD A, (ScreenDirty)
    OR A
    RET Z

    ; --- Default: synthetic entry inactiva (sera reactivada si roll spawneara) ---
    LD A, $FE
    LD (RandomSynthMapX), A

    ; --- Scan BG stream, build SlotList ---
    XOR A
    LD (RandomSlotCount), A
    LD HL, (CurrentScreenAddr)
.urpScanLoop:
    LD A, (HL)                          ; A = id
    CP $FF
    JR Z, .urpScanDone
    CP RANDOM_SLOT_MARKER
    JR NZ, .urpSkipEntry
    ; Es marker. Cap reached?
    LD A, (RandomSlotCount)
    CP RANDOM_SLOT_MAX
    JR NC, .urpSkipEntry
    ; SlotList[count*2] = charX, [count*2+1] = charY
    INC HL                              ; HL @ charX
    LD B, (HL)                          ; B = charX
    INC HL                              ; HL @ charY
    LD C, (HL)                          ; C = charY
    PUSH HL                             ; save HL @ charY
    ADD A, A                            ; A = count*2
    LD L, A
    LD H, 0
    LD DE, RandomSlotList
    ADD HL, DE
    LD (HL), B                          ; charX
    INC HL
    LD (HL), C                          ; charY
    LD HL, RandomSlotCount
    INC (HL)
    POP HL                              ; HL @ charY
    INC HL                              ; HL @ v
    INC HL                              ; HL @ next id
    JR .urpScanLoop
.urpSkipEntry:
    ; Skip entry: 4 bytes (id, charX, charY, v).
    INC HL : INC HL : INC HL : INC HL
    JR .urpScanLoop
.urpScanDone:

    ; --- count == 0 -> nada que hacer ---
    LD A, (RandomSlotCount)
    OR A
    RET Z

    ; --- Pick slot via R mod count ---
    LD B, A                             ; B = count
    LD A, R
.urpModLoop:
    SUB B
    JR NC, .urpModLoop
    ADD A, B                            ; A = R mod count, [0..count-1]

    ; --- Read SlotList[A*2] = (charX, charY) ---
    ADD A, A
    LD E, A
    LD D, 0
    LD HL, RandomSlotList
    ADD HL, DE
    LD A, (HL)                          ; charX
    LD (RandomSynthCharX), A
    INC HL
    LD A, (HL)                          ; charY
    LD (RandomSynthCharY), A

    ; --- Roll type usando R XOR SYS_FRAMES ---
    LD A, R
    LD HL, $5C78
    XOR (HL)
    CP PROB_LIFE_END
    JR C, .urpDoLife
    CP PROB_HEALTH_END
    JR C, .urpDoHealth
    CP PROB_STAMINA_END
    JR C, .urpDoStamina
    RET                                 ; tipo nada, RandomSynthMapX ya esta a $FE
.urpDoLife:
    LD HL, BgGfx_life
    JR .urpActivate
.urpDoHealth:
    LD HL, BgGfx_health_pickup
    JR .urpActivate
.urpDoStamina:
    LD HL, BgGfx_stamina_pickup
.urpActivate:
    LD (RandomSynthPtr), HL             ; ptr al sprite elegido
    LD A, (CurrentScreenX)
    LD (RandomSynthMapX), A             ; activa la entry
    LD A, (CurrentScreenY)
    LD (RandomSynthMapY), A
    LD A, $FF
    LD (RandomSynthTint), A             ; sin tint
    RET

; ==============================================================================
; PaintSynthPickupAttrs - Pinta attrs hardcoded del random pickup en VRAM
; ==============================================================================
; Se llama desde:
;   - .pkDrawDone (DrawScreen): tras dibujar pixels del synth.
;   - MainLoop tras RefreshPickupAttrs: para repintar attrs si un enemigo paso
;     por encima y los borro.
;
; Bypass total de tint swap + day/night remap → siempre brillan:
;   life          = $47 (white bright, paper black)
;   health_pickup = $42 (red bright,   paper black)
;   stamina_pickup= $45 (cyan bright,  paper black)
;
; Pickup es 16x16 = 2x2 char attrs.
; Early-out si RandomSynthMapX = $FE (no activo).
; Destruye AF, BC, DE, HL.
; ==============================================================================
PaintSynthPickupAttrs:
    LD A, (RandomSynthMapX)
    CP $FE
    RET Z                               ; no activo
    ; --- Determinar attr byte por tipo (compara ptr) ---
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_life
    OR A
    SBC HL, DE
    LD A, $47                           ; white bright (life)
    JR Z, .pspaAttrReady
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_health_pickup
    OR A
    SBC HL, DE
    LD A, $42                           ; red bright (health)
    JR Z, .pspaAttrReady
    LD A, $45                           ; cyan bright (stamina)
.pspaAttrReady:
    LD C, A                             ; C = attr byte
    ; --- Calcular VRAM addr fila 0 = ATTR_BASE + (charY+BG_Y_OFFSET)*32 + charX ---
    LD A, (RandomSynthCharY)
    ADD A, BG_Y_OFFSET
    LD H, 0
    LD L, A
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; *32
    LD A, (RandomSynthCharX)
    ADD A, L
    LD L, A
    JR NC, .pspaNoCarry
    INC H
.pspaNoCarry:
    LD DE, ATTR_BASE
    ADD HL, DE                          ; HL = VRAM addr fila 0, col 0
    ; --- Escribir 4 attrs (2x2) ---
    LD (HL), C
    INC HL
    LD (HL), C                          ; fila 0
    LD A, L
    ADD A, 31                           ; +32 a fila siguiente, -1 (al col 0)
    LD L, A
    JR NC, .pspaNoCarry2
    INC H
.pspaNoCarry2:
    LD (HL), C
    INC HL
    LD (HL), C                          ; fila 1
    RET

; ==============================================================================
; CheckRandomSyntheticPickup - colision + collect del pickup sintetico
; ==============================================================================
; Llamada por CheckPickupCollect tras procesar PickupTable. Si la entry
; sintetica esta activa, hace AABB contra el player. Si hay hit:
;   - SFX_Pickup
;   - Erase XOR + restore attrs
;   - Mark inactiva ($FE)
;   - Dispatch GiveLife/GiveHealth/GiveStamina segun RandomSynthPtr
; ==============================================================================
CheckRandomSyntheticPickup:
    LD A, (RandomSynthMapX)
    CP $FE
    RET Z                               ; inactiva
    ; Sanity: solo procesar si estamos en su sala (deberia ser asi tras hook).
    LD B, A
    LD A, (CurrentScreenX)
    CP B
    RET NZ
    LD A, (RandomSynthMapY)
    LD B, A
    LD A, (CurrentScreenY)
    CP B
    RET NZ

    ; --- Cargar sprite a BgSpriteBuffer (header + pixels + attrs) ---
    LD HL, (RandomSynthPtr)
    LD A, 3                             ; bank 3
    CALL LoadBgSpriteToBuffer

    ; --- Calcular pk_left, pk_top, pk_width_px, pk_height_px ---
    LD HL, BgSpriteBuffer
    LD A, (HL)                          ; height_px
    LD (.crsPkH+1), A
    INC HL
    LD A, (HL)
    AND $7F                             ; width_bytes (sin flag RLE)
    ADD A, A
    ADD A, A
    ADD A, A                            ; width_px = bytes*8
    LD (.crsPkW+1), A
    LD A, (RandomSynthCharX)
    ADD A, A
    ADD A, A
    ADD A, A                            ; pk_left = charX*8
    LD (.crsPkLeft+1), A
    LD A, (RandomSynthCharY)
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A                            ; pk_top = (charY+BG_Y_OFFSET)*8
    LD (.crsPkTop+1), A

    ; --- AABB: player_right > pk_left AND player_left < pk_right
    ;          AND player_bottom > pk_top AND player_top < pk_bottom ---
    LD A, (EntityTable + ENT_POSX)
    LD (.crsPlX+1), A
.crsPlX:
    LD A, 0                             ; player_left (self-mod)
    ADD A, 16                           ; player_right
.crsPkLeft:
    LD B, 0
    CP B
    RET C                               ; player_right <= pk_left -> miss
    RET Z
.crsPkW:
    LD A, 0                             ; pk_width
    ADD A, B                            ; pk_right
    LD B, A
    LD A, (.crsPlX+1)
    CP B
    RET NC                              ; player_left >= pk_right -> miss

    LD A, (EntityTable + ENT_POSY)
    LD (.crsPlY+1), A
.crsPlY:
    LD A, 0                             ; player_top
    ADD A, 21                           ; player_bottom (player es 21 alto)
.crsPkTop:
    LD B, 0
    CP B
    RET C
    RET Z
.crsPkH:
    LD A, 0                             ; pk_height
    ADD A, B                            ; pk_bottom
    LD B, A
    LD A, (.crsPlY+1)
    CP B
    RET NC                              ; miss

    ; --- HIT: SFX + erase + attrs + apply effect + mark inactive ---
    LD HL, SFX_Pickup
    CALL PlaySFX

    ; Erase: XOR redraw (sprite ya esta en BgSpriteBuffer)
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    POP BC                              ; B=charX, C=charY

    ; Restore attrs: D=height_chars, E=width_chars
    LD HL, BgSpriteBuffer
    LD A, (HL)                          ; height_px
    RRCA : RRCA : RRCA
    AND $1F
    LD D, A
    INC HL
    LD A, (HL)
    AND $7F
    LD E, A
    CALL RestorePickupAttrs

    ; Mark inactive
    LD A, $FE
    LD (RandomSynthMapX), A

    ; Dispatch GiveX por ptr
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_life
    OR A
    SBC HL, DE
    JP Z, GiveLife
    LD HL, (RandomSynthPtr)
    LD DE, BgGfx_health_pickup
    OR A
    SBC HL, DE
    JP Z, GiveHealth
    JP GiveStamina                      ; fallthrough: si no es life/health, debe ser stamina
