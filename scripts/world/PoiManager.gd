# scripts/world/PoiManager.gd
class_name PoiManager
extends Node

# Claims Points of Interest for whichever tribe reaches them first. A ruin is
# looted ONCE: its loot goes to the claiming unit's player, EventBus.poi_claimed
# fires, and it can never be looted again (WorldData.claim_poi is idempotent).
#
# Runs ONLY on the authority (offline / server): claiming credits resources, so
# a pure client must never do it — the claim replicates from the server. This is
# symmetric — any tribe's units, human or AI, trigger it identically.

const CHECK_INTERVAL: float = 0.25   # seconds between proximity sweeps
const CLAIM_RADIUS_TILES: int = 1    # a unit on or adjacent to the ruin claims it

var _accum: float = 0.0

func _process(delta: float) -> void:
	if not Net.is_authority():
		return
	if GameManager.world == null or GameManager.state != GameManager.GameState.RUNNING:
		return
	_accum += delta
	if _accum < CHECK_INTERVAL:
		return
	_accum = 0.0
	check_claims()

# Public (also called directly by the test harness for determinism): one sweep
# of all units against nearby unclaimed POIs.
func check_claims() -> void:
	for node: Node in get_tree().get_nodes_in_group("units"):
		var unit: UnitBase = node as UnitBase
		if unit == null:
			continue
		var cell: Vector2i = Constants.world_to_grid(unit.global_position)
		var pid: int = unit.player_id
		for dy in range(-CLAIM_RADIUS_TILES, CLAIM_RADIUS_TILES + 1):
			for dx in range(-CLAIM_RADIUS_TILES, CLAIM_RADIUS_TILES + 1):
				_try_claim(cell + Vector2i(dx, dy), pid)

func _try_claim(cell: Vector2i, player_id: int) -> void:
	if GameManager.world.is_poi_claimed(cell):
		return
	var poi: Dictionary = GameManager.world.peek_poi_at(cell)
	if poi.is_empty():
		return
	if not GameManager.world.claim_poi(cell):
		return  # lost a race this frame; idempotent guard
	var loot: Dictionary = poi.get("loot", {})
	for res_type: int in loot:
		GameManager.add_resource(player_id, res_type, int(loot[res_type]))
	EventBus.poi_claimed.emit(cell, String(poi.get("type", "")), player_id)
