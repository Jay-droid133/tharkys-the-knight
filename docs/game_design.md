p---
name: Game Design Document
description: Complete game design - story, mechanics, progression, key items, monster herding, endgame
type: project
---

# Game Design Document

## Setting
- Small walled city, much smaller than Sabre Wulf
- East: cemetery (locked gate) with a church inside
- West: wooded area
- Surrounded by walls, great gate at the south center (locked)
- Flick-screen maze exploration

## Story
Player must rid the town of 3 monsters by herding them into the church using a crucifx.

## Day/Night Cycle Phases
| Phase | Nasties | Monsters | Notes |
|-------|---------|----------|-------|
| DY (day) | Diurnals (Eagle, Spider, Goat, Snake) | No | |
| C1 (early twilight) | Diurnals | No | |
| C2 (late twilight) | Crepusculars (Rat, Bat, Scorpion, RabidCat) | No | |
| N1 (early night) | Crepusculars | No | |
| N2 (late night) | None (bells scare them) | Yes (3 monsters) | |
| A1 (early dawn) | None - pause | No (monsters flee) | |
| A2 (late dawn) | Diurnals return | No | |

## Progression System
- DayCycleCount only advances when player collects the current key piece
- If key piece not collected, day REPEATS (Groundhog Day loop)
- DAY indicator in HUD shows progress (DAY 1, 2, 3, 4...)

## Key Pieces - Carrier Mechanic
Each day, a special WHITE carrier nasty follows a fixed route through the city.
It waits in a room until the player enters, then moves to the next room on its route.
If player deviates, carrier waits at its next stop.

| Key Piece | Diurnal Carrier | Crepuscular Form | Route |
|-----------|----------------|-------------------|-------|
| Piece 1 | White Eagle | White Bat | Route A |
| Piece 2 | White Goat | White Cat | Route B |
| Piece 3 | White Snake | White Rat | Route C |

- C2 (late twilight): carrier transforms into crepuscular version, same route
- N2 (bells): carrier drops the key piece wherever it is, then flees
- Key piece not collected: next day NO carrier. Piece is on the ground in that room. Player must explore to find it
- Key piece collected: next day, next carrier, next route

## Crucifx Acquisition
After collecting all 3 key pieces:
1. Go to cemetery, use complete key to unlock gate padlock
2. If player doesn't open padlock: day REPEATS
3. Next day (daytime only): a WHITE SPIDER appears, heads toward the church, enters it
4. Church door stays open. Player enters (disappears inside), crucifix lights up in HUD, player exits
5. If nighttime: church window flickers as hint to come back during daytime
6. Spider is slow, won't escape - contrast with previous carriers

## Monster Herding (Endgame)
With the crucifix:
- Monsters AVOID the player (crucifix repels them)
- Crucifix acts as COMPASS: brightness indicates proximity to nearest monster
  - Dim: monsters far away
  - Medium: getting closer
  - Bright/flash: adjacent room
  - Fast flash: same room
- Monsters always spawn FAR from cemetery (west/south rooms), forcing player to cross the town
- Player must HERD monsters like cattle using sword hits, pushing them toward the cemetery/church
- Goal: herd all 3 together if skilled, or one at a time
- If player can't get them all in one night, wait for next night (monsters will be elsewhere)
- Monsters move FASTER inside the cemetery (increased difficulty)

## Church Mechanics
- Player opens church door with sword attack (door stays open briefly, then closes)
- While open, push monsters inside
- Each monster that enters: door + windows flash WHITE, door closes
- Can try to push multiple at once or one by one
- After 3rd monster enters: flash WHITE + RED, game complete
- Door closes after each entry, must reopen with sword for next monster

## Endgame Sequence
1. Three monsters inside church: door flashes white+red
2. Player must go to the great south gate (now open?)
3. Player enters gate
4. Game takes control: player turns around thoughtfully
5. A hand appears above player's head giving the finger to the town
6. Black screen, credits

## Health & Stamina System
- Health indicator: LEFT side of clock decoration, depletes line by line
- Stamina indicator: RIGHT side of clock decoration, depletes line by line
- Both change color as they deplete: green, blue, yellow, red, magenta, blue

### Stamina Levels affect sword mode:
| Level | Sword Mode |
|-------|-----------|
| Maximum (start, potion) | Continuous use |
| Medium | Fixed swing (mode F) |
| Low | Short cooldown |
| Empty | Long cooldown |

### Recovery:
- Wells (scattered through town)
- Potions (dropped by any monster occasionally, or a specific one)
- Recovery works for both health and stamina

## HUD Elements
- Clock (center): analog clock with day cycle
- Health (left clock decoration): depleting bar with color change
- Stamina (right clock decoration): depleting bar with color change
- Key pieces (3 slots): empty/filled
- Crucifix: appears when obtained
- DAY indicator: DAY 1, 2, 3, 4...
- Sword mode: C/F/S (debug, may remove later)

## Predator AI (Nasties)
Three attack types, cumulative by cycle:
- **Cycle 1**: Aerial (Eagle/Bat) - dive from above when aligned with player row
- **Cycle 2**: + Ground (Snake/Scorpion) - lunge from below when aligned
- **Cycle 3**: + Horizontal (Goat/RabidCat) - charge when aligned with player column
- Speed escalates: 2px (cycle 1), 3px (cycle 2), 4px (cycle 3+)

## Scared Behavior (Bells/Dawn)
Nasties AND monsters share scared behavior:
1. Dramatic pause: freeze, look side to side (~3s)
2. Flee toward nearest screen edge
3. Despawn when reaching edge

## Game Start
- Starts at 07:00 (daytime, DY phase)
- Player sees the town, the locked gate, begins exploring
