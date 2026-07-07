# Age of Amazon — Phase 2 Design (war, collect, HUD, infinite world)

## Infinite world

The fixed 64x64 pre-baked map becomes a chunk-streamed infinite world.

- **WorldGen** — pure per-tile biome function, deterministic for any integer
  coordinate: elevation/moisture/forest FBM noise + a ridged "river" noise
  (|n| below a threshold carves winding channels; a detail noise forces
  periodic shallow fords). Spawn clearings are radial grass overrides around
  fixed player origins (player 0 at (0,0), enemy at (44,44)).
- **WorldData** — persistent chunk dictionary (`Vector2i -> Chunk`). Chunk
  data (biomes, resource nodes, building occupancy) is generated lazily once
  and never discarded. Tile queries route through here.
- **Chunk** — 16x16 tiles. Data plus lazily-built visuals: baked ground
  texture (1024x512), water-mask overlay with the animated shader, doodad
  and resource-node sprites.
- **ChunkManager** — Node2D replacing IsometricMap. Each frame computes the
  camera's visible chunk range (+1 ring margin), instantiates visuals for
  missing chunks (budgeted per frame to avoid hitches) and frees visuals
  outside the range. Data persists.
- **Pathfinder** — custom A* (binary heap, octile heuristic) over WorldData,
  since AStarGrid2D needs a fixed region. Expansion budget with best-effort
  partial paths. Building-occupied cells are unwalkable.
- Camera bounds clamping removed.

## Collect system

- Resource nodes live in chunk data: **trees** (wood) in forests, **berry
  bushes** (food) on grass, **jade deposits** on high ground. One node per
  tile, amounts 60-150. Depleted nodes disappear.
- Villager cycle: move adjacent to node → gather 1/1.2 s until carrying 10 →
  walk to nearest own Town Center → deposit into player stockpile → repeat
  until the node dies, then retarget a nearby node of the same type.
- Stockpiles per player in GameManager; EventBus.resources_changed drives
  the HUD.

## War system

- Unit stats come from Constants.UNIT_DEFS (villager, warrior). Warriors:
  more HP/attack, auto-acquire enemies in vision when idle.
- ATTACKING state: chase until in range, strike on a cooldown, damage =
  max(1, attack - armor). Victim death frees the attacker to re-acquire.
- **Town Center**: 2x2-tile building, 600 HP, blocks pathfinding, deposit
  point, trains villagers (50 food) and warriors (40 food + 20 wood) on a
  queue. Destroying a Town Center ends the game (win/lose).
- **Enemy AI**: trickle income (standard "cheating AI" — no simulated enemy
  economy), trains warriors on a timer, launches attack waves of 3+ at the
  player's Town Center, defends its base.

## HUD

CanvasLayer with: top resource bar (food/wood/jade + population/cap 20),
bottom selection panel (selected units summary, or Town Center panel with
train buttons and queue), camera-centered minimap (1 px/tile window of
generated chunks, unit/building dots, click to jump the camera), and a
game-over overlay.

## Command dispatch (right-click)

Enemy unit/building under cursor → attack; resource node (villagers) →
gather; otherwise → formation move.
