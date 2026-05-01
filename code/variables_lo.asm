; ==============================================================================
; LOW-RAM VARIABLES — ubicadas en $5D00+ via EQU (no emiten bytes al .tap)
; ==============================================================================
; Reubicacion fase A del plan de ampliacion de bank 2 (mem/expand-bank2):
; mover los buffers/scratch que solo se acceden en cold paths a la zona libre
; del bank 5 ($5800-$7FFF). $4000-$5AFF es VRAM; $5B00-$5CCB es system area
; del 128 (printer buffer + system vars). Empezamos en $5D00 con margen.
;
; IMPORTANTE: los simbolos son EQU, asi que NO se emite ningun byte al .tap.
; El loader deja la zona con valores indeterminados; Inicio: hace zero-fill
; de [LOW_RAM_BASE, LOW_RAM_END) y luego pone los defaults no-cero.
;
; Solo entran aqui variables cuya frecuencia de acceso es practicamente nula
; durante el inner loop. La memoria de $5D00-$7FFF es CONTENDED, asi que
; cualquier variable hot debe seguir en bank 2 ($8000-$BFFF, no-contended).
; ==============================================================================

LOW_RAM_BASE        EQU $5D00

; --- Zone cell list: solo se construye al cambiar de sala (BuildZoneCellList) ---
; y se lee en SpawnOneNasty. Cold path (transition + spawn).
ZoneCellCount       EQU LOW_RAM_BASE
ZoneCellList        EQU ZoneCellCount + 1            ; DEFS 255 * 2

; --- BFS rescue de la muerte: solo se dispara cuando StuckCounter llega a 6 ---
DBfsQueue           EQU ZoneCellList + 510           ; DEFS 108
DBfsQHead           EQU DBfsQueue + 108              ; DEFW
DBfsQTail           EQU DBfsQHead + 2                ; DEFW
DBfsBestDir         EQU DBfsQTail + 2                ; DEFB
DBfsBestDepth       EQU DBfsBestDir + 1
DBfsBestManh        EQU DBfsBestDepth + 1
DBfsPlayerCx        EQU DBfsBestManh + 1
DBfsPlayerCy        EQU DBfsPlayerCx + 1
DBfsCurCx           EQU DBfsPlayerCy + 1
DBfsCurCy           EQU DBfsCurCx + 1
DBfsCurFirstDir     EQU DBfsCurCy + 1
DBfsCurDepth        EQU DBfsCurFirstDir + 1
DBfsTryCx           EQU DBfsCurDepth + 1
DBfsTryCy           EQU DBfsTryCx + 1
DBfsTryDir          EQU DBfsTryCy + 1

; --- Pending erase list: la usa EraseDeadSprites; cuenta>0 es muy raro ---
PendingEraseCount   EQU DBfsTryDir + 1
PendingEraseSlots   EQU PendingEraseCount + 1        ; DEFS 3 * 5

; --- Monster AI v2 cold state: solo se accede en transicion / scared ---
RoomHistory         EQU PendingEraseSlots + 15       ; DEFB 0,0,0
MonsterLastSeenRoom EQU RoomHistory + 3              ; DEFB $FF,$FF,$FF (init explicito)
MonsterLastSeenX    EQU MonsterLastSeenRoom + 3
MonsterLastSeenY    EQU MonsterLastSeenX + 3
MonsterShakeOrigX   EQU MonsterLastSeenY + 3
MonsterShakeOrigY   EQU MonsterShakeOrigX + 3

; --- Cutscene de iglesia: solo accede cuando ChurchCutscenePhase != 0 ---
; ChurchCutscenePhase se queda en bank 2 (lo lee MainLoop cada frame).
ChurchCutsceneFrame      EQU MonsterShakeOrigY + 3
ChurchCutsceneSlot       EQU ChurchCutsceneFrame + 1
ChurchCutsceneTypeIdx    EQU ChurchCutsceneSlot + 1
ChurchCutsceneStatueOrigX EQU ChurchCutsceneTypeIdx + 1
ChurchCutsceneStatueOrigY EQU ChurchCutsceneStatueOrigX + 1
ChurchCutsceneStatueLastX EQU ChurchCutsceneStatueOrigY + 1
ChurchCutsceneStatueLastY EQU ChurchCutsceneStatueLastX + 1
ChurchCutsceneLookCount  EQU ChurchCutsceneStatueLastY + 1

LOW_RAM_END         EQU ChurchCutsceneLookCount + 1
LOW_RAM_SIZE        EQU LOW_RAM_END - LOW_RAM_BASE
