# Construction Design

Players construct buildings with villagers. Decided with the author:
House + Barracks + Watchtower, villager-built (AoE-style).

- **Defs** (`Constants.BUILDING_DEFS`): house 1x1/200hp/30w (+5 pop, ceiling
  50), barracks 2x2/400hp/60w20f (trains warriors), watchtower 1x1/250hp/40w
  (16-tile vision). Constructable = has a `cost`.
- **Model**: `place` command → authority validates (cost, walkable,
  unoccupied, resource-free, scouted by that tribe via per-player visions) →
  spends → spawns a site at 10% hp → auto-orders the issuing villagers.
  Villagers get a BUILDING state (adjacent, +6 hp per 0.5s swing each).
  Completion unlocks training/pop bonus; sites give only 3 tiles of vision
  and can be razed. `build` command resumes an abandoned site (also via
  right-click).
- **UX**: build buttons in the HUD when villagers are selected → ghost
  placement mode (green/red validity, left-click place, right-click/Esc
  cancel) in SelectionManager.
- **MP**: rides the existing pipeline — spawns via entity_spawned, the
  building state tick + spawn data gain an `is_constructed` flag
  (PROTOCOL_VERSION 4).
- **Art**: three new procedural BuildingArtist sprites (hut, longhouse,
  stilted tower), sites drawn translucent earth-toned.
- **Verified**: `--test-build` (7 assertions: rejections, cost, guard,
  completion, pop cap, barracks training) + `build-sync` in the MP client
  harness + full suite.
