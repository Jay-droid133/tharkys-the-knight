; ==============================================================================
; random_pickups_thunks.asm - Wrappers slot 1 para random_pickups.asm en bank 7
; ==============================================================================
; random_pickups.asm vivia en slot 1 ($6BF7..$70E4, ~1.26 KB). Movido a bank 7
; para liberar slot 1 (donde RoomCompGapsTable y el resto del flujo compiten
; por el espacio antes del ORG $7B7B de Im2Vector). Libera ~1.1 KB neto.
;
; Body bank 7 expone 9 entry points externos. Aqui se exponen como thunks que
; comparten un shell de SP swap + page switch para minimizar bytes en slot 1.
;
; Reutiliza de bank_cutscene_thunks.asm (slot 1, ya incluido en main.asm):
;   - _PageBank0 / _PageBank7
;   - BankCutsceneAltStackTop
;   - LoadBgSpriteToBuffer_B7
;   - DrawBgSpriteXOR_B7
;   - PlaySFX_B7
;
; Nuevos _B7 wrappers (slot 1, para usar desde body en bank 7):
;   - SkipPixelData_B7        (bank 0)
;   - RestorePickupAttrs_B7   (bank 0)
;   - ApplyMagicCompassBuff_B7 (slot 1, wrap por seguridad — llama helpers bank 0)
;
; CRITICO: stack normal en slot 3 (bank 0 paginable). Los thunks hacen SP swap
; a BankCutsceneAltStackTop antes del page switch. Compartido secuencialmente
; con bank_cutscene/town_gate thunks dentro del mismo frame — no conflicto
; porque son single-threaded (Z80 + IRQ handler en slot 1 que no toca slot 3).
; ==============================================================================

; ==============================================================================
; _RP_Thunk - shell compartido por los 9 entry thunks
; ==============================================================================
; IN:  HL = body address (en bank 7)
; OUT: lo que devuelva el body. Regs intermedios usados por body, no preservados.
; Destruye: AF, HL (la propia entrada).
;
; Flujo:
;   1. Save SP normal en _RP_savedSP.
;   2. Swap SP a alt_stack (slot 1 always-visible).
;   3. Page bank 7 en slot 3.
;   4. JP (HL) -> body (via CALL .callHL + JP (HL): el RET del body cae aqui).
;   5. Page bank 0 en slot 3.
;   6. Restore SP normal.
;   7. RET al caller original (MainLoop).
; ==============================================================================
_RP_Thunk:
    LD (_RP_savedSP), SP
    LD SP, BankCutsceneAltStackTop
    CALL _PageBank7
    CALL .callHL
    CALL _PageBank0
    LD SP, (_RP_savedSP)
    RET
.callHL:
    JP (HL)
_RP_savedSP: DEFW 0

; ==============================================================================
; Entry thunks - cada uno carga HL=body y salta al shell shared
; ==============================================================================
; 5 bytes cada uno (LD HL = 3 B + JR = 2 B). JR backward al shell. Como el
; shell mide ~18 B + las entries son ~45 B, todos los offsets caben en signed 8.
;
; Callers externos (registros sin args):
;   UpdateRandomPickup, UpdateRoulette, PaintSynthPickupAttrs, UpdateSpeedBuff,
;   UpdateMushroomBuff: MainLoop cada frame (early-out fast).
;   CheckRandomSyntheticPickup: screen_system / pickup collect.
;   GiveLife / GiveHealth / GiveStamina: screen_system (well pickup) +
;       internamente desde CheckRandomSyntheticPickup body (intra-bank, no thunk).
; ==============================================================================
UpdateRandomPickup:
    LD HL, UpdateRandomPickupBody
    JR _RP_Thunk
UpdateRoulette:
    LD HL, UpdateRouletteBody
    JR _RP_Thunk
PaintSynthPickupAttrs:
    LD HL, PaintSynthPickupAttrsBody
    JR _RP_Thunk
UpdateSpeedBuff:
    LD HL, UpdateSpeedBuffBody
    JR _RP_Thunk
UpdateMushroomBuff:
    LD HL, UpdateMushroomBuffBody
    JR _RP_Thunk
CheckRandomSyntheticPickup:
    LD HL, CheckRandomSyntheticPickupBody
    JR _RP_Thunk
GiveLife:
    LD HL, GiveLifeBody
    JR _RP_Thunk
GiveHealth:
    LD HL, GiveHealthBody
    JR _RP_Thunk
GiveStamina:
    LD HL, GiveStaminaBody
    JR _RP_Thunk
UpdatePlayerColorCycler:
    ; CRITICO: PlayerHitTimer vive en bank 0 (slot 3). Hay que leerlo AQUI
    ; (con slot 3 = bank 0 default) antes de paginar bank 7 en el shell. Si
    ; lo lee el body, leeria de bank 7 (basura) y abortaria casi siempre.
    LD A, (PlayerHitTimer)
    OR A
    RET NZ                              ; damage flash priority -> no cyclar
    LD HL, UpdatePlayerColorCyclerBody
    JR _RP_Thunk
UpdateEspadaBuff:
    LD HL, UpdateEspadaBuffBody
    JR _RP_Thunk
UpdateEscudoBuff:
    LD HL, UpdateEscudoBuffBody
    JR _RP_Thunk
UpdateReverseBuff:
    LD HL, UpdateReverseBuffBody
    JR _RP_Thunk

; ==============================================================================
; _B7 wrappers - llamados desde body en bank 7. Paginan bank 0, ejecutan el
; callee, paginan bank 7 al volver. Estos viven en slot 1 (always-visible).
; ==============================================================================
; SkipPixelData / RestorePickupAttrs: bank 0 (slot 3 default), helpers de
; pickup rendering usados por LoadSynthSpriteAndExtractAttr / CheckRandomSyntheticPickup.
;
; ApplyMagicCompassBuff: slot 1 (magic_compass.asm) pero llama helpers bank 0
; internamente -> wrap completo. Solo se usa via JP tail-call desde dispatch
; del pickup compass directo (no via ruleta).
; ==============================================================================
SkipPixelData_B7:
    CALL _PageBank0
    CALL SkipPixelData
    JP _PageBank7
RestorePickupAttrs_B7:
    CALL _PageBank0
    CALL RestorePickupAttrs
    JP _PageBank7
ApplyMagicCompassBuff_B7:
    CALL _PageBank0
    CALL ApplyMagicCompassBuff
    JP _PageBank7
ApplyMapPickup_B7:
    ; Pickup MAP (id 184): muestra minimapa 5 s + tics beeper + early-exit
    ; por cualquier tecla. ShowMinimapTimed vive en minimap.asm (bank 0).
    CALL _PageBank0
    CALL ShowMinimapTimed
    JP _PageBank7
