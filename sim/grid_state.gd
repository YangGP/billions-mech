class_name MechGridState
extends RefCounted
## Terrain and occupancy are separate authoritative layers.

enum Terrain { OPEN, ROUGH, OBSTACLE }

const MOBILE_RADIUS: float = 0.22

var _dimensions: Vector2i = Vector2i.ZERO
var _terrain := PackedByteArray()
var _occupancy := PackedInt32Array()
var _coverage := PackedByteArray()
var _rough_weight: float = 2.0
var _revision: int = 0


func configure(definition: MechMapDefinition) -> void:
	_dimensions = definition.dimensions
	_rough_weight = definition.rough_movement_weight
	_terrain = definition.terrain_cells()
	_occupancy.resize(_terrain.size())
	_occupancy.fill(0)
	_coverage.resize(_terrain.size())
	_coverage.fill(0)
	_revision += 1


func dimensions() -> Vector2i:
	return _dimensions


func revision() -> int:
	return _revision


func contains(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, _dimensions).has_point(cell)


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
				if dx * dx + dy * dy <= radius * radius:
					_coverage[_index(Vector2i(x, y))] = 1
	_revision += 1


func release(entity_id: int) -> void:
	for index: int in range(_occupancy.size()):
		if _occupancy[index] == entity_id:
			_occupancy[index] = 0
	_revision += 1


func is_walkable(cell: Vector2i, include_buildings: bool = true) -> bool:
	return contains(cell) and terrain_at(cell) != Terrain.OBSTACLE and (not include_buildings or occupant_at(cell) == 0)


func mobile_position_clear(point: Vector2) -> bool:
	# Match the native RVO circle, including at building corners.
	var low := Vector2i((point - Vector2.ONE * MOBILE_RADIUS).floor())
	var high := Vector2i((point + Vector2.ONE * MOBILE_RADIUS).floor())
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			if is_walkable(cell):
				continue
			var closest: Vector2 = point.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
			if point.distance_squared_to(closest) < MOBILE_RADIUS * MOBILE_RADIUS:
				return false
	return true


func mobile_segment_clear(from: Vector2, to: Vector2) -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / 0.1))
	for index: int in range(1, steps + 1):
		if not mobile_position_clear(from.lerp(to, float(index) / steps)):
			return false
	return true


func movement_weight(cell: Vector2i) -> float:
	return _rough_weight if terrain_at(cell) == Terrain.ROUGH else 1.0


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
	for cell_info: Dictionary in result["cells"]:
		_occupancy[_index(cell_info["cell"])] = entity_id
	_revision += 1
	return result


func snapshot() -> Dictionary:
	return {"dimensions": _dimensions, "terrain": _terrain.duplicate(),
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
