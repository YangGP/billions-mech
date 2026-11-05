class_name MechEntityState
extends RefCounted
## Logical state only; never holds a Node or rendering resource.

var entity_id: int = 0
var kind: StringName = &""
var display_name: String = ""
var position: Vector2 = Vector2.ZERO
var move_target: Vector2 = Vector2.ZERO
var move_speed: float = 0.0
var has_move_order: bool = false
var footprint: Vector2i = Vector2i.ONE
var unit_definition: MechUnitDefinition
var team: int = 1
var hp: int = 0
var max_hp: int = 0
var order: StringName = &"idle"
var order_goal: Vector2 = Vector2.ZERO
var attack_target_id: int = 0
var cooldown_ticks: int = 0
var repath_ticks: int = 0
var blocked_ticks: int = 0
var shot_ticks: int = 0
var shot_target: Vector2 = Vector2.ZERO
var _waypoints := PackedVector2Array()
var _waypoint_index: int = 0


func set_move_path(points: PackedVector2Array) -> void:
	_waypoints = points.duplicate()
	_waypoint_index = 0
	has_move_order = not points.is_empty()
	if has_move_order:
		move_target = points[points.size() - 1]


func step(seconds: float, can_enter: Callable) -> void:
	if not has_move_order:
		return
	var remaining: float = move_speed * seconds
	while has_move_order and remaining > 0.0:
		var next_point: Vector2 = _waypoints[_waypoint_index]
		var distance: float = position.distance_to(next_point)
		var candidate: Vector2 = position.move_toward(next_point, remaining)
		if not can_enter.call(candidate):
			return
		if distance <= remaining:
			position = next_point
			remaining -= distance
			_waypoint_index += 1
			has_move_order = _waypoint_index < _waypoints.size()
		else:
			position = candidate
			remaining = 0.0


func snapshot() -> Dictionary:
	return {"id": entity_id, "kind": kind, "name": display_name,
		"position": position, "target": move_target, "has_order": has_move_order,
		"footprint": footprint, "path": _waypoints.slice(_waypoint_index),
		"is_unit": unit_definition != null, "team": team, "hp": hp, "max_hp": max_hp,
		"order": order, "order_goal": order_goal, "attack_target_id": attack_target_id,
		"shot_ticks": shot_ticks, "shot_target": shot_target,
		"capacity_cost": unit_definition.capacity_cost if unit_definition != null else 0,
		"damage": unit_definition.damage if unit_definition != null else 0,
		"attack_range": unit_definition.attack_range if unit_definition != null else 0.0}
