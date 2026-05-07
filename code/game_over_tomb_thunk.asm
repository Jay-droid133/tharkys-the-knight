; ==============================================================================
; GAME OVER TUMBA — THUNK (slot 1 always-visible, ~45 B)
; ==============================================================================
; Wrapper para llamar al body que vive en bank 7. El body por sí mismo no puede
; llamar a LoadBgSpriteToBuffer (esa rutina restaura bank 0 al final → bank 7
; desaparecería del slot 3 con el body ejecutándose → crash).
;
; Estrategia:
;   1. Carga el sprite usando LoadBgSpriteToBuffer normalmente. Termina con
;      bank 0 paginado en slot 3.
;   2. Pagina bank 7 en slot 3 (el thunk vive en slot 1 always-visible →
;      seguro hacer la conmutación aquí).
;   3. CALL al body (en bank 7, ahora visible en slot 3).
;   4. Body retorna → restauramos bank 0.
;
; Llamado por PaintGameOverScreen (en logic_game.asm, bank 0). PaintGameOverScreen
; está en slot 3 = bank 0; tras LoadBgSpriteToBuffer y el round-trip a bank 7,
; restauramos bank 0 antes del RET → caller sigue ejecutando bank 0 sin sorpresas.
; ==============================================================================

DrawTombstone2xCentered:
    ; --- 1. Cargar sprite a BgSpriteBuffer (bank 4 in/out, restaura bank 0) ---
    LD HL, BgGfx_little_house_cemetery
    LD A, TOMB_SRC_BANK             ; 4
    CALL LoadBgSpriteToBuffer

    ; --- 2. Paginar bank 7 en slot 3 para acceder al body ---
    DI
    LD A, (CurrentPaging)
    AND $F8
    OR 7
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; --- 3. CALL al body (vive en bank 7, ahora visible en slot 3) ---
    CALL DrawTombstone2xBody

    ; --- 4. Restaurar bank 0 (estado por defecto del juego) ---
    LD A, (CurrentPaging)
    AND $F8                         ; bank 0 = bits 0-2 a cero
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A

    ; Restaurar interrupciones (mismo patrón que LoadBgSpriteToBuffer)
    LD A, (StartupComplete)
    OR A
    RET Z                           ; aún en Inicio → dejar DI
    EI
    RET
