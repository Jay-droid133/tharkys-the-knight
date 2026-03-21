; ==============================================================================
; MOTOR GRAFICO - Sprites y utilidades de pantalla
; ==============================================================================

ClearScreen:
    CALL ROM_CLS
    RET

; ==============================================================================
; DrawSprite - Dibuja un sprite de 16x16 con XOR en pantalla
; ==============================================================================
; Enfoque Sabre Wulf: sprites alineados a caracter (8px grid).
; XOR permite borrar redibujando el mismo sprite en la misma posicion.
;
; Entrada:
;   D = Y pixel (alineado a 8px por el caller)
;   E = X pixel (alineado a 8px por el caller)
;   IX = puntero a datos del sprite (SPRITE_W * SPRITE_H bytes)
;
; El sprite es de 2 bytes ancho (16px) x 16 lineas alto.
; Ocupa 2 columnas de caracter y 2 filas de caracter (2x2 celdas).
; ==============================================================================
DrawSprite:
    ; Calcular dir VRAM del bloque superior-izquierdo (celda 0,0)
    CALL CalcPixelAddr          ; HL = dir VRAM para (D,E)

    ; --- Dibujar mitad superior (8 lineas, celda fila 0) ---
    LD B, 8
.topHalf:
    LD A, (IX+0)                ; Byte izquierdo del sprite
    XOR (HL)                    ; XOR con pantalla
    LD (HL), A
    INC L                       ; Columna siguiente (byte derecho)
    LD A, (IX+1)
    XOR (HL)
    LD (HL), A
    DEC L                       ; Volver a columna izquierda
    INC H                       ; Siguiente linea de pixel (dentro del char)
    INC IX
    INC IX                      ; Avanzar 2 bytes en datos del sprite
    DJNZ .topHalf

    ; --- Calcular dir VRAM de la celda inferior (Y+8) ---
    LD A, D
    ADD A, 8                    ; Y + 8 = fila de caracter siguiente
    LD D, A
    CALL CalcPixelAddr          ; HL = dir VRAM para (D, E) en celda inferior

    ; --- Dibujar mitad inferior (8 lineas, celda fila 1) ---
    LD B, 8
.bottomHalf:
    LD A, (IX+0)
    XOR (HL)
    LD (HL), A
    INC L
    LD A, (IX+1)
    XOR (HL)
    LD (HL), A
    DEC L
    INC H
    INC IX
    INC IX
    DJNZ .bottomHalf

    RET

; ==============================================================================
; EraseSprite - Borra un sprite de 16x16 (pone a 0, sin XOR)
; ==============================================================================
; Mas rapido que XOR para borrar cuando no nos importa el fondo.
; Entrada: D=Y (alineado 8px), E=X (alineado 8px)
; ==============================================================================
EraseSprite:
    CALL CalcPixelAddr

    ; Mitad superior (8 lineas)
    LD B, 8
.eraseTop:
    LD (HL), 0
    INC L
    LD (HL), 0
    DEC L
    INC H
    DJNZ .eraseTop

    ; Celda inferior
    LD A, D
    ADD A, 8
    LD D, A
    CALL CalcPixelAddr

    ; Mitad inferior (8 lineas)
    LD B, 8
.eraseBot:
    LD (HL), 0
    INC L
    LD (HL), 0
    DEC L
    INC H
    DJNZ .eraseBot

    RET

; ==============================================================================
; SetSpriteAttr - Pone atributo de color en las 2x2 celdas del sprite
; ==============================================================================
; Entrada: D=Y pixel (alineado 8px), E=X pixel (alineado 8px), A=atributo
; ==============================================================================
SetSpriteAttr:
    PUSH AF                     ; Guardar atributo
    ; Calcular posicion en tabla de atributos
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
    ADD HL, HL                  ; * 32
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F                     ; X / 8 = columna
    OR L
    LD L, A
    LD BC, ATTR_BASE
    ADD HL, BC                  ; HL = dir atributo celda (0,0)

    POP AF                      ; Recuperar atributo
    ; Celda (0,0) y (0,1) - fila superior
    LD (HL), A
    INC HL
    LD (HL), A
    ; Celda (1,0) y (1,1) - fila inferior (+32 bytes)
    LD BC, 31                   ; 32 - 1 (ya avanzamos 1)
    ADD HL, BC
    LD (HL), A
    INC HL
    LD (HL), A
    RET

; ==============================================================================
; RestoreTileAttrs - Restaura los atributos de tile bajo un sprite 2x2
; ==============================================================================
; Lee los 4 tile IDs de la pantalla actual en la posicion dada y escribe
; sus atributos correctos en VRAM. Usado para "limpiar" los atributos
; blancos que deja el sprite del jugador al moverse.
;
; Entrada: D = Y pixel (alineado a 8), E = X pixel (alineado a 8)
; ==============================================================================
RestoreTileAttrs:
    ; Calcular offset = charRow * 32 + charCol
    LD A, D
    RRCA
    RRCA
    RRCA
    AND $1F                     ; charRow = Y / 8
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                  ; HL = charRow * 32
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F                     ; charCol = X / 8
    OR L
    LD L, A                     ; HL = offset = row*32 + col

    ; Calcular ambas direcciones a partir del offset
    PUSH HL                     ; Guardar offset
    LD BC, (CurrentScreenAddr)
    ADD HL, BC                  ; HL = puntero a tile data
    POP BC                      ; BC = offset
    PUSH HL                     ; Guardar tile pointer
    LD HL, ATTR_BASE
    ADD HL, BC                  ; HL = puntero a atributo VRAM
    EX DE, HL                   ; DE = attr pointer
    POP HL                      ; HL = tile pointer

    ; Celda sup-izq
    LD A, (HL)
    CALL GetTileAttr
    LD (DE), A

    ; Celda sup-der
    INC HL
    INC DE
    LD A, (HL)
    CALL GetTileAttr
    LD (DE), A

    ; Avanzar a fila siguiente (31 = 32 - 1 porque ya incrementamos 1)
    LD BC, 31
    ADD HL, BC
    EX DE, HL
    ADD HL, BC
    EX DE, HL

    ; Celda inf-izq
    LD A, (HL)
    CALL GetTileAttr
    LD (DE), A

    ; Celda inf-der
    INC HL
    INC DE
    LD A, (HL)
    CALL GetTileAttr
    LD (DE), A

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
; Formato: "X,Y" en hexadecimal (ej: "8,8" para pantalla central)
; Usa fuente ROM directamente sobre VRAM
; ==============================================================================
DrawDebugInfo:
    ; ScreenX en columna 0
    LD A, (CurrentScreenX)
    LD E, 0
    CALL .drawHexDigit

    ; Coma en columna 1
    LD A, ','
    LD E, 1
    CALL .drawChar

    ; ScreenY en columna 2
    LD A, (CurrentScreenY)
    LD E, 2
    CALL .drawHexDigit

    ; Atributos: bright blanco sobre negro para las 3 celdas
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
    ; A = codigo ASCII, E = columna (0-31)
    ; Buscar bitmap del caracter en fuente ROM ($3C00 + ascii*8)
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    LD BC, $3C00
    ADD HL, BC              ; HL = dir bitmap del caracter

    ; VRAM fila 0, columna E: dir = $4000 + E
    LD D, $40
    LD B, 8
.charLoop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC D                   ; siguiente scanline ($40->$41->...$47)
    DJNZ .charLoop
    RET
