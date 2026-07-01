// Manual TÉCNICO de "Tharkys the Knight" - .docx con índice clickable y dinámico
const fs = require('fs');
const path = require('path');

const NPM_GLOBAL = process.env.APPDATA + '/npm/node_modules';
const docx = require(NPM_GLOBAL + '/docx');

const {
    Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
    Header, Footer, AlignmentType, LevelFormat,
    HeadingLevel, BorderStyle, WidthType, ShadingType, PageNumber, PageBreak,
    TableOfContents, UnderlineType,
} = docx;

// -------------------------- helpers ----------------------------------------
const cBorder = { style: BorderStyle.SINGLE, size: 4, color: "888888" };
const borders = { top: cBorder, bottom: cBorder, left: cBorder, right: cBorder };

function P(text, opts = {}) {
    return new Paragraph({
        spacing: { after: 120 },
        ...opts,
        children: [new TextRun({ text })],
    });
}
function H1(text) {
    return new Paragraph({
        heading: HeadingLevel.HEADING_1, pageBreakBefore: true,
        children: [new TextRun(text)],
    });
}
function H2(text) { return new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(text)] }); }
function H3(text) { return new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(text)] }); }
function bullet(text, level = 0) {
    return new Paragraph({ numbering: { reference: "bullets", level }, children: [new TextRun(text)] });
}
function numbered(text) {
    return new Paragraph({ numbering: { reference: "numbers", level: 0 }, children: [new TextRun(text)] });
}
function mono(text) {
    return new Paragraph({
        spacing: { after: 100 },
        shading: { fill: "F0F0F0", type: ShadingType.CLEAR },
        children: [new TextRun({ text, font: "Consolas", size: 19 })],
    });
}
function note(text) {
    return new Paragraph({
        spacing: { before: 60, after: 120 },
        indent: { left: 240 },
        border: { left: { style: BorderStyle.SINGLE, size: 18, color: "2E5C8A", space: 6 } },
        shading: { fill: "EAF3FB", type: ShadingType.CLEAR },
        children: [new TextRun({ text, italics: true, size: 20 })],
    });
}
function cell(text, opts = {}) {
    const { width, shade, bold, align, font } = opts;
    return new TableCell({
        borders,
        width: { size: width, type: WidthType.DXA },
        shading: shade ? { fill: shade, type: ShadingType.CLEAR } : undefined,
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({
            alignment: align || AlignmentType.LEFT,
            children: [new TextRun({ text, bold: !!bold, font: font || "Arial", size: font ? 19 : 22 })],
        })],
    });
}
function buildTable(headers, rows, columnWidths, monoIdx = []) {
    const total = columnWidths.reduce((a, b) => a + b, 0);
    const headerRow = new TableRow({
        tableHeader: true,
        children: headers.map((h, i) => cell(h, { width: columnWidths[i], shade: "1F3A5F", bold: true })),
    });
    const bodyRows = rows.map((r, ridx) => new TableRow({
        children: r.map((c, i) => cell(c, {
            width: columnWidths[i],
            shade: ridx % 2 === 0 ? "F2F2F2" : "FFFFFF",
            font: monoIdx.includes(i) ? "Consolas" : undefined,
        })),
    }));
    return new Table({ width: { size: total, type: WidthType.DXA }, columnWidths, rows: [headerRow, ...bodyRows] });
}

// -------------------------- contenido --------------------------------------
const s = [];

// ====== Portada ======
s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 2400, after: 240 },
    children: [new TextRun({ text: "THARKYS THE KNIGHT", bold: true, size: 56, color: "1F3A5F" })],
}));
s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 200 },
    children: [new TextRun({ text: "Manual Técnico", italics: true, size: 40, color: "555555" })],
}));
s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 1200 },
    children: [new TextRun({ text: "Arquitectura, motor y herramientas", size: 26, color: "777777" })],
}));
s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Z80 · ZX Spectrum 128K · sjasmplus · AY-3-8912", size: 22 })],
}));
s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 3600 },
    children: [new TextRun({ text: "Documento generado automáticamente.", size: 20, italics: true, color: "888888" })],
}));
s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Pulsa F9 sobre el índice para refrescarlo.", size: 20, italics: true, color: "888888" })],
}));

// ====== Índice ======
s.push(new Paragraph({ children: [new PageBreak()] }));
s.push(new Paragraph({
    heading: HeadingLevel.HEADING_1,
    children: [new TextRun("Índice")],
}));
s.push(new Paragraph({
    spacing: { after: 200 },
    children: [new TextRun({
        text: "El índice de abajo es un campo dinámico. Cada entrada es un hipervínculo: " +
              "Ctrl+clic la abre. Para regenerarlo tras editar el documento: clic derecho → " +
              "Actualizar campos (o F9).",
        italics: true, size: 20, color: "666666",
    })],
}));
s.push(new TableOfContents("Tabla de contenidos", {
    hyperlink: true,
    headingStyleRange: "1-3",
    captionLabel: "Tharkys the Knight",
}));

// ====== 1. Visión general ======
s.push(H1("1. Visión general del proyecto"));
s.push(P(
    "«Tharkys the Knight» es un juego de aventura tipo flick-screen escrito íntegramente en " +
    "ensamblador Z80 para ZX Spectrum 128K. El motor utiliza paginación de bancos extensiva, " +
    "un driver de audio sobre el AY-3-8912 y un sistema de pathfinding BFS para una brújula " +
    "mágica que guía al jugador en tiempo real."
));
s.push(buildTable(
    ["Campo", "Valor"],
    [
        ["Plataforma",        "ZX Spectrum 128K / +2 / +3 (emuladores compatibles)"],
        ["CPU",               "Z80 @ 3,5 MHz"],
        ["RAM",               "128 KB en 8 bancos de 16 KB"],
        ["Sonido",            "AY-3-8912 (3 canales tonales + 1 ruido)"],
        ["Vídeo",             "256×192 px, 32×24 attr (1 tinta + 1 papel + bright/flash por celda 8×8)"],
        ["Frame rate",        "50 Hz (PAL, sincronizado con HALT)"],
        ["Audio rate",        "25 Hz (IRQ cada 2 frames)"],
        ["Ensamblador",       "sjasmplus"],
        ["Lenguaje secundario", "Python (toolchain), JavaScript (editores HTML)"],
        ["Salida",            "juego.tap (cinta), juego.sna (snapshot)"],
        ["Líneas .asm",       "48 archivos en code/"],
        ["Herramientas",      "32 scripts Python + 8 editores HTML"],
    ],
    [3200, 6160],
));

// ====== 2. Mapa de memoria ======
s.push(H1("2. Mapa de memoria y bancos"));

s.push(H2("2.1 Slots de paginación del Z80"));
s.push(P(
    "El Z80 ve 64 KB de espacio direccionable, divididos en 4 «slots» de 16 KB cada uno. " +
    "El controlador de memoria del Spectrum 128 permite mapear cualquiera de los 8 bancos físicos " +
    "en el slot 3 (escribiendo en el puerto $7FFD)."
));
s.push(buildTable(
    ["Slot", "Direcciones", "Contenido", "Notas"],
    [
        ["0", "$0000–$3FFF", "ROM (BASIC/Editor o 128K)",         "Solo lectura. No usada por el juego."],
        ["1", "$4000–$7FFF", "Banco 5 fijo (VRAM)",               "VRAM ($4000–$5AFF) + attr ($5800–$5AFF). Contenido. RAM hasta $7FFF."],
        ["2", "$8000–$BFFF", "Banco 2 fijo",                       "RAM principal del juego: motor, lógica, datos calientes."],
        ["3", "$C000–$FFFF", "Banco paginable (0/1/3/4/6/7)",      "Banco activo según necesidad. La PILA vive aquí: ¡cuidado al paginar!"],
    ],
    [600, 1700, 3300, 3760],
));
s.push(note(
    "Crítico: la pila (SP) vive en slot 3. Cualquier rutina que pagine slot 3 debe garantizar " +
    "que la pila esté en zona segura ANTES del cambio, o el siguiente RET salta a basura. " +
    "El juego usa un patrón de «alt stack» (SP temporal en slot 1) durante page switches."
));

s.push(H2("2.2 Uso real de bancos"));
s.push(P("Estos números provienen del último build (build_stats.json):"));
s.push(buildTable(
    ["Banco", "Bytes usados", "Libre", "%", "Contenido"],
    [
        ["0", "15 830", "554",    "96,6 %", "Código principal (parte alta)"],
        ["1", "11 841", "4 543",  "72,3 %", "screen_rooms (datos de pantallas)"],
        ["2", "—",      "—",      "—",      "Variables RAM + buffers calientes (slot 2)"],
        ["3", "14 097", "2 287",  "86,0 %", "bg_gfx (baseline + neutrales + fillers)"],
        ["4", "11 732", "4 652",  "71,6 %", "bg_gfx_b (ruinas + cementerio)"],
        ["5", "—",      "~660",   "~95 %",  "screen_gaps + drivers + datos slot 1"],
        ["6", "14 080", "2 304",  "85,9 %", "monster_ai + sprite_data + shift_tables"],
        ["7", "14 379", "2 005",  "87,8 %", "bg_gfx_c (bosque) + cinemática puerta sur"],
    ],
    [800, 1700, 1300, 1100, 4460],
));
s.push(note(
    "El banco 5 (slot 1) está prácticamente lleno, pero contiene ~660 B repartidos en tres " +
    "zonas: gap interno (~600 B), final (~64 B) y variables_lo ($5D00, ~53 B)."
));

s.push(H2("2.3 RAM baja ($5B00–$5FFF)"));
s.push(buildTable(
    ["Rango",        "Uso"],
    [
        ["$5800–$5AFF", "Atributos de pantalla (768 B)"],
        ["$5B00–$5BFF", "Buffer de impresora (256 B) - reusado como scratch BFS de la brújula mágica"],
        ["$5C00–$5CFF", "BFS scratch / datos calientes que NO deben caer en bus flotante"],
        ["$5D00–$5FFF", "Variables low-RAM (variables_lo.asm)"],
    ],
    [2400, 6960],
));
s.push(note(
    "El printer buffer se reutiliza como scratch BFS: siempre visible y excluido del SAVETAP. " +
    "La tabla IM 2 vive en bank 2 (im2_table.asm, no-contended): I apuntando a RAM contended " +
    "produce ULA snow en hardware real."
));

// ====== 3. Boot y bucle principal ======
s.push(H1("3. Arranque y bucle principal"));

s.push(H2("3.1 Secuencia de arranque (Inicio)"));
s.push(numbered("DI: deshabilitar interrupciones."));
s.push(numbered("Set SP a SP_ADDRESS (valor conocido, slot 3)."));
s.push(numbered("CALL InitPaging: dejar banco 0 en slot 3 (estado conocido)."));
s.push(numbered("CALL AY_Init: silenciar AY (necesario en port: chips/zx.h no resetea AY)."));
s.push(numbered("Borde negro + clear total de VRAM (6912 B)."));
s.push(numbered("Zero-fill de variables low-RAM ($5D00–LOW_RAM_END)."));
s.push(numbered("Setup IM 2 (I = high Im2Table; tabla de 257 bytes en bank 2, im2_table.asm)."));
s.push(numbered("Setea StartupComplete = 1 (en lugar de LD A,I — race condition con IRQ)."));
s.push(numbered("EI + JP MainLoop."));

s.push(H2("3.2 Main loop (50 Hz)"));
s.push(mono(
    "MainLoop:\n" +
    "    HALT                       ; espera VBlank (50 Hz exacto)\n" +
    "    CALL ReadInput             ; teclado + Kempston + Sinclair 1\n" +
    "    CALL UpdateLogic           ; tick global: clock, milestones, AI\n" +
    "    CALL DrawGame              ; erase + update + draw por entidad\n" +
    "    JP MainLoop"
));

s.push(H2("3.3 Pipeline por entidad"));
s.push(P("Cada entidad ocupa 12 bytes en una tabla fija (estructura universal):"));
s.push(buildTable(
    ["Offset", "Campo",         "Bytes", "Descripción"],
    [
        ["+0",  "TYPE",          "1",     "Tipo (player, nasty, monster, death, puff, tomb…)"],
        ["+1",  "STATE",         "1",     "Idle / spawning / dying / scared / ghost…"],
        ["+2",  "X",             "1",     "Posición X (8 bit, sin subpixel)"],
        ["+3",  "Y",             "1",     "Posición Y"],
        ["+4",  "DX, DY",        "2",     "Dirección o componentes de movimiento"],
        ["+6",  "SPRITEID",      "1",     "Frame actual (para animación incremental)"],
        ["+7",  "ATTR",          "1",     "Color de tinta + bright"],
        ["+8",  "FLAGS",         "1",     "Bit 0 = KB directo del player, bit 1 = ghost, …"],
        ["+9",  "TIMER",         "1",     "Timer de estado actual"],
        ["+10", "AUX1, AUX2",    "2",     "Uso libre por tipo"],
    ],
    [800, 1600, 800, 6160],
));
s.push(P("Bucle por entidad: ERASE (XOR del frame anterior) → UPDATE (lógica) → DRAW (XOR del nuevo frame). Una sola rutina XOR sirve para ambos lados."));

// ====== 4. Sistema de gráficos ======
s.push(H1("4. Sistema gráfico"));

s.push(H2("4.1 Sprites de fondo (BG sprites)"));
s.push(P(
    "Los sprites de fondo (rocas, árboles, edificios, puertas, pickups visibles) se almacenan " +
    "como datos invertidos (CPL'd) con compresión RLE opcional."
));
s.push(bullet("Cabecera: width_bytes (1 B) + height (1 B). Bit 7 del width = sprite RLE."));
s.push(bullet("Solo DrawBgGfxSprite decodifica RLE; las rutinas XOR custom (shake, jitter) requieren datos planos."));
s.push(bullet("Almacenados en bancos 3, 4 y 7 según el bioma (forest / ruins-cemetery / town)."));
s.push(bullet("Direccionados por (puntero, banco) vía BgGfxPtrById."));
s.push(bullet("Límite por sprite individual: 1024 B en BgSpriteBuffer."));

s.push(H2("4.2 Sprites de entidades"));
s.push(bullet("sprite_data.asm (banco 6): bytes directos (NO CPL'd). 16×24 píxeles típicos."));
s.push(bullet("Player es 16×21 (no 16×24): el bbox de colisión usa Y+0..Y+20."));
s.push(bullet("Frames por animación: 2–4. Avance por sprite ID secuencial."));
s.push(bullet("Atributos por celda: tabla per-frame o per-tipo. Bypass del remap día/noche en pickups sintéticos."));

s.push(H2("4.3 Sistema de bancos para gráficos"));
s.push(P(
    "Las pantallas (rooms) almacenan placements en formato de 4 bytes: { id, x, y, v }, " +
    "donde v es un índice de variante (para tints o frames alternativos). La resolución " +
    "id → puntero ocurre en BgGfxPtrById, que devuelve además el banco a paginar."
));
s.push(P("Los IDs en los bordes de pantalla determinan el «vecino» de bioma: un árbol pegado a una pared de piedra hereda el bioma vecino al cruzar."));

s.push(H2("4.4 Rutinas de dibujo"));
s.push(buildTable(
    ["Rutina",                "Uso"],
    [
        ["DrawBgGfxSprite",      "Render normal con decodificación RLE."],
        ["DrawBgSpriteXOR",      "XOR sin RLE (shake, blink, jitter)."],
        ["DrawBgSprite16XorAtPixel", "XOR a píxel exacto (sub-char) para temblores."],
        ["DrawSprite16",         "Sprites de entidad de 16 píxeles de ancho."],
        ["DrawTombstone2xCentered", "Upscale 2× via NibbleDoubleLUT para Game Over."],
        ["NextPixelLine",        "Helper para avanzar 1 línea pixel en VRAM (sin bounds check)."],
    ],
    [3600, 5760],
));
s.push(note("NextPixelLine no comprueba límites: cualquier XOR custom debe clamp Y < 192 o escribirá en la zona de atributos."));

// ====== 5. Driver de audio ======
s.push(H1("5. Audio: driver AY y sistema SFX"));

s.push(H2("5.1 Topología"));
s.push(buildTable(
    ["Canal AY", "Uso primario", "Uso secundario"],
    [
        ["A", "Música (melodía)",     "—"],
        ["B", "Música (acompañamiento) / SFX cortos", "Loop de monstruos (popopopo continuo)"],
        ["C", "Música (bajo / textura)", "Death music / efectos largos"],
        ["Ruido", "SFX percusivos",   "Hit del player, viento"],
    ],
    [1400, 4000, 3960],
));

s.push(H2("5.2 Driver de música"));
s.push(P(
    "El driver vive en music_irq.asm (slot 1, banco 5). El tick se llama desde el handler IM 2 " +
    "una vez cada 2 frames (25 Hz)."
));
s.push(bullet("State + tablas + tick: ~940 B residentes en slot 1."));
s.push(bullet("Dispatcher StartMusic: tabla de temas en banco 4."));
s.push(bullet("Compone notas, envelope hardware y cambio de instrumento."));
s.push(bullet("Headroom para ~313 notas adicionales antes de saturar slot 1."));
s.push(note(
    "Por qué 25 Hz y no 50: a 50 Hz cada nota dura mínimo 20 ms (1 frame), lo que limita la " +
    "granularidad de envelopes. A 25 Hz se libera mitad del coste CPU del IRQ y los efectos " +
    "siguen sonando con suficiente resolución temporal."
));

s.push(H2("5.3 Sistema de SFX"));
s.push(P("Los efectos se escriben directamente sobre los registros AY, compartiendo canales con la música:"));
s.push(bullet("sfx_interp.asm: intérprete de tablas SFX_*."));
s.push(bullet("sfx_data.asm: definiciones declarativas (tono, duración, envelope)."));
s.push(bullet("SFX cortos (hit, pickup, beep): un canal libre + cutoff abrupto al terminar."));
s.push(bullet("AY_PlayPlayerHit y AY_PlayBeep son no bloqueantes: ticken desde el IRQ handler."));
s.push(note(
    "El tick de SFX debe vivir en el IRQ, NO en MainLoop. Si vive en MainLoop, la latencia de " +
    "transiciones de pantalla (carga de banco, LDIR) alarga las notas y arruina el sonido."
));

s.push(H2("5.4 Trampa del thunk AY"));
s.push(P(
    "Una rutina AY que cambie de banco (PUSH BC, paginar, POP BC) corrompe sus argumentos: la " +
    "pila vive en slot 3, así que el PUSH/POP a través del cambio de banco no es atómico. " +
    "Solución: la rutina AY debe ser self-contained en banco 2 (siempre visible)."
));

// ====== 6. IRQ y sincronía ======
s.push(H1("6. IRQ y sincronía"));

s.push(H2("6.1 Modo IM 2"));
s.push(P(
    "El juego usa IM 2 con una tabla de 257 bytes ($7B) en bank 2 — no-contended, para que el " +
    "registro I nunca apunte a RAM contended (ULA snow en hardware real) — y un vector handler " +
    "fijo en $7B7B. Esto permite tener un handler propio independiente del valor del bus flotante."
));
s.push(bullet("Tabla en zona protegida del banco 5."));
s.push(bullet("Vector inicializado en arranque, EI tras setup completo."));
s.push(bullet("StartupComplete flag protege el handler de ejecutar antes de tiempo (evita race con LD A,I)."));

s.push(H2("6.2 Restricciones del handler IRQ"));
s.push(P("El handler IM 2 NO PUEDE paginar slot 3 (donde vive la pila). Por tanto:"));
s.push(bullet("Todo el código que invoca desde el IRQ debe estar en slot 1 o slot 2 (banco 5 o banco 2)."));
s.push(bullet("Datos del IRQ (tablas de música, scratch) también en slot 1 o 2."));
s.push(bullet("Si necesitas paginar durante el IRQ, usa un alt-stack temporal en slot 1."));

s.push(H2("6.3 Bus flotante y quirks del port"));
s.push(P(
    "chips/zx.h (port SDL2) no implementa el bus flotante en IORQ+M1 (bus = $FF). Esto puede " +
    "afectar a IM 2 si la tabla de vectores no es uniforme. El juego mueve el scratch del BFS " +
    "a low RAM ($5C00) para evitar el bug en builds nativos y mantener el port limpio."
));

// ====== 7. Brújula mágica ======
s.push(H1("7. Brújula mágica: pathfinding sala-a-sala"));
s.push(P(
    "El power-up «brújula mágica» calcula la dirección óptima hacia el objetivo actual " +
    "mediante un BFS reverse (desde la sala destino hacia la actual), respetando los gaps " +
    "físicos entre componentes conectables de cada sala."
));

s.push(H2("7.1 Topología de salas"));
s.push(P("Cada sala se modela como uno o varios componentes conectados internamente. Los gaps en los bordes (N/S/E/W) conectan componentes de salas vecinas:"));
s.push(bullet("N/S: 4 chars de ancho."));
s.push(bullet("W/E (duales): 3 chars arriba + 5 chars abajo."));
s.push(bullet("Tabla RoomCompGapsTable: 256 punteros DEFW autogenerados por tools/build_screen_gaps.py."));
s.push(bullet("Cada registro: { side_comp (4 bits side + 4 bits comp), coord }."));

s.push(H2("7.2 BFS amortizado"));
s.push(buildTable(
    ["Aspecto",         "Valor"],
    [
        ["Estado",         "Tupla (sid, comp_local) por nodo."],
        ["Frontera",       "Cola circular en RAM baja."],
        ["Resumen",        "Cada frame ejecuta 8 iteraciones; estado persiste entre frames."],
        ["Cache",          "LastMagicCompassDrawn = (PathDir, Permanent) — redraw solo en cambio."],
        ["Invalidación",   "Al cambiar de sala (CheckScreenTransition) y al avanzar de hito."],
        ["Tracking entry", "LastEntrySide + LastEntryCoord para empezar el BFS con el comp correcto."],
    ],
    [2800, 6560],
));

s.push(H2("7.3 HUD"));
s.push(P("El HUD de la brújula consta de 4 chars (32 píxeles) con 8 flechas + una «X»:"));
s.push(bullet("Verde: el objetivo está más cerca que en el frame anterior."));
s.push(bullet("Rojo: te alejas."));
s.push(bullet("X blanca: estás en la sala destino."));
s.push(bullet("Override blanco bright durante el «tick AY heartbeat» (jingle de la brújula)."));

// ====== 8. Editor de niveles e infraestructura ======
s.push(H1("8. Infraestructura: editores y herramientas"));

s.push(H2("8.1 Editores HTML"));
s.push(buildTable(
    ["Editor",            "Función"],
    [
        ["BG_editor.html",     "Diseño de sprites de fondo. Edita píxeles + paper/ink + propaga a sprites hijos (slice)."],
        ["level_editor.html",  "Coloca sprites BG en pantallas, gestiona conexiones de salas, exporta a screen_rooms.asm."],
        ["sprite_generator.html", "PNG → pixel art Spectrum (8 colores). Bridge BroadcastChannel al BG editor."],
        ["sfx_editor.html",    "Diseña tablas SFX_* declarativas, exporta JSON, valida con el intérprete."],
        ["music_converter.html", "MIDI → driver de música (tabla de notas + duraciones)."],
        ["hud_viewer.html",    "Inspección visual del HUD (clock, llaves, brújula)."],
        ["memory_map_template.html", "Visor live del mapa RAM/banks (regiones + heat + dead code + call graph)."],
        ["map_grid_viewer.html", "Visión global del mapa del juego como rejilla."],
    ],
    [3000, 6360],
));

s.push(H2("8.2 Workflow de sprites BG"));
s.push(P("4 capas de almacenamiento, con reglas estrictas de sincronización:"));
s.push(numbered("BG IndexedDB (en el navegador): primario para el BG_editor."));
s.push(numbered("Level IndexedDB: primario para level_editor."));
s.push(numbered("bg_sprites.json: snapshot en disco (export desde BG_editor)."));
s.push(numbered("bg_gfx*.asm: código generado para el ensamblador (tools/sync_bg_pickups.py)."));
s.push(note(
    "Regla de oro: tras dibujar, «Export All BG» en BG_editor. Antes de abrir level_editor, " +
    "«Load BG Data». Los .bat de build hacen auto-backup de bg_sprites.json para evitar pérdidas."
));

s.push(H2("8.3 Toolchain Python"));
s.push(P("32 scripts en tools/ cubren el pipeline:"));
s.push(buildTable(
    ["Script",                "Propósito"],
    [
        ["build_screen_gaps.py",   "Calcula gaps entre salas a partir de bg_gfx*.asm + screen_rooms.asm."],
        ["build_sfx.py",           "Compila tablas SFX desde JSON → sfx_data.asm."],
        ["sync_bg_pickups.py",     "Sincroniza bg_sprites.json → bg_gfx*.asm (RLE-aware, auto-recompress)."],
        ["compress_bg_rle.py",     "Compresión RLE de sprites BG."],
        ["memory_map.py",          "Análisis RAM/banks: regiones, heat, call graph, move cost, dead code."],
        ["check_slot_overlap.py",  "Valida que no haya overlap entre módulos en slot 1."],
        ["import_*.py",            "Importadores: aseprite/PNG → DEFB Z80 (compass, smoke, death, monster, puff, nasty…)."],
        ["renumber_sprites.py",    "Renumera IDs de sprite sin romper referencias."],
        ["track_player.py",        "Logger para debugging de movimiento."],
    ],
    [2800, 6560],
));

s.push(H2("8.4 Build scripts"));
s.push(bullet("build_and_spectaculator.bat → ensambla + lanza Spectaculator."));
s.push(bullet("build_and_tharkys.bat → ensambla + lanza el port SDL2 nativo."));
s.push(bullet("build_and_zesarux.bat → ensambla + lanza ZEsarUX."));
s.push(P("Todos invocan a sjasmplus con main.asm y producen juego.tap + juego.sna. Antes generan: gaps, RLE, sprites BG."));

// ====== 9. Port SDL2 ======
s.push(H1("9. Port nativo: SDL2 + chips"));
s.push(P(
    "El proyecto incluye un wrapper en port/ que reproduce el juego en escritorio (Win/Mac/Linux) " +
    "usando la librería chips de Andre Weissflog y SDL2."
));
s.push(buildTable(
    ["Aspecto",         "Detalle"],
    [
        ["Lenguaje",       "C99"],
        ["Build",          "CMake (FetchContent de SDL2 + chips)"],
        ["Emu core",       "chips/zx.h (ZX Spectrum 128K, Z80 + AY-3-8912 + ULA)"],
        ["Input",          "SDL2 → mapeo a teclado virtual del chips (QAOP + SPACE + debug keys)"],
        ["Audio",          "Resampleo del AY a 44,1 kHz vía SDL_OpenAudio."],
        ["Vídeo",          "Framebuffer 320×256 (incl. border) escalado vía SDL_Renderer."],
        ["Trampas",        "AY default float = 0 NO silencia (macro _ZX_DEFAULT). Asignar e->zx.ay.mag = 0.0f."],
        ["Bus flotante",   "No implementado en chips → BFS scratch movido a low RAM (resuelto game-side)."],
    ],
    [2400, 6960],
));

// ====== 10. Sistemas notables ======
s.push(H1("10. Sistemas notables"));

s.push(H2("10.1 Cadena de objetivos (milestones)"));
s.push(P(
    "11 hitos, tabla MilestoneTable de pares {tipo, ref}. Tipos: PICKUP (1), TRIGGER (2), " +
    "SPECIAL (3). MilestoneResolveTable mapea cada hito a la coordenada que la brújula resuelve."
));
s.push(bullet("Avance automático en CheckMilestonePickup (al recoger key) y CheckBumpTriggers (al activar puerta)."));
s.push(bullet("Skip libre con tecla M (debug)."));
s.push(bullet("Hito 7 (SPECIAL) avanza desde UpdatePostTrapPause al soltar el cheque del banco."));

s.push(H2("10.2 Trampa de la iglesia"));
s.push(P("Pushback del monstruo a celdas puerta → cutscene → estatua tiembla → puerta cierra → respawn de llave de iglesia."));
s.push(bullet("Phase machine: bit en ENT_FLAGS distingue knockback directo del player vs heredado por billar."));
s.push(bullet("CheckChurchTrap solo dispara con kb directo."));
s.push(bullet("Cutscene freeze: skip de ProcessEnemies/UpdateMonster para evitar conflictos XOR."));

s.push(H2("10.3 Cinemática de la puerta sur"));
s.push(P(
    "Hito 11 (final). El arco se divide en 3 sprites; el part1 actúa como trigger AABB custom. " +
    "Secuencia: WAIT_NASTIES → WALK_TO_ANCHOR → BiClip slide-S off-screen → «The End» → créditos."
));
s.push(bullet("Reside en banco 7 vía thunks en slot 1 (libera 1,3 KB en banco 0)."));
s.push(bullet("Usa alt-stack durante page switches para evitar corromper la pila."));

s.push(H2("10.4 Tumbas persistentes"));
s.push(P("Storage: banco 7 $E000, 200 entradas × 4 B. Helpers en slot 1. DrawPendingTomb in-place tras la animación de muerte."));
s.push(bullet("WriteTombAttrsCyan: bypass del remap día/noche."));
s.push(bullet("RefreshTombAttrsForRoom: sanea CleanAttrMap tras cambio de fase si una entity está encima."));

s.push(H2("10.5 Day/Night cycle"));
s.push(P(
    "DayCycleCount solo avanza al recoger la pieza de llave del día. UpdateGameClock gateado por " +
    "TimeFrozen (0=normal, 1=trampa iglesia con clock parpadeando, 2=muerte player silencioso)."
));

s.push(H2("10.6 Sistema random anti-reroll"));
s.push(P(
    "Cache de pickups aleatorios: 2 entradas (current + previous), 4 B cada una, guarda {slot, rolled}. " +
    "Al re-entrar en una sala con pickup ya tirado: restore exacto. Al consumir: cur.rolled = 0."
));

// ====== 11. Gotchas y patrones ======
s.push(H1("11. Gotchas y patrones del código"));

s.push(H2("11.1 sjasmplus: símbolos silenciosos"));
s.push(P(
    "sjasmplus resuelve símbolos indefinidos como 0 sin warning. Si una EQU está mal escrita o " +
    "falta un INCLUDE, el código se ensambla pero ejecuta NOPs/JR a $0000. Verificar siempre " +
    "los bytes en el .lst si una rutina «no hace nada»."
));

s.push(H2("11.2 ORG retrograde"));
s.push(P(
    "sjasmplus permite ORG hacia atrás silenciosamente. Las tablas grandes en slot 1 deben ir " +
    "ANTES del INCLUDE con ORG explícito. Caso real: RoomCompGapsTable vs music_irq (entonces ORG $7A00; hoy ASSERT $ <= $7B7B)."
));

s.push(H2("11.3 LDIR corrompe BC"));
s.push(P(
    "Las rutinas Draw/Load helpers ejecutan LDIR internamente, destruyendo BC. Si pasas args en " +
    "B/C antes del CALL: PUSH/POP. Caso real: invariante de animación HAND_OPEN_IN."
));

s.push(H2("11.4 Stack en slot 3"));
s.push(P(
    "PUSH/POP a través de page switches corrompe args. Solución: rutinas críticas self-contained " +
    "en banco 2 (siempre visible) sin paging."
));

s.push(H2("11.5 Symbols locales en sjasmplus"));
s.push(P(
    "Las etiquetas .foo están scoped al último global. Insertar helpers globales entre handlers " +
    "locales rompe el dispatcher. Cuidado al reordenar."
));

s.push(H2("11.6 IFF race fix"));
s.push(P(
    "LD A,I tiene race condition con IRQ que puede colgar el juego en arranque. Reemplazado por " +
    "flag StartupComplete en bloques DI/EI."
));

s.push(H2("11.7 chips _ZX_DEFAULT trap"));
s.push(P(
    "En el port SDL2: .ay_volume = 0.0f NO silencia el AY (la macro mapea 0 → default). " +
    "Escribir e->zx.ay.mag = 0.0f tras zx_init."
));

// ====== 12. Estructura de archivos ======
s.push(H1("12. Estructura del repositorio"));
s.push(mono(
    "NUEVO_JUEGO/\n" +
    " ├ code/             48 archivos .asm (motor, lógica, datos, drivers)\n" +
    " │  ├ main.asm        Punto de entrada (banco 5, $6000)\n" +
    " │  ├ constants.asm   EQUs globales\n" +
    " │  ├ variables.asm   Vars en banco 2 (slot 2)\n" +
    " │  ├ variables_lo.asm Vars en low RAM ($5D00+)\n" +
    " │  ├ logic_game.asm  Update + draw + AI por entidad\n" +
    " │  ├ music_irq.asm   Driver de música (slot 1)\n" +
    " │  ├ sfx_*.asm       Sistema SFX\n" +
    " │  ├ bg_gfx*.asm     Sprites BG (bancos 3/4/7)\n" +
    " │  ├ screen_rooms.asm Datos de pantallas (banco 1)\n" +
    " │  ├ magic_compass.asm Pathfinding BFS\n" +
    " │  ├ milestones.asm  Cadena de objetivos\n" +
    " │  └ … (cutscenes, monstruos, nasties, tumbas, …)\n" +
    " │\n" +
    " ├ tools/             32 scripts Python + 8 editores HTML\n" +
    " ├ docs/              Documentación (game_design, magic_compass, RAM_MAP, …)\n" +
    " ├ port/              Wrapper SDL2 + chips (build CMake)\n" +
    " ├ juego.sna          Snapshot de debug\n" +
    " └ juego.tap          Cinta para Spectrum real / emus"
));

// ====== 13. Métricas ======
s.push(H1("13. Métricas del build actual"));
s.push(buildTable(
    ["Métrica",            "Valor"],
    [
        ["Archivos .asm",       "48"],
        ["Scripts Python",      "32"],
        ["Editores HTML",       "8"],
        ["Total ROM/RAM ocupada (bancos 0,1,3,4,6,7)", "~82 KB"],
        ["Libre disponible en bancos",             "~16 KB distribuidos"],
        ["Slot 1 libre (banco 5)",                 "~660 B"],
        ["Banco más lleno",     "Banco 0: 96,6 % (campo crítico)"],
        ["IRQ rate",            "25 Hz (música) / 50 Hz (game loop)"],
        ["Game loop budget",    "~280 000 T-states / frame @ 3,5 MHz"],
        ["Entidades simultáneas", "16 slots (player + 11 nasties + 3 monsters + 1 death)"],
        ["Salas mapeadas",      "256 (cap del sistema, ~70 % usadas)"],
        ["Hitos en cadena",     "11"],
    ],
    [4400, 4960],
));

// ====== 14. Referencias internas ======
s.push(H1("14. Documentación interna y referencias"));
s.push(P("Documentación adicional en docs/:"));
s.push(bullet("docs/game_design.md — Diseño completo (historia, mecánicas, progresión)."));
s.push(bullet("docs/magic_compass.md — Documentación canónica del sistema de brújula BFS."));
s.push(bullet("docs/level_editor_manual.md — Manual del editor de niveles."));
s.push(bullet("docs/MEMORY_MAP.md — Doc del tool memory_map.py (call graph, heat, dead code)."));
s.push(bullet("docs/RAM_OPTIMIZATION_PLAN.md — Plan de optimización de RAM en 4 fases."));
s.push(bullet("docs/SPRITE_WORKFLOW.md — Workflow de 4 capas para sprites BG."));
s.push(bullet("docs/bank_cutscene.md y bank_cutscene_handoff.md — Cinemática de banco 7."));
s.push(bullet("code/asm_index.md — Índice de rutinas con líneas y archivos."));

s.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 600 },
    children: [new TextRun({ text: "— Fin del manual técnico —", italics: true, color: "888888" })],
}));

// -------------------------- Document ---------------------------------------
const doc = new Document({
    creator: "Tharkys the Knight",
    title: "Tharkys the Knight — Manual Técnico",
    description: "Documento técnico: arquitectura, motor y herramientas",
    features: { updateFields: true }, // Word pedirá actualizar el TOC al abrir
    styles: {
        default: { document: { run: { font: "Arial", size: 22 } } },
        paragraphStyles: [
            { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
              run: { size: 36, bold: true, font: "Arial", color: "1F3A5F" },
              paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
            { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
              run: { size: 28, bold: true, font: "Arial", color: "2E5C8A" },
              paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 } },
            { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
              run: { size: 24, bold: true, font: "Arial", color: "555555" },
              paragraph: { spacing: { before: 180, after: 100 }, outlineLevel: 2 } },
        ],
    },
    numbering: {
        config: [
            { reference: "bullets",
              levels: [
                  { level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
                    style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
              ] },
            { reference: "numbers",
              levels: [
                  { level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
                    style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
              ] },
        ],
    },
    sections: [{
        properties: {
            page: {
                size: { width: 12240, height: 15840 },
                margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
            },
        },
        headers: {
            default: new Header({
                children: [new Paragraph({
                    alignment: AlignmentType.RIGHT,
                    border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "1F3A5F", space: 4 } },
                    children: [new TextRun({ text: "Tharkys the Knight — Manual Técnico", italics: true, color: "555555", size: 18 })],
                })],
            }),
        },
        footers: {
            default: new Footer({
                children: [new Paragraph({
                    alignment: AlignmentType.CENTER,
                    children: [
                        new TextRun({ text: "— ", color: "777777" }),
                        new TextRun({ children: [PageNumber.CURRENT], color: "777777" }),
                        new TextRun({ text: " / ", color: "777777" }),
                        new TextRun({ children: [PageNumber.TOTAL_PAGES], color: "777777" }),
                        new TextRun({ text: " —", color: "777777" }),
                    ],
                })],
            }),
        },
        children: s,
    }],
});

const outPath = path.resolve(__dirname, '..', 'docs', 'Tharkys_the_Knight_TechManual.docx');
Packer.toBuffer(doc).then(buffer => {
    fs.writeFileSync(outPath, buffer);
    console.log("OK:", outPath, "size:", buffer.length, "B");
});
