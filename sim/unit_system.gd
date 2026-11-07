class_name MechUnitSystem
extends RefCounted
## Player orders and the M4 static-target combat loop. No scene dependencies.

## Combat-level noise emitter (set by SimCore); fired at each shot's impact point.
var combat_noise: Callable = Callable()
var _formations := MechFormationPlanner.new()
var _formation_sequence: int = 0


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
	var formation: Dictionary = {}
	if kind == &"attack":
		var enemy: MechEntityState = registry.get_entity(target_id)
		if enemy == null or enemy.team != 2 or enemy.hp <= 0:
			return {"ok": false, "reason": "攻击目标已失效"}
		goal = enemy.position
	else:
		if not goal.is_finite() or not grid.contains(Vector2i(goal.floor())) or not grid.is_walkable(Vector2i(goal.floor())):
			return {"ok": false, "reason": "目标超界或被地形/建筑阻挡"}
		if not grid.mobile_position_clear(goal):
			return {"ok": false, "reason": "目标过于贴近障碍，无法容纳单位"}
		var members: Array[MechEntityState] = []
		for id: int in selected:
			members.append(registry.get_entity(id))
		formation = _formations.plan(members, goal, grid, navigation)
		if not formation["ok"]:
			return formation
		paths = formation["paths"]
	return {"ok": true, "reason": "", "ids": selected.keys(), "kind": kind,
		"goal": goal, "target_id": target_id, "paths": paths, "formation": formation}


func apply_order(plan: Dictionary, registry: MechEntityRegistry) -> void:
	_formation_sequence += 1
	var formation: Dictionary = plan.get("formation", {})
	for id: int in plan["ids"]:
		var unit: MechEntityState = registry.get_entity(id)
		unit.order = plan["kind"]
		unit.attack_target_id = plan["target_id"] if unit.order == &"attack" else 0
		unit.order_goal = plan["goal"]
		unit.repath_ticks = 0
		unit.blocked_ticks = 0
		unit.formation_id = _formation_sequence if not formation.is_empty() else 0
		unit.formation_size = plan["ids"].size() if not formation.is_empty() else 0
		unit.has_arrival_facing = not formation.is_empty()
		if not formation.is_empty():
			unit.arrival_facing = formation["facing"]
			unit.formation_center = formation["center"]
			unit.formation_offset = formation["slots"][id] - formation["center"]
		if plan["paths"].has(id):
			var path: PackedVector2Array = plan["paths"][id]
			unit.order_goal = path[path.size() - 1]
			unit.set_move_path(path)
		else:
			unit.set_move_path(PackedVector2Array())


func spawn(building: MechBuildingState, rally: Vector2i, rules: MechUnitDefinition, registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation) -> bool:
	var occupied: Dictionary = {}
	for entity: MechEntityState in registry.all():
		if entity.rvo_speed > 0.0:
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


func advance(registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation, hz: int, vision: MechVisionSystem) -> Array[int]:
	var dead: Array[int] = []
	var enemies: Dictionary[Vector2i, Array] = {}
	for entity: MechEntityState in registry.all():
		if entity.team == 2 and entity.hp > 0 and vision.is_visible(entity.position):
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
				_resume_order_path(unit, navigation, hz)
			_repath_blocked(unit, navigation, hz)
			continue
		var target: MechEntityState = registry.get_entity(unit.attack_target_id)
		if target != null and not vision.is_visible(target.position):
			# Search the last observed position, never follow a hidden entity ID.
			unit.set_move_path(PackedVector2Array())
			unit.repath_ticks = 0
			unit.attack_target_id = 0
			if unit.order == &"attack":
				unit.order = &"attack_move"
			target = null
		if target == null or target.hp <= 0 or target.team != 2:
			if unit.attack_target_id != 0:
				unit.set_move_path(PackedVector2Array())
				unit.repath_ticks = 0
			target = null
			unit.attack_target_id = 0
			if unit.order == &"attack":
				unit.order = &"idle"
		# An idle unit can fire from its position, but never leave its slot to
		# chase or obtain LOS. Revalidate retained targets as well as new ones.
		if target != null and unit.order == &"idle" and not _can_hit(unit, target, grid):
			unit.attack_target_id = 0
			unit.set_move_path(PackedVector2Array())
			target = null
		if target == null:
			target = _nearest_enemy(unit, enemies, grid)
			if target != null:
				unit.attack_target_id = target.entity_id
				unit.set_move_path(PackedVector2Array())
				unit.repath_ticks = 0
		if target != null:
			if unit.order == &"attack":
				unit.order_goal = target.position
			if _can_hit(unit, target, grid):
				unit.face_direction(target.position - unit.position)
				unit.set_move_path(PackedVector2Array())
				if unit.cooldown_ticks == 0:
					target.hp = maxi(0, target.hp - unit.unit_definition.damage)
					unit.cooldown_ticks = maxi(1, ceili(unit.unit_definition.attack_seconds * hz))
					unit.shot_ticks = maxi(1, ceili(0.1 * hz))
					unit.shot_target = target.position
					if combat_noise.is_valid():
						combat_noise.call(target.position)
					if target.hp == 0:
						dead.append(target.entity_id)
			elif unit.order != &"idle" and unit.repath_ticks == 0 and (not unit.has_move_order or unit.move_target.distance_to(target.position) > unit.unit_definition.attack_range or not _line_clear(unit.move_target, target.position, grid)):
				unit.set_move_path(_attack_path(unit, target, registry, grid, navigation))
				unit.repath_ticks = maxi(1, hz / 2)
		else:
			if unit.order == &"attack_move" and not unit.has_move_order:
				_resume_order_path(unit, navigation, hz)
		_repath_blocked(unit, navigation, hz)
	return dead


func _nearest_enemy(unit: MechEntityState, buckets: Dictionary, grid: MechGridState) -> MechEntityState:
	var center := Vector2i(unit.position.floor())
	var range_cells: float = unit.unit_definition.attack_range if unit.order == &"idle" else unit.unit_definition.acquisition_range
	var radius: int = ceili(range_cells)
	var best: float = range_cells * range_cells
	var result: MechEntityState
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			for candidate: MechEntityState in buckets.get(Vector2i(x, y), []):
				var distance: float = unit.position.distance_squared_to(candidate.position)
				if candidate.hp > 0 and distance <= best and (unit.order != &"idle" or _line_clear(unit.position, candidate.position, grid)):
					best = distance
					result = candidate
	return result


func _can_hit(unit: MechEntityState, target: MechEntityState, grid: MechGridState) -> bool:
	var range_cells: float = unit.unit_definition.attack_range
	return unit.position.distance_squared_to(target.position) <= range_cells * range_cells and _line_clear(unit.position, target.position, grid)


func _line_clear(from: Vector2, to: Vector2, grid: MechGridState) -> bool:
	return grid.terrain_line_clear(from, to)


func _attack_path(unit: MechEntityState, target: MechEntityState, registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation) -> PackedVector2Array:
	var center := Vector2i(target.position.floor())
	var radius: int = ceili(unit.unit_definition.attack_range)
	var candidates: Array[Vector2i] = []
	var occupied: Array[Vector2i] = []
	for other: MechEntityState in registry.all():
		if other.entity_id != unit.entity_id and other.rvo_speed > 0.0:
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
		# Allies reserve firing positions, not whole transit cells in a narrow lane.
		var path: PackedVector2Array = navigation.find_path(unit.position, cell)
		if not path.is_empty():
			return path
	return PackedVector2Array()


func _resume_order_path(unit: MechEntityState, navigation: MechGridNavigation, hz: int) -> void:
	if unit.position.distance_to(unit.order_goal) <= MechEntityState.ARRIVAL_TOLERANCE:
		unit.order = &"idle"
		unit.face_arrival()
		return
	if unit.repath_ticks > 0:
		return
	# An interrupted/empty route is not completion. Retry the original goal,
	# including after displacement, without choosing a nearby substitute.
	unit.set_move_path(navigation.find_path_to_point(unit.position, unit.order_goal))
	unit.repath_ticks = hz


func _repath_blocked(unit: MechEntityState, navigation: MechGridNavigation, hz: int) -> void:
	if unit.blocked_ticks < hz or not unit.has_move_order or unit.repath_ticks > 0:
		return
	var goal: Vector2 = unit.move_target
	if unit.order == &"move" or (unit.order == &"attack_move" and unit.attack_target_id == 0):
		goal = unit.order_goal
	var path: PackedVector2Array = navigation.find_path_to_point(unit.position, goal)
	if not path.is_empty():
		unit.set_move_path(path)
	unit.repath_ticks = hz
