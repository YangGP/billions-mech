class_name MechEntityRegistry
extends RefCounted
## Sim systems share owned states; presentation receives only value snapshots.

var _entities: Dictionary[int, MechEntityState] = {}
var _next_id: int = 1


func clear() -> void:
	_entities.clear()
	_next_id = 1


func create(kind: StringName, display_name: String, position: Vector2, speed: float = 0.0, footprint: Vector2i = Vector2i.ONE) -> int:
	var entity := MechEntityState.new()
	entity.entity_id = _next_id
	entity.kind = kind
	entity.display_name = display_name
	entity.position = position
	entity.move_target = position
	entity.order_goal = position
	entity.move_speed = speed
	entity.footprint = footprint
	_entities[_next_id] = entity
	_next_id += 1
	return entity.entity_id


func can_move(entity_id: int) -> bool:
	var entity: MechEntityState = _entities.get(entity_id)
	return entity != null and entity.move_speed > 0.0


func get_entity(entity_id: int) -> MechEntityState:
	return _entities.get(entity_id)


func all() -> Array[MechEntityState]:
	var result: Array[MechEntityState] = []
	result.assign(_entities.values())
	return result


func mobile_space_free(point: Vector2, ignored: Dictionary = {}) -> bool:
	for entity: MechEntityState in _entities.values():
		if entity.move_speed > 0.0 and not ignored.has(entity.entity_id) and entity.position.distance_squared_to(point) < 0.52 * 0.52:
			return false
	return true


func position_of(entity_id: int) -> Vector2:
	return _entities[entity_id].position


func remove(entity_id: int) -> void:
	_entities.erase(entity_id)


func stop(entity_id: int) -> void:
	_entities[entity_id].set_move_path(PackedVector2Array())


func teleport(entity_id: int, position: Vector2) -> void:
	var entity: MechEntityState = _entities[entity_id]
	entity.position = position
	entity.move_target = position
	entity.set_move_path(PackedVector2Array())


func movable_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: MechEntityState in _entities.values():
		if entity.move_speed > 0.0:
			result.append(entity.snapshot())
	return result


func set_move_path(entity_id: int, path: PackedVector2Array) -> void:
	var entity: MechEntityState = _entities[entity_id]
	entity.set_move_path(path)


func step(seconds: float, grid: MechGridState) -> void:
	var buckets: Dictionary[Vector2i, Array] = {}
	for entity: MechEntityState in _entities.values():
		if entity.move_speed > 0.0:
			var cell := Vector2i(entity.position.floor())
			if not buckets.has(cell):
				buckets[cell] = []
			buckets[cell].append(entity)
	for entity: MechEntityState in _entities.values():
		if entity.move_speed <= 0.0 or not entity.has_move_order:
			continue
		var old: Vector2 = entity.position
		var cell := Vector2i(old.floor())
		buckets[cell].erase(entity)
		entity.step(seconds / grid.movement_weight(cell), _can_enter.bind(entity.entity_id, grid, buckets))
		entity.blocked_ticks = entity.blocked_ticks + 1 if entity.position.is_equal_approx(old) else 0
		cell = Vector2i(entity.position.floor())
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(entity)


func _can_enter(point: Vector2, id: int, grid: MechGridState, buckets: Dictionary) -> bool:
	var cell := Vector2i(point.floor())
	if not grid.is_walkable(cell):
		return false
	for y: int in range(cell.y - 1, cell.y + 2):
		for x: int in range(cell.x - 1, cell.x + 2):
			for other: MechEntityState in buckets.get(Vector2i(x, y), []):
				if other.entity_id != id and other.position.distance_squared_to(point) < 0.52 * 0.52:
					return false
	return true


func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: MechEntityState in _entities.values():
		result.append(entity.snapshot())
	return result
