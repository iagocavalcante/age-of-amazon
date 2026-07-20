# Age of Amazon — Game Bible

This is the canonical design reference for Age of Amazon: what the game is,
why it is that way, and where it is going. It is the *what and why* companion
to [`architecture.md`](./architecture.md), which records the *how* (ADRs).
Feature-phase design docs live under [`docs/plans/`](./plans).

Sections marked **[SHIPPED]** describe the game as it exists today. Sections
marked **[PLANNED]** are validated designs awaiting implementation; the build
order is in the [Roadmap](#7-roadmap).

---

## 1. Vision & Design Pillars

Age of Amazon is a 2D isometric real-time strategy game set in an endless
procedurally generated Amazon rainforest. Two to four tribes gather, build,
scout, fight, and race to raise a jade Monument — against an AI that plays by
the same information rules, or against each other in the browser.

Every design decision is tested against five pillars:

### P1 — The jungle is the antagonist
The Amazon is not a backdrop. Distance, rivers, dense forest, predators, and
the unknown are the real opposition; the rival tribe is just the one that
navigates them better. Every new feature should make the world more *alive*,
not more decorative. If a feature could exist unchanged in a generic
grass-plains RTS, it needs a jungle reason to exist here.

### P2 — Fair knowledge
Nobody cheats: not the AI, not the server, not the player. The AI owns its own
fog-of-war knowledge and may only act on what it has scouted (ADR 10). The
multiplayer server validates every command (ADR 15). Any future system that
grants information must grant it symmetrically.

### P3 — Readable depth
Strategy comes from meaningful choices — which era to advance to, which tribe
to play, which river to follow — never from memorized complexity. A new
player should understand any unit or building at a glance. Rosters stay
small; each entry earns its slot by creating a decision, not a lookup.

### P4 — Everything runs everywhere
Web-first, tiny download, GL Compatibility renderer, procedural art with
painted overrides (ADRs 1, 7, 16). No feature ships if it breaks the browser
build or meaningfully grows the download. Every feature lands with a headless
`--test-*` harness (ADR 12).

### P5 — Respect for the real Amazon
The game honors real Amazonian peoples and ecology. Tribes inspired by real
cultures are portrayed with dignity under the guidelines in
[Section 3](#3-the-tribes); wildlife and biomes are drawn from the real
rainforest. The game never claims to depict real societies, beliefs, or
history.

---

## 2. The World

### 2.1 Generation model **[SHIPPED]**

The world is infinite and deterministic. `WorldGen` is a pure per-tile
function (elevation / moisture / forest FBM noise plus ridged river noise):
any integer coordinate yields the same biome forever, from a single
`map_seed`. Chunk *data* (16×16 tiles) is generated lazily and never
discarded; chunk *visuals* stream in around the camera (ADR 5). Terrain never
crosses the network — multiplayer clients and the daily challenge rebuild
identical worlds from the seed alone.

Current biomes: grass, light forest, dense forest, shallow water, deep water
(unwalkable), swamp, cliff (unwalkable), high ground. Resources: **food**
(bushes, fishing spots, wildlife bounties), **wood** (trees; fruit trees pay
a food bonus), **jade** (rare; fuels the Monument victory).

### 2.2 Expanded biomes **[PLANNED — Phase 1]**

New biomes derive from the same pure per-tile function; determinism is
untouched. Each exists to create a strategic texture, not scenery:

| Biome | Character | Strategic role |
|---|---|---|
| **Várzea (flooded forest)** | Wetland flanking rivers | Slow movement, rich food, **no building** — tempting and dangerous |
| **Terra firme jungle** | The dense default, re-flavored | More wood; slightly reduced vision inside — ambush country |
| **Clearings / savanna patches** | Open ground | Fast movement, ideal base sites, exposed to attack |
| **Jade highlands** | Rocky hills | Jade concentrates here; sparse trees; natural chokepoints |
| **Igarapé streams** | Narrow channels off the river noise | Crossable only at **fords**, carving the map into defensible regions |

Rivers are promoted from decoration to strategy: fords are the chokepoints,
fishing spots the economy, and — once War Canoes exist (Section 4) — the
water itself becomes a highway.

### 2.3 Points of interest **[PLANNED — Phase 1]**

Rare deterministic features seeded by chunk hash — same seed, same world, so
multiplayer and the daily challenge stay in sync. POIs obey fog exactly like
buildings (discovered permanently once seen), and the AI learns of them only
through its own `PlayerVision`. They give the scouting phase real
destinations: exploration becomes a strategy, not a chore.

| POI | Effect | Notes |
|---|---|---|
| **Ancient ruins** | One-time resource cache (wood/food/jade) to the first tribe whose unit reaches it | Simplest POI; ships first |
| **Sacred grove** | Small aura while your units hold it (e.g. slow food trickle or vision bonus) | A contestable objective; control is presence-based |
| **Abandoned village** | Neutral ruined buildings; claim by repairing with a villager | A forward base you earn |
| **Wildlife hotspots** | Jaguar dens, capybara herds — biased spawn regions for the ambient `AnimalManager` | Risk/reward geography for hunting |

### 2.4 Wildlife **[SHIPPED]**

Five species roam the world as neutral entities, hunted by right-click attack
for a food bounty paid to the killer's tribe (ADR 14): **capybara** (staple
prey), **tapir** (big placid bounty), **bush dog** (weak pack predator),
**caiman** (water-edge ambusher), **jaguar** (apex predator, best bounty).
Population is ambient and bounded around the action, fog-consistent for both
player and AI.

---

## 3. The Tribes **[PLANNED — Phase 3]**

Four playable tribes at launch, each named in honor of a real Amazonian
people. Bonuses are drawn from broadly documented, non-caricatured cultural
strengths and stay deliberately light — **one economic bonus, one military
flavor, one unique unit or building each** — to keep balance tractable and
the AI symmetric.

| Tribe | Identity | Economic bonus | Military flavor | Unique |
|---|---|---|---|---|
| **Tupi** | The widespread river-and-coast generalists | +10% food from all sources | Balanced roster | **Elite Bowman** — upgraded archer line |
| **Kayapó** | Renowned defenders of their forest territory | Buildings −15% cost | Buildings +20% HP | **War Lodge** — fortified watchtower that garrisons units |
| **Yanomami** | Deep-forest dwellers | Wood gathered +10% faster | Units move faster and see farther in forest biomes | **Forest Scout** — stealthy, wide-vision skirmisher |
| **Munduruku** | Historically famed river warriors | Fishing +25% | Water units stronger | **War Canoe** upgraded; land raids from water |

Mechanics are **decoupled from names**: bonuses live in a data table keyed by
tribe id, display names and art live in a separate presentation layer. This
keeps the cultural fallback (below) a rename, not a redesign.

### Cultural respect guidelines

These are binding on all tribe content — writing, art, audio, and store
material:

1. **Inspiration, not depiction.** Tribes are *inspired by and named in honor
   of* real peoples. The game does not claim to depict their societies,
   beliefs, or history, and says so in-game.
2. **No sacred mechanics.** Spiritual or sacred practices are never turned
   into game mechanics. The Shaman unit is a generic healer archetype, not a
   depiction of any real practice.
3. **No costume clichés.** Art direction uses regionally plausible material
   culture (architecture, tools, watercraft); body paint and ornament
   patterns are kept generic and invented, never copied from a specific
   people's protected designs.
4. **Acknowledgment screen.** An in-game screen names the peoples that
   inspired the tribes and links to learning resources about the
   contemporary Indigenous Amazon.
5. **PT-BR is first-class.** Brazilian Portuguese localization ships with the
   tribes, not after them.
6. **Pre-agreed fallback.** If any depiction draws criticism from Indigenous
   communities, the tribes are renamed to fictional ecology-based identities
   (River People, Canopy People, …). Because mechanics are decoupled from
   names, this is cheap by design.

---

## 4. Progression — The Three Eras **[PLANNED — Phase 2]**

Era advancement happens at the Town Center, costs resources, and is
**announced to all players** (horn + minimap ping) — you always know your
rival advanced, per P2. There is no separate research tree: **the era itself
is the upgrade**. Advancing unlocks the next content tier and applies one
small, readable tribe-wide buff.

### Era I — Forest Age (match start)

The scouting-and-hunting opening: find food, find water, find the enemy.

- **Units:** Villager, Warrior
- **Buildings:** Town Center, House, Watchtower

### Era II — Village Age

*Advance cost: food + wood; requires 2 Houses.*
*Advance buff: villagers gather slightly faster.*

- **Units:** **Archer** (moves here from the base roster), **Hunter** *(new)*
  — villager-line unit with bonus damage vs. animals and larger carried-food
  capacity; makes wildlife hotspots strategic
- **Buildings:** Barracks, **Storehouse** *(new)* — resource drop-off point
  that shortens gather routes; the expansion enabler, **Palisade wall &
  gate** *(new)*

### Era III — Chiefdom Age

*Advance cost: includes jade — pushing players toward highlands and ruins
before the endgame.*
*Advance buff: warriors and archers +1 armor.*

- **Units:** **Shaman** *(new)* — slow heal aura, no attack; each tribe's
  **unique unit** (Section 3); **War Canoe** *(new)* — water combat, unlocks
  river dominance
- **Buildings:** **Monument** — the jade victory build (finish it, hold it
  for 90 seconds, win)

### Rules that keep it honest

- The **AI advances through the same eras at the same costs**, paid from its
  trickle income, and its army composition tiers up accordingly — symmetric
  by construction. AI era logic ships in the same phase as the era system;
  an AI stuck in Era I would violate P2's spirit.
- Roster growth is deliberately small (P3): three new common units + tribe
  uniques, three new buildings. Any further addition must displace a
  decision, not add a lookup.
- Era state replicates over the existing multiplayer config/tick protocol
  (ADR 15); no new replication machinery.

---

## 5. Ways to Play

### 5.1 Skirmish vs. AI **[SHIPPED]**
The core offline mode: one human tribe against the symmetric-fog AI opponent
on an endless world. Victory by conquest or Monument.

### 5.2 Multiplayer **[SHIPPED]**
2–4 players over WebSockets: authoritative headless server, 4-letter room
codes, process-per-match (ADR 15). Terrain from seed; commands validated
server-side.

### 5.3 Daily challenge **[SHIPPED]**
A shared UTC-seeded map each day; race to win fastest; public daily board.
Phase 1's biomes and POIs make each day's map genuinely distinctive.

### 5.4 Survival mode **[PLANNED — Phase 4]**

Solo, endless, escalating — the purest expression of P1: *the jungle itself
attacks*. Waves alternate between **predator packs** (bush dogs, jaguars,
caimans from the rivers) and **raider camps** — hostile neutral warbands
that spawn at the fog edge and march on your base. Each wave is stronger;
between waves you get a breather to rebuild and advance eras.

- **Score:** waves survived + style bonus (villagers alive, buildings
  standing).
- **Leaderboard:** reuses the daily-challenge board plumbing.
- **Implementation shape:** raiders are a hostile "player" with no economy —
  the trickle-income AI pattern already proves that shape works. Spawning
  reuses `AnimalManager` patterns; combat and fog are untouched.

### 5.5 Scenario campaign — *The First Chiefdom* **[PLANNED — Phase 4]**

Five to seven authored missions teaching mechanics in story order. Each
scenario is **a seed + scripted spawns + a win/lose condition** — data-driven,
no new engine systems beyond an objective checker.

1. **First Fire** — hunt & gather tutorial
2. **Flood Season** — survive escalating predators (survival-mode preview)
3. **The Taken** — rescue villagers from a raider camp
4. **The Long Walk** — escort a shaman to a sacred grove
5. **Stones of the Ancients** — claim a ruin before the rival tribe does
6. **Two Rivers** — full match with era play
7. **The First Chiefdom** — build the Monument under siege

### 5.6 Match setup **[PARTIALLY SHIPPED]**
Today: mode selection and multiplayer rooms. With Phase 3: tribe pick in
setup and lobby. Seed entry exists for reproducibility; further setup options
(AI difficulty tiers, alternate win conditions) are deliberately deferred —
see [Non-goals](#8-non-goals--deferred).

---

## 6. Achievements **[PLANNED — Phase 4]**

Roughly twenty in-match goals evaluated from existing `EventBus` signals
(kills, construction, resources, exploration already flow through it).
Stored locally, surfaced post-match. They layer replayability onto every
mode without touching gameplay code — pure listeners.

Representative set:

| Achievement | Condition |
|---|---|
| *Pacifist Victory* | Monument win with zero enemy units killed |
| *Apex Predator* | Kill a jaguar with a villager |
| *Cartographer* | Explore 100 chunks in one match |
| *River Lord* | Field 5 War Canoes at once |
| *Landlord* | Claim an abandoned village |
| *First Light* | Reach Chiefdom Age before 10 minutes |
| *The Jungle Provides* | Win without ever building a Barracks |
| Tribe-specific | One per tribe, themed on its identity |

---

## 7. Roadmap

Four phases; each is shippable on its own and ends with the existing
verification discipline — headless `--test-*` harnesses plus movie-writer
captures (ADR 12) — and must stay inside the web-build budget (P4).

### Phase 1 — The Living World
1. Expanded biome table: várzea, clearings, jade highlands, igarapé fords.
2. POIs in order of simplicity: ruins → sacred groves → abandoned villages →
   wildlife hotspots.

*Every existing mode gets better immediately; daily-challenge maps become
distinctive. No dependencies.*

### Phase 2 — The Three Eras
1. Era state machine, costs, gating, advancement announcements.
2. New commons: Storehouse, Hunter, Palisade, Shaman, War Canoe.
3. **AI era logic in the same phase** (P2).
4. Era state over the existing replication protocol.

### Phase 3 — The Tribes
1. Bonus/unique-unit data layer, mechanics decoupled from names.
2. Tribe pick in match setup and multiplayer lobby.
3. Acknowledgment screen; PT-BR localization pass.

### Phase 4 — Challenges
1. **Achievements first** — cheapest, pure EventBus listeners, and they
   retroactively reward Phases 1–3 content.
2. Survival mode.
3. Scenario campaign last — it teaches eras and tribes, which must exist
   first.

---

## 8. Non-goals / deferred

Recorded so future ideas are judged against deliberate choices, not gaps:

- **No fourth resource.** Jade covers "rare and precious"; a stone/gold
  economy adds lookups, not decisions (P3).
- **No research tree.** Eras carry all progression; per-tech menus were
  considered and rejected as complexity without readability (P3).
- **No hero units or abilities.** Units stay one-glance readable (P3).
- **No naval-only maps.** Water is a strategic layer of the one endless
  world, not a separate map type.
- **Bounded/mirrored competitive maps** — deferred, not rejected; the POI
  system may later support "curated seeds" cheaply.
- **AI villager economy** (replacing trickle income) — the natural next step
  after Phase 2, still deferred (ADR 10's documented asymmetry).
- **Server-side visibility filtering** (anti-maphack) — known hardening step,
  deliberately deferred (ADR 15).

---

*This bible is living: when a phase ships, its sections flip from PLANNED to
SHIPPED and the corresponding ADRs land in `architecture.md`.*
