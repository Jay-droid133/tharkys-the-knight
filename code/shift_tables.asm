; ==============================================================================
; TABLAS DE SHIFT PRE-COMPUTADAS (fiel a Sabre Wulf $F000-$FFFF)
; ==============================================================================
; 7 pares de 256 bytes = 3584 bytes (shifts 1-7).
; Para cada shift S:
;   Pagina par:  table[byte] = byte >> S  (high part, queda en columna actual)
;   Pagina impar: table[byte] = byte << (8-S) (overflow, pasa a siguiente columna)
;
; Shift 0 (alineado) no necesita tabla — se usa el path directo.
;
; Uso: B = pagina de tabla, C = byte de sprite, LD A,(BC) = resultado instantaneo.
;   INC B → pagina overflow. DEC B → restaurar.
;
; Calculo de B desde X%8:
;   LD A, X_pixel / AND 7 / DEC A / RLCA / AND $0E / OR SHIFT_TABLE_BASE
; ==============================================================================

    ALIGN 4096
ShiftTables:
    LUA ALLPASS
    for shift = 1, 7 do
        -- High part: byte >> shift
        for i = 0, 255 do
            sj.add_byte(math.floor(i / (2^shift)))
        end
        -- Overflow: byte << (8-shift), modulo 256
        for i = 0, 255 do
            sj.add_byte(math.floor((i * (2^(8-shift))) % 256))
        end
    end
    ENDLUA

SHIFT_TABLE_BASE EQU ShiftTables / 256
