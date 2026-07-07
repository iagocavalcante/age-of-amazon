# scripts/autoloads/EventBus.gd
extends Node

# Unit signals
signal unit_selected(unit: Node2D)
signal unit_deselected(unit: Node2D)
signal units_commanded_move(units: Array[Node2D], target: Vector2)
signal selection_cleared()
signal selection_changed()
signal unit_died(unit: Node2D)

# Building signals
signal building_selected(building: Node2D)
signal building_damaged(building: Node2D, attacker: Node2D)
signal building_destroyed(building: Node2D)
signal training_queued(building: Node2D, unit_type: String)
signal training_completed(building: Node2D, unit_type: String)

# Economy signals
signal resources_changed(player_id: int)
signal population_changed(player_id: int)

# World signals
signal world_ready()

# Game signals
signal game_state_changed(new_state: String)
signal game_over(winner_player_id: int)
