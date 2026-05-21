#!/usr/bin/env python3
"""
rerender_types_sheet.py — Re-pinta tools/minimap_types_sheet.svg leyendo
el JSON actual sin tocar nada mas. Si un tipo tiene user_sprite, lo muestra
en amarillo bright con marco cian; si no, en gris.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from classify_minimap_types import render_sheet


def main():
    root = HERE.parent
    with (root / 'code' / 'minimap_types.json').open(encoding='utf-8') as f:
        data = json.load(f)
    render_sheet(data['types'], root / 'tools' / 'minimap_types_sheet.svg')


if __name__ == '__main__':
    main()
