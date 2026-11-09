class_name MechGridState
extends RefCounted
## 地形与占用是两个相互独立的权威层。

enum Terrain { OPEN, ROUGH, OBSTACLE }

## 移动实体（机器人）的碰撞圆半径，须与原生 RVO 圆保持一致。
const MOBILE_RADIUS: float = 0.22

var _dimensions: Vector2i = Vector2i.ZERO
var _terrain := PackedByteArray()
var _occupancy := PackedInt32Array()
var _pass_through: Dictionary[int, bool] = {}
## 仅玩家可用的穿越表（闸门类）；敌方路径校验不得使用它。
var _friendly_pass: Dictionary[int, bool] = {}
var _coverage := PackedByteArray()
## 显式环境层：水面同时也是障碍地形，风区不是。
var _wind := PackedByteArray()
var _water := PackedByteArray()
## 逐格覆盖变更标记，与占用层修订号相互独立。
var _coverage_changes: Dictionary[int, int] = {}
var _rough_weight: float = 2.0
var _revision: int = 0
var _terrain_revision: int = 0
var _coverage_revision: int = 0
## 逐格占用变更序号；上限为地图尺寸，A* 与 RVO 各自独立消费，
## 互不清除对方的脏格标记。
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
	_wind = definition.wind_mask()
	_water = definition.water_mask()
	_outline = definition.outline()
	_cache_boundary()
	_occupancy.resize(_terrain.size())
	_occupancy.fill(0)
	_pass_through.clear()
	_friendly_pass.clear()
	_coverage.resize(_terrain.size())
	_coverage.fill(0)
	_coverage_changes.clear()
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


func coverage_changes_since(since: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index: int in _coverage_changes:
		if _coverage_changes[index] > since:
			cells.append(Vector2i(index % _dimensions.x, index / _dimensions.x))
	return cells


func navigation_changes_since(since: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index: int in _navigation_changes:
		if _navigation_changes[index] > since:
			cells.append(Vector2i(index % _dimensions.x, index / _dimensions.x))
	return cells


## 供后台路径数据构建使用的独立不可变副本：
## 工作线程绝不读取活网格，避免与命令写入占用层产生竞争。
func navigation_copy(ignore_rough: bool = false) -> MechGridState:
	var copy := MechGridState.new()
	copy._dimensions = _dimensions
	copy._rough_weight = 1.0 if ignore_rough else _rough_weight
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


func is_wind(cell: Vector2i) -> bool:
	return contains(cell) and _wind[_index(cell)] != 0


func is_water(cell: Vector2i) -> bool:
	return contains(cell) and _water[_index(cell)] != 0


func footprint_covered(origin: Vector2i, footprint: Vector2i) -> bool:
	for y: int in range(footprint.y):
		for x: int in range(footprint.x):
			if not is_covered(origin + Vector2i(x, y)):
				return false
	return true


## 旧版单源覆盖，仅供设置校验器与既有视野夹具使用；
## 运行时覆盖一律经 recompute_coverage() 计算。
func set_core_coverage(origin: Vector2i, footprint: Vector2i, radius: int) -> void:
	var mask := PackedByteArray()
	mask.resize(_coverage.size())
	mask.fill(0)
	if radius >= 0:
		_stamp_source(mask, origin, footprint, radius)
	_apply_coverage_mask(mask)
	_revision += 1


## 以主脑为根的连通覆盖。中继只有当自身格子已被根或另一连通中继覆盖时
## 才扩展覆盖；孤立回路与失连中继绝不自行供电。
func recompute_coverage(buildings: Array[MechBuildingState]) -> Array[Vector2i]:
	var root: MechBuildingState = null
	var relays: Array[MechBuildingState] = []
	for building: MechBuildingState in buildings:
		if building.hp <= 0 or building.phase != MechBuildingState.Phase.OPERATING:
			continue
		if building.definition == null or building.definition.coverage_radius <= 0:
			continue
		if building.definition.is_core:
			root = building
		else:
			relays.append(building)
	var mask := PackedByteArray()
	mask.resize(_coverage.size())
	mask.fill(0)
	if root != null:
		_stamp_source(mask, root.origin, root.definition.footprint, root.definition.coverage_radius)
		var pending: Array[MechBuildingState] = relays.duplicate()
		var grew: bool = true
		while grew:
			grew = false
			for index: int in range(pending.size() - 1, -1, -1):
				var relay: MechBuildingState = pending[index]
				if not contains(relay.origin) or mask[_index(relay.origin)] == 0:
					continue
				_stamp_source(mask, relay.origin, relay.definition.footprint, relay.definition.coverage_radius)
				pending.remove_at(index)
				grew = true
	return _apply_coverage_mask(mask)


func _stamp_source(mask: PackedByteArray, origin: Vector2i, footprint: Vector2i, radius: int) -> void:
	if radius < 0:
		return
	var low := (origin - Vector2i(radius, radius)).max(Vector2i.ZERO)
	var high := (origin + footprint - Vector2i.ONE + Vector2i(radius, radius)).min(_dimensions - Vector2i.ONE)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var dx: int = maxi(maxi(origin.x - x, 0), x - (origin.x + footprint.x - 1))
			var dy: int = maxi(maxi(origin.y - y, 0), y - (origin.y + footprint.y - 1))
			if dx * dx + dy * dy <= radius * radius:
				mask[_index(Vector2i(x, y))] = 1


func _apply_coverage_mask(mask: PackedByteArray) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	var next_revision: int = _coverage_revision + 1
	for index: int in range(_coverage.size()):
		if mask[index] == _coverage[index]:
			continue
		_coverage[index] = mask[index]
		_coverage_changes[index] = next_revision
		changed.append(Vector2i(index % _dimensions.x, index / _dimensions.x))
	if not changed.is_empty():
		_coverage_revision = next_revision
	return changed


func release(entity_id: int) -> void:
	_revision += 1
	for index: int in range(_occupancy.size()):
		if _occupancy[index] == entity_id:
			_occupancy[index] = 0
			_navigation_changes[index] = _revision
	_pass_through.erase(entity_id)
	_friendly_pass.erase(entity_id)


## 穿越占用者保留其格子（放置校验与矿点绑定仍然可见），
## 而寻路、RVO 障碍与移动校验把格子视为空地——用于被摧毁的基座。
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


func is_walkable(cell: Vector2i, include_buildings: bool = true, ignored_occupants: Dictionary = {}, friendly_pass: bool = false) -> bool:
	return contains(cell) and terrain_at(cell) != Terrain.OBSTACLE \
		and (not include_buildings or ignored_occupants.has(occupant_at(cell))
			or not _blocks_path(occupant_at(cell))
			or (friendly_pass and _friendly_pass.has(occupant_at(cell))))


func set_friendly_pass(entity_id: int, enabled: bool) -> void:
	if _friendly_pass.has(entity_id) == enabled:
		return
	if enabled:
		_friendly_pass[entity_id] = true
	else:
		_friendly_pass.erase(entity_id)
	_revision += 1
	for index: int in range(_occupancy.size()):
		if _occupancy[index] == entity_id:
			_navigation_changes[index] = _revision


func _blocks_path(occupant: int) -> bool:
	return occupant != 0 and not _pass_through.has(occupant)


## 该格是否被穿越占用者持有（被摧毁的基座）。
func is_pass_through(cell: Vector2i) -> bool:
	var occupant: int = occupant_at(cell)
	return occupant != 0 and _pass_through.has(occupant)


func mobile_position_clear(point: Vector2, ignored_occupants: Dictionary = {}, friendly_pass: bool = false) -> bool:
	if not point_inside(point):
		return false
	# 与原生 RVO 圆保持一致，含建筑拐角处的判定。
	var low := Vector2i((point - Vector2.ONE * MOBILE_RADIUS).floor())
	var high := Vector2i((point + Vector2.ONE * MOBILE_RADIUS).floor())
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			if is_walkable(cell, true, ignored_occupants, friendly_pass):
				continue
			var closest: Vector2 = point.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
			if point.distance_squared_to(closest) < MOBILE_RADIUS * MOBILE_RADIUS:
				return false
	return true


func mobile_segment_clear(from: Vector2, to: Vector2, ignored_occupants: Dictionary = {}, friendly_pass: bool = false) -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / 0.1))
	for index: int in range(1, steps + 1):
		if not mobile_position_clear(from.lerp(to, float(index) / steps), ignored_occupants, friendly_pass):
			return false
	return true


func movement_weight(cell: Vector2i) -> float:
	return _rough_weight if terrain_at(cell) == Terrain.ROUGH else 1.0


func terrain_line_clear(from: Vector2, to: Vector2, reveal_blocker: bool = false) -> bool:
	# 超覆盖遍历：岩石间的对角缝隙绝不漏视野。视线束照亮其首个阻挡格；
	# 战斗射线无法穿透该格。建筑与崎岖地形不阻挡任何一类射线。
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
		"movement_weight": movement_weight(cell), "covered": is_covered(cell),
		"wind": is_wind(cell), "water": is_water(cell), "reason": reason}


func preview_footprint(origin: Vector2i, footprint: Vector2i) -> Dictionary:
	var cells: Array[Dictionary] = []
	var bounds := Rect2i(Vector2i.ZERO, _dimensions)
	var reason: String = ""
	if footprint.x < 1 or footprint.y < 1 or footprint.x > 16 or footprint.y > 16:
		return {"ok": false, "reason": "占地尺寸无效", "cells": cells, "origin": origin, "footprint": footprint}
	if not bounds.encloses(Rect2i(origin, footprint)):
		reason = "超出地图边界"
	# 全局排序：所有地形错误优先于所有占用冲突错误。
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
		"wind": _wind.duplicate(), "water": _water.duplicate(),
		"rough_weight": _rough_weight, "revision": _revision}


func terrain_build_error(cell: Vector2i) -> String:
	if not contains(cell):
		return "超出地图边界"
	if is_water(cell):
		return "水域不可建造"
	match terrain_at(cell):
		Terrain.ROUGH:
			return "崎岖地不可建造"
		Terrain.OBSTACLE:
			return "障碍地不可建造"
	return ""


func _index(cell: Vector2i) -> int:
	return cell.y * _dimensions.x + cell.x
