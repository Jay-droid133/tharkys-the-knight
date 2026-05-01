; ==============================================================================
; church_cutscene.asm - Cutscene de captura de monsters en la iglesia (M7)
; ==============================================================================
; Vive en $6000+ (slot 1, bank 5, siempre visible). Solo se ejecuta una vez por
; partida durante la trampa de la iglesia. Penalty de contended ~5-10% durante
; la cinematica — invisible porque es one-shot.
; 
; Las CALLs externas a bank 0 (DrawSprite, GetOldSpriteAddr, etc.) funcionan
; sin envoltura porque bank 0 sigue paginado por defecto en slot 3.
; ID labels y tablas (StatueIdTable, ChurchTrapBitMask, etc.) son accedidos
; tambien desde bank 0 — al estar en slot 1 (siempre visible), se leen OK.
; ==============================================================================

; ==============================================================================
; EraseChurchTrappedMonster - borra el sprite del monster atrapado in-place
; ==============================================================================
; Llamada al final de la fase LOOK (antes de CloseChurchDoor) para que
; durante la fase SHAKE la puerta cerrada no muestre pixels residuales
; del monster por debajo del marco. Auto-carga IX desde
; ChurchCutsceneSlot.
; Destruye: AF, BC, DE, HL, IX (callsite debe asumir IX no preservado).
; ==============================================================================
EraseChurchTrappedMonster:
    LD A, (ChurchCutsceneSlot)
    INC A                                   ; SLOT_MONSTER0 = 1
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; * ENT_SIZE (16)
    LD DE, EntityTable
    ADD HL, DE
    PUSH HL
    POP IX
    CALL GetOldSpriteAddr                   ; OldSprAddr setado
    LD A, (IX+ENT_OLDY)
    LD D, A
    LD A, (IX+ENT_OLDX)
    LD E, A
    LD IX, (OldSprAddr)
    JP DrawSprite                           ; XOR-erase + RET tail-call

; ==============================================================================
; ApplyChurchTrapEffects - efectos finales tras el cutscene
; ==============================================================================
; - Marca slot atrapado en MonsterTrappedFlags.
; - Despawn monster (ENT_TYPE=0).
; - Cierra puerta (CloseChurchDoor patchea ptr + ScreenDirty=1).
; - Si <3 atrapados: respawnea church_key en AltN.
; - Si 3 atrapados: spawnea town_gate_key + avanza hito 7 -> 8.
; ==============================================================================
ApplyChurchTrapDone:
    ; Get IX = monster atrapado (a partir del entity slot guardado)
    LD A, (ChurchCutsceneSlot)
    INC A                                   ; SLOT_MONSTER0 = 1
    LD L, A
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL                              ; * ENT_SIZE (16)
    LD DE, EntityTable
    ADD HL, DE
    PUSH HL
    POP IX
    ; Set bit por TIPO en MonsterTrappedFlags (TypeIdx ya calculado y
    ; guardado en TriggerChurchTrap).
    LD A, (ChurchCutsceneTypeIdx)
    LD HL, ChurchTrapBitMask
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    LD HL, MonsterTrappedFlags
    OR (HL)
    LD (HL), A
    ; Avanzar al siguiente paso del orden fijo de captura.
    ; Tras step=2 (skeleton), pasa a step=3 (todos atrapados, no se resalta
    ; ninguna estatua y CheckChurchTrap rechaza cualquier monstruo).
    LD HL, NextChurchTrapStep
    INC (HL)
    ; Encender ya la estatua del siguiente esperado (no-op si step==3).
    ; Esto da feedback visual inmediato al jugador tras la cutscene de
    ; captura: el humo se disipa y la siguiente estatua parpadea ON-OFF
    ; antes de quedarse fija en blanco brillante.
    PUSH IX
    CALL StartStatueBlink
    POP IX
    ; (Erase ya ejecutado al final de fase LOOK por EraseChurchTrappedMonster.)
    ; Despawn monster: TYPE = 0 (ANIMBASE preservado para que TryRespawn lo
    ; vea y, via .rmTrapBits indexado por type, decida saltarlo).
    LD (IX+ENT_TYPE), TYPE_NONE
    LD (IX+ENT_STATE), 0
    LD (IX+ENT_DELTAX), 0
    LD (IX+ENT_DELTAY), 0
    ; (Restos ya dibujados al inicio de la fase SMOKE. En re-entradas a la
    ; sala se redibujan automaticamente desde DrawScreen .sprSkipHidden.)
    ; (CloseChurchDoor y EraseStatueAtSlot ya se ejecutaron en fases
    ; anteriores del cutscene.)
    ; Decidir spawn: 3 atrapados?
    LD A, (MonsterTrappedFlags)
    AND $07
    CP $07
    JR Z, .actdAllTrapped
    ; <3 atrapados: respawn church_key en AltN
    LD A, 1
    LD (ChurchKeySpawned), A
    LD HL, ChurchKeyAltSpawnIdx
    INC (HL)                                ; idx pasa a 1 o 2
    CALL RespawnChurchKeyAtAlt
    ; Dibujar surgical en su nueva posicion
    LD DE, BgGfx_church_key
    JP RedrawPickupByPtr
.actdAllTrapped:
    ; Los 3 monstruos atrapados: descongelar el reloj, el ciclo dia/noche
    ; reanuda desde donde se quedo al abrir la iglesia.
    XOR A
    LD (TimeFrozen), A
    LD A, 1
    LD (TownGateKeySpawned), A
    LD DE, BgGfx_town_gate_key
    CALL RedrawPickupByPtr
    LD A, (CurrentObjective)
    CP 7
    RET NZ
    INC A
    LD (CurrentObjective), A
    CALL ResolveObjectiveScreen
    LD A, $FF
    LD (PreviousObjectiveDistance), A
    RET

ChurchTrapBitMask: DEFB $01, $02, $04

; ==============================================================================
; STATUES - 3 estatuas en la iglesia, una por TIPO de monster
; ==============================================================================
; Mapeo (indexado por monster type idx = (ANIMBASE - SPRID_MONSTER_0) / 8):
;   idx 0 (SPRID_MONSTER_0 = zombi)    -> statue_zombi (213)
;   idx 1 (SPRID_MONSTER_1 = skeleton) -> statue_skeleton (212)
;   idx 2 (SPRID_MONSTER_2 = ghost)    -> statue_ghost (211)
; Indexar por tipo y no por slot porque ShuffleMonsterTypes baraja la
; asignacion slot->tipo al inicio: el "slot 0" no tiene tipo fijo.
; MonsterTrappedFlags pasa a indexarse por tipo tambien.
; ==============================================================================
StatueIdTable:
    DEFB 213        ; type idx 0: statue_zombi
    DEFB 225        ; type idx 1: statue_skeleton
    DEFB 211        ; type idx 2: statue_ghost

; ==============================================================================
; StatueBrokenIdTable - sprites de estatua "parcialmente rota". Se intercambia
; con StatueIdTable a mitad de la fase SHAKE_STATUE para reforzar la sensacion
; de que la estatua se cuartea. Mismas dimensiones (16x24) que las enteras.
; Indexado igual que StatueIdTable (por type idx).
; ==============================================================================
StatueBrokenIdTable:
    DEFB 234        ; type idx 0: statue_zombi_braking
    DEFB 235        ; type idx 1: statue_skeleton_braking
    DEFB 233        ; type idx 2: statue_ghost_braking

; ==============================================================================
; RemainsIdTable - BG sprite id de los restos que dejan los monstruos al ser
; atrapados. 16x8 (2 chars de ancho x 1 de alto). Se dibujan en la base de la
; estatua (charY + 2) cuando MonsterTrappedFlags tiene el bit del tipo set.
; Indexada por type idx (igual que StatueIdTable y MonsterTrappedFlags).
; ==============================================================================
RemainsIdTable:
    DEFB 232        ; type idx 0: zombi remains
    DEFB 231        ; type idx 1: skeleton remains
    DEFB 230        ; type idx 2: ghost remains

; ==============================================================================
; LastHiddenStatueType - Type idx del ultimo CheckStatueHidden que devolvio NZ.
; Permite al caller (DrawScreen .sprSkipHidden) dibujar los restos correctos
; sin re-buscar la estatua en CurrentScreenBuffer.
; Solo es valido si la llamada anterior a CheckStatueHidden devolvio NZ.
; ==============================================================================
LastHiddenStatueType: DEFB 0

; ==============================================================================
; Smoke frames (16x16, 3 frames) - cutscene fase SMOKE
; ==============================================================================
; Formato compatible con DrawBgSprite16XorAtPixel: header 2 bytes
; (height_px, width_bytes) + 32 bytes pixel data CPL'd (2 bytes/fila * 16 filas).
; Importados de References/smoke02-856x176-16x16.aseprite.
; ==============================================================================
SmokeFrame0:
    DEFB 16, 2                              ; height_px, width_bytes
    DEFB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
    DEFB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
    DEFB $FF,$BF, $FF,$BF, $FE,$7F, $FD,$FF
    DEFB $FD,$FF, $FE,$FF, $FE,$FF, $FE,$FF

SmokeFrame1:
    DEFB 16, 2                              ; height_px, width_bytes
    DEFB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
    DEFB $FB,$FF, $FD,$FF, $FE,$7F, $FF,$BF
    DEFB $FF,$BF, $FF,$BF, $FE,$7F, $FD,$FF
    DEFB $FD,$FF, $FE,$FF, $FE,$FF, $FE,$FF

SmokeFrame2:
    DEFB 16, 2                              ; height_px, width_bytes
    DEFB $FF,$FF, $FE,$1F, $FD,$FF, $FB,$FF
    DEFB $FB,$FF, $FD,$FF, $FE,$7F, $FF,$BF
    DEFB $FF,$BF, $FF,$BF, $FE,$FF, $FD,$FF
    DEFB $FF,$FF, $FE,$FF, $FF,$FF, $FF,$FF

SmokeFramePtrTable:
    DEFW SmokeFrame0
    DEFW SmokeFrame1
    DEFW SmokeFrame2

; ==============================================================================
; DrawSmokeFrameXor - XOR-dibuja un frame de humo en la posicion de la estatua
; ==============================================================================
; IN: A = frame idx (0..2)
; XOR-draw es reversible: la primera llamada con un frame lo dibuja, la
; segunda lo borra. Usado por la fase SMOKE de UpdateChurchCutscene.
; Posicion: ChurchCutsceneStatueOrigX/Y (top-left de la estatua original).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
DrawSmokeFrameXor:
    ADD A, A                                ; *2 (entries de 2 bytes)
    LD L, A
    LD H, 0
    LD DE, SmokeFramePtrTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                              ; DE = ptr al frame data (header+pixel)
    ; Copiar 34 bytes (header 2 + pixel 32) a BgSpriteBuffer.
    ; Source y destino accesibles sin paging (milestones bank 0,
    ; BgSpriteBuffer en RAM principal).
    EX DE, HL                               ; HL = source
    LD DE, BgSpriteBuffer
    LD BC, 34
    LDIR
    ; Pixel pos = (StatueOrigX, StatueOrigY) — top-left de la estatua original
    LD A, (ChurchCutsceneStatueOrigY)
    LD D, A
    LD A, (ChurchCutsceneStatueOrigX)
    LD E, A
    JP DrawBgSprite16XorAtPixel

; ==============================================================================
; ClearSmokeAttrs - pone a $00 (paper black, ink black) los 2x2 chars
; donde estaba el humo, al terminar la fase SMOKE de la cutscene.
; ==============================================================================
; Sin esto, los attrs originales de la estatua (paper coloreado) quedan
; visibles en esos 4 chars tras el XOR-erase del ultimo smoke frame, dando
; la sensacion de "celda de color, sin pixels". Limpiando attrs queda
; uniformemente negro -- el efecto que pidio el usuario.
;
; Posicion: (ChurchCutsceneStatueOrigX/8, ChurchCutsceneStatueOrigY/8) en
; coords de char, area 2x2. Ojo: OrigY ya tiene BG_Y_OFFSET aplicado
; (asi se guardo en ChurchCutsceneInitStatueShake), por eso es directo.
; Destruye: AF, BC, DE, HL.
; ==============================================================================
ClearSmokeAttrs:
    ; HL = $5800 + (origY/8) * 32 + (origX/8)
    LD A, (ChurchCutsceneStatueOrigY)
    SRL A : SRL A : SRL A                   ; A = char Y (post-HUD)
    LD H, 0
    LD L, A
    ADD HL, HL                              ; *2
    ADD HL, HL                              ; *4
    ADD HL, HL                              ; *8
    ADD HL, HL                              ; *16
    ADD HL, HL                              ; *32
    LD A, (ChurchCutsceneStatueOrigX)
    SRL A : SRL A : SRL A                   ; A = char X
    LD E, A
    LD D, 0
    ADD HL, DE
    LD DE, $5800
    ADD HL, DE                              ; HL = attr addr top-left del 2x2
    XOR A                                   ; paper black, ink black
    LD (HL), A                              ; (charY, charX)
    INC HL
    LD (HL), A                              ; (charY, charX+1)
    LD DE, 31
    ADD HL, DE                              ; saltar a (charY+1, charX)
    LD (HL), A
    INC HL
    LD (HL), A                              ; (charY+1, charX+1)
    RET

; ==============================================================================
; CheckStatueHidden - es esta entry de BG una estatua oculta?
; ==============================================================================
; IN:  A = sprite id
; OUT: NZ si es estatua y su slot esta atrapado (skip drawing).
;      Z si no es estatua o esta visible (draw normalmente).
; Destruye: AF, BC, HL.
; ==============================================================================
CheckStatueHidden:
    LD HL, StatueIdTable
    LD B, 3
    LD C, 0                                 ; slot index 0..2
.cshLoop:
    CP (HL)
    JR Z, .cshMatch
    INC HL
    INC C
    DJNZ .cshLoop
    XOR A                                   ; not statue -> Z (visible)
    RET
.cshMatch:
    ; A es statue id. C = slot/type idx. Comprobar bit en MonsterTrappedFlags.
    LD A, C
    LD (LastHiddenStatueType), A            ; expose type para el caller
    LD HL, ChurchTrapBitMask
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; bit mask
    LD HL, MonsterTrappedFlags
    AND (HL)
    RET                                     ; NZ si bit set (hidden), Z si no

; ==============================================================================
; EraseStatueAtSlot - borra (XOR) la estatua del slot N en la pantalla actual
; ==============================================================================
; IN: A = slot (0..2)
; Solo tiene efecto si la estatua esta colocada en la pantalla actual.
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
EraseStatueAtSlot:
    ; Get statue ID from table
    LD HL, StatueIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = statue id
    OR A
    RET Z                                   ; ID 0 = no estatua (no exportada)
    LD (.eseTargetId), A
    ; Scan CurrentScreenBuffer (formato 4B: id, charX, charY, variant; $FF = end)
    LD HL, (CurrentScreenAddr)
.eseLoop:
    LD A, (HL)
    CP $FF
    RET Z                                   ; no encontrada en esta pantalla
    LD B, A                                 ; B = current id
    LD A, (.eseTargetId)
    CP B
    JR Z, .eseFound
    LD DE, 4
    ADD HL, DE
    JR .eseLoop
.eseFound:
    ; HL en id. Avanzar a charX, charY.
    INC HL
    LD B, (HL)                              ; B = charX
    INC HL
    LD C, (HL)                              ; C = charY
    ; Cargar sprite via BgGfxPtrById[id]: id*3 -> ptr (DEFW), bank (DEFB).
    LD A, (.eseTargetId)
    LD L, A
    LD H, 0
    LD D, H
    LD E, L
    ADD HL, HL                              ; *2
    ADD HL, DE                              ; *3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                              ; DE = ptr
    INC HL
    LD A, (HL)                              ; A = bank
    PUSH BC
    EX DE, HL                               ; HL = ptr
    CALL LoadBgSpriteToBuffer               ; preserva BC
    POP BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR                    ; XOR-erase
    RET
.eseTargetId: DEFB 0

; ==============================================================================
; DrawRemainsForType - dibuja los restos del tipo de monstruo en la base de
; su estatua (charY + 2). Localiza la estatua en CurrentScreenBuffer.
; ==============================================================================
; IN:  A = type idx (0..2)
; OUT: -
; Destruye: AF, BC, DE, HL, IX.
; Si el tipo no tiene estatua en la pantalla actual, retorna sin dibujar.
; ==============================================================================
DrawRemainsForType:
    LD (.drftType), A
    ; Lookup statue id por tipo
    LD HL, StatueIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                              ; A = statue id
    OR A
    RET Z                                   ; sin estatua exportada
    LD (.drftStatueId), A
    ; Scan CurrentScreenBuffer para encontrar la estatua (formato 4B)
    LD HL, (CurrentScreenAddr)
.drftLoop:
    LD A, (HL)
    CP $FF
    RET Z                                   ; estatua no esta en esta sala
    LD B, A                                 ; B = current id
    LD A, (.drftStatueId)
    CP B
    JR Z, .drftFound
    LD DE, 4
    ADD HL, DE
    JR .drftLoop
.drftFound:
    ; HL apunta al id, +1=charX, +2=charY, +3=variant
    INC HL
    LD B, (HL)                              ; B = charX
    INC HL
    LD A, (HL)
    ADD A, 2                                ; charY + 2 (base de la estatua)
    LD C, A
    ; Lookup remains id por tipo
    LD A, (.drftType)
    LD HL, RemainsIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)
    JP DrawBgSpriteByIdAtChar               ; tail call (no-op si id 0)
.drftType:     DEFB 0
.drftStatueId: DEFB 0

; ==============================================================================
; DrawBgSpriteByIdAtChar - Dibuja un BG sprite (pixels + attrs) por id en (B, C)
; ==============================================================================
; IN: A = sprite id (lookup en BgGfxPtrById), B = charX, C = charY
;     charY se da SIN BG_Y_OFFSET (DrawBgGfxSprite lo aplica internamente).
; OUT: -
; Destruye: AF, BC, DE, HL, IX.
; ID 0 -> retorno silencioso (no exportado / sin sprite).
; Usado por: DrawScreen .sprSkipHidden (dibujar restos en lugar de estatua),
;            ApplyChurchTrapDone (dibujar restos al terminar cutscene).
; ==============================================================================
DrawBgSpriteByIdAtChar:
    OR A
    RET Z                                   ; id 0 = no sprite, salir
    PUSH BC
    LD L, A
    LD H, 0
    LD D, H
    LD E, L                                 ; DE = id
    ADD HL, HL                              ; *2
    ADD HL, DE                              ; *3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                              ; DE = ptr
    INC HL
    LD A, (HL)                              ; A = bank
    LD (CurrentBgSpriteBank), A
    EX DE, HL                               ; HL = ptr
    CALL LoadBgSpriteToBuffer               ; preserva BC
    LD IX, BgSpriteBuffer
    POP BC
    JP DrawBgGfxSprite                      ; tail call

; ==============================================================================
; DrawBgSprite16XorAtPixel - draw 16px-wide BG sprite at arbitrary pixel pos
; ==============================================================================
; Especializado para sprites de 2 bytes de ancho (16 px, como las 3 estatuas).
; Permite posicion sub-char en X (shift bits) Y (scan line).
;
; IN: BgSpriteBuffer pre-cargado con el sprite completo (header incluido).
;     D = pixel Y (0-191, post-HUD ya aplicado).
;     E = pixel X (0-255).
; Para shift>0, escribe 3 bytes por scan line; para shift=0 escribe 2.
; Solo XOR de pixels (no toca attrs).
; Destruye: AF, BC, DE, HL, IX.
; ==============================================================================
DrawBgSprite16XorAtPixel:
    LD IX, BgSpriteBuffer
    LD A, (IX+0)                            ; height_px
    OR A
    RET Z
    LD (.dbsHeight), A
    INC IX
    INC IX                                  ; -> pixel data
    ; Shift = E & 7 ; aligned X = E & ~7
    LD A, E
    AND $07
    LD (.dbsShift), A
    LD A, E
    AND $F8
    LD E, A
    CALL CalcPixelAddr                      ; HL = VRAM addr
.dbsRow:
    PUSH HL                                 ; save row start
    ; --- Byte 0 del sprite ---
    LD A, (IX+0)
    CPL                                     ; un-invert
    LD D, A                                 ; D = sprite byte
    LD E, 0                                 ; E = bits que caen al siguiente byte
    LD A, (.dbsShift)
    OR A
    JR Z, .dbsNoShift0
    LD B, A
.dbsShift0Loop:
    SRL D
    RR E
    DJNZ .dbsShift0Loop
.dbsNoShift0:
    LD A, D
    XOR (HL)
    LD (HL), A                              ; write VRAM byte 0 (sin prev carry)
    INC HL
    LD C, E                                 ; C = carry para siguiente byte
    ; --- Byte 1 del sprite ---
    LD A, (IX+1)
    CPL
    LD D, A
    LD E, 0
    LD A, (.dbsShift)
    OR A
    JR Z, .dbsNoShift1
    LD B, A
.dbsShift1Loop:
    SRL D
    RR E
    DJNZ .dbsShift1Loop
.dbsNoShift1:
    LD A, D
    OR C                                    ; combinar con carry de byte 0
    XOR (HL)
    LD (HL), A
    INC HL
    LD C, E                                 ; carry para byte final
    ; --- Byte final (solo si shift>0) ---
    LD A, (.dbsShift)
    OR A
    JR Z, .dbsNoFinal
    LD A, C
    XOR (HL)
    LD (HL), A
.dbsNoFinal:
    POP HL                                  ; restore row start
    CALL NextPixelLine
    INC IX                                  ; advance sprite ptr by 2 (width)
    INC IX
    LD A, (.dbsHeight)
    DEC A
    LD (.dbsHeight), A
    JR NZ, .dbsRow
    RET
.dbsHeight: DEFB 0
.dbsShift:  DEFB 0

; ==============================================================================
; CloseChurchDoor - cierra la puerta: erase OPEN + draw CLOSED in-place
; ==============================================================================
; Estamos por definicion en la pantalla de la iglesia (la trampa solo dispara
; aqui), asi que el redraw quirurgico siempre es valido. Pasos:
;   1. FindPickupEntryByPtr(BgGfx_old_church_door_open) -> HL = mapX byte
;   2. Leer charX/charY de la entry
;   3. Cargar OPEN al BgSpriteBuffer + DrawBgSpriteXOR -> borra pixels open
;   4. Patch ptr de la entry a BgGfx_old_church_door_closed
;   5. Cargar CLOSED + DrawBgSpriteXOR + DrawBgAttrOnly -> dibuja closed
;   6. ChurchDoorOpen = 0
; ==============================================================================
CloseChurchDoor:
    ; SFX del cierre (mismo crujido que el SFX_ChurchDoorOpen, sirve para
    ; ambos sentidos). Suena ANTES del cambio visual.
    LD HL, SFX_ChurchDoorOpen
    CALL PlaySFX
    LD DE, BgGfx_old_church_door_open
    CALL FindPickupEntryByPtr               ; HL = mapX byte si Z
    JR NZ, .ccdFlag                         ; entry no encontrada -> solo flag
    ; Leer charX (HL+4) y charY (HL+5) en BC
    PUSH HL                                 ; save mapX ptr
    LD BC, 4
    ADD HL, BC
    LD B, (HL)                              ; B = charX
    INC HL
    LD C, (HL)                              ; C = charY
    POP HL                                  ; HL = mapX ptr
    ; --- Erase OPEN sprite: cargar al buffer + XOR redraw ---
    PUSH HL
    PUSH BC
    LD HL, BgGfx_old_church_door_open
    LD A, 3
    CALL LoadBgSpriteToBuffer               ; preserva BC
    POP BC
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR                    ; borra
    POP BC
    POP HL
    ; --- Patch ptr: open -> closed ---
    INC HL : INC HL                         ; -> ptr_lo
    LD A, LOW BgGfx_old_church_door_closed
    LD (HL), A
    INC HL
    LD A, HIGH BgGfx_old_church_door_closed
    LD (HL), A
    ; --- Draw CLOSED: cargar + XOR redraw + attrs ---
    PUSH BC
    LD HL, BgGfx_old_church_door_closed
    LD A, 3
    CALL LoadBgSpriteToBuffer
    POP BC
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    POP BC
    LD IX, BgSpriteBuffer
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgAttrOnly
.ccdFlag:
    XOR A
    LD (ChurchDoorOpen), A
    RET

; ==============================================================================
; RespawnChurchKeyAtAlt - patch PickupTable entry de church_key con coords AltN
; ==============================================================================
; Lee ChurchKeyAltSpawnIdx (1 o 2) y patchea con CHURCH_KEY_ALT[1|2]_* coords.
; ==============================================================================
RespawnChurchKeyAtAlt:
    LD A, (ChurchKeyAltSpawnIdx)
    CP 1
    JR Z, .rcaAlt1
    CP 2
    JR Z, .rcaAlt2
    RET                                     ; estado raro, no hacer nada
.rcaAlt1:
    LD B, CHURCH_KEY_ALT1_SCREEN_X
    LD C, CHURCH_KEY_ALT1_SCREEN_Y
    LD D, CHURCH_KEY_ALT1_CHAR_X
    LD A, CHURCH_KEY_ALT1_CHAR_Y
    JR .rcaPatch
.rcaAlt2:
    LD B, CHURCH_KEY_ALT2_SCREEN_X
    LD C, CHURCH_KEY_ALT2_SCREEN_Y
    LD D, CHURCH_KEY_ALT2_CHAR_X
    LD A, CHURCH_KEY_ALT2_CHAR_Y
.rcaPatch:
    LD (.rcaCharY), A
    PUSH BC                                 ; preservar B=mapX, C=mapY
    PUSH DE                                 ; preservar D=charX
    LD DE, BgGfx_church_key
    CALL FindPickupEntryByPtr               ; HL = mapX byte
    POP DE
    POP BC
    JR NZ, .rcaSkip
    LD (HL), B                              ; mapX = AltN_SCREEN_X
    INC HL
    LD (HL), C                              ; mapY = AltN_SCREEN_Y
    INC HL : INC HL : INC HL                ; skip ptr_lo, ptr_hi
    LD (HL), D                              ; charX = AltN_CHAR_X
    INC HL
    LD A, (.rcaCharY)
    LD (HL), A                              ; charY = AltN_CHAR_Y
.rcaSkip:
    RET
.rcaCharY: DEFB 0

; ==============================================================================
; FindPickupEntryByPtr - busca entry en PickupTable por sprite ptr
; ==============================================================================
; Recorre TODAS las entries (active = mapX != $FE, inactive = mapX == $FE),
; comparando ptr_lo/ptr_hi con DE.
; IN:  DE = ptr buscado.
; OUT: HL = puntero al byte mapX de la entry. Z si encontrado, NZ si no.
; Destruye: AF.
; ==============================================================================
FindPickupEntryByPtr:
    LD HL, PickupTable
.fpeLoop:
    LD A, (HL)
    CP $FF
    JR Z, .fpeNotFound
    PUSH HL
    INC HL : INC HL                         ; -> ptr_lo
    LD A, (HL)
    CP E
    JR NZ, .fpeNoMatch
    INC HL
    LD A, (HL)
    CP D
    JR NZ, .fpeNoMatch
    POP HL
    XOR A                                   ; Z = encontrado
    RET
.fpeNoMatch:
    POP HL
    PUSH BC
    LD BC, 7
    ADD HL, BC
    POP BC
    JR .fpeLoop
.fpeNotFound:
    OR 1                                    ; NZ
    RET
