class_name MechMarchField
extends RefCounted
## Weighted integration field for horde marching (values.md §11 soft-cost model,
## Mindustry Pathfinder style). Cell enter cost = terrain weight × building soft
## cost, so a sufficiently wide opening is always cheaper than chewing walls:
## enemies funnel through gaps without special cases, and with no cheap route the
## field still points into the wall, where blocker engagement in MechEnemySystem
## keeps "撞墙打墙". The owner recomputes on occupancy changes or HP drift.

const SOFT_COST_CAP: int = 400
const SOFT_COST_DIVISOR: float = 8.0

const _DIRS_4: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

const _DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _dimensions: Vector2i = Vector2i.ZERO
var _goal: Vector2i = Vector2i.ZERO
var _cost := PackedFloat32Array()
var _dist := PackedFloat32Array()


func rebuild(grid: MechGridState, goal: Vector2i, buildings: Array[MechBuildingState]) -> void:
	_dimensions = grid.dimensions()
	_goal = goal
	var count: int = _dimensions.x * _dimensions.y
	_cost.resize(count)
	_dist.resize(count)
	_fill_costs(grid, buildings)
	_integrate()


## Integration distance to the goal; INF for unreachable/off-map cells.
func cost_at(cell: Vector2i) -> float:
	if not _contains(cell):
		return INF
	return _dist[cell.y * _dimensions.x + cell.x]


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
		var distance: float = cost_at(cell + direction)
		if is_finite(distance) and distance < best:
			best = distance
			best_dir = direction
	if best_dir == Vector2i.ZERO:
		return Vector2.ZERO
	return Vector2(best_dir).normalized()


func _contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _dimensions.x and cell.y < _dimensions.y


## Enter cost per cell: terrain weight; building cells add 1 + min(HP, cap) / divisor.
## The building containing the goal (the mainbrain) is exempt — it is the
## destination, not an obstacle. Destroyed bases (hp == 0) are pass-through
## rubble on open terrain: marchers stream straight through the gap they made.
## Non-building occupants keep plain terrain cost.
func _fill_costs(grid: MechGridState, buildings: Array[MechBuildingState]) -> void:
	var goal_building_id: int = 0
	var soft: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0:
			continue
		if Rect2i(building.origin, building.definition.footprint).has_point(_goal):
			goal_building_id = building.entity_id
			continue
		var cost: float = 1.0 + float(mini(building.hp, SOFT_COST_CAP)) / SOFT_COST_DIVISOR
		soft[building.entity_id] = cost
	for index: int in range(_cost.size()):
		var cell := Vector2i(index % _dimensions.x, index / _dimensions.x)
		var weight: float = grid.movement_weight(cell)
		var occupant: int = grid.occupant_at(cell)
		if grid.terrain_at(cell) == MechGridState.Terrain.OBSTACLE:
			_cost[index] = INF
		elif occupant > 0 and occupant != goal_building_id and soft.has(occupant):
			_cost[index] = weight * soft[occupant]
		else:
			_cost[index] = weight


## Dijkstra wavefront from the goal over enter costs, with a flat binary heap and
## lazy stale-entry deletion. 4-connected integration; flow_at adds diagonals.
func _integrate() -> void:
	_dist.fill(INF)
	if not _contains(_goal):
		return
	var goal_index: int = _goal.y * _dimensions.x + _goal.x
	if not is_finite(_cost[goal_index]):
		return
	_dist[goal_index] = 0.0
	var heap_key := PackedFloat32Array()
	var heap_value := PackedInt32Array()
	_heap_push(heap_key, heap_value, 0.0, goal_index)
	while heap_key.size() > 0:
		var distance: float = heap_key[0]
		var index: int = heap_value[0]
		_heap_pop(heap_key, heap_value)
		if distance > _dist[index]:
			continue
		var cell := Vector2i(index % _dimensions.x, index / _dimensions.x)
		for direction: Vector2i in _DIRS_4:
			var neighbour := Vector2i(cell.x + direction.x, cell.y + direction.y)
			if not _contains(neighbour):
				continue
			var neighbour_index: int = neighbour.y * _dimensions.x + neighbour.x
			var enter: float = _cost[neighbour_index]
			if not is_finite(enter):
				continue
			var candidate: float = distance + enter
			if candidate < _dist[neighbour_index]:
				_dist[neighbour_index] = candidate
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
