#!/usr/bin/env python3
"""
build_screen_gaps.py — Phase 1 of monster AI v2

Reads level_data.json + bg_sprites.json, computes per-screen valid border
openings (filtered by MIN_POCKET_SIZE against cul-de-sacs), coalesces
contiguous walkable border cells into single openings, emits
code/screen_gaps.asm to be included in bank 6.

Walkability bitmap is NOT exported here — it's computed at runtime on room
entry from CurrentScreenBuffer (saves ~22 KB of bank space).

Output ASM structures:
  ScreenGapsTable   — 256 pointers (2B each) indexed by screen_id = Y*16+X
  ScreenGaps_NN     — DEFB count, then {side, coord}*count
  ScreenGapsNone    — shared zero-gap record for empty/useless slots

Sides: 0=N (top), 1=S (bottom), 2=W (left), 3=E (right)
Coord = char coord of opening MIDPOINT along the border
  (0..31 for N/S, 0..21 for W/E).
"""

import json
import os
import sys
from pathlib import Path

# ---- Constants (mirror editor / runtime) ------------------------------------

GRID_W = 32          # chars per screen (X)
GRID_H = 22          # chars per screen (Y)
TILE_SIZE = 8        # px per char
MAP_W = 16           # screens wide
MAP_H = 16           # screens tall

MIN_POCKET_SIZE = 20 # cells min in connected region for a gap to be valid

# Monster footprint (in chars). Monster sprite ≈ 16 × 21 px → 2 × 3 chars.
MONSTER_FOOT_W = 2
MONSTER_FOOT_H = 3

# Per-side spawn anchor: where the monster's top-left lands when entering.
# MAI_ENTRY_OFFSET = 16 px = 2 chars. Char-aligned so footprint check is clean.
# CollisionMap cy = pixel_y/8 - BG_Y_OFFSET (=2).
#   N side: pixel Y = SCREEN_MIN_Y(16) + OFFSET(16) = 32 → cy = 32/8 - 2 = 2
#   S side: pixel Y = SCREEN_MAX_Y(168) - OFFSET(16) = 152 → cy = 152/8 - 2 = 17
#   W side: pixel X = OFFSET(16) = 16 → cx = 2
#   E side: pixel X = SCREEN_MAX_X(232) - OFFSET(16) = 216 → cx = 27
# Coord stored in the gap record = position of the variable axis (cx for N/S,
# cy for W/E) of the monster's top-left.
SIDE_N, SIDE_S, SIDE_W, SIDE_E = 0, 1, 2, 3
SIDE_NAMES = {SIDE_N: 'N', SIDE_S: 'S', SIDE_W: 'W', SIDE_E: 'E'}
SIDE_SPAWN_CY = {SIDE_N: 2,  SIDE_S: 17}  # fixed cy for horizontal borders
SIDE_SPAWN_CX = {SIDE_W: 2,  SIDE_E: 27}  # fixed cx for vertical borders


# ---- Loading ----------------------------------------------------------------

def load_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def sprites_by_id(bg_data):
    return {s['id']: s for s in bg_data['sprites']}


# ---- Per-screen walkability -------------------------------------------------

def cells_occupied_by(sprite, x, y):
    """Return set of (cx, cy) that a sprite placed at (x, y) chars occupies."""
    w = sprite.get('w', TILE_SIZE)
    h = sprite.get('h', TILE_SIZE)
    cw = (w + TILE_SIZE - 1) // TILE_SIZE
    ch = (h + TILE_SIZE - 1) // TILE_SIZE
    cells = set()
    for dy in range(ch):
        for dx in range(cw):
            cells.add((x + dx, y + dy))
    return cells


def screen_walkgrid(level, sprites, rx, ry):
    """Compute walkgrid for screen at (rx, ry). Returns 2D list [y][x] or None."""
    template_idx = level['mapTable'][ry][rx]
    if template_idx == 0:
        return None
    placements = list(level['bgPlacements'].get(str(template_idx), []))
    overlays = level['cellOverlays'].get(f"{rx},{ry}", [])
    placements.extend(overlays)

    blocked = set()
    for pl in placements:
        if pl.get('cat') == 'pickup':
            continue
        sp = sprites.get(pl['id'])
        if not sp:
            continue
        for cell in cells_occupied_by(sp, pl['x'], pl['y']):
            if 0 <= cell[0] < GRID_W and 0 <= cell[1] < GRID_H:
                blocked.add(cell)

    grid = [[0 if (x, y) in blocked else 1
             for x in range(GRID_W)]
            for y in range(GRID_H)]
    return grid


# ---- Connected components & gap filtering -----------------------------------

def connected_components(grid):
    """Return list of components, each a set of (x,y)."""
    seen = [[False] * GRID_W for _ in range(GRID_H)]
    comps = []
    for sy in range(GRID_H):
        for sx in range(GRID_W):
            if not grid[sy][sx] or seen[sy][sx]:
                continue
            stack = [(sx, sy)]
            comp = set()
            while stack:
                x, y = stack.pop()
                if not (0 <= x < GRID_W and 0 <= y < GRID_H):
                    continue
                if seen[y][x] or not grid[y][x]:
                    continue
                seen[y][x] = True
                comp.add((x, y))
                stack.extend([(x+1, y), (x-1, y), (x, y+1), (x, y-1)])
            comps.append(comp)
    return comps


def monster_fits_at(grid, side, coord):
    """Check if the 2x3 monster footprint fits entirely in walkable cells at
    the spawn position associated with this opening candidate.

    coord = variable axis: cx for N/S borders, cy for W/E borders.
    """
    if side in (SIDE_N, SIDE_S):
        cy_top = SIDE_SPAWN_CY[side]
        cx_left = coord
    else:
        cx_left = SIDE_SPAWN_CX[side]
        cy_top = coord

    for dy in range(MONSTER_FOOT_H):
        for dx in range(MONSTER_FOOT_W):
            cx = cx_left + dx
            cy = cy_top + dy
            if not (0 <= cx < GRID_W and 0 <= cy < GRID_H):
                return False
            if not grid[cy][cx]:
                return False
    return True


def spawn_in_main_region(comp_of, comps, side, coord):
    """True iff the spawn footprint lands in the main walkable region (the
    largest CC). Prevents spawning into a small pocket disconnected from
    where the player can walk."""
    if not comps:
        return False
    main = max(range(len(comps)), key=lambda i: len(comps[i]))
    if side in (SIDE_N, SIDE_S):
        cy, cx = SIDE_SPAWN_CY[side], coord
    else:
        cx, cy = SIDE_SPAWN_CX[side], coord
    return comp_of.get((cx, cy)) == main and len(comps[main]) >= MIN_POCKET_SIZE


def filter_gaps(grid, comps):
    """Return (valid_openings, discarded).

    valid_openings: list of (side, midpoint_coord). coord = cx (N/S) or cy (W/E)
                    of the monster's top-left anchor. Runs of contiguous valid
                    coords are coalesced; midpoint of the run is emitted.
    discarded: list of (side, coord, reason) for the report (debug only).
    """
    if not comps:
        return [], []
    comp_of = {}
    for i, comp in enumerate(comps):
        for cell in comp:
            comp_of[cell] = i

    valid_openings = []
    discarded = []

    # Variable axis: cx ranges 0..29 (to allow cx+1), cy ranges 0..19 (cy+2)
    def side_range(side):
        if side in (SIDE_N, SIDE_S):
            return range(GRID_W - MONSTER_FOOT_W + 1)
        return range(GRID_H - MONSTER_FOOT_H + 1)

    for side in (SIDE_N, SIDE_S, SIDE_W, SIDE_E):
        run_start = None
        for coord in side_range(side):
            ok = monster_fits_at(grid, side, coord) and \
                 spawn_in_main_region(comp_of, comps, side, coord)
            if ok:
                if run_start is None:
                    run_start = coord
            else:
                if run_start is not None:
                    mid = (run_start + coord - 1) // 2
                    valid_openings.append((side, mid))
                    run_start = None
        if run_start is not None:
            end = list(side_range(side))[-1]
            mid = (run_start + end) // 2
            valid_openings.append((side, mid))

    return valid_openings, discarded


# ---- ASM emission -----------------------------------------------------------

def screen_label(rx, ry):
    return f"ScreenGaps_{ry:X}{rx:X}"


def emit_asm(all_data, report, out_path):
    """Write the generated ASM."""
    lines = []
    lines.append("; ==============================================================================")
    lines.append("; SCREEN GAPS (bank 6)")
    lines.append("; Auto-generated by tools/build_screen_gaps.py — DO NOT EDIT BY HAND.")
    lines.append(";")
    lines.append("; Each opening = a contiguous run of walkable border cells that reach")
    lines.append("; the main walkable region (MIN_POCKET_SIZE filter). Coord = midpoint.")
    lines.append(";")
    lines.append(";   ScreenGapsTable   — 256 DEFW ptrs (screen_id = Y*16+X)")
    lines.append(";   ScreenGaps_YX     — DEFB count; then {side, coord} × count")
    lines.append(";     side: 0=N, 1=S, 2=W, 3=E")
    lines.append(";     coord: char col (0-31) N/S; char row (0-21) W/E")
    lines.append(";   ScreenGapsNone    — shared zero record (DEFB 0)")
    lines.append("; ==============================================================================")
    lines.append("")

    lines.append("ScreenGapsTable:")
    for ry in range(MAP_H):
        refs = []
        for rx in range(MAP_W):
            if (rx, ry) in all_data and all_data[(rx, ry)]['gaps']:
                refs.append(screen_label(rx, ry))
            else:
                refs.append("ScreenGapsNone")
        lines.append("    DEFW " + ", ".join(refs) + f"    ; Y={ry}")
    lines.append("")

    lines.append("ScreenGapsNone:")
    lines.append("    DEFB 0")
    lines.append("")

    for (rx, ry), data in sorted(all_data.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        gaps = data['gaps']
        if not gaps:
            continue
        lines.append(f"{screen_label(rx, ry)}:    ; room ({rx},{ry})")
        lines.append(f"    DEFB {len(gaps)}")
        for side, coord in gaps:
            lines.append(f"    DEFB {side}, {coord}    ; {SIDE_NAMES[side]} @ {coord}")
        lines.append("")

    lines.append("ScreenGapsEnd:")
    lines.append("")

    out_path.write_text("\n".join(lines), encoding='utf-8', newline='\n')

    with open(out_path.with_suffix('.report.txt'), 'w', encoding='utf-8') as f:
        f.write(report)


# ---- Main -------------------------------------------------------------------

def main():
    root = Path(__file__).resolve().parent.parent
    level = load_json(root / 'code' / 'level_data.json')
    bg = load_json(root / 'code' / 'bg_sprites.json')
    sprites = sprites_by_id(bg)

    all_data = {}
    report_lines = []
    total_rooms = 0
    total_openings = 0
    total_discarded = 0
    rooms_with_zero_openings = []

    for ry in range(MAP_H):
        for rx in range(MAP_W):
            grid = screen_walkgrid(level, sprites, rx, ry)
            if grid is None:
                continue
            total_rooms += 1
            comps = connected_components(grid)
            valid, discarded = filter_gaps(grid, comps)
            all_data[(rx, ry)] = {
                'gaps': valid,
                'comps': len(comps),
            }
            total_openings += len(valid)
            total_discarded += len(discarded)
            if not valid:
                rooms_with_zero_openings.append((rx, ry))

            report_lines.append(
                f"Room ({rx:2d},{ry:2d})  openings={len(valid):2d}  "
                f"cul-de-sacs={len(discarded):2d}  comps={len(comps)}"
            )
            for side, coord, reason in discarded:
                report_lines.append(
                    f"    DROP {SIDE_NAMES[side]}@{coord}: {reason}"
                )

    gap_bytes = sum(1 + 2 * len(d['gaps']) for d in all_data.values() if d['gaps'])
    ptr_bytes = 256 * 2
    none_bytes = 1
    total_bytes = gap_bytes + ptr_bytes + none_bytes

    summary = [
        "=" * 70,
        f"SUMMARY",
        "=" * 70,
        f"Rooms used         : {total_rooms} / {MAP_W * MAP_H}",
        f"Valid openings     : {total_openings}",
        f"Cul-de-sacs dropped: {total_discarded}",
        f"Rooms with 0 gaps  : {len(rooms_with_zero_openings)}",
    ]
    for rx, ry in rooms_with_zero_openings:
        summary.append(f"    !! ({rx},{ry}) has NO valid gaps — runtime fallback to LastEntryPos")
    summary.extend([
        "",
        f"Bank 6 estimated usage:",
        f"  Pointer table (256×2B) : {ptr_bytes} B",
        f"  Gap records            : {gap_bytes} B",
        f"  None placeholder       : {none_bytes} B",
        f"  TOTAL                  : {total_bytes} B "
        f"({total_bytes / 16384 * 100:.1f}% of bank 6)",
        "=" * 70,
    ])
    report = "\n".join(report_lines + [""] + summary) + "\n"
    print("\n".join(summary))

    out_path = root / 'code' / 'screen_gaps.asm'
    emit_asm(all_data, report, out_path)
    print(f"\nWrote {out_path}")
    print(f"Wrote {out_path.with_suffix('.report.txt')}")


if __name__ == '__main__':
    main()
