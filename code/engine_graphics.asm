; ==============================================================================
; MOTOR GRAFICO - Sprites genericos y utilidades de pantalla
; ==============================================================================
; Sistema fiel a Sabre Wulf:
; - Sprites de tamanyo variable (width+height en cabecera)
; - XOR para draw/erase (dibujar dos veces = borrar)
; - NextPixelLine para cruzar character rows y tercios
; - Atributos dinamicos segun tamanyo del sprite
; ==============================================================================

ClearScreen:
    CALL ROM_CLS
    RET

; ==============================================================================
; DrawSprite - Dibuja un sprite con XOR, pixel-perfect (fiel a Sabre Wulf)
; ==============================================================================
; Entrada:
;   D = Y pixel (cualquier valor, no requiere alineacion)
;   E = X pixel (cualquier valor, no requiere alineacion)
;   IX = puntero a datos del sprite (con cabecera width, height)
;
; Formato del sprite:
;   DEFB width_bytes  (2 = 16px, 3 = 24px)
;   DEFB height_pixels
;   DEFB pixel_data... (width * height bytes)
;
; Dos paths:
;   - Alineado (X%8==0): XOR directo, sin tablas
;   - Shifted (X%8!=0): lookup tables pre-computadas (LD C,byte / LD A,(BC))
;     Cada byte de sprite produce high part + overflow en columna siguiente.
;     Un sprite de W bytes ocupa W+1 columnas VRAM cuando shifted.
;
; Usa XOR: dibujar dos veces en la misma posicion = borrar.
; ==============================================================================
DrawSprite:
    ; Guardar posicion
    LD A, D
    LD (.posY), A
    LD A, E
    LD (.posX), A

    ; Leer cabecera sprite
    LD A, (IX+0)                ; width_bytes
    LD (.widthSave), A
    LD A, (IX+1)                ; height_pixels
    LD (.heightSave), A
    INC IX
    INC IX                      ; IX → pixel data

    ; === Y CLIPPING ===
    ; Clip superior: si Y < SCREEN_MIN_Y, saltar filas superiores
    LD A, (.posY)
    CP SCREEN_MIN_Y
    JR NC, .clipTopDone
    ; Filas a saltar = SCREEN_MIN_Y - Y
    LD B, A                     ; B = Y
    LD A, SCREEN_MIN_Y
    SUB B                       ; A = filas a saltar
    LD B, A                     ; B = skip rows
    ; Reducir altura
    LD A, (.heightSave)
    SUB B
    RET Z                       ; Sprite completamente fuera → no dibujar
    RET C                       ; Idem
    LD (.heightSave), A
    ; Avanzar IX: skip_rows * width_bytes
    LD A, (.widthSave)
    LD C, A
.clipSkipRow:
    LD A, C
.clipSkipByte:
    INC IX
    DEC A
    JR NZ, .clipSkipByte
    DJNZ .clipSkipRow
    ; Ajustar Y al borde
    LD A, SCREEN_MIN_Y
    LD (.posY), A
    LD D, A
.clipTopDone:
    ; Clip inferior: si Y + height > 192, reducir altura
    LD A, (.posY)
    LD B, A
    LD A, (.heightSave)
    ADD A, B                    ; A = Y + height
    JR C, .clipBot              ; Overflow → fuera por abajo
    CP 192
    JR C, .clipBotDone          ; Dentro de pantalla
.clipBot:
    ; Reducir altura: new_height = 192 - Y
    LD A, 192
    SUB B                       ; A = 192 - Y
    RET Z
    RET C
    LD (.heightSave), A
.clipBotDone:

    ; Comprobar alineacion
    LD A, E
    AND 7
    JR NZ, .shifted

    ; ==================================================================
    ; PATH ALINEADO (X%8 == 0) — sin tablas, XOR directo
    ; ==================================================================
    CALL CalcPixelAddr          ; D=Y, E=X → HL = dir VRAM
    LD A, (.heightSave)
    LD C, A                     ; C = height counter

.alignedLine:
    LD A, (.widthSave)
    LD B, A                     ; B = ancho en bytes
    PUSH HL                     ; Guardar inicio de linea en VRAM

.alignedByte:
    LD A, (IX+0)
    XOR (HL)
    LD (HL), A
    INC HL                      ; Siguiente columna VRAM
    INC IX                      ; Siguiente byte de sprite
    DJNZ .alignedByte

    POP HL                      ; Restaurar inicio de linea
    DEC C
    RET Z                       ; Terminamos todas las lineas
    CALL NextPixelLine          ; HL = siguiente linea (cruza chars/tercios)
    JR .alignedLine

    ; ==================================================================
    ; PATH SHIFTED (X%8 != 0) — tablas de lookup (fiel a Sabre Wulf)
    ; ==================================================================
    ; A = shift amount (1-7) al llegar aqui
.shifted:
    ; Calcular pagina de tabla (fiel a PrepDraw original)
    DEC A                       ; 0-6
    RLCA                        ; ×2 (cada shift usa 2 paginas)
    AND $0E
    OR SHIFT_TABLE_BASE         ; Base de tablas
    LD (.tablePage), A

    ; Convertir IX → DE (sprite data), necesitamos BC para tabla
    PUSH IX
    POP DE                      ; DE = puntero a pixel data
    PUSH DE                     ; Guardar sprite data ptr en stack

    ; Recargar D=Y, E=X para CalcPixelAddr
    LD A, (.posY)
    LD D, A
    LD A, (.posX)
    LD E, A
    CALL CalcPixelAddr          ; HL = dir VRAM

    POP DE                      ; DE = sprite data ptr restaurado
    LD A, (.tablePage)
    LD B, A                     ; B = pagina high part

.shiftedLine:
    PUSH HL                     ; Guardar inicio de linea
    LD A, (.widthSave)
    LD (.widthCount), A

.shiftedByte:
    ; === Inner loop fiel al original ($BA0D) ===
    LD A, (DE)                  ; Leer byte de sprite
    LD C, A                     ; C = byte value (indice en tabla)
    LD A, (BC)                  ; A = byte >> shift (high part)
    XOR (HL)                    ; XOR con VRAM
    LD (HL), A                  ; Escribir
    INC L                       ; Siguiente columna VRAM
    INC B                       ; Pagina overflow
    LD A, (BC)                  ; A = byte << (8-shift) (overflow)
    XOR (HL)                    ; XOR con VRAM
    LD (HL), A                  ; Escribir
    DEC B                       ; Restaurar pagina high
    INC DE                      ; Siguiente byte de sprite
    ; Siguiente byte de ancho
    LD A, (.widthCount)
    DEC A
    LD (.widthCount), A
    JR NZ, .shiftedByte

    POP HL                      ; Restaurar inicio de linea
    LD A, (.heightSave)
    DEC A
    LD (.heightSave), A
    RET Z                       ; Terminamos todas las lineas
    CALL NextPixelLine          ; HL = siguiente linea
    JR .shiftedLine

; Variables locales de DrawSprite
.posX:       DEFB 0
.posY:       DEFB 0
.widthSave:  DEFB 0
.heightSave: DEFB 0
.tablePage:  DEFB 0
.widthCount: DEFB 0

; ==============================================================================
; NextPixelLine - Avanza HL a la siguiente linea de pixel en VRAM
; ==============================================================================
; Maneja correctamente los cruces de character row (cada 8 lineas)
; y los cruces de tercio de pantalla (cada 64 lineas).
;
; Entrada/Salida: HL = direccion VRAM (modificada in-place)
; ==============================================================================
; Fiel a Sabre Wulf $B8CC: "Screen Address One Pixel Below"
NextPixelLine:
    INC H                       ; Siguiente scanline dentro del char
    LD A, H
    AND 7
    RET NZ                      ; Sin cruce de char row → listo

    ; --- Cruce de character row ---
    LD A, L
    ADD A, 32                   ; Avanzar fila de caracteres (Y5Y4Y3 += 1)
    LD L, A
    AND $E0                     ; ¿Y5Y4Y3 volvio a 000?
    RET Z                       ; Si → cruce de tercio, INC H ya dejo H correcto

    ; --- No cruce de tercio: deshacer carry espurio de INC H ---
    LD A, H
    SUB 8
    LD H, A
    RET

; ==============================================================================
; SetEntityAttr - Pone atributo en las celdas del sprite (tamanyo variable)
; ==============================================================================
; Usa EntityAttrW/H calculados previamente por SaveEntityAttr.
; Entrada:
;   D = Y pixel (alineado 8px), E = X pixel (alineado 8px)
;   A = atributo a pintar
; ==============================================================================
SetEntityAttr:
    PUSH AF                     ; Guardar atributo
    CALL CalcAttrAddr           ; HL = dir atributo celda (0,0)
    POP AF

    LD B, A                     ; B = atributo (preservar)
    LD A, (EntityAttrH)
    LD C, A                     ; C = filas
.rowLoop:
    ; Clipping: no pintar en filas del HUD (ATTR_BASE..ATTR_BASE+63)
    PUSH HL
    LD A, H
    CP (ATTR_BASE + 64) >> 8   ; Comprobar si estamos en las 2 primeras filas
    JR NZ, .rowNotHud
    LD A, L
    CP (ATTR_BASE + 64) & $FF
    JR NC, .rowNotHud
    ; Fila en HUD → saltar sin pintar
    POP HL
    JR .rowSkip
.rowNotHud:
    POP HL
    LD A, (EntityAttrW)
    PUSH HL                     ; Guardar inicio de fila
    ; Pintar una fila
.colLoop:
    LD (HL), B
    INC HL
    DEC A
    JR NZ, .colLoop
    POP HL
.rowSkip:
    ; Siguiente fila: HL += 32
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC C
    JR NZ, .rowLoop
    RET

; ==============================================================================
; SaveEntityAttr - Guarda atributos VRAM bajo un sprite de tamanyo variable
; ==============================================================================
; Lee width_chars × height_chars atributos y los guarda en EntitySavedAttr.
; Se llama ANTES de pintar el sprite.
;
; Entrada: D = Y pixel (alineado 8px), E = X pixel (alineado 8px)
;          IX = puntero al sprite (para leer width/height)
; ==============================================================================
; CalcEntityAttrSize - Calcula EntityAttrW/H sin guardar attrs (para enemigos)
; ==============================================================================
; Entrada: D = Y pixel, E = X pixel, IX = puntero al sprite (width/height)
; Solo calcula las dimensiones en chars para que SetEntityAttr funcione.
; ==============================================================================
CalcEntityAttrSize:
    LD A, (IX+0)                ; width_bytes
    LD B, A
    LD A, E
    AND 7
    JR Z, .ceNoExtra
    INC B
.ceNoExtra:
    LD A, B
    LD (EntityAttrW), A
    LD A, D
    AND 7
    LD C, A
    LD A, (IX+1)                ; height_pixels
    ADD A, C
    ADD A, 7
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (EntityAttrH), A
    RET

; ==============================================================================
SaveEntityAttr:
    ; Calcular width_chars = sprite_width + (X%8 != 0 ? 1 : 0)
    LD A, (IX+0)                ; width_bytes
    LD B, A
    LD A, E                     ; X pixel (raw)
    AND 7
    JR Z, .noExtraW
    INC B                       ; +1 columna si no alineado
.noExtraW:
    LD A, B
    LD (EntityAttrW), A

    ; Calcular height_chars = (Y%8 + height + 7) / 8
    LD A, D                     ; Y pixel (raw)
    AND 7                       ; Y offset dentro del char
    LD C, A
    LD A, (IX+1)                ; height_pixels
    ADD A, C                    ; + Y offset
    ADD A, 7
    RRCA
    RRCA
    RRCA
    AND $1F                     ; / 8 = height_chars
    LD (EntityAttrH), A

    CALL CalcAttrAddr           ; HL = dir atributo celda (0,0)
    LD DE, EntitySavedAttr      ; DE = buffer destino

    LD A, (EntityAttrH)
    LD C, A                     ; C = filas
.saveRow:
    LD A, (EntityAttrW)
    LD B, A                     ; B = columnas
    PUSH HL                     ; Guardar inicio de fila
.saveCol:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    DJNZ .saveCol
    POP HL
    ; Siguiente fila attr: HL += 32
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC C
    JR NZ, .saveRow
    RET

; ==============================================================================
; RestoreEntityAttr - Restaura atributos guardados a VRAM
; ==============================================================================
; Escribe los valores de EntitySavedAttr de vuelta a VRAM.
; Usa EntityAttrW/H guardados por SaveEntityAttr.
;
; Entrada: D = Y pixel (alineado 8px), E = X pixel (alineado 8px)
; ==============================================================================
RestoreEntityAttr:
    CALL CalcAttrAddr           ; HL = dir atributo celda (0,0)
    LD DE, EntitySavedAttr      ; DE = buffer fuente

    LD A, (EntityAttrH)
    LD C, A
.restRow:
    LD A, (EntityAttrW)
    LD B, A
    PUSH HL
.restCol:
    LD A, (DE)
    LD (HL), A
    INC HL
    INC DE
    DJNZ .restCol
    POP HL
    PUSH DE
    LD DE, 32
    ADD HL, DE
    POP DE
    DEC C
    JR NZ, .restRow
    RET

; --- Buffer de atributos guardados POR ENTIDAD ---
; Cada entidad activa necesita su propio buffer (max 4x4=16 bytes + 2 de W/H).
; SavedAttrTable: NUM_ENTITIES * 18 bytes. Seleccionar con SetAttrSlot antes de Save/Restore.
; ---
EntitySavedAttr:    DEFS 16     ; Buffer activo (copia del slot actual)
EntityAttrW:        DEFB 0      ; width_chars del sprite actual
EntityAttrH:        DEFB 0      ; height_chars del sprite actual
SavedAttrTable:     DEFS NUM_ENTITIES * 18  ; 17 slots * 18 bytes = 306 bytes
CurrentAttrSlot:    DEFB 0      ; Indice del slot activo (0-16)

; ==============================================================================
; SetAttrSlot - Selecciona slot de atributos para una entidad
; ==============================================================================
; Entrada: A = indice de entidad (0-16)
; Carga el buffer de ese slot en EntitySavedAttr/W/H para usar Save/Restore.
; ==============================================================================
SetAttrSlot:
    LD (CurrentAttrSlot), A
    ; Calcular offset: A * 18
    LD L, A
    LD H, 0
    ADD HL, HL                  ; x2
    LD D, H
    LD E, L                     ; DE = x2
    ADD HL, HL                  ; x4
    ADD HL, HL                  ; x8
    ADD HL, HL                  ; x16
    ADD HL, DE                  ; x18
    LD DE, SavedAttrTable
    ADD HL, DE                  ; HL = &SavedAttrTable[slot*18]
    ; Copiar 18 bytes a EntitySavedAttr
    LD DE, EntitySavedAttr
    LD BC, 18
    LDIR
    RET

; ==============================================================================
; FlushAttrSlot - Guarda el buffer activo de vuelta al slot
; ==============================================================================
FlushAttrSlot:
    LD A, (CurrentAttrSlot)
    LD L, A
    LD H, 0
    ADD HL, HL                  ; x2
    LD D, H
    LD E, L
    ADD HL, HL                  ; x4
    ADD HL, HL                  ; x8
    ADD HL, HL                  ; x16
    ADD HL, DE                  ; x18
    LD DE, SavedAttrTable
    ADD HL, DE                  ; HL = destino en tabla
    EX DE, HL                   ; DE = destino
    LD HL, EntitySavedAttr      ; HL = fuente
    LD BC, 18
    LDIR
    RET

; ==============================================================================
; CalcAttrAddr - Calcula direccion de atributo para coordenadas alineadas a 8px
; ==============================================================================
; Entrada: D = Y pixel (alineado 8px), E = X pixel (alineado 8px)
; Salida: HL = direccion en zona de atributos ($5800+)
; ==============================================================================
CalcAttrAddr:
    LD A, D
    RRCA
    RRCA
    RRCA
    AND $1F                     ; Y / 8 = fila de atributo
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = fila * 32
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F                     ; X / 8 = columna
    OR L
    LD L, A
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = ATTR_BASE + fila*32 + col
    RET

; ==============================================================================
; CalcPixelAddr - Calcula dir VRAM para coordenadas alineadas a 8px
; ==============================================================================
; Entrada: D=Y pixel, E=X pixel (ambos alineados a 8)
; Salida: HL=direccion en VRAM
; Formato VRAM: H=010 Y7Y6 Y2Y1Y0, L=Y5Y4Y3 X4X3X2X1X0
; ==============================================================================
CalcPixelAddr:
    LD A, D
    AND $C0                     ; Y7 Y6
    RRA
    RRA
    RRA                         ; >> 3
    OR $40                      ; + SCREEN_BASE ($4000)
    LD H, A

    LD A, D
    AND $07                     ; Y2 Y1 Y0 (linea dentro del char)
    OR H
    LD H, A

    LD A, D
    AND $38                     ; Y5 Y4 Y3 (fila de caracter)
    ADD A, A
    ADD A, A                    ; << 2, ahora en bits 7-5 de L
    LD L, A

    LD A, E
    RRA
    RRA
    RRA
    AND $1F                     ; X / 8 = columna
    OR L
    LD L, A
    RET

; ==============================================================================
; DrawDebugInfo - Muestra coordenadas de pantalla en esquina sup-izq
; ==============================================================================
DrawDebugInfo:
    LD A, (CurrentScreenX)
    LD E, 0
    CALL .drawHexDigit

    LD A, ','
    LD E, 1
    CALL .drawChar

    LD A, (CurrentScreenY)
    LD E, 2
    CALL .drawHexDigit

    LD HL, ATTR_BASE
    LD A, WHITE | $40
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    RET

.drawHexDigit:
    AND $0F
    CP 10
    JR C, .isNum
    ADD A, 'A' - 10
    JR .drawChar
.isNum:
    ADD A, '0'
.drawChar:
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, $3C00
    ADD HL, BC

    LD D, $40
    LD B, 8
.charLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D
    DJNZ .charLoop
    RET
