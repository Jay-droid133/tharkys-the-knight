# Tharkys the Knight — Devlog: índice cronológico (borrador)

**Autor:** Claude (yo), el asistente AI con el que se desarrolló el juego.
**Audiencia:** programadores, sobre todo gente con interés por retro / Z80 / Spectrum.
**Tono:** primera persona, presente histórico cuando relato cacerías de bugs; arqueológico (lectura de git + memoria + docs) cuando reconstruyo episodios que no recuerdo de forma continua, marcado explícitamente.
**Formato:** esqueleto cronológico con deep-dives temáticos. Los posts arrancan de un bug o problema concreto y el sistema se explica al hilo.

**Ámbito temporal:** 21 marzo 2026 → 23 mayo 2026. ~64 días, 820 commits.

**Reparto del trabajo:** Jay no ha escrito una sola línea de código — yo (Claude) escribí el 100 % (Z80, HTML, Python, C). Él aportó el **pixel art** (vasta mayoría dibujada desde cero por él; cinco sprites grandes asistidos con Gemini Nano Banana y luego refinados a mano: cabaña del bosque, árboles del bosque, puerta de la ciudad, iglesia, splash), la **música** (variaciones MIDI propias que él compone y toca; yo solo el conversor a AY y el driver), y todo el **diseño y dirección**. Es relevante para entender de quién está hablando cada post.

**Aviso de spoilers:** el blog es técnico, pero el **post 01** describe el flujo completo del juego incluido el final, y muchos posts posteriores asumen que ya lo conoces. Si quieres jugar a Tharkys sin saber nada, **juega primero y vuelve**.

**Hilos transversales:** dos arcos atraviesan el blog y se mencionan recurrentemente —
- la **evolución del diseño** (el juego que se diseñó no es el que se implementó; pivote brusco a finales de abril; ver post **11**).
- el **crecimiento del toolset** (las herramientas custom que se construyeron a medida que iban haciendo falta — editor BG, build_screen_gaps.py, memory_map.py, editor SFX, editor minimap, etc. Ver post **34**).

---

## Cómo leer este índice

Cada entrada es un **post candidato** del blog, no un post escrito todavía. Formato:

```
NN. Título tentativo (fecha o rango)
    Una línea de qué cuenta.
    Fuentes: commits / memorias / docs.
```

Marcas: `[bug-story]` = post-cacería, `[sistema]` = deep-dive de un sistema, `[meta]` = sobre el desarrollo en sí.

Cuando aparezcan memorias entre dobles corchetes (`[[slug]]`), son entradas concretas de mi memoria persistente del proyecto.

Los números son **tentativos**: si se inserta o se funde un post, los siguientes pueden cambiar.

---

## FASE 0 — Meta

**00. Por qué un devlog escrito por la AI** `[meta]`
Quién soy en este blog, cómo escribo (qué recuerdo y qué reconstruyo), cómo se repartió el trabajo con Jay durante el desarrollo. La parte honesta: no tengo recuerdo continuo, tengo artefactos.
Fuentes: introductoria, sin material previo.

**01. Tharkys the Knight: el juego que escribimos** `[meta]`
El pitch: Spectrum 128K, flick-screen, día/noche, conducir 3 monstruos a la iglesia. Por qué un juego de Spectrum en 2026. NOTA: el pitch aquí describe el juego que se terminó, no el que se diseñó al principio (ver post 11).
Fuentes: [[game-title]], implementación final.

---

## FASE 1 — Foundations (21 marzo → ~mediados abril)

**02. Día 1: Starting** (2026-03-21) `[meta]`
El primer commit literal se llama "Starting" — pero **no es zero**. 26 archivos, 3.830 líneas, build funcional, level editor HTML de 1.473 líneas, cinco salas conectadas en cruz. Antes del primer commit hubo dos fases que NO me corresponden: un juego anterior de Jay llamado *Snake* (de donde viene la estructura y el build pipeline) y un scaffolding inicial via **Google Antigravity** (de donde vienen las 3.830 líneas iniciales). El commit "Starting" marca la migración a Claude Code, no el inicio del juego.
Fuentes: commit `1495e05`, primeros 10 commits, `git show --stat`, [[snake-antigravity-prehistory]].

**03. Los editores HTML: dibujar y colocar Spectrum desde el navegador** (2026-03-22 → 28) `[sistema]`
Antes que el juego, los editores. Dos herramientas distintas: el **BG editor** (sprites individuales a nivel de pixel, RLE, slice→derived) y el **Level editor** (placements en salas, library manager, tint, auto-fill, triggers, templates). Pipeline 4 capas IndexedDB → JSON → ASM. Por qué HTML es el ángulo correcto para AI-assisted retro dev. Primer eslabón del toolset arc (ver post 34).
Fuentes: commits `c71bc39`, `fe36494`, `f167b22`, `f4cba2b`; [[bg-editor-idb-flow]], [[bg-editor-vs-level-editor]], [[sprite-workflow]], [[sync-bg-pickups]], `docs/SPRITE_WORKFLOW.md`.

**04. Ciclo día/noche: la regla PAPER, no INK** (2026-03-25) `[bug-story]`
El bug que me enseñó la diferencia entre PAPER e INK en attrs del Spectrum. Por qué cualquier color que cicla con la fase del día tiene que ser PAPER.
Fuentes: commits `9777fd0`, `a1d6c7a`, `579dc01`, `b0bc7fa`; [[paper-ink-rule]].

**05. HUD clock: agujas, decoraciones, color cycle** (2026-03-28) `[sistema]`
El reloj central del HUD. Sprite especial id=14 con render animado. Cómo se sincroniza con el ciclo de día. Cache de posición de las agujas para matar el parpadeo.
Fuentes: commits `ea03db1`, `dc619d0`, `2a768fc`, fix `8d2cb29` (mucho más tarde); [[plaza-clock]].

**06. Trampa silenciosa: sjasmplus resuelve símbolos indefinidos como 0** `[bug-story]`
El bug recurrente que me mordió varias veces. EQU mal escrita → símbolo a 0 → runtime "no hace nada" sin un solo warning. Cómo desarrollé el reflejo de mirar el .lst antes de debuggear.
Fuentes: [[undefined-symbols-silent]], [[sjasmplus-local-scope]].

---

## FASE 2 — Monsters, nasties y el paginado del 128K (final marzo → mayo)

**07. Nastis: spawn por gaps precalculados desde Python** (abril) `[sistema]`
Por qué los nastis no spawnean random sino en gaps validados por Python en build-time. La huella 2×3, la región conexa, el filtro MIN_POCKET_SIZE. Nacimiento de `tools/build_screen_gaps.py` — segunda gran herramienta del toolset, después del editor de BG. Más adelante el script evoluciona varias veces: parser de bg_gfx_c.asm, FORCED_GAPS, NON_BLOCKING_IDS.
Fuentes: `tools/build_screen_gaps.py`, [[nasty-spawn]], [[screen-gaps-gotchas]], [[gap-dimensions]], [[forced-gaps]], [[random-pickup-marker]].

**08. Monster AI v2: 12 fases, dos días** (2026-04-22 → 23) `[sistema]`
La saga grande. Pathfinding híbrido reactivo, 7 reglas de comportamiento, memoria per-slot (RoomId, LastSeen, EntryBorder), restore in-transit. Saco material de mi propia bitácora de la sesión.
Fuentes: `MONSTER_AI_SESSION.md` (es literalmente mi log de aquellos dos días), [[eager-state-transition]], [[monster-freeze-corpse]].

**09. El paginado del 128K: la geografía que decidió el proyecto** (visión transversal) `[sistema]`
Visión transversal de la arquitectura RAM que estructuró todo. Cuatro slots × 16 KB, qué es fijo y qué es paginable, dónde vive el stack ($FF58 en slot 3), qué hace el puerto $7FFD. Patrones que aparecieron: **alt stack** en slot 1, **thunks bank 7**, paging inline sin CALL, **IRQ atomic** en slot 3, **bank 2** como zona de variables fijas. El baile constante: ejemplos reales de código y datos que se movieron entre bancos durante los 64 días (driver de música, room routes, magic compass scratch, minimap sprites, town gate cutscene). `memory_map.py` y `check_slot_overlap.py` como visualizadores del baile. Post insertado fuera de cronología — el conocimiento se acumuló durante todo el proyecto, pero el lector necesita el modelo mental antes de leer los bug-stories que vienen.
Fuentes: memorias [[paging-alt-stack]], [[irq-slot3-atomic]], [[bank7-thunk-pattern]], [[slot1-im2-overflow]], [[ram-placement]], [[128k-build]], [[memory-map-tool]], [[slot1-real-free-space]]; commits dispersos por toda la línea temporal.

**10. Cuando el stack vive en slot 3: la trampa del paginado** `[bug-story]`
La cacería que me enseñó la arquitectura de paginación del Spectrum 128 en primera persona. Por qué rutinas que llaman a un bank paginado no pueden tocar el stack durante la ventana paginada. Stack temporal en bank 2, SP alterno en slot 1. Primera vez que la regla del post 09 se materializó como un bug concreto y costoso.
Fuentes: [[ay-thunk-stack-bug]], [[irq-slot3-atomic]], [[paging-alt-stack]]; commits `fcc49fc`, `dab8de0`, `e1e9c5f` (todos 2026-05-09).

---

## FASE 3 — El pivote del diseño (finales abril)

**11. Cómo evolucionó el diseño: 4 fases en 64 días** (visión transversal) `[meta]`
El juego que se diseñó NO es el juego que se implementó. Reconstruyo cuatro fases:

- **A — Solo motor** (21 marzo → 1 abril): sin documento de diseño. Editores, ciclo día/noche, BG sprites. El juego es "un motor de Spectrum".
- **B — Sabre Wulf con crucifijo** (`docs/game_design.md`, 2 abril → 25 abril): 3 trozos de llave soltados por carrier nasties blancas (1/día), crucifijo robado por un monstruo, mecánica final = conducir como ganado con crucifijo (los monstruos te huyen). Endgame = puerta sur + dedo medio.
- **C — Pivote a 9 hitos lineales** (`DESIGN_NOTES.md`, 26-27 abril): adiós carriers, adiós crucifijo. Entra cadena gateada de 9 hitos físicos. La brújula deja de ser objeto y se vuelve HUD. Se añaden sistema de muerte, tumbas, score.
- **D — Lo no planeado** (12 mayo → 23 mayo): magic compass como pickup (BFS sala-a-sala) que NO está en ningún diseño. Random pickup system completo (buffs/debuffs/seta/caracol). Bank cutscene infra. Sistema de dificultad diseñado pero nunca mergeado.

Through-lines y abandonos: la **ambientación** (ciudad amurallada, cementerio este, iglesia, puerta sur con dedo) sobrevive intacta desde la fase B. Las **mecánicas** que la conectaban se reemplazaron por una cadena lineal. El documento `docs/game_design.md` se commiteó UNA vez (2 abril) y nunca se actualizó — es un fantasma del juego que no fue.

Fuentes: `docs/game_design.md` (commit `53fc2fe`, 2026-04-02), `DESIGN_NOTES.md` (commit `49f3c46`, 2026-04-27), brain-dump original del autor (privado), comparación con memorias de implementación final, [[milestone-chain]], [[magic-compass]], [[difficulty-system]].

**12. Sesión cloud de diseño: el día del pivote** (2026-04-26) `[meta]`
Zoom-in al momento concreto. La sesión donde Jay y yo (en Claude on the web, sin código) cerramos las decisiones que hicieron posible la fase C: muerte y respawn, score, brújula HUD, cadena de 9 hitos, tumbas. Documento de salida: `DESIGN_NOTES.md`.
Fuentes: `DESIGN_NOTES.md`, [[milestone-chain]], [[hito-resolution]], [[compass-hud]].

**13. La cadena de hitos: del open-world al juego dirigido** (mayo) `[sistema]`
Cómo se implementó la cadena después del diseño. El diseño original (DESIGN_NOTES.md) listaba 9 hitos; la implementación final añadió el **cheque** y el **bank cutscene** como hitos extra entre la iglesia y la puerta sur. `CurrentObjective`, `MilestoneTable`, resolución dinámica de coordenadas escaneando `PickupTable`, dígito 8×8 de debug en el HUD.
Fuentes: [[milestone-chain]], [[hito-resolution]], [[cheque-bank-flow]], commits `f4bc8a4` (cheque como hito real), `8b6e4fb` (M#11 = arco sur).

---

## FASE 4 — La iglesia, la brújula, las muertes (mayo)

**14. La trampa de la iglesia: cinemática + freeze pattern** (final abril → mayo) `[sistema]`
La mecánica central del juego. Push del monstruo a celdas puerta, cutscene con la estatua temblando, puerta cierra, key spawn. Por qué el gameplay se tiene que congelar durante el XOR para no corromper attrs. La distinción entre knockback directo y por billar.
Fuentes: [[church-trap]], [[cutscene-freeze-pattern]], [[kb-direct]], [[statues-by-type]], [[time-freeze]]; commits `5b96518`, `204651a`, `d5f7bd3`, `9fe7f6e`.

**15. La brújula mágica: BFS sala-a-sala** (mayo) `[sistema]`
El sistema más complejo del juego desde mi punto de vista. BFS reverso con estado (sid, comp_local), tabla per-gap auto-generada por Python, LastEntrySide+LastEntryCoord para trackear el comp del player al entrar.
Fuentes: [[magic-compass]], `docs/magic_compass.md`, commits `62114f7`, `707b499`.

**16. Sistema de muerte: cuatro fases coreografiadas** (2026-05-05 → 09) `[sistema]`
HP=0 → golpe mortal → onda expansiva → caída (yellow 2s) → velo rojo (2s) → countdown 3.8s con beeps → gracia 1s. Cómo se coordinan vidas, border, anim, freezing de monstruos, tumba.
Fuentes: [[player-death-full-flow]], [[player-respawn-flow]]; commits `fd353aa`, `9c41f00`, `a4f5d5e`, `9b10cc2`.

**17. Tumbas persistentes** (mayo) `[sistema]`
Cómo se guardan tumbas en bank 7, 200 entradas × 4B. Por qué WriteTombAttrsCyan tiene que bypassear el remap día/noche. RefreshTombAttrsForRoom y la limpieza del CleanAttrMap.
Fuentes: [[tombstones]], [[sprite-2x-upscale]] (la tumba 2x del Game Over).

---

## FASE 5 — Cazerías de bugs gordos (mayo, en paralelo)

**18. El bus flotante que no era mío: chips emulator + IORQ+M1** (2026-05-11 → 12) `[bug-story]`
El bug que me tuvo dos días buscando una corrupción de memoria fantasma. Resulta que era el emulador `chips/zx.h` no implementando el comportamiento real del Spectrum durante IORQ+M1 (bus=$FF). Fix del lado del juego: mover BFS scratch lejos de la zona problemática.
Fuentes: [[chips-floating-bus-fix]], commits `95cc723`, `f1ca576`.

**19. LDIR destruye BC sin avisarte** (2026-05-10) `[bug-story]`
La animación HAND_OPEN_IN no funcionaba. Resulta que las rutinas Draw/Load que internamente usan LDIR destruyen BC. Si pasas args en B/C antes del CALL, PUSH/POP.
Fuentes: [[ldir-bc-corruption]], commit `ed30599`.

**20. El overflow silencioso del slot 1 y la tabla IM2** (2026-05-10) `[bug-story]`
Cualquier byte solapando $7A00..$7B00 corrompía la IM 2 table. El hardware lo enmascara via bus flotante, los emuladores imperfectos lo delataban. La saga: jingle dead-code eliminado, RoomCompGapsTable reubicado, ORG retrógrado descubierto.
Fuentes: [[slot1-im2-overflow]], [[slot1-overflow-canary]], [[org-retrograde-overlap]]; commits `6ab2ec1`, `5a2ceb9`, `7d210b3`.

**21. El stack que se corrompía atravesando page-switches** (2026-05-09) `[bug-story]`
Versión 1: PUSH/POP a través del page switch corrompen args porque el stack vive en slot 3. Solución: rutina self-contained en bank 2 sin paging.
Versión 2 (IM 2 race): el handler IRQ no puede paginar slot 3 porque el stack vive ahí. Código + datos llamados desde IRQ tienen que vivir en slot 1/2.
Fuentes: [[ay-thunk-stack-bug]], [[irq-slot3-atomic]]; commits `fcc49fc`, `dab8de0`.

**22. El IFF race: LD A,I y los freezes al arrancar** `[bug-story]`
El opcode `LD A,I` tiene una race condition con IRQ que ocasionalmente provocaba freezes al iniciar. Reemplazado por un flag `StartupComplete` propio en bloques DI/EI.
Fuentes: [[iff-race-fix]].

**23. Slot 3 stack corruption: cuando los datos en bank 0 se comen tu RAM** `[bug-story]`
SP_ADDRESS=$FF58 está dentro de slot 3. Datos en bank 0 a direcciones ~$FE80-$FF58 los corrompen los IRQs durante gameplay vía PUSH. Caso real: el sistema de minimap por sprites.
Fuentes: [[slot3-stack-corruption]], [[minimap-sprite-system]].

---

## FASE 6 — Audio (mayo, todo el mes)

**24. El driver AY: música a 25 Hz desde IRQ** (mayo) `[sistema]`
Cómo se compuso el driver de música. State+tablas+tick en slot 1, dispatcher StartMusic en bank 4, ~940 B de headroom. Por qué tickeamos a 25 Hz desde IRQ y no desde MainLoop.
Fuentes: [[ay-music-driver]], [[paging-alt-stack]].

**25. Editor de SFX en HTML: 5 fases en una tarde** (2026-05-15) `[sistema]`
La tarde del 15 de mayo: 5 commits `feat(sfx)` consecutivos. Schema JSON + compilador ASM + intérprete slot 1 + editor HTML Bfxr-style + migración de SFX existentes. Por qué se pudo hacer tan rápido (spoiler: porque el resto del toolset ya estaba maduro y el patrón JSON→ASM era ya rutina).
Fuentes: [[ay-sfx-editor]]; commits `af2476b`, `a804cfb`, `76a7ee4`, `1958352`, `6b0618c`, `cbf6b20`.

**26. La música de los monstruos disfrazada de SFX** (mayo) `[sistema]`
El "popopopo" continuo durante la noche que parece SFX pero es música funcional sobre canal B. Coexiste con Death music, nunca con Sunrise/Tension.
Fuentes: [[monsters-music-channel-b]], [[gameover-drums]].

**27. SFX no-bloqueantes: AY_PlayPlayerHit y AY_PlayBeep** (mayo) `[sistema]`
Cómo evitamos que un SFX bloquee el resto del audio. Tickeo desde el IRQ handler, no desde MainLoop, para inmunizar la duración frente a latencia de transiciones.
Fuentes: [[player-hit-sfx-ay]].

---

## FASE 7 — Port a SDL2 (mayo)

**28. El port: emular el Spectrum a mano** (mayo) `[sistema]`
Por qué hay una carpeta `port/` con SDL2 + chips. Wrapper sobre chips emulator para correr el SNA fuera de Spectaculator. F1 help, splash, pause, gamepad, CRT filters.
Fuentes: [[desktop-wrapper]]; commits `c203ea1`, `b53678a`, `25eb236`, `6e815e2`.

**29. El AY que silbaba en mono: anti-flange en ayumi** (2026-05-18) `[bug-story]`
Cuando period_a == period_c y se mezclan A+C a mono, suena phaseado. Fix: silenciar C en ayumi solo en el wrapper, mantener estéreo ABC en el SNA (porque Spectaculator y hardware real lo manejan bien).
Fuentes: [[poly2-mono-flange]]; commit `7d9d5f5`.

---

## FASE 8 — Pulido y release (14 → 23 mayo)

**30. Minimap: de tabla a sprite por sala** (2026-05-14 → 21) `[sistema]`
La saga del minimap. Empezó como MinimapConnTable + smDrawConnectedBorder, terminó como sprite 8×8 px por sala diseñado en `tools/minimap_sprite_editor.html`. Pipeline JSON → ASM. Datos en slot 1 por seguridad.
Fuentes: [[minimap-sprite-system]]; commits `e87720b`, `f3b61ce`, `d643176`, `390bb6f`, `15964f8`.

**31. La cinemática del portón final** (2026-05-14 → 20) `[sistema]`
M9 final. Arco partido en 3 sprites (part1=trigger), WAIT_NASTIES + WALK_TO_ANCHOR + BiClip slide-S off-screen → "The End" → créditos. Migración del cutscene a bank 7 con thunks. Esta cinemática es lo único de la endgame original (fase B del diseño) que sobrevivió intacto.
Fuentes: [[town-gate-cutscene]], [[bank-cutscene-session]], [[bank7-thunk-pattern]]; commits `c558b04`, `482c849`, `cbc97ff`.

**32. RAM master plan: cómo recuperamos 4 KB del slot 1** (mayo) `[sistema]`
El plan de optimización de RAM. 4 fases, branch `ram/optimize-slot1`, validador `tools/check_slot_overlap.py`. Cómo el slot 1 estaba a 99.6 % y aún había ~660 B reales libres distribuidos en tres zonas. Nacimiento de `tools/memory_map.py` v1→v2→v3 — la herramienta que más cambió mi forma de razonar sobre el proyecto. Hito clave del toolset arc.
Fuentes: [[ram-master-plan]], [[ram-expansion-plan]], [[ram-optimization-options]], [[slot1-real-free-space]], [[memory-map-tool]]; `docs/RAM_OPTIMIZATION_PLAN.md`, `docs/MEMORY_MAP.md`.

**33. Release: TAP, splash, font Reward, créditos** (2026-05-19 → 23) `[meta]`
Los últimos días. Cómo se empaqueta el TAP final. Splash con música EndGame durante carga, prompt "PRESS ANY KEY / BUTTON", Reward font para créditos. Los últimos commits del proyecto.
Fuentes: commits `77461bf`, `78ac381`, `c5161bc`.

**34. El toolset que creció con el juego** (visión transversal) `[meta]`
Tharkys no se hizo solo con sjasmplus y un editor de texto. A medida que el desarrollo lo pedía, fueron apareciendo herramientas custom — todas en Python o HTML, todas pegadas al pipeline de build. Inventario y arco temporal:

- **Marzo**: editor de BG en HTML con IndexedDB ([[bg-editor-idb-flow]]). El primero. Nace antes que cualquier código del juego.
- **Marzo-abril**: level editor con player start, key/lock placement, ALT respawn markers, route visualization, library manager ([[player-start]], [[editor-altkey]], [[route-visualization]], [[saved-routes]], [[safety-guards]], [[library-manager-ux]], [[editor-robustness]]).
- **Abril**: `tools/build_screen_gaps.py` para validar gaps de spawn — primero parser de bg_gfx.asm, luego soporte multi-biome, luego FORCED_GAPS para salas densas, luego NON_BLOCKING_IDS para markers ([[screen-gaps-gotchas]], [[forced-gaps]], [[gap-dimensions]], [[random-pickup-marker]]).
- **Abril-mayo**: scripts pixel-art `import_nasty.py`, `import_compass.py`, `import_smoke.py` — aseprite → DEFB ASM con detección strip vs frames separados ([[pixel-import-scripts]], [[sprite-tools]]).
- **Mayo**: `tools/sprite_generator.html` con bridge BroadcastChannel al BG editor — PNG → pixel art Spectrum ([[sprite-generator]]).
- **Mayo**: `tools/sync_bg_pickups.py` RLE-aware con auto-recompress ([[sync-bg-pickups]]).
- **Mayo (cuando la RAM se acabó)**: `tools/memory_map.py` v1→v2→v3 + `tools/check_slot_overlap.py`. v3 trajo call graph, heat map, dead-code detection, move-cost analysis. La herramienta que más cambió mi forma de razonar sobre el proyecto ([[memory-map-tool]], `docs/MEMORY_MAP.md`).
- **Mayo**: editor de SFX HTML Bfxr-style + intérprete ASM en slot 1 ([[ay-sfx-editor]]).
- **Mayo**: `tools/minimap_sprite_editor.html` y pipeline JSON → ASM para sprites de minimap ([[minimap-sprite-system]]).
- **Mayo**: `midi_to_endgame_asm.py` con `--loop-from BAR.BEAT` para convertir MIDI a música AY del bank 7.

Patrón observable: cada herramienta nace en el momento exacto en que algo del juego empieza a ser cuello de botella manual. El editor de BG nace porque hacer sprites a mano no escala. build_screen_gaps.py nace porque debuggear spawns de nastis manualmente no escala. memory_map.py nace porque calcular delta de RAM desde el .lst a mano no escala. El patrón se mantiene los 64 días: detectar coste manual repetitivo → script o editor.

Punto fuerte para el ángulo técnico del blog: los lectores con proyectos retro propios pueden mirar este post como un *checklist* — "¿qué deberías estar automatizando ya?". Y el ángulo meta: las tools son lo que más se beneficia del trabajo AI-asistido (boilerplate parsing + UI). Más que el código del juego.

Fuentes: memorias listadas arriba, `tools/` (todo el directorio), commits dispersos a lo largo del proyecto.

---

## CIERRE

**35. Lo que queda fuera del release: bugs abiertos y features no mergeadas** `[meta]`
El freeze observado durante muerte en sala (8,8) que no he conseguido reproducir. La lista privada del autor con cosas sin tachar. El sistema de dificultad diseñado pero no integrado. Por qué no son blockers para el release y qué pasaría si quisiéramos cerrarlos.
Fuentes: [[death-freeze-open]], [[difficulty-system]].

---

## Posts candidatos en cola (sin sitio claro todavía)

Cosas que quería contar pero no sé si merecen post propio o se funden en otros:

- **Las tablas que identifican sprites por puntero exacto** ([[keylock-sprite-id-trap]]) — gotcha del editor que rompió KeyLockTable. Se podría meter en el post del editor (#03) o del milestone chain (#13).
- **La pipeline pixel-art** ([[pixel-import-scripts]], `tools/sprite_generator_PROMPT.md`) — scripts Python de aseprite → DEFB. Podría ir en #03 o como post propio si se quiere defender la pipeline asistida.
- **El render RLE de sprites** ([[rle-sprite-render]]) — bit 7 de width_bytes = RLE, solo DrawBgGfxSprite decodifica. Gotcha técnica que merece nota pero quizás no post entero.
- **Player vs BG sprites: CPL'd o no** ([[player-sprite-no-cpl]]) — sprite_data.asm bytes directos vs bg_gfx.asm CPL'd. Gotcha de las rutinas XOR custom.
- **XOR custom y el clip Y=192** ([[xor-clip-192]]) — sin clip explícito a Y>=192, custom XOR escribe en attr area → flashes random.

---

## Notas sobre cómo se va a escribir

- **Cada post arranca con un problema concreto**, no con "vamos a explicar el sistema X". El sistema se explica al hilo de la cacería.
- **El git log es la verdad** para fechas y orden. Mi memoria persistente es el material narrativo. Los `docs/*.md` son el material de referencia técnica.
- **Cuando algo se sale de mi memoria**, lo marco: "Reconstruyo desde commit XYZ — no recuerdo esta sesión directamente, pero los .md y el diff cuentan que…".
- **Los errores que cometí van dentro**: las veces que propuse algo que no funcionó, las suposiciones falsas que costaron tiempo, los bugs que se me escaparon. Es lo que hace al blog distinto de la documentación técnica del repo.
- **No vamos a publicar todavía**. Esto es el índice provisional. Lo que esperaría es que reacciones diciendo: este post sí, este no, este lo fundes con aquel, este episodio falta, este lo cuento yo, este lo cuentas tú, etc.

---

*Borrador 1 — generado el 2026-05-23 por Claude.*
*Revisión 2 — añadido post 10 (evolución del diseño), renumerados los siguientes.*
*Revisión 3 — añadido post 33 (toolset arc) como segundo hilo transversal; cierre pasa a 34; mejoradas menciones de tools en posts 03, 07, 24, 31.*
*Revisión 4 — añadido post 09 (paginado del 128K) como visión transversal arquitectónica; renumerados todos los posts 09-34 → 10-35; FASE 2 renombrada a "Monsters, nasties y el paginado del 128K"; cross-refs actualizados.*
