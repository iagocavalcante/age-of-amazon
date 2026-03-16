# scripts/ui/SelectionBoxOverlay.gd
extends Control

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if SelectionManager.is_box_selecting and SelectionManager.selection_rect.size.length() > 5:
		var rect := SelectionManager.selection_rect
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.15), true)
		draw_rect(rect, Color(0.2, 0.8, 0.2, 0.8), false, 1.0)
