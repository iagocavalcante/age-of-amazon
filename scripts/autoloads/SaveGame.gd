# scripts/autoloads/SaveGame.gd
extends Node

# Single-player persistence: the offline match autosaves every few seconds
# to user:// (IndexedDB on the web export), so a browser refresh resumes
# where you left off. The world itself is never serialized — terrain and
# resources rebuild from (map_seed + harvest deltas); only entities, fog,
# stockpiles, and the camera are stored. Multiplayer state lives on the
# server and uses the seat-rejoin flow instead.

const PATH: String = "user://sp_save.json"
const AUTOSAVE_INTERVAL: float = 8.0

# Set by the menu's Continue button; Main's offline boot consumes it.
var pending_resume: bool = false

var _accum: float = 0.0

func _process(delta: float) -> void:
	if Net.mode != Net.Mode.OFFLINE \
			or GameManager.state != GameManager.GameState.RUNNING \
			or GameManager.world == null:
		return
	_accum += delta
	if _accum >= AUTOSAVE_INTERVAL:
		_accum = 0.0
		save_now()

func _ready() -> void:
	# A finished match is not worth resuming.
	EventBus.game_over.connect(func(_winner: int) -> void:
		if Net.mode == Net.Mode.OFFLINE:
			clear())

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

func save_now() -> void:
	var tree: SceneTree = get_tree()
	var units: Array = []
	for node: Node in tree.get_nodes_in_group("units"):
		var unit: UnitBase = node as UnitBase
		if unit != null:
			units.append([String(unit.name), unit.unit_type, unit.player_id,
				unit.global_position.x, unit.global_position.y, unit.current_hp])
	var buildings: Array = []
	for node: Node in tree.get_nodes_in_group("buildings"):
		var building: Building = node as Building
		if building != null:
			buildings.append([String(building.name), building.building_type,
				building.player_id, building.footprint_cells[0].x,
				building.footprint_cells[0].y, building.current_hp,
				building.is_constructed, building.train_queue.duplicate(),
				building.train_progress])
	var animals: Array = []
	for node: Node in tree.get_nodes_in_group("animals"):
		var animal: Animal = node as Animal
		if animal != null:
			animals.append([animal.species, animal.global_position.x,
				animal.global_position.y, animal.current_hp])
	var deltas: Array = []
	for cell: Vector2i in GameManager.world.resource_deltas:
		deltas.append([cell.x, cell.y, GameManager.world.resource_deltas[cell]])

	var camera: Camera2D = tree.current_scene.get_node_or_null("GameCamera")
	var data: Dictionary = {
		"seed": GameManager.map_seed,
		"next_id": GameManager._next_entity_id,
		"player_count": GameManager.player_count,
		"stockpiles": GameManager.stockpiles.map(_stockpile_out),
		"units": units,
		"buildings": buildings,
		"animals": animals,
		"deltas": deltas,
		"explored": _explored_out(GameManager.fog.vision if GameManager.fog != null else null),
		"ai_explored": _explored_out(_enemy_vision()),
		"camera": [camera.global_position.x, camera.global_position.y,
			camera.target_zoom] if camera != null else [0, 0, 1.2],
		"ts": Time.get_unix_time_from_system(),
	}
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))

func load_data() -> Dictionary:
	if not has_save():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}

func _enemy_vision() -> PlayerVision:
	var ai: Node = get_tree().current_scene.get_node_or_null("EnemyAI")
	return ai.vision if ai != null else null

# JSON keys must be strings; ResourceType ints round-trip through them.
func _stockpile_out(stockpile: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for type: int in stockpile:
		out[str(type)] = stockpile[type]
	return out

static func stockpile_in(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in raw:
		out[int(key)] = int(raw[key])
	return out

func _explored_out(vision: PlayerVision) -> Array:
	var out: Array = []
	if vision == null:
		return out
	for cell: Vector2i in vision.explored:
		out.append([cell.x, cell.y])
	return out
