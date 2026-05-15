; ==============================================================================
; sfx_player_hit_ay.asm - Wrappers legacy → AY_PlaySFX (Fase 5 migration done)
; ==============================================================================
; Histórico: este archivo albergaba AY_PlayPlayerHit y un puñado de SFX AY
; hard-codeados (Beep, Knock, CompassPickup, LastingPickup, VictoryFanfare,
; PlayerDeath) con su propio ticker (AY_UpdatePlayerHit) y state.
;
; Post Fase 5: todos esos SFX viven ahora como datos en sfx_library.json,
; compilados a opcode streams por tools/build_sfx.py, interpretados por
; sfx_interp.asm via AY_PlaySFX. Las entries AY_Play* permanecen como
; wrappers de 1 instruccion para no tocar los call sites legacy.
;
; AY_PlayBeep ELIMINADO: sus 5 callers (logic_game, magic_compass, sound,
; bank_cutscene) ya hacen LD A, AYSFX_X : CALL AY_PlaySFX directamente.
;
; Slot 1, siempre visible. JP a AY_PlaySFX (tail call) — sin coste de stack.
; ==============================================================================

AY_PlayPlayerHit:
    LD A, AYSFX_PLAYER_HIT
    JP AY_PlaySFX

AY_PlayPlayerDeath:
    LD A, AYSFX_PLAYER_DEATH
    JP AY_PlaySFX

AY_PlayCompassPickup:
    LD A, AYSFX_COMPASS_PICKUP
    JP AY_PlaySFX

AY_PlayLastingPickup:
    LD A, AYSFX_LASTING_PICKUP
    JP AY_PlaySFX

AY_PlayVictoryFanfare:
    LD A, AYSFX_VICTORY_FANFARE
    JP AY_PlaySFX

; Knock callers (bank_cutscene) hacen LD B,4 antes — dead code inofensivo:
; el wrapper ignora B y usa la duracion baked-in en AYSFX_KNOCK_*.
AY_PlayKnockSoft:
    LD A, AYSFX_KNOCK_SOFT
    JP AY_PlaySFX

AY_PlayKnockLoud:
    LD A, AYSFX_KNOCK_LOUD
    JP AY_PlaySFX
