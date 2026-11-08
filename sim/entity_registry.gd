class_name MechEntityRegistry
extends RefCounted
## Sim systems share owned states; presentation receives only value snapshots.

signal movement_finished

const CROWD_SCRIPT = preload("res://sim/crowd_navigation.gd")
const MOBILE_SPACING: float = 0.52

var _entities: Dictionary[int, MechEntityState] = {}
var _next_id: int = 1
var _crowd = CROWD_SCRIPT.new()
var _pending_request: int = 0
var _motion_grid: MechGridState
var _motion_seconds: float = 0.0
var _starting_positions: Dictionary[int, Vector2] = {}
var _starting_waypoints: Dictionary[int, Vector2] = {}


func _init() -> void:
	_crowd.velocities_ready.connect(_apply_velocities)


func clear() -> void:
	cancel_pending_motion()
	_crowd.dispose()
	_entities.clear()
	_next_id = 1


func create(kind: StringName, display_name: String, position: Vector2, rvo_speed: float = 0.0, footprint: Vector2i = Vector2i.ONE) -> int:
	var entity := MechEntityState.new()
	entity.entity_id = _next_id
	entity.kind = kind
	entity.display_name = display_name
	entity.position = position
	entity.move_target = position
	entity.order_goal = position
	entity.rvo_speed = rvo_speed
	entity.footprint = footprint
	_entities[_next_id] = entity
	_next_id += 1
	return entity.entity_id


func can_move(entity_id: int) -> bool:
	var entity: MechEntityState = _entities.get(entity_id)
	return entity != null and entity.rvo_speed > 0.0


func get_entity(entity_id: int) -> MechEntityState:
	return _entities.get(entity_id)


func all() -> Array[MechEntityState]:
	var result: Array[MechEntityState] = []
	result.assign(_entities.values())
	return result


func mobile_space_free(point: Vector2, ignored: Dictionary = {}) -> bool:
	for entity: MechEntityState in _entities.values():
		if entity.rvo_speed > 0.0 and not ignored.has(entity.entity_id) and entity.position.distance_squared_to(point) < MOBILE_SPACING * MOBILE_SPACING:
			return false
	return true


func position_of(entity_id: int) -> Vector2:
	return _entities[entity_id].position


func remove(entity_id: int) -> void:
	_crowd.remove(entity_id)
	_entities.erase(entity_id)


func stop(entity_id: int) -> void:
	_entities[entity_id].set_move_path(PackedVector2Array())


func teleport(entity_id: int, position: Vector2) -> void:
	var entity: MechEntityState = _entities[entity_id]
	entity.position = position
	entity.move_target = position
	entity.set_move_path(PackedVector2Array())
	_crowd.teleport(entity_id, position)


func movable_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: MechEntityState in _entities.values():
		if entity.rvo_speed > 0.0:
			result.append(entity.snapshot())
	return result


func set_move_path(entity_id: int, path: PackedVector2Array) -> void:
	var entity: MechEntityState = _entities[entity_id]
	entity.set_move_path(path)


func set_friendly_pass(enabled: bool) -> void:
	_crowd.set_friendly_pass(enabled)


func step(seconds: float, grid: MechGridState) -> void:
	_motion_grid = grid
	_motion_seconds = seconds
	_starting_positions.clear()
	_starting_waypoints.clear()
	var preferred: Dictionary[int, Vector2] = {}
	for entity: MechEntityState in _entities.values():
		if entity.rvo_speed <= 0.0 or not grid.is_walkable(Vector2i(entity.position.floor())):
			continue
		var speed: float = entity.rvo_speed / grid.movement_weight(Vector2i(entity.position.floor()))
		preferred[entity.entity_id] = entity.preferred_velocity(speed, seconds, grid.mobile_segment_clear)
		_starting_positions[entity.entity_id] = entity.position
		_starting_waypoints[entity.entity_id] = entity.next_waypoint()
	_pending_request = _crowd.request(all(), preferred, grid)
	if _pending_request == 0:
		movement_finished.emit()


func cancel_pending_motion() -> void:
	_pending_request = 0
	_starting_positions.clear()
	_starting_waypoints.clear()
	_crowd.cancel_pending()


func suspend_motion() -> void:
	cancel_pending_motion()
	_crowd.suspend()


func _apply_velocities(request_id: int, velocities: Dictionary) -> void:
	if request_id != _pending_request:
		return
	_pending_request = 0
	for id: int in velocities:
		var entity: MechEntityState = _entities.get(id)
		if entity == null or not _starting_positions.has(id):
			continue
		var velocity: Vector2 = velocities[id]
		var desired: Vector2 = entity.position + velocity * _motion_seconds
		# Final static guard only; all dynamic avoidance is performed by native RVO.
		if _motion_grid.mobile_segment_clear(entity.position, desired, {}, true):
			entity.position = desired
		entity.face_direction(entity.position - _starting_positions[id])
		entity.finish_path_if_arrived()
		if not entity.has_move_order:
			entity.face_arrival()
		var waypoint: Vector2 = _starting_waypoints[id]
		var advanced: bool = not entity.has_move_order or entity.position.distance_to(waypoint) < _starting_positions[id].distance_to(waypoint) - 0.001
		entity.blocked_ticks = 0 if advanced else entity.blocked_ticks + 1
	_starting_positions.clear()
	_starting_waypoints.clear()
	movement_finished.emit()


func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: MechEntityState in _entities.values():
		result.append(entity.snapshot())
	return result
