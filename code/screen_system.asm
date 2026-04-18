; ==============================================================================
; SISTEMA DE PANTALLAS (estilo Sabre Wulf - flick-screen)
; ==============================================================================
; Mapa de 256 pantallas (16x16). Cada pantalla es un "room" definido como
; lista de sprites de fondo (BgSprites). La colision se hace iterando la
; lista de sprites del room actual (como la rutina B873 de Sabre Wulf).
; ==============================================================================

; ==============================================================================
; InitScreenSystem - Inicializa el sistema de pantallas
; ==============================================================================
InitScreenSystem:
    LD A, START_SCREEN_X
    LD (CurrentScreenX), A
    LD A, START_SCREEN_Y
    LD (CurrentScreenY), A
    LD A, 1
    LD (ScreenDirty), A         ; Forzar dibujado inicial
    XOR A
    LD (ScreenTransition), A
    CALL CalcScreenAddress
    RET

; ==============================================================================
; CalcScreenAddress - Lee MapTable y RoomTable para obtener puntero al room
; ==============================================================================
; MapTable[Y*16+X] = indice de room -> RoomTable[indice] = puntero a room data
; ==============================================================================
CalcScreenAddress:
    LD A, (CurrentScreenY)
    LD L, A
    LD H, 0
    ADD HL, HL                  ; x2
    ADD HL, HL                  ; x4
    ADD HL, HL                  ; x8
    ADD HL, HL                  ; x16
    LD A, (CurrentScreenX)
    LD E, A
    LD D, 0
    ADD HL, DE                  ; HL = Y*16 + X
    LD DE, MapTable
    ADD HL, DE                  ; HL = &MapTable[index]
    LD A, (HL)                  ; A = room index (0-47)
    ; Lookup en RoomTable (tabla de DEFWs)
    LD L, A
    LD H, 0
    ADD HL, HL                  ; index * 2
    LD DE, RoomTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = puntero a Room_Txx (en bank 1)
    ; Copiar room data desde bank 1 al buffer en RAM fija
    EX DE, HL                   ; HL = Room_Txx ptr
    CALL LoadRoomToBuffer       ; pagina bank 1, copia, repagina bank 0
    ; CurrentScreenAddr apunta al buffer, no al original en bank 1
    LD DE, CurrentScreenBuffer
    LD (CurrentScreenAddr), DE
    RET

; ==============================================================================
; CheckScreenTransition - Detecta si el jugador debe cambiar de pantalla
; ==============================================================================
; Cada direccion solo se comprueba si el player esta ACTIVAMENTE pulsando
; esa direccion en el input. Asi nunca se dispara una transicion no intencionada
; por estar atrapado cerca del borde.
; ==============================================================================
CheckScreenTransition:
    XOR A
    LD (ScreenTransition), A

    LD A, (InputDirection)
    LD D, A                     ; D = input direction (bits 0-3: N S E W)

    ; --- Comprobar borde OESTE (solo si pulsa W) ---
    BIT 3, D                    ; W
    JP Z, .noWest
    LD A, (EntityTable + ENT_POSX)
    CP TRANSITION_ZONE
    JP NC, .noWest
    LD A, (CurrentScreenX)
    OR A
    JP Z, .noWest
    ; Check collision at col 0 (top + mid + bottom del player)
    LD B, 0
    LD A, (EntityTable + ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JP NZ, .noWest
    LD B, 0
    LD A, (EntityTable + ENT_POSY)
    ADD A, 10
    LD C, A
    CALL IsPointBlocked
    JP NZ, .noWest
    LD B, 0
    LD A, (EntityTable + ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    JP NZ, .noWest
    LD A, (CurrentScreenX)
    DEC A
    LD (CurrentScreenX), A
    LD A, DIR_W
    LD (ScreenTransition), A
    LD A, SCREEN_MAX_X
    LD (EntityTable + ENT_POSX), A
    JP .doTransition

.noWest:
    ; --- Comprobar borde ESTE (solo si pulsa E) ---
    BIT 2, D                    ; E
    JP Z, .noEast
    LD A, (EntityTable + ENT_POSX)
    CP SCREEN_MAX_X
    JP C, .noEast
    LD A, (CurrentScreenX)
    CP MAP_WIDTH - 1
    JP Z, .noEast
    ; Check collision at col 31 (top + mid + bottom del player)
    LD B, 248
    LD A, (EntityTable + ENT_POSY)
    LD C, A
    CALL IsPointBlocked
    JP NZ, .noEast
    LD B, 248
    LD A, (EntityTable + ENT_POSY)
    ADD A, 10
    LD C, A
    CALL IsPointBlocked
    JP NZ, .noEast
    LD B, 248
    LD A, (EntityTable + ENT_POSY)
    ADD A, 20
    LD C, A
    CALL IsPointBlocked
    JP NZ, .noEast
    LD A, (CurrentScreenX)
    INC A
    LD (CurrentScreenX), A
    LD A, DIR_E
    LD (ScreenTransition), A
    LD A, SCREEN_MIN_X
    LD (EntityTable + ENT_POSX), A
    JP .doTransition

.noEast:
    ; --- Comprobar borde NORTE (solo si pulsa N) ---
    BIT 0, D                    ; N
    JP Z, .noNorth
    LD A, (EntityTable + ENT_POSY)
    CP SCREEN_MIN_Y + TRANSITION_ZONE
    JP NC, .noNorth
    LD A, (CurrentScreenY)
    OR A
    JP Z, .noNorth
    ; Check collision at row 0 (left + mid + right del player)
    LD A, (EntityTable + ENT_POSX)
    LD B, A
    LD C, SCREEN_MIN_Y
    CALL IsPointBlocked
    JP NZ, .noNorth
    LD A, (EntityTable + ENT_POSX)
    ADD A, 7
    LD B, A
    LD C, SCREEN_MIN_Y
    CALL IsPointBlocked
    JP NZ, .noNorth
    LD A, (EntityTable + ENT_POSX)
    ADD A, 15
    LD B, A
    LD C, SCREEN_MIN_Y
    CALL IsPointBlocked
    JP NZ, .noNorth
    LD A, (CurrentScreenY)
    DEC A
    LD (CurrentScreenY), A
    LD A, DIR_N
    LD (ScreenTransition), A
    LD A, SCREEN_MAX_Y
    LD (EntityTable + ENT_POSY), A
    JP .doTransition

.noNorth:
    ; --- Comprobar borde SUR (solo si pulsa S) ---
    BIT 1, D                    ; S
    JP Z, .noSouth
    LD A, (EntityTable + ENT_POSY)
    CP SCREEN_MAX_Y
    JP C, .noSouth
    LD A, (CurrentScreenY)
    CP MAP_HEIGHT - 1
    JP Z, .noSouth
    ; Check collision at row 21 (left + mid + right del player)
    LD A, (EntityTable + ENT_POSX)
    LD B, A
    LD C, SCREEN_MAX_Y
    CALL IsPointBlocked
    JP NZ, .noSouth
    LD A, (EntityTable + ENT_POSX)
    ADD A, 7
    LD B, A
    LD C, SCREEN_MAX_Y
    CALL IsPointBlocked
    JP NZ, .noSouth
    LD A, (EntityTable + ENT_POSX)
    ADD A, 15
    LD B, A
    LD C, SCREEN_MAX_Y
    CALL IsPointBlocked
    JP NZ, .noSouth
    LD A, (CurrentScreenY)
    INC A
    LD (CurrentScreenY), A
    LD A, DIR_S
    LD (ScreenTransition), A
    LD A, SCREEN_MIN_Y
    LD (EntityTable + ENT_POSY), A
    JP .doTransition

.doTransition:
    LD A, (ScreenTransition)
    LD (LastScreenTransition), A
    ; Guardar posicion del player al entrar (unico punto seguro para monsters)
    LD A, (EntityTable + ENT_POSX)
    LD (LastEntryPosX), A
    LD A, (EntityTable + ENT_POSY)
    LD (LastEntryPosY), A
    CALL CalcScreenAddress
    CALL ClearNasties           ; Limpiar enemigos al cambiar de pantalla
    CALL RepositionMonstersAtEntry ; Monsters siguen al player desde la pantalla anterior
    ; SFX de transicion de pantalla (comentado para pruebas)
    ; LD HL, SFX_ScreenTransition
    ; CALL PlaySFX
    XOR A
    LD (PendingEraseCount), A   ; Cancelar erases pendientes (pantalla se borra)
    LD A, 1
    LD (ScreenDirty), A
    LD (ScreenJustRedrawn), A
.noSouth:
    RET

; ==============================================================================
; ClearNasties - Limpia todos los slots de nasties (enemigos destruibles)
; ==============================================================================
; Los nasties no persisten entre pantallas (como en Sabre Wulf).
; ==============================================================================
ClearNasties:
    LD HL, EntityTable + (SLOT_NASTY0 * ENT_SIZE)
    LD B, NUM_NASTIES
.clearLoop:
    PUSH BC
    PUSH HL
    LD (HL), 0                  ; ENT_SPRITEID = 0
    INC HL
    LD (HL), 0                  ; ENT_TYPE = 0 (inactivo)
    POP HL
    LD DE, ENT_SIZE
    ADD HL, DE
    POP BC
    DJNZ .clearLoop
    ; Reset spawn timer para nueva pantalla (delay antes de nasties)
    LD A, SPAWN_INTERVAL
    LD (SpawnTimer), A
    RET

; ==============================================================================
; DrawScreen - Dibuja la pantalla actual iterando BG sprites
; ==============================================================================
; Formato room: DEFW BgGfx_ptr : DEFB x_char, y_char ... DEFW $0000
; Formato BgGfx: DEFB height_px, width_bytes, pixel_data(CPL),
;                DEFB attr_h, attr_w, attr_data
; Solo se ejecuta cuando ScreenDirty=1 (cambio de pantalla).
; ==============================================================================
DrawScreen:
    LD A, (ScreenDirty)
    OR A
    RET Z

    ; --- Reset well / plaza clock detection ---
    XOR A
    LD (WellActive), A
    LD (PlazaClockActive), A
    LD A, $FF
    LD (PlazaLastHour), A       ; forzar redibujado al entrar en room
    LD (PlazaLastMin), A

    ; --- Limpiar pixeles ---
    LD HL, SCREEN_BASE
    LD DE, SCREEN_BASE + 1
    LD BC, 6143
    XOR A
    LD (HL), A
    LDIR

    ; --- Limpiar atributos: ink=WHITE, paper=BLACK ---
    LD HL, ATTR_BASE
    LD DE, ATTR_BASE + 1
    LD BC, ATTR_SIZE - 1
    LD A, $07
    LD (HL), A
    LDIR

    ; --- Iterar sprites del room ---
    LD HL, (CurrentScreenAddr)
.sprLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .drawDone

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    LD A, (HL)                  ; A = tint variant (255=none)
    INC HL
    LD (CurrentTintVar), A
    PUSH HL                     ; Guardar puntero room data

    ; Comprobar si es sprite tipo "house" (para day cycle)
    CALL CheckIfHouseSprite

    ; Comprobar si es pozo: guardar posicion para recuperacion
    PUSH HL                     ; Preservar room data ptr (ya en stack via PUSH HL arriba)
    PUSH BC                     ; Preservar x_char, y_char
    LD HL, BgGfx_well_pozo
    OR A
    SBC HL, DE                  ; HL = 0 si coincide
    POP BC
    POP HL
    JR NZ, .notWell
    ; Es pozo: guardar posicion en pixeles
    LD A, B                     ; x_char
    ADD A, A                    ; *2
    ADD A, A                    ; *4
    ADD A, A                    ; *8
    LD (WellPosX), A
    LD A, C                     ; y_char
    ADD A, BG_Y_OFFSET          ; + offset HUD
    ADD A, A                    ; *2
    ADD A, A                    ; *4
    ADD A, A                    ; *8
    LD (WellPosY), A
    LD A, 1
    LD (WellActive), A
.notWell:

    ; Comprobar si es reloj de plaza
    PUSH HL
    PUSH BC
    LD HL, BgGfx_reloj_plaza
    OR A
    SBC HL, DE
    POP BC
    POP HL
    JR NZ, .notPlazaClock
    LD A, B
    LD (PlazaClockCharX), A
    LD A, C
    ADD A, BG_Y_OFFSET
    LD (PlazaClockCharY), A
    LD A, 1
    LD (PlazaClockActive), A
    PUSH DE
    PUSH BC
    CALL BuildPlazaScanAddrs
    CALL LoadPlazaClockPixels   ; cachear pixel data para DrawPlazaClock per-frame
    POP BC
    POP DE
.notPlazaClock:

    ; DE = puntero a BgGfx sprite data (en bank 3). Cargar al buffer primero.
    EX DE, HL                   ; HL = BgGfx ptr
    CALL LoadBgSpriteToBuffer   ; copia 256 B a BgSpriteBuffer
    LD IX, BgSpriteBuffer
    CALL DrawBgGfxSprite

    POP HL
    JR .sprLoop

.drawDone:
    ; --- Dibujar objetos per-cell desde ObjectTable ---
    LD HL, ObjectTable
.objDrawLoop:
    LD A, (HL)
    CP $FF
    JR Z, .objDrawDone
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    ; Comparar con pantalla actual
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .objDrawSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .objDrawSkip
    ; Coincide: leer sprite pointer y posicion
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx pointer
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    INC HL
    LD A, (HL)                  ; A = tint variant
    INC HL
    LD (CurrentTintVar), A
    PUSH HL
    ; Comprobar si es pozo
    PUSH DE
    PUSH BC
    LD HL, BgGfx_well_pozo
    OR A
    SBC HL, DE
    POP BC
    POP DE
    JR NZ, .objNotWell
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A
    LD (WellPosX), A
    LD A, C
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A
    LD (WellPosY), A
    LD A, 1
    LD (WellActive), A
.objNotWell:
    ; No es house sprite (sin remap de color)
    XOR A
    LD (BgSpriteIsHouse), A
    EX DE, HL                   ; HL = BgGfx ptr (bank 3)
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    CALL DrawBgGfxSprite
    POP HL
    JR .objDrawLoop
.objDrawSkip:
    LD DE, 5                    ; skip DEFW ptr (2) + DEFB x (1) + DEFB y (1) + DEFB v (1)
    ADD HL, DE
    JR .objDrawLoop
.objDrawDone:

    CALL BuildCollisionMap      ; Pre-computar mapa de colision para la nueva pantalla
    XOR A
    LD (ScreenDirty), A
    LD A, 1
    LD (ScreenJustRedrawn), A

    ; Marcar TODOS los enemigos como NEWSPAWN para que no hagan erase
    ; (round-robin: no todos se renderizan este frame)
    LD IX, EntityTable + SLOT_MONSTER0 * ENT_SIZE
    LD B, NUM_MONSTERS + NUM_NASTIES
.markFresh:
    LD A, (IX+ENT_TYPE)
    OR A
    JR Z, .markSkip
    SET ENTF_NEWSPAWN, (IX+ENT_FLAGS)
.markSkip:
    LD DE, ENT_SIZE
    ADD IX, DE
    DJNZ .markFresh

    CALL DrawClockSprite        ; restaurar decoración del reloj tras borrado de pantalla
    CALL DrawTimeIndicator      ; HUD: momento del dia (col 30-31)
    CALL DrawRoomInfo           ; HUD: coordenadas y nombre de room (fila 23)
    ; Snapshot de atributos ANTES de pickups (fondo limpio sin pickups)
    CALL SaveCleanAttrs

    ; --- Dibujar pickups con XOR (sobre fondo limpio guardado) ---
    LD HL, PickupTable
.pkDrawLoop:
    LD A, (HL)
    CP $FF
    JR Z, .pkDrawDone
    CP $FE
    JR Z, .pkDrawSkipInactive
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .pkDrawSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .pkDrawSkip
    ; Coincide: dibujar pickup con XOR (pixeles) + atributos
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx pointer
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    INC HL
    LD A, (HL)                  ; A = tint variant
    INC HL
    LD (CurrentTintVar), A
    PUSH HL                     ; guardar puntero tabla
    EX DE, HL                   ; HL = BgGfx ptr (bank 3)
    CALL LoadBgSpriteToBuffer   ; paginar bank 3, copiar a BgSpriteBuffer (preserva BC)
    PUSH BC                     ; guardar charX, charY (DrawBgSpriteXOR los corrompe)
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR        ; dibujar pixeles con XOR
    POP BC                      ; restaurar charX, charY
    LD IX, BgSpriteBuffer       ; IX al inicio del sprite de nuevo
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgAttrOnly         ; pintar solo atributos
    POP HL                      ; restaurar puntero tabla
    JR .pkDrawLoop
.pkDrawSkip:
    LD DE, 5                    ; skip ptr(2) + x(1) + y(1) + v(1)
    ADD HL, DE
    JR .pkDrawLoop
.pkDrawSkipInactive:
    LD DE, 7                    ; skip mapX(1) + mapY(1) + ptr(2) + x(1) + y(1) + v(1)
    ADD HL, DE
    JR .pkDrawLoop
.pkDrawDone:
    RET

; ==============================================================================
; DrawBgGfxSprite - Dibuja un BG sprite con pixeles y atributos
; ==============================================================================
; Entrada: IX = datos del sprite, B = x_char, C = y_char
; Formato: DEFB height_px, width_bytes, pixel_data(CPL),
;          DEFB tintPaper, attr_h, attr_w, attr_data
; ==============================================================================
DrawBgGfxSprite:
    LD A, (IX+0)                ; height_px
    OR A
    RET Z                       ; sprite nulo (sin datos)
    LD (.heightCnt), A
    LD A, (IX+1)                ; width_bytes (bit 7 = RLE flag)
    LD (.rleFlag), A
    AND $7F
    LD (.widthVal), A

    ; Aplicar offset HUD: desplazar sprites BG 2 filas hacia abajo
    LD A, C
    ADD A, BG_Y_OFFSET
    LD C, A

    ; Guardar posicion para la fase de atributos
    LD A, B
    LD (.xChar), A
    LD A, C
    LD (.yChar), A

    INC IX
    INC IX                      ; IX -> pixel data

    ; Calcular dir VRAM inicio: x_pixel = x_char*8, y_pixel = y_char*8
    LD A, C
    RLCA
    RLCA
    RLCA
    LD D, A                     ; D = y_pixel
    LD A, B
    RLCA
    RLCA
    RLCA
    LD E, A                     ; E = x_pixel
    CALL CalcPixelAddr          ; HL = dir VRAM

    ; --- Inicializar RLE state ---
    XOR A
    LD (.rlePending), A         ; sin run pendiente al inicio

    ; --- Comprobar si es RLE o literal ---
    LD A, (.rleFlag)
    BIT 7, A
    JR NZ, .rlePixRow

    ; ===================== PATH LITERAL (sin cambios) =====================
.pixRow:
    LD A, (.widthVal)
    LD B, A
    PUSH HL                     ; guardar inicio de fila VRAM

.pixCol:
    LD A, (IX+0)
    CPL                         ; des-invertir (dato almacenado CPL'd)
    LD (HL), A
    INC IX
    INC HL
    DJNZ .pixCol

    POP HL                      ; restaurar inicio fila
    LD A, (.heightCnt)
    DEC A
    LD (.heightCnt), A
    JR Z, .pixDone
    CALL NextPixelLine          ; HL = siguiente linea pixel
    JR .pixRow

    ; ===================== PATH RLE =====================
    ; Stream RLE con chunks explícitos (sin ambigüedad token/dato):
    ;   Control $01-$7F: literal group, siguen (control) bytes raw
    ;   Control $80-$FF: run, count = (control & $7F)+2, sigue 1 byte valor
    ; El estado .rlePending conserva el chunk entre filas:
    ;   0 = necesita nuevo token
    ;   >0 = en run, quedan .rlePending bytes de .rleValue
    ;   <0 = en literal group, quedan -(.rlePending) bytes por leer de IX
.rlePixRow:
    LD A, (.widthVal)
    LD B, A
    PUSH HL                     ; guardar inicio de fila VRAM

.rlePixCol:
    LD A, (.rlePending)
    OR A
    JP Z, .rleNewToken          ; 0 = necesita nuevo chunk
    JP M, .rleLitEmit           ; <0 = literal group en curso
    ; >0 = run en curso, emitir valor
.rleRunEmit:
    LD A, (.rleValue)
    CPL
    LD (HL), A
    INC HL
    LD A, (.rlePending)
    DEC A
    LD (.rlePending), A
    DJNZ .rlePixCol
    JR .rleRowDone

.rleNewToken:
    LD A, (IX+0)
    INC IX
    BIT 7, A
    JR NZ, .rleNewRun
    ; --- Literal group: A = count (1-127) ---
    NEG                         ; A = -count (negativo)
    LD (.rlePending), A
    ; fall through: emitir primer byte literal

.rleLitEmit:
    LD A, (IX+0)
    INC IX
    CPL
    LD (HL), A
    INC HL
    LD A, (.rlePending)
    INC A                       ; hacia 0
    LD (.rlePending), A
    DJNZ .rlePixCol
    JR .rleRowDone

    ; --- Run: count = (A & $7F) + 2 ---
.rleNewRun:
    AND $7F
    ADD A, 2
    LD (.rlePending), A
    LD A, (IX+0)
    INC IX
    LD (.rleValue), A
    JR .rleRunEmit

.rleRowDone:
    POP HL                      ; restaurar inicio fila
    LD A, (.heightCnt)
    DEC A
    LD (.heightCnt), A
    JR Z, .pixDone
    CALL NextPixelLine
    JR .rlePixRow

.pixDone:
    ; --- Leer tintPaper del sprite data ---
    LD A, (IX+0)                ; tintPaper (255=not tintable)
    LD (CurrentTintPaper), A
    INC IX

    ; --- Pintar atributos ---
    LD A, (IX+0)                ; attr_h
    OR A
    RET Z
    LD E, A                     ; E = filas de atributos
    LD A, (IX+1)                ; attr_w
    LD D, A                     ; D = columnas de atributos
    INC IX
    INC IX                      ; IX -> attr data

    ; Calcular dir atributos: ATTR_BASE + y_char*32 + x_char
    LD A, (.yChar)
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = y_char * 32
    LD A, (.xChar)
    ADD A, L
    LD L, A
    JR NC, .noCarryA
    INC H
.noCarryA:
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = dir atributo VRAM

.attrRow:
    LD B, D                     ; B = attr_w
    PUSH HL

.attrCol:
    LD A, (IX+0)
    CALL ApplyTintSwap          ; Reemplazar paper si coincide con tintPaper
    CALL ApplyDayCycleRemap     ; Transformar attr segun momento del dia
    LD (HL), A
    INC IX
    INC HL
    DJNZ .attrCol

    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC E
    JR NZ, .attrRow
    RET

; Variables locales DrawBgGfxSprite
.heightCnt: DEFB 0
.widthVal:  DEFB 0
.xChar:     DEFB 0
.yChar:     DEFB 0
.rleFlag:   DEFB 0              ; bit 7 = sprite RLE comprimido
.rlePending: DEFB 0             ; bytes restantes del run actual
.rleValue:  DEFB 0              ; valor del run actual

; Variables de tint
CurrentTintVar:   DEFB $FF    ; paper destino del placement (255=sin tint)
CurrentTintPaper: DEFB $FF    ; paper original tintable del sprite (255=no tintable)

; ==============================================================================
; ApplyTintSwap - Reemplaza paper si coincide con tintPaper del sprite
; ==============================================================================
; Entrada: A = attr byte
; Salida:  A = attr con paper reemplazado (o sin cambio)
; Preserva: HL, DE, BC, IX
; ==============================================================================
ApplyTintSwap:
    PUSH BC
    LD B, A                     ; B = attr original
    LD A, (CurrentTintVar)
    CP $FF
    JR Z, .tintNoChange
    LD C, A                     ; C = tint variant (new paper 0-7)
    LD A, (CurrentTintPaper)
    CP $FF
    JR Z, .tintNoChange
    ; A = tintPaper (0-7), C = tintVar (0-7), B = attr
    ; Extraer paper del attr: bits 5-3
    LD A, B
    AND $38                     ; A = 00PPP000
    RRCA
    RRCA
    RRCA                        ; A = 00000PPP = paper actual
    PUSH DE
    LD D, A                     ; D = paper actual
    LD A, (CurrentTintPaper)
    CP D                        ; paper actual == tintPaper?
    POP DE
    JR NZ, .tintNoChange
    ; Match: reemplazar paper bits con tintVar
    LD A, B
    AND $C7                     ; A = FB000III (limpiar paper)
    PUSH DE
    LD D, A
    LD A, C                     ; A = tintVar (0-7)
    RLCA
    RLCA
    RLCA                        ; A = 00PPP000
    OR D                        ; A = FBPPPIII
    POP DE
    POP BC
    RET
.tintNoChange:
    LD A, B                     ; devolver sin cambio
    POP BC
    RET

; ==============================================================================
; RemapScreenAttrs - Remap rapido de atributos (sin redibujar pixeles)
; ==============================================================================
; Solo se ejecuta cuando AttrsDirty=1 (cambio de fase day/night).
; Itera BG sprites saltando pixel data, solo repinta attrs con nuevo remap.
; ==============================================================================
RemapScreenAttrs:
    LD A, (AttrsDirty)
    OR A
    RET Z

    XOR A
    LD (AttrsDirty), A

    ; --- Iterar sprites del room (solo attrs) ---
    LD HL, (CurrentScreenAddr)
.rsLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .rsDone

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    LD A, (HL)                  ; A = tint variant
    INC HL
    LD (CurrentTintVar), A
    PUSH HL

    CALL CheckIfHouseSprite

    ; Cargar sprite al buffer (bank 3 → BgSpriteBuffer) antes de leer attrs
    EX DE, HL                   ; HL = BgGfx ptr
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    CALL RemapBgAttrsOnly

    POP HL
    JR .rsLoop

.rsDone:
    CALL DrawClockSprite
    CALL DrawTimeIndicator
    ; Snapshot de atributos limpios tras remap
    JP SaveCleanAttrs           ; tail call

; ==============================================================================
; SaveCleanAttrs - Copia ATTR_BASE → CleanAttrMap (768 bytes)
; ==============================================================================
; Llamado tras DrawScreen y RemapScreenAttrs.
; ==============================================================================
SaveCleanAttrs:
    LD HL, ATTR_BASE
    LD DE, CleanAttrMap
    LD BC, ATTR_SIZE
    LDIR
    RET

; ==============================================================================
; RestoreOldAttr - Restaura atributos del fondo en posicion vieja del sprite
; ==============================================================================
; D = pixelY viejo, E = pixelX viejo. Restaura 3x3 celdas desde CleanAttrMap.
; ==============================================================================
RestoreOldAttr:
    ; Calcular offset en attr map: (Y/8)*32 + (X/8)
    LD A, D
    RRCA
    RRCA
    RRCA
    AND $1F                             ; charY
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                          ; HL = charY * 32
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F                             ; charX
    LD E, A
    LD D, 0
    ADD HL, DE                          ; HL = offset en attr map
    ; DE = destino en ATTR_BASE, BC fuente en CleanAttrMap
    PUSH HL
    LD DE, ATTR_BASE
    ADD HL, DE
    EX DE, HL                           ; DE = ATTR_BASE + offset (destino)
    POP HL
    LD BC, CleanAttrMap
    ADD HL, BC                          ; HL = CleanAttrMap + offset (fuente)
    ; Copiar 3 celdas × 3 filas
    LD B, 3
.roaRow:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    ; Siguiente fila: avanzar 30 posiciones (32 - 2 ya avanzadas)
    PUSH BC
    LD BC, 30
    ADD HL, BC
    EX DE, HL
    ADD HL, BC
    EX DE, HL
    POP BC
    DJNZ .roaRow
    RET

; ==============================================================================
; SkipPixelData - Avanza IX pasando cabecera + pixel data (literal o RLE)
; ==============================================================================
; Entrada: IX = inicio del sprite (byte 0 = height_px, byte 1 = width_bytes|flag)
; Salida:  IX = primer byte tras pixel data (tintPaper)
; Modifica: AF, BC, DE, HL
; ==============================================================================
SkipPixelData:
    LD A, (IX+0)                ; height_px
    LD D, A                     ; D = height_px
    LD A, (IX+1)                ; width_bytes (bit 7 = RLE flag)
    LD E, A                     ; E = raw value con flag
    INC IX
    INC IX                      ; IX -> pixel data

    BIT 7, E
    JR NZ, .spSkipRle

    ; --- Path literal: saltar height * width bytes ---
    LD A, E                     ; width_bytes (sin flag, bit7=0)
.spLitRow:
    LD B, A
.spLitCol:
    INC IX
    DJNZ .spLitCol
    DEC D
    JR NZ, .spLitRow
    RET

    ; --- Path RLE: recorrer tokens para saltar el stream ---
    ; Total pixeles = height_px * (width_bytes & $7F)
.spSkipRle:
    LD A, E
    AND $7F                     ; width_bytes real
    ; Calcular total = D * A (height * width)
    LD B, D                     ; B = height
    LD HL, 0
    LD D, 0
    LD E, A                     ; DE = width
.spMul:
    ADD HL, DE
    DJNZ .spMul
    ; HL = total pixeles a consumir
    ; Recorrer tokens RLE hasta consumir HL pixeles
.spRleLoop:
    LD A, H
    OR L
    RET Z                       ; 0 pixeles restantes → IX en posicion correcta
    LD A, (IX+0)
    INC IX
    BIT 7, A
    JR NZ, .spRleRun
    ; Literal group: consume A bytes de datos (A = count 1-127)
    LD E, A
    LD D, 0
    SBC HL, DE                  ; HL -= count
    ; Saltar los bytes literales
    LD B, E
.spRleLitSkip:
    INC IX
    DJNZ .spRleLitSkip
    JR .spRleLoop
.spRleRun:
    ; Run: consume (A & $7F)+2 pixeles, saltar 1 byte valor
    AND $7F
    ADD A, 2
    LD E, A
    LD D, 0
    SBC HL, DE                  ; HL -= count
    INC IX                      ; saltar byte valor
    JR .spRleLoop

; ==============================================================================
; RemapBgAttrsOnly - Salta pixel data de un BG sprite, solo repinta attrs
; ==============================================================================
; Entrada: IX = datos del sprite, B = x_char, C = y_char
; ==============================================================================
RemapBgAttrsOnly:
    LD A, (IX+0)                ; height_px
    OR A
    RET Z

    ; Aplicar offset HUD
    LD A, C
    ADD A, BG_Y_OFFSET
    LD C, A

    ; Saltar cabecera + pixel data (soporta RLE y literal)
    PUSH BC
    CALL SkipPixelData          ; IX = inicio de tintPaper
    POP BC

    ; Leer tintPaper
    LD A, (IX+0)                ; tintPaper
    LD (CurrentTintPaper), A
    INC IX

    ; Leer attr_h, attr_w
    LD A, (IX+0)                ; attr_h
    OR A
    RET Z
    LD E, A                     ; E = attr_h (filas)
    LD A, (IX+1)                ; attr_w
    LD D, A                     ; D = attr_w (cols)
    INC IX
    INC IX                      ; IX -> attr data

    ; Calcular dir atributos: ATTR_BASE + y_char*32 + x_char
    LD A, C
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = y_char * 32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .noCarry
    INC H
.noCarry:
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = dir atributo VRAM

.raRow:
    LD B, D                     ; B = attr_w
    PUSH HL

.raCol:
    LD A, (IX+0)
    CALL ApplyTintSwap
    CALL ApplyDayCycleRemap
    LD (HL), A
    INC IX
    INC HL
    DJNZ .raCol

    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC E
    JR NZ, .raRow
    RET

; ==============================================================================
; BuildCollisionMap - Construye mapa de colision desde los sprites del room
; ==============================================================================
; Llamado una vez al cargar cada pantalla (desde DrawScreen).
; Itera la lista de BG sprites y marca su footprint en CollisionMap.
; Todos los BG sprites se tratan como solidos.
; ==============================================================================
BuildCollisionMap:
    ; Limpiar mapa a 0 (todo libre)
    LD HL, CollisionMap
    LD DE, CollisionMap + 1
    LD BC, 32 * 22 - 1
    XOR A
    LD (HL), A
    LDIR

    ; Iterar sprites del room
    LD HL, (CurrentScreenAddr)
.bcmLoop:
    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD A, D
    OR E
    JR Z, .bcmRoomDone          ; Terminador $0000 → pasar a ObjectTable

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    INC HL                      ; skip tint variant byte
    PUSH HL                     ; Guardar puntero room data
    PUSH BC                     ; Guardar x_char, y_char

    ; Cargar sprite desde bank 3 al buffer para leer sus dimensiones
    EX DE, HL                   ; HL = BgGfx ptr
    CALL LoadBgSpriteToBuffer
    LD HL, BgSpriteBuffer
    POP BC                      ; B = x_char, C = y_char

    ; Leer dimensiones del sprite
    LD A, (HL)                  ; height_px
    OR A
    JR Z, .bcmNullSpr
    RRCA
    RRCA
    RRCA
    AND $1F                     ; A = height_chars
    LD D, A                     ; D = height_chars
    INC HL
    LD A, (HL)
    AND $7F                     ; Enmascarar bit 7 (flag RLE)
    LD E, A                     ; E = width_chars (= width_bytes)

    ; Marcar rectangulo en CollisionMap
    ; B=x_char, C=y_char, D=height, E=width
    CALL .markRect

.bcmNullSpr:
    POP HL
    JR .bcmLoop

    ; --- Marcar objetos per-cell desde ObjectTable ---
.bcmRoomDone:
    LD HL, ObjectTable
.objColLoop:
    LD A, (HL)
    CP $FF
    JR Z, .bcmStartLocks
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .objColSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .objColSkip
    ; Coincide: leer sprite y marcar colision
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx pointer
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    INC HL
    INC HL                      ; skip tint variant byte
    PUSH HL                     ; room walker ptr
    PUSH BC                     ; charX, charY
    EX DE, HL                   ; HL = BgGfx pointer (bank 3)
    CALL LoadBgSpriteToBuffer
    LD HL, BgSpriteBuffer
    POP BC                      ; B = charX, C = charY
    LD A, (HL)                  ; height_px
    RRCA
    RRCA
    RRCA
    AND $1F
    LD D, A                     ; D = height_chars
    INC HL
    LD A, (HL)
    AND $7F                     ; Enmascarar flag RLE
    LD E, A                     ; E = width_chars
    CALL .markRect
    POP HL
    JR .objColLoop
.objColSkip:
    LD DE, 5                    ; skip ptr(2) + x(1) + y(1) + v(1)
    ADD HL, DE
    JR .objColLoop

; --- Pickups-como-candado: bloquear chars si requieren key que el player no tiene ---
.bcmStartLocks:
    LD HL, PickupTable
.bcmPkLoop:
    LD A, (HL)
    CP $FF
    RET Z
    CP $FE
    JR Z, .bcmPkInactive        ; HL en mapX
    LD B, A                     ; mapX
    INC HL
    LD C, (HL)                  ; mapY
    INC HL                      ; HL en ptr_lo
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .bcmPkSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .bcmPkSkip
    ; Pantalla correcta: leer BgGfx ptr
    LD E, (HL)
    INC HL                      ; HL en ptr_hi
    LD D, (HL)                  ; DE = BgGfx ptr
    ; Clasificar sprite
    CALL GetPickupKeyBehavior   ; A = 0..8, preserva HL/DE/BC
    CP 5
    JR C, .bcmPkAdvance         ; <5 = normal o key, no bloquea
    SUB 4
    LD B, A                     ; B = key requerida
    LD A, (CurrentKey)
    CP B
    JR Z, .bcmPkAdvance         ; tiene la key → candado abierto, no bloquea
    ; Lock activo: marcar sus chars como pared
    INC HL                      ; HL en charX
    LD B, (HL)                  ; charX
    INC HL                      ; HL en charY
    LD C, (HL)                  ; charY
    INC HL                      ; HL en tint
    INC HL                      ; HL en next mapX
    PUSH HL                     ; guardar puntero a siguiente entry
    PUSH BC                     ; charX, charY
    EX DE, HL                   ; HL = BgGfx ptr
    CALL LoadBgSpriteToBuffer
    LD HL, BgSpriteBuffer
    POP BC                      ; B=charX, C=charY
    LD A, (HL)                  ; height_px
    RRCA
    RRCA
    RRCA
    AND $1F
    LD D, A                     ; height_chars
    INC HL
    LD A, (HL)
    AND $7F
    LD E, A                     ; width_chars
    CALL .markRect
    POP HL                      ; recuperar puntero a siguiente entry
    JR .bcmPkLoop
.bcmPkAdvance:
    ; HL en ptr_hi. Skip 4 para llegar al siguiente mapX.
    LD DE, 4
    ADD HL, DE
    JR .bcmPkLoop
.bcmPkSkip:
    ; HL en ptr_lo. Skip 5 para llegar al siguiente mapX.
    LD DE, 5
    ADD HL, DE
    JR .bcmPkLoop
.bcmPkInactive:
    ; HL en mapX ($FE). Skip 7.
    LD DE, 7
    ADD HL, DE
    JR .bcmPkLoop

; --- Marca un rectangulo en el CollisionMap ---
; B=x_char, C=y_char, D=height (filas), E=width (cols)
.markRect:
    ; Calcular HL = CollisionMap + C*32 + B
    LD A, C
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = y_char * 32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .mrNoCarry
    INC H
.mrNoCarry:
    LD BC, CollisionMap
    ADD HL, BC                  ; HL = &CollisionMap[y*32 + x]

.mrRowLoop:
    PUSH HL
    LD B, E                     ; B = width
.mrColLoop:
    LD (HL), 1
    INC HL
    DJNZ .mrColLoop
    POP HL
    ; Siguiente fila: HL += 32
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC D
    JR NZ, .mrRowLoop
    RET

; ==============================================================================
; IsPointBlocked - Lookup rapido en CollisionMap (O(1))
; ==============================================================================
; Entrada: B = X pixel, C = Y pixel
; Salida: Z = libre, NZ = bloqueado
; Preserva: BC, DE
; ==============================================================================
IsPointBlocked:
    ; Debug noclip: Z = libre siempre (también permite transición entre rooms)
    LD A, (NoclipMode)
    OR A
    JR Z, .ipbReal
    XOR A
    RET
.ipbReal:
    PUSH DE
    ; charX = X_pixel / 8
    LD A, B
    RRCA
    RRCA
    RRCA
    AND $1F
    LD E, A                     ; E = charX
    ; charY = Y_pixel / 8 - BG_Y_OFFSET
    LD A, C
    RRCA
    RRCA
    RRCA
    AND $1F
    SUB BG_Y_OFFSET
    ; Bounds check (charY debe estar en 0..21)
    CP 22
    JR NC, .ipFree
    ; HL = CollisionMap + charY*32 + charX
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = charY * 32
    LD D, 0
    ADD HL, DE                  ; + charX
    LD DE, CollisionMap
    ADD HL, DE
    LD A, (HL)
    OR A                        ; Z=libre, NZ=bloqueado
    POP DE
    RET
.ipFree:
    XOR A                       ; Z = libre
    POP DE
    RET

; ==============================================================================
; CheckPickupCollect - Comprobar si el jugador recoge un pickup
; ==============================================================================
; Recorre PickupTable. Si el jugador solapa con un pickup en la pantalla actual,
; borra el sprite (XOR redraw) y desactiva la entrada (mapX = $FE).
; Los pickups reaparecen al volver a la pantalla (DrawScreen los redibuja).
; ==============================================================================
CheckPickupCollect:
    LD HL, PickupTable
.cpLoop:
    LD A, (HL)
    CP $FF
    RET Z                       ; fin de tabla
    CP $FE
    JP Z, .cpSkipInactive       ; entrada desactivada (ya recogida)
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL
    ; Comprobar pantalla actual
    LD A, (CurrentScreenX)
    CP B
    JP NZ, .cpSkipEntry
    LD A, (CurrentScreenY)
    CP C
    JP NZ, .cpSkipEntry
    ; Pantalla correcta: leer sprite data
    ; HL apunta a DEFW BgGfx_ptr
    PUSH HL                     ; guardar puntero a entrada
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx ptr
    ; Determinar keyBehavior (0=normal, 1-4=key, 5-8=lock)
    CALL GetPickupKeyBehavior
    LD (PickupCurBehavior), A
    CP 5
    JR C, .cpBehOK              ; <5: normal o key → sin prereq
    SUB 4
    LD B, A                     ; B = key requerida (1..4)
    LD A, (CurrentKey)
    CP B
    JP NZ, .cpNoHit             ; lock sin llave → tratar como no-hit
.cpBehOK:
    INC HL
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    ; Calcular rect del pickup en pixeles
    ; px_left = charX * 8, px_top = (charY + BG_Y_OFFSET) * 8
    LD A, B
    ADD A, A
    ADD A, A
    ADD A, A                    ; A = px_left
    LD (.cpPkLeft+1), A        ; self-modify: store pickup left
    ; width from sprite data: cargar header desde bank 3 al buffer
    PUSH BC
    EX DE, HL                  ; HL = BgGfx ptr (en bank 3)
    CALL LoadBgSpriteToBuffer
    LD HL, BgSpriteBuffer
    LD A, (HL)                 ; height_px
    LD (.cpPkH+1), A
    INC HL
    LD A, (HL)                 ; width_bytes (bit 7 = RLE flag)
    AND $7F
    ADD A, A
    ADD A, A
    ADD A, A                   ; width_px = width_bytes * 8
    LD (.cpPkW+1), A
    POP BC
    LD A, C
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A                   ; A = px_top
    LD (.cpPkTop+1), A
    ; Player rect: 16x16 sprite at EntityTable pos
    LD A, (EntityTable + ENT_POSX)
    LD (.cpPlX+1), A
    LD A, (EntityTable + ENT_POSY)
    LD (.cpPlY+1), A
    ; AABB overlap test:
    ; player_right > pk_left AND player_left < pk_right
    ; player_bottom > pk_top AND player_top < pk_bottom
.cpPlX:
    LD A, 0                     ; player_left (self-mod)
    ADD A, 16                   ; player_right = left + 16
.cpPkLeft:
    LD B, 0                     ; pickup_left (self-mod)
    CP B
    JR C, .cpNoHit              ; player_right <= pk_left
    JR Z, .cpNoHit
    ; player_left < pk_right?
.cpPkW:
    LD A, 0                     ; pk_width (self-mod)
    ADD A, B                    ; A = pk_right = pk_left + pk_width
    LD B, A                     ; B = pk_right
.cpPlX2:
    LD A, (.cpPlX+1)            ; player_left (re-read)
    CP B
    JR NC, .cpNoHit             ; player_left >= pk_right
    ; vertical check
.cpPlY:
    LD A, 0                     ; player_top (self-mod)
    ADD A, 16                   ; player_bottom
.cpPkTop:
    LD B, 0                     ; pickup_top (self-mod)
    CP B
    JR C, .cpNoHit
    JR Z, .cpNoHit
.cpPkH:
    LD A, 0                     ; pk_height (self-mod)
    ADD A, B                    ; pk_bottom = pk_top + pk_height
    LD B, A
    LD A, (.cpPlY+1)            ; player_top
    CP B
    JR NC, .cpNoHit
    ; --- HIT: player overlaps pickup ---
    ; El sprite ya fue cargado a BgSpriteBuffer arriba para el AABB test.
    ; Lo reutilizamos: IX = buffer → DrawBgSpriteXOR. No hace falta volver
    ; a leer DE del entry porque el buffer es lo que el draw necesita.
    POP HL                      ; entry pointer (DEFW BgGfx_ptr)
    PUSH HL
    INC HL
    INC HL                      ; skip ptr (2)
    LD B, (HL)                  ; B = charX
    INC HL
    LD C, (HL)                  ; C = charY
    PUSH BC                     ; guardar charX, charY
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    ; Leer dimensiones del buffer (la base, no IX avanzado)
    POP BC                      ; B=charX, C=charY
    LD HL, BgSpriteBuffer
    LD A, (HL)                  ; height_px
    RRCA : RRCA : RRCA
    AND $1F
    LD D, A
    INC HL
    LD A, (HL)
    AND $7F
    LD E, A
    CALL RestorePickupAttrs
    ; Desactivar entrada
    POP HL                      ; entry pointer (DEFW pos)
    DEC HL
    DEC HL                      ; apuntar a mapX
    LD (HL), $FE                ; desactivar
    ; Aplicar efecto key/lock según PickupCurBehavior
    LD A, (PickupCurBehavior)
    OR A
    JR Z, .cpKeyEffectDone      ; 0 = normal, nada
    CP 5
    JR NC, .cpLockConsume       ; 5..8 = lock abierto → consumir key
    ; 1..4 = key recogida
    LD (CurrentKey), A
    JR .cpKeyEffectDone
.cpLockConsume:
    XOR A
    LD (CurrentKey), A
.cpKeyEffectDone:
    ; Sonido de recogida
    PUSH HL
    LD HL, SFX_Pickup
    CALL PlaySFX
    POP HL
    ; Avanzar al siguiente entry: +7 desde mapX (mapX+mapY+ptr+x+y+v)
    LD DE, 7
    ADD HL, DE
    JP .cpLoop
.cpNoHit:
    POP HL                      ; recover entry pointer
    ; Avanzar 5 bytes (ptr+x+y+v) para llegar al siguiente entry
    LD DE, 5
    ADD HL, DE
    JP .cpLoop
.cpSkipEntry:
    ; Ya leimos mapX,mapY (2 bytes), skip 5 mas (ptr+x+y+v)
    LD DE, 5
    ADD HL, DE
    JP .cpLoop
.cpSkipInactive:
    ; Entrada desactivada: skip 7 bytes (mapX + mapY + ptr + x + y + v)
    LD DE, 7
    ADD HL, DE
    JP .cpLoop

; ==============================================================================
; KeyLockTable - Sprites que actúan como llave o candado
; ==============================================================================
; Slots 1..4 son KEYS (id de llave). Slots 5..8 son LOCKS (id_lock = key_id + 4).
; Cuando se toca una llave, CurrentKey = id. Al tocar un candado con la llave
; correspondiente, el candado se recoge y CurrentKey pasa a 0 (consumida).
; Entradas a DEFW 0 están deshabilitadas (sprite no importado todavía).
; ==============================================================================
KeyLockTable:
    DEFW BgGfx_forestkey        ; 1: Forest Key
    DEFW BgGfx_ruinskey         ; 2: Ruins Key
    DEFW BgGfx_cemeterykey      ; 3: Cemetery Key
    DEFW BgGfx_towngatekey      ; 4: TownGate Key
    DEFW BgGfx_forestlock       ; 5: Forest Lock
    DEFW 0                      ; 6: Ruins Lock (pendiente de importar)
    DEFW 0                      ; 7: Cemetery Lock
    DEFW 0                      ; 8: TownGate Lock

; ==============================================================================
; GetPickupKeyBehavior - Devuelve el comportamiento de un pickup según su sprite
; ==============================================================================
; IN:  DE = BgGfx pointer
; OUT: A = 0 (normal), 1..4 (key), 5..8 (lock con key requerida = A-4)
; Preserva: BC, DE, HL. Slots con DEFW 0 nunca matchean (DE es ptr válido != 0).
; ==============================================================================
GetPickupKeyBehavior:
    PUSH HL
    PUSH BC
    LD HL, KeyLockTable
    LD B, 8                     ; 8 slots
    LD C, 1                     ; id actual (1..8)
.gpkbLoop:
    LD A, (HL)                  ; ptr_lo del slot
    CP E
    JR NZ, .gpkbNext
    INC HL
    LD A, (HL)                  ; ptr_hi
    DEC HL
    CP D
    JR Z, .gpkbFound
.gpkbNext:
    INC HL
    INC HL                      ; siguiente slot (DEFW = 2 bytes)
    INC C
    DJNZ .gpkbLoop
    XOR A                       ; no encontrado → comportamiento normal
    POP BC
    POP HL
    RET
.gpkbFound:
    LD A, C                     ; A = id (1..8)
    POP BC
    POP HL
    RET

; ==============================================================================
; ErasePickupArea - Borra un rectangulo de pixeles y atributos
; ==============================================================================
; Entrada: B=charX, C=charY, D=height_chars, E=width_chars
; Borra los pixeles a 0 y los atributos a $07 (ink white, paper black)
; ==============================================================================
; ==============================================================================
; DoPendingPickupErase - Ejecuta borrado diferido de pickup
; ==============================================================================
; Llamar DESPUES de que el player haya sido borrado (XOR erase) y ANTES de
; que se dibuje de nuevo en su nueva posicion.
; ==============================================================================
; ==============================================================================
; DrawBgSpriteXOR - Dibuja un BG sprite con XOR (para pickups)
; ==============================================================================
; Entrada: IX = datos del sprite, B = x_char, C = y_char
; Solo dibuja pixeles con XOR (sin atributos).
; Llamar dos veces en la misma posicion = borrado limpio.
; ==============================================================================
DrawBgSpriteXOR:
    LD A, (IX+0)                ; height_px
    OR A
    RET Z
    LD (.xhCnt), A
    LD A, (IX+1)                ; width_bytes (bit 7 = flag RLE, ignorar)
    AND $7F
    LD (.xwVal), A
    ; Aplicar offset HUD
    LD A, C
    ADD A, BG_Y_OFFSET
    LD C, A
    INC IX
    INC IX                      ; IX -> pixel data
    ; Calcular dir VRAM
    LD A, C
    RLCA : RLCA : RLCA
    LD D, A
    LD A, B
    RLCA : RLCA : RLCA
    LD E, A
    CALL CalcPixelAddr          ; HL = dir VRAM
.xpxRow:
    LD A, (.xwVal)
    LD B, A
    PUSH HL
.xpxCol:
    LD A, (IX+0)
    CPL                         ; des-invertir
    XOR (HL)                    ; XOR con pantalla
    LD (HL), A
    INC IX
    INC HL
    DJNZ .xpxCol
    POP HL
    LD A, (.xhCnt)
    DEC A
    LD (.xhCnt), A
    RET Z
    CALL NextPixelLine
    JR .xpxRow
.xhCnt: DEFB 0
.xwVal: DEFB 0

; ==============================================================================
; DrawBgAttrOnly - Pinta solo los atributos de un BG sprite (sin pixeles)
; ==============================================================================
; Entrada: IX = datos del sprite (desde el inicio), B = x_char, C = y_char
; Salta los pixel data y pinta solo los atributos.
; ==============================================================================
DrawBgAttrOnly:
    LD A, (IX+0)                ; height_px
    OR A
    RET Z
    ; Saltar cabecera + pixel data (soporta RLE y literal)
    PUSH BC
    CALL SkipPixelData          ; IX = inicio de tintPaper
    POP BC
    ; IX ahora apunta a tintPaper, luego attr data
    LD A, (IX+0)                ; tintPaper
    LD (CurrentTintPaper), A
    INC IX
    LD A, (IX+0)                ; attr_h
    OR A
    RET Z
    LD E, A                     ; E = filas de atributos
    LD A, (IX+1)                ; attr_w
    LD D, A                     ; D = columnas de atributos
    INC IX
    INC IX                      ; IX -> attr data
    ; Calcular dir atributos: ATTR_BASE + (y_char+BG_Y_OFFSET)*32 + x_char
    LD A, C
    ADD A, BG_Y_OFFSET
    LD L, A
    LD H, 0
    ADD HL, HL : ADD HL, HL : ADD HL, HL : ADD HL, HL : ADD HL, HL
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .baoNoCarry
    INC H
.baoNoCarry:
    LD BC, ATTR_BASE
    ADD HL, BC
.baoAttrRow:
    LD B, D                     ; B = attr_w
    PUSH HL
.baoAttrCol:
    LD A, (IX+0)
    CALL ApplyTintSwap          ; aplicar tint si corresponde
    LD (HL), A                  ; pintar atributo (sin day remap para pickups)
    INC IX
    INC HL
    DJNZ .baoAttrCol
    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC E
    JR NZ, .baoAttrRow
    RET

; ==============================================================================
; RestorePickupAttrs - Restaura atributos de CleanAttrMap para un rectangulo
; ==============================================================================
; Entrada: B=charX, C=charY, D=height_chars, E=width_chars
; ==============================================================================
RestorePickupAttrs:
    LD A, C
    ADD A, BG_Y_OFFSET
    LD L, A
    LD H, 0
    ADD HL, HL : ADD HL, HL : ADD HL, HL : ADD HL, HL : ADD HL, HL  ; *32
    LD A, B
    ADD A, L
    LD L, A
    JR NC, .rpaNoCarry
    INC H
.rpaNoCarry:
    ; HL = offset into attr area (y*32 + x)
    PUSH HL
    LD BC, CleanAttrMap
    ADD HL, BC                  ; HL = source (CleanAttrMap)
    POP BC
    PUSH HL                     ; save source
    LD HL, ATTR_BASE
    ADD HL, BC                  ; HL = dest (VRAM)
    POP BC                      ; BC = source
    ; Now HL=dest(VRAM), BC=source(CleanAttrMap), D=rows, E=cols
.rpaRow:
    PUSH HL
    PUSH BC
    LD A, E
    LD (.rpaW), A
.rpaCol:
    LD A, (BC)
    LD (HL), A
    INC HL
    INC BC
    LD A, (.rpaW)
    DEC A
    LD (.rpaW), A
    JR NZ, .rpaCol
    POP BC
    POP HL
    ; Siguiente fila: +32
    PUSH DE
    LD DE, 32
    ADD HL, DE
    LD A, C
    ADD A, 32
    LD C, A
    LD A, B
    ADC A, 0
    LD B, A
    POP DE
    DEC D
    JR NZ, .rpaRow
    RET
.rpaW: DEFB 0
