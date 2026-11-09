class_name MechEntityRegistry
extends RefCounted
## 实体注册表：模拟系统共享自有状态；表现层只接收值快照。

## 整批原生移动提交完成后发一次（不是每实体一次）。
signal movement_finished

const CROWD_SCRIPT = preload("res://sim/crowd_navigation.gd")
## 出生点间距：出生格搜索时与其他移动实体的最小间距（格）。
const MOBILE_SPACING: float = 0.52

var _entities: Dictionary[int, MechEntityState] = {}
var _next_id: int = 1
var _crowd = CROWD_SCRIPT.new()
var _pending_request: int = 0
var _friendly_pass: bool = false
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


## 登记一个新实体并分配自增 ID；rvo_speed 为 0 的实体不进入原生求解器。
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


## 出生点判定：与未驻防的活跃移动实体保持 MOBILE_SPACING 间距。
func mobile_space_free(point: Vector2, ignored: Dictionary = {}) -> bool:
	for entity: MechEntityState in _entities.values():
		if not entity.garrisoned and (entity.rvo_speed > 0.0 or (entity.enemy_definition != null and entity.hp > 0)) and not ignored.has(entity.entity_id) and entity.position.distance_squared_to(point) < MOBILE_SPACING * MOBILE_SPACING:
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
	_friendly_pass = enabled
	_crowd.set_friendly_pass(enabled)


## 发起一帧原生移动：收集期望速度，向 RVO 提交异步请求；
## 请求即刻完成或回调 _apply_velocities 后发 movement_finished。
func step(seconds: float, grid: MechGridState) -> void:
	_motion_grid = grid
	_motion_seconds = seconds
	_starting_positions.clear()
	_starting_waypoints.clear()
	var preferred: Dictionary[int, Vector2] = {}
	for entity: MechEntityState in _entities.values():
		if entity.rvo_speed <= 0.0 or not grid.is_walkable(Vector2i(entity.position.floor()), true, {}, _friendly_pass):
			continue
		var speed: float = entity.rvo_speed / grid.movement_weight(Vector2i(entity.position.floor()))
		preferred[entity.entity_id] = entity.preferred_velocity(speed, seconds, grid.mobile_segment_clear.bind({}, _friendly_pass))
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


## RVO 回调：提交整批解算速度，静态阻挡兜底、更新朝向并检测卡位。
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
		# 仅做最后的静态阻挡兜底；全部动态避让由原生 RVO 完成。
		if _motion_grid.mobile_segment_clear(entity.position, desired, {}, _friendly_pass):
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


## 导出全部实体的只读快照。
func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity: MechEntityState in _entities.values():
		result.append(entity.snapshot())
	return result
