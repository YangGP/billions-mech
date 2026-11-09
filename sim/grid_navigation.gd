class_name MechGridNavigation
extends RefCounted
## 用原生加权 A* 选出行进走廊。跟随者拿到可直接到达的最远航点，
## 因此开阔地带以直线穿越。

var _navigation := AStarGrid2D.new()
var _grid: MechGridState
## 寻路时视为可通行的占用者（例如正在移动的自身）。
var _ignored_occupants: Dictionary = {}
## 友军可穿越模式：被网格标记为可穿越的占用者不再阻挡寻路。
var _friendly_pass: bool = false
## 上次同步的网格版本号，用于增量更新。
var _revision: int = -1
var _terrain_revision: int = -1


func set_friendly_pass(enabled: bool) -> void:
	_friendly_pass = enabled


## 重建 A* 网格。换网格、地形版本变化或忽略占用表变化时全量刷新，
## 否则只更新自上次版本以来的脏格子。
func rebuild(grid: MechGridState, ignored_occupants: Dictionary = {}) -> void:
	var full_refresh: bool = _grid != grid or _terrain_revision != grid.terrain_revision() or _ignored_occupants != ignored_occupants
	_grid = grid
	_ignored_occupants = ignored_occupants.duplicate()
	if full_refresh:
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
				_navigation.set_point_solid(cell, not grid.is_walkable(cell, true, _ignored_occupants, _friendly_pass))
				_navigation.set_point_weight_scale(cell, grid.movement_weight(cell))
	else:
		# set_point_solid 会原地更新原生网格；update() 会清空全部点数据，
		# 逼得每段墙都引发一次全图重写。
		for cell: Vector2i in grid.navigation_changes_since(_revision):
			_navigation.set_point_solid(cell, not grid.is_walkable(cell, true, _ignored_occupants, _friendly_pass))
	_revision = grid.revision()
	_terrain_revision = grid.terrain_revision()


## 以目标格中心为目的地的寻路便捷封装。
func find_path(from: Vector2, target_cell: Vector2i) -> PackedVector2Array:
	return find_path_to_point(from, Vector2(target_cell) + Vector2(0.5, 0.5))


## 求解从 from 到 target 的路径。目标点不可站立时返回空数组；
## 返回的航点序列不含起点，末点精确等于 target 而非格子中心。
func find_path_to_point(from: Vector2, target: Vector2) -> PackedVector2Array:
	if not from.is_finite() or not target.is_finite() or not _grid.mobile_position_clear(target, _ignored_occupants, _friendly_pass):
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
	# 末点是实际的指令目的地，而不是隐式吸附到格子中心。
	if not points[-1].is_equal_approx(target):
		if not segment_clear(points[-1], target):
			return PackedVector2Array()
		points.append(target)
	# 起点能直视第二个航点时提前丢弃第一个航点，尽早拉直。
	if points.size() > 2 and segment_clear(from, points[2]):
		points.remove_at(1)
	points = _straighten_path(points)
	if points.size() > 1:
		points.remove_at(0)
	return points


## 两点间是否可直线通行（含身体间隙检查）。
func segment_clear(from: Vector2, to: Vector2) -> bool:
	return _grid.mobile_segment_clear(from, to, _ignored_occupants, _friendly_pass)


## 在不增加总代价的前提下贪心拉直路径。
func _straighten_path(points: PackedVector2Array) -> PackedVector2Array:
	# 零容差只移除共线点；原生 RDP 不了解身体间隙、地形权重与障碍，
	# 因此不能由它来挑选捷径。
	var route: PackedVector2Array = NavigationServer2D.simplify_path(points, 0.0)
	if route.size() <= 2:
		return route
	var costs := PackedFloat64Array([0.0])
	for index: int in range(1, route.size()):
		costs.append(costs[-1] + _segment_cost(route[index - 1], route[index]))
	var result := PackedVector2Array([route[0]])
	var anchor: int = 0
	while anchor < route.size() - 1:
		# 从最远点回退，取第一个被允许的捷径目标。
		var next: int = route.size() - 1
		while next > anchor + 1 and not _shortcut_allowed(route[anchor], route[next], costs[next] - costs[anchor]):
			next -= 1
		result.append(route[next])
		anchor = next
	return result


## 捷径须同时满足：可直线通行，且代价不超过原路（含 0.01 容差）。
func _shortcut_allowed(from: Vector2, to: Vector2, budget: float) -> bool:
	return segment_clear(from, to) and _segment_cost(from, to) <= budget + 0.01


## 估算一段的行程代价：按 0.1 格步长采样地形权重取平均。
func _segment_cost(from: Vector2, to: Vector2) -> float:
	# 用与原生 A* 相同的地形权重比较行程时间。
	var length: float = from.distance_to(to)
	var steps: int = maxi(1, ceili(length / 0.1))
	var weight: float = 0.0
	for index: int in range(steps):
		var point: Vector2 = from.lerp(to, (index + 0.5) / float(steps))
		weight += _grid.movement_weight(Vector2i(point.floor()))
	return length * weight / float(steps)
