# Sesión: depuración de los controles MÓVILES del wrapper web

> Nota de memoria para retomar en una sesión local. Rama de trabajo:
> `claude/adoring-ptolemy-FRKRa` (commit `d69efe2`). Único fichero tocado:
> `port/src/main.c`. Build verificado en limpio con Emscripten.

## Problema

En móvil el **TAP no sacaba del SplashWait del juego** (pantalla "pulsa para
empezar" con iconos animados, justo antes de la primera sala). El intro del
wrapper, el menú de idioma y la historia SÍ avanzaban con tap; solo se atascaba
en el SplashWait.

## Causa raíz (confirmada leyendo el código, no a ciegas)

Dos causas acopladas, ambas en la ruta de input móvil (`#ifdef __EMSCRIPTEN__`)
de `port/src/main.c`:

1. **FIRE es de NIVEL, no de flanco.** El intro/menú/historia avanzan en el
   flanco `SDL_FINGERDOWN`, por eso funcionaban. El SplashWait
   (`code/splash_wait.asm`, `SplashCheckInput` ~línea 184) lee el bit FIRE
   *presente* en el mask Kempston que el wrapper reconstruye 1 vez por RAF. Un
   tap rápido cuyo `FINGERUP` caía en el mismo lote de `SDL_PollEvent` que el
   `FINGERDOWN` dejaba `g_web_fire_fingers` de vuelta en 0 ANTES de construir el
   mask → FIRE nunca se reenviaba.

2. **El tilt bloqueaba la fase de RELEASE del SplashWait.** `SplashWait` es
   idle → press → release, y la fase final espera a que `$1F` lea TOTALMENTE
   idle. El primer tap ponía `g_web_game_started = 1`, lo que des-gateaba el
   tilt al instante; con el móvil a >10° del neutral capturado, un bit de
   dirección (p.ej. RIGHT=`$01`) quedaba activo para siempre →
   `SplashCheckInput` devolvía NZ ("pulsado") → `.spwWaitRelease` en bucle
   infinito → atascado. (Esto explica por qué gatear el tilt tras
   `game_started` no bastó: arregló la fase idle inicial, no la de release.)

Descartadas: hipótesis #4 (chips usa Kempston, `EMU_JOY_FIRE=$10` → bit 4, `IN
$1F` lee `$10` bien) e hipótesis #2 (`g_input_needs_release` se limpia en 1
frame en móvil al no haber teclado/gamepad).

## El fix (en `port/src/main.c`, todo bajo `#ifdef __EMSCRIPTEN__`)

- Nuevo `g_web_fire_hold` + `#define WEB_FIRE_MIN_HOLD 6`: `SDL_FINGERDOWN`
  engancha un mínimo de frames de FIRE forzado, así el press se ve siempre por
  rápido que se levante el dedo.
- `web_mobile_mask()` reenvía FIRE si hay dedo apoyado **o** el hold sigue
  contando.
- `g_web_tilt_arm` + `#define WEB_TILT_ARM_FRAMES 60` + `web_mobile_tick()`
  (llamada 1 vez por frame de gameplay, antes de `web_mobile_mask`): el tilt se
  arma SOLO tras soltar el tap de inicio **completo** + ~1 s de retardo — para
  entonces el release del SplashWait ya registró y estás en la primera sala.
- Eliminado el viejo `g_web_game_started = 1;` instantáneo del `FINGERDOWN`.
- Añadido diagnóstico por `stderr` (`mobile tap: fingers/hold/arm`,
  `tilt armed`) visible por remote-debug (Android: `chrome://inspect`; iOS:
  Safari Web Inspector).

## Estado / pendiente

- [x] Fix implementado y commiteado (`d69efe2`) en `claude/adoring-ptolemy-FRKRa`.
- [x] Build web verificado en limpio (emcc 5.0.7). Artefactos generados en
      `port/build-web/bin/tharkys.{html,js,wasm}`, sello `2026-05-29 06:15`.
      (Los 4 warnings de compilación son `unused-variable` preexistentes,
      ajenos a este cambio.)
- [ ] **Deploy a Pages** (`Jay-droid133/tharkys` → rama `main`): pendiente,
      lo hace el usuario. No tengo credenciales para ese repo desde la sesión.
      Lo más simple: renombrar `tharkys.html`→`index.html` y subir los 3 a mano
      por la web de GitHub, o usar el bloque `git mktree`/`gh-pages` del
      enunciado desde un clon local.
- [ ] **Probar en el dispositivo real** (preguntar al usuario móvil/navegador).
      Verificar con la consola remota que aparece `mobile tap: ...` en cada
      toque y `tilt armed` ~1 s tras el primer tap.

## Cómo seguir en local

```bash
git fetch origin
git checkout feat/wrapper-web
git merge origin/claude/adoring-ptolemy-FRKRa   # solo toca port/src/main.c, merge limpio
# rebuild:
emcmake cmake -B port/build-web -S port
emmake cmake --build port/build-web
python port/serve_web.py 8766                    # servir local sin cache
```

## No re-romper (trampas ya resueltas en el wrapper)

Audio a rate nativo del navegador (no 44100) + callback/ring; teclado con
captura global + filtro de atajos en `shell.html`; `SDL_PIXELFORMAT_RGBA32`;
`ALLOW_HIGHDPI` para CRT 1:1; el tilt necesita HTTPS (Pages lo da). NO editar
fuentes con acentos vía PowerShell `Get/Set-Content` (corrompe UTF-8 → usar
editor normal o Python utf-8).
