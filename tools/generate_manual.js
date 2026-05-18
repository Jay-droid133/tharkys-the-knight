// Generador del manual del juego "Tharkys the Knight" en formato .docx
const fs = require('fs');
const path = require('path');

const NPM_GLOBAL = process.env.APPDATA + '/npm/node_modules';
const docx = require(NPM_GLOBAL + '/docx');

const {
    Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
    Header, Footer, AlignmentType, PageOrientation, LevelFormat,
    HeadingLevel, BorderStyle, WidthType, ShadingType, PageNumber, PageBreak,
    TableOfContents, TabStopType, TabStopPosition
} = docx;

// --- helpers -----------------------------------------------------------------
const border = { style: BorderStyle.SINGLE, size: 4, color: "888888" };
const borders = { top: border, bottom: border, left: border, right: border };

function P(text, opts = {}) {
    return new Paragraph({
        spacing: { after: 120 },
        ...opts,
        children: [new TextRun({ text, ...(opts.run || {}) })],
    });
}

function H1(text) {
    return new Paragraph({
        heading: HeadingLevel.HEADING_1,
        pageBreakBefore: true,
        children: [new TextRun(text)],
    });
}

function H2(text) {
    return new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(text)] });
}

function H3(text) {
    return new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(text)] });
}

function bullet(text, level = 0) {
    return new Paragraph({
        numbering: { reference: "bullets", level },
        children: [new TextRun(text)],
    });
}

function numbered(text) {
    return new Paragraph({
        numbering: { reference: "numbers", level: 0 },
        children: [new TextRun(text)],
    });
}

function richP(runs, opts = {}) {
    return new Paragraph({
        spacing: { after: 120 },
        ...opts,
        children: runs.map(r => typeof r === 'string' ? new TextRun(r) : new TextRun(r)),
    });
}

// --- tables ------------------------------------------------------------------
function cell(text, opts = {}) {
    const { width, shade, bold, align } = opts;
    return new TableCell({
        borders,
        width: { size: width, type: WidthType.DXA },
        shading: shade ? { fill: shade, type: ShadingType.CLEAR } : undefined,
        margins: { top: 80, bottom: 80, left: 120, right: 120 },
        children: [new Paragraph({
            alignment: align || AlignmentType.LEFT,
            children: [new TextRun({ text, bold: !!bold })],
        })],
    });
}

function buildTable(headers, rows, columnWidths) {
    const total = columnWidths.reduce((a, b) => a + b, 0);
    const headerRow = new TableRow({
        tableHeader: true,
        children: headers.map((h, i) => cell(h, { width: columnWidths[i], shade: "2E5C8A", bold: true })),
    });
    const bodyRows = rows.map((r, ridx) => new TableRow({
        children: r.map((c, i) => cell(c, {
            width: columnWidths[i],
            shade: ridx % 2 === 0 ? "F2F2F2" : "FFFFFF",
        })),
    }));
    return new Table({
        width: { size: total, type: WidthType.DXA },
        columnWidths,
        rows: [headerRow, ...bodyRows],
    });
}

// --- contenido ---------------------------------------------------------------
const CONTENT_W = 9360; // US Letter, márgenes 1"

const sections = [];

// ===== Portada =====
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 2400, after: 240 },
    children: [new TextRun({ text: "THARKYS THE KNIGHT", bold: true, size: 64, color: "1F3A5F" })],
}));
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 1200 },
    children: [new TextRun({ text: "Manual del Jugador", italics: true, size: 36, color: "555555" })],
}));
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 240 },
    children: [new TextRun({ text: "Una aventura para ZX Spectrum 128K", size: 28 })],
}));
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 4000 },
    children: [new TextRun({ text: "(compatible con Spectrum +2 / +3 y emuladores)", size: 22, color: "777777" })],
}));
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "« No basta con tener una espada. ", italics: true, size: 24 })],
}));
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Hay que saber dónde clavarla. »", italics: true, size: 24 })],
}));

// ===== Índice =====
sections.push(new Paragraph({ children: [new PageBreak()] }));
sections.push(H2("Índice"));
sections.push(new TableOfContents("Tabla de contenidos", { hyperlink: true, headingStyleRange: "1-3" }));

// ===== 1. Historia =====
sections.push(H1("1. La historia"));
sections.push(P(
    "En una pequeña ciudad amurallada, los días se repiten como una pesadilla. Tres criaturas " +
    "antiguas se ocultan entre los muros y, cada noche, salen a vagar por las calles vacías. " +
    "Las puertas de la ciudad están selladas y el cementerio, al este, guarda una iglesia " +
    "que podría ser la clave de todo."
));
sections.push(P(
    "Tú eres Tharkys, el último caballero de la guardia. Tu misión es recuperar las piezas " +
    "perdidas de una llave maestra, hacerte con un crucifijo bendecido y encerrar a los tres " +
    "monstruos en la iglesia antes de que la ciudad se desmorone."
));
sections.push(P(
    "Y cuando por fin termines… quizás te queden algunas palabras finales para los habitantes."
));

// ===== 2. Controles =====
sections.push(H1("2. Controles"));
sections.push(P("El juego acepta tres esquemas de control simultáneamente — usa el que prefieras."));

sections.push(H2("2.1 Teclado (QAOP)"));
sections.push(buildTable(
    ["Acción", "Tecla"],
    [
        ["Mover arriba", "Q"],
        ["Mover abajo", "A"],
        ["Mover izquierda", "O"],
        ["Mover derecha", "P"],
        ["Atacar / Espada", "ESPACIO"],
    ],
    [6240, 3120],
));

sections.push(H2("2.2 Joystick Kempston"));
sections.push(P("Joystick conectado al puerto 31 (Kempston). Las 4 direcciones + botón de disparo."));

sections.push(H2("2.3 Sinclair Joystick 1"));
sections.push(buildTable(
    ["Acción", "Tecla"],
    [
        ["Izquierda", "1"],
        ["Derecha", "2"],
        ["Abajo", "3"],
        ["Arriba", "4"],
        ["Disparo", "5"],
    ],
    [6240, 3120],
));

sections.push(H2("2.4 Teclas de depuración"));
sections.push(P(
    "Estas teclas existen para facilitar pruebas durante el desarrollo. Pueden estar " +
    "desactivadas en la versión final."
));
sections.push(buildTable(
    ["Tecla", "Efecto"],
    [
        ["M", "Saltar al siguiente hito (objetivo)."],
        ["K", "Otorgar todas las llaves."],
        ["N", "Activar / desactivar modo «noclip» (atravesar paredes). Indicador NC en HUD."],
    ],
    [1800, 7560],
));

// ===== 3. Pantalla =====
sections.push(H1("3. La pantalla del juego"));
sections.push(P(
    "La acción se desarrolla en pantallas fijas conectadas (flick-screen, como en Sabre Wulf). " +
    "Al cruzar un borde, la pantalla siguiente carga al instante y Tharkys aparece en el lado opuesto."
));

sections.push(H2("3.1 Zonas del mundo"));
sections.push(buildTable(
    ["Zona", "Descripción"],
    [
        ["Centro de la ciudad", "Calles, plaza con reloj y edificios principales (ayuntamiento, banco)."],
        ["Bosque (oeste)", "Arboleda con caminos sinuosos; aquí vive la primera llave."],
        ["Ruinas", "Antiguas piedras semienterradas donde acecha la segunda llave."],
        ["Cementerio (este)", "Tras la verja del cementerio se alza la iglesia. Aquí encerrarás a los monstruos."],
        ["Puerta sur", "La gran puerta del sur, sellada hasta el desenlace."],
    ],
    [2800, 6560],
));

sections.push(H2("3.2 HUD (interfaz)"));
sections.push(buildTable(
    ["Elemento", "Función"],
    [
        ["Reloj central", "Reloj analógico con la hora del ciclo día/noche."],
        ["Barra izquierda del reloj", "Salud (HP). Cambia de color al bajar: verde → azul → amarillo → rojo → magenta."],
        ["Barra derecha del reloj", "Vigor / Stamina. Determina el modo de ataque de la espada."],
        ["Ranuras de llaves (×6)", "Llaves recogidas (bosque, ruinas, cementerio, reloj, iglesia, ciudad)."],
        ["Crucifijo", "Aparece cuando lo obtienes en la iglesia."],
        ["Indicador DAY", "DAY 1, 2, 3… Cuenta los días que llevas en la ciudad."],
        ["Brújula mágica", "Flecha que apunta al objetivo actual; cambia de color según te acerques."],
        ["Vidas", "Vidas restantes (corazones)."],
    ],
    [3000, 6360],
));

// ===== 4. Ciclo día/noche =====
sections.push(H1("4. El ciclo día/noche"));
sections.push(P(
    "El tiempo avanza solo. La ciudad cambia de habitantes según la fase del día: " +
    "cada fase tiene depredadores distintos (los «nasties»), y solo de noche profunda salen los monstruos."
));
sections.push(buildTable(
    ["Fase", "Hora aprox.", "Depredadores", "Monstruos"],
    [
        ["DY — Día",            "07:00 – 17:00", "Diurnos (águila, araña, cabra, serpiente)", "—"],
        ["C1 — Crepúsculo temprano", "17:00 – 18:30", "Diurnos", "—"],
        ["C2 — Crepúsculo tardío",   "18:30 – 20:00", "Crepusculares (rata, murciélago, escorpión, gato rabioso)", "—"],
        ["N1 — Noche temprana",      "20:00 – 22:00", "Crepusculares", "—"],
        ["N2 — Noche profunda",      "22:00 – 04:00", "Ninguno (las campanas los ahuyentan)", "Los 3 monstruos despiertan"],
        ["A1 — Amanecer temprano",   "04:00 – 05:30", "Pausa", "Huyen"],
        ["A2 — Amanecer tardío",     "05:30 – 07:00", "Diurnos regresan", "—"],
    ],
    [1500, 1700, 3800, 2360],
));
sections.push(P("Las campanas de la iglesia anuncian el cambio de fase y asustan a las criaturas presentes."));

sections.push(H2("4.1 Repetir el día («efecto Día de la Marmota»)"));
sections.push(P(
    "El día solo avanza si recoges la pieza de llave de ese día. Si no lo haces, el día se " +
    "repite: los habitantes despiertan en las mismas casillas y el portador vuelve a aparecer " +
    "con la misma pieza. ¡No hay prisa por arriesgar, pero tampoco se puede holgazanear!"
));

// ===== 5. Salud y vigor =====
sections.push(H1("5. Salud y vigor"));
sections.push(H2("5.1 Salud (HP)"));
sections.push(P(
    "Tharkys pierde salud al ser tocado por enemigos. Cuando llega a cero, pierde una vida y " +
    "vuelve a aparecer en el punto de respawn de la sala tras una breve cuenta atrás."
));
sections.push(P("Durante el respawn:"));
sections.push(bullet("Suenan 3 pitidos cortos y un «GO!» largo."));
sections.push(bullet("Tras el «GO!» se otorga un breve período de gracia (~1 s) durante el cual eres invulnerable."));
sections.push(bullet("Al terminar la gracia, el control vuelve a ti."));

sections.push(H2("5.2 Vigor (Stamina)"));
sections.push(P("El vigor determina cómo se comporta la espada:"));
sections.push(buildTable(
    ["Nivel de vigor", "Modo de espada"],
    [
        ["Máximo (recién comido / poción)", "Espada continua (puedes atacar todo el tiempo que mantengas fuego)."],
        ["Medio", "Estocada fija (un golpe por pulsación)."],
        ["Bajo", "Estocada con cooldown corto."],
        ["Vacío", "Cooldown largo. Te conviene descansar."],
    ],
    [4000, 5360],
));

sections.push(H2("5.3 Recuperación"));
sections.push(bullet("Pozos: repartidos por la ciudad; recargan salud y vigor."));
sections.push(bullet("Pociones: las dejan caer ocasionalmente los enemigos derrotados."));
sections.push(bullet("Vida extra (corazón): aparece raramente; suma una vida al contador."));

// ===== 6. Objetos =====
sections.push(H1("6. Objetos y llaves"));
sections.push(P("Existen 6 llaves principales y sus 6 cerraduras correspondientes, además de objetos especiales:"));
sections.push(buildTable(
    ["Llave", "Encuentro", "Abre"],
    [
        ["Llave del bosque",     "Oculta en el bosque oeste",                    "Verja del bosque"],
        ["Llave de las ruinas",  "Entre las piedras del este",                   "Cerradura de las ruinas"],
        ["Llave del cementerio", "Tras superar las ruinas",                      "Verja del cementerio"],
        ["Llave del reloj",      "En la zona del reloj de la plaza",             "Puerta del campanario"],
        ["Llave de la iglesia",  "Dentro del ayuntamiento (dinámica)",           "Puerta de la iglesia"],
        ["Llave de la ciudad",   "Cae tras la cinemática del banco (dinámica)",  "Gran puerta sur"],
    ],
    [2400, 3960, 3000],
));
sections.push(P("Otros objetos:"));
sections.push(bullet("Crucifijo: se obtiene al entrar en la iglesia con la llave de la iglesia. Repele a los monstruos."));
sections.push(bullet("Cheque del banco: pieza intermedia que aparece tras la cinemática de la iglesia."));
sections.push(bullet("Setas: ¡cuidado! Inhabilitan tu espada durante un rato (no atacarás aunque pulses fuego)."));
sections.push(bullet("Tumbas: marcan los lugares donde Tharkys ha muerto. Decorativas, pero no se borran."));

// ===== 7. Enemigos =====
sections.push(H1("7. Enemigos"));
sections.push(H2("7.1 Nasties (depredadores)"));
sections.push(P(
    "Los nasties son pequeñas criaturas que pueblan la ciudad por turnos según la hora. " +
    "Su agresividad escala con el «ciclo de día» (cuantos más días llevas, peor se ponen)."
));
sections.push(buildTable(
    ["Ciclo", "Tipo de ataque", "Velocidad", "Ejemplos"],
    [
        ["1", "Aéreo: se lanzan en picado cuando estás en su fila", "2 px/frame", "Águila / Murciélago"],
        ["2", "+ Terrestre: brincan desde abajo si te alinean en columna", "3 px/frame", "Serpiente / Escorpión"],
        ["3", "+ Horizontal: cargan en línea recta", "4 px/frame", "Cabra / Gato rabioso"],
    ],
    [1000, 4500, 1800, 2060],
));

sections.push(H3("Comportamiento «asustado»"));
sections.push(P(
    "Las campanas y el amanecer asustan a nasties y monstruos por igual: se quedan paralizados " +
    "unos segundos mirando a un lado y otro, luego huyen hacia el borde más cercano de la pantalla."
));

sections.push(H3("El portador blanco"));
sections.push(P(
    "Cada día, un nasty BLANCO especial sigue una ruta fija por la ciudad llevando una pieza " +
    "de la llave. Espera en una sala hasta que entras, y se mueve a la siguiente. Si te alejas, " +
    "te espera. Al caer la noche profunda, suelta la pieza donde esté y huye."
));
sections.push(buildTable(
    ["Pieza", "Forma diurna", "Forma crepuscular"],
    [
        ["Pieza 1", "Águila blanca", "Murciélago blanco"],
        ["Pieza 2", "Cabra blanca",  "Gato blanco"],
        ["Pieza 3", "Serpiente blanca", "Rata blanca"],
    ],
    [2000, 3680, 3680],
));

sections.push(H2("7.2 Monstruos"));
sections.push(P(
    "Hay tres monstruos antiguos en la ciudad. Solo aparecen en N2 (noche profunda). Son " +
    "grandes, lentos y peligrosos. No puedes matarlos: tienes que ENCERRARLOS en la iglesia."
));
sections.push(P("Con el crucifijo en mano, los monstruos huyen de ti. Se vuelven «ganado» que puedes guiar a base de empujones y golpes de espada."));

sections.push(H2("7.3 Muerte (Death entity)"));
sections.push(P(
    "Si tardas demasiado, una figura encapuchada empieza a perseguirte. Es lenta pero implacable, " +
    "y puede atravesar paredes si se queda atascada (modo «fantasma» durante 15 s). " +
    "Aparece lejos de ti y se acerca con paciencia. Un toque, y es muerte segura."
));

// ===== 8. Cadena de objetivos =====
sections.push(H1("8. Cadena de objetivos"));
sections.push(P(
    "La brújula mágica te guía siempre al hito actual. La cadena tiene 11 etapas:"
));
sections.push(buildTable(
    ["#", "Objetivo", "Cómo se completa"],
    [
        ["1",  "Llave del bosque",          "Recogerla en el bosque oeste."],
        ["2",  "Llave de las ruinas",       "Recogerla en las ruinas."],
        ["3",  "Llave del cementerio",      "Recogerla más allá de las ruinas."],
        ["4",  "Llave del reloj",           "Recogerla cerca del reloj de la plaza."],
        ["5",  "Puerta del ayuntamiento",   "Activar el trigger de la puerta del ayuntamiento."],
        ["6",  "Llave de la iglesia",       "Recogerla dentro del ayuntamiento."],
        ["7",  "Encerrar los monstruos",    "Empujar a los 3 monstruos al interior de la iglesia."],
        ["8",  "El cheque del banco",       "Recogerlo tras la cinemática de la iglesia."],
        ["9",  "Cinemática del banco",      "Disparar el trigger del banco."],
        ["10", "Llave de la ciudad",        "La suelta la cinemática del banco."],
        ["11", "La gran puerta sur",        "Cruzar la puerta sur → cinemática final."],
    ],
    [600, 3500, 5260],
));

// ===== 9. La iglesia =====
sections.push(H1("9. La iglesia y los monstruos"));
sections.push(P(
    "Con el crucifijo, los monstruos te evitan. El crucifijo además funciona como brújula:"
));
sections.push(bullet("Tenue: los monstruos están lejos."));
sections.push(bullet("Medio: te acercas."));
sections.push(bullet("Brillante / parpadeo: sala adyacente."));
sections.push(bullet("Parpadeo rápido: en la misma sala que tú."));

sections.push(H2("9.1 Empujar monstruos a la iglesia"));
sections.push(numbered("Abre la puerta de la iglesia golpeándola con tu espada. Se queda abierta unos segundos."));
sections.push(numbered("Empuja al monstruo (con golpes/cuerpo) por la puerta antes de que se cierre."));
sections.push(numbered("Al entrar un monstruo: puerta y ventanas destellan en BLANCO, y la puerta se cierra."));
sections.push(numbered("Repite con el siguiente. Si tienes habilidad, puedes intentar encerrar a varios a la vez."));
sections.push(numbered("Al entrar el tercero: destello BLANCO + ROJO. ¡Los tres monstruos quedan encerrados!"));

sections.push(H2("9.2 La trampa de la iglesia"));
sections.push(P(
    "Cuidado: si un monstruo te golpea en una zona concreta cerca de la iglesia, las puertas " +
    "se cierran tras de ti y la estatua tiembla. Esto reinicia la llave de la iglesia. Tendrás " +
    "que volver al ayuntamiento."
));

// ===== 10. Sistemas avanzados =====
sections.push(H1("10. Detalles avanzados"));

sections.push(H2("10.1 La brújula mágica"));
sections.push(P(
    "En el HUD aparece una brújula con 8 direcciones (N, NE, E, SE, S, SW, W, NW) más una «X». " +
    "Sus colores:"
));
sections.push(bullet("Verde: el objetivo está más cerca de lo que estaba."));
sections.push(bullet("Rojo: te estás alejando."));
sections.push(bullet("X blanca: estás en la sala correcta."));
sections.push(P(
    "La brújula se calcula dinámicamente con un BFS sala-a-sala, así que respeta los caminos " +
    "reales del mundo (no apunta a través de paredes)."
));

sections.push(H2("10.2 Tumbas"));
sections.push(P(
    "Cada vez que mueres, queda una tumba en el lugar donde caíste. No bloquean el paso, " +
    "pero te recuerdan tus errores. En la pantalla de «Game Over» verás tu tumba a tamaño doble " +
    "presidiendo el plano."
));

sections.push(H2("10.3 Freeze de monstruos"));
sections.push(P(
    "Si Tharkys muere mientras hay monstruos cerca, estos se quedan paralizados mirando el cadáver. " +
    "Si estaban a menos de 16 píxeles, retroceden 16 píxeles. Quedan inmóviles hasta el primer " +
    "tañido de campana del próximo amanecer urbano."
));

sections.push(H2("10.4 Cache de pickups aleatorios"));
sections.push(P(
    "Las recompensas aleatorias (pociones, vidas) tienen un sistema anti-repetición: " +
    "el juego recuerda qué te tocó en las dos últimas salas. Si vuelves rápido a una sala que ya " +
    "tenía un pickup, encontrarás el mismo (no se «rerollea» en tu favor)."
));

// ===== 11. Consejos =====
sections.push(H1("11. Consejos del veterano"));
sections.push(bullet("Aprende las rutas de los portadores blancos: si te quedas en su sala objetivo, vendrá a ti."));
sections.push(bullet("Las campanas son tu aliado: en N2 los nasties desaparecen y solo hay monstruos. Es el mejor momento para explorar el cementerio."));
sections.push(bullet("Si tienes el vigor bajo, evita combates: la espada queda con cooldown largo y serás carne fácil."));
sections.push(bullet("Una seta NO mata, pero te deja sin espada justo cuando más la necesitas. Recónocelas a distancia."));
sections.push(bullet("La «Muerte» encapuchada es lenta, pero si te atasca contra una pared, atraviesa muros durante 15 segundos. Mantente en movimiento."));
sections.push(bullet("Para encerrar los 3 monstruos en una sola noche, aprende a agruparlos en un pasillo y golpear puerta + cuerpo."));
sections.push(bullet("Visita los pozos antes de noches importantes. El vigor lleno te da espada continua."));

// ===== 12. Créditos =====
sections.push(H1("12. Créditos"));
sections.push(P("«Tharkys the Knight» — un juego para ZX Spectrum 128K."));
sections.push(P("Diseño, programación, gráficos, música y SFX: el autor."));
sections.push(P(
    "Música compuesta para el chip AY-3-8912. Driver de música y SFX a 25 Hz, mezclando " +
    "canales A, B y C para temas y efectos sonoros simultáneos."
));
sections.push(P(
    "Inspiración: Sabre Wulf, Atic Atac, Cobra's Arc y, por supuesto, la edad de oro del Speccy."
));
sections.push(P({ run: { italics: true, color: "777777" }, run: { italics: true } }, ));

sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 600 },
    children: [new TextRun({ text: "« Cuando todo termine, mira a la ciudad. ", italics: true })],
}));
sections.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: "Levanta la mano. Y diles lo que piensas. »", italics: true })],
}));

// --- Documento ---------------------------------------------------------------
const doc = new Document({
    creator: "Tharkys the Knight",
    title: "Tharkys the Knight — Manual del Jugador",
    description: "Manual del juego Tharkys the Knight para ZX Spectrum 128K",
    styles: {
        default: { document: { run: { font: "Arial", size: 22 } } },
        paragraphStyles: [
            {
                id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
                run: { size: 36, bold: true, font: "Arial", color: "1F3A5F" },
                paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 },
            },
            {
                id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
                run: { size: 28, bold: true, font: "Arial", color: "2E5C8A" },
                paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 },
            },
            {
                id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
                run: { size: 24, bold: true, font: "Arial", color: "555555" },
                paragraph: { spacing: { before: 180, after: 100 }, outlineLevel: 2 },
            },
        ],
    },
    numbering: {
        config: [
            {
                reference: "bullets",
                levels: [
                    { level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
                      style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
                    { level: 1, format: LevelFormat.BULLET, text: "◦", alignment: AlignmentType.LEFT,
                      style: { paragraph: { indent: { left: 1440, hanging: 360 } } } },
                ],
            },
            {
                reference: "numbers",
                levels: [
                    { level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
                      style: { paragraph: { indent: { left: 720, hanging: 360 } } } },
                ],
            },
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
                    children: [new TextRun({ text: "Tharkys the Knight — Manual", italics: true, color: "555555", size: 18 })],
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
                        new TextRun({ text: " —", color: "777777" }),
                    ],
                })],
            }),
        },
        children: sections,
    }],
});

const outPath = path.resolve(__dirname, '..', 'docs', 'Tharkys_the_Knight_Manual.docx');
Packer.toBuffer(doc).then(buffer => {
    fs.writeFileSync(outPath, buffer);
    console.log("OK:", outPath);
});
