class_name MechFormationPlanner
extends RefCounted
## 命令时刻对未修改的 MIT RTSFormation 模块的适配器。槽位是终点承诺；
## 行军途中原生 RVO 可能打破队列。

const FORMATION = preload("res://vendor/rts_advanced_lite/rts_formation.gd")
## 编队槽位间距（格）。
const SPACING: float = 1.0
## 判定“仅微调”的队心偏移上限（格）。
const SHORT_ADJUSTMENT: float = 1.5
## 朝向一致判定的点积阈值。
const SAME_HEADING_DOT: float = 0.98480775 # 十度朝向容差。


## 为整支部队规划行军编队：可复用现有队形时保持各成员偏移，
## 否则用 FORMATION 模块生成盒式槽位并分配；理想槽被挡时从后备环就近补位。
## 任一成员找不到可达路径则整体失败（原指令保持）。
## 成功返回 {"ok": true, "reason", "paths", "slots", "center", "facing"}。
func plan(members: Array[MechEntityState], goal: Vector2, grid: MechGridState, navigation: MechGridNavigation) -> Dictionary:
	var center := Vector2.ZERO
	for unit: MechEntityState in members:
		center += unit.position
	center /= float(members.size())
	var forward: Vector2 = _arrival_direction(members, center, goal, navigation)
	var desired: Dictionary = {}
	if _can_reuse(members, goal, forward):
		# 朝向基本一致时沿用原到达朝向，避免队形原地旋转。
		if members[0].arrival_facing.dot(forward) >= SAME_HEADING_DOT:
			forward = members[0].arrival_facing
		# 复用现有队形：各成员保持既有编队偏移。
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
			# 惰性生成一次目标周边的后备环形布置。
			if fallback.is_empty():
				fallback = _fallback_slots(goal, members.size(), grid)
			var candidates: Array[Vector2] = []
			for fallback_point: Vector2 in fallback:
				candidates.append(fallback_point)
			candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(point) < b.distance_squared_to(point))
			# 按到理想槽的距离从近到远尝试，取第一个既空闲又不属于他人的可达槽。
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


## 推导到达朝向：默认取队心指向目标；若实际路径末段走向与之夹角超过 45°，
## 改用路径末段走向。
func _arrival_direction(members: Array[MechEntityState], center: Vector2, goal: Vector2, navigation: MechGridNavigation) -> Vector2:
	var forward: Vector2 = center.direction_to(goal)
	if forward.is_zero_approx():
		forward = members[0].arrival_facing if members[0].has_arrival_facing else members[0].facing
	# 即使队心落在岩石里，离队心最近的真实成员也能作为有效的寻路起点。
	var anchor: MechEntityState = members[0]
	for unit: MechEntityState in members:
		if unit.position.distance_squared_to(center) < anchor.position.distance_squared_to(center):
			anchor = unit
	var route: PackedVector2Array = navigation.find_path_to_point(anchor.position, goal)
	if route.size() > 1:
		var approach: Vector2 = route[-1] - route[-2]
		# 0.70710678 ≈ cos45°：末段走向与默认朝向偏差过大时以路径为准。
		if approach.length() >= 0.5 and forward.dot(approach.normalized()) < 0.70710678:
			forward = approach.normalized()
	return forward.normalized()


## 同一编队且规模一致、无人接敌，并且队心偏移不超过 SHORT_ADJUSTMENT
## 或到达朝向一致时，可复用现有队形偏移。
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


## 生成盒式编队槽位并按成员相对位置分配。
func _assign_slots(members: Array[MechEntityState], center: Vector2, goal: Vector2, forward: Vector2) -> Dictionary:
	var target := Vector3(goal.x, 0.0, goal.y)
	var from := Vector3(goal.x - forward.x, 0.0, goal.y - forward.y)
	var slots: Array[Vector3] = FORMATION.box(from, target, members.size(), SPACING)
	# 末行不满员时槽位质心略有偏移；在不改动上游布局生成器的前提下，
	# 把点击点校回队伍实际中心。
	var mean := Vector3.ZERO
	for slot: Vector3 in slots:
		mean += slot
	mean /= float(slots.size())
	for index: int in range(slots.size()):
		slots[index] += target - mean
	var ordered: Array[MechEntityState] = _ordered_members(members, forward)
	var positions: Array[Vector3] = []
	for unit: MechEntityState in ordered:
		# 在终点处比较相对位置，避免长途行军让每个成员都贪婪争抢同一近侧排。
		var translated: Vector2 = goal + unit.position - center
		positions.append(Vector3(translated.x, 0.0, translated.y))
	var assignment: Array[int] = FORMATION.assign(positions, slots)
	var result: Dictionary = {}
	for index: int in range(ordered.size()):
		var slot: Vector3 = slots[assignment[index]]
		result[ordered[index].entity_id] = Vector2(slot.x, slot.z)
	return result


## 按“最靠前优先、再按左侧、entity_id 兜底”排序，确定槽位分配与占位顺序。
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


## 槽位是否可用：地面可站立且与已占槽位保持 MOBILE_SPACING 间距。
func _slot_clear(point: Vector2, occupied: PackedVector2Array, grid: MechGridState) -> bool:
	if not grid.mobile_position_clear(point, {}, true):
		return false
	for other: Vector2 in occupied:
		if point.distance_squared_to(other) < MechEntityRegistry.MOBILE_SPACING * MechEntityRegistry.MOBILE_SPACING:
			return false
	return true


## 判断候选点是否是其他未分配成员仍有效的理想槽位（修复时不得抢占）。
func _reserved_for_other(point: Vector2, id: int, desired: Dictionary, assigned: Dictionary, grid: MechGridState) -> bool:
	# 修复被阻挡的落点，同时不占用其他未处理成员的有效槽位。
	for other_id: int in desired:
		if other_id == id or assigned.has(other_id):
			continue
		var other: Vector2 = desired[other_id]
		if point.distance_squared_to(other) < MechEntityRegistry.MOBILE_SPACING * MechEntityRegistry.MOBILE_SPACING and grid.mobile_position_clear(other, {}, true):
			return true
	return false


## 以目标为圆心逐环扩张，收集足够数量的可站立后备槽位。
func _fallback_slots(goal: Vector2, count: int, grid: MechGridState) -> PackedVector2Array:
	# 复用先前的环形布置思路，仅用于修复被阻挡的理想槽位。
	var result := PackedVector2Array()
	var origin := Vector2i(goal.floor())
	for radius: int in range(21):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = origin + Vector2i(x, y)
				if not grid.is_walkable(cell, true, {}, true):
					continue
				var point: Vector2 = goal + Vector2(x, y)
				if not grid.mobile_position_clear(point, {}, true):
					point = Vector2(cell) + Vector2(0.5, 0.5)
				if grid.mobile_position_clear(point, {}, true):
					result.append(point)
		if result.size() >= count * 3 + 8:
			break
	return result
