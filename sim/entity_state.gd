class_name MechEntityState
extends RefCounted
## 纯逻辑实体状态；绝不持有 Node 或渲染资源。

## 中途路径点的切换容差（格）。
const PATH_POINT_TOLERANCE: float = 0.3
## 终点到达容差（格）。
const ARRIVAL_TOLERANCE: float = 0.08

var entity_id: int = 0
var kind: StringName = &""
var display_name: String = ""
var position: Vector2 = Vector2.ZERO
var move_target: Vector2 = Vector2.ZERO
## RVO/路径点管线速度：0 表示注册表绝不把该实体提交给原生求解器。
## 单位把定义速度复制到此处；敌人按 enemy_definition.move_speed 行军并保持 0。
var rvo_speed: float = 0.0
var has_move_order: bool = false
var footprint: Vector2i = Vector2i.ONE
var unit_definition: MechUnitDefinition
var enemy_definition: MechEnemyDefinition
var team: int = 1
var hp: int = 0
var max_hp: int = 0
var hp_last_tick: int = -1
var order: StringName = &"idle"
var order_goal: Vector2 = Vector2.ZERO
var attack_target_id: int = 0
var cooldown_ticks: int = 0
var repath_ticks: int = 0
var blocked_ticks: int = 0
var shot_ticks: int = 0
var shot_target: Vector2 = Vector2.ZERO
## 只保留最强的一层控制效果；EMP 刷新时长但绝不叠加。
var slow_ticks: int = 0
var slow_multiplier: float = 1.0
var slow_effect_multiplier: float = 1.0
var _slow_effects: Dictionary = {}
var fence_slow_multiplier: float = 1.0
var last_fence_cell: Vector2i = Vector2i(-999, -999)
var fog_coarse: bool = false
var garrison_target_id: int = 0
var garrisoned: bool = false
var garrison_building_id: int = 0
var garrison_saved_speed: float = 0.0
## 稳定的局部导航区域；z 分量区分常规/穿墙规则。
var march_zone := Vector3i(-1, -1, -1)
var facing: Vector2 = Vector2.UP
var arrival_facing: Vector2 = Vector2.UP
var has_arrival_facing: bool = false
var formation_id: int = 0
var formation_size: int = 0
var formation_center: Vector2 = Vector2.ZERO
var formation_offset: Vector2 = Vector2.ZERO
var _waypoints := PackedVector2Array()
var _waypoint_index: int = 0


## 写入移动路径点序列并重置游标；空路径即取消移动指令。
func set_move_path(points: PackedVector2Array) -> void:
	_waypoints = points.duplicate()
	_waypoint_index = 0
	has_move_order = not points.is_empty()
	if has_move_order:
		move_target = points[points.size() - 1]


func next_waypoint() -> Vector2:
	return _waypoints[_waypoint_index] if has_move_order else position


## 计算 RVO 期望速度：依次推进可直连的中途点，返回朝向当前目标点的速度。
func preferred_velocity(speed: float, seconds: float, can_travel: Callable) -> Vector2:
	while has_move_order:
		var next_point: Vector2 = _waypoints[_waypoint_index]
		var distance: float = position.distance_to(next_point)
		var intermediate: bool = _waypoint_index + 1 < _waypoints.size()
		if intermediate and distance <= PATH_POINT_TOLERANCE and can_travel.call(position, _waypoints[_waypoint_index + 1]):
			_waypoint_index += 1
			continue
		# 只有已提交的 RVO 位置才能完成最终路径点；
		# 原生避让尚未落定时保持指令与优先级不变。
		if not intermediate and distance <= ARRIVAL_TOLERANCE:
			return Vector2.ZERO
		return position.direction_to(next_point) * minf(speed, distance / seconds)
	return Vector2.ZERO


## 已在最终路径点的到达容差内时结束路径并朝向到达朝向。
func finish_path_if_arrived() -> void:
	if has_move_order and _waypoint_index == _waypoints.size() - 1 and position.distance_to(_waypoints[_waypoint_index]) <= ARRIVAL_TOLERANCE:
		_waypoint_index = _waypoints.size()
		has_move_order = false
		face_arrival()


func face_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.000001:
		facing = direction.normalized()


## 到达且无攻击目标时应用预设的到达朝向。
func face_arrival() -> void:
	if has_arrival_facing and attack_target_id == 0 and position.distance_to(order_goal) <= ARRIVAL_TOLERANCE:
		facing = arrival_facing


## 导出只读快照（含剩余路径与战斗表现字段）。
func snapshot() -> Dictionary:
	return {"id": entity_id, "kind": kind, "name": display_name,
		"position": position, "target": move_target, "has_order": has_move_order,
		"footprint": footprint, "path": _waypoints.slice(_waypoint_index),
		"is_unit": unit_definition != null, "team": team, "hp": hp, "max_hp": max_hp,
		"is_enemy": enemy_definition != null,
		"enemy_id": enemy_definition.enemy_id if enemy_definition != null else &"",
		"order": order, "order_goal": order_goal, "attack_target_id": attack_target_id,
		"facing": facing, "arrival_facing": arrival_facing, "has_arrival_facing": has_arrival_facing,
		"formation_id": formation_id, "formation_center": formation_center, "formation_offset": formation_offset,
		"shot_ticks": shot_ticks, "shot_target": shot_target,
		"capacity_cost": unit_definition.capacity_cost if unit_definition != null else 0,
		"damage": unit_definition.damage if unit_definition != null else 0,
		"attack_range": unit_definition.attack_range if unit_definition != null else 0.0}


## 施加一层减速控制；同倍率刷新时长，不同倍率各自独立计时。
func apply_slow(multiplier: float, ticks: int) -> void:
	if multiplier >= 1.0 or multiplier <= 0.0 or ticks <= 0:
		return
	_slow_effects[multiplier] = maxi(ticks, int(_slow_effects.get(multiplier, 0)))
	_refresh_slow()


## 推进各层控制的剩余时长并重算汇总值。
func advance_slow() -> void:
	if _slow_effects.is_empty():
		return
	for multiplier: float in _slow_effects.keys():
		var remaining: int = int(_slow_effects[multiplier]) - 1
		if remaining <= 0:
			_slow_effects.erase(multiplier)
		else:
			_slow_effects[multiplier] = remaining
	_refresh_slow()


## 汇总：取最长剩余时长与最强减速，再与围栏减速合成最终倍率。
func _refresh_slow() -> void:
	slow_ticks = 0
	slow_effect_multiplier = 1.0
	for multiplier: float in _slow_effects:
		slow_ticks = maxi(slow_ticks, int(_slow_effects[multiplier]))
		slow_effect_multiplier = minf(slow_effect_multiplier, multiplier)
	slow_multiplier = minf(slow_effect_multiplier, fence_slow_multiplier)
