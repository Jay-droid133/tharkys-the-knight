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
    CALL BuildHouseBits         ; P4: HouseIdList -> mapa de bits (CheckIfHouseSprite)
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

    ; Cutscene final (M9): el player queda totalmente confinado mientras
    ; TownGatePhase != 0. La fase 12 (slide-out) hace POSY >= SCREEN_MAX_Y
    ; intencionadamente; sin este guard una S residual en InputDirection
    ; dispararia transicion sur en plena animacion.
    LD A, (TownGatePhase)
    OR A
    RET NZ

    ; Mientras el reloj esta congelado (fase de captura en la iglesia), el
    ; jugador queda confinado a la sala. Los monstruos NO pasan por aqui:
    ; ellos usan MonsterRoomId + la AI para moverse entre salas, asi que
    ; pueden entrar/salir libremente de la iglesia mientras el jugador no.
    ; Si el jugador intenta salir por el sur (unica salida real), tocar
    ; SFX_BlockedExit con debounce para que no parezca un bug.
    LD A, (TimeFrozen)
    OR A
    JR Z, .cstNotFrozen
    LD A, (InputDirection)
    BIT 1, A                    ; S
    JR Z, .cstClearBlockFlag
    LD A, (EntityTable + ENT_POSY)
    CP SCREEN_MAX_Y
    JR C, .cstClearBlockFlag    ; no en borde sur
    ; Pulsando S y en borde sur: tocar SFX una vez por intento.
    LD A, (BlockedExitSoundFlag)
    OR A
    RET NZ                      ; ya sonó, esperar release o move
    LD A, 1
    LD (BlockedExitSoundFlag), A
    LD HL, SFX_BlockedExit
    JP PlaySFX                  ; tail call
.cstClearBlockFlag:
    XOR A
    LD (BlockedExitSoundFlag), A
    RET
.cstNotFrozen:
    ; Asegurar que el flag queda limpio cuando el reloj reanuda.
    XOR A
    LD (BlockedExitSoundFlag), A

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
    LD A, 3                             ; entró por E (cruzó W) → side 3 = E
    LD (LastEntrySide), A
    ; LastEntryCoord = (POSY - 16) / 8 (charY top-left aprox)
    LD A, (EntityTable + ENT_POSY)
    SUB 16
    SRL A : SRL A : SRL A
    LD (LastEntryCoord), A
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
    LD A, 2                             ; entró por W (cruzó E) → side 2 = W
    LD (LastEntrySide), A
    LD A, (EntityTable + ENT_POSY)
    SUB 16
    SRL A : SRL A : SRL A
    LD (LastEntryCoord), A
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
    LD A, 1                             ; entró por S (cruzó N) → side 1 = S
    LD (LastEntrySide), A
    ; LastEntryCoord = POSX / 8 (charX top-left aprox)
    LD A, (EntityTable + ENT_POSX)
    SRL A : SRL A : SRL A
    LD (LastEntryCoord), A
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
    LD A, 0                             ; entró por N (cruzó S) → side 0 = N
    LD (LastEntrySide), A
    LD A, (EntityTable + ENT_POSX)
    SRL A : SRL A : SRL A
    LD (LastEntryCoord), A
    LD A, SCREEN_MIN_Y
    LD (EntityTable + ENT_POSY), A
    JP .doTransition

.doTransition:
    ; --- Snap PlayerPOSY/POSX a mod 4 = 0 (fail-safe alignment) ----------
    ; Defensa en profundidad complementaria al snap de UpdateSpeedBuffBody.
    ; Cualquier transición sanea la alineación, así si un buff aún activo
    ; (no expirado todavía) o cualquier futura mecánica deja Y/X en mod 8
    ; ∈ {1,2,3,5,6,7}, el siguiente cruce de sala lo limpia. SCREEN_MIN/MAX
    ; (X=0/232, Y=16/168) son todos mod 4 = 0, así que para N/S/E/W donde la
    ; transición resetea un eje, este snap es no-op en ese eje. Para el eje
    ; preservado (POSY en W/E, POSX en N/S) hace el ajuste real (1-3 px).
    ; El snap nunca cruza char boundary (delta máximo 3 px), así LastEntry*
    ; abajo queda consistente con la posición snapeada.
    LD A, (EntityTable + ENT_POSY)
    AND $FC
    LD (EntityTable + ENT_POSY), A
    LD A, (EntityTable + ENT_POSX)
    AND $FC
    LD (EntityTable + ENT_POSX), A

    ; --- Bump trigger cooldown ------------------------------------------
    ; Inhibir bump triggers durante los próximos N frames. Da al jugador
    ; tiempo de asentarse en la sala nueva antes de que un trigger pueda
    ; dispararse por proximidad/inercia. 15 frames @ 25 Hz = 0.6 s.
    LD A, 15
    LD (BumpInhibitFrames), A

    ; Silenciar musica de la muerte INMEDIATAMENTE al cruzar el borde. Se hace
    ; aqui (no en el bloque de reset al final del draw de la nueva sala) para
    ; que no haya 1-2 frames de coletazo musical durante la transicion.
    ; $FD = stop-if-loopable: solo corta DeathMusic (loopable, ligada a Death
    ; entity que se despawnea ahora). Tracks one-shot (tension/sunrise/endgame)
    ; siguen sonando — no tienen sentido cortarlos al cambiar de sala.
    PUSH AF
    LD A, $FD
    CALL StartMusic
    POP AF
    LD A, (ScreenTransition)
    LD (LastScreenTransition), A
    ; Guardar posicion del player al entrar (unico punto seguro para monsters)
    LD A, (EntityTable + ENT_POSX)
    LD (LastEntryPosX), A
    LD A, (EntityTable + ENT_POSY)
    LD (LastEntryPosY), A
    CALL CalcScreenAddress
    CALL ClearNasties           ; Limpiar enemigos al cambiar de pantalla
    CALL DespawnScaredMonsters  ; Borra monsters fleeing stuck (no siguen al player en dawn)
    CALL RepositionMonstersAtEntry ; Monsters siguen al player desde la pantalla anterior
    ; SFX de transicion de pantalla (comentado para pruebas)
    ; LD HL, SFX_ScreenTransition
    ; CALL PlaySFX
    XOR A
    LD (PendingEraseCount), A   ; Cancelar erases pendientes (pantalla se borra)
    LD A, 1
    LD (ScreenDirty), A
    LD (ScreenJustRedrawn), A

    ; --- Reiniciar el patron "po-po-popo-po" de MonstersMusic en cada cruce ---
    ; Si el secuencer esta activo (Step != $FF), resetear Step=0 + Timer=1 ->
    ; el primer "po" suena en el frame inmediato de la nueva sala.
    ; Step=$FF (sentinel inactivo) -> StartMonstersMusic no se llama.
    LD A, (MonstersMusicStep)
    INC A
    CALL NZ, StartMonstersMusic

    ; --- Magic compass: BFS sincronico ANTES de DrawScreen ---
    ; Si el power-up esta activo, recalcular el path AHORA con el nuevo
    ; CurrentScreenX/Y + LastEntrySide/Coord. Sin esto, el BFS amortizado
    ; tarda 3-4 frames en converger y los primeros ticks visibles en la
    ; nueva sala parpadeaban apuntando a la direccion vieja. El sync se paga
    ; con ~10K T-states extra en el frame del cruce — el unico que ya tenia
    ; presupuesto apretado por DrawScreen, pero solo ocurre 1 vez por cruce
    ; y no afecta a los frames de gameplay normal.
    LD A, (MagicCompassTimer)
    LD B, A
    LD A, (MagicCompassTimer + 1)
    OR B
    CALL NZ, ForceComputeMagicCompassPath

    ; --- Achievement chime: sweep AY al entrar a la sala del hito ---
    ; Reusa AY_PlayCompassPickup (mismo sweep ascendente que el pickup del
    ; magic compass random). No bloqueante, canal B AY. Solo dispara al
    ; CRUZAR el borde de la sala objetivo (no cada frame).
    LD A, (ObjectiveScreenX)
    CP $FF
    JR Z, .noSouth                  ; sin objetivo resuelto -> nada
    LD HL, CurrentScreenX
    CP (HL)
    JR NZ, .noSouth                 ; X distinta -> no es la sala
    LD A, (ObjectiveScreenY)
    LD HL, CurrentScreenY
    CP (HL)
    JR NZ, .noSouth                 ; Y distinta -> no es la sala
    CALL AY_PlayCompassPickup
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

    ; --- Iterar sprites del room (formato Stage A: DEFB id, x, y, v; $FF = end) ---
    LD HL, (CurrentScreenAddr)
.sprLoop:
    LD A, (HL)                  ; A = id
    INC HL
    CP $FF
    JP Z, .drawDone
    CP RANDOM_SLOT_MARKER       ; id 210: ghost (no se dibuja, solo marker para hook)
    JR Z, .sprSkipRandom
    LD (CurrentBgSpriteId), A   ; Stage B.2: guardar id para comparaciones
    ; Skip estatua si su slot esta atrapado (paso 7 - trampa de la iglesia).
    ; CheckStatueHidden corrompe A; lo restauramos despues si no hay skip.
    PUSH HL
    CALL CheckStatueHidden
    POP HL
    JR NZ, .sprSkipHidden       ; NZ = estatua oculta, dibujar restos
    LD A, (CurrentBgSpriteId)   ; restaurar id (CheckStatueHidden corrompe A)
    JR .sprDrawIt
.sprSkipHidden:
    ; Estatua oculta: dibujar los restos del monstruo en su base
    ; (charY + 2 chars). LastHiddenStatueType lo dejo CheckStatueHidden.
    ; Se mantiene la persistencia entre entradas a la sala porque el draw
    ; loop pasa por aqui en cada DrawScreen.
    LD B, (HL)                  ; B = charX (mismo que la estatua)
    INC HL
    LD A, (HL)
    ADD A, 2                    ; charY + 2 (base de la estatua, 1 char alto)
    LD C, A
    INC HL
    INC HL                      ; skip variant
    PUSH HL                     ; preservar reader
    LD A, (LastHiddenStatueType)
    LD HL, RemainsIdTable
    LD E, A
    LD D, 0
    ADD HL, DE
    LD A, (HL)                  ; A = remains id (0 si no exportado)
    CALL DrawBgSpriteByIdAtChar ; no-op si id=0
    POP HL
    JP .sprLoop
.sprSkipRandom:
    ; id 210 (random pickup marker): no render, no collision. Skip x, y, v.
    INC HL
    INC HL
    INC HL
    JP .sprLoop
.sprDrawIt:

    ; Resolver id -> (ptr, bank) via BgGfxPtrById (bank 0, lookup sin paging).
    ; Formato: DEFW ptr, DEFB bank por entrada (3 bytes, indexado con id*3).
    PUSH HL                     ; guardar reader
    LD L, A
    LD H, 0
    LD D, H
    LD E, L                     ; DE = id
    ADD HL, HL                  ; HL = id*2
    ADD HL, DE                  ; HL = id*3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = ptr al sprite data
    INC HL
    LD A, (HL)                  ; A = bank
    LD (CurrentBgSpriteBank), A
    POP HL                      ; restaurar reader

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    LD A, (HL)                  ; A = tint variant (255=none)
    INC HL
    LD (CurrentTintVar), A
    PUSH HL                     ; Guardar puntero room data

    ; Comprobar si es sprite tipo "house" (Stage B.2: por ID, no por ptr)
    LD A, (CurrentBgSpriteId)
    CALL CheckIfHouseSprite

    ; Comprobar si es pozo (Stage B.2: por ID)
    LD A, (CurrentBgSpriteId)
    CP WELL_POZO_ID
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

    ; Comprobar si es reloj de plaza (Stage B.2: por ID)
    LD A, (CurrentBgSpriteId)
    CP RELOJ_PLAZA_ID
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

    ; DE = puntero a BgGfx sprite data. Cargar al buffer primero.
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, (CurrentBgSpriteBank) ; A = bank (leido antes del lookup)
    CALL LoadBgSpriteToBuffer   ; copia 256 B a BgSpriteBuffer
    LD IX, BgSpriteBuffer
    CALL DrawBgGfxSprite
    ; Si acabamos de pintar el pozo y hay cooldown activo, re-pintar blanco
    ; de inmediato (minimiza el flash cian al entrar en la room).
    CALL ApplyWellCooldownIfActive

    POP HL
    JP .sprLoop

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
    LD A, 3                     ; ObjectTable ptrs viven en bank 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    CALL DrawBgGfxSprite
    CALL ApplyWellCooldownIfActive   ; minimizar flash cian si es el pozo
    POP HL
    JR .objDrawLoop
.objDrawSkip:
    LD DE, 5                    ; skip DEFW ptr (2) + DEFB x (1) + DEFB y (1) + DEFB v (1)
    ADD HL, DE
    JR .objDrawLoop
.objDrawDone:

    ; Pintar tumbas que pertenecen a esta sala (ID 252, BgGfx_tomb).
    ; No participan en CollisionMap → puramente decorativas.
    CALL DrawTombstonesInRoom

    CALL BuildCollisionMap      ; Pre-computar mapa de colision para la nueva pantalla
    CALL MaiComputeFlowField    ; FlowField (bank 6) reachability desde player
    CALL BuildZoneCellList      ; lista celdas alcanzables + filtro Manhattan @ entrada
    ; Reset del sistema de la muerte: nueva sala = nuevo countdown.
    XOR A
    LD (DeathSpawned), A
    LD (DeathSubPixelAcc), A
    LD (DeathStuckCounter), A
    LD (DeathGhostMode), A
    LD (DeathInhibitInRoom), A          ; nueva sala -> levantar inhibicion
    LD (EntityTable + (SLOT_DEATH * ENT_SIZE) + ENT_TYPE), A
    LD HL, 0
    LD (DeathScreenTimer), HL       ; 16-bit reset
    LD HL, 0
    LD (DeathGhostStuckTimer), HL
    ; Silenciar musica de la muerte si estaba sonando ($FD = stop-if-loopable).
    ; Idempotente para tracks no-loopable (tension/sunrise siguen sonando).
    LD A, $FD
    CALL StartMusic
    XOR A
    LD (ScreenDirty), A
    LD A, 1
    LD (ScreenJustRedrawn), A
    ; Invalidar caché del HUD de vidas: DrawScreen borra todo el HUD area
    LD A, $FF
    LD (DrawLivesHUD.dlhLast), A

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
    ; Resaltar la estatua del monstruo esperado en la iglesia (no-op fuera
    ; de la sala). Se llama ANTES de SaveCleanAttrs para que los $47 entren
    ; en el snapshot y los enemigos al borrar restauren correctamente.
    CALL HighlightExpectedStatue
    ; Snapshot de atributos ANTES de pickups (fondo limpio sin pickups)
    CALL SaveCleanAttrs
    ; Si el cooldown del pozo sigue activo (p.ej. volvemos a la room),
    ; re-aplicar blanco sobre el cian recién pintado.
    CALL ApplyWellCooldownIfActive

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
    ; Random pickup marker (id 210): no dibujarlo. Solo es candidato de slot.
    ; El roll en room-enter pintara la pickup elegida en la posicion del slot.
    PUSH HL
    LD HL, BgGfx_random_pickup
    OR A
    SBC HL, DE
    POP HL
    JR Z, .pkDrawDormantSkip    ; mismo offset (HL en ptr_hi -> avanza 4)
    ; Pickup latente sin spawnar: no dibujarlo.
    CALL IsPickupDormant
    JR NZ, .pkDrawDormantSkip
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
    LD A, 3                     ; PickupTable ptrs viven en bank 3
    CALL LoadBgSpriteToBuffer   ; paginar, copiar a BgSpriteBuffer (preserva BC)
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
.pkDrawDormantSkip:
    ; HL apunta a ptr_hi tras IsPickupDormant: skip charX(1)+charY(1)+v(1)+next_mapX_offset = 4
    LD DE, 4
    ADD HL, DE
    JR .pkDrawLoop
.pkDrawDone:
    ; --- Random pickup sintetico (RandomSyntheticEntry) ---
    ; UpdateRandomPickup setea esta entry al entrar en sala. Si MapX != $FE,
    ; hay un pickup random en esta sala y debe pintarse con XOR como el resto.
    LD A, (RandomSynthMapX)
    CP $FE
    JR Z, .pkDrawNoSynth
    LD DE, (RandomSynthPtr)
    EX DE, HL                           ; HL = ptr
    LD A, 3                             ; pickups (life/health/stamina) en bank 3
    CALL LoadBgSpriteToBuffer
    LD A, (RandomSynthCharX)
    LD B, A
    LD A, (RandomSynthCharY)
    LD C, A
    LD A, (RandomSynthTint)
    LD (CurrentTintVar), A
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    CALL PaintSynthPickupAttrs  ; attrs hardcoded por tipo (bypass remap)
.pkDrawNoSynth:
    JP BuildPickupRectCache             ; cache rects + clear dirty (tail call)

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

    ; P4: datos de pixeles por DE (7 T/byte) en vez de IX (19 T/byte); el
    ; estado RLE vive en registros, no en variables (antes ~110-126 T/byte).
    PUSH IX
    POP DE
    INC DE
    INC DE                      ; DE -> pixel data
    LD A, (.rleFlag)
    RLCA
    JR C, .rleStart

    ; ===================== PATH LITERAL =====================
.pixRow:
    LD A, (.widthVal)
    LD B, A
    PUSH HL                     ; guardar inicio de fila VRAM
.pixCol:
    LD A, (DE)
    INC DE
    CPL                         ; des-invertir (dato almacenado CPL'd)
    LD (HL), A
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
    ; Stream RLE con chunks explicitos (sin ambiguedad token/dato):
    ;   Control $01-$7F: literal group, siguen (control) bytes raw
    ;   Control $80-$FF: run, count = (control & $7F)+2, sigue 1 byte valor
    ; Un chunk puede seguir en la fila siguiente. Registros:
    ;   C = bytes que quedan del chunk (0 = leer token), IXH = 0 literal / 1 run,
    ;   IXL = valor del run (ya des-invertido), B = bytes que quedan de la fila.
.rleStart:
    LD C, 0
.rleRow:
    LD A, (.widthVal)
    LD B, A
    PUSH HL                     ; guardar inicio de fila VRAM
    LD A, C
    OR A
    JR Z, .rleToken
    LD A, IXH                   ; chunk que viene de la fila anterior
    OR A
    JR Z, .rleLit
    LD A, IXL
    JR .rleRun
.rleToken:
    LD A, (DE)
    INC DE
    BIT 7, A
    JR NZ, .rleNewRun
    LD C, A                     ; literal group: A bytes
    LD IXH, 0
.rleLit:
    LD A, (DE)
    INC DE
    CPL
    LD (HL), A
    INC HL
    DEC C
    JR Z, .rleLitEnd
    DJNZ .rleLit
    JR .rleRowDone              ; fin de fila, el grupo sigue
.rleLitEnd:
    DJNZ .rleToken
    JR .rleRowDone
.rleNewRun:
    AND $7F
    ADD A, 2
    LD C, A                     ; longitud del run
    LD A, (DE)
    INC DE
    CPL
    LD IXL, A
    LD IXH, 1
.rleRun:
    LD (HL), A
    INC HL
    DEC C
    JR Z, .rleRunEnd
    DJNZ .rleRun
    JR .rleRowDone              ; fin de fila, el run sigue
.rleRunEnd:
    DJNZ .rleToken
.rleRowDone:
    POP HL                      ; restaurar inicio fila
    LD A, (.heightCnt)
    DEC A
    LD (.heightCnt), A
    JR Z, .pixDone
    CALL NextPixelLine
    JR .rleRow

.pixDone:
    PUSH DE
    POP IX                      ; IX -> tras los pixeles (como antes)
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

    ; P4: si ni el tint ni el remap del dia cambian nada (sin tint y de dia,
    ; o con BgSpriteSkipRemap), copiar sin las dos CALL por celda.
    LD A, (CurrentTintVar)
    INC A
    JR Z, .attrNoTint
    LD A, (CurrentTintPaper)
    INC A
    JR NZ, .attrRow             ; hay tint: camino general
.attrNoTint:
    LD A, (BgSpriteSkipRemap)
    OR A
    JR NZ, .attrFastRow
    LD A, (CurrentTimeOfDay)
    OR A
    JR NZ, .attrRow             ; noche/crepusculo: camino general
.attrFastRow:
    LD B, D                     ; B = attr_w
    PUSH HL
.attrFastCol:
    LD A, (IX+0)
    LD (HL), A
    INC IX
    INC HL
    DJNZ .attrFastCol
    POP HL
    LD BC, 32
    ADD HL, BC
    DEC E
    JR NZ, .attrFastRow
    RET

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

; Variables de tint
CurrentTintVar:   DEFB $FF    ; paper destino del placement (255=sin tint)
CurrentTintPaper: DEFB $FF    ; paper original tintable del sprite (255=no tintable)

; Bank del sprite que se va a cargar con LoadBgSpriteToBuffer. Los iteradores
; de placements (DrawScreen, RemapScreenAttrs, CollisionMap) lo leen de
; BgGfxPtrById[id].bank tras resolver el ID. HUD y otros callers con labels
; hardcoded (DrawKeyHUD, etc.) asignan 3 directamente.
CurrentBgSpriteBank: DEFB 3

; ID del sprite actualmente siendo procesado en los iteradores (Stage B.2).
; Usado por CheckIfHouseSprite (compara por ID contra HouseIdList) y por
; comparaciones con WELL_POZO_ID / RELOJ_PLAZA_ID en DrawScreen.
CurrentBgSpriteId: DEFB 0

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

    ; --- Iterar sprites del room (solo attrs, formato Stage A) ---
    LD HL, (CurrentScreenAddr)
.rsLoop:
    LD A, (HL)                  ; A = id
    INC HL
    CP $FF
    JR Z, .rsDone
    CP RANDOM_SLOT_MARKER       ; id 210: ghost (no remap, no attrs).
    JR NZ, .rsNotMarker
    INC HL : INC HL : INC HL    ; skip x, y, v
    JR .rsLoop
.rsNotMarker:
    LD (CurrentBgSpriteId), A

    ; Resolver id -> (ptr, bank) via BgGfxPtrById (formato 3B: ptr + bank)
    PUSH HL
    LD L, A
    LD H, 0
    LD D, H
    LD E, L                     ; DE = id
    ADD HL, HL                  ; HL = id*2
    ADD HL, DE                  ; HL = id*3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = ptr al sprite data
    INC HL
    LD A, (HL)                  ; A = bank
    LD (CurrentBgSpriteBank), A
    POP HL

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    LD A, (HL)                  ; A = tint variant
    INC HL
    LD (CurrentTintVar), A
    PUSH HL

    LD A, (CurrentBgSpriteId)
    CALL CheckIfHouseSprite

    ; Cargar sprite al buffer (bank variable → BgSpriteBuffer) antes de leer attrs
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, (CurrentBgSpriteBank)
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    CALL RemapBgAttrsOnly

    POP HL
    JR .rsLoop

.rsDone:
    CALL DrawClockSprite
    ; Snapshot de atributos limpios tras remap
    CALL SaveCleanAttrs
    ; Tumbas: si habia entities encima durante el remap, sus attrs entraron
    ; en ATTR_BASE y CleanAttrMap. Re-pintar cyan deja la tumba consistente.
    CALL RefreshTombAttrsForRoom
    ; Cambio de fase day/night: RemapScreenAttrs solo toca BG sprites
    ; (loop por CurrentScreenAddr). Los pickups (PickupTable, render aparte)
    ; no se remapean aqui, asi que marcamos PickupAttrsDirty=1 para que
    ; RefreshPickupAttrs los repinte con el nuevo remap en este mismo frame.
    LD A, 1
    LD (PickupAttrsDirty), A
    ; Si el cooldown sigue activo (p.ej. cambio de fase día/noche durante
    ; cooldown), re-aplicar blanco sobre el cian recien pintado.
    JP ApplyWellCooldownIfActive

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
    ; Guardar charX/charY del erase para AABB-check al final.
    LD A, D
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (.roaEraseY), A
    LD A, E
    RRCA
    RRCA
    RRCA
    AND $1F
    LD (.roaEraseX), A
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
    ; Copiar 4 celdas × 4 filas (cubre worst-case bbox unaligned de Death/Goat
    ; 24x24. Para sprites menores restaura 1-2 celdas extras de fondo, que son
    ; no-op porque ya estaban con su valor de CleanAttrMap).
    LD B, 4
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
    INC HL
    INC DE
    LD A, (HL)
    LD (DE), A
    ; Siguiente fila: avanzar 29 posiciones (32 - 3 ya avanzadas)
    PUSH BC
    LD BC, 29
    ADD HL, BC
    EX DE, HL
    ADD HL, BC
    EX DE, HL
    POP BC
    DJNZ .roaRow
    ; --- AABB-check 4x4 erase rect vs PickupRectCache ---
    ; Si solapa con algun pickup activo, set PickupAttrsDirty=1 para que
    ; RefreshPickupAttrs (post-ProcessEnemies) repinte. Sin overlap = no-op.
    LD A, (NumPickupsCached)
    OR A
    RET Z
    LD B, A                             ; B = entries
    LD HL, PickupRectCache
.roaAabbLoop:
    ; (HL+0)=pX, (HL+1)=pY, (HL+2)=pXEnd, (HL+3)=pYEnd.
    ; eraseRect = [eX..eX+3] × [eY..eY+3].
    ; Overlap: pX <= eX+3 AND pXEnd >= eX AND pY <= eY+3 AND pYEnd >= eY.
    ; eX+3 < pX -> no overlap (X)
    LD A, (.roaEraseX)
    ADD A, 3
    CP (HL)
    JR C, .roaAabbNext
    INC HL                              ; pY
    ; eY+3 < pY -> no overlap (Y)
    LD A, (.roaEraseY)
    ADD A, 3
    CP (HL)
    JR C, .roaAabbNext1
    INC HL                              ; pXEnd
    ; pXEnd < eX -> no overlap
    LD A, (HL)
    LD C, A
    LD A, (.roaEraseX)
    CP C
    JR Z, .roaAabbXEndOk
    JR NC, .roaAabbNext2
.roaAabbXEndOk:
    INC HL                              ; pYEnd
    ; pYEnd < eY -> no overlap
    LD A, (HL)
    LD C, A
    LD A, (.roaEraseY)
    CP C
    JR Z, .roaAabbHit
    JR NC, .roaAabbNext3
.roaAabbHit:
    LD A, 1
    LD (PickupAttrsDirty), A
    RET                                 ; flag set, no need to check more
.roaAabbNext3:
    INC HL                              ; advance to next entry's pX
    DJNZ .roaAabbLoop
    RET
.roaAabbNext2:
    INC HL : INC HL                     ; from pXEnd to next pX
    DJNZ .roaAabbLoop
    RET
.roaAabbNext1:
    INC HL : INC HL : INC HL            ; from pY to next pX
    DJNZ .roaAabbLoop
    RET
.roaAabbNext:
    LD DE, 4                            ; from pX to next pX
    ADD HL, DE
    DJNZ .roaAabbLoop
    RET
.roaEraseX: DEFB 0
.roaEraseY: DEFB 0

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

    ; Iterar sprites del room (formato Stage A: DEFB id, x, y, v; $FF = end)
    LD HL, (CurrentScreenAddr)
.bcmLoop:
    LD A, (HL)                  ; A = id
    INC HL
    CP $FF
    JR Z, .bcmRoomDone          ; Terminador → pasar a ObjectTable
    CP RANDOM_SLOT_MARKER       ; id 210: ghost (no es solido). Skip x, y, v.
    JR NZ, .bcmNotMarker
    INC HL
    INC HL
    INC HL
    JR .bcmLoop
.bcmNotMarker:

    ; Resolver id -> (ptr, bank) via BgGfxPtrById (formato 3B: ptr + bank)
    PUSH HL
    LD L, A
    LD H, 0
    LD D, H
    LD E, L                     ; DE = id
    ADD HL, HL                  ; HL = id*2
    ADD HL, DE                  ; HL = id*3
    LD DE, BgGfxPtrById
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = ptr al sprite data
    INC HL
    LD A, (HL)                  ; A = bank
    LD (CurrentBgSpriteBank), A
    POP HL

    LD B, (HL)                  ; B = x_char
    INC HL
    LD C, (HL)                  ; C = y_char
    INC HL
    INC HL                      ; skip tint variant byte
    PUSH HL                     ; Guardar puntero room data
    PUSH BC                     ; Guardar x_char, y_char

    ; Cargar sprite al buffer (bank variable) para leer sus dimensiones
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, (CurrentBgSpriteBank)
    CALL LoadBgSpriteHeader   ; P1: solo H/W
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
    LD A, 3                     ; ObjectTable ptrs viven en bank 3
    CALL LoadBgSpriteHeader   ; P1: solo H/W
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
    ; Pickup latente sin spawnar: tratarlo como inexistente (no bloquea).
    CALL IsPickupDormant
    JR NZ, .bcmPkAdvance
    ; Bump-trigger: marca walls siempre, sin chequear key.
    CALL IsAlwaysWall
    JR NZ, .bcmPkMarkWalls
    ; Clasificar sprite
    CALL GetPickupKeyBehavior   ; A = 0..13, preserva HL/DE/BC
    CP 8
    JR C, .bcmPkAdvance         ; <8 = normal o key (1..7), no bloquea
    SUB 7
    LD B, A                     ; B = key requerida (1..6)
    LD A, (CurrentKey)
    CP B
    JR Z, .bcmPkAdvance         ; tiene la key → candado abierto, no bloquea
.bcmPkMarkWalls:
    ; Lock activo o bump-trigger: marcar sus chars como pared
    INC HL                      ; HL en charX
    LD B, (HL)                  ; charX
    INC HL                      ; HL en charY
    LD C, (HL)                  ; charY
    INC HL                      ; HL en tint
    INC HL                      ; HL en next mapX
    PUSH HL                     ; guardar puntero a siguiente entry
    PUSH BC                     ; charX, charY
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, 3                     ; PickupTable ptrs viven en bank 3
    CALL LoadBgSpriteHeader   ; P1: solo H/W
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
    JP Z, CheckRandomSyntheticPickup    ; tras tabla normal, comprobar entry sintetica
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
    ; Random pickup marker: tratar como no-hit. La entry NO debe consumirse
    ; (no $FE'arla) — sigue siendo candidato de slot en futuros rolls.
    PUSH HL
    LD HL, BgGfx_random_pickup
    OR A
    SBC HL, DE
    POP HL
    JP Z, .cpNoHit
    ; Pickup latente sin spawnar: tratarlo como no-hit (skip de la entry).
    CALL IsPickupDormant
    JP NZ, .cpNoHit
    ; Determinar keyBehavior (0=normal, 1-7=key, 8-13=lock)
    CALL GetPickupKeyBehavior
    LD (PickupCurBehavior), A
    CP 8
    JR C, .cpBehOK              ; <8: normal o key (1..7) → sin prereq
    SUB 7
    LD B, A                     ; B = key requerida (1..6)
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
    LD A, 3                    ; pickup sprites viven en bank 3
    CALL LoadBgSpriteHeader    ; P1: el AABB solo necesita H/W
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
    JP C, .cpNoHit              ; player_right <= pk_left
    JP Z, .cpNoHit
    ; player_left < pk_right?
.cpPkW:
    LD A, 0                     ; pk_width (self-mod)
    ADD A, B                    ; A = pk_right = pk_left + pk_width
    LD B, A                     ; B = pk_right
.cpPlX2:
    LD A, (.cpPlX+1)            ; player_left (re-read)
    CP B
    JP NC, .cpNoHit             ; player_left >= pk_right
    ; vertical check
.cpPlY:
    LD A, 0                     ; player_top (self-mod)
    ADD A, 16                   ; player_bottom
.cpPkTop:
    LD B, 0                     ; pickup_top (self-mod)
    CP B
    JP C, .cpNoHit
    JP Z, .cpNoHit
.cpPkH:
    LD A, 0                     ; pk_height (self-mod)
    ADD A, B                    ; pk_bottom = pk_top + pk_height
    LD B, A
    LD A, (.cpPlY+1)            ; player_top
    CP B
    JP NC, .cpNoHit
    ; --- HIT: player overlaps pickup ---
    ; Sonido primero: PickupCurBehavior ya esta fijado (lock>=8 → crujido puerta).
    PUSH HL
    LD A, (PickupCurBehavior)
    CP 8
    JR C, .cpSfxPickup
    LD HL, SFX_ChurchDoorOpen       ; lock: creak compartido con iglesia/banco/ciudad
    JR .cpSfxPlay
.cpSfxPickup:
    LD HL, SFX_Pickup
.cpSfxPlay:
    CALL PlaySFX
    POP HL
    ; El sprite ya fue cargado a BgSpriteBuffer arriba para el AABB test.
    ; Lo reutilizamos: IX = buffer → DrawBgSpriteXOR. No hace falta volver
    ; a leer DE del entry porque el buffer es lo que el draw necesita.
    POP HL                      ; entry pointer (DEFW BgGfx_ptr)
    PUSH HL
    ; P1: el AABB solo cargo la cabecera; cargar el sprite entero para borrarlo
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL                   ; HL = BgGfx ptr (bank 3)
    LD A, 3
    CALL LoadBgSpriteToBuffer
    POP HL
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
    CP 8
    JR NC, .cpLockConsume       ; 8..13 = lock abierto → consumir key
    ; 1..7 = key recogida (incluido BankCheck en slot 7)
    LD (CurrentKey), A
    PUSH AF                             ; preservar key id para CheckMilestonePickup
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo del icono HUD para confirmar pickup
    LD (PickupFlashKey), A
    POP AF
    CALL CheckMilestonePickup           ; A = key id (1..7); avanza hito si toca
    JR .cpKeyEffectDone
.cpLockConsume:
    XOR A
    LD (CurrentKey), A
.cpKeyEffectDone:
    ; (Sonido ya reproducido al principio del HIT, antes del erase.)
    ; --- Random pickup dispatch: si el ptr es life/health/stamina, llamar Give ---
    ; HL apunta a mapX. Re-leer ptr desde la entry (mapX+2 = ptr_lo, mapX+3 = ptr_hi).
    PUSH HL
    INC HL
    INC HL
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = pickup BgGfx ptr
    POP HL                      ; HL = mapX
    PUSH HL                     ; preservar mapX durante los compares
    LD HL, BgGfx_life
    OR A
    SBC HL, DE
    POP HL
    JR NZ, .cpNotLife
    CALL GiveLife
    JR .cpAdvanceEntry
.cpNotLife:
    PUSH HL
    LD HL, BgGfx_health_pickup
    OR A
    SBC HL, DE
    POP HL
    JR NZ, .cpNotHealth
    CALL GiveHealth
    JR .cpAdvanceEntry
.cpNotHealth:
    PUSH HL
    LD HL, BgGfx_stamina_pickup
    OR A
    SBC HL, DE
    POP HL
    JR NZ, .cpNotStamina
    CALL GiveStamina
    JR .cpAdvanceEntry
.cpNotStamina:
    ; town_gate_key (llave de la ciudad, M#10): activa la brujula permanente
    ; silenciosamente — el player la necesita para encontrar la puerta sur
    ; (town_gate cutscene M#11). Setup completo equivalente a ApplyMagicCompassBuff
    ; pero SIN el tail-call a AY_Play*Pickup (el clink del pickup ya sonando).
    ;
    ; CRITICO: MagicCompassPathDirty=1 fuerza al BFS a recalcular el path al
    ; siguiente hito; sin esto el HUD no muestra nada o muestra info stale.
    PUSH HL
    LD HL, BgGfx_town_gate_key
    OR A
    SBC HL, DE
    POP HL
    JR NZ, .cpNotTownGateKey
    LD A, 1
    LD (MagicCompassPermanent), A
    LD HL, MAGIC_COMPASS_FRAMES
    LD (MagicCompassTimer), HL
    LD A, 1
    LD (MagicCompassPathDirty), A       ; fuerza BFS recompute (sin esto HUD vacio)
    XOR A
    LD (MagicCompassTickActiveFrames), A
    LD A, MAGIC_COMPASS_TICK_NORMAL
    LD (MagicCompassTickCounter), A
    LD A, $FF
    LD (MagicCompassJingleIdx), A
    LD A, HUD_PICKUP_FLASH_FRAMES       ; parpadeo del icono HUD compass al activar lasting
    LD (PickupFlashCompass), A
    JR .cpAdvanceEntry
.cpNotTownGateKey:
    PUSH HL
    LD HL, BgGfx_pickup_compass
    OR A
    SBC HL, DE
    POP HL
    JR Z, .cpDoCompass
    PUSH HL
    LD HL, BgGfx_compass_lasting
    OR A
    SBC HL, DE
    POP HL
    JR NZ, .cpAdvanceEntry
    LD A, 1
    LD (MagicCompassPermanent), A       ; lasting: marcador para hook MainLoop
.cpDoCompass:
    CALL ApplyMagicCompassBuff
    ; SFX al recoger: ApplyMagicCompassBuff ya no lo dispara para evitar el
    ; bug "dos AY_PlaySFX back-to-back". Lo disparamos aqui segun el tipo
    ; (lasting vs random). Para el caso random_pickups (synthetic), el SFX
    ; ya se disparo en .crsSpecialSfx y NO se vuelve aqui — esta call solo
    ; cubre el path editor-placed.
    LD A, (MagicCompassPermanent)
    OR A
    JR NZ, .cpDoCompassLasting
    CALL AY_PlayCompassPickup
    JR .cpAdvanceEntry
.cpDoCompassLasting:
    CALL AY_PlayLastingPickup
.cpAdvanceEntry:
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
; Slots 1..7 son KEYS (id de llave). Slots 8..13 son LOCKS (id_lock = key_id + 7).
; Cuando se toca una llave, CurrentKey = id. Al tocar un candado con la llave
; correspondiente, el candado se recoge y CurrentKey pasa a 0 (consumida).
; Entradas a DEFW 0 están deshabilitadas (sprite no importado todavía).
;
; (Histórico) Slots 10 y 11 antes eran lock-overlap. Migrados a bump-trigger
; (ahora viven en BumpTriggerTable, no aquí). Tras la inserción de BankCheck
; en slot 7, esas entradas vacías quedan en slots 11 y 12.
; ==============================================================================
KeyLockTable:
    DEFW BgGfx_forestkey            ; 1: Forest Key
    DEFW BgGfx_ruinskey             ; 2: Ruins Key
    DEFW BgGfx_cemeterykey          ; 3: Cemetery Key
    DEFW BgGfx_clock_tower_key      ; 4: ClockTower Key (id 66)
    DEFW BgGfx_church_key           ; 5: Church Key (id 191)
    DEFW BgGfx_town_gate_key        ; 6: TownGate Key (id 186)
                                    ;    Sustituible por BgGfx_BankKey una vez
                                    ;    el editor exporte id 41 — la cinematica
                                    ;    del banco suelta esta llave visualmente.
    DEFW BgGfx_BankCheck            ; 7: BankCheck (cheque dropped por church
                                    ;    cutscene; consumido por el bump trigger
                                    ;    del banco que arranca bank_cutscene).
    DEFW BgGfx_forestlock           ; 8: Forest Lock (was 7).
    DEFW BgGfx_ruinslock            ; 9: Ruins Lock (was 8).
    DEFW BgGfx_cemeterylock         ; 10: Cemetery Lock (was 9).
    ; Slots 11 y 12 antes eran lock-overlap (consume key al pisar). Migrados a
    ; bump-trigger: el sprite es sólido siempre y la acción se dispara al
    ; chocar contra él. Definidos en BumpTriggerTable + WallAlwaysTable.
    DEFW 0                          ; 11: ex-TownHall Door (was 10).
    DEFW 0                          ; 12: ex-Church Door (was 11).
    DEFW 0                          ; 13: TownGate Lock (pendiente, was 12).

; ==============================================================================
; DormantPickupTable - Pickups latentes que solo aparecen tras un trigger
; ==============================================================================
; Cada entry: ptr_sprite (DEFW), ptr_flag (DEFW). Terminada en DEFW 0.
; El bucle de pickups consulta IsPickupDormant antes de procesar cada entry:
; si su ptr está aquí y el flag vale 0, la entry se trata como inactiva.
; Cuando el flag pasa a 1 (vía side effect de un lock), el pickup aparece.
; ==============================================================================
DormantPickupTable:
    DEFW BgGfx_church_key, ChurchKeySpawned
    DEFW BgGfx_town_gate_key, TownGateKeySpawned
    DEFW BgGfx_BankCheck, BankCheckSpawned      ; cheque dropped por church cutscene (M8)
    DEFW BgGfx_compass_lasting, LastingCompassSpawned ; compass permanente (M8, ~0.6s tras cheque)
    DEFW BgGfx_arm, ArmRevealed                 ; cutscene final: flag siempre 0
    DEFW BgGfx_finger, FingerRevealed
    DEFW 0                          ; fin

; ==============================================================================
; IsPickupDormant - ¿está esta entry de pickup latente y aún no activada?
; ==============================================================================
; IN:  DE = BgGfx ptr del pickup
; OUT: A = 0 si está activo (no es dormant o flag=1), 1 si dormant inactivo.
;      Z flag set si activo (NZ si dormant).
; Preserva: BC, DE, HL.
; ==============================================================================
IsPickupDormant:
    PUSH HL
    PUSH BC
    LD HL, DormantPickupTable
.ipdLoop:
    LD A, (HL)
    INC HL
    LD B, (HL)                      ; B = ptr_hi de la entry
    INC HL
    OR B
    JR Z, .ipdActive                ; ptr 0 = fin de tabla → no es dormant
    ; HL apunta ahora a flag_lo. ptr_lo está en HL-2, ptr_hi en HL-1.
    DEC HL : DEC HL                 ; volver a ptr_lo
    LD A, (HL)
    CP E
    JR NZ, .ipdNext
    INC HL
    LD A, (HL)
    CP D
    JR NZ, .ipdNextHi
    ; ptr matchea: leer dirección del flag y consultar
    INC HL
    LD C, (HL)                      ; flag_lo
    INC HL
    LD B, (HL)                      ; flag_hi
    LD A, (BC)
    OR A
    JR NZ, .ipdActive               ; flag != 0 → activo
    LD A, 1                         ; dormant inactivo
    POP BC
    POP HL
    OR A                            ; NZ
    RET
.ipdNextHi:
    ; HL en ptr_hi tras la 2ª comparación → +3 = SIG ptr_lo
    INC HL
    INC HL
    INC HL
    JR .ipdLoop
.ipdNext:
    ; HL en ptr_lo tras la 1ª comparación → +4 = SIG ptr_lo
    INC HL
    INC HL
    INC HL
    INC HL
    JR .ipdLoop
.ipdActive:
    XOR A                           ; Z, no dormant
    POP BC
    POP HL
    RET

; ==============================================================================
; WallAlwaysTable - sprites cuyos chars son walls SIEMPRE en .bcmPkLoop.
; ==============================================================================
; Para puertas tipo bump-trigger: el sprite es sólido independientemente de si
; el player tiene la key. La key solo dispara el side effect (vía CheckBumpTriggers).
; Lista terminada en DEFW 0.
WallAlwaysTable:
    DEFW BgGfx_old_church_door_closed
    DEFW BgGfx_old_church_door_open
    DEFW BgGfx_chimes_tower_door    ; puerta del ayuntamiento (bump-trigger TownHall)
    DEFW 0
    ; Nota: el arco "Town Gate" (id 183, BgGfx_town_gate) NO entra aqui aunque
    ; sea bump-trigger. Su solidez la define el editor por celdas (BG normal),
    ; respetando el hueco del arco. Meterlo aqui forzaria walls en sus 11x9
    ; chars enteros, bloqueando tambien el hueco — y rompiendo el visual de
    ; "player enmarcado" (anchor2 cae dentro del rectangulo del arco).

; ==============================================================================
; IsAlwaysWall - ¿este sprite debe marcar siempre walls (bump-trigger)?
; ==============================================================================
; IN:  DE = BgGfx ptr
; OUT: A = 1 si está en WallAlwaysTable, 0 si no.
;      Z flag SET si NO está, NZ si SÍ está.
; Preserva: BC, DE, HL.
; ==============================================================================
IsAlwaysWall:
    PUSH HL
    PUSH BC
    LD HL, WallAlwaysTable
.iawLoop:
    LD A, (HL)
    INC HL
    LD B, (HL)
    INC HL
    OR B
    JR Z, .iawNotFound
    DEC HL : DEC HL
    LD A, (HL) : CP E : JR NZ, .iawNext
    INC HL
    LD A, (HL) : CP D : JR NZ, .iawNextHi
    ; match
    LD A, 1
    POP BC
    POP HL
    OR A                            ; NZ
    RET
.iawNextHi:
    ; HL en ptr_hi tras la 2ª comparación → +1 = SIG ptr_lo
    INC HL
    JR .iawLoop
.iawNext:
    ; HL en ptr_lo tras la 1ª comparación → +2 = SIG ptr_lo
    INC HL
    INC HL
    JR .iawLoop
.iawNotFound:
    XOR A                           ; Z
    POP BC
    POP HL
    RET

; ==============================================================================
; BumpTriggerTable - sprites que disparan acción al "chocar" (no por overlap).
; ==============================================================================
; Cada entry: ptr (DEFW), required_key (DEFB), action_id (DEFB). 4 bytes.
; Terminada en DEFW 0.
;
; Action_ids:
;   1 = TownHall: ChurchKeySpawned = 1, CurrentKey = 0.
;   2 = ChurchDoor: ChurchDoorOpen = 1, CurrentKey = 0, reescribe ptr de la
;       entry a BgGfx_old_church_door_open + rebuild CollisionMap.
;
; El sprite tiene que estar también en WallAlwaysTable para que sea sólido.
;
; NOTA: el cutscene final (action 3 = TownGate) se dispara aparte, en
; CheckTownGateTriggerBg (town_gate_cutscene.asm). El arco es BG sprite y
; no esta en PickupTable, asi que esta tabla no puede hospedarlo. La logica
; es equivalente: AABB del player vs rect del arco con tolerancia +-4.
; ==============================================================================
BumpTriggerTable:
    DEFW BgGfx_old_church_door_closed
    DEFB 5                          ; key requerida = ChurchKey
    DEFB 2                          ; action = ChurchDoor open
    DEFW BgGfx_chimes_tower_door
    DEFB 4                          ; key requerida = ClockTowerKey
    DEFB 1                          ; action = TownHall (ChurchKeySpawned=1)
    DEFW 0                          ; fin
    DEFB 0, 0

; ==============================================================================
; LookupBumpTrigger - busca un ptr en BumpTriggerTable.
; ==============================================================================
; IN:  DE = BgGfx ptr a buscar.
; OUT: A = action_id (0 si no encontrado, NZ = encontrado).
;      C = required_key (válido si A != 0).
; Preserva: DE, IX, IY. Destruye: A, BC, HL.
; ==============================================================================
LookupBumpTrigger:
    LD HL, BumpTriggerTable
.lbtLoop:
    LD C, (HL)
    INC HL
    LD B, (HL)
    INC HL
    LD A, B
    OR C
    JR Z, .lbtEnd                   ; ptr=0 → fin de tabla
    LD A, C
    CP E
    JR NZ, .lbtSkip
    LD A, B
    CP D
    JR NZ, .lbtSkip
    ; match
    LD C, (HL)                      ; key
    INC HL
    LD A, (HL)                      ; action
    OR A
    RET
.lbtSkip:
    INC HL                          ; skip key
    INC HL                          ; skip action
    JR .lbtLoop
.lbtEnd:
    XOR A
    RET

; ==============================================================================
; RedrawPickupByPtr - Localiza un pickup por su ptr en PickupTable y lo dibuja.
; ==============================================================================
; IN:  DE = BgGfx ptr del sprite a redibujar.
; Si la entry está activa (no $FE) y en la pantalla actual, carga el sprite
; al BgSpriteBuffer y lo pinta con XOR + DrawBgAttrOnly. Si no la encuentra,
; retorna sin hacer nada. Usado en .cbtActTownHall para revelar la church_key
; (que estaba dormant) sin re-renderizar la pantalla.
; Destruye: A, BC, DE, HL.
; ==============================================================================
RedrawPickupByPtr:
    LD HL, PickupTable
.rpbpLoop:
    LD A, (HL)
    CP $FF
    RET Z                       ; fin de tabla, no encontrado
    CP $FE
    JR Z, .rpbpSkipInactive
    LD B, A                     ; mapX
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .rpbpSkipMapY
    LD C, (HL)                  ; mapY
    INC HL
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .rpbpSkipPtr
    ; HL en ptr_lo. Comparar ptr con DE.
    LD A, (HL)
    CP E
    JR NZ, .rpbpSkipPtr
    INC HL                      ; HL en ptr_hi
    LD A, (HL)
    CP D
    JR NZ, .rpbpSkipPtrHi
    ; Match. HL en ptr_hi. Avanzar a charX/charY/tint.
    INC HL                      ; HL en charX
    LD B, (HL)                  ; charX
    INC HL                      ; HL en charY
    LD C, (HL)                  ; charY
    INC HL                      ; HL en tint
    LD A, (HL)
    LD (CurrentTintVar), A      ; tint correcto del placement (255 = sin tint)
    ; Cargar sprite al buffer y dibujar.
    PUSH BC
    EX DE, HL                   ; HL = sprite ptr (DE tenía el ptr)
    LD A, 3
    CALL LoadBgSpriteToBuffer   ; preserva BC interno; destruye DE, HL
    POP BC
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR        ; corrompe BC
    POP BC
    LD IX, BgSpriteBuffer
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgAttrOnly
    JP BuildPickupRectCache             ; pickup spawneado in-place: rebuild + clear dirty
.rpbpSkipInactive:
    LD BC, 7
    ADD HL, BC
    JR .rpbpLoop
.rpbpSkipMapY:
    ; HL en mapY. +6 = next mapX.
    LD BC, 6
    ADD HL, BC
    JR .rpbpLoop
.rpbpSkipPtr:
    ; HL en ptr_lo. +5 = next mapX.
    LD BC, 5
    ADD HL, BC
    JR .rpbpLoop
.rpbpSkipPtrHi:
    ; HL en ptr_hi. +4 = next mapX.
    LD BC, 4
    ADD HL, BC
    JR .rpbpLoop

; ==============================================================================
; UpdatePickupFlash - Parpadeo on/off de un pickup recién spawnado.
; ==============================================================================
; Cada PICKUP_FLASH_PERIOD frames hace un XOR redraw del sprite (toggle
; visible/invisible). Tras PickupFlashToggles toggles para de parpadear.
; Como toggles inicial es par, termina en estado visible.
; Llamado desde MainLoop tras RefreshPickupAttrs.
; ==============================================================================
UpdatePickupFlash:
    LD A, (PickupFlashToggles)
    OR A
    RET Z                       ; no hay parpadeo activo
    LD A, (PickupFlashFrames)
    DEC A
    LD (PickupFlashFrames), A
    OR A
    RET NZ                      ; aún no toca toggle
    ; Reset frame counter, decrementar toggles
    LD A, PICKUP_FLASH_PERIOD
    LD (PickupFlashFrames), A
    LD A, (PickupFlashToggles)
    DEC A
    LD (PickupFlashToggles), A
    ; Toggle XOR del sprite (church_key hardcoded por ahora)
    LD DE, BgGfx_church_key
    JP RedrawPickupByPtr        ; tail call

; ==============================================================================
; CheckBumpTriggers - cada frame, si player AABB toca un sprite bump-trigger
; ==============================================================================
; en la pantalla actual y tiene la key correcta, dispara la acción.
; Player AABB = 16×16 en (EntityTable[ENT_POSX/POSY]).
; Sprite AABB se extiende +1 pixel en cada lado para detectar "pegado".
; Como los chars del sprite son walls (vía WallAlwaysTable), el player nunca
; se solapa físicamente con él — solo puede estar pegado por algún borde.
; ==============================================================================
CheckBumpTriggers:
    ; Cooldown post-transición: si BumpInhibitFrames > 0, decrementa y skip.
    ; El decremento vive aquí (en vez de en MainLoop) para que se ejecute
    ; SOLO cuando se chequea bump — si gameplay paused, la pausa también pausa
    ; el cooldown.
    LD A, (BumpInhibitFrames)
    OR A
    JR Z, .cbtNoInhibit
    DEC A
    LD (BumpInhibitFrames), A
    RET
.cbtNoInhibit:
    XOR A
    LD (.cbtDenialFrame), A         ; reset per-frame "bump sin llave" deteccion
    LD HL, PickupTable
.cbtLoop:
    LD A, (HL)
    CP $FF
    JP Z, .cbtAllDone               ; terminator -> procesar debounce SFX y RET
    CP $FE
    JP Z, .cbtSkipInactive
    LD B, A                         ; mapX
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JP NZ, .cbtSkipMapY
    LD C, (HL)                      ; mapY
    INC HL
    LD A, (CurrentScreenY)
    CP C
    JP NZ, .cbtSkipPtr
    ; Pantalla actual: leer ptr
    PUSH HL                         ; entry en ptr_lo
    LD E, (HL)
    INC HL
    LD D, (HL)                      ; DE = ptr
    CALL LookupBumpTrigger          ; A = action, C = key
    OR A
    JP Z, .cbtPopNext               ; no es bump-trigger
    LD (.cbtAction), A              ; salvar action (B se reusa abajo)
    LD A, C
    LD (.cbtRequiredKey), A         ; key-check movido tras el AABB para detectar
                                    ; bump-sin-llave y sonar SFX_BlockedExit.
    ; Cargar sprite para conocer dimensiones y testear AABB.
    ; (action ya está en .cbtAction; BC libre para usar como dimensiones)
    EX DE, HL                       ; HL = sprite ptr
    LD A, 3                         ; PickupTable ptrs viven en bank 3
    CALL LoadBgSpriteToBuffer
    LD HL, BgSpriteBuffer
    LD A, (HL)                      ; height_px
    LD (.cbtSpH), A
    INC HL
    LD A, (HL)
    AND $7F
    ADD A, A                        ; *2
    ADD A, A                        ; *4
    ADD A, A                        ; *8 = width_px
    LD (.cbtSpW), A
    ; Recuperar charX/charY de la entry (POP HL → entry ptr_lo, +2 = charX)
    POP HL                          ; HL en ptr_lo
    PUSH HL                         ; volver a guardar para el handler
    INC HL : INC HL                 ; skip ptr
    LD A, (HL)                      ; charX
    ADD A, A : ADD A, A : ADD A, A  ; *8 = px_left
    LD (.cbtSpX), A
    INC HL
    LD A, (HL)                      ; charY
    ADD A, BG_Y_OFFSET
    ADD A, A : ADD A, A : ADD A, A  ; *8 = px_top
    LD (.cbtSpY), A
    ; AABB overlap test con extensión +SPEED_RUN pixels en cada lado.
    ; Motivo: el motor revierte el movimiento al chocar, dejando al player
    ; hasta 4 px del wall. Sin esta tolerancia, el bump nunca dispararía.
    ; Horizontal: ext_left = max(0, sprite_left - 4), ext_right = min(255, sprite_right + 4).
    LD A, (EntityTable + ENT_POSX)
    LD C, A                         ; C = player_left
    ADD A, 16                       ; A = player_right
    LD D, A
    ; ext_left: sprite_left - 4 con clamp inferior (sin underflow)
    LD A, (.cbtSpX)
    SUB 4
    JR NC, .cbtNoUnderflowL
    XOR A
.cbtNoUnderflowL:
    CP D
    JP NC, .cbtPopNext              ; ext_left >= player_right → fuera por la izquierda
    ; ext_right: sprite_right + 4 con clamp superior
    LD A, (.cbtSpW)
    LD B, A
    LD A, (.cbtSpX)
    ADD A, B                        ; sprite_right
    ADD A, 4                        ; +4
    JR NC, .cbtNoOverflowR
    LD A, $FF
.cbtNoOverflowR:
    CP C
    JP C, .cbtPopNext               ; ext_right < player_left → fuera por la derecha
    ; Vertical
    LD A, (EntityTable + ENT_POSY)
    LD C, A
    ADD A, 16
    LD D, A
    LD A, (.cbtSpY)
    SUB 4
    JR NC, .cbtNoUnderflowT
    XOR A
.cbtNoUnderflowT:
    CP D
    JP NC, .cbtPopNext
    LD A, (.cbtSpH)
    LD B, A
    LD A, (.cbtSpY)
    ADD A, B
    ADD A, 4
    JR NC, .cbtNoOverflowB
    LD A, $FF
.cbtNoOverflowB:
    CP C
    JP C, .cbtPopNext
    ; HIT: el AABB del player solapa este bump-trigger.
    POP HL                          ; HL en ptr_lo de la entry
    ; Llave correcta? Si no, denial sonoro (debouncado al final del frame).
    LD A, (CurrentKey)
    LD B, A
    LD A, (.cbtRequiredKey)
    CP B
    JR Z, .cbtKeyMatch
    ; Bump sin llave. La puerta del AYUNTAMIENTO (action 1, ClockTowerKey) se
    ; queda silenciosa por decision de diseño; el resto (church door, etc.)
    ; suena el SFX_BlockedExit con debounce. La puerta de la CIUDAD vive en
    ; CheckTownGateTriggerBg (bank 7) y gestiona su propio denial allí.
    LD A, (.cbtAction)
    CP 1
    JP Z, .cbtAdvanceAfterAction    ; town hall: silencioso
    LD A, 1
    LD (.cbtDenialFrame), A
    JP .cbtAdvanceAfterAction
.cbtKeyMatch:
    LD A, (.cbtAction)              ; A = action
    CP 1
    JR Z, .cbtActTownHall
    CP 2
    JR Z, .cbtActChurchDoor
    JP .cbtAdvanceAfterAction
.cbtActTownHall:
    ; Tocar la puerta del ayuntamiento con la ClockTower Key revela la
    ; church_key (estaba dormant via DormantPickupTable) y la dibuja
    ; in-place. Inicia parpadeo para llamar la atención.
    ; SFX primero (clink): el jugador oye la llave caer ANTES de verla
    ; aparecer. PlaySFX corrompe HL/AF/BC/DE -> PUSH/POP del entry ptr.
    PUSH HL
    LD HL, SFX_KeyDrop
    CALL PlaySFX
    POP HL
    LD A, 1
    LD (ChurchKeySpawned), A
    XOR A
    LD (CurrentKey), A
    LD DE, BgGfx_church_key
    CALL RedrawPickupByPtr
    ; (Tras RedrawPickupByPtr HL queda corrupto; .cbtAdvanceAfterAction lo
    ; tolera porque el +5 cae sobre datos del entry siguiente o terminator.)
    ; Iniciar parpadeo: 6 toggles (par → termina visible) cada PICKUP_FLASH_PERIOD frames.
    LD A, 6
    LD (PickupFlashToggles), A
    LD A, PICKUP_FLASH_PERIOD
    LD (PickupFlashFrames), A
    LD A, 1                             ; action 1 = TownHall
    CALL CheckMilestoneTrigger
    JP .cbtAdvanceAfterAction
.cbtActChurchDoor:
    ; Abrir iglesia: si la muerte ya estaba activa en sala, matarla con puff.
    ; Y bloquear su respawn hasta que el player cambie de sala — la cinematica
    ; de captura debe correr sin interferencia de la muerte. La inhibicion se
    ; limpia en screen_system al hacer reset de DeathSpawned.
    PUSH HL
    CALL KillDeathIfActive
    POP HL
    LD A, 1
    LD (DeathInhibitInRoom), A
    LD (ChurchDoorOpen), A
    LD (ChurchEverOpened), A    ; sticky: no se limpia al cerrar puerta
    LD (TimeFrozen), A          ; congela reloj hasta atrapar los 3 monstruos
    XOR A
    LD (CurrentKey), A
    ; SFX: crujido de puerta vieja
    PUSH HL
    LD HL, SFX_ChurchDoorOpen
    CALL PlaySFX
    POP HL
    ; HL en ptr_lo de la entry. Leer charX/charY (bytes +2, +3 tras INC ptr).
    PUSH HL
    INC HL : INC HL                 ; HL en charX
    LD B, (HL)                      ; B = charX
    INC HL
    LD C, (HL)                      ; C = charY
    POP HL                          ; HL en ptr_lo
    ; BgSpriteBuffer todavía contiene el sprite cerrado (cargado en AABB test).
    ; Borrarlo con XOR redraw en su posición.
    PUSH HL
    PUSH BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    POP BC
    POP HL
    ; Reescribir el ptr de la entry a la versión "open".
    LD A, LOW BgGfx_old_church_door_open
    LD (HL), A
    INC HL
    LD A, HIGH BgGfx_old_church_door_open
    LD (HL), A
    DEC HL                          ; HL en ptr_lo otra vez
    ; Cargar el sprite "open" al buffer (bank 3) y dibujarlo + atributos.
    PUSH HL
    PUSH BC
    LD HL, BgGfx_old_church_door_open
    LD A, 3
    CALL LoadBgSpriteToBuffer       ; preserva BC
    LD IX, BgSpriteBuffer
    CALL DrawBgSpriteXOR
    POP BC
    PUSH BC
    LD IX, BgSpriteBuffer
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgAttrOnly
    POP BC
    POP HL                          ; HL en ptr_lo
    ; Forzar medianoche al abrir iglesia: garantizar que la transicion a N2
    ; (bells + windows off + monster spawn + statue blink) sucede SIEMPRE,
    ; incluso si BellsTriggered=1 por bells naturales de noches anteriores.
    ; Antes condicionabamos por BellsTriggered, lo que hacia que abrir la
    ; iglesia en dia 2+ solo encendiese la statue sin re-disparar la noche.
    PUSH HL
    LD A, (CurrentTimeOfDay)
    CP 4
    JR Z, .cbtChurchAlreadyN2           ; ya en N2 (bells sonaron esta noche): solo statue blink
    XOR A
    LD (BellsTriggered), A              ; reset para forzar re-trigger fresh
    CALL TriggerChurchMidnight          ; warp a 00:00 + bells + UpdateBellsDoneTimer encadena el resto
    JR .cbtChurchTriggerDone
.cbtChurchAlreadyN2:
    CALL StartStatueBlink               ; bells naturales ya sonaron + estamos en N2: encender ya
.cbtChurchTriggerDone:
    POP HL
    JP .cbtAdvanceAfterAction
.cbtAdvanceAfterAction:
    ; HL en ptr_lo. Skip 5 (ptr+charX+charY+tint = next mapX).
    LD DE, 5
    ADD HL, DE
    JP .cbtLoop
.cbtPopNext:
    POP HL                          ; recuperar entry pointer (ptr_lo)
.cbtSkipPtr:
    ; HL en ptr_lo. Skip 5 al siguiente mapX.
    LD DE, 5
    ADD HL, DE
    JP .cbtLoop
.cbtSkipMapY:
    ; HL en mapY. Skip 6 al siguiente mapX.
    LD DE, 6
    ADD HL, DE
    JP .cbtLoop
.cbtSkipInactive:
    LD DE, 7
    ADD HL, DE
    JP .cbtLoop

; Fin del loop: procesa el debounce del SFX_BlockedExit para cerrojos sin llave.
; Misma semantica que BlockedExitSoundFlag (intento de salir de iglesia durante
; cinematica): flag 1 = ya sono este contacto -> espera fin de contacto para
; re-armar. .cbtDenialFrame es scratch per-frame; BlockedBumpSoundFlag persiste.
.cbtAllDone:
    LD A, (.cbtDenialFrame)
    OR A
    JR Z, .cbtNoDenialFrame
    LD A, (BlockedBumpSoundFlag)
    OR A
    RET NZ                          ; ya sono este contacto, no replay
    LD A, 1
    LD (BlockedBumpSoundFlag), A
    LD HL, SFX_BlockedExit
    JP PlaySFX                      ; tail call
.cbtNoDenialFrame:
    XOR A
    LD (BlockedBumpSoundFlag), A    ; sin contacto este frame -> listo para el siguiente
    RET

.cbtSpX:    DEFB 0
.cbtSpY:    DEFB 0
.cbtSpW:    DEFB 0
.cbtSpH:    DEFB 0
.cbtAction: DEFB 0
.cbtRequiredKey: DEFB 0
.cbtDenialFrame: DEFB 0

; ==============================================================================
; CheckLockBump - SFX al chocar contra un cerrojo de bioma sin la llave
; ==============================================================================
; Cubre los slots 8-10 de KeyLockTable: forest, ruins y cemetery locks. Estos
; locks son walls del BG (no bump-triggers), asi que el player rebota sin SFX
; cuando no tiene la llave. Esta rutina detecta el "bump" con tolerancia +4 px
; (igual que CheckBumpTriggers) y suena SFX_BlockedExit una vez por contacto.
;
; Estructura paralela a CheckBumpTriggers (mismo loop sobre PickupTable, mismo
; AABB +4 tol), pero filtra por GetPickupKeyBehavior >= 8 en lugar de mirar
; BumpTriggerTable. Si el player tiene la llave correcta (CurrentKey ==
; behavior-7), salta el entry: que el overlap normal de pickups lo abra.
;
; Iglesia/Ayuntamiento NO entran aqui (sus puertas viven en BumpTriggerTable,
; no en KeyLockTable → GetPickupKeyBehavior devuelve 0).
;
; Llamado cada frame desde MainLoop tras CheckBankTriggerBg.
; ==============================================================================
CheckLockBump:
    LD A, (BumpInhibitFrames)
    OR A
    RET NZ                          ; cooldown post-transición
    XOR A
    LD (.clbDenialFrame), A
    LD HL, PickupTable
.clbLoop:
    LD A, (HL)
    CP $FF
    JP Z, .clbAllDone               ; terminator
    CP $FE
    JP Z, .clbSkipInactive
    LD B, A                         ; mapX
    INC HL
    LD A, (CurrentScreenX)
    CP B
    JP NZ, .clbSkipMapY
    LD C, (HL)                      ; mapY
    INC HL
    LD A, (CurrentScreenY)
    CP C
    JP NZ, .clbSkipPtr
    ; Pantalla actual
    PUSH HL                         ; entry en ptr_lo
    LD E, (HL)
    INC HL
    LD D, (HL)                      ; DE = sprite ptr
    CALL GetPickupKeyBehavior       ; A = 0 normal / 1-7 key / 8-13 lock; preserva BC/DE/HL
    CP 8
    JP C, .clbPopNext               ; no es lock -> skip (incl. bump-trigger doors, que devuelven 0)
    SUB 7
    LD B, A                         ; B = key requerida (1-6)
    LD A, (CurrentKey)
    CP B
    JP Z, .clbPopNext               ; tiene la llave: que el overlap normal la abra
    ; Lock sin llave: medir sprite + AABB +4 tolerance.
    EX DE, HL                       ; HL = sprite ptr (bank 3)
    LD A, 3
    CALL LoadBgSpriteHeader         ; P1: solo H/W; entry sigue en stack
    LD HL, BgSpriteBuffer
    LD A, (HL)                      ; height_px
    LD (.clbSpH), A
    INC HL
    LD A, (HL)
    AND $7F
    ADD A, A
    ADD A, A
    ADD A, A                        ; *8 = width_px
    LD (.clbSpW), A
    ; charX/charY de la entry
    POP HL                          ; HL en ptr_lo de la entry
    PUSH HL                         ; re-guardar
    INC HL
    INC HL                          ; skip ptr -> HL en charX
    LD A, (HL)                      ; charX
    ADD A, A
    ADD A, A
    ADD A, A                        ; *8 = px_left
    LD (.clbSpX), A
    INC HL
    LD A, (HL)                      ; charY
    ADD A, BG_Y_OFFSET
    ADD A, A
    ADD A, A
    ADD A, A                        ; *8 = px_top
    LD (.clbSpY), A
    ; AABB con +4 px tolerance en cada lado. Player rect 16x21 (alto real).
    LD A, (EntityTable + ENT_POSX)
    LD C, A                         ; C = player_left
    ADD A, 16
    LD D, A                         ; D = player_right
    LD A, (.clbSpX)
    SUB 4
    JR NC, .clbNoUnderL
    XOR A
.clbNoUnderL:
    CP D
    JP NC, .clbPopNext
    LD A, (.clbSpW)
    LD B, A
    LD A, (.clbSpX)
    ADD A, B
    ADD A, 4
    JR NC, .clbNoOverR
    LD A, $FF
.clbNoOverR:
    CP C
    JP C, .clbPopNext
    ; Vertical (player rect alto real = 21 px; ver project_player_collision_rect)
    LD A, (EntityTable + ENT_POSY)
    LD C, A                         ; player_top
    ADD A, 21
    LD D, A                         ; player_bottom
    LD A, (.clbSpY)
    SUB 4
    JR NC, .clbNoUnderT
    XOR A
.clbNoUnderT:
    CP D
    JP NC, .clbPopNext
    LD A, (.clbSpH)
    LD B, A
    LD A, (.clbSpY)
    ADD A, B
    ADD A, 4
    JR NC, .clbNoOverB
    LD A, $FF
.clbNoOverB:
    CP C
    JP C, .clbPopNext
    ; HIT: AABB+4 tol overlap con lock sin llave -> marcar denial.
    POP HL                          ; HL en ptr_lo de la entry
    LD A, 1
    LD (.clbDenialFrame), A
    JP .clbAdvanceAfterAction
.clbAdvanceAfterAction:
    LD DE, 5
    ADD HL, DE
    JP .clbLoop
.clbPopNext:
    POP HL                          ; recuperar entry pointer
.clbSkipPtr:
    LD DE, 5
    ADD HL, DE
    JP .clbLoop
.clbSkipMapY:
    LD DE, 6
    ADD HL, DE
    JP .clbLoop
.clbSkipInactive:
    LD DE, 7
    ADD HL, DE
    JP .clbLoop
.clbAllDone:
    LD A, (.clbDenialFrame)
    OR A
    JR Z, .clbNoDenial
    LD A, (LockBumpSoundFlag)
    OR A
    RET NZ                          ; ya sonó este contacto
    LD A, 1
    LD (LockBumpSoundFlag), A
    LD HL, SFX_BlockedExit
    JP PlaySFX                      ; tail call (slot 1 -> slot 1, sin thunk)
.clbNoDenial:
    XOR A
    LD (LockBumpSoundFlag), A
    RET

.clbSpX: DEFB 0
.clbSpY: DEFB 0
.clbSpW: DEFB 0
.clbSpH: DEFB 0
.clbDenialFrame: DEFB 0

; ==============================================================================
; GetPickupKeyBehavior - Devuelve el comportamiento de un pickup según su sprite
; ==============================================================================
; IN:  DE = BgGfx pointer
; OUT: A = 0 (normal), 1..7 (key), 8..13 (lock con key requerida = A-7)
; Preserva: BC, DE, HL. Slots con DEFW 0 nunca matchean (DE es ptr válido != 0).
; ==============================================================================
GetPickupKeyBehavior:
    PUSH HL
    PUSH BC
    LD HL, KeyLockTable
    LD B, 13                    ; 13 slots (insertado BankCheck en slot 7)
    LD C, 1                     ; id actual (1..13)
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
; RefreshPickupAttrs - Repinta los atributos de los pickups activos del room actual
; ==============================================================================
; Los enemigos restauran atributos desde CleanAttrMap (que NO incluye pickups)
; cuando se borran. Después de que pasen por encima de un pickup, los chars
; quedan con attrs de fondo y el pickup pierde su color característico. Esta
; función se llama una vez por frame después de ProcessEnemies para re-pintar
; los attrs de cada pickup activo en el room actual.
; ==============================================================================
RefreshPickupAttrs:
    LD A, (PickupAttrsDirty)
    OR A
    RET Z                       ; nada erased sobre un pickup -> no-op
    XOR A
    LD (PickupAttrsDirty), A
    LD HL, PickupTable
.rpaLoop:
    LD A, (HL)
    CP $FF
    RET Z
    CP $FE
    JR Z, .rpaInactive          ; HL en mapX
    LD B, A                     ; mapX
    INC HL
    LD C, (HL)                  ; mapY
    INC HL                      ; HL en ptr_lo
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .rpaSkip
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .rpaSkip
    ; Pantalla correcta: cargar sprite y pintar attrs
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx ptr
    INC HL                      ; HL en charX
    LD B, (HL)                  ; charX
    INC HL
    LD C, (HL)                  ; charY
    INC HL
    LD A, (HL)                  ; tint variant
    INC HL                      ; HL en siguiente mapX
    LD (CurrentTintVar), A
    PUSH HL                     ; guardar puntero a siguiente entry
    PUSH BC                     ; charX, charY (LoadBgSpriteToBuffer preserva BC, pero por seguridad)
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, 3                     ; ObjectTable (attrs) ptrs viven en bank 3
    CALL LoadBgSpriteToBuffer
    POP BC
    LD IX, BgSpriteBuffer
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgAttrOnly         ; solo attrs
    POP HL                      ; recuperar puntero a siguiente entry
    JR .rpaLoop
.rpaSkip:
    ; HL en ptr_lo. Skip 5 (ptr_lo, ptr_hi, charX, charY, tint) al siguiente mapX.
    LD DE, 5
    ADD HL, DE
    JR .rpaLoop
.rpaInactive:
    ; HL en mapX ($FE). Skip 7.
    LD DE, 7
    ADD HL, DE
    JR .rpaLoop

; ==============================================================================
; BuildPickupRectCache - Para cada pickup ACTIVO (no dormant) en la pantalla
; actual, lee H/W del sprite header y guarda (charX, charY, charXEnd, charYEnd)
; inclusivo en PickupRectCache. Llamada al final de DrawScreen y tras
; RedrawPickupByPtr (cuando un pickup pasa de dormant->active).
; Usado por RestoreOldAttr para AABB-check sin paginar bank cada frame.
; Tambien resetea PickupAttrsDirty (DrawScreen acaba de pintar attrs frescos).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
BuildPickupRectCache:
    XOR A
    LD (NumPickupsCached), A
    LD (PickupAttrsDirty), A    ; attrs frescos tras DrawScreen
    LD HL, PickupTable
.bprcLoop:
    LD A, (HL)
    CP $FF
    RET Z
    CP $FE
    JR Z, .bprcInactive
    LD B, A                     ; B = mapX
    INC HL
    LD C, (HL)                  ; C = mapY
    INC HL                      ; HL -> ptr_lo
    LD A, (CurrentScreenX)
    CP B
    JR NZ, .bprcSkipFromPtrLo
    LD A, (CurrentScreenY)
    CP C
    JR NZ, .bprcSkipFromPtrLo
    ; Pickup en esta sala. Leer ptr.
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx ptr
    INC HL                      ; HL -> charX
    ; Random pickup marker: no es pickup activo (no se dibuja). No cachear.
    PUSH HL
    LD HL, BgGfx_random_pickup
    OR A
    SBC HL, DE
    POP HL
    JR Z, .bprcSkipFromCharX
    ; Dormant? IsPickupDormant preserva BC, DE, HL.
    CALL IsPickupDormant
    JR NZ, .bprcSkipFromCharX
    ; Cache lleno?
    LD A, (NumPickupsCached)
    CP MAX_PICKUPS_CACHED
    JR NC, .bprcSkipFromCharX
    ; Cargar header del sprite (necesario para H, W).
    PUSH HL                     ; save HL @ charX
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, 3
    CALL LoadBgSpriteHeader     ; P1: solo H/W; preserva BC
    POP HL                      ; HL @ charX
    ; Append a cache: IX = PickupRectCache + idx*4
    PUSH HL                     ; save HL @ charX
    LD A, (NumPickupsCached)
    INC A
    LD (NumPickupsCached), A
    DEC A
    ADD A, A
    ADD A, A                    ; A = idx*4
    LD E, A
    LD D, 0
    LD HL, PickupRectCache
    ADD HL, DE                  ; HL = slot
    PUSH HL
    POP IX                      ; IX = slot
    POP HL                      ; HL @ charX
    ; Escribir [0]=charX, [2]=charXEnd
    LD A, (HL)                  ; charX
    LD (IX+0), A
    LD B, A                     ; B = charX
    LD A, (BgSpriteBuffer + 1)
    AND $7F                     ; charW (bit 7 = RLE flag, ignorar)
    ADD A, B
    DEC A                       ; charXEnd = charX + W - 1
    LD (IX+2), A
    INC HL                      ; HL @ charY
    ; Escribir [1]=charY (con BG_Y_OFFSET para alinear con ATTR_BASE), [3]=charYEnd
    LD A, (HL)
    ADD A, BG_Y_OFFSET
    LD (IX+1), A
    LD B, A                     ; B = charY post-offset
    LD A, (BgSpriteBuffer)      ; H_px
    SRL A
    SRL A
    SRL A                       ; charH
    ADD A, B
    DEC A                       ; charYEnd
    LD (IX+3), A
    ; HL @ charY. Skip 2 (charY, tint) al siguiente mapX.
    INC HL
    INC HL
    JR .bprcLoop
.bprcSkipFromCharX:
    ; HL en charX. Skip 3 al siguiente mapX.
    LD DE, 3
    ADD HL, DE
    JR .bprcLoop
.bprcSkipFromPtrLo:
    ; HL en ptr_lo. Skip 5 al siguiente mapX.
    LD DE, 5
    ADD HL, DE
    JP .bprcLoop
.bprcInactive:
    ; HL en mapX ($FE). Skip 7.
    LD DE, 7
    ADD HL, DE
    JP .bprcLoop

; ==============================================================================
; DrawKeyHUD - Muestra la llave actual en el HUD (cols 20-22, rows 0-1)
; ==============================================================================
; Slot 3×2 chars en la fila HUD superior, justo a la derecha del reloj-decor.
; Las 6 keys son todas 24×16 (3×2 chars).
; Si CurrentKey == 0: limpia el área. Si > 0: dibuja el sprite de la key.
; Se llama cada frame desde MainLoop.
; ==============================================================================
DrawKeyHUD:
    LD A, (CurrentKey)
    OR A
    JR NZ, .dkhDraw

    ; Limpiar pixeles fila 0 (third 0, scans 0-7 = H $40..$47)
    LD HL, $4015                ; row 0 col 21 scan 0
    LD B, 8
.dkhClr0:
    XOR A
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    DEC HL
    DEC HL
    INC H
    DJNZ .dkhClr0
    ; Limpiar pixeles fila 1
    LD HL, $4035                ; row 1 col 21 scan 0
    LD B, 8
.dkhClr1:
    XOR A
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    DEC HL
    DEC HL
    INC H
    DJNZ .dkhClr1
    ; Limpiar attrs (row 0-1, cols 21-23)
    LD A, $47                   ; bright white on black
    LD ($5815), A
    LD ($5816), A
    LD ($5817), A
    LD ($5835), A
    LD ($5836), A
    LD ($5837), A
    RET

.dkhDraw:
    ; A = 1..7: sacar el BgGfx ptr de KeyLockTable[A-1] (slot 7 = BankCheck)
    DEC A
    ADD A, A                    ; *2 (DEFW size)
    LD L, A
    LD H, 0
    LD DE, KeyLockTable
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)                  ; DE = BgGfx ptr
    EX DE, HL                   ; HL = BgGfx ptr
    LD A, 3                     ; KeyLockTable ptrs viven en bank 3
    CALL LoadBgSpriteToBuffer
    LD IX, BgSpriteBuffer
    LD B, 21                    ; charX (col 21)
    ; Target row 0. DrawBgGfxSprite hará C + BG_Y_OFFSET → necesitamos C = -2 ($FE)
    ; para que la fila resultante sea 0.
    LD A, 0
    SUB BG_Y_OFFSET
    LD C, A                     ; C = $FE
    XOR A
    LD (BgSpriteIsHouse), A
    CALL DrawBgGfxSprite

    ; --- Pickup flash: tras coger una llave o cheque, alterna attrs visible/$00
    ; sincronizado con el resto del HUD (GameFrameCounter & HUD_BUFF_BLINK_MASK).
    ; El sprite se redibuja cada frame (DrawKeyHUD no cachea), asi que solo
    ; necesitamos override de attrs en fase off. ---
    LD A, (PickupFlashKey)
    OR A
    RET Z                       ; sin flash → attrs del sprite quedan visibles
    DEC A
    LD (PickupFlashKey), A
    LD A, (GameFrameCounter)
    AND HUD_BUFF_BLINK_MASK
    RET Z                       ; on-phase → attrs del sprite quedan
    ; off-phase: paint $00 sobre los 6 chars (3 cols × 2 rows) del icono
    XOR A
    LD ($5815), A
    LD ($5816), A
    LD ($5817), A
    LD ($5835), A
    LD ($5836), A
    LD ($5837), A
    RET

; ==============================================================================
; DrawLivesHUD - Renderiza N iconos "Vidas" (BG35, 8x16 = 1x2 chars) en rows 0-1 cols 0-4
; ==============================================================================
; N = vidas EXTRA = max(0, min(PlayerLives - 1, PLAYER_LIVES_MAX - 1)).
; La vida en uso NO cuenta como icono: con PLAYER_LIVES_INIT=3, al arranque
; el HUD muestra 2 iconos. PlayerLives=1 muestra 0 (ultima vida, sin extras).
; ==============================================================================
DrawLivesHUD:
    ; --- Determinar N = PlayerLives - 1, clamp [0 .. PLAYER_LIVES_MAX-1] ---
    LD A, (PlayerLives)
    OR A
    JR Z, .dlhCapOk                 ; PlayerLives=0: 0 iconos (game over imminent)
    DEC A                           ; vida en uso no cuenta
    CP PLAYER_LIVES_MAX
    JR C, .dlhCapOk
    LD A, PLAYER_LIVES_MAX - 1      ; safety cap (no deberia ocurrir, max=MAX-1)
.dlhCapOk:
    LD B, A                         ; B = N actual

    ; --- Cache check: pixels solo se redibujan en cambio de count ---
    LD A, (.dlhLast)
    CP B
    JP Z, .dlhFlashOnly             ; mismo count: skip clear+draw, solo tick flash
    LD A, B
    LD (.dlhLast), A
    LD (.dlhCount), A

    ; --- Limpiar strip pixels (rows 0-1, cols 0-4 = 5 bytes × 16 scans) ---
    ; Dos pasadas separadas: row 0 ($4000-$4700) y row 1 ($4020-$4720), el
    ; INC H no salta correctamente entre filas char-aligned dentro de la
    ; misma seccion VRAM.
    LD HL, $4000                    ; row 0 col 0 scan 0
    CALL .dlhClrPxRow
    LD HL, $4020                    ; row 1 col 0 scan 0
    CALL .dlhClrPxRow
    ; --- Limpiar attrs (rows 0-1, cols 0-4 = 10 chars) ---
    ; $07 (no bright) = mismo attr nativo del sprite Vidas. Si pintas aqui
    ; $47 (bright) y luego DrawBgGfxSprite repinta a $07, el raster puede
    ; capturar el estado intermedio bright -> destello visible 1 frame.
    LD A, $07
    LD ($5800), A
    LD ($5801), A
    LD ($5802), A
    LD ($5803), A
    LD ($5804), A
    LD ($5820), A
    LD ($5821), A
    LD ($5822), A
    LD ($5823), A
    LD ($5824), A

    ; Si N=0, ya esta (strip limpio).
    LD A, (.dlhCount)
    OR A
    RET Z

    ; --- Cargar sprite Vidas al buffer una sola vez ---
    LD HL, BgGfx_vidas
    LD A, 3                         ; bank 3 (bg_gfx.asm)
    CALL LoadBgSpriteToBuffer

    ; --- Loop dibuja en cols 0..4 segun count ---
    LD A, (.dlhCount)
    LD B, A
    LD C, 0                         ; starting col
.dlhLoop:
    PUSH BC                         ; B=count, C=charX
    LD IX, BgSpriteBuffer
    LD A, C
    LD B, A                         ; B = charX
    LD A, 0
    SUB BG_Y_OFFSET
    LD C, A                         ; C = 0 - BG_Y_OFFSET (row 0 destino)
    XOR A
    LD (BgSpriteIsHouse), A
    LD (CurrentTintVar), A
    CALL DrawBgGfxSprite
    POP BC
    INC C                           ; siguiente col
    DJNZ .dlhLoop
    ; Fall-through a .dlhFlashOnly (mismo frame: ya dibujamos los pixels;
    ; ahora el flash, si activo, pinta sus attrs sobre el sprite recien
    ; dibujado para que el primer frame post-pickup ya cuente como "on").

.dlhFlashOnly:
    ; --- Pickup flash: solo toggle ATTRS (no toca pixels) para evitar el
    ;     flicker de clear+redraw cada frame. Solo el ULTIMO icono (la vida
    ;     recien recogida) parpadea; las vidas en espera anteriores se quedan
    ;     estables. El blink usa GameFrameCounter & HUD_BUFF_BLINK_MASK. En el
    ;     ultimo frame del flash forzamos ON para no dejar el icono invisible
    ;     hasta el proximo cache miss (cambio de sala). ---
    LD A, (PickupFlashLife)
    OR A
    JR Z, .dlhRespawnBlink
    DEC A
    LD (PickupFlashLife), A
    LD B, A                         ; B = PickupFlashLife post-DEC (0 = ultimo frame)
    LD A, (.dlhCount)
    OR A
    JR Z, .dlhRespawnBlink          ; sin iconos visibles -> nada que togglear
    LD C, A                         ; C = N (iconos)
    ; --- Decidir attr: ultimo frame siempre ON; resto segun frame counter ---
    LD A, B
    OR A
    JR Z, .dlhFlashOn               ; ultimo frame -> forzar ON
    LD A, (GameFrameCounter)
    AND HUD_BUFF_BLINK_MASK
    JR Z, .dlhFlashOn
    XOR A                           ; off phase: invisible ($00)
    JR .dlhFlashApply
.dlhFlashOn:
    LD A, $07                       ; on phase: attr nativo del sprite
.dlhFlashApply:
    ; --- Pintar A solo en la col N-1 (row 0 + row 1) ---
    LD B, A                         ; B = attr a pintar
    LD A, C                         ; A = N
    DEC A                           ; col destino = N-1
    LD L, A
    LD H, $58                       ; HL = $5800 + (N-1)
    LD (HL), B
    LD A, L
    ADD A, $20
    LD L, A                         ; HL = $5820 + (N-1)
    LD (HL), B
    ; Fall-through a .dlhRespawnBlink: durante phase 1 sobrescribe el attr
    ; del ULTIMO icono con el blink sync al countdown (doble freq vs player).

; ==============================================================================
; .dlhRespawnBlink - blink del ultimo icono durante el countdown 3-2-1
; ==============================================================================
; Durante PlayerRespawnPhase==1, el ultimo icono (col N-1, rows 0-1) parpadea
; en sincronia con los beats del countdown — doble frecuencia que el player.
; PlayerRespawnTimer (20..0) se divide en 4 cuadrantes de 5 frames:
;   T in [20,16] -> ON, [15,11] -> OFF, [10,6] -> ON, [5,0] -> OFF.
; Sincronizado con el beat porque cada beat resetea el timer a 20.
; ==============================================================================
.dlhRespawnBlink:
    LD A, (PlayerRespawnPhase)
    DEC A
    RET NZ                          ; solo phase 1
    LD A, (PlayerRespawnConsumesLife)
    OR A
    RET Z                           ; spawn inicial (no post-death): no blink
    LD A, (PlayerRespawnBeatIdx)
    CP 4
    RET NC                          ; beat 4 (GO) y posterior: no blink — el
                                    ; DEC ya ocurrio, el icono que parpadeaba
                                    ; ya no existe, el que QUEDA no debe blinkear
    LD A, (.dlhCount)
    OR A
    RET Z                           ; sin iconos: nada que togglear
    LD B, A                         ; B = N (count)
    ; --- Determinar attr segun cuadrante del timer ---
    LD A, (PlayerRespawnTimer)
    CP 16
    JR NC, .drbOn
    CP 11
    JR NC, .drbOff
    CP 6
    JR NC, .drbOn
.drbOff:
    XOR A
    JR .drbApply
.drbOn:
    LD A, $47                       ; bright white on black (nativo)
.drbApply:
    ; --- Pintar A en attr del ultimo icono: row 0 + row 1, col (N-1) ---
    LD C, A                         ; C = attr a pintar
    LD A, B                         ; A = N
    DEC A                           ; col destino = N-1
    LD H, $58
    LD L, A                         ; HL = $5800 + (N-1)
    LD (HL), C
    LD A, L
    ADD A, $20
    LD L, A                         ; HL = $5820 + (N-1)
    LD (HL), C
    RET

; Helper: limpia 5 cols × 8 scans (1 char tall) empezando en HL.
; HL = $40xx con col base + scan base. Destruye AF, B, HL.
.dlhClrPxRow:
    LD B, 8
.dlhClrPxLoop:
    XOR A
    LD (HL), A
    INC HL : LD (HL), A
    INC HL : LD (HL), A
    INC HL : LD (HL), A
    INC HL : LD (HL), A             ; 5 cols
    LD A, L
    SUB 4
    LD L, A                         ; volver al inicio de fila
    INC H                           ; siguiente scanline (dentro de seccion VRAM)
    DJNZ .dlhClrPxLoop
    RET
.dlhCount: DEFB 0
.dlhLast:  DEFB $FF                     ; sentinel: force redraw on first call

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
    CALL ApplyDayCycleRemap     ; remap segun momento del dia (mirror DrawBgGfxSprite).
                                ; Antes los pickups perdian el ciclo cada frame
                                ; porque RefreshPickupAttrs los repintaba aqui sin
                                ; remap → puertas y otros pickups no ciclaban color.
    LD (HL), A
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
