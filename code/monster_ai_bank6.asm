; ==============================================================================
; MONSTER AI v2 — buffers runtime en bank 6
; ==============================================================================
; Se incluye en main.asm dentro del bloque PAGE 6, DESPUES de screen_gaps.asm.
; Los buffers viven en $Cxxx y se acceden paginando bank 6 al slot 3.
;
;   FlowField   — 704 B, distancia-al-player por celda (32×22 chars)
;                 Formato: 1 byte por celda. Valor $FF = inalcanzable.
;                 Offset lineal: cellY * 32 + cellX
;
;   BfsQueue    — 128 B, FIFO para el BFS (cola de celdas a procesar)
;                 Cada entrada: 1 byte = celly*32 + cellX (0..703)
;                 Con 128 entradas cabemos para la mayoria de screens;
;                 si saturase, el BFS se corta graciosamente.
;
; Escritura y lectura: los clientes deben paginar bank 6 antes, repaginar bank 0
; despues (ver PageBankSlot3 en paging.asm).
; ==============================================================================

FlowField:      DEFS 704
BfsQueue:       DEFS 128

MonsterAiBank6End:
