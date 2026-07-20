# scripts/autoloads/CommandRouter.gd
extends Node

# The single seam every gameplay order flows through, as plain data:
#   {type:"move",   player_id, actor_names: Array, target: Vector2}
#   {type:"gather", player_id, actor_names: Array, cell: Vector2i}
#   {type:"attack", player_id, actor_names: Array, target_name: String}
#   {type:"train",  player_id, building_name: String, unit_type: String}
# Offline the router is its own authority. In multiplayer, clients forward
# commands to the server, which validates and executes the same way.

func submit(command: Dictionary) -> void:
	if Net.mode == Net.Mode.CLIENT:
		_submit_to_server.rpc_id(1, command)
	else:
		_validate_and_execute(command)

@rpc("any_peer", "call_remote", "reliable")
func _submit_to_server(command: Dictionary) -> void:
	if Net.mode != Net.Mode.SERVER:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not Net.peer_players.has(sender):
		return
	# Identity comes from the connection, never from the payload — a client
	# cannot command another tribe's units no matter what it sends.
	command["player_id"] = Net.peer_players[sender]
	if OS.is_stdout_verbose():
		print("[cmd] p%s %s" % [command["player_id"], command.get("type", "?")])
	_validate_and_execute(command)

func _validate_and_execute(command: Dictionary) -> void:
	match command.get("type", ""):
		"move":
			_exec_move(command)
		"gather":
			_exec_gather(command)
		"attack":
			_exec_attack(command)
		"train":
			_exec_train(command)
		"place":
			_exec_place(command)
		"rally":
			_exec_rally(command)
		"attack_move":
			_exec_attack_move(command)
		"stop":
			_exec_stop(command)
		"build":
			_exec_build(command)
		_:
			push_warning("CommandRouter: unknown command %s" % [command])

# Actors resolve by name from the issuing player's group — ownership check
# and dangling-reference filtering in one step.
func _exec_stop(command: Dictionary) -> void:
	for unit: UnitBase in _resolve_actors(command):
		unit.stop_order()

func _resolve_actors(command: Dictionary) -> Array[UnitBase]:
	var owned: Array[UnitBase] = []
	var wanted: Array = command.get("actor_names", [])
	for node: Node in get_tree().get_nodes_in_group("player_%d" % int(command["player_id"])):
		var unit: UnitBase = node as UnitBase
		if unit != null and String(unit.name) in wanted:
			owned.append(unit)
	return owned

func _resolve_target(target_name: String) -> Node2D:
	for group: String in ["units", "buildings", "animals"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if String(node.name) == target_name:
				return node as Node2D
	return null

func _exec_move(command: Dictionary) -> void:
	var actors: Array[UnitBase] = _resolve_actors(command)
	if actors.is_empty():
		return
	var target: Vector2 = command["target"]
	var cells: Array[Vector2i] = []
	if GameManager.pathfinder != null:
		cells = GameManager.pathfinder.formation_cells(target, actors.size())
	for i in range(actors.size()):
		var spot: Vector2 = target
		if i < cells.size():
			spot = Constants.grid_to_world(cells[i].x, cells[i].y)
		actors[i].move_to(spot)

func _exec_gather(command: Dictionary) -> void:
	var mover_names: Array = []
	for unit: UnitBase in _resolve_actors(command):
		if unit.can_gather:
			unit.command_gather(command["cell"])
		else:
			mover_names.append(String(unit.name))
	if not mover_names.is_empty():
		var cell: Vector2i = command["cell"]
		_exec_move({
			"type": "move", "player_id": command["player_id"],
			"actor_names": mover_names,
			"target": Constants.grid_to_world(cell.x, cell.y),
		})

func _exec_attack(command: Dictionary) -> void:
	var target: Node2D = _resolve_target(command["target_name"])
	if target == null:
		return
	# You cannot attack your own things (animals carry no player_id and stay
	# attackable — `get()` returns null for them).
	var target_owner: Variant = target.get("player_id")
	if target_owner != null and int(target_owner) == int(command["player_id"]):
		return
	for unit: UnitBase in _resolve_actors(command):
		unit.command_attack(target)

func _exec_rally(command: Dictionary) -> void:
	var building: Building = _resolve_target(command.get("building_name", "")) as Building
	if building == null or building.player_id != int(command["player_id"]):
		return
	building.rally_cell = command["cell"]

# March toward a point, engaging anything hostile met on the way.
func _exec_attack_move(command: Dictionary) -> void:
	var target: Vector2 = command["target"]
	var cells: Array[Vector2i] = []
	var actors: Array[UnitBase] = _resolve_actors(command)
	if GameManager.pathfinder != null:
		cells = GameManager.pathfinder.formation_cells(target, actors.size())
	for i in range(actors.size()):
		var spot: Vector2 = target
		if i < cells.size():
			spot = Constants.grid_to_world(cells[i].x, cells[i].y)
		actors[i].command_attack_move(spot)

# Place a construction site: pay the cost, occupy the cells, then send the
# issuing villagers to build it. Every rule a client could bend is checked
# here, on the authority.
func _exec_place(command: Dictionary) -> void:
	var building_type: String = command.get("building_type", "")
	var def: Dictionary = Constants.BUILDING_DEFS.get(building_type, {})
	if not def.has("cost"):
		return  # unknown type, or one players may not construct
	var player_id: int = int(command["player_id"])
	var base_cell: Vector2i = command["cell"]

	var footprint: Vector2i = def["footprint"]
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var cell: Vector2i = base_cell + Vector2i(dx, dy)
			if not GameManager.world.is_buildable(cell):
				return
			if GameManager.world.building_at(cell) != null:
				return
			if not GameManager.world.get_resource_at(cell).is_empty():
				return
			if not GameManager.has_explored(player_id, cell):
				return
	if not GameManager.spend(player_id, def["cost"]):
		return

	var containers: Array = get_tree().get_nodes_in_group("building_container")
	if containers.is_empty():
		return
	var site: Building = Building.new()
	site.name = GameManager.claim_entity_name("B")
	site.setup(building_type, player_id, base_cell, false)
	containers[0].add_child(site)

	_send_builders(command, site)

func _exec_build(command: Dictionary) -> void:
	var site: Building = _resolve_target(command.get("building_name", "")) as Building
	if site == null or site.player_id != int(command["player_id"]) \
			or site.current_hp >= site.max_hp:
		return
	_send_builders(command, site)

func _send_builders(command: Dictionary, site: Building) -> void:
	for unit: UnitBase in _resolve_actors(command):
		if unit.can_gather:
			unit.command_build(site)

func _exec_train(command: Dictionary) -> void:
	var building: Building = _resolve_target(command["building_name"]) as Building
	if building == null or building.player_id != int(command["player_id"]):
		return
	building.queue_train(command["unit_type"])
