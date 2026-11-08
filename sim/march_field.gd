class_name MechMarchField
extends RefCounted
## Terrain-only integration field for horde marching (Mindustry Pathfinder
## style). Cell enter cost is the terrain weight; buildings are deliberately not
## part of the global route. A wall or building on the route is a local blocker
## that the enemy attacks, and once removed the enemy continues toward the core.
## The field is static for a session and is not rebuilt for occupancy or HP.

const _DIRS_4: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

const _DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _dimensions: Vector2i = Vector2i.ZERO
var _goal: Vector2i = Vector2i.ZERO
var _bounds := Rect2i()
var _cost := PackedFloat32Array()
var _dist := PackedFloat32Array()
var _source := PackedInt32Array()


func rebuild(grid: MechGridState, goal: Vector2i) -> void:
	_dimensions = grid.dimensions()
	_goal = goal
	_bounds = Rect2i(Vector2i.ZERO, _dimensions)
	var count: int = _dimensions.x * _dimensions.y
	_cost.resize(count)
	_dist.resize(count)
	_source.resize(count)
	_fill_costs(grid)
	var sources: Array[Vector2i] = [goal]
	_integrate_sources(sources)


## Local fields respect live occupancy and allocate only their own bounds.
## Optional source values connect boundary exits to the static global field.
func rebuild_local(grid: MechGridState, bounds: Rect2i, sources: Array[Vector2i], source_values: Dictionary = {}, ignored_occupants: Dictionary = {}) -> void:
	_bounds = bounds.intersection(Rect2i(Vector2i.ZERO, grid.dimensions()))
	_dimensions = _bounds.size
	var count: int = _dimensions.x * _dimensions.y
	_cost.resize(count)
	_dist.resize(count)
	_source.resize(count)
	_fill_costs(grid, true, ignored_occupants)
	_integrate_sources(sources, source_values)


## Integration distance to the goal; INF for unreachable/off-map cells.
func cost_at(cell: Vector2i) -> float:
	if not _contains(cell):
		return INF
	return _dist[_index(cell)]


func source_at(cell: Vector2i) -> Vector2i:
	if not _contains(cell) or not is_reachable(cell):
		return Vector2i(-1, -1)
	var index: int = _source[_index(cell)]
	return _bounds.position + Vector2i(index % _dimensions.x, index / _dimensions.x)


func blocks_at(cell: Vector2i) -> bool:
	return not _contains(cell) or not is_finite(_cost[_index(cell)])


func _index(cell: Vector2i) -> int:
	var local: Vector2i = cell - _bounds.position
	return local.y * _dimensions.x + local.x


func is_reachable(cell: Vector2i) -> bool:
	return is_finite(cost_at(cell))


## Unit direction from `cell` toward its lowest-distance 8-neighbour. ZERO at the
## goal, on unreachable cells, or without a strictly lower neighbour.
func flow_at(cell: Vector2i) -> Vector2:
	var here: float = cost_at(cell)
	if not is_finite(here) or here <= 0.0:
		return Vector2.ZERO
	var best: float = here
	var best_dir: Vector2i = Vector2i.ZERO
	for direction: Vector2i in _DIRS_8:
		if direction.x != 0 and direction.y != 0 and (
			blocks_at(cell + Vector2i(direction.x, 0)) or blocks_at(cell + Vector2i(0, direction.y))
		):
			continue
		var distance: float = cost_at(cell + direction)
		if is_finite(distance) and distance < best:
			best = distance
			best_dir = direction
	if best_dir == Vector2i.ZERO:
		return Vector2.ZERO
	return Vector2(best_dir).normalized()


func _contains(cell: Vector2i) -> bool:
	return _bounds.has_point(cell)


## Global enter costs use terrain alone. Local fields also mark blocked cells
## according to the movement class; neither mode reads building HP.
func _fill_costs(grid: MechGridState, include_buildings: bool = false, ignored_occupants: Dictionary = {}) -> void:
	for y: int in range(_bounds.position.y, _bounds.end.y):
		for x: int in range(_bounds.position.x, _bounds.end.x):
			var cell := Vector2i(x, y)
			var index: int = _index(cell)
			if not grid.is_walkable(cell, include_buildings, ignored_occupants):
				_cost[index] = INF
			else:
				_cost[index] = grid.movement_weight(cell)


## Dijkstra wavefront from all sources over enter costs, with a flat binary heap
## and lazy stale-entry deletion. 4-connected integration; flow_at adds diagonals.
func _integrate_sources(sources: Array[Vector2i], source_values: Dictionary = {}) -> void:
	if _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return
	for y: int in range(_bounds.position.y, _bounds.end.y):
		for x: int in range(_bounds.position.x, _bounds.end.x):
			_dist[_index(Vector2i(x, y))] = INF
	_source.fill(-1)
	var heap_key := PackedFloat32Array()
	var heap_value := PackedInt32Array()
	for source: Vector2i in sources:
		if not _contains(source):
			continue
		var index: int = _index(source)
		var initial: float = source_values.get(source, 0.0)
		if not is_finite(_cost[index]) or not is_finite(initial) or _dist[index] <= initial:
			continue
		_dist[index] = initial
		_source[index] = index
		_heap_push(heap_key, heap_value, initial, index)
	while heap_key.size() > 0:
		var distance: float = heap_key[0]
		var index: int = heap_value[0]
		_heap_pop(heap_key, heap_value)
		if distance > _dist[index]:
			continue
		var cell: Vector2i = _bounds.position + Vector2i(index % _dimensions.x, index / _dimensions.x)
		for direction: Vector2i in _DIRS_4:
			var neighbour := Vector2i(cell.x + direction.x, cell.y + direction.y)
			if not _contains(neighbour):
				continue
			var neighbour_index: int = _index(neighbour)
			var enter: float = _cost[neighbour_index]
			if not is_finite(enter):
				continue
			var candidate: float = distance + enter
			if candidate < _dist[neighbour_index]:
				_dist[neighbour_index] = candidate
				_source[neighbour_index] = _source[index]
				_heap_push(heap_key, heap_value, candidate, neighbour_index)


func _heap_push(keys: PackedFloat32Array, values: PackedInt32Array, key: float, value: int) -> void:
	keys.append(key)
	values.append(value)
	var index: int = keys.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if keys[parent] <= keys[index]:
			break
		_swap(keys, values, parent, index)
		index = parent


func _heap_pop(keys: PackedFloat32Array, values: PackedInt32Array) -> void:
	var last: int = keys.size() - 1
	keys[0] = keys[last]
	values[0] = values[last]
	keys.resize(last)
	values.resize(last)
	var index: int = 0
	while true:
		var left: int = index * 2 + 1
		var right: int = index * 2 + 2
		var smallest: int = index
		if left < keys.size() and keys[left] < keys[smallest]:
			smallest = left
		if right < keys.size() and keys[right] < keys[smallest]:
			smallest = right
		if smallest == index:
			break
		_swap(keys, values, smallest, index)
		index = smallest


func _swap(keys: PackedFloat32Array, values: PackedInt32Array, a: int, b: int) -> void:
	var key: float = keys[a]
	keys[a] = keys[b]
	keys[b] = key
	var value: int = values[a]
	values[a] = values[b]
	values[b] = value
