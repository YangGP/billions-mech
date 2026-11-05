class_name MechGridNavigation
extends RefCounted
## Reuses Godot AStarGrid2D for the probe/player path. Not a horde flow field.

var _navigation := AStarGrid2D.new()
var _grid: MechGridState


func rebuild(grid: MechGridState) -> void:
	_grid = grid
	_navigation.region = Rect2i(Vector2i.ZERO, grid.dimensions())
	_navigation.cell_size = Vector2.ONE
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_navigation.jumping_enabled = false
	_navigation.update()
	for y: int in range(grid.dimensions().y):
		for x: int in range(grid.dimensions().x):
			var cell := Vector2i(x, y)
			_navigation.set_point_solid(cell, not grid.is_walkable(cell))
			_navigation.set_point_weight_scale(cell, grid.movement_weight(cell))


func find_path(from: Vector2, target_cell: Vector2i) -> PackedVector2Array:
	var cells: Array[Vector2i] = _navigation.get_id_path(Vector2i(from.floor()), target_cell)
	var points := PackedVector2Array()
	for cell: Vector2i in cells:
		points.append(Vector2(cell) + Vector2(0.5, 0.5))
	# Replanning must not send a moving unit back to the start-cell centre.
	# Retain that centre when it is needed to clear a building corner.
	if points.size() > 1 and _grid.mobile_segment_clear(from, points[1]):
		points.remove_at(0)
	return points
