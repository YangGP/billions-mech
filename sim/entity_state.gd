class_name MechEntityState
extends RefCounted
## Logical state only; never holds a Node or rendering resource.

const PATH_POINT_TOLERANCE: float = 0.3
const ARRIVAL_TOLERANCE: float = 0.08

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


func next_waypoint() -> Vector2:
	return _waypoints[_waypoint_index] if has_move_order else position


func preferred_velocity(speed: float, seconds: float, can_travel: Callable) -> Vector2:
	while has_move_order:
		var next_point: Vector2 = _waypoints[_waypoint_index]
		var distance: float = position.distance_to(next_point)
		var intermediate: bool = _waypoint_index + 1 < _waypoints.size()
		if intermediate and distance <= PATH_POINT_TOLERANCE and can_travel.call(position, _waypoints[_waypoint_index + 1]):
			_waypoint_index += 1
			continue
		# Only the committed RVO position may complete the final waypoint.
		# Keep the active order/priority while native avoidance is still pending.
		if not intermediate and distance <= ARRIVAL_TOLERANCE:
			return Vector2.ZERO
		return position.direction_to(next_point) * minf(speed, distance / seconds)
	return Vector2.ZERO


func finish_path_if_arrived() -> void:
	if has_move_order and _waypoint_index == _waypoints.size() - 1 and position.distance_to(_waypoints[_waypoint_index]) <= ARRIVAL_TOLERANCE:
		_waypoint_index = _waypoints.size()
		has_move_order = false


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
