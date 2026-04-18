; ==============================================================================
; PAGING - Control de bancos RAM del Spectrum 128K
; ==============================================================================
; Port $7FFD (write-only):
;   bits 0-2: banco RAM en slot 3 ($C000-$FFFF)
;   bit 3:    pantalla (0=normal, 1=shadow)
;   bit 4:    ROM (0=128 editor, 1=48 BASIC)
;   bit 5:    disable paging (permanent lock — NO tocar)
;
; Bancos disponibles:
;   Bank 0: mapeado en $C000-$FFFF por defecto. Contiene parte del juego actual.
;           NO tocar mientras se ejecuta codigo desde $C000+.
;   Bank 1: libre para datos nuevos (contended)
;   Bank 2: fijo en $8000-$BFFF, no paginable (no-contended)
;   Bank 3: libre para datos nuevos (contended)
;   Bank 4: libre para datos nuevos (no-contended)
;   Bank 5: pantalla en $4000-$5AFF (contended)
;   Bank 6: libre para datos nuevos (no-contended)
;   Bank 7: libre (no-contended), usar con cuidado (shadow screen)
; ==============================================================================

; Rutinas de paginacion — se ejecutan SIEMPRE desde bank 2 ($8000-$BFFF)
; para no machacarse a si mismas al cambiar de banco.

; ==============================================================================
; PageBankSlot3 - Cambia el banco en slot 3 ($C000-$FFFF)
; ==============================================================================
; Entrada: A = banco (0-7)
; Preserva: HL, DE, IX, IY
; Destruye: A, BC
; ==============================================================================
PageBankSlot3:
    AND $07                     ; asegurar solo bits 0-2
    LD B, A                     ; guardar banco nuevo
    LD A, (CurrentPaging)
    AND $F8                     ; limpiar bits de banco
    OR B                        ; poner nuevo banco
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; ==============================================================================
; InitPaging - Estado inicial de paginacion al arrancar
; ==============================================================================
; Llamar en el startup antes de cualquier acceso paginado.
; Deja bank 0 en slot 3 (que es el default del Spectrum 128K al boot).
; ==============================================================================
InitPaging:
    LD A, $10                   ; bank 0, screen normal, ROM 48, paging enabled
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET

; ==============================================================================
; LoadRoomToBuffer - Copia un Room_Txx desde bank 1 a CurrentScreenBuffer
; ==============================================================================
; IN:  HL = puntero al Room_Txx (direccion en $C000-$FFFF, en bank 1)
; OUT: CurrentScreenBuffer relleno con los bytes del room (terminador $FF).
;      Paginacion restaurada a bank 0.
; Destruye: A, BC, DE, HL
;
; Formato del room (Stage A, ID-based): secuencia de entries de 4 B
; { DEFB id, x, y, v } hasta encontrar id = $FF que marca el final.
; Copiamos el byte id, y si no es $FF tambien los 3 bytes (x, y, v).
; El engine resuelve id -> puntero via BgGfxPtrById (en bank 0).
; ==============================================================================
LoadRoomToBuffer:
    ; El stack vive en slot 3 ($FF58). Paginar con CALL a PageBankSlot3
    ; corromperia el stack: CALL empuja la direccion de retorno en bank X,
    ; el OUT cambia el slot a bank Y, RET popearia de bank Y → garbage.
    ; Por eso INLINEAMOS el page-switch aqui, sin CALL intermedios.
    ;
    ; Entre los dos OUT no se debe tocar el stack: nada de CALLs, PUSHes
    ; ni interrupciones (DI). Solo LDs al buffer.
    LD A, I                         ; P/V = IFF2 (interrupts previos)
    PUSH AF                         ; push en bank 0 (slot 3 sigue bank 0)
    DI
    ; --- Page bank 1 en slot 3 (inline) ---
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 1
    ; --- Copy loop (HL = Room_Txx en bank 1, DE = buffer) ---
    ; Formato: DEFB id, x, y, v por entrada; $FF = terminador.
    LD DE, CurrentScreenBuffer
.lrbLoop:
    LD A, (HL)                      ; id
    LD (DE), A
    INC HL
    INC DE
    CP $FF                          ; terminador?
    JR Z, .lrbDone
    ; Copiar 3 bytes mas (x, y, v)
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
    INC HL
    INC DE
    JR .lrbLoop
.lrbDone:
    ; --- Page bank 0 en slot 3 (inline) ---
    LD A, (CurrentPaging)
    AND $F8                         ; bank 0
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 → stack accesible otra vez
    ; Restaurar IFF original: si estaba deshabilitado (startup), no hacer EI
    POP AF                          ; pop desde bank 0 (el que pusimos al entrar)
    RET PO                          ; P/V odd = IFF2 era 0 → dejar DI
    EI
    RET

; ==============================================================================
; LoadBgSpriteToBuffer - Copia 256 B desde un BgGfx_* (bank 3) a BgSpriteBuffer
; ==============================================================================
; IN:  HL = puntero al sprite BG (direccion en $C000-$FFFF, bank 3)
; OUT: BgSpriteBuffer relleno con 256 B copiados. Paginacion restaurada.
;      HL destruido (no lo necesitamos tras la copia, el caller usa el buffer).
; Destruye: A, BC, DE, HL. Preserva IX, IY.
;
; Mismo patron que LoadRoomToBuffer: inline page switch (CALL corromperia el
; stack que vive en slot 3), DI durante la ventana, IFF2 preservado para no
; forzar EI prematuro en startup.
; ==============================================================================
LoadBgSpriteToBuffer:
    ; Preservar BC: los callers (DrawScreen) usan B=x_char, C=y_char y
    ; esperan que siga intacto tras la carga. Lo salvamos al principio.
    PUSH BC
    LD A, I
    PUSH AF                         ; P/V = IFF2
    DI
    ; Page bank 3 inline
    LD A, (CurrentPaging)
    AND $F8
    OR 3
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; --- Copia inteligente: parsea la cabecera y copia solo lo necesario ---
    ; Formato sprite: H, W|RLE, pixeles, tint, AH, AW, attrs
    ; Si bit 7 de W esta set → RLE, fallback a copia de 1024 B.
    ; Si no → calcular bytes exactos y copiar byte a byte.
    LD DE, BgSpriteBuffer
    ; Copiar H (header byte 0)
    LD A, (HL)
    LD (DE), A
    LD (.lbsHsave), A
    INC HL
    INC DE
    ; Copiar W|RLE (header byte 1)
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    BIT 7, A
    JR NZ, .lbsRleFallback
    AND $7F
    LD (.lbsWsave), A
    ; --- Copiar H filas de W bytes de pixeles ---
    LD A, (.lbsHsave)
    OR A
    JR Z, .lbsAfterPixels           ; H=0, sprite vacio
    LD B, A                         ; B = H (outer loop)
.lbsPixRow:
    LD A, (.lbsWsave)
    OR A
    JR Z, .lbsPixRowDone
    LD C, A                         ; C = W (inner loop)
.lbsPixCol:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    DEC C
    JR NZ, .lbsPixCol
.lbsPixRowDone:
    DJNZ .lbsPixRow
.lbsAfterPixels:
    ; --- Copiar 1 byte tint ---
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    ; --- Copiar AH, AW y luego attrs (AH filas x AW cols) ---
    LD A, (HL)
    LD (DE), A
    LD (.lbsHsave), A               ; reusar var
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    LD (.lbsWsave), A
    INC HL
    INC DE
    LD A, (.lbsHsave)
    OR A
    JR Z, .lbsLoadDone              ; sin attrs
    LD B, A
.lbsAttrRow:
    LD A, (.lbsWsave)
    OR A
    JR Z, .lbsAttrRowDone
    LD C, A
.lbsAttrCol:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    DEC C
    JR NZ, .lbsAttrCol
.lbsAttrRowDone:
    DJNZ .lbsAttrRow
    JR .lbsLoadDone

.lbsRleFallback:
    ; Sprite RLE: tamaño desconocido sin parsear, copia BG_SPRITE_BUFFER_SIZE-2
    LD BC, BG_SPRITE_BUFFER_SIZE - 2
    LDIR

.lbsLoadDone:
    ; Page bank 0 inline
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; Restaurar IFF
    POP AF
    JP PO, .lbsbNoEI                ; P/V odd = IFF2 era 0 → dejar DI
    EI
.lbsbNoEI:
    POP BC                          ; restaurar BC del caller
    RET

.lbsHsave: DEFB 0
.lbsWsave: DEFB 0

; ==============================================================================
; LoadPlazaClockPixels - Copia los 32 B de pixel data del reloj de plaza a RAM fija
; ==============================================================================
; Se llama una vez al cargar pantalla cuando se detecta BgGfx_reloj_plaza.
; DrawPlazaClock lee PlazaClockPixels cada frame sin tocar paginacion.
; ==============================================================================
LoadPlazaClockPixels:
    PUSH BC
    LD A, I
    PUSH AF
    DI
    ; Page bank 3 inline
    LD A, (CurrentPaging)
    AND $F8
    OR 3
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; Copia 32 bytes (16 rows * 2 bytes) desde BgGfx_reloj_plaza+2
    LD HL, BgGfx_reloj_plaza + 2
    LD DE, PlazaClockPixels
    LD BC, 32
    LDIR
    ; Page bank 0 inline
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    POP AF
    JP PO, .lpcpNoEI
    EI
.lpcpNoEI:
    POP BC
    RET
