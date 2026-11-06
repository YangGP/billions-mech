class_name MechEnemySystem
extends RefCounted
## M5 marching and combat for wave-side enemies. Marching reads a weighted
## MechMarchField (terrain × building soft cost, values.md §11): a wide opening is
## always cheaper than chewing walls, so enemies funnel through gaps; with no
## cheap route the field points into the wall and blocker engagement attacks it
## ("撞墙打墙", waves-enemies.md §8). The field recomputes on occupancy changes
## or building HP drift. Enemies are not native RVO agents; stepping is guarded
## here and crowd separation comes from the vendored Steering over grid-bucket
## neighbours. Enemies attacking buildings crowd tighter (partial overlap).

const FLOW_WEIGHT: float = 1.0
const SEPARATION_WEIGHT: float = 0.6
const SEPARATION_RADIUS: float = 0.6
const CROWD_SEPARATION_RADIUS: float = 0.3
const VISION_SCAN_INTERVAL: int = 5
const FIELD_HP_REFRESH_SECONDS: float = 1.0
const CONVERGE_REPATH_SECONDS: float = 2.0
const CONVERGE_ARRIVAL: float = 1.0
const SHUFFLE_DECISION_SECONDS: float = 4.0
const SHUFFLE_RADIUS: int = 5
const SHUFFLE_ATTEMPTS: int = 6

var _field := MechMarchField.new()
var _goal: Vector2i = Vector2i.ZERO
var _field_revision: int = -1
var _field_hp: Dictionary = {}
var _tick_counter: int = 0
var _combat_noise: Callable = Callable()


func configure_noise(emitter: Callable) -> void:
	_combat_noise = emitter


func reset(grid: MechGridState, goal: Vector2i, buildings: Array[MechBuildingState]) -> void:
	_tick_counter = 0
	_goal = goal
	_field_revision = -1
	_field_hp.clear()
	_refresh_field(grid, buildings)


func _refresh_field(grid: MechGridState, buildings: Array[MechBuildingState], hz: int = 30) -> void:
	# Occupancy changes (place/cancel/destroy) rebuild immediately; plain HP drift
	# (walls being chewed) is throttled to once per refresh interval.
	if grid.revision() != _field_revision:
		_rebuild_field(grid, buildings)
		return
	if _tick_counter % maxi(1, ceili(FIELD_HP_REFRESH_SECONDS * hz)) != 0:
		return
	for building: MechBuildingState in buildings:
		if _field_hp.get(building.entity_id, -1) != building.hp:
			_rebuild_field(grid, buildings)
			return


func _rebuild_field(grid: MechGridState, buildings: Array[MechBuildingState]) -> void:
	_field.rebuild(grid, _goal, buildings)
	_field_revision = grid.revision()
	_field_hp.clear()
	for building: MechBuildingState in buildings:
		_field_hp[building.entity_id] = building.hp


func create(registry: MechEntityRegistry, rules: MechEnemyDefinition, position: Vector2) -> int:
	# rvo_speed stays 0 so the RVO pipeline (registry step/snapshots) skips enemies.
	var id: int = registry.create(rules.enemy_id, rules.display_name, position, 0.0, Vector2i.ONE)
	var enemy: MechEntityState = registry.get_entity(id)
	enemy.team = 2
	enemy.enemy_definition = rules
	enemy.hp = rules.max_hp
	enemy.max_hp = rules.max_hp
	enemy.hp_last_tick = rules.max_hp
	enemy.order = &"wandering" if not rules.marches_to_core else &"marching"
	return id


## Returns unit deaths and building damage; SimCore applies them through its own
## removal/economy paths so refunds and capacity follow the existing rules.
func advance(registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation, buildings: Array[MechBuildingState], hz: int, noises: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {"dead_units": [], "building_hits": []}
	_refresh_field(grid, buildings, hz)
	var building_ids: Dictionary = {}
	var buildings_by_id: Dictionary = {}
	var building_cells: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0:
			continue
		building_ids[building.entity_id] = true
		buildings_by_id[building.entity_id] = building
		for y: int in range(building.definition.footprint.y):
			for x: int in range(building.definition.footprint.x):
				building_cells[building.origin + Vector2i(x, y)] = building.entity_id
	var unit_buckets: Dictionary = {}
	var enemy_buckets: Dictionary = {}
	var enemies: Array[MechEntityState] = []
	for entity: MechEntityState in registry.all():
		if entity.hp <= 0:
			continue
		if entity.team == 1 and entity.unit_definition != null:
			var unit_cell := Vector2i(entity.position.floor())
			if not unit_buckets.has(unit_cell):
				unit_buckets[unit_cell] = []
			unit_buckets[unit_cell].append(entity)
		elif entity.team == 2 and entity.enemy_definition != null:
			enemies.append(entity)
			var enemy_cell := Vector2i(entity.position.floor())
			if not enemy_buckets.has(enemy_cell):
				enemy_buckets[enemy_cell] = []
			enemy_buckets[enemy_cell].append(entity)
	var dt: float = 1.0 / float(hz)
	var tick: int = _tick_counter
	_tick_counter += 1
	for enemy: MechEntityState in enemies:
		_advance_one(enemy, registry, grid, navigation, buildings_by_id, building_ids,
			building_cells, unit_buckets, enemy_buckets, noises, tick, dt, hz, result)
	return result


func _advance_one(enemy: MechEntityState, registry: MechEntityRegistry, grid: MechGridState,
		navigation: MechGridNavigation, buildings_by_id: Dictionary, building_ids: Dictionary,
		building_cells: Dictionary, unit_buckets: Dictionary, enemy_buckets: Dictionary,
		noises: Array[Dictionary], tick: int, dt: float, hz: int, result: Dictionary) -> void:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	if rules == null:
		return
	enemy.cooldown_ticks = maxi(0, enemy.cooldown_ticks - 1)
	enemy.shot_ticks = maxi(0, enemy.shot_ticks - 1)
	enemy.repath_ticks = maxi(0, enemy.repath_ticks - 1)
	# Being attacked is an immediate engage condition even between vision scans.
	var provoked: bool = enemy.hp < enemy.hp_last_tick
	enemy.hp_last_tick = enemy.hp
	var scan_due: bool = provoked or (tick + enemy.entity_id) % VISION_SCAN_INTERVAL == 0
	if enemy.order == &"engaged":
		_advance_engaged(enemy, registry, grid, navigation, buildings_by_id, building_ids,
			building_cells, unit_buckets, enemy_buckets, dt, hz, result)
		return
	if scan_due:
		var target: int = _acquire_target(enemy, grid, unit_buckets, building_cells)
		if target > 0:
			_engage(enemy, target)
	if enemy.order == &"engaged":
		_advance_engaged(enemy, registry, grid, navigation, buildings_by_id, building_ids,
			building_cells, unit_buckets, enemy_buckets, dt, hz, result)
		return
	# Wanderers never march to the core: noise convergence or TAB-style shuffling.
	if not enemy.enemy_definition.marches_to_core:
		_advance_wandering(enemy, noises, grid, navigation, enemy_buckets, building_ids, buildings_by_id, dt)
		return
	_advance_marching(enemy, grid, enemy_buckets, building_ids, dt)


## Idle wanderer behaviour: walk toward the loudest heard noise ("闻声缓慢聚拢")
## and, with no noise, occasionally shuffle to a nearby cell at a slow decision
## cadence; the current walk always finishes, so losing a noise source leaves
## them lingering wherever they stopped.
func _advance_wandering(enemy: MechEntityState, noises: Array[Dictionary], grid: MechGridState,
		navigation: MechGridNavigation, enemy_buckets: Dictionary, building_ids: Dictionary,
		buildings_by_id: Dictionary, dt: float) -> void:
	var heard: Dictionary = {}
	var best_radius: float = 0.0
	var best_distance: float = INF
	for noise: Dictionary in noises:
		var distance: float = enemy.position.distance_to(noise["position"])
		if distance > noise["radius"]:
			continue
		var radius: float = noise["radius"]
		if radius > best_radius or (radius == best_radius and distance < best_distance):
			heard = noise
			best_radius = radius
			best_distance = distance
	if not heard.is_empty():
		var goal: Vector2 = heard["position"]
		if enemy.position.distance_to(goal) <= CONVERGE_ARRIVAL:
			enemy.set_move_path(PackedVector2Array())
			enemy.repath_ticks = maxi(1, ceili(CONVERGE_REPATH_SECONDS / dt))
			return
		if enemy.repath_ticks == 0 and (not enemy.has_move_order or enemy.order_goal.distance_to(goal) > 1.0):
			var goal_cell := Vector2i(goal.floor())
			var source_building: MechBuildingState = buildings_by_id.get(grid.occupant_at(goal_cell))
			# Building noise originates inside solid occupancy. Reuse the combat
			# approach cell so AStarGrid2D can lead listeners to its perimeter.
			if source_building != null:
				goal_cell = _building_chase_cell(enemy, source_building, grid)
			var path := PackedVector2Array()
			if grid.is_walkable(goal_cell):
				path = navigation.find_path(enemy.position, goal_cell)
			enemy.repath_ticks = maxi(1, ceili(CONVERGE_REPATH_SECONDS / dt))
			if not path.is_empty():
				enemy.order_goal = goal
				enemy.set_move_path(path)
	elif enemy.repath_ticks == 0 and not enemy.has_move_order:
		# TAB-style idle shuffle: sometimes drift to a random walkable cell nearby.
		enemy.repath_ticks = maxi(1, ceili(SHUFFLE_DECISION_SECONDS / dt))
		var shuffle_target: Vector2i = _shuffle_cell(enemy, grid) if randf() < 0.5 else Vector2i(-1, -1)
		if shuffle_target.x >= 0:
			var path: PackedVector2Array = navigation.find_path(enemy.position, shuffle_target)
			if not path.is_empty():
				enemy.order_goal = Vector2(shuffle_target) + Vector2(0.5, 0.5)
				enemy.set_move_path(path)
	if not enemy.has_move_order:
		return
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var speed: float = enemy.enemy_definition.move_speed / grid.movement_weight(cell)
	var velocity: Vector2 = enemy.preferred_velocity(speed, dt, grid.mobile_segment_clear)
	if velocity == Vector2.ZERO:
		enemy.finish_path_if_arrived()
		return
	var direction: Vector2 = enemy.position.direction_to(enemy.next_waypoint())
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), SEPARATION_RADIUS)
	var blended: Vector2 = Steering.combine(velocity, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, blended, direction, speed, dt, grid, building_ids)
	enemy.finish_path_if_arrived()


func _shuffle_cell(enemy: MechEntityState, grid: MechGridState) -> Vector2i:
	var center: Vector2i = Vector2i(enemy.position.floor())
	for attempt: int in range(SHUFFLE_ATTEMPTS):
		var candidate: Vector2i = center + Vector2i(randi_range(-SHUFFLE_RADIUS, SHUFFLE_RADIUS), randi_range(-SHUFFLE_RADIUS, SHUFFLE_RADIUS))
		if grid.is_walkable(candidate):
			return candidate
	return Vector2i(-1, -1)


func _advance_marching(enemy: MechEntityState, grid: MechGridState, enemy_buckets: Dictionary, building_ids: Dictionary, dt: float) -> void:
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var flow_dir: Vector2 = _field.flow_at(cell)
	if flow_dir == Vector2.ZERO:
		return
	var speed: float = enemy.enemy_definition.move_speed / grid.movement_weight(cell)
	var desired: Vector2 = Steering.desired_velocity(flow_dir, speed)
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), SEPARATION_RADIUS)
	var velocity: Vector2 = Steering.combine(desired, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, velocity, flow_dir, speed, dt, grid, building_ids)


func _advance_engaged(enemy: MechEntityState, registry: MechEntityRegistry, grid: MechGridState,
		navigation: MechGridNavigation, buildings_by_id: Dictionary, building_ids: Dictionary,
		building_cells: Dictionary, unit_buckets: Dictionary, enemy_buckets: Dictionary,
		dt: float, hz: int, result: Dictionary) -> void:
	var target_id: int = enemy.attack_target_id
	var target_building: MechBuildingState = buildings_by_id.get(target_id)
	var target_unit: MechEntityState = null
	if target_building == null:
		target_unit = registry.get_entity(target_id)
		if target_unit == null or target_unit.team != 1 or target_unit.hp <= 0:
			target_unit = null
	if target_building == null and target_unit == null:
		var found: int = _acquire_target(enemy, grid, unit_buckets, building_cells)
		if found > 0:
			_engage(enemy, found)
			target_building = buildings_by_id.get(found)
			if target_building == null:
				target_unit = registry.get_entity(found)
		else:
			_disengage(enemy)
			return
	if target_building == null and target_unit == null:
		_disengage(enemy)
		return
	var rules: MechEnemyDefinition = enemy.enemy_definition
	var aim_point: Vector2
	var in_range: bool
	if target_building != null:
		aim_point = Vector2(target_building.origin) + Vector2(target_building.definition.footprint) * 0.5
		in_range = _building_in_range(enemy, target_building, rules.attack_range)
	else:
		aim_point = target_unit.position
		in_range = enemy.position.distance_to(target_unit.position) <= rules.attack_range
	if in_range and grid.terrain_line_clear(enemy.position, aim_point):
		enemy.set_move_path(PackedVector2Array())
		if enemy.cooldown_ticks == 0:
			enemy.cooldown_ticks = maxi(1, ceili(rules.attack_seconds * hz))
			enemy.shot_ticks = maxi(1, ceili(0.1 * hz))
			enemy.shot_target = aim_point
			if _combat_noise.is_valid():
				_combat_noise.call(aim_point)
			if target_building != null:
				result["building_hits"].append({"id": target_building.entity_id, "damage": rules.building_damage()})
			else:
				target_unit.hp = maxi(0, target_unit.hp - rules.damage)
				if target_unit.hp == 0:
					result["dead_units"].append(target_unit.entity_id)
		return
	# Enemies closing on a building may partially overlap so a crowd can all reach it.
	var separation_radius: float = CROWD_SEPARATION_RADIUS if target_building != null else SEPARATION_RADIUS
	_chase(enemy, grid, navigation, target_building, target_unit, enemy_buckets, building_ids, dt, separation_radius)


func _chase(enemy: MechEntityState, grid: MechGridState, navigation: MechGridNavigation,
		target_building: MechBuildingState, target_unit: MechEntityState,
		enemy_buckets: Dictionary, building_ids: Dictionary, dt: float, separation_radius: float) -> void:
	if enemy.repath_ticks == 0 and not enemy.has_move_order:
		var chase_cell := Vector2i(-1, -1)
		if target_building != null:
			chase_cell = _building_chase_cell(enemy, target_building, grid)
		elif target_unit != null:
			chase_cell = Vector2i(target_unit.position.floor())
		enemy.repath_ticks = _repath_interval(dt)
		if chase_cell.x < 0 or not grid.is_walkable(chase_cell):
			_disengage(enemy)
			return
		var path: PackedVector2Array = navigation.find_path(enemy.position, chase_cell)
		if path.is_empty():
			# Target visible but unreachable: resume the march; blocked steps will
			# engage whatever building stands in the way.
			_disengage(enemy)
			return
		enemy.set_move_path(path)
	if not enemy.has_move_order:
		return
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var speed: float = enemy.enemy_definition.move_speed / grid.movement_weight(cell)
	var velocity: Vector2 = enemy.preferred_velocity(speed, dt, grid.mobile_segment_clear)
	if velocity == Vector2.ZERO:
		# A finished route frees the enemy to re-path toward a moving target.
		enemy.finish_path_if_arrived()
		return
	var direction: Vector2 = enemy.position.direction_to(enemy.next_waypoint())
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), separation_radius)
	var blended: Vector2 = Steering.combine(velocity, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, blended, direction, speed, dt, grid, building_ids)
	enemy.finish_path_if_arrived()


func _repath_interval(dt: float) -> int:
	return maxi(1, ceili(1.0 / dt))


func _engage(enemy: MechEntityState, target_id: int) -> void:
	enemy.order = &"engaged"
	enemy.attack_target_id = target_id
	enemy.set_move_path(PackedVector2Array())
	enemy.repath_ticks = 0


func _disengage(enemy: MechEntityState) -> void:
	# Wanderers idle where the chase ended; wave enemies resume the core march.
	enemy.order = &"wandering" if not enemy.enemy_definition.marches_to_core else &"marching"
	enemy.attack_target_id = 0
	enemy.set_move_path(PackedVector2Array())


func _acquire_target(enemy: MechEntityState, grid: MechGridState, unit_buckets: Dictionary, building_cells: Dictionary) -> int:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	var center: Vector2i = Vector2i(enemy.position.floor())
	var radius: int = ceili(rules.vision_radius)
	var vision_squared: float = rules.vision_radius * rules.vision_radius
	var best: int = 0
	var best_distance: float = INF
	var best_building: int = 0
	var best_building_distance: float = INF
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			for unit: MechEntityState in unit_buckets.get(cell, []):
				# Earlier enemies may have killed this unit during the same pass.
				if unit.hp <= 0:
					continue
				var distance: float = enemy.position.distance_squared_to(unit.position)
				if distance <= vision_squared and distance < best_distance and grid.terrain_line_clear(enemy.position, unit.position):
					best = unit.entity_id
					best_distance = distance
			var building_id: int = building_cells.get(cell, 0)
			if building_id <= 0:
				continue
			var cell_center := Vector2(cell) + Vector2(0.5, 0.5)
			var building_distance: float = enemy.position.distance_squared_to(cell_center)
			if building_distance <= vision_squared and building_distance < best_building_distance and grid.terrain_line_clear(enemy.position, cell_center):
				best_building = building_id
				best_building_distance = building_distance
	if rules.prefers_buildings and best_building > 0:
		return best_building
	return best if best > 0 else best_building


func _separation_neighbors(enemy: MechEntityState, enemy_buckets: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var cell := Vector2i(enemy.position.floor())
	for y: int in range(cell.y - 1, cell.y + 2):
		for x: int in range(cell.x - 1, cell.x + 2):
			for other: MechEntityState in enemy_buckets.get(Vector2i(x, y), []):
				if other.entity_id != enemy.entity_id:
					result.append(other.position)
	return result


## Escalating step guards adapted from the Crusade follower idea: blended step,
## direction-only step, then a cardinal slide toward lower integration cost.
## A building blocker at any level engages that building instead of moving.
func _guarded_step(enemy: MechEntityState, velocity: Vector2, direction: Vector2, speed: float,
		dt: float, grid: MechGridState, building_ids: Dictionary) -> void:
	if velocity.length_squared() <= 0.0:
		return
	var blocker: Dictionary = _blocker_at(enemy.position + velocity * dt, grid, building_ids)
	if blocker["building"] > 0:
		_engage(enemy, blocker["building"])
		return
	if not blocker["blocked"]:
		enemy.position += velocity * dt
		return
	var direct: Vector2 = Steering.desired_velocity(direction, speed) * dt
	if direct.length_squared() > 0.0:
		blocker = _blocker_at(enemy.position + direct, grid, building_ids)
		if blocker["building"] > 0:
			_engage(enemy, blocker["building"])
			return
		if not blocker["blocked"]:
			enemy.position += direct
			return
	_slide_step(enemy, direction, speed, dt, grid, building_ids)


func _slide_step(enemy: MechEntityState, direction: Vector2, speed: float, dt: float,
		grid: MechGridState, building_ids: Dictionary) -> void:
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var step_x: int = int(sign(direction.x))
	var step_y: int = int(sign(direction.y))
	var best_position: Vector2 = enemy.position
	var best_cost: float = INF
	var found: bool = false
	for offset: Vector2i in [Vector2i(step_x, 0), Vector2i(0, step_y)]:
		if offset == Vector2i.ZERO:
			continue
		var neighbour: Vector2i = cell + offset
		var cost: float = _field.cost_at(neighbour)
		if not is_finite(cost) or cost >= best_cost and found:
			continue
		var center: Vector2 = Vector2(neighbour) + Vector2(0.5, 0.5)
		var to_center: Vector2 = center - enemy.position
		if to_center.length_squared() <= 0.0:
			continue
		var candidate: Vector2 = enemy.position + to_center.normalized() * minf(speed * dt, to_center.length())
		var blocker: Dictionary = _blocker_at(candidate, grid, building_ids)
		if blocker["building"] > 0:
			_engage(enemy, blocker["building"])
			return
		if blocker["blocked"]:
			continue
		best_cost = cost
		best_position = candidate
		found = true
	enemy.position = best_position


## Circle-body check mirroring grid mobile rules; classifies the blocker so the
## caller can engage buildings. Non-building occupants behave like static walls.
func _blocker_at(point: Vector2, grid: MechGridState, building_ids: Dictionary) -> Dictionary:
	var radius: float = MechGridState.MOBILE_RADIUS
	var low := Vector2i((point - Vector2.ONE * radius).floor())
	var high := Vector2i((point + Vector2.ONE * radius).floor())
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			var occupant: int = grid.occupant_at(cell)
			var solid_terrain: bool = occupant == 0 and grid.terrain_at(cell) == MechGridState.Terrain.OBSTACLE
			if occupant == 0 and not solid_terrain:
				continue
			var closest := point.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
			if point.distance_squared_to(closest) < radius * radius:
				return {"blocked": true, "building": occupant if occupant > 0 and building_ids.has(occupant) else 0}
	return {"blocked": false, "building": 0}


func _building_in_range(enemy: MechEntityState, building: MechBuildingState, attack_range: float) -> bool:
	# Distance to the footprint rectangle: diagonally adjacent (0.71) also counts
	# as close-quarters contact for a 1-cell melee range.
	var rect := Rect2(Vector2(building.origin), Vector2(building.definition.footprint))
	var clamped := Vector2(clampf(enemy.position.x, rect.position.x, rect.end.x), clampf(enemy.position.y, rect.position.y, rect.end.y))
	return enemy.position.distance_to(clamped) <= attack_range


func _building_chase_cell(enemy: MechEntityState, building: MechBuildingState, grid: MechGridState) -> Vector2i:
	var area := Rect2i(building.origin, building.definition.footprint)
	var best := Vector2i(-1, -1)
	var best_distance: float = INF
	for y: int in range(area.position.y - 1, area.end.y + 1):
		for x: int in range(area.position.x - 1, area.end.x + 1):
			var cell := Vector2i(x, y)
			if area.has_point(cell) or not grid.is_walkable(cell):
				continue
			var distance: float = Vector2(cell).distance_squared_to(enemy.position)
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best
