class_name MechVisionSystem
extends RefCounted
## Authoritative, monotonic exploration. LOS footprints are cached per source;
## movement within a tile does not rebuild visibility or upload the fog texture.

enum State { UNEXPLORED, EXPLORED, VISIBLE }

var _dimensions := Vector2i.ZERO
var _states := PackedByteArray()
var _explored := PackedByteArray()
var _sources: Dictionary = {}
var _footprints: Dictionary = {}
var _grid_revision: int = -1
var _revision: int = 0


func reset(grid: MechGridState) -> void:
	_dimensions = grid.dimensions()
	_states.resize(_dimensions.x * _dimensions.y)
	_states.fill(State.UNEXPLORED)
	_explored = _states.duplicate()
	_sources.clear()
	_footprints.clear()
	_grid_revision = -1
	_revision += 1


func update(grid: MechGridState, registry: MechEntityRegistry, buildings: Array[MechBuildingState], probe_radius: float) -> bool:
	var sources: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp > 0 and building.operating() and building.definition.sight_radius > 0.0:
			var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
			sources[building.entity_id] = Vector3(center.x, center.y, building.definition.sight_radius)
	for entity: MechEntityState in registry.all():
		if entity.team != 1:
			continue
		var radius: float = 0.0
		if entity.unit_definition != null and entity.hp > 0:
			radius = entity.unit_definition.sight_radius
		elif entity.kind == &"probe":
			radius = probe_radius
		if radius > 0.0:
			var center: Vector2 = entity.position.floor() + Vector2(0.5, 0.5)
			sources[entity.entity_id] = Vector3(center.x, center.y, radius)
	if sources == _sources and _grid_revision == grid.revision():
		return false
	var next := PackedByteArray()
	next.resize(_states.size())
	for y: int in range(_dimensions.y):
		for x: int in range(_dimensions.x):
			var index: int = y * _dimensions.x + x
			if grid.is_covered(Vector2i(x, y)):
				_explored[index] = 1
			next[index] = State.EXPLORED if _explored[index] != 0 else State.UNEXPLORED
	var footprints: Dictionary = {}
	for id: int in sources:
		var source: Vector3 = sources[id]
		var cells: PackedInt32Array
		if _sources.get(id) == source:
			cells = _footprints[id]
		else:
			cells = _cast_source(grid, Vector2(source.x, source.y), source.z)
		footprints[id] = cells
		for index: int in cells:
			next[index] = State.VISIBLE
			_explored[index] = 1
	_sources = sources
	_footprints = footprints
	_grid_revision = grid.revision()
	if next == _states:
		return false
	_states = next
	_revision += 1
	return true


func _cast_source(grid: MechGridState, center: Vector2, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var low := Vector2i((center - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((center + Vector2.ONE * radius).floor()).min(_dimensions - Vector2i.ONE)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			var point := Vector2(cell) + Vector2(0.5, 0.5)
			if grid.contains(cell) and center.distance_squared_to(point) <= radius * radius and grid.terrain_line_clear(center, point, true):
				result.append(y * _dimensions.x + x)
	return result


func state_at(cell: Vector2i) -> State:
	if not Rect2i(Vector2i.ZERO, _dimensions).has_point(cell):
		return State.UNEXPLORED
	return _states[cell.y * _dimensions.x + cell.x] as State


func is_visible(position: Vector2) -> bool:
	return state_at(Vector2i(position.floor())) == State.VISIBLE


func snapshot() -> Dictionary:
	return {"dimensions": _dimensions, "cells": _states.duplicate(), "revision": _revision}
