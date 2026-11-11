class_name MechUnitSystem
extends RefCounted
## 玩家指令与 M4 静态目标战斗循环。无场景依赖。
## 对敌人的命中以结果返回；伤害由 SimCore 统一应用，
## 使偏转场与拾荒防护等效果经由同一入口生效。

## 战斗级噪声发射器（由 SimCore 设置）；每次开火的命中点都会触发。
var combat_noise: Callable = Callable()
var _formations := MechFormationPlanner.new()
var _formation_sequence: int = 0


## 创建玩家单位实体并按定义初始化 HP。
func create(registry: MechEntityRegistry, rules: MechUnitDefinition, cell: Vector2i) -> int:
	var id: int = registry.create(rules.unit_id, rules.display_name, Vector2(cell) + Vector2(0.5, 0.5), rules.move_speed)
	var unit: MechEntityState = registry.get_entity(id)
	unit.unit_definition = rules
	unit.hp = rules.max_hp
	unit.max_hp = rules.max_hp
	return id


## 统计存活玩家单位占用的总容量。
func capacity_used(registry: MechEntityRegistry) -> int:
	var total: int = 0
	for entity: MechEntityState in registry.all():
		if entity.team == 1 and entity.unit_definition != null and entity.hp > 0:
			total += entity.unit_definition.capacity_cost
	return total


## 校验并规划一条玩家指令；失败返回原因，成功返回含路径与编队信息的计划。
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
		if unit.garrisoned:
			return {"ok": false, "reason": "驻防中的单位须先撤离"}
		if not grid.is_walkable(Vector2i(unit.position.floor()), true, {}, true):
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
		if not goal.is_finite() or not grid.contains(Vector2i(goal.floor())) or not grid.is_walkable(Vector2i(goal.floor()), true, {}, true):
			return {"ok": false, "reason": "目标超界或被地形/建筑阻挡"}
		if not grid.mobile_position_clear(goal, {}, true):
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


## 将计划写入各单位的实体状态：指令、目标、编队槽位与路径。
func apply_order(plan: Dictionary, registry: MechEntityRegistry) -> void:
	_formation_sequence += 1
	var formation: Dictionary = plan.get("formation", {})
	for id: int in plan["ids"]:
		var unit: MechEntityState = registry.get_entity(id)
		unit.garrison_target_id = 0
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


## 在建筑周边找一个可走空格生成单位，并朝集结点下达移动指令。
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
			if not area.has_point(cell) and grid.is_walkable(cell, true, {}, true) and not occupied.has(cell) and registry.mobile_space_free(Vector2(cell) + Vector2(0.5, 0.5)):
				candidates.append(cell)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(rally) < b.distance_squared_to(rally))
	var id: int = create(registry, rules, candidates[0])
	if grid.is_walkable(rally, true, {}, true):
		var plan: Dictionary = plan_order([id], &"move", Vector2(rally) + Vector2(0.5, 0.5), 0, registry, grid, navigation)
		if plan["ok"]:
			apply_order(plan, registry)
	return true


## 推进一步玩家单位的战斗循环；返回对敌人的命中，由 SimCore 应用伤害。
func advance(registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation, hz: int, vision: MechVisionSystem) -> Dictionary:
	var enemy_hits: Array[Dictionary] = []
	var enemies: Dictionary[Vector2i, Array] = {}
	for entity: MechEntityState in registry.all():
		# 索敌桶只收录玩家视野内的敌人。
		if entity.team == 2 and entity.hp > 0 and vision.is_visible(entity.position):
			var cell := Vector2i(entity.position.floor())
			if not enemies.has(cell):
				enemies[cell] = []
			enemies[cell].append(entity)
	for unit: MechEntityState in registry.all():
		if unit.team != 1 or unit.unit_definition == null or unit.hp <= 0 or unit.garrisoned:
			continue
		unit.cooldown_ticks = maxi(0, unit.cooldown_ticks - 1)
		unit.repath_ticks = maxi(0, unit.repath_ticks - 1)
		unit.shot_ticks = maxi(0, unit.shot_ticks - 1)
		if not grid.is_walkable(Vector2i(unit.position.floor()), true, {}, true):
			continue
		if unit.order == &"move":
			if not unit.has_move_order:
				_resume_order_path(unit, navigation, hz)
			_repath_blocked(unit, navigation, hz)
			continue
		var target: MechEntityState = registry.get_entity(unit.attack_target_id)
		if target != null and not vision.is_visible(target.position):
			# 只朝最后观察到的位置搜索，绝不跟随已隐身的实体 ID。
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
		# 待机单位可原地开火，但绝不离开卡位去追击或争取视线。
		# 对保留目标与新目标都要重新校验。
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
					var stats: Dictionary = _attack_stats(unit, target)
					enemy_hits.append({"id": target.entity_id, "damage": int(stats["damage"]),
						"splash_radius": float(stats["splash_radius"])})
					var hit_ids: Dictionary = {target.entity_id: true}
					for extra: int in range(maxi(0, unit.unit_definition.cleave_targets - 1)):
						var secondary: MechEntityState = _cleave_target(unit, target, enemies, grid, hit_ids)
						if secondary == null:
							break
						hit_ids[secondary.entity_id] = true
						enemy_hits.append({"id": secondary.entity_id,
							"damage": maxi(1, roundi(float(stats["damage"]) * unit.unit_definition.cleave_secondary_ratio)),
							"splash_radius": 0.0})
					unit.cooldown_ticks = maxi(1, ceili(float(stats["cooldown"]) * hz))
					# shot_ticks 仅用于表现层的开火闪烁时长（0.1 秒）。
					unit.shot_ticks = maxi(1, ceili(0.1 * hz))
					unit.shot_target = target.position
					if combat_noise.is_valid():
						combat_noise.call(target.position)
			# 射程外则重寻接近路径：仅在路径缺失、终点过远或视线受阻时重算。
			elif unit.order != &"idle" and unit.repath_ticks == 0 and (not unit.has_move_order or unit.move_target.distance_to(target.position) > unit.unit_definition.attack_range or not _line_clear(unit.move_target, target.position, grid)):
				unit.set_move_path(_attack_path(unit, target, registry, grid, navigation))
				# 追击路径每 0.5 秒重算一次。
				unit.repath_ticks = maxi(1, hz / 2)
		else:
			if unit.order == &"attack_move" and not unit.has_move_order:
				_resume_order_path(unit, navigation, hz)
		_repath_blocked(unit, navigation, hz)
	return {"enemy_hits": enemy_hits}


## 就近索敌：待机时用射程且要求视线通畅，行军时用更大的索敌半径。
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
	var range_cells: float = _weapon_range(unit, unit.position.distance_to(target.position))
	return unit.position.distance_squared_to(target.position) <= range_cells * range_cells and _line_clear(unit.position, target.position, grid)


func _weapon_range(unit: MechEntityState, distance: float) -> float:
	var rules: MechUnitDefinition = unit.unit_definition
	if rules.secondary_damage > 0 and distance > rules.weapon_switch_range:
		return rules.secondary_range
	return rules.primary_range if rules.primary_range > 0.0 else rules.attack_range


func _attack_stats(unit: MechEntityState, target: MechEntityState) -> Dictionary:
	var rules: MechUnitDefinition = unit.unit_definition
	var distance: float = unit.position.distance_to(target.position)
	if rules.secondary_damage > 0 and distance > rules.weapon_switch_range:
		return {"damage": rules.secondary_damage, "cooldown": rules.secondary_attack_seconds,
			"splash_radius": rules.secondary_splash_radius}
	return {"damage": rules.damage, "cooldown": rules.attack_seconds, "splash_radius": rules.splash_radius}


func _cleave_target(unit: MechEntityState, primary: MechEntityState, buckets: Dictionary,
		grid: MechGridState, hit_ids: Dictionary) -> MechEntityState:
	var radius: int = ceili(unit.unit_definition.attack_range)
	var center := Vector2i(unit.position.floor())
	var best: float = INF
	var result: MechEntityState
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			for candidate: MechEntityState in buckets.get(Vector2i(x, y), []):
				if candidate.entity_id == primary.entity_id or hit_ids.has(candidate.entity_id):
					continue
				if candidate.hp <= 0 or not _can_hit(unit, candidate, grid):
					continue
				var distance: float = unit.position.distance_squared_to(candidate.position)
				if distance < best:
					best = distance
					result = candidate
	return result


func _line_clear(from: Vector2, to: Vector2, grid: MechGridState) -> bool:
	return grid.terrain_line_clear(from, to)


## 求进入目标射程的接近路径：目标周边射击位按距离排序，取首个可达者。
func _attack_path(unit: MechEntityState, target: MechEntityState, registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation) -> PackedVector2Array:
	var center := Vector2i(target.position.floor())
	var radius: int = ceili(unit.unit_definition.attack_range)
	var candidates: Array[Vector2i] = []
	var occupied: Array[Vector2i] = []
	for other: MechEntityState in registry.all():
		if other.entity_id != unit.entity_id and other.rvo_speed > 0.0:
			occupied.append(Vector2i(other.position.floor()))
			# 攻击同一目标的友军若在移动，其移动终点也视为占位（预订射击位）。
			if other.attack_target_id == target.entity_id and other.has_move_order:
				occupied.append(Vector2i(other.move_target.floor()))
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			var point: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
			if grid.is_walkable(cell, true, {}, true) and not cell in occupied and point.distance_to(target.position) <= unit.unit_definition.attack_range and _line_clear(point, target.position, grid):
				candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(unit.position) < Vector2(b).distance_squared_to(unit.position))
	for cell: Vector2i in candidates:
		# 友军只预订射击位，而非整条窄道中的通行格。
		var path: PackedVector2Array = navigation.find_path(unit.position, cell)
		if not path.is_empty():
			return path
	return PackedVector2Array()


## 恢复指令路径：抵达则转待机并朝向，否则按原目标重寻路。
func _resume_order_path(unit: MechEntityState, navigation: MechGridNavigation, hz: int) -> void:
	if unit.position.distance_to(unit.order_goal) <= MechEntityState.ARRIVAL_TOLERANCE:
		unit.order = &"idle"
		unit.face_arrival()
		return
	if unit.repath_ticks > 0:
		return
	# 被打断/空路径不算抵达。重试原目标点（包括被挤出后），
	# 不就近替换目标。
	unit.set_move_path(navigation.find_path_to_point(unit.position, unit.order_goal))
	unit.repath_ticks = hz


## 卡位重寻路：被阻挡满一秒且仍有移动指令时，按原目标重算路径。
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
