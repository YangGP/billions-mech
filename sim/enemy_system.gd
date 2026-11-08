class_name MechEnemySystem
extends RefCounted
## Horde marching: a static terrain field provides the strategic direction.
## Overlapping local fields route unengaged enemies through reachable gaps and
## offer short, forward building detours. An engaged enemy keeps its target;
## walls are attacked on contact, never selected just because they are visible.
## HP does not invalidate any field. Local fields use actual movement rules;
## wall passers share the global field and cache wall-exempt local fields.

const FLOW_WEIGHT: float = 1.0
const SEPARATION_WEIGHT: float = 0.6
const SEPARATION_RADIUS: float = 0.6
const CROWD_SEPARATION_RADIUS: float = 0.3
const VISION_SCAN_INTERVAL: int = 5
const FOG_DECISION_STRIDE: int = 4
const ACTIVITY_BUCKET_SIZE: int = 16
const CONVERGE_REPATH_SECONDS: float = 2.0
const CONVERGE_ARRIVAL: float = 1.0
## 32×32 fields, spaced 16 cells apart: overlapping bounds keep routes stable
## while crossing regions. One local construction task may be in flight.
const ASSAULT_ZONE_SIZE: int = 32
const ASSAULT_ZONE_STRIDE: int = 16
const ASSAULT_ZONE_MARGIN: int = 2
const OPPORTUNISTIC_RANGE: float = 3.0
const OPPORTUNISTIC_DETOUR: float = 2.0
const BREACH_DETOUR: float = 8.0
const SHUFFLE_DECISION_SECONDS: float = 8.0
const SHUFFLE_RADIUS: int = 2
const SHUFFLE_ATTEMPTS: int = 6

const WALL_ID: StringName = &"armored_wall"

var profiling_enabled: bool = false
var _field := MechMarchField.new()
## Wall passers follow the normal march field; they only ignore wall collision
## while moving. The extra A* map is for chase/path queries, not a second field.
var _proto_navigation := MechGridNavigation.new()
var _wall_ids: Dictionary = {}
var _goal: Vector2i = Vector2i.ZERO
var _field_revision: int = -1
var _proto_navigation_revision: int = -1
var _proto_navigation_geometry: Dictionary = {}
var _zones: Dictionary = {}
var _zone_grid_revision: int = -1
var _zone_task: int = -1
var _zone_result: Dictionary = {}
var _zone_mutex := Mutex.new()
var _tick_counter: int = 0
var _combat_noise: Callable = Callable()
var _field_task: int = -1
var _field_result: Dictionary = {}
var _field_mutex := Mutex.new()


func configure_noise(emitter: Callable) -> void:
	_combat_noise = emitter


func reset(_grid: MechGridState, goal: Vector2i, _buildings: Array[MechBuildingState]) -> void:
	shutdown()
	_tick_counter = 0
	_goal = goal
	_field = MechMarchField.new()
	_proto_navigation = MechGridNavigation.new()
	_field_revision = -1
	_proto_navigation_revision = -1
	_proto_navigation_geometry.clear()
	_zones.clear()
	_zone_grid_revision = -1
	_wall_ids.clear()


func shutdown() -> void:
	if _field_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_field_task)
		_field_task = -1
	_field_result = {}
	if _zone_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_zone_task)
		_zone_task = -1
	_zone_result = {}


## The shared field only depends on static terrain, so it never needs a
## signature. The wall-pass A* still needs non-wall geometry for chase/path
## queries; wall geometry and wall HP are deliberately absent there.
func _nav_signature(buildings: Array[MechBuildingState]) -> Dictionary:
	var proto_geometry: Dictionary = {}
	var wall_ids: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0:
			continue
		if building.definition.building_id == WALL_ID:
			wall_ids[building.entity_id] = true
		if Rect2i(building.origin, building.definition.footprint).has_point(_goal):
			continue
		if building.definition.building_id != WALL_ID:
			proto_geometry[building.entity_id] = Vector4i(
				building.origin.x, building.origin.y,
				building.definition.footprint.x, building.definition.footprint.y
			)
	return {"proto_geometry": proto_geometry, "wall_ids": wall_ids}


func _refresh_field(grid: MechGridState, buildings: Array[MechBuildingState], need_main: bool, need_proto: bool) -> void:
	# Wanderers use the existing A* and never consume the core march field.
	# The shared field is terrain-only and never invalidated by buildings.
	_collect_field_result(buildings)
	if _field_task >= 0 or (not need_main and not need_proto):
		return
	var revision: int = grid.revision()
	var signatures: Dictionary = _nav_signature(buildings)
	var proto_geometry: Dictionary = signatures["proto_geometry"]
	var wall_ids: Dictionary = signatures["wall_ids"]
	var rebuild_main: bool = need_main and _field_revision < 0
	# The wall-pass A* is only for chase/path queries; it ignores wall
	# occupancy, so only non-wall geometry invalidates it.
	var nav_stale: bool = _proto_navigation_revision < 0 \
		or _proto_navigation_geometry != proto_geometry
	var rebuild_nav: bool = need_proto and nav_stale
	if not rebuild_main and not rebuild_nav:
		_wall_ids = wall_ids
		return
	var started: int = Time.get_ticks_usec() if profiling_enabled else 0
	_wall_ids = wall_ids
	var job: Dictionary = {"grid": grid.navigation_copy(), "goal": _goal,
		"wall_ids": wall_ids, "revision": revision,
		"main": rebuild_main, "nav": rebuild_nav,
		"proto_geometry": proto_geometry, "profiling": profiling_enabled}
	_field_task = WorkerThreadPool.add_task(_compute_fields.bind(job), false, "Mech march fields")
	if profiling_enabled:
		print("[perf:fields] submit_ms=%.3f revision=%d" % [(Time.get_ticks_usec() - started) / 1000.0, revision])


func _compute_fields(job: Dictionary) -> void:
	var started: int = Time.get_ticks_usec() if job["profiling"] else 0
	var output: Dictionary = {"revision": job["revision"],
		"proto_geometry": job["proto_geometry"], "wall_ids": job["wall_ids"]}
	var grid: MechGridState = job["grid"]
	if job["main"]:
		var field := MechMarchField.new()
		field.rebuild(grid, job["goal"])
		output["field"] = field
	if job["nav"]:
		# Each AStarGrid2D is owned by one thread at a time, then handed off
		# after task completion; no live A* object is accessed concurrently.
		var navigation := MechGridNavigation.new()
		navigation.rebuild(grid, job["wall_ids"])
		output["navigation"] = navigation
	if job["profiling"]:
		output["worker_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	_field_mutex.lock()
	_field_result = output
	_field_mutex.unlock()


func _collect_field_result(buildings: Array[MechBuildingState]) -> void:
	if _field_task < 0 or not WorkerThreadPool.is_task_completed(_field_task):
		return
	WorkerThreadPool.wait_for_task_completion(_field_task)
	_field_task = -1
	_field_mutex.lock()
	var result: Dictionary = _field_result
	_field_result = {}
	_field_mutex.unlock()
	var current: Dictionary = _nav_signature(buildings)
	# The shared field is terrain-only and valid regardless of buildings. The
	# wall-pass A* is only used for chase/path queries and depends on non-wall
	# geometry.
	var nav_ok: bool = result.get("proto_geometry", {}) == current["proto_geometry"]
	var applied_main: bool = false
	var applied_nav: bool = false
	if result.has("field"):
		_field = result["field"]
		_field_revision = result["revision"]
		applied_main = true
	if result.has("navigation") and nav_ok:
		_proto_navigation = result["navigation"]
		_proto_navigation_revision = result["revision"]
		_proto_navigation_geometry = result["proto_geometry"]
		applied_nav = true
	elif result.has("navigation"):
		_proto_navigation_revision = -1
	_wall_ids = current["wall_ids"]
	if result.has("worker_ms"):
		print("[perf:fields] worker_ms=%.3f main=%s nav=%s revision=%d" % [
			result["worker_ms"], applied_main, applied_nav, result["revision"]])


## Bind only marching enemies near assets. Existing assignments survive until
## the inner edge of their bounds is crossed; neighbouring regions overlap.
func _refresh_zones(enemies: Array[MechEntityState], buildings: Array[MechBuildingState], grid: MechGridState, active_regions: Dictionary) -> void:
	if _field_revision < 0:
		return
	_collect_zone_result(grid, buildings)
	var changed: Array[Vector2i] = []
	if _zone_grid_revision != grid.revision():
		changed = grid.navigation_changes_since(_zone_grid_revision)
	_zone_grid_revision = grid.revision()
	for zone: Dictionary in _zones.values():
		if zone["dirty"]:
			continue
		var bounds: Rect2i = zone["bounds"]
		var forward: MechMarchField = zone["forward"]
		var ignored: Dictionary = _wall_ids if zone["passes_walls"] else {}
		var touched: bool = false
		for cell: Vector2i in changed:
			if not bounds.grow(1).has_point(cell):
				continue
			touched = true
			# An adjacent footprint can add/remove an attack position just inside
			# the region even when its occupied cells lie outside the bounds.
			var adjacent: bool = bounds.grow(1).has_point(cell) and not bounds.has_point(cell)
			if adjacent or (bounds.has_point(cell) and forward.blocks_at(cell) == grid.is_walkable(cell, true, ignored)):
				zone["dirty"] = true
				break
		if touched and not zone["dirty"] and zone["source_key"] != _zone_source_key(bounds, buildings):
			zone["dirty"] = true
	var active: Dictionary = {}
	for enemy: MechEntityState in enemies:
		if not enemy.enemy_definition.marches_to_core:
			continue
		var cell := Vector2i(enemy.position.floor())
		var previous: Dictionary = _zones.get(enemy.march_zone, {})
		if not previous.is_empty() and previous["bounds"].grow(-ASSAULT_ZONE_MARGIN).has_point(cell):
			active[enemy.march_zone] = true
			continue
		enemy.march_zone = Vector3i(-1, -1, -1)
		if not active_regions.has(_activity_bucket(cell)):
			continue
		var center := Vector2i(
			floori(float(cell.x) / ASSAULT_ZONE_STRIDE) * ASSAULT_ZONE_STRIDE + ASSAULT_ZONE_STRIDE / 2,
			floori(float(cell.y) / ASSAULT_ZONE_STRIDE) * ASSAULT_ZONE_STRIDE + ASSAULT_ZONE_STRIDE / 2
		)
		var key := Vector3i(center.x, center.y, int(enemy.enemy_definition.passes_walls))
		if not _zones.has(key):
			var half: int = ASSAULT_ZONE_SIZE / 2
			var bounds := Rect2i(center - Vector2i(half, half), Vector2i(ASSAULT_ZONE_SIZE, ASSAULT_ZONE_SIZE))
			bounds = bounds.intersection(Rect2i(Vector2i.ZERO, grid.dimensions()))
			_zones[key] = {"bounds": bounds, "passes_walls": enemy.enemy_definition.passes_walls,
				"forward": MechMarchField.new(), "buildings": MechMarchField.new(),
				"owners": {}, "dirty": true}
		enemy.march_zone = key
		active[key] = true
	for key: Vector3i in active:
		var zone: Dictionary = _zones[key]
		if zone["dirty"] and _zone_task < 0:
			_submit_zone(key, zone, grid, buildings)
			break


func _submit_zone(key: Vector3i, zone: Dictionary, grid: MechGridState, buildings: Array[MechBuildingState]) -> void:
	var started: int = Time.get_ticks_usec() if profiling_enabled else 0
	var frozen: Array[MechBuildingState] = []
	var bounds: Rect2i = zone["bounds"]
	for building: MechBuildingState in buildings:
		if building.hp <= 0 or building.definition.building_id == WALL_ID or not bounds.grow(1).intersects(Rect2i(building.origin, building.definition.footprint)):
			continue
		var copy := MechBuildingState.new()
		copy.entity_id = building.entity_id
		copy.origin = building.origin
		copy.hp = 1
		copy.definition = building.definition
		frozen.append(copy)
	var input: Dictionary = {"key": key, "bounds": zone["bounds"], "passes_walls": zone["passes_walls"],
		"grid": grid.navigation_copy(), "revision": grid.revision(), "buildings": frozen,
		"global": _field, "wall_ids": _wall_ids.duplicate(), "profiling": profiling_enabled}
	_zone_task = WorkerThreadPool.add_task(_compute_zone.bind(input), false, "Mech local field")
	if profiling_enabled:
		print("[perf:assault-submit] ms=%.3f bounds=%s" % [(Time.get_ticks_usec() - started) / 1000.0, bounds])


func _compute_zone(input: Dictionary) -> void:
	var started: int = Time.get_ticks_usec() if input["profiling"] else 0
	var zone: Dictionary = {"bounds": input["bounds"], "passes_walls": input["passes_walls"],
		"forward": MechMarchField.new(), "buildings": MechMarchField.new(), "owners": {}, "dirty": true}
	_build_zone(zone, input["grid"], input["buildings"], input["global"], input["wall_ids"])
	var result: Dictionary = {"key": input["key"], "zone": zone, "revision": input["revision"]}
	if input["profiling"]:
		result["worker_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	_zone_mutex.lock()
	_zone_result = result
	_zone_mutex.unlock()


func _collect_zone_result(grid: MechGridState, buildings: Array[MechBuildingState]) -> void:
	if _zone_task < 0 or not WorkerThreadPool.is_task_completed(_zone_task):
		return
	WorkerThreadPool.wait_for_task_completion(_zone_task)
	_zone_task = -1
	_zone_mutex.lock()
	var result: Dictionary = _zone_result
	_zone_result = {}
	_zone_mutex.unlock()
	var zone: Dictionary = result["zone"]
	var bounds: Rect2i = zone["bounds"]
	var forward: MechMarchField = zone["forward"]
	var ignored: Dictionary = _wall_ids if zone["passes_walls"] else {}
	var valid: bool = zone["source_key"] == _zone_source_key(bounds, buildings)
	# Other regions and pure HP events do not invalidate this result. Validate
	# only changed occupancy affecting this region or its attack-position rim.
	for cell: Vector2i in grid.navigation_changes_since(result["revision"]):
		var adjacent: bool = bounds.grow(1).has_point(cell) and not bounds.has_point(cell)
		if adjacent or (bounds.has_point(cell) and forward.blocks_at(cell) == grid.is_walkable(cell, true, ignored)):
			valid = false
			break
	if valid:
		_zones[result["key"]] = zone
	if result.has("worker_ms"):
		print("[perf:assault] worker_ms=%.3f applied=%s bounds=%s targets=%d passes_walls=%s" % [
			result["worker_ms"], valid, bounds, zone["owners"].size(), zone["passes_walls"]])


func _zone_source_key(bounds: Rect2i, buildings: Array[MechBuildingState]) -> Dictionary:
	var key: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp > 0 and building.definition.building_id != WALL_ID and bounds.grow(1).intersects(Rect2i(building.origin, building.definition.footprint)):
			key[building.entity_id] = Vector4i(building.origin.x, building.origin.y,
				building.definition.footprint.x, building.definition.footprint.y)
	return key


## Sources on the region boundary inherit the global integration value. Core
## attack positions are additional exits when the core lies inside this zone.
## This connects local open routes to strategic progress, including fresh gaps.
func _build_zone(zone: Dictionary, grid: MechGridState, buildings: Array[MechBuildingState], global_field: MechMarchField, wall_ids: Dictionary) -> void:
	var bounds: Rect2i = zone["bounds"]
	var ignored: Dictionary = wall_ids if zone["passes_walls"] else {}
	var exits: Dictionary = {}
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if x != bounds.position.x and x != bounds.end.x - 1 and y != bounds.position.y and y != bounds.end.y - 1:
				continue
			var cell := Vector2i(x, y)
			if grid.is_walkable(cell, true, ignored) and global_field.is_reachable(cell):
				exits[cell] = global_field.cost_at(cell)
	var owners: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0 or building.definition.building_id == WALL_ID:
			continue
		var area := Rect2i(building.origin, building.definition.footprint)
		if not bounds.intersects(area.grow(1)):
			continue
		for y: int in range(area.position.y - 1, area.end.y + 1):
			for x: int in range(area.position.x - 1, area.end.x + 1):
				var cell := Vector2i(x, y)
				if area.has_point(cell) or not bounds.has_point(cell) or not grid.is_walkable(cell, true, ignored):
					continue
				if building.definition.is_core:
					exits[cell] = global_field.cost_at(cell)
				elif not owners.has(cell):
					owners[cell] = building.entity_id
	var exit_cells: Array[Vector2i] = []
	for cell: Vector2i in exits:
		exit_cells.append(cell)
	var targets: Array[Vector2i] = []
	for cell: Vector2i in owners:
		targets.append(cell)
	var forward: MechMarchField = zone["forward"]
	var nearby: MechMarchField = zone["buildings"]
	forward.rebuild_local(grid, bounds, exit_cells, exits, ignored)
	nearby.rebuild_local(grid, bounds, targets, {}, ignored)
	zone["owners"] = owners
	zone["source_key"] = _zone_source_key(bounds, buildings)
	zone["dirty"] = false


## A locally reachable exit must improve strategic progress. Limit the extra
## route length, so a region cannot lure a horde into a long retreat/detour.
func _march_field_for(enemy: MechEntityState) -> MechMarchField:
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	if zone.is_empty() or zone["dirty"]:
		return _field
	var local: MechMarchField = zone["forward"]
	var cell := Vector2i(enemy.position.floor())
	var source: Vector2i = local.source_at(cell)
	if source.x < 0:
		return _field
	var here: float = _field.cost_at(cell)
	if _field.cost_at(source) >= here or local.cost_at(cell) > here + BREACH_DETOUR:
		return _field
	return local


## Nearby buildings are optional short detours, never a clear-the-entire-zone
## objective. Disconnected targets have INF cost and cannot keep a zone active.
func _opportunistic_target(enemy: MechEntityState) -> int:
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	if zone.is_empty() or zone["dirty"]:
		return 0
	var nearby: MechMarchField = zone["buildings"]
	var cell := Vector2i(enemy.position.floor())
	var distance: float = nearby.cost_at(cell)
	if distance > minf(OPPORTUNISTIC_RANGE, enemy.enemy_definition.vision_radius):
		return 0
	var source: Vector2i = nearby.source_at(cell)
	var progress: float = _field.cost_at(source) - _field.cost_at(cell)
	if progress > 0.0 or distance + progress > OPPORTUNISTIC_DETOUR:
		return 0
	return zone["owners"].get(source, 0)


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
func advance(registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation, buildings: Array[MechBuildingState], hz: int, noises: Array[Dictionary], vision: MechVisionSystem) -> Dictionary:
	var result: Dictionary = {"dead_units": [], "building_hits": []}
	var buildings_by_id: Dictionary = {}
	var building_cells: Dictionary = {}
	var non_wall_cells: Dictionary = {}
	var active_regions: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0:
			continue
		buildings_by_id[building.entity_id] = building
		for y: int in range(building.definition.footprint.y):
			for x: int in range(building.definition.footprint.x):
				building_cells[building.origin + Vector2i(x, y)] = building.entity_id
				if building.definition.building_id != WALL_ID:
					non_wall_cells[building.origin + Vector2i(x, y)] = building.entity_id
				_mark_active_region(building.origin + Vector2i(x, y), active_regions)
	var unit_buckets: Dictionary = {}
	var enemy_buckets: Dictionary = {}
	var enemies: Array[MechEntityState] = []
	var need_main: bool = false
	var need_proto: bool = false
	for entity: MechEntityState in registry.all():
		if entity.hp <= 0:
			continue
		if entity.team == 1 and entity.unit_definition != null:
			var unit_cell := Vector2i(entity.position.floor())
			if not unit_buckets.has(unit_cell):
				unit_buckets[unit_cell] = []
			unit_buckets[unit_cell].append(entity)
			_mark_active_region(unit_cell, active_regions)
		elif entity.team == 2 and entity.enemy_definition != null:
			enemies.append(entity)
			need_proto = need_proto or entity.enemy_definition.passes_walls
			# Wall passers read the same weighted field as normal marchers;
			# only their collision ignores armored walls.
			need_main = need_main or entity.enemy_definition.marches_to_core
			var enemy_cell := Vector2i(entity.position.floor())
			if not enemy_buckets.has(enemy_cell):
				enemy_buckets[enemy_cell] = []
			enemy_buckets[enemy_cell].append(entity)
	_refresh_field(grid, buildings, need_main, need_proto)
	_refresh_zones(enemies, buildings, grid, active_regions)
	var dt: float = 1.0 / float(hz)
	var tick: int = _tick_counter
	_tick_counter += 1
	for enemy: MechEntityState in enemies:
		if enemy.slow_ticks > 0:
			enemy.slow_ticks -= 1
		enemy.slow_multiplier = 0.4 if enemy.slow_ticks > 0 else 1.0
		enemy.slow_multiplier = minf(enemy.slow_multiplier, enemy.fence_slow_multiplier)
		var cell := Vector2i(enemy.position.floor())
		var near_assets: bool = active_regions.has(_activity_bucket(cell))
		var local_radius: float = maxf(enemy.enemy_definition.vision_radius, enemy.enemy_definition.attack_range)
		var coarse: bool = not vision.is_visible(enemy.position) and not near_assets and local_radius <= ACTIVITY_BUCKET_SIZE
		if enemy.fog_coarse and not coarse:
			enemy.repath_ticks = 0
		enemy.fog_coarse = coarse
		var passes_walls: bool = enemy.enemy_definition.passes_walls
		_advance_one(enemy, registry, grid, _proto_navigation if passes_walls else navigation, buildings_by_id,
			non_wall_cells if passes_walls else building_cells, unit_buckets, enemy_buckets, noises, tick, dt, hz, result, coarse)
	return result


func _activity_bucket(cell: Vector2i) -> Vector2i:
	return Vector2i(Vector2(cell) / float(ACTIVITY_BUCKET_SIZE))


func _mark_active_region(cell: Vector2i, regions: Dictionary) -> void:
	var bucket: Vector2i = _activity_bucket(cell)
	# At least sixteen tiles of margin: combat and nearby enemy perception keep
	# full cadence even in terrain blind spots. Fog never disables enemy senses.
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			regions[bucket + Vector2i(x, y)] = true


func _advance_one(enemy: MechEntityState, registry: MechEntityRegistry, grid: MechGridState,
		navigation: MechGridNavigation, buildings_by_id: Dictionary,
		building_cells: Dictionary, unit_buckets: Dictionary, enemy_buckets: Dictionary,
		noises: Array[Dictionary], tick: int, dt: float, hz: int, result: Dictionary, coarse: bool) -> void:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	if rules == null:
		return
	if rules.passes_walls and _proto_navigation_revision < 0:
		return
	enemy.cooldown_ticks = maxi(0, enemy.cooldown_ticks - 1)
	enemy.shot_ticks = maxi(0, enemy.shot_ticks - 1)
	enemy.repath_ticks = maxi(0, enemy.repath_ticks - 1)
	# Being attacked is an immediate engage condition even between vision scans.
	var provoked: bool = enemy.hp < enemy.hp_last_tick
	enemy.hp_last_tick = enemy.hp
	var stride: int = FOG_DECISION_STRIDE if coarse and not provoked else 1
	var scan_due: bool = provoked or (tick + enemy.entity_id) % (VISION_SCAN_INTERVAL * stride) == 0
	if enemy.order == &"engaged":
		_advance_engaged(enemy, registry, grid, navigation, buildings_by_id,
			building_cells, unit_buckets, enemy_buckets, dt, hz, result)
		return
	if scan_due:
		var target: int = _acquire_target(enemy, grid, unit_buckets, building_cells, buildings_by_id)
		if target > 0:
			_engage(enemy, target)
	if enemy.order == &"engaged":
		_advance_engaged(enemy, registry, grid, navigation, buildings_by_id,
			building_cells, unit_buckets, enemy_buckets, dt, hz, result)
		return
	# Wanderers never march to the core: noise convergence or TAB-style shuffling.
	if not enemy.enemy_definition.marches_to_core:
		var decision_due: bool = (tick + enemy.entity_id) % stride == 0
		_advance_wandering(enemy, noises, grid, navigation, enemy_buckets, buildings_by_id, dt, decision_due, stride)
		return
	_advance_marching(enemy, grid, enemy_buckets, buildings_by_id, dt)


## Idle wanderer behaviour: walk toward the loudest heard noise ("闻声缓慢聚拢")
## and, with no noise, occasionally shuffle to a nearby cell at a slow decision
## cadence; the current walk always finishes, so losing a noise source leaves
## them lingering wherever they stopped.
func _advance_wandering(enemy: MechEntityState, noises: Array[Dictionary], grid: MechGridState,
		navigation: MechGridNavigation, enemy_buckets: Dictionary, buildings_by_id: Dictionary,
		dt: float, decision_due: bool, stride: int) -> void:
	if not decision_due:
		_walk_wanderer(enemy, grid, enemy_buckets, buildings_by_id, dt)
		return
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
			enemy.repath_ticks = maxi(1, ceili(CONVERGE_REPATH_SECONDS * stride / dt))
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
			enemy.repath_ticks = maxi(1, ceili(CONVERGE_REPATH_SECONDS * stride / dt))
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
	_walk_wanderer(enemy, grid, enemy_buckets, buildings_by_id, dt)


func _walk_wanderer(enemy: MechEntityState, grid: MechGridState, enemy_buckets: Dictionary, buildings_by_id: Dictionary, dt: float) -> void:
	# Movement, collision, cooldowns and damage retain the normal tick duration.
	if not enemy.has_move_order:
		return
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var speed: float = enemy.enemy_definition.move_speed * enemy.enemy_definition.wandering_speed_ratio * enemy.slow_multiplier / grid.movement_weight(cell)
	var velocity: Vector2 = enemy.preferred_velocity(speed, dt, grid.mobile_segment_clear.bind(_wall_ids if enemy.enemy_definition.passes_walls else {}))
	if velocity == Vector2.ZERO:
		enemy.finish_path_if_arrived()
		return
	var direction: Vector2 = enemy.position.direction_to(enemy.next_waypoint())
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), SEPARATION_RADIUS)
	var blended: Vector2 = Steering.combine(velocity, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, blended, direction, speed, dt, grid, buildings_by_id)
	enemy.finish_path_if_arrived()


func _shuffle_cell(enemy: MechEntityState, grid: MechGridState) -> Vector2i:
	var center: Vector2i = Vector2i(enemy.position.floor())
	for attempt: int in range(SHUFFLE_ATTEMPTS):
		var candidate: Vector2i = center + Vector2i(randi_range(-SHUFFLE_RADIUS, SHUFFLE_RADIUS), randi_range(-SHUFFLE_RADIUS, SHUFFLE_RADIUS))
		if grid.is_walkable(candidate):
			return candidate
	return Vector2i(-1, -1)


func _advance_marching(enemy: MechEntityState, grid: MechGridState, enemy_buckets: Dictionary, buildings_by_id: Dictionary, dt: float) -> void:
	var cell: Vector2i = Vector2i(enemy.position.floor())
	if _field_revision < 0:
		return
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	# Wait briefly for the bounded region job instead of committing to another
	# wall while a newly opened gap has not been integrated yet.
	if not zone.is_empty() and zone["dirty"]:
		return
	var field: MechMarchField = _march_field_for(enemy)
	var flow_dir: Vector2 = field.flow_at(cell)
	if flow_dir == Vector2.ZERO:
		flow_dir = _field.flow_at(cell)
	var speed: float = enemy.enemy_definition.move_speed * enemy.slow_multiplier / grid.movement_weight(cell)
	var desired: Vector2 = Steering.desired_velocity(flow_dir, speed)
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), SEPARATION_RADIUS)
	var velocity: Vector2 = Steering.combine(desired, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, velocity, flow_dir, speed, dt, grid, buildings_by_id)


func _advance_engaged(enemy: MechEntityState, registry: MechEntityRegistry, grid: MechGridState,
		navigation: MechGridNavigation, buildings_by_id: Dictionary,
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
		# A destroyed wall releases its attackers back into marching. Surviving
		# wall targets never pass this branch, so a new gap does not retarget them.
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
	_chase(enemy, grid, navigation, target_building, target_unit, enemy_buckets, buildings_by_id, dt, separation_radius)


func _chase(enemy: MechEntityState, grid: MechGridState, navigation: MechGridNavigation,
		target_building: MechBuildingState, target_unit: MechEntityState,
		enemy_buckets: Dictionary, buildings_by_id: Dictionary, dt: float, separation_radius: float) -> void:
	if enemy.repath_ticks == 0 and not enemy.has_move_order:
		var chase_cell := Vector2i(-1, -1)
		if target_building != null:
			chase_cell = _building_chase_cell(enemy, target_building, grid)
		elif target_unit != null:
			chase_cell = Vector2i(target_unit.position.floor())
		enemy.repath_ticks = _repath_interval(dt)
		if chase_cell.x < 0 or not grid.is_walkable(chase_cell, true, _wall_ids if enemy.enemy_definition.passes_walls else {}):
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
	var speed: float = enemy.enemy_definition.move_speed * enemy.slow_multiplier / grid.movement_weight(cell)
	var velocity: Vector2 = enemy.preferred_velocity(speed, dt, navigation.segment_clear)
	if velocity == Vector2.ZERO:
		# A finished route frees the enemy to re-path toward a moving target.
		enemy.finish_path_if_arrived()
		return
	var direction: Vector2 = enemy.position.direction_to(enemy.next_waypoint())
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), separation_radius)
	var blended: Vector2 = Steering.combine(velocity, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, blended, direction, speed, dt, grid, buildings_by_id)
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


func _acquire_target(enemy: MechEntityState, grid: MechGridState, unit_buckets: Dictionary, building_cells: Dictionary, buildings_by_id: Dictionary) -> int:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	var center: Vector2i = Vector2i(enemy.position.floor())
	var radius: int = ceili(rules.vision_radius)
	var vision_squared: float = rules.vision_radius * rules.vision_radius
	var best: int = 0
	var best_distance: float = INF
	var best_building: int = _opportunistic_target(enemy) if rules.marches_to_core else 0
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
			var building: MechBuildingState = buildings_by_id.get(building_id)
			if building == null or building.definition.building_id == WALL_ID:
				continue
			var cell_center := Vector2(cell) + Vector2(0.5, 0.5)
			var building_distance: float = enemy.position.distance_squared_to(cell_center)
			if building_distance > vision_squared or not grid.terrain_line_clear(enemy.position, cell_center):
				continue
			# Marchers only acquire a building directly when already in reach.
			# Longer approaches come from the reachable, bounded detour field.
			if rules.marches_to_core and not _building_in_range(enemy, building, rules.attack_range):
				continue
			if building_distance < best_building_distance:
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
## A building blocker at any level engages that building instead of moving;
## armored walls do not stop wall passers (prototype, waves-enemies.md §8.2).
func _guarded_step(enemy: MechEntityState, velocity: Vector2, direction: Vector2, speed: float,
		dt: float, grid: MechGridState, buildings_by_id: Dictionary) -> void:
	if velocity.length_squared() <= 0.0:
		return
	var ignore_walls: bool = enemy.enemy_definition.passes_walls
	var blocker: Dictionary = _blocker_at(enemy.position + velocity * dt, grid, buildings_by_id, ignore_walls)
	if blocker["building"] > 0:
		_engage(enemy, blocker["building"])
		return
	if not blocker["blocked"]:
		enemy.position += velocity * dt
		return
	var direct: Vector2 = Steering.desired_velocity(direction, speed) * dt
	if direct.length_squared() > 0.0:
		blocker = _blocker_at(enemy.position + direct, grid, buildings_by_id, ignore_walls)
		if blocker["building"] > 0:
			_engage(enemy, blocker["building"])
			return
		if not blocker["blocked"]:
			enemy.position += direct
			return
	_slide_step(enemy, direction, speed, dt, grid, buildings_by_id)


func _slide_step(enemy: MechEntityState, direction: Vector2, speed: float, dt: float,
		grid: MechGridState, buildings_by_id: Dictionary) -> void:
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var field: MechMarchField = _march_field_for(enemy)
	var ignore_walls: bool = enemy.enemy_definition.passes_walls
	var step_x: int = int(sign(direction.x))
	var step_y: int = int(sign(direction.y))
	var best_position: Vector2 = enemy.position
	var best_cost: float = INF
	var found: bool = false
	for offset: Vector2i in [Vector2i(step_x, 0), Vector2i(0, step_y)]:
		if offset == Vector2i.ZERO:
			continue
		var neighbour: Vector2i = cell + offset
		var cost: float = field.cost_at(neighbour) if enemy.order == &"marching" else \
			(Vector2(neighbour) + Vector2(0.5, 0.5)).distance_squared_to(enemy.next_waypoint())
		if not is_finite(cost) or cost >= best_cost and found:
			continue
		var center: Vector2 = Vector2(neighbour) + Vector2(0.5, 0.5)
		var to_center: Vector2 = center - enemy.position
		if to_center.length_squared() <= 0.0:
			continue
		var candidate: Vector2 = enemy.position + to_center.normalized() * minf(speed * dt, to_center.length())
		var blocker: Dictionary = _blocker_at(candidate, grid, buildings_by_id, ignore_walls)
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
## Wall passers treat armored-wall cells as open ground (normal-speed crossing).
func _blocker_at(point: Vector2, grid: MechGridState, buildings_by_id: Dictionary, ignore_walls: bool = false) -> Dictionary:
	if not grid.point_inside(point):
		return {"blocked": true, "building": 0}
	var radius: float = MechGridState.MOBILE_RADIUS
	var low := Vector2i((point - Vector2.ONE * radius).floor())
	var high := Vector2i((point + Vector2.ONE * radius).floor())
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			var occupant: int = grid.occupant_at(cell)
			var solid_terrain: bool = occupant == 0 and grid.terrain_at(cell) == MechGridState.Terrain.OBSTACLE
			if (occupant == 0 and not solid_terrain) or grid.is_pass_through(cell):
				continue
			if occupant > 0 and buildings_by_id.has(occupant):
				var blocking: MechBuildingState = buildings_by_id[occupant]
				if ignore_walls and blocking.definition.building_id == WALL_ID:
					continue
				if _circle_hits_cell(point, cell, radius):
					return {"blocked": true, "building": occupant}
				continue
			if _circle_hits_cell(point, cell, radius):
				return {"blocked": true, "building": 0}
	return {"blocked": false, "building": 0}


func _circle_hits_cell(point: Vector2, cell: Vector2i, radius: float) -> bool:
	var closest := point.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
	return point.distance_squared_to(closest) < radius * radius


func _building_in_range(enemy: MechEntityState, building: MechBuildingState, attack_range: float) -> bool:
	# Distance to the footprint rectangle: diagonally adjacent (0.71) also counts
	# as close-quarters contact for a 1-cell melee range.
	var rect := Rect2(Vector2(building.origin), Vector2(building.definition.footprint))
	var clamped := Vector2(clampf(enemy.position.x, rect.position.x, rect.end.x), clampf(enemy.position.y, rect.position.y, rect.end.y))
	return enemy.position.distance_to(clamped) <= attack_range


func _building_chase_cell(enemy: MechEntityState, building: MechBuildingState, grid: MechGridState) -> Vector2i:
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	if not zone.is_empty() and not zone["dirty"]:
		var nearby: MechMarchField = zone["buildings"]
		var approach: Vector2i = nearby.source_at(Vector2i(enemy.position.floor()))
		if zone["owners"].get(approach, 0) == building.entity_id:
			return approach
	var area := Rect2i(building.origin, building.definition.footprint)
	var best := Vector2i(-1, -1)
	var best_distance: float = INF
	for y: int in range(area.position.y - 1, area.end.y + 1):
		for x: int in range(area.position.x - 1, area.end.x + 1):
			var cell := Vector2i(x, y)
			if area.has_point(cell) or not grid.is_walkable(cell, true, _wall_ids if enemy.enemy_definition.passes_walls else {}):
				continue
			var distance: float = Vector2(cell).distance_squared_to(enemy.position)
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best
