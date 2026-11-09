class_name MechVisionSystem
extends RefCounted
## 视野与战争迷雾。探索覆盖每个视野源的半径，不受遮挡影响；
## 实时可视野额外要求地形通视（LOS）。通视脚印按视野源缓存，
## 格内移动不会重建可见性，也不会重新上传迷雾纹理。

enum State { UNEXPLORED, EXPLORED, VISIBLE }

var _dimensions := Vector2i.ZERO
## 当前可见性状态（探索 ∪ 实时可视野）。
var _states := PackedByteArray()
## 已探索记录，单调递增，只增不减。
var _explored := PackedByteArray()
var _sources: Dictionary = {}
var _footprints: Dictionary = {}
var _grid_revision: int = -1
var _revision: int = 0
var _explored_revision: int = 0
var _explored_changed: bool = false
var _explored_changes: Array[Vector2i] = []


## 按网格尺寸重置全部视野状态。
func reset(grid: MechGridState) -> void:
	_dimensions = grid.dimensions()
	_states.resize(_dimensions.x * _dimensions.y)
	_states.fill(State.UNEXPLORED)
	_explored = _states.duplicate()
	_sources.clear()
	_footprints.clear()
	_grid_revision = -1
	_revision += 1
	_explored_revision += 1
	_explored_changed = false
	_explored_changes.clear()


func explored_revision() -> int:
	return _explored_revision


## 取走自上次消费以来新探索的格子；消费后清空，调用方独占这批变更。
func consume_explored_changes() -> Array[Vector2i]:
	var result: Array[Vector2i] = _explored_changes.duplicate()
	_explored_changes.clear()
	return result


## 汇总所有视野源（运行中的建筑 + 玩家实体）并重建可见性。
## 返回本 tick 可见性是否发生变化（决定是否上传迷雾纹理）。
func update(grid: MechGridState, registry: MechEntityRegistry, buildings: Array[MechBuildingState], probe_radius: float) -> bool:
	var sources: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp > 0 and building.operating() and building.definition.sight_radius > 0.0:
			var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
			sources[building.entity_id] = Vector3(center.x, center.y, building.definition.sight_radius)
	for entity: MechEntityState in registry.all():
		if entity.team != 1 or entity.garrisoned:
			continue
		var radius: float = 0.0
		if entity.unit_definition != null and entity.hp > 0:
			radius = entity.unit_definition.sight_radius
		elif entity.kind == &"probe":
			radius = probe_radius
		if radius > 0.0:
			var center: Vector2 = entity.position.floor() + Vector2(0.5, 0.5)
			sources[entity.entity_id] = Vector3(center.x, center.y, radius)
	if sources == _sources and _grid_revision == grid.coverage_revision():
		return false
	_explored_changed = false
	if _grid_revision != grid.coverage_revision():
		if _grid_revision < 0:
			for y: int in range(_dimensions.y):
				for x: int in range(_dimensions.x):
					if grid.is_covered(Vector2i(x, y)):
						_mark_explored(y * _dimensions.x + x)
		else:
			for cell: Vector2i in grid.coverage_changes_since(_grid_revision):
				if grid.is_covered(cell):
					_mark_explored(cell.y * _dimensions.x + cell.x)
	var footprints: Dictionary = {}
	for id: int in sources:
		var source: Vector3 = sources[id]
		var cells: PackedInt32Array
		if _sources.get(id) == source:
			cells = _footprints[id]
		else:
			cells = _cast_source(grid, Vector2(source.x, source.y), source.z)
		footprints[id] = cells
	# 先施放再复制：施放先记录完整探索圆盘（含遮挡地形），复制让新灰格同次更新生效；记忆 0/1 单调，实时可见是独立并集。
	var next: PackedByteArray = _explored.duplicate()
	for cells: PackedInt32Array in footprints.values():
		for index: int in cells:
			next[index] = State.VISIBLE
	_sources = sources
	_footprints = footprints
	_grid_revision = grid.coverage_revision()
	if _explored_changed:
		_explored_revision += 1
	if next == _states:
		return false
	_states = next
	_revision += 1
	return true


func _mark_explored(index: int) -> void:
	if _explored[index] == State.EXPLORED:
		return
	_explored[index] = State.EXPLORED
	_explored_changed = true
	_explored_changes.append(Vector2i(index % _dimensions.x, index / _dimensions.x))


func _cast_source(grid: MechGridState, center: Vector2, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var low := Vector2i((center - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((center + Vector2.ONE * radius).floor()).min(_dimensions - Vector2i.ONE)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			var point := Vector2(cell) + Vector2(0.5, 0.5)
			if not grid.contains(cell) or center.distance_squared_to(point) > radius * radius:
				continue
			var index: int = y * _dimensions.x + x
			_mark_explored(index)
			if grid.terrain_line_clear(center, point, true):
				result.append(index)
	return result


func state_at(cell: Vector2i) -> State:
	if not Rect2i(Vector2i.ZERO, _dimensions).has_point(cell):
		return State.UNEXPLORED
	return _states[cell.y * _dimensions.x + cell.x] as State


## 世界坐标处的目标当前是否可见（战斗锁定的判定条件）。
func is_visible(position: Vector2) -> bool:
	return state_at(Vector2i(position.floor())) == State.VISIBLE


func snapshot() -> Dictionary:
	return {"dimensions": _dimensions, "cells": _states.duplicate(), "revision": _revision}
