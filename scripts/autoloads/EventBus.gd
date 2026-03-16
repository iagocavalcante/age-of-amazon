# scripts/autoloads/EventBus.gd
extends Node

# Unit signals
signal unit_selected(unit: Node2D)
signal unit_deselected(unit: Node2D)
signal units_commanded_move(units: Array[Node2D], target: Vector2)
signal selection_cleared()

# Map signals
signal map_generated(width: int, height: int)

# Game signals
signal game_state_changed(new_state: String)
