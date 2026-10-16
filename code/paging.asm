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
;   Bank 7: bg_gfx_c.asm (variantes forest). Antes reservado para shadow
;           screen — se renuncio porque el juego no usa double-buffering.
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
; Formato del room en FUENTE (variable-length):
;   sin tint (98% de casos, 3B): DEFB id, x, y
;   con tint (4B):               DEFB id, x|$80, y, v
;   terminador:                  DEFB $FF
; x nativo va 0-31 (5 bits); bit 7 libre para el flag "hay v siguiente".
;
; Formato en CurrentScreenBuffer tras esta rutina (FIJO 4B):
;   DEFB id, x (limpio 0-31), y, v  (v=$FF si no habia tint)
; Asi los 3 iteradores de runtime (DrawScreen, RemapScreenAttrs,
; CollisionMap) siguen leyendo 4B fijos sin cambios.
; ==============================================================================
LoadRoomToBuffer:
    ; El stack normal vive en slot 3 ($FF58). Mientras paginamos slot 3 al
    ; bank de datos, el stack normal queda fisicamente "oculto" (pero intacto
    ; en bank 0). Si una IRQ entra durante el LDIR, su PUSH PC iria al bank
    ; de datos -> corrupcion del room data que estamos leyendo.
    ;
    ; Solucion: cambiar SP a un buffer alterno en slot 1 (siempre visible)
    ; durante la copia. Asi las IRQs siguen procesandose normalmente y el
    ; tick de musica no pierde frames durante DrawScreen / transiciones.
    ;
    ; INLINEAMOS el page-switch (sin CALL intermedios) porque al inicio el
    ; SP aun apunta al stack normal con la PC del CALL pushed; un CALL aqui
    ; usaria stack normal y no podriamos garantizar atomicidad.
    LD (.lrbSavedSP), SP            ; salva SP normal (con PC + caller frame)
    LD SP, PagingAltStackTop        ; SP -> stack alterno (slot 1)
    ; --- Page bank 1 en slot 3 (inline, SIN DI) ---
    LD A, (CurrentPaging)
    AND $F8
    OR 1
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 1
    ; --- Copy + decompress loop ---
    ; HL = source (Room_Txx en bank 1, formato variable)
    ; DE = dest (CurrentScreenBuffer, formato fijo 4B)
    LD DE, CurrentScreenBuffer
.lrbLoop:
    LD A, (HL)                      ; id
    LD (DE), A
    INC HL
    INC DE
    CP $FF                          ; terminador?
    JR Z, .lrbDone
    ; Leer x (puede tener bit 7 = flag tint). B guarda el raw para test,
    ; al buffer escribimos x limpio (AND $7F).
    LD A, (HL)
    INC HL
    LD B, A                         ; B = x raw (con flag)
    AND $7F
    LD (DE), A                      ; buffer: x limpio 0-31
    INC DE
    ; Copiar y
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    ; v: si bit 7 de x estaba set, leer v de source; si no, escribir $FF.
    BIT 7, B
    JR Z, .lrbNoTint
    LD A, (HL)                      ; v desde source
    INC HL
    LD (DE), A
    INC DE
    JR .lrbLoop
.lrbNoTint:
    LD A, $FF                       ; sin tint: buffer escribe $FF
    LD (DE), A
    INC DE
    JR .lrbLoop
.lrbDone:
    ; --- Page bank 0 en slot 3 (inline) ---
    LD A, (CurrentPaging)
    AND $F8                         ; bank 0
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A                      ; slot 3 = bank 0 → stack normal accesible
    LD SP, (.lrbSavedSP)            ; restaurar SP al stack normal
    RET

.lrbSavedSP: DEFW 0

; ==============================================================================
; LoadBgSpriteToBuffer - Copia 256 B desde un BgGfx_* a BgSpriteBuffer
; ==============================================================================
; IN:  HL = puntero al sprite BG (direccion en $C000-$FFFF)
;      A  = bank (0-7) donde vive el sprite
; OUT: BgSpriteBuffer relleno con 256 B copiados. Paginacion restaurada.
;      HL destruido (no lo necesitamos tras la copia, el caller usa el buffer).
; Destruye: A, BC, DE, HL. Preserva IX, IY.
;
; Mismo patron que LoadRoomToBuffer: inline page switch + SP alterno (slot 1)
; durante la copia. IRQs siguen procesandose normalmente -> tick de musica
; no se desfasa durante DrawScreen. Sin DI/EI internos.
;
; Stage B.1: antes era hardcoded bank 3. Ahora el caller decide el bank
; leyendolo de BgGfxPtrById. Stage C dividira sprites entre bank 3 y 4.
; ==============================================================================
LoadBgSpriteToBuffer:
    ; Mismo patron que LoadRoomToBuffer: SP -> alterno antes del page switch
    ; para que las IRQs durante la copia no corrompan el stack normal (que
    ; queda fisicamente "oculto" mientras slot 3 = bank de sprite).
    LD (.lbsBankSave), A
    ; Preservar BC del caller (DrawScreen usa B=x_char, C=y_char) ANTES de
    ; cambiar SP — el PUSH va al stack normal. El LD SP siguiente preserva
    ; ese frame; al restaurar SP el POP BC final lo recupera.
    PUSH BC
    LD (.lbsSavedSP), SP            ; salva SP normal (con PC + BC pushed)
    LD SP, PagingAltStackTop        ; SP -> stack alterno (slot 1)
    ; Page bank deseado inline (SIN DI)
    LD A, (CurrentPaging)
    AND $F8
    LD B, A                         ; B = paging limpio sin bank
    LD A, (.lbsBankSave)
    AND $07                         ; safety: solo bits 0-2
    OR B                            ; merge bank en paging
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; --- P2: copia exacta con LDIR (cabecera + pixeles + cola) ---
    ; Formato: H, W|RLE, pixeles (H*W literales o stream RLE que cubre H*W),
    ; tint, AH, AW, attrs (AH*AW). Antes: literales byte a byte (42 T/B) y los
    ; RLE copiaban siempre BG_SPRITE_BUFFER_SIZE-2 B aunque ocupasen menos.
    ; tools: sprites_offline.py valida que cada stream RLE acaba en H*W justos.
    LD DE, BgSpriteBuffer
    LD A, (HL)                      ; H
    LD (DE), A
    INC HL
    INC DE
    LD C, A                         ; C = H
    LD A, (HL)                      ; W|RLE
    LD (DE), A
    INC HL
    INC DE
    LD (.lbsWsave), A
    AND $7F
    CALL .lbsMul                    ; BC = H*W (bytes de pixeles a cubrir)
    LD A, (.lbsWsave)
    RLCA
    JR C, .lbsRleTok
    CALL .lbsLdir                   ; literal: H*W bytes tal cual
    JR .lbsTail
.lbsRleTok:
    LD A, B                         ; BC = bytes de pixeles que faltan
    OR C
    JR Z, .lbsTail
    LD A, (HL)                      ; control
    LD (DE), A
    INC HL
    INC DE
    PUSH BC
    BIT 7, A
    JR NZ, .lbsRun
    LD C, A                         ; literal: A bytes
    LD B, 0
    LDIR
    JR .lbsSub                      ; A = bytes cubiertos
.lbsRun:
    AND $7F
    ADD A, 2                        ; A = longitud del run
    LDI                             ; valor del run
.lbsSub:
    POP BC
    PUSH HL
    LD H, B
    LD L, C
    LD C, A
    LD B, 0
    OR A
    SBC HL, BC                      ; faltan -= cubiertos
    LD B, H
    LD C, L
    POP HL
    JR NC, .lbsRleTok               ; (<0 = stream corrupto: cortar)
.lbsTail:
    LDI                             ; tint
    LD A, (HL)                      ; AH (sin LDI: decrementaria BC)
    LD (DE), A
    INC HL
    INC DE
    LD C, A
    LD A, (HL)                      ; AW
    LD (DE), A
    INC HL
    INC DE
    CALL .lbsMul                    ; BC = AH*AW
    CALL .lbsLdir
    JR .lbsLoadDone

; BC = A * C (8x8 -> 16). Preserva DE, HL. (SP alterno: CALL/PUSH validos)
.lbsMul:
    PUSH HL
    LD HL, 0
    LD B, H
    OR A
    JR Z, .lbsMulEnd
.lbsMulLoop:
    ADD HL, BC
    DEC A
    JR NZ, .lbsMulLoop
.lbsMulEnd:
    LD B, H
    LD C, L
    POP HL
    RET

; LDIR que no copia nada si BC = 0 (LDIR con BC = 0 copiaria 64 KB)
.lbsLdir:
    LD A, B
    OR C
    RET Z
    LDIR
    RET

.lbsLoadDone:
    ; Page bank 0 inline
    LD A, (CurrentPaging)
    AND $F8
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD SP, (.lbsSavedSP)            ; restaurar SP al stack normal
    POP BC                          ; restaurar BC del caller (estaba en stack normal)
    RET

.lbsWsave:    DEFB 0
.lbsBankSave: DEFB 0
.lbsSavedSP:  DEFW 0

; ==============================================================================
; LoadBgSpriteHeader - Copia solo la cabecera (H, W|RLE) de un BgGfx_* a
; BgSpriteBuffer+0/+1
; ==============================================================================
; Para quien solo necesita las dimensiones (BuildCollisionMap, CheckLockBump,
; CheckPickupCollect, BuildPickupRectCache). ~200 T frente a los 5.000-22.000 T
; de LoadBgSpriteToBuffer (que copia el sprite entero, 830 B si es RLE).
; Mismo patron: SP alterno (slot 1) durante la ventana, sin DI.
; IN:  HL = puntero al sprite ($C000-$FFFF), A = bank
; OUT: BgSpriteBuffer+0 = height_px, +1 = width_bytes|RLE
; Destruye: A, HL. Preserva BC, DE, IX, IY.
; ==============================================================================
LoadBgSpriteHeader:
    PUSH BC
    PUSH DE
    LD (.lbhSavedSP), SP
    LD SP, PagingAltStackTop
    AND $07
    LD E, A
    LD A, (CurrentPaging)
    AND $F8
    LD D, A                         ; D = paging con bank 0
    OR E
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    LD A, (HL)
    LD (BgSpriteBuffer), A
    INC HL
    LD A, (HL)
    LD (BgSpriteBuffer + 1), A
    LD A, D
    LD (CurrentPaging), A
    OUT (C), A                      ; BC sigue siendo $7FFD
    LD SP, (.lbhSavedSP)
    POP DE
    POP BC
    RET
.lbhSavedSP: DEFW 0

; ==============================================================================
; LoadPlazaClockPixels - Copia los 32 B de pixel data del reloj de plaza a RAM fija
; ==============================================================================
; Se llama una vez al cargar pantalla cuando se detecta BgGfx_reloj_plaza.
; DrawPlazaClock lee PlazaClockPixels cada frame sin tocar paginacion.
; ==============================================================================
LoadPlazaClockPixels:
    ; Mismo patron que LoadRoomToBuffer/LoadBgSpriteToBuffer: SP alterno en
    ; slot 1 durante la copia para no enmascarar IRQs.
    PUSH BC
    LD (.lpcpSavedSP), SP
    LD SP, PagingAltStackTop
    ; Page bank 3 inline (SIN DI)
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
    LD SP, (.lpcpSavedSP)
    POP BC
    RET

.lpcpSavedSP: DEFW 0

; ==============================================================================
; PagingAltStack - Stack alterno en slot 1 para Load*ToBuffer
; ==============================================================================
; Se usa cuando LoadRoomToBuffer / LoadBgSpriteToBuffer / LoadPlazaClockPixels
; paginan slot 3 al bank de datos. Mientras dura la copia, SP apunta aqui en
; vez de al stack normal (que vive en slot 3 = bank de datos en ese momento).
; Asi una IRQ entrante hace PUSH PC al alterno (slot 1, bank fijo) y el
; handler IRQ corre sin corromper los bytes del bank de datos que estamos
; leyendo. Resultado: las transiciones de pantalla ya no enmascaran IRQs ->
; el tick de musica a 25 Hz se mantiene exacto incluso durante DrawScreen.
;
; Tamano: 64 B = 32 niveles de PUSH. Pico real medido del handler IRQ:
;   PUSH PC (IRQ accept) + 4 PUSHes handler + 5-6 PUSH PC anidados en la
;   cadena AY_UpdatePlayerHit / upmiTickOnce->MusicAdvanceNote->AY_WriteRegSlot1
;   + algun PUSH HL en .map2NoteA  ~=  22 B pico. 64 B = 3x margen.
; ==============================================================================
PagingAltStack: DEFS 64, 0
PagingAltStackTop EQU PagingAltStack + 64
