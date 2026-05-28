#!/usr/bin/env python3
"""
build_standalone_story.py
=========================
Genera code/standalone_story_data.asm con las 6 paginas EN + 6 paginas ES
del wrapper SDL (port/src/main.c STORY_PAGES_*). Convierte UTF-8 -> codepoints
custom 0x80-0x8B (acentos), centra verticalmente, emite DEFB con marcadores:

  - Cada linea: DEFB row, "texto", 0
  - $FE = fin de pagina (wait input, clear, next)
  - $FF = fin de historia

Idempotente: solo reescribe si el output cambia.

Uso:
    python tools/build_standalone_story.py
"""

from __future__ import annotations

from pathlib import Path
import sys

REPO = Path(__file__).resolve().parent.parent
OUT  = REPO / "code" / "standalone_story_data.asm"

# UTF-8 -> codepoint custom (ver code/standalone_main_b4.asm ExtFontGlyphs)
UTF8_MAP = {
    "á": 0x80, "é": 0x81, "í": 0x82, "ó": 0x83, "ú": 0x84,
    "Á": 0x85, "É": 0x86, "Í": 0x87, "Ó": 0x88, "Ú": 0x89,
    "ñ": 0x8A, "Ñ": 0x8B,
}

SCREEN_ROWS = 24
MAX_LINE_CHARS = 32

STORY_ES = [
    [
        "Sir Tharkys es un tipo",
        "con mala suerte.",
        "",
        "Durante mucho tiempo",
        "extendió cheques que su",
        "cuerpo no podía pagar.",
        "Su escudero le ha abandonado.",
        " Le ha abandonado",
        "hasta su caballo...",
    ],
    [
        "No le queda más remedio",
        "que ir allá donde",
        "se requiera una espada,",
        "esperando algunas migajas",
        "a cambio de sus servicios.",
    ],
    [
        "Le llegaron noticias de un ",
        "pueblo que vive atemorizado",
        " por unos monstruos ",
        "de origen desconocido.",
        "",
        "A quien les liberara de ",
        "ellos, prometían entregar ",
        "una jugosa recompensa ",
        "que sacaría a Tharkys ",
        "de sus apuros económicos.",
    ],
    [
        "Tras hablar con el",
        "alcalde, éste le entrega",
        "una brújula rota que",
        "le indicará vagamente",
        "la ubicación de sus",
        "objetivos. También dice",
        "que tenía un mapa en",
        "una servilleta (!?!),",
        "pero se lo llevó el aire (!??!).",
    ],
    [
        "Le desea buena suerte",
        "y, como despedida, le informa",
        "de que han cerrado la puerta",
        "de la ciudad para que no pueda",
        "ceder a la tentación de huir.",
    ],
    [
        "Ganas le dan, tras ver",
        "cómo está todo lleno",
        "de bichos y, sobre todo,",
        "tras conocer que muchos otros",
        " caballeros han caído antes",
        " en el intento...",
    ],
]

STORY_EN = [
    [
        "Sir Tharkys is a man",
        "with bad luck.",
        "",
        "For a long time he wrote",
        "checks his body could not",
        "cash. His squire has",
        "abandoned him.",
        "Even his horse has",
        "abandoned him...",
    ],
    [
        "He has no choice but",
        "to go wherever a sword",
        "is needed, hoping for",
        "a few scraps in return",
        "for his services.",
    ],
    [
        "Word reached him of a",
        "village living in terror",
        "of monsters of unknown",
        "origin. ",
        "",
        "To whoever freed them,",
        " they promised a",
        "handsome reward that",
        "would lift the knight out",
        "of his financial troubles.",
    ],
    [
        "After speaking with the",
        "mayor, the latter hands",
        "him a broken compass",
        "that will vaguely show",
        "the location of his",
        "targets. He also mentions",
        "a map on a napkin (!?!),",
        "but the wind blew it",
        "away (!!??!!).",
    ],
    [
        "He wishes him good luck",
        "and, as a parting note,",
        "informs him they have",
        "locked the town gate so",
        "he cannot give in to the",
        "temptation of fleeing.",
    ],
    [
        "He feels like doing just",
        "that, after seeing the",
        "place crawling with",
        "creatures and, above all,",
        "after learning that many",
        "knights have already",
        "fallen trying...",
    ],
]


def line_to_defb(line: str) -> str:
    """Convierte una linea UTF-8 a DEFB con codepoints custom."""
    if len(line) > MAX_LINE_CHARS:
        sys.exit(f"build_standalone_story: line >32 chars: {line!r}")
    parts = []
    run = ""
    for ch in line:
        cp = UTF8_MAP.get(ch)
        if cp is not None:
            if run:
                parts.append(f'"{run}"')
                run = ""
            parts.append(f"${cp:02X}")
        else:
            if ch == '"' or ch == "\\":
                # escape para sjasmplus
                if run:
                    parts.append(f'"{run}"')
                    run = ""
                parts.append(f"${ord(ch):02X}")
            else:
                run += ch
    if run:
        parts.append(f'"{run}"')
    parts.append("0")
    return ", ".join(parts)


def emit_story(label: str, pages: list[list[str]]) -> list[str]:
    out = [f"{label}:"]
    for i, page in enumerate(pages):
        n = len(page)
        # Espaciado: 1 fila vacia entre cada linea. Altura total = n*2-1 filas.
        height = n * 2 - 1
        if height > SCREEN_ROWS:
            sys.exit(f"build_standalone_story: page {i} needs {height} rows, max {SCREEN_ROWS}")
        start_row = (SCREEN_ROWS - height) // 2
        end_row = start_row + (n - 1) * 2
        out.append(f"    ; --- Page {i + 1} ({n} lines, rows {start_row}..{end_row} step 2) ---")
        for j, line in enumerate(page):
            out.append(f"    DEFB {start_row + j * 2}, {line_to_defb(line)}")
        out.append(f"    DEFB $FE                ; end of page {i + 1}")
    out.append(f"    DEFB $FF                ; end of {label}")
    return out


def main() -> int:
    lines: list[str] = [
        "; ==============================================================================",
        "; standalone_story_data.asm - 6 paginas EN + 6 paginas ES (F4)",
        "; ==============================================================================",
        "; Auto-generado por tools/build_standalone_story.py. NO editar a mano: cambios",
        "; perderan en el siguiente build. Para modificar el texto, editar las listas",
        "; STORY_ES / STORY_EN en el script Python y volver a ejecutarlo.",
        ";",
        "; Formato consumido por StandaloneStoryShow:",
        ";   Cada pagina: secuencia de {row(1B), char*, 0}, terminada por $FE",
        ";   Historia completa terminada por $FF",
        ";",
        "; Codepoints 0x80-0x8B = a-acute, e-acute, i-acute, o-acute, u-acute,",
        ";                       A-acute, E-acute, I-acute, O-acute, U-acute, n-tilde, N-tilde",
        "; ==============================================================================",
        "",
    ]
    lines += emit_story("StoryPagesEN", STORY_EN)
    lines.append("")
    lines += emit_story("StoryPagesES", STORY_ES)
    lines.append("")
    content = "\n".join(lines) + "\n"

    if OUT.is_file() and OUT.read_text(encoding="utf-8") == content:
        print(f"build_standalone_story: {OUT.name} up to date ({OUT.stat().st_size} B)")
        return 0
    OUT.write_text(content, encoding="utf-8")
    print(f"build_standalone_story: wrote {OUT.name} ({OUT.stat().st_size} B)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
