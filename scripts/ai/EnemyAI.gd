# scripts/ai/EnemyAI.gd
extends Node

# Minimal but functional opponent: receives a trickle income (a standard
# "cheating AI" — it fields no economy of its own), keeps training warriors
# at its Town Center, and periodically throws an attack wave at the player.

const ENEMY_ID: int = 1
const TICK_INTERVAL: float = 1.0
const WAVE_INTERVAL: float = 75.0
const WAVE_MIN_WARRIORS: int = 3
const MAX_WARRIORS: int = 8

const TRICKLE: Dictionary = {
	Constants.ResourceType.FOOD: 3,
	Constants.ResourceType.WOOD: 2,
}

var _tick_accum: float = 0.0
var _wave_accum: float = 0.0

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.RUNNING:
		return
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum = 0.0
	_wave_accum += TICK_INTERVAL
	_tick()

func _tick() -> void:
	for type: int in TRICKLE:
		GameManager.add_resource(ENEMY_ID, type, TRICKLE[type])

	var tc: Building = _own_town_center()
	if tc == null:
		return

	var warriors: Array[UnitBase] = _own_warriors()

	if warriors.size() + tc.train_queue.size() < MAX_WARRIORS:
		if GameManager.can_afford(ENEMY_ID, Constants.UNIT_DEFS["warrior"]["cost"]):
			tc.queue_train("warrior")

	if _wave_accum >= WAVE_INTERVAL:
		var idle: Array[UnitBase] = []
		for warrior: UnitBase in warriors:
			if warrior.current_state == UnitBase.State.IDLE:
				idle.append(warrior)
		if idle.size() >= WAVE_MIN_WARRIORS:
			_wave_accum = 0.0
			var target: Node2D = _player_target()
			if target != null:
				for warrior: UnitBase in idle:
					warrior.command_attack(target)

func _own_town_center() -> Building:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.player_id == ENEMY_ID and building.building_type == "town_center":
			return building
	return null

func _own_warriors() -> Array[UnitBase]:
	var result: Array[UnitBase] = []
	for node: Node in get_tree().get_nodes_in_group("player_%d" % ENEMY_ID):
		var unit: UnitBase = node as UnitBase
		if unit != null and unit.unit_type == "warrior":
			result.append(unit)
	return result

func _player_target() -> Node2D:
	# Prefer the player's Town Center; fall back to any player unit.
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null and building.player_id == GameManager.LOCAL_PLAYER_ID:
			return building
	for node: Node in get_tree().get_nodes_in_group("player_%d" % GameManager.LOCAL_PLAYER_ID):
		if node is UnitBase:
			return node as Node2D
	return null
