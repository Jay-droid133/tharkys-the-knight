; ==============================================================================
; bank_cutscene_thunks.asm - Wrappers slot 1 para bank_cutscene en bank 7
; ==============================================================================
; bank_cutscene.asm vive en bank 7 (movido desde bank 0 para descongestionar el
; main code). Este archivo expone los 2 entry points externos como thunks que
; paginan bank 7 antes del body y restauran bank 0 al volver. Tambien proporciona
; helpers _PageBank0 / _PageBank7 que el body bank 7 usa para envolver cada
; CALL a una funcion en bank 0 (o en slot 1 que internamente llame a bank 0).
;
; Funciones externas que requieren el wrap pre+post (paginar bank 0 antes,
; restaurar bank 7 despues):
;   - DrawBgSpriteXOR, DrawBgGfxSprite, RedrawPickupByPtr, PlaySFX,
;     CheckMilestoneTrigger    (todas en bank 0)
;   - TownGateRedrawPlayer     (slot 1, pero llama internamente a RestoreOldAttr
;                              que vive en bank 0)
;
; Funciones que requieren solo post-wrap (ya paginan bank 0 al final ellas mismas):
;   - LoadBgSpriteToBuffer     (slot 1, deja bank 0 paginado al RET -> repaginar
;                              bank 7 manualmente)
;
; Funciones que NO necesitan wrap (verificado por call graph):
;   - KillAllActiveNasties, SnapPuffPos, CheckEnemyCollision  (bank 2 slot 2)
;   - KillDeathIfActive -> StartMusic                          (bank 2 slot 2)
;   - TownGateAllNastiesDeadCheck                              (slot 1, no calls)
;   - AY_PlayKnockSoft/Loud/Beep                               (slot 1, no calls externos)
;   - DrawBgSprite16XorAtPixel -> CalcPixelAddr/NextPixelLine  (bank 2 slot 2)
;
; Vive en slot 1 (always-visible). Patron similar a game_over_tomb_thunk.asm.
;
; CRITICO: el stack normal del juego vive en $FF58 (slot 3, bank 0 paginable).
; Si los thunks paginan bank 7 en slot 3 sin tocar SP, el stack normal desaparece
; bajo nuestros pies -> CALL/RET dentro del body bank 7 leen basura -> crash.
; Solucion: los entry thunks (CheckBankTriggerBg, UpdateBankCutscene) hacen SP
; swap a BankCutsceneAltStack (RAM always-visible en slot 1, zona $5BE0..$5C00
; del printer buffer) durante toda la cutscene. Los _B7 thunks de funciones
; externas heredan ese SP (no necesitan su propio swap).
;
; Sin DI en los page switches: MusicIrqHandler vive en slot 1, por convencion
; project_irq_slot3_atomic no toca slot 3 -> IRQs corren normales durante los
; page switches igual que en LoadBgSpriteToBuffer.
; ==============================================================================

; Alt stack: 64 B al final de slot 1 ($7FC0..$7FFF, hueco libre tras music_irq).
; Vive en bank 5 always-visible, no toca otras zonas de RAM. Pico medido:
; TownGateRedrawPlayer -> DrawSprite -> _DrawSpriteImpl + IRQ handler
; concurrente puede superar 32 B; 64 B (32 niveles) da margen amplio.
BankCutsceneAltStackBase EQU $7FC0
BankCutsceneAltStackTop  EQU $8000       ; SP top: first PUSH escribe a $7FFE-$7FFF

; ==============================================================================
; _PageBank0 - Pagina bank 0 en slot 3. Preserva AF + BC + resto del caller.
; ==============================================================================
; Llamado por:
;   - Entry thunks al final (devolver al gameplay normal).
;   - Body bank 7 antes de cada CALL externo que toca bank 0.
; Destruye: ningun reg (todo restaurado via PUSH/POP).
; ==============================================================================
_PageBank0:
    PUSH AF
    PUSH BC
    LD A, (CurrentPaging)
    AND $F8                              ; bank 0 = bits 0-2 a cero
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    POP BC
    POP AF
    RET

; ==============================================================================
; _PageBank7 - Pagina bank 7 en slot 3. Preserva AF + BC + resto del caller.
; ==============================================================================
; Llamado por:
;   - Entry thunks al principio (para que el body bank 7 sea visible).
;   - Body bank 7 despues de cada CALL externo (para retomar el flujo).
; Destruye: ningun reg.
; ==============================================================================
_PageBank7:
    PUSH AF
    PUSH BC
    LD A, (CurrentPaging)
    AND $F8
    OR 7
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    POP BC
    POP AF
    RET

; ==============================================================================
; CheckBankTriggerBg - Thunk de entry. Swap SP a alt_stack, pagina bank 7,
; ejecuta body, restaura bank 0 + SP normal.
; ==============================================================================
; Llamado desde MainLoop cada frame. Body verifica si el player toca la
; puerta del banco con el cheque y dispara la cutscene + avance de hito M9.
;
; CRITICO: stack normal vive en bank 0 (slot 3) -> desaparece al paginar bank 7.
; Por eso swap SP a alt_stack ANTES del page switch.
; ==============================================================================
CheckBankTriggerBg:
    LD (.savedSPCheck), SP                   ; save SP normal (en bank 0)
    LD SP, BankCutsceneAltStackTop           ; SP -> alt_stack (slot 1 always-vis)
    CALL _PageBank7
    CALL CheckBankTriggerBgBody
    CALL _PageBank0                          ; bank 0 paginado -> SP normal accesible al restaurar
    LD SP, (.savedSPCheck)                   ; restore SP normal
    RET                                      ; vuelve al CALL del MainLoop
.savedSPCheck: DEFW 0

; ==============================================================================
; UpdateBankCutscene - Thunk de entry para el tick por frame de la cutscene.
; ==============================================================================
; Mismo patron SP swap que CheckBankTriggerBg. Llamado desde MainLoop cada
; frame si BankCutscenePhase != 0.
; ==============================================================================
UpdateBankCutscene:
    LD (.savedSPUpdate), SP
    LD SP, BankCutsceneAltStackTop
    CALL _PageBank7
    CALL UpdateBankCutsceneBody
    CALL _PageBank0
    LD SP, (.savedSPUpdate)
    RET
.savedSPUpdate: DEFW 0

; ==============================================================================
; Entry thunks para town_gate_cutscene (body en bank 7)
; ==============================================================================
; Mutuamente exclusiva con bank_cutscene (M11 vs M9), comparte el alt_stack
; (no pueden estar activas a la vez por el milestone gating en MainLoop).
;
; StartTownGateCutscene NO necesita su propio entry thunk — se llama solo
; desde CheckTownGateTriggerBgBody (interno bank 7).
; ==============================================================================
CheckTownGateTriggerBg:
    LD (.savedSPCheckTG), SP
    LD SP, BankCutsceneAltStackTop
    CALL _PageBank7
    CALL CheckTownGateTriggerBgBody
    CALL _PageBank0
    LD SP, (.savedSPCheckTG)
    RET
.savedSPCheckTG: DEFW 0

UpdateTownGateCutscene:
    LD (.savedSPUpdateTG), SP
    LD SP, BankCutsceneAltStackTop
    CALL _PageBank7
    CALL UpdateTownGateCutsceneBody
    CALL _PageBank0
    LD SP, (.savedSPUpdateTG)
    RET
.savedSPUpdateTG: DEFW 0

; ==============================================================================
; External call thunks - usados desde el body bank 7 para llamar a rutinas
; que viven en bank 0 (o en slot 1 que internamente toca bank 0).
; ==============================================================================
; Patron: body bank 7 hace `CALL <Func>_B7`. El thunk pagina bank 0, llama a
; la funcion real, repagina bank 7, y RETurnea al body. Args en HL/BC/DE/A/IX
; quedan intactos (_PageBank0 / _PageBank7 preservan AF + BC via PUSH/POP).
;
; CRITICO: el body bank 7 NO puede llamar _PageBank0 directamente — al volver,
; slot 3 estaria en bank 0 y el RET aterrizaria en bank 0 (no en bank 7) =
; crash. Por eso cada wrap vive como thunk individual en slot 1 (always-vis).
; ==============================================================================

; --- bank 0 callees (paginar bank 0 antes, restaurar bank 7 al RET) ---

ClearPlayerBuffs_B7:
    CALL _PageBank0
    CALL ClearPlayerBuffs
    JP _PageBank7

DrawBgSpriteXOR_B7:
    CALL _PageBank0
    CALL DrawBgSpriteXOR
    JP _PageBank7

; DrawBgGfxSprite_B7 - draw + flags. El unico caller del body bank 7 es
; BankCutsceneCloseDoorRestoreAttrs, que necesita BgSpriteIsHouse=0 y
; CurrentTintVar=$FF antes del draw. Esas vars viven en BANK 0, asi que
; se escriben aqui DENTRO del wrap pre-paginated. Antes era un thunk
; aparte (DrawBankDoorSprite_B7) pero combinar ahorra 18 B en slot 1 —
; critico para que magic_compass.asm no cruce $7A00 (im2 table).
DrawBgGfxSprite_B7:
    CALL _PageBank0
    XOR A
    LD (BgSpriteIsHouse), A
    LD A, $FF
    LD (CurrentTintVar), A
    CALL DrawBgGfxSprite
    JP _PageBank7

RedrawPickupByPtr_B7:
    CALL _PageBank0
    CALL RedrawPickupByPtr
    JP _PageBank7

PlaySFX_B7:                              ; HL = SFX data ptr (en bank 0)
    CALL _PageBank0
    CALL PlaySFX
    JP _PageBank7

CheckMilestoneTrigger_B7:                ; A = action id
    CALL _PageBank0
    CALL CheckMilestoneTrigger
    JP _PageBank7

; --- slot 1 callee con dependencia bank 0 interna ---

TownGateRedrawPlayer_B7:
    CALL _PageBank0
    CALL TownGateRedrawPlayer            ; -> TownGateErasePlayer -> RestoreOldAttr (bank 0)
    JP _PageBank7

; --- slot 1 callee que deja bank 0 paginado al RET (solo post-wrap) ---

LoadBgSpriteToBuffer_B7:                 ; HL = sprite ptr, A = bank
    CALL LoadBgSpriteToBuffer            ; ya pagina bank 3/4 internamente, deja bank 0 al RET
    JP _PageBank7                        ; repaginar bank 7 (LoadBgSpriteToBuffer no lo hace)

; --- slot 2 callees que internamente paginan bank 6 (sprite_data) y "restauran"
;     bank 0 al RET, no el bank original. Si los llamasemos crudamente desde
;     bank 7, slot 3 terminaria con bank 0 -> body bank 7 invisible -> crash.
;     KillAllActiveNasties -> SnapPuffPos -> GetSpriteDims (pagina bank 6).
;     KillDeathIfActive    -> StartMusic   (pagina bank 4). ---

KillAllActiveNasties_B7:
    CALL KillAllActiveNasties
    JP _PageBank7                        ; restaura bank 7 (KillAll dejo bank 0)

KillDeathIfActive_B7:
    CALL KillDeathIfActive
    JP _PageBank7                        ; restaura bank 7 (StartMusic dejo bank 0)

; ==============================================================================
; Thunks adicionales para town_gate_cutscene body (bank 7)
; ==============================================================================
; town_gate body llama tambien a las siguientes funciones bank 2 / bank 0.
; Mismo patron: paginate bank 0, CALL, repaginate bank 7.
;
; DrawSprite / GetSpriteAddr / GetOldSpriteAddr paginan bank 6 internamente
; y restauran bank 0 al RET -> wrap completo (page bank 0 antes, page bank 7
; despues).
;
; RestoreOldAttr / SetEntityAttr / CalcEntityAttrSize estan en bank 0 / bank 2
; pero no paginan slot 3 -> tecnicamente el wrap _PageBank0 antes seria
; suficiente sin necesidad de _PageBank7 despues. Aun asi por consistencia
; con el patron usamos wrap completo.
;
; StartMusic pagina bank 4 internamente y restaura bank 0 -> wrap completo.
; ==============================================================================

DrawSprite_B7:                           ; IX = sprite ptr, D = Y, E = X
    CALL _PageBank0
    CALL DrawSprite
    JP _PageBank7

GetSpriteAddr_B7:                        ; IX = entity ptr, OUT: SpriteAddrTemp
    CALL _PageBank0
    CALL GetSpriteAddr
    JP _PageBank7

GetOldSpriteAddr_B7:                     ; IX = entity ptr, OUT: OldSprAddr
    CALL _PageBank0
    CALL GetOldSpriteAddr
    JP _PageBank7

RestoreOldAttr_B7:                       ; D = Y, E = X
    CALL _PageBank0
    CALL RestoreOldAttr
    JP _PageBank7

SetEntityAttr_B7:                        ; D = Y, E = X, A = attr
    CALL _PageBank0
    CALL SetEntityAttr
    JP _PageBank7

CalcEntityAttrSize_B7:                   ; IX = sprite ptr
    CALL _PageBank0
    CALL CalcEntityAttrSize
    JP _PageBank7

StartMusic_B7:                           ; A = track arg
    CALL _PageBank0
    CALL StartMusic
    JP _PageBank7

; TownGatePlayerSlide* viven en slot 1 (no se mueven a bank 7 porque paginan
; bank 6 internamente — si fueran bank 7 el OUT haria desaparecer el codigo
; bajo sus pies). Pero al volver al body bank 7 dejan slot 3 = bank 0 ->
; necesitan post-wrap.
TownGatePlayerSlideErase_B7:
    CALL TownGatePlayerSlideErase
    JP _PageBank7

TownGatePlayerSlideDraw_B7:
    CALL TownGatePlayerSlideDraw
    JP _PageBank7

; DrawBgGfxSpriteBlackTint_B7 - draw con CurrentTintVar=0 + BgSpriteIsHouse=0.
; Para town_gate: open door + "The End" sprites usan tint negro (ApplyTintSwap
; reemplaza paper con 0 = black). Distinto de DrawBgGfxSprite_B7 que pone
; tint=$FF (sin swap, attr preservado) para la puerta del banco.
DrawBgGfxSpriteBlackTint_B7:
    CALL _PageBank0
    XOR A
    LD (BgSpriteIsHouse), A
    LD (CurrentTintVar), A
    CALL DrawBgGfxSprite
    JP _PageBank7

; ==============================================================================
; LoadCreditsFontToBuffer_B7 - Copia el font de creditos (bank 4) a slot 2.
; ==============================================================================
; Llamado UNA VEZ desde TownGateDrawCredits al entrar fase CREDITS. Pagina
; bank 4 en slot 3, LDIRs CreditsFontData -> BgSpriteBuffer (always-visible),
; restaura bank 7 (para que el caller en bank 7 siga visible al RET).
;
; Bank 4 esta holgado y BgSpriteBuffer no se reusa durante CREDITS (no hay
; mas sprite loads despues de la fase END_HOLD).
; Destruye: AF, BC, DE, HL.
; ==============================================================================
LoadCreditsFontToBuffer_B7:
    ; --- Pagina bank 4 (preserva bit 4 = ROM select) ---
    LD A, (CurrentPaging)
    AND $F8
    OR 4
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    ; --- Copia font -> BgSpriteBuffer ---
    LD HL, CreditsFontData
    LD DE, BgSpriteBuffer
    LD BC, CREDITS_FONT_SIZE
    LDIR
    ; --- Restaura bank 7 (caller vive en bank 7) ---
    LD A, (CurrentPaging)
    AND $F8
    OR 7
    LD (CurrentPaging), A
    LD BC, $7FFD
    OUT (C), A
    RET
