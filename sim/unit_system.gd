class_name MechUnitSystem
extends RefCounted
## Player orders and the M4 static-target combat loop. No scene dependencies.


func create(registry: MechEntityRegistry, rules: MechUnitDefinition, cell: Vector2i) -> int:
	var id: int = registry.create(rules.unit_id, rules.display_name, Vector2(cell) + Vector2(0.5, 0.5), rules.move_speed)
	var unit: MechEntityState = registry.get_entity(id)
	unit.unit_definition = rules
	unit.hp = rules.max_hp
	unit.max_hp = rules.max_hp
	return id


func capacity_used(registry: MechEntityRegistry) -> int:
	var total: int = 0
	for entity: MechEntityState in registry.all():
		if entity.team == 1 and entity.unit_definition != null and entity.hp > 0:
			total += entity.unit_definition.capacity_cost
	return total


func plan_order(ids: Array, kind: StringName, goal: Vector2, target_id: int, registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation) -> Dictionary:
	if not kind in [&"move", &"attack_move", &"attack"]:
		return {"ok": false, "reason": "未知单位指令"}
	if ids.is_empty() or ids.size() > 1000:
		return {"ok": false, "reason": "请选择部队"}
	var selected: Dictionary = {}
	for raw_id: Variant in ids:
		if typeof(raw_id) != TYPE_INT:
			return {"ok": false, "reason": "单位编号无效"}
		var unit: MechEntityState = registry.get_entity(raw_id)
		if unit == null or unit.unit_definition == null or unit.team != 1 or unit.hp <= 0:
			return {"ok": false, "reason": "所选单位已失效"}
		if not grid.is_walkable(Vector2i(unit.position.floor())):
			return {"ok": false, "reason": "部队位于施工占地，待完工移出后再下令"}
		selected[raw_id] = true
	var paths: Dictionary = {}
	if kind == &"attack":
		var enemy: MechEntityState = registry.get_entity(target_id)
		if enemy == null or enemy.team != 2 or enemy.hp <= 0:
			return {"ok": false, "reason": "攻击目标已失效"}
		goal = enemy.position
	else:
		if not goal.is_finite() or not grid.contains(Vector2i(goal.floor())) or not grid.is_walkable(Vector2i(goal.floor())):
			return {"ok": false, "reason": "目标超界或被地形/建筑阻挡"}
		var slots: Array[Vector2i] = _formation_cells(Vector2i(goal.floor()), selected, registry, grid)
		for id: int in selected:
			var unit: MechEntityState = registry.get_entity(id)
			var assigned: bool = false
			for index: int in range(slots.size()):
				var path: PackedVector2Array = navigation.find_path(unit.position, slots[index])
				if path.is_empty():
					continue
				paths[id] = path
				slots.remove_at(index)
				assigned = true
				break
			if not assigned:
				return {"ok": false, "reason": "无法为整支部队找到可达位置，原指令保持"}
	return {"ok": true, "reason": "", "ids": selected.keys(), "kind": kind,
		"goal": goal, "target_id": target_id, "paths": paths}


func apply_order(plan: Dictionary, registry: MechEntityRegistry) -> void:
	for id: int in plan["ids"]:
		var unit: MechEntityState = registry.get_entity(id)
		unit.order = plan["kind"]
		unit.attack_target_id = plan["target_id"] if unit.order == &"attack" else 0
		unit.order_goal = plan["goal"]
		unit.repath_ticks = 0
		unit.blocked_ticks = 0
		if plan["paths"].has(id):
			var path: PackedVector2Array = plan["paths"][id]
			unit.order_goal = path[path.size() - 1]
			unit.set_move_path(path)
		else:
			unit.set_move_path(PackedVector2Array())


func _formation_cells(goal: Vector2i, selected: Dictionary, registry: MechEntityRegistry, grid: MechGridState) -> Array[Vector2i]:
	var occupied: Dictionary = {}
	for entity: MechEntityState in registry.all():
		if entity.move_speed > 0.0 and not selected.has(entity.entity_id):
			occupied[Vector2i(entity.position.floor())] = true
	var result: Array[Vector2i] = []
	for radius: int in range(21):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = goal + Vector2i(x, y)
				if grid.is_walkable(cell) and not occupied.has(cell) and registry.mobile_space_free(Vector2(cell) + Vector2(0.5, 0.5), selected):
					result.append(cell)
		if result.size() >= selected.size() * 3 + 8:
			break
	return result


func spawn(building: MechBuildingState, rally: Vector2i, rules: MechUnitDefinition, registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation) -> bool:
	var occupied: Dictionary = {}
	for entity: MechEntityState in registry.all():
		if entity.move_speed > 0.0:
			occupied[Vector2i(entity.position.floor())] = true
	var area := Rect2i(building.origin, building.definition.footprint)
	var candidates: Array[Vector2i] = []
	for y: int in range(area.position.y - 1, area.end.y + 1):
		for x: int in range(area.position.x - 1, area.end.x + 1):
			var cell := Vector2i(x, y)
			var outside_x: bool = x < area.position.x or x >= area.end.x
			var outside_y: bool = y < area.position.y or y >= area.end.y
			if outside_x and outside_y:
				continue
			if not area.has_point(cell) and grid.is_walkable(cell) and not occupied.has(cell) and registry.mobile_space_free(Vector2(cell) + Vector2(0.5, 0.5)):
				candidates.append(cell)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(rally) < b.distance_squared_to(rally))
	var id: int = create(registry, rules, candidates[0])
	if grid.is_walkable(rally):
		var plan: Dictionary = plan_order([id], &"move", Vector2(rally) + Vector2(0.5, 0.5), 0, registry, grid, navigation)
		if plan["ok"]:
			apply_order(plan, registry)
	return true


func advance(registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation, hz: int) -> Array[int]:
	var dead: Array[int] = []
	var enemies: Dictionary[Vector2i, Array] = {}
	for entity: MechEntityState in registry.all():
		if entity.team == 2 and entity.hp > 0:
			var cell := Vector2i(entity.position.floor())
			if not enemies.has(cell):
				enemies[cell] = []
			enemies[cell].append(entity)
	for unit: MechEntityState in registry.all():
		if unit.team != 1 or unit.unit_definition == null or unit.hp <= 0:
			continue
		unit.cooldown_ticks = maxi(0, unit.cooldown_ticks - 1)
		unit.repath_ticks = maxi(0, unit.repath_ticks - 1)
		unit.shot_ticks = maxi(0, unit.shot_ticks - 1)
		if not grid.is_walkable(Vector2i(unit.position.floor())):
			continue
		if unit.order == &"move":
			if not unit.has_move_order:
				unit.order = &"idle"
			else:
				_repath_blocked(unit, registry, navigation, hz)
			continue
		var target: MechEntityState = registry.get_entity(unit.attack_target_id)
		if target == null or target.hp <= 0 or target.team != 2:
			if unit.attack_target_id != 0:
				unit.set_move_path(PackedVector2Array())
				unit.repath_ticks = 0
			target = null
			unit.attack_target_id = 0
			if unit.order == &"attack":
				unit.order = &"idle"
		if target == null:
			target = _nearest_enemy(unit, enemies)
			if target != null:
				unit.attack_target_id = target.entity_id
		if target != null:
			if unit.position.distance_to(target.position) <= unit.unit_definition.attack_range and _line_clear(unit.position, target.position, grid):
				unit.set_move_path(PackedVector2Array())
				if unit.cooldown_ticks == 0:
					target.hp = maxi(0, target.hp - unit.unit_definition.damage)
					unit.cooldown_ticks = maxi(1, ceili(unit.unit_definition.attack_seconds * hz))
					unit.shot_ticks = maxi(1, ceili(0.1 * hz))
					unit.shot_target = target.position
					if target.hp == 0:
						dead.append(target.entity_id)
			elif unit.repath_ticks == 0:
				unit.set_move_path(_attack_path(unit, target, registry, grid, navigation))
				unit.repath_ticks = maxi(1, hz / 2)
		else:
			if unit.order == &"attack_move" and not unit.has_move_order:
				if unit.position.distance_to(unit.order_goal) > 0.15 and unit.repath_ticks == 0:
					unit.set_move_path(navigation.find_path(unit.position, Vector2i(unit.order_goal.floor())))
					unit.repath_ticks = hz
				elif unit.position.distance_to(unit.order_goal) <= 0.15:
					unit.order = &"idle"
		_repath_blocked(unit, registry, navigation, hz)
	return dead


func _nearest_enemy(unit: MechEntityState, buckets: Dictionary) -> MechEntityState:
	var center := Vector2i(unit.position.floor())
	var radius: int = ceili(unit.unit_definition.acquisition_range)
	var best: float = unit.unit_definition.acquisition_range * unit.unit_definition.acquisition_range
	var result: MechEntityState
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			for candidate: MechEntityState in buckets.get(Vector2i(x, y), []):
				var distance: float = unit.position.distance_squared_to(candidate.position)
				if candidate.hp > 0 and distance <= best:
					best = distance
					result = candidate
	return result


func _line_clear(from: Vector2, to: Vector2, grid: MechGridState) -> bool:
	for cell: Vector2i in Geometry2D.bresenham_line(Vector2i(from.floor()), Vector2i(to.floor())):
		if grid.terrain_at(cell) == MechGridState.Terrain.OBSTACLE:
			return false
	return true


func _attack_path(unit: MechEntityState, target: MechEntityState, registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation) -> PackedVector2Array:
	var center := Vector2i(target.position.floor())
	var radius: int = ceili(unit.unit_definition.attack_range)
	var candidates: Array[Vector2i] = []
	var occupied: Array[Vector2i] = []
	for other: MechEntityState in registry.all():
		if other.entity_id != unit.entity_id and other.move_speed > 0.0:
			occupied.append(Vector2i(other.position.floor()))
			if other.attack_target_id == target.entity_id and other.has_move_order:
				occupied.append(Vector2i(other.move_target.floor()))
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			var point: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
			if grid.is_walkable(cell) and not cell in occupied and point.distance_to(target.position) <= unit.unit_definition.attack_range and _line_clear(point, target.position, grid):
				candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(unit.position) < Vector2(b).distance_squared_to(unit.position))
	for cell: Vector2i in candidates:
		var path: PackedVector2Array = navigation.find_path_avoiding(unit.position, cell, occupied)
		if not path.is_empty():
			return path
	return PackedVector2Array()


func _repath_blocked(unit: MechEntityState, registry: MechEntityRegistry, navigation: MechGridNavigation, hz: int) -> void:
	if unit.blocked_ticks < hz or not unit.has_move_order:
		return
	var occupied: Array[Vector2i] = []
	for other: MechEntityState in registry.all():
		if other.entity_id != unit.entity_id and other.move_speed > 0.0:
			occupied.append(Vector2i(other.position.floor()))
	var path: PackedVector2Array = navigation.find_path_avoiding(unit.position, Vector2i(unit.move_target.floor()), occupied)
	if not path.is_empty():
		unit.set_move_path(path)
	unit.blocked_ticks = 0
