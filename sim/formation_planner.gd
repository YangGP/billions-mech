class_name MechFormationPlanner
extends RefCounted
## Command-time adapter for the unmodified MIT RTSFormation module. Slots are
## destination commitments; native RVO can break ranks while travelling.

const FORMATION = preload("res://vendor/rts_advanced_lite/rts_formation.gd")
const SPACING: float = 1.0
const SHORT_ADJUSTMENT: float = 1.5
const SAME_HEADING_DOT: float = 0.98480775 # Ten degrees of heading tolerance.


func plan(members: Array[MechEntityState], goal: Vector2, grid: MechGridState, navigation: MechGridNavigation) -> Dictionary:
	var center := Vector2.ZERO
	for unit: MechEntityState in members:
		center += unit.position
	center /= float(members.size())
	var forward: Vector2 = _arrival_direction(members, center, goal, navigation)
	var desired: Dictionary = {}
	if _can_reuse(members, goal, forward):
		if members[0].arrival_facing.dot(forward) >= SAME_HEADING_DOT:
			forward = members[0].arrival_facing
		for unit: MechEntityState in members:
			desired[unit.entity_id] = goal + unit.formation_offset
	else:
		desired = _assign_slots(members, center, goal, forward)
	var paths: Dictionary = {}
	var slots: Dictionary = {}
	var occupied := PackedVector2Array()
	var fallback := PackedVector2Array()
	var ordered: Array[MechEntityState] = _ordered_members(members, forward)
	for unit: MechEntityState in ordered:
		var point: Vector2 = desired[unit.entity_id]
		var path := PackedVector2Array()
		if _slot_clear(point, occupied, grid):
			path = navigation.find_path_to_point(unit.position, point)
		if path.is_empty():
			if members.size() == 1:
				return {"ok": false, "reason": "目标无法到达，原指令保持"}
			if fallback.is_empty():
				fallback = _fallback_slots(goal, members.size(), grid)
			var candidates: Array[Vector2] = []
			for fallback_point: Vector2 in fallback:
				candidates.append(fallback_point)
			candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(point) < b.distance_squared_to(point))
			for candidate: Vector2 in candidates:
				if not _slot_clear(candidate, occupied, grid):
					continue
				if _reserved_for_other(candidate, unit.entity_id, desired, slots, grid):
					continue
				path = navigation.find_path_to_point(unit.position, candidate)
				if not path.is_empty():
					point = candidate
					break
		if path.is_empty():
			return {"ok": false, "reason": "无法为整支部队找到可达队列位置，原指令保持"}
		occupied.append(point)
		slots[unit.entity_id] = point
		paths[unit.entity_id] = path
	return {"ok": true, "reason": "", "paths": paths, "slots": slots, "center": goal, "facing": forward}


func _arrival_direction(members: Array[MechEntityState], center: Vector2, goal: Vector2, navigation: MechGridNavigation) -> Vector2:
	var forward: Vector2 = center.direction_to(goal)
	if forward.is_zero_approx():
		forward = members[0].arrival_facing if members[0].has_arrival_facing else members[0].facing
	# A real member is a valid route origin even when the centroid lies in rock.
	var anchor: MechEntityState = members[0]
	for unit: MechEntityState in members:
		if unit.position.distance_squared_to(center) < anchor.position.distance_squared_to(center):
			anchor = unit
	var route: PackedVector2Array = navigation.find_path_to_point(anchor.position, goal)
	if route.size() > 1:
		var approach: Vector2 = route[-1] - route[-2]
		if approach.length() >= 0.5 and forward.dot(approach.normalized()) < 0.70710678:
			forward = approach.normalized()
	return forward.normalized()


func _can_reuse(members: Array[MechEntityState], goal: Vector2, forward: Vector2) -> bool:
	if members.size() < 2:
		return false
	var first: MechEntityState = members[0]
	if first.formation_id == 0 or first.formation_size != members.size():
		return false
	for unit: MechEntityState in members:
		if unit.formation_id != first.formation_id or unit.formation_size != members.size():
			return false
		if unit.attack_target_id != 0:
			return false
	return goal.distance_to(first.formation_center) <= SHORT_ADJUSTMENT or first.arrival_facing.dot(forward) >= SAME_HEADING_DOT


func _assign_slots(members: Array[MechEntityState], center: Vector2, goal: Vector2, forward: Vector2) -> Dictionary:
	var target := Vector3(goal.x, 0.0, goal.y)
	var from := Vector3(goal.x - forward.x, 0.0, goal.y - forward.y)
	var slots: Array[Vector3] = FORMATION.box(from, target, members.size(), SPACING)
	# Incomplete last rows have a small centroid bias; keep the click at the
	# actual centre of the group without changing the upstream layout generator.
	var mean := Vector3.ZERO
	for slot: Vector3 in slots:
		mean += slot
	mean /= float(slots.size())
	for index: int in range(slots.size()):
		slots[index] += target - mean
	var ordered: Array[MechEntityState] = _ordered_members(members, forward)
	var positions: Array[Vector3] = []
	for unit: MechEntityState in ordered:
		# Compare relative positions at the destination, so long travel distance
		# cannot make every member greedily compete for the same near-side row.
		var translated: Vector2 = goal + unit.position - center
		positions.append(Vector3(translated.x, 0.0, translated.y))
	var assignment: Array[int] = FORMATION.assign(positions, slots)
	var result: Dictionary = {}
	for index: int in range(ordered.size()):
		var slot: Vector3 = slots[assignment[index]]
		result[ordered[index].entity_id] = Vector2(slot.x, slot.z)
	return result


func _ordered_members(members: Array[MechEntityState], forward: Vector2) -> Array[MechEntityState]:
	var result: Array[MechEntityState] = members.duplicate()
	var side := Vector2(forward.y, -forward.x)
	result.sort_custom(func(a: MechEntityState, b: MechEntityState) -> bool:
		var front_a: int = roundi(a.position.dot(forward) * 20.0)
		var front_b: int = roundi(b.position.dot(forward) * 20.0)
		if front_a != front_b:
			return front_a > front_b
		var side_a: int = roundi(a.position.dot(side) * 20.0)
		var side_b: int = roundi(b.position.dot(side) * 20.0)
		return side_a < side_b if side_a != side_b else a.entity_id < b.entity_id)
	return result


func _slot_clear(point: Vector2, occupied: PackedVector2Array, grid: MechGridState) -> bool:
	if not grid.mobile_position_clear(point):
		return false
	for other: Vector2 in occupied:
		if point.distance_squared_to(other) < MechEntityRegistry.MOBILE_SPACING * MechEntityRegistry.MOBILE_SPACING:
			return false
	return true


func _reserved_for_other(point: Vector2, id: int, desired: Dictionary, assigned: Dictionary, grid: MechGridState) -> bool:
	# Repair a blocked endpoint without taking an untouched member's valid slot.
	for other_id: int in desired:
		if other_id == id or assigned.has(other_id):
			continue
		var other: Vector2 = desired[other_id]
		if point.distance_squared_to(other) < MechEntityRegistry.MOBILE_SPACING * MechEntityRegistry.MOBILE_SPACING and grid.mobile_position_clear(other):
			return true
	return false


func _fallback_slots(goal: Vector2, count: int, grid: MechGridState) -> PackedVector2Array:
	# Reuse the previous placement ring only to repair blocked ideal slots.
	var result := PackedVector2Array()
	var origin := Vector2i(goal.floor())
	for radius: int in range(21):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = origin + Vector2i(x, y)
				if not grid.is_walkable(cell):
					continue
				var point: Vector2 = goal + Vector2(x, y)
				if not grid.mobile_position_clear(point):
					point = Vector2(cell) + Vector2(0.5, 0.5)
				if grid.mobile_position_clear(point):
					result.append(point)
		if result.size() >= count * 3 + 8:
			break
	return result
