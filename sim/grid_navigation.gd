class_name MechGridNavigation
extends RefCounted
## Native weighted A* selects the corridor. The follower receives the furthest
## directly reachable waypoints, so free ground is crossed in a straight line.

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
	return find_path_to_point(from, Vector2(target_cell) + Vector2(0.5, 0.5))


func find_path_to_point(from: Vector2, target: Vector2) -> PackedVector2Array:
	if not from.is_finite() or not target.is_finite() or not _grid.mobile_position_clear(target):
		return PackedVector2Array()
	var target_cell := Vector2i(target.floor())
	var cells: Array[Vector2i] = _navigation.get_id_path(Vector2i(from.floor()), target_cell)
	if cells.is_empty():
		return PackedVector2Array()
	var points := PackedVector2Array([from])
	for cell: Vector2i in cells:
		var point := Vector2(cell) + Vector2(0.5, 0.5)
		if not points[-1].is_equal_approx(point):
			points.append(point)
	# The final point is the actual command destination, not an implicit snap.
	if not points[-1].is_equal_approx(target):
		if not _grid.mobile_segment_clear(points[-1], target):
			return PackedVector2Array()
		points.append(target)
	if points.size() > 2 and _grid.mobile_segment_clear(from, points[2]):
		points.remove_at(1)
	points = _straighten_path(points)
	if points.size() > 1:
		points.remove_at(0)
	return points


func _straighten_path(points: PackedVector2Array) -> PackedVector2Array:
	# Zero epsilon only removes collinear points; native RDP does not know about
	# body clearance, terrain weights or obstacles, so it cannot select shortcuts.
	var route: PackedVector2Array = NavigationServer2D.simplify_path(points, 0.0)
	if route.size() <= 2:
		return route
	var costs := PackedFloat64Array([0.0])
	for index: int in range(1, route.size()):
		costs.append(costs[-1] + _segment_cost(route[index - 1], route[index]))
	var result := PackedVector2Array([route[0]])
	var anchor: int = 0
	while anchor < route.size() - 1:
		var next: int = route.size() - 1
		while next > anchor + 1 and not _shortcut_allowed(route[anchor], route[next], costs[next] - costs[anchor]):
			next -= 1
		result.append(route[next])
		anchor = next
	return result


func _shortcut_allowed(from: Vector2, to: Vector2, budget: float) -> bool:
	return _grid.mobile_segment_clear(from, to) and _segment_cost(from, to) <= budget + 0.01


func _segment_cost(from: Vector2, to: Vector2) -> float:
	# Compare travel time using the same terrain weights as the native A*.
	var length: float = from.distance_to(to)
	var steps: int = maxi(1, ceili(length / 0.1))
	var weight: float = 0.0
	for index: int in range(steps):
		var point: Vector2 = from.lerp(to, (index + 0.5) / float(steps))
		weight += _grid.movement_weight(Vector2i(point.floor()))
	return length * weight / float(steps)
