; ==============================================================================
; MACROS ÚTILES PARA EL DESARROLLO
; ==============================================================================

    ; Marco para pintar un color rápidamente en la pantalla
    MACRO SET_COLOR color, address
        LD A, color
        LD HL, address
        LD (HL), A
    ENDM

    ; Macro estándar para sumar A a HL
    MACRO ADD_HL_A
        ADD A, L
        LD L, A
        ADC A, H
        SUB L
        LD H, A
    ENDM
