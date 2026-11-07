class_name MechGridState
extends RefCounted
## Terrain and occupancy are separate authoritative layers.

enum Terrain { OPEN, ROUGH, OBSTACLE }

const MOBILE_RADIUS: float = 0.22

var _dimensions: Vector2i = Vector2i.ZERO
var _terrain := PackedByteArray()
var _occupancy := PackedInt32Array()
var _pass_through: Dictionary[int, bool] = {}
var _coverage := PackedByteArray()
var _rough_weight: float = 2.0
var _revision: int = 0
var _terrain_revision: int = 0
var _coverage_revision: int = 0
## Last change per occupied/cleared cell; bounded by map size, independently
## consumed by A* and RVO without clearing another consumer's dirty cells.
var _navigation_changes: Dictionary[int, int] = {}
var _playable := PackedByteArray()
var _outline := PackedVector2Array()
var _boundary: Array[Vector2i] = []
var _boundary_sides: Dictionary = {}


func configure(definition: MechMapDefinition) -> void:
	_dimensions = definition.dimensions
	_rough_weight = definition.rough_movement_weight
	_terrain = definition.terrain_cells()
	_playable = definition.playable_cells()
	_outline = definition.outline()
	_cache_boundary()
	_occupancy.resize(_terrain.size())
	_occupancy.fill(0)
	_pass_through.clear()
	_coverage.resize(_terrain.size())
	_coverage.fill(0)
	_revision += 1
	_terrain_revision = _revision
	_coverage_revision = _revision
	_navigation_changes.clear()


func dimensions() -> Vector2i:
	return _dimensions


func playable_cell_count() -> int:
	return _playable.count(1)


func revision() -> int:
	return _revision


func terrain_revision() -> int:
	return _terrain_revision


func coverage_revision() -> int:
	return _coverage_revision


func navigation_changes_since(since: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index: int in _navigation_changes:
		if _navigation_changes[index] > since:
			cells.append(Vector2i(index % _dimensions.x, index / _dimensions.x))
	return cells


## Independent immutable input for background path-data construction. The
## worker never reads the live grid while commands mutate its occupancy.
func navigation_copy() -> MechGridState:
	var copy := MechGridState.new()
	copy._dimensions = _dimensions
	copy._rough_weight = _rough_weight
	copy._terrain = _terrain.duplicate()
	copy._playable = _playable.duplicate()
	copy._outline = _outline.duplicate()
	copy._occupancy = _occupancy.duplicate()
	copy._pass_through = _pass_through.duplicate()
	copy._revision = _revision
	copy._terrain_revision = _terrain_revision
	return copy


func contains(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, _dimensions).has_point(cell) and _playable[_index(cell)] != 0


func point_inside(point: Vector2) -> bool:
	return contains(Vector2i(point.floor())) and Geometry2D.is_point_in_polygon(point, _outline)


func boundary_cells() -> Array[Vector2i]:
	return _boundary.duplicate()


func boundary_side(cell: Vector2i) -> StringName:
	return _boundary_sides.get(cell, &"north")


func _cache_boundary() -> void:
	_boundary.clear()
	_boundary_sides.clear()
	var sides: Array[StringName] = [&"north", &"east", &"south", &"west"]
	for y: int in range(_dimensions.y):
		for x: int in range(_dimensions.x):
			var cell := Vector2i(x, y)
			if not contains(cell):
				continue
			if contains(cell + Vector2i.UP) and contains(cell + Vector2i.RIGHT) and contains(cell + Vector2i.DOWN) and contains(cell + Vector2i.LEFT):
				continue
			_boundary.append(cell)
			var center := Vector2(cell) + Vector2(0.5, 0.5)
			var best: float = INF
			for edge: int in range(_outline.size()):
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, _outline[edge], _outline[(edge + 1) % _outline.size()])
				var distance: float = center.distance_squared_to(closest)
				if distance < best:
					best = distance
					_boundary_sides[cell] = sides[edge]


func terrain_at(cell: Vector2i) -> Terrain:
	if not contains(cell):
		return Terrain.OBSTACLE
	return _terrain[_index(cell)] as Terrain


func occupant_at(cell: Vector2i) -> int:
	return _occupancy[_index(cell)] if contains(cell) else 0


func is_covered(cell: Vector2i) -> bool:
	return contains(cell) and _coverage[_index(cell)] != 0


func footprint_covered(origin: Vector2i, footprint: Vector2i) -> bool:
	for y: int in range(footprint.y):
		for x: int in range(footprint.x):
			if not is_covered(origin + Vector2i(x, y)):
				return false
	return true


func set_core_coverage(origin: Vector2i, footprint: Vector2i, radius: int) -> void:
	_coverage.fill(0)
	if radius >= 0:
		for y: int in range(_dimensions.y):
			for x: int in range(_dimensions.x):
				var dx: int = maxi(maxi(origin.x - x, 0), x - (origin.x + footprint.x - 1))
				var dy: int = maxi(maxi(origin.y - y, 0), y - (origin.y + footprint.y - 1))
				if contains(Vector2i(x, y)) and dx * dx + dy * dy <= radius * radius:
					_coverage[_index(Vector2i(x, y))] = 1
	_revision += 1
	_coverage_revision = _revision


func release(entity_id: int) -> void:
	_revision += 1
	for index: int in range(_occupancy.size()):
		if _occupancy[index] == entity_id:
			_occupancy[index] = 0
			_navigation_changes[index] = _revision
	_pass_through.erase(entity_id)


## Pass-through occupants keep their cells (placement checks and mineral
## bindings still see them) while pathfinding, RVO obstacles and movement
## validation treat the cells as open ground — used by destroyed bases.
func set_pass_through(entity_id: int, enabled: bool) -> void:
	if _pass_through.has(entity_id) == enabled:
		return
	if enabled:
		_pass_through[entity_id] = true
	else:
		_pass_through.erase(entity_id)
	_revision += 1
	for index: int in range(_occupancy.size()):
		if _occupancy[index] == entity_id:
			_navigation_changes[index] = _revision


func is_walkable(cell: Vector2i, include_buildings: bool = true, ignored_occupants: Dictionary = {}) -> bool:
	return contains(cell) and terrain_at(cell) != Terrain.OBSTACLE \
		and (not include_buildings or ignored_occupants.has(occupant_at(cell)) or not _blocks_path(occupant_at(cell)))


func _blocks_path(occupant: int) -> bool:
	return occupant != 0 and not _pass_through.has(occupant)


## True when the cell is held by a pass-through occupant (destroyed base).
func is_pass_through(cell: Vector2i) -> bool:
	var occupant: int = occupant_at(cell)
	return occupant != 0 and _pass_through.has(occupant)


func mobile_position_clear(point: Vector2, ignored_occupants: Dictionary = {}) -> bool:
	if not point_inside(point):
		return false
	# Match the native RVO circle, including at building corners.
	var low := Vector2i((point - Vector2.ONE * MOBILE_RADIUS).floor())
	var high := Vector2i((point + Vector2.ONE * MOBILE_RADIUS).floor())
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			if is_walkable(cell, true, ignored_occupants):
				continue
			var closest: Vector2 = point.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
			if point.distance_squared_to(closest) < MOBILE_RADIUS * MOBILE_RADIUS:
				return false
	return true


func mobile_segment_clear(from: Vector2, to: Vector2, ignored_occupants: Dictionary = {}) -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / 0.1))
	for index: int in range(1, steps + 1):
		if not mobile_position_clear(from.lerp(to, float(index) / steps), ignored_occupants):
			return false
	return true


func movement_weight(cell: Vector2i) -> float:
	return _rough_weight if terrain_at(cell) == Terrain.ROUGH else 1.0


func terrain_line_clear(from: Vector2, to: Vector2, reveal_blocker: bool = false) -> bool:
	# Supercover traversal: diagonal cracks between rocks never leak vision.
	# A visibility ray reveals its first blocking tile; combat rays cannot hit
	# through it. Buildings and rough terrain do not block either kind of ray.
	var cell := Vector2i(from.floor())
	var goal := Vector2i(to.floor())
	if not contains(cell) or not contains(goal):
		return false
	var delta: Vector2 = to - from
	var step := Vector2i(signi(goal.x - cell.x), signi(goal.y - cell.y))
	var stride := Vector2(INF if step.x == 0 else absf(1.0 / delta.x), INF if step.y == 0 else absf(1.0 / delta.y))
	var boundary := Vector2(cell) + Vector2(1 if step.x > 0 else 0, 1 if step.y > 0 else 0)
	var crossing := Vector2(INF if step.x == 0 else (boundary.x - from.x) / delta.x, INF if step.y == 0 else (boundary.y - from.y) / delta.y)
	while true:
		if cell == goal:
			return reveal_blocker or terrain_at(cell) != Terrain.OBSTACLE
		if terrain_at(cell) == Terrain.OBSTACLE:
			return false
		if is_equal_approx(crossing.x, crossing.y):
			if terrain_at(cell + Vector2i(step.x, 0)) == Terrain.OBSTACLE or terrain_at(cell + Vector2i(0, step.y)) == Terrain.OBSTACLE:
				return false
			cell += step
			crossing += stride
		elif crossing.x < crossing.y:
			cell.x += step.x
			crossing.x += stride.x
		else:
			cell.y += step.y
			crossing.y += stride.y
	return false


func inspect_cell(cell: Vector2i) -> Dictionary:
	if not contains(cell):
		return {"cell": cell, "inside": false, "terrain_name": "地图外", "reason": "超出地图边界"}
	var terrain: Terrain = terrain_at(cell)
	var terrain_name: String = ["开阔地", "崎岖地", "障碍地"][terrain]
	var reason: String = terrain_build_error(cell)
	if reason.is_empty() and occupant_at(cell) != 0:
		reason = "已有建筑占用"
	return {"cell": cell, "inside": true, "terrain": terrain, "terrain_name": terrain_name,
		"occupied_by": occupant_at(cell), "walkable": is_walkable(cell),
		"movement_weight": movement_weight(cell), "covered": is_covered(cell), "reason": reason}


func preview_footprint(origin: Vector2i, footprint: Vector2i) -> Dictionary:
	var cells: Array[Dictionary] = []
	var bounds := Rect2i(Vector2i.ZERO, _dimensions)
	var reason: String = ""
	if footprint.x < 1 or footprint.y < 1 or footprint.x > 16 or footprint.y > 16:
		return {"ok": false, "reason": "占地尺寸无效", "cells": cells, "origin": origin, "footprint": footprint}
	if not bounds.encloses(Rect2i(origin, footprint)):
		reason = "超出地图边界"
	# Global ordering: all terrain errors precede all overlap errors.
	for y: int in range(footprint.y):
		for x: int in range(footprint.x):
			var cell: Vector2i = origin + Vector2i(x, y)
			var cell_reason: String = terrain_build_error(cell)
			if reason.is_empty() and not cell_reason.is_empty():
				reason = cell_reason
			if cell_reason.is_empty() and occupant_at(cell) != 0:
				cell_reason = "已有建筑占用"
			cells.append({"cell": cell, "ok": cell_reason.is_empty(), "reason": cell_reason})
	if reason.is_empty():
		for cell_info: Dictionary in cells:
			if not cell_info["ok"]:
				reason = cell_info["reason"]
				break
	return {"ok": reason.is_empty(), "reason": reason, "cells": cells, "origin": origin, "footprint": footprint}


func try_occupy(entity_id: int, origin: Vector2i, footprint: Vector2i) -> Dictionary:
	if entity_id <= 0:
		return {"ok": false, "reason": "建筑实体编号无效"}
	var result: Dictionary = preview_footprint(origin, footprint)
	if not result["ok"]:
		return result
	_revision += 1
	for cell_info: Dictionary in result["cells"]:
		var index: int = _index(cell_info["cell"])
		_occupancy[index] = entity_id
		_navigation_changes[index] = _revision
	return result


func snapshot() -> Dictionary:
	return {"dimensions": _dimensions, "terrain": _terrain.duplicate(),
		"playable": _playable.duplicate(), "outline": _outline.duplicate(),
		"occupancy": _occupancy.duplicate(), "coverage": _coverage.duplicate(),
		"rough_weight": _rough_weight, "revision": _revision}


func terrain_build_error(cell: Vector2i) -> String:
	if not contains(cell):
		return "超出地图边界"
	match terrain_at(cell):
		Terrain.ROUGH:
			return "崎岖地不可建造"
		Terrain.OBSTACLE:
			return "障碍地不可建造"
	return ""


func _index(cell: Vector2i) -> int:
	return cell.y * _dimensions.x + cell.x
