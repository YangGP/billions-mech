class_name MechMarchField
extends RefCounted
## 供虫群行军使用的纯地形积分场（Mindustry Pathfinder 风格）。
## 格子的进入代价就是地形权重；建筑刻意不纳入全局路线。
## 路上的墙或建筑只是局部阻挡，敌人会将其击毁，清除后继续向主脑推进。
## 该场在一局内保持静态，不因占用或 HP 变化而重建。

## 积分传播用的 4 邻域方向。
const _DIRS_4: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## flow_at 用的 8 邻域方向。
const _DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _dimensions: Vector2i = Vector2i.ZERO
var _goal: Vector2i = Vector2i.ZERO
var _bounds := Rect2i()
## 每格的进入代价；INF 表示阻挡。
var _cost := PackedFloat32Array()
## 每格到目标的积分距离；INF 表示不可达。
var _dist := PackedFloat32Array()
## 每格连通到的源格索引（局部场用于边界出口溯源）。
var _source := PackedInt32Array()


## 重建指向 goal 的全局静态场：只用地形，不含建筑与占用。
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


## 局部场遵守实时占用，只分配自己的边界。
## 可选的 source_values 把边界出口接到静态全局场上。
func rebuild_local(grid: MechGridState, bounds: Rect2i, sources: Array[Vector2i], source_values: Dictionary = {}, ignored_occupants: Dictionary = {}) -> void:
	_bounds = bounds.intersection(Rect2i(Vector2i.ZERO, grid.dimensions()))
	_dimensions = _bounds.size
	var count: int = _dimensions.x * _dimensions.y
	_cost.resize(count)
	_dist.resize(count)
	_source.resize(count)
	_fill_costs(grid, true, ignored_occupants)
	_integrate_sources(sources, source_values)


## 到目标的积分距离；不可达或界外格子为 INF。
func cost_at(cell: Vector2i) -> float:
	if not _contains(cell):
		return INF
	return _dist[_index(cell)]


## 该格连通到的源格（以全局坐标返回）；界外或不可达时返回 (-1, -1)。
func source_at(cell: Vector2i) -> Vector2i:
	if not _contains(cell) or not is_reachable(cell):
		return Vector2i(-1, -1)
	var index: int = _source[_index(cell)]
	return _bounds.position + Vector2i(index % _dimensions.x, index / _dimensions.x)


## 该格是否为阻挡（界外或进入代价为 INF）。
func blocks_at(cell: Vector2i) -> bool:
	return not _contains(cell) or not is_finite(_cost[_index(cell)])


## 把全局格子坐标转为数组索引（局部场需减去边界偏移）。
func _index(cell: Vector2i) -> int:
	var local: Vector2i = cell - _bounds.position
	return local.y * _dimensions.x + local.x


func is_reachable(cell: Vector2i) -> bool:
	return is_finite(cost_at(cell))


## 从 cell 指向其距离最小的 8 邻域的单位方向。在目标格、不可达格
## 或没有严格更低邻居时返回 ZERO。
func flow_at(cell: Vector2i) -> Vector2:
	var here: float = cost_at(cell)
	if not is_finite(here) or here <= 0.0:
		return Vector2.ZERO
	var best: float = here
	var best_dir: Vector2i = Vector2i.ZERO
	for direction: Vector2i in _DIRS_8:
		# 对角移动要求相邻两个正交格都可通行，防止斜穿墙角。
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


## 全局模式的进入代价只用地形。局部场还会按移动类别标记阻挡格；
## 两种模式都不读建筑 HP。
func _fill_costs(grid: MechGridState, include_buildings: bool = false, ignored_occupants: Dictionary = {}) -> void:
	for y: int in range(_bounds.position.y, _bounds.end.y):
		for x: int in range(_bounds.position.x, _bounds.end.x):
			var cell := Vector2i(x, y)
			var index: int = _index(cell)
			if not grid.is_walkable(cell, include_buildings, ignored_occupants):
				_cost[index] = INF
			else:
				_cost[index] = grid.movement_weight(cell)


## 从所有源出发、按进入代价扩散的 Dijkstra 波前，配扁平二叉堆
## 与惰性过期条目删除。积分只走 4 连通；flow_at 再补对角。
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
		# 惰性删除：堆里的过期条目直接跳过。
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


## 向扁平数组二叉堆压入一个条目。
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


## 弹出堆顶（最小键）条目。
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
