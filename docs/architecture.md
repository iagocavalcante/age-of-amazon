# Age of Amazon — Architecture Decisions

This document records the significant architectural decisions behind the Godot
build of Age of Amazon and the reasoning that led to each one. It is written as
a set of lightweight ADRs (Architecture Decision Records): each entry states the
**context**, the **decision**, and the **consequences** (including the
trade-offs we knowingly accepted).

It is the reference for *why the code is shaped the way it is*. Design docs for
individual feature phases live under [`docs/plans/`](./plans); this file is the
durable, cross-cutting summary.

---

## System at a glance

```
                         EventBus  (autoload: decoupled signals)
                             ▲
   ┌─────────────┐          │           ┌──────────────────────────┐
   │  Main.tscn  │──────────┼───────────│  Autoload singletons      │
   │  (scene)    │          │           │  GameManager  (state,     │
   └──────┬──────┘          │           │    stockpiles, world ref) │
          │                 │           │  Constants   (tunables,   │
   ┌──────┴───────┐         │           │    grid math, defs)       │
   │ ChunkManager │─visuals─┤           │  AssetLibrary (art cache) │
   │ (streaming)  │         │           │  SelectionManager (input) │
   └──────┬───────┘         │           └──────────────────────────┘
          │ data
   ┌──────┴───────┐   ┌───────────┐   ┌───────────┐   ┌──────────────┐
   │  WorldData   │   │ Pathfinder│   │ FogOfWar  │   │  EnemyAI     │
   │ (chunks,     │◀──│ (custom   │   │ (renderer │   │ (symmetric   │
   │  occupancy,  │   │  A*)      │   │  + Player │   │  PlayerVision│
   │  resources)  │   └───────────┘   │  Vision)  │   │  opponent)   │
   └──────────────┘                   └───────────┘   └──────────────┘
              ▲                              │
        UnitBase / Building ────────── PlayerVision (per-player knowledge)
```

Entities (units, buildings) are Godot nodes in groups (`units`, `buildings`,
`player_0`, `player_1`); systems find them by group rather than by holding
references, which keeps them decoupled and makes the world naturally dynamic.

---

## ADR 1 — Godot 4.5 + GDScript, GL Compatibility renderer, web-first

**Context.** The game began as a ~23K-line TypeScript/Three.js prototype. We
wanted a mobile- and web-friendly 2D isometric RTS that ships as a static site.

**Decision.** Port to Godot 4.5 with GDScript, using the **GL Compatibility**
renderer, and export to Web (WASM) for GitHub Pages. Web export runs with
`thread_support = false`.

**Consequences.**
- GL Compatibility runs on the widest set of GPUs/browsers, including mobile,
  at the cost of some modern rendering features we don't need for 2D.
- `thread_support = false` is required because GitHub Pages cannot send the
  COOP/COEP headers that `SharedArrayBuffer` (threaded WASM) demands.
- GDScript keeps iteration fast and the whole game in one language; the node
  tree replaces the old custom ECS (scene-node composition).

---

## ADR 2 — Isometric grid with one conversion as the single source of truth

**Context.** Isometric math is easy to get subtly wrong, and inconsistent
grid↔world conversions cause drift between terrain, units, picking, and fog.

**Decision.** All coordinate conversion goes through `Constants.grid_to_world`
and `Constants.world_to_grid` (64×32 tiles). No system re-derives the projection
locally.

**Consequences.** Terrain rendering, unit placement, mouse picking, pathfinding,
the minimap, and the fog shader all agree by construction. Changing the tile
size or projection is a one-place edit.

---

## ADR 3 — Autoload singletons for cross-cutting state

**Decision.** Five autoloads, each with a narrow role:
- **EventBus** — global signals only; no logic or state.
- **GameManager** — game state machine, per-player stockpiles, population,
  and the references to the live `world`, `pathfinder`, and `fog`.
- **Constants** — tile math, biome tables, and the data-driven unit/building
  definitions.
- **AssetLibrary** — the procedural-art cache, built once at startup.
- **SelectionManager** — translates raw input into selection and commands.

**Consequences.** Systems reach shared state without threading references
through constructors. The discipline that keeps this from becoming a "god
object" pile is that EventBus holds no state and GameManager holds no rendering.

---

## ADR 4 — Event-driven decoupling via EventBus

**Decision.** Cross-system communication is done with EventBus signals
(`resources_changed`, `building_damaged`, `unit_died`, `help_requested`, …)
rather than direct calls between subsystems.

**Consequences.** The HUD, fog, AI, and audio/feedback can react to gameplay
without the gameplay code knowing they exist. New listeners are additive. The
cost is that control flow is less linear; the signal list in `EventBus.gd` is
kept as the authoritative catalogue.

---

## ADR 5 — Infinite world: persistent data, streamed visuals

**Context.** The prototype used a fixed pre-baked map. We wanted an endless
world that generates as you explore, without unbounded memory growth or hitches.

**Decision.** Split the world into **data** and **visuals**:
- **WorldGen** is a *pure, deterministic* per-tile function (elevation/moisture/
  forest FBM noise plus a ridged "river" noise). Any integer coordinate yields
  the same biome forever, with no stored state.
- **WorldData** holds the lazily generated **chunk data** (16×16 tiles: biomes,
  resource nodes, building occupancy) in a dictionary that is generated on
  demand and **never discarded** — so revisited land is identical and gameplay
  state is never lost.
- **ChunkManager** streams only the **visuals**: it builds ground/water/doodad
  sprites for chunks near the camera (plus a one-chunk margin), budgeted per
  frame, and frees them when they leave range.

**Consequences.** Memory for visuals is bounded by the viewport, not by how far
you've explored; chunk *data* grows slowly and cheaply (no textures). The
determinism also makes the world reproducible from a single seed. Border-ring
tile painting and a world-space water shader keep chunk seams invisible.

---

## ADR 6 — Custom A* pathfinder instead of the built-in navigation

**Context.** The world is infinite. Godot's `AStarGrid2D` and the
`NavigationServer` both want a **bounded, pre-defined region** — incompatible
with a map that has no edges and generates as you walk.

**Decision.** Hand-roll an A* pathfinder (`Pathfinder.gd`) that queries
`WorldData` on demand: a binary min-heap open set, an octile heuristic, an
**expansion budget** (~4000 nodes) so a hopeless request can't stall a frame,
and a **partial-path fallback** that returns the best-effort route toward
unreachable targets.

**Consequences.** Pathfinding works anywhere in the endless world with no
pre-baking. The budget caps worst-case cost; the partial-path fallback keeps
units responsive when a target is blocked or in the fog. We own the code, so
formation movement and "walk to the nearest walkable adjacent tile" (for
gathering/depositing) are straightforward extensions.

---

## ADR 7 — Procedural pixel-art pipeline (no external art assets)

**Context.** We wanted an "A+" cohesive look, a tiny download, and no
dependency on hand-authored sprite sheets or licensing.

**Decision.** Generate **all** art procedurally at startup:
- `PixelArt.gd` provides the primitives — a 4×4 **Bayer dither** matrix, a
  deterministic 2D **hash** (`hash2`), **ramp shading**, ASCII-rows→texture,
  and ellipse fills/rings.
- Per-domain artists (`UnitArtist`, `BuildingArtist`, `DoodadArtist`,
  `TerrainArtist`, and now `AnimalArtist`) compose those primitives.
- `AssetLibrary` builds every texture once at boot and hands them out.

**Consequences.** The whole art set is a few kilobytes of code, deterministic,
and trivially re-tinted per player (units/buildings take a `player_color`).
Ordered dithering over color ramps gives gradients a hand-pixelled feel instead
of banding. The trade-off is that art changes are code changes, and complex
shapes are more work than dropping in a PNG — accepted for the consistency and
zero-asset footprint.

---

## ADR 8 — Data-driven entities with a single state machine

**Decision.** Units are one `UnitBase` (a `CharacterBody2D`) driven by a small
state machine — `IDLE / MOVING / GATHERING / ATTACKING` — plus an `_intent`
dictionary describing what `MOVING` should do on arrival (gather, deposit,
attack). Stats live in `Constants.UNIT_DEFS`; buildings in `BUILDING_DEFS`.

**Consequences.** Adding a unit type is a data edit, not a new class. The
`_intent`-on-arrival pattern cleanly expresses "walk there, *then* do X" without
nested callbacks. Behaviours shared by every unit (retaliation when struck,
aggressive auto-acquire) live in one place.

---

## ADR 9 — Fog of War: knowledge vs. renderer, split cleanly

**Context.** We wanted Age-of-Empires fog: unexplored land is black, explored
land is remembered but dimmed, and only currently-watched land is clear — over
an infinite, streamed world.

**Decision.** Separate the **knowledge** from the **drawing**:
- **PlayerVision** is a plain object holding one player's `explored` (permanent)
  and `visible` (this frame) tile sets, recomputed from that player's units and
  buildings. It answers `is_visible`, `is_explored`, `can_see_entity`,
  `has_discovered_building`.
- **FogOfWar** is the *renderer for the local player*: it keeps a per-chunk R8
  fog image, blits the chunks around the camera into one window texture, and a
  full-screen shader maps that texture back onto the isometric grid (inverse
  projection) with soft edges. It also **culls entities** — enemy units hide
  unless currently visible; enemy buildings stay once their ground is explored.

**Consequences.** Because knowledge is a separate object, *any* player can have
vision — which is what makes symmetric AI fog (ADR 10) possible. Rebuilds are
scoped to chunks whose knowledge changed, so cost tracks activity, not world
size.

---

## ADR 10 — Symmetric fog for the AI

**Context.** An AI that reads the full game state "cheats" — it beelines to your
base from minute one. We wanted the opponent to play by the same information
rules as the player.

**Decision.** `EnemyAI` owns its **own `PlayerVision`**. It may only target
buildings it has actually **discovered** (remembered once seen, since buildings
can't move) and units currently **inside its vision**. While the player is
undiscovered it sends a scout sweeping the eight compass directions, expanding
outward each round; being attacked reveals the attacker (idle warriors rally to
defend).

**Consequences.** Discovery and aggression emerge from the AI's own scouting,
not omniscience. One asymmetry remains **by design and is documented**: the AI
runs on trickle income rather than a real villager economy — an *economy*
concession, not an *information* one. (Giving the AI real gathering villagers
driven by the same command API is the natural next step.)

---

## ADR 11 — UI built in code

**Decision.** The HUD and the How-to-Play screen are constructed in GDScript
(`HUD.gd`, `HelpScreen.gd`) rather than authored as `.tscn` scenes, with styling
defined right next to the logic. The help overlay is modal (pauses the match,
shields the HUD from input, restores the prior pause state on close) and is
opened via the decoupled `EventBus.help_requested` signal or the H/F1 keys.

**Consequences.** All of a widget's appearance and behaviour live in one file,
which suits procedurally themed UI and keeps styling consistent. The cost is
more verbose construction code than a visual editor; accepted for the cohesion.

---

## ADR 12 — Verification via headless harnesses and offline frame capture

**Context.** Testing the *deployed* web build by clicking it is unreliable:
browsers throttle `requestAnimationFrame` on occluded/hidden tabs, so units
appear frozen while automated clicks still register — a false negative that
wasted real debugging time.

**Decision.** Prove gameplay **natively**:
- Headless `--test-*` harnesses (`--test-move`, `--test-systems`, `--test-scout`,
  `--test-hunt`) drive the real systems and print pass/fail assertions. They
  **self-terminate** (`get_tree().quit()`) so they run cleanly in automation.
- Visual layout is checked with Godot's **movie-writer mode**, which renders
  frames offline deterministically; a `--capture-help`-style harness saves a
  screenshot we can inspect.

**Consequences.** Logic and layout are verified without a flaky browser in the
loop. Deployment freshness is confirmed separately by comparing the shasum of
the locally built `index.pck` against the one served at the edge.

---

## ADR 13 — Deployment: gitignored build, gh-pages via worktree

**Decision.** The Web export writes to `build/web/` (which is **gitignored**).
Deployment copies that output onto the **`gh-pages`** branch (files at the repo
root plus a `.nojekyll` marker) using a dedicated git **worktree**, then pushes.
GitHub Pages serves the branch.

**Consequences.** Source history (`main`) stays free of build artifacts, while
the served site is a plain static branch. The worktree keeps the deploy checkout
isolated from the working tree. Freshness is verified by fetching the live
`index.pck` and comparing its hash to the local build.

---

_Feature-level ADRs are appended below as systems are added._

---

## ADR 14 — Huntable wildlife

**Context.** We wanted animals roaming the map that **both** the player and the
AI can hunt for food, consistent with the endless world and the existing
combat, gathering, and fog systems.

**Decision.**
- **Neutral entities, own group.** Animals are `CharacterBody2D` nodes in an
  `animals` group with a neutral `player_id` (`-1`). They are deliberately
  **not** in the `units` group, so warriors do not auto-wander off to hunt
  during battles — hunting is a *deliberate* command. Retaliation against a
  predator still works because it flows through `take_damage(attacker)`, which
  doesn't care about groups.
- **Two data-driven species** in `Constants.ANIMAL_DEFS`:
  - **Capybara** — passive prey: wanders, and flees from any unit that gets
    close. Low HP, modest food bounty. The staple hunt.
  - **Jaguar** — predator: wanders, and attacks the nearest unit of *any*
    player within its aggro radius. Higher HP, larger bounty — risk/reward.
- **Hunting = combat.** Right-clicking an animal issues the existing
  `command_attack`; the fog picker already restricts targets to what's visible.
  On death the animal pays a **food bounty directly to the killer's player**.
  This is symmetric — the AI hunts with its warriors and is rewarded the same
  way — and avoids new "carcass as a gatherable resource" plumbing (which would
  need render-after-build and a fresh fog path, and wouldn't help the AI, which
  fields no villagers). Food-on-kill is the simpler, fully symmetric choice.
- **Ambient population, not chunk-bound.** An `AnimalManager` maintains a
  **bounded** number of live animals within the active area around the camera
  and player units — spawning on walkable land just outside view and despawning
  strays that wander far from everything. Animals move between chunks, so tying
  their lifecycle to chunk load/unload (as we do for static doodads) would be
  wrong; an ambient spawner keeps the count and cost bounded in the infinite
  world.
- **Fog-consistent for both sides.** Animals are culled by the fog like enemy
  units (hidden unless in the local player's vision) and shown on the minimap
  only when visible. The AI likewise only hunts animals inside **its own**
  `PlayerVision`.

**Consequences.** Wildlife reuses combat, fog, culling, and the minimap with no
special cases in those systems beyond an added group. Food-on-kill keeps the
reward symmetric between the human and the trickle-economy AI without inventing
an economy for the latter. The bounded ambient population keeps performance flat
regardless of how far the world is explored. Predators add danger and naturally
exercise the existing retaliation rules. The main trade-off versus AoE-style
carcass-gathering is that villagers gain no special role in hunting — accepted
for the symmetry and simplicity.
