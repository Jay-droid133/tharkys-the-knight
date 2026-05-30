# Handoff: fix crash del minimapa (map random pickup) — fix de layout de RAM

> Documento de traspaso para retomar en sesión fresca. Causa raíz cazada y plan
> listo para ejecutar. El crash NO está arreglado todavía: falta la reorganización
> de memoria (bloqueada por presupuesto de RAM al máximo en la sesión anterior).

## Estado git
- Branch: `fix/minimap-slot1` (creado desde `main` = e9a7348), **árbol limpio**.
- Los 5 intentos fallidos viven en `fix/attr-bounds-guard` (WIP commit `9e78abc`) — DESCARTABLE.

## EL BUG (causa raíz, confirmada por git bisect)
El crash al coger un "map" random pickup (→ `ShowMinimapTimed`) es **corrupción de
stack**: `minimap.asm` vive al FINAL de bank 0 (slot 3), y sus rutinas caen en
**`$FE80-$FF58`**, la zona que el stack del gameplay (`SP_ADDRESS=$FF58` en
constants.asm:7, pico ~$FE80) + los IRQs machacan con cada PUSH. El CÓDIGO del
minimapa y `smSavedSP` salen corruptos; al abrir el mapa, ejecuta código corrupto
→ crash NO DETERMINISTA ("nunca igual"). Es la nota de memoria "Slot 3 stack corruption".

Direcciones en el commit malo (cd447d0): `smMinimapCleanup $FEBB`, `smSavedSP $FECE`,
`smDrawRoomSprite $FED0`, `smDrawOuterFrame $FF01` (todas en zona peligro).
`smRenderMap $FE20` y `smCopyFramePiece $FF9A` quedan fuera.

**git bisect → primer commit malo = `cd447d0`** ("feat(sfx): denial SFX en bank door
+ forest/ruins/cemetery locks"): metió ~256 B a bank 0 (CheckLockBump en
screen_system.asm), empujando minimap.asm a la zona peligro. En `b4d9aa2` (último
bueno) el minimapa estaba ~256 B más abajo, a salvo.

PRECEDENTE: el proyecto YA movió `minimap_sprites.asm` y `minimap_timed.asm` a slot 1
por ESTE mismo bug (ver comentario en main.asm bloque slot 1). Solo `minimap.asm` se
quedó en bank 0.

## FIX VALIDADO
Mover `minimap.asm` (508 B) fuera de bank 0 a RAM siempre-visible (slot 1) ARREGLA la
corrupción — PROBADO: el mapa se dibujó perfecto, audio al abrir, corrupción ida.

## EL BLOQUEO (presupuesto de RAM al máximo)
- Bank 0: lleno. Slot 1: lleno (minimapa necesita **~215 B** de hueco antes de `$7A00`).
  Slot 2 (bank 2): lleno (21 B).
- **Bank 7: lleno para CÓDIGO** (solo 82 B; `TOMBSTONE_ADDR=$FB00` en tombstones.asm:35
  reserva el resto — hay ASSERT `$ <= TOMBSTONE_ADDR`).
- Solo **bank 1 (4557 B) y bank 4 (4510 B)** tienen sitio → slot-3, necesitan thunk de
  paginación.
- Mover whole minimap a slot 1 SOLO → OVERFLOW de la tabla IM2: `minimap_timed` se empuja
  sobre `$7A00` (el `ORG $7A00` de music_irq lo solapa silenciosamente → vectores IM2
  corruptos → FREEZE). `check_slot_overlap.py` NO lo caza (bug del validador — verificar
  a mano).

## EL PLAN
1. **Mover `debug_unlock.asm` (194 B) de slot 1 a BANK 4.** Es código puro; sus deps son
   todas siempre-visibles (`PauseAy`/`ResumeAy` en slot 1, vars en variables.asm = bank 2).
   Entry único: `DebugFramePoll` (llamado desde MainLoop, main.asm). Plan:
   - Renombrar `DebugFramePoll:` → `DebugFramePollBody:` en debug_unlock.asm.
   - Mover su INCLUDE del bloque slot 1 (main.asm ~línea 374) al bloque `PAGE 4`
     (`ORG $C000`, busca "PAGE 4" en main.asm).
   - Crear thunk `DebugFramePoll` con patrón alt-stack bank-4 (copia de `AY_UpdateBell`
     en ay_sound_thunks.asm ~línea 53: save SP → `LD SP, PagingAltStackTop` → page bank 4
     (`AND $F8 : OR 4` en CurrentPaging + OUT $7FFD) → `CALL DebugFramePollBody` →
     page bank 0 → restore SP → RET).
   - **Coloca el thunk en un hueco POST-IM2 de slot 1** (después de la zona música,
     ~$7Bxx+) para NO competir con el espacio pre-$7A00. Así libera ~194 B antes de $7A00.
   - Verificar callers: solo `DebugFramePoll` se llama desde fuera (main.asm MainLoop); las
     internas (CheckBugSequence/StartBorderFlash/TickBorderFlash/CheckPauseKey) son
     self-contained.
2. **Liberar ~21 B más** antes de $7A00 (mide el overflow real tras mover; puede ser <21 B).
   Opciones: trim de dead code, o pelín de algo pequeño.
3. **Mover `INCLUDE "minimap.asm"`** del bloque bank-0 (main.asm ~línea 726) al bloque
   slot-1 (junto a minimap_sprites/minimap_timed, ~líneas 368-385).
   - Única dep bank-0 del minimapa: `MapTable` ($E1D9, screen_data.asm:177), leída por
     smRenderMap. Como `ShowMinimapTimed` ya hace `CALL _PageBank0` y slot 1 es
     siempre-visible, un minimapa en slot 1 que lee MapTable (bank 0 en slot 3) funciona —
     NO cambiar ese paging.
   - NO añadir PauseAy (el original no lo tiene a propósito; el "freeze" era el IM2 overlap,
     no alt-stack).

## VALIDACIÓN (cada paso)
- Build: `code\build_and_standalone.bat` (standalone, -DSTANDALONE=1, lanza Spectaculator).
  NUNCA sjasmplus pelado (los preprocs inyectan 9 sprites). Para todo: `build_all.bat`.
- `python tools/check_slot_overlap.py` (pero VERIFICA A MANO que ningún símbolo de
  minimap/minimap_timed cae en `$7A00-$7B7B` = Im2Table — el validador tiene un bug).
- Confirmar símbolos minimap (smRenderMap etc.) ahora en slot 1 ($4000-$7FFF, < $7A00)
  parseando `code/tmp_standalone.lst`.
- El bug afecta a dev Y standalone (cd447d0 es código común). Prueba standalone (peor caso:
  slot 1 más apretado por los thunks de la historia IFDEF STANDALONE).

## TESTING runtime
- Pon `DEBUG_FORCE_MAP EQU 1` en constants.asm:200 → cada random pickup es un map.
  Build → Spectaculator. Coge maps.
- Oráculo DETERMINISTA (el crash es no-determinista): el sonido de pickup suena
  **al ABRIR** el minimapa = BUENO; **al CERRAR / freeze** = MALO (IRQ disrupted por IM2
  overlap).
- Al terminar: revertir DEBUG_FORCE_MAP a 0.

## QUÉ NO REPETIR (ya probado y fallido)
- Guards de attrs (CalcAttrAddr clamp / SetEntityAttr bottom clip) — tratan síntoma.
- smRenderMap goal-marker $FF guard — no era.
- PauseAy en ShowMinimapTimed — cambió síntoma, no arregló.
- BgSpriteBuffer como stack del minimapa (832 B) — no era (el problema es el CÓDIGO
  corrupto, no su stack).
- day_cycle → bank 7 — day_cycle es render-hot (ApplyDayCycleRemap/CheckIfHouseSprite se
  llaman por celda durante render BG). MAL candidato.
- minimap → bank 7 — bloqueado por MapTable (dep bank 0).
- debug_unlock → bank 7 — bank 7 lleno de código (TOMBSTONE_ADDR $FB00).

## FALLBACK (si el thunk bank-4 / los 21 B se complican)
Quitar la historia del standalone tap (bloques IFDEF STANDALONE: F1Setup inline en Inicio,
standalone_splash_thunk, DecompressSplashTrampoline, SafeHaltAndPrefetch — ~112 B en
slot 1 + ~1.5 KB bank 4). La historia se conserva en desktop/web wrappers. Coste: quien
cargue el .tap en hardware real/emulador pelado se queda sin intro. El usuario PREFIERE
conservarla, por eso el plan principal es el camino mínimo (debug_unlock + 21 B).

## Archivos / direcciones clave
- `code/main.asm`: INCLUDE minimap.asm (~726, bank 0) · INCLUDE debug_unlock.asm (~374,
  slot 1) · bloques PAGE 4 y PAGE 7.
- `code/minimap.asm` (508 B, a mover) · `code/minimap_timed.asm` + `code/minimap_sprites.asm`
  (ya en slot 1).
- `code/debug_unlock.asm` (194 B, a bank 4) · `code/ay_sound_thunks.asm` (patrón thunk bank-4,
  AY_UpdateBell ~53) · `code/random_pickups_thunks.asm` (_RP_Thunk, patrón bank-7).
- `code/screen_data.asm:177` MapTable (bank 0) · `code/constants.asm:7` SP_ADDRESS=$FF58,
  :200 DEBUG_FORCE_MAP · `code/tombstones.asm:35` TOMBSTONE_ADDR=$FB00.
- Tools: `python tools/memory_map.py --cohesion|--heat|--movecost SYS --from N --to M|--dead`
  (doc docs/MEMORY_MAP.md).
