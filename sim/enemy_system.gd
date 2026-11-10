class_name MechEnemySystem
extends RefCounted
## 虫群行军：静态地形场提供战略方向。相互重叠的局部场引导未交战的
## 敌人经由可达缺口行进，并提供绕行前方建筑的短途支线。已交战的敌人
## 保持原目标不变；墙只在接触时被攻击，绝不因其可见而被选中。
## HP 不会使任何场失效。长足者共用免崎岖权重静态场及豁免墙的局部场。

## 转向混合权重：流场速度与同类分离力各占的比重。
const FLOW_WEIGHT: float = 1.0
const SEPARATION_WEIGHT: float = 0.6
## 常规分离半径；围攻建筑时改用更小的拥挤半径，让群体都能贴到目标。
const SEPARATION_RADIUS: float = 0.6
const CROWD_SEPARATION_RADIUS: float = 0.3
## 决策节拍（tick）：视野扫描的基础间隔；迷雾粗化模式下按 FOG_DECISION_STRIDE 倍数拉长间隔。
const VISION_SCAN_INTERVAL: int = 5
const FOG_DECISION_STRIDE: int = 4
## 活跃分桶的格子边长：资产周围按此粒度标记保持全速决策的区域。
const ACTIVITY_BUCKET_SIZE: int = 16
## 目标查询只访问包含单位/非墙建筑格的区域；底层候选格与原选敌顺序不变。
const TARGET_REGION_SIZE: int = 4
## 闻声聚拢：朝声响重寻路的间隔秒数与视为已抵达的距离。
const CONVERGE_REPATH_SECONDS: float = 2.0
const CONVERGE_ARRIVAL: float = 1.0
## 32×32 的局部场，彼此间隔 16 格：重叠的边界保证跨越区域时路线稳定；
## MARGIN 为分配的内缩余量，越过内边缘才重新分配区域。
## 同一时刻最多只有一个局部场构建任务在途。
const ASSAULT_ZONE_SIZE: int = 32
const ASSAULT_ZONE_STRIDE: int = 16
const ASSAULT_ZONE_MARGIN: int = 2
## 顺手攻击：可选建筑支线的感知距离与允许的额外绕行路长。
const OPPORTUNISTIC_RANGE: float = 3.0
const OPPORTUNISTIC_DETOUR: float = 2.0
## 局部出口必须优于全局进展时才被采用，此为允许的额外路长上限。
const BREACH_DETOUR: float = 8.0
## 闲逛者的 TAB 式挪动：决策间隔秒数、随机半径与尝试次数。
const SHUFFLE_DECISION_SECONDS: float = 8.0
const SHUFFLE_RADIUS: int = 2
const SHUFFLE_ATTEMPTS: int = 6

var profiling_enabled: bool = false
var _target_regions: Dictionary = {}
var _sample_motion: bool = false
var _motion_profile: Dictionary = {}
var _field := MechMarchField.new()
## 长足者共享忽略崎岖权重的静态场，不为单个敌人重复求解。
var _wall_field := MechMarchField.new()
## 穿墙单位沿用普通行军场，只在移动时无视墙体碰撞。
## 这份额外的 A* 仅用于追击/寻路查询，并非第二套场。
var _wall_navigation := MechGridNavigation.new()
var _wall_ids: Dictionary = {}
var _goal: Vector2i = Vector2i.ZERO
var _field_revision: int = -1
var _wall_navigation_revision: int = -1
var _wall_navigation_geometry: Dictionary = {}
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


## 重置到新战局：goal 为敌人行军的核心目标格，其余历史状态全部作废。
func reset(_grid: MechGridState, goal: Vector2i, _buildings: Array[MechBuildingState]) -> void:
	shutdown()
	_tick_counter = 0
	_goal = goal
	_field = MechMarchField.new()
	_wall_field = MechMarchField.new()
	_wall_navigation = MechGridNavigation.new()
	_field_revision = -1
	_wall_navigation_revision = -1
	_wall_navigation_geometry.clear()
	_zones.clear()
	_zone_grid_revision = -1
	_wall_ids.clear()


## 等待所有在途 Worker 任务完成并丢弃其结果，保证安全销毁。
func shutdown() -> void:
	_target_regions.clear()
	if _field_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_field_task)
		_field_task = -1
	_field_result = {}
	if _zone_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_zone_task)
		_zone_task = -1
	_zone_result = {}


## 共享场只依赖静态地形，因此从不需要签名校验。穿墙 A* 仍需要
## 非墙几何用于追击/寻路查询；墙的几何与墙的 HP 都被刻意排除在外。
func _nav_signature(buildings: Array[MechBuildingState]) -> Dictionary:
	var wall_geometry: Dictionary = {}
	var wall_ids: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0:
			continue
		if building.definition.is_wall_like():
			wall_ids[building.entity_id] = true
		if Rect2i(building.origin, building.definition.footprint).has_point(_goal):
			continue
		if not building.definition.is_wall_like():
			wall_geometry[building.entity_id] = Vector4i(
				building.origin.x, building.origin.y,
				building.definition.footprint.x, building.definition.footprint.y
			)
	return {"wall_geometry": wall_geometry, "wall_ids": wall_ids}


## 收集上次的构建结果，并按需在 Worker 线程重建共享行军场与穿墙 A*。
func _refresh_field(grid: MechGridState, buildings: Array[MechBuildingState], need_main: bool, need_wall: bool) -> void:
	# 闲逛者复用现有 A*，从不消耗核心行军场。
	# 共享场只含地形，绝不因建筑而失效。
	_collect_field_result(buildings)
	if _field_task >= 0 or (not need_main and not need_wall):
		return
	var revision: int = grid.revision()
	var signatures: Dictionary = _nav_signature(buildings)
	var wall_geometry: Dictionary = signatures["wall_geometry"]
	var wall_ids: Dictionary = signatures["wall_ids"]
	var rebuild_main: bool = need_main and _field_revision < 0
	# 穿墙 A* 只用于追击/寻路查询；它无视墙的占位，
	# 因此只有非墙几何变化才会使其失效。
	var nav_stale: bool = _wall_navigation_revision < 0 \
		or _wall_navigation_geometry != wall_geometry
	var rebuild_nav: bool = need_wall and nav_stale
	if not rebuild_main and not rebuild_nav:
		_wall_ids = wall_ids
		return
	var started: int = Time.get_ticks_usec() if profiling_enabled else 0
	_wall_ids = wall_ids
	var job: Dictionary = {"grid": grid.navigation_copy(), "goal": _goal,
		"wall_ids": wall_ids, "revision": revision,
		"main": rebuild_main, "nav": rebuild_nav,
		"wall_geometry": wall_geometry, "profiling": profiling_enabled}
	_field_task = WorkerThreadPool.add_task(_compute_fields.bind(job), false, "Mech march fields")
	if profiling_enabled:
		print("[perf:fields] submit_ms=%.3f revision=%d" % [(Time.get_ticks_usec() - started) / 1000.0, revision])


## Worker 任务体：按 job 标志重建行军场与/或穿墙 A*，结果写入互斥锁保护的 _field_result。
func _compute_fields(job: Dictionary) -> void:
	var started: int = Time.get_ticks_usec() if job["profiling"] else 0
	var output: Dictionary = {"revision": job["revision"],
		"wall_geometry": job["wall_geometry"], "wall_ids": job["wall_ids"]}
	var grid: MechGridState = job["grid"]
	if job["main"]:
		var field := MechMarchField.new()
		field.rebuild(grid, job["goal"])
		output["field"] = field
		var wall_field := MechMarchField.new()
		wall_field.rebuild(grid.navigation_copy(true), job["goal"])
		output["wall_field"] = wall_field
	if job["nav"]:
		# 每个 AStarGrid2D 同一时刻只归属一个线程，任务完成后才移交；
		# 不存在并发访问活跃 A* 对象的情况。
		var navigation := MechGridNavigation.new()
		navigation.rebuild(grid, job["wall_ids"], true)
		output["navigation"] = navigation
	if job["profiling"]:
		output["worker_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	_field_mutex.lock()
	_field_result = output
	_field_mutex.unlock()


## 收集已完成的场构建结果：几何签名仍匹配的穿墙 A* 才会应用，否则作废。
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
	# 共享场只含地形，与建筑无关、始终有效。穿墙 A*
	# 只用于追击/寻路查询，依赖非墙几何。
	var nav_ok: bool = result.get("wall_geometry", {}) == current["wall_geometry"]
	var applied_main: bool = false
	var applied_nav: bool = false
	if result.has("field"):
		_field = result["field"]
		_wall_field = result["wall_field"]
		_field_revision = result["revision"]
		applied_main = true
	if result.has("navigation") and nav_ok:
		_wall_navigation = result["navigation"]
		_wall_navigation_revision = result["revision"]
		_wall_navigation_geometry = result["wall_geometry"]
		applied_nav = true
	elif result.has("navigation"):
		_wall_navigation_revision = -1
	_wall_ids = current["wall_ids"]
	if result.has("worker_ms"):
		print("[perf:fields] worker_ms=%.3f main=%s nav=%s revision=%d" % [
			result["worker_ms"], applied_main, applied_nav, result["revision"]])


## 只为资产附近的行军敌人绑定局部场区域。已有分配在越出所在区域边界
## 的内缘之前保持有效；相邻区域彼此重叠。
func _refresh_zones(enemies: Array[MechEntityState], buildings: Array[MechBuildingState], grid: MechGridState, active_regions: Dictionary) -> void:
	if _field_revision < 0:
		return
	_collect_zone_result(grid, buildings)
	var changed: Array[Vector2i] = []
	if _zone_grid_revision != grid.revision():
		changed = grid.navigation_changes_since(_zone_grid_revision)
	_zone_grid_revision = grid.revision()
	# 用上次记录版本以来的占位/地形变化，把受影响的区域标记为脏。
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
			# 紧邻的占地即使占用格在边界之外，也可能增删恰好位于
			# 区域内侧的攻击位置。
			var adjacent: bool = bounds.grow(1).has_point(cell) and not bounds.has_point(cell)
			if adjacent or (bounds.has_point(cell) and forward.blocks_at(cell) == grid.is_walkable(cell, true, ignored)):
				zone["dirty"] = true
				break
		if touched and not zone["dirty"] and zone["source_key"] != _zone_source_key(bounds, buildings):
			zone["dirty"] = true
	var active: Dictionary = {}
	for enemy: MechEntityState in enemies:
		if enemy.wandering:
			continue
		var cell := Vector2i(enemy.position.floor())
		var previous: Dictionary = _zones.get(enemy.march_zone, {})
		# 仍在原区域的内缩余量内则保持绑定，避免在重叠带上反复切换。
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
	# 同一时刻只允许一个区域构建任务在途，所以每步最多提交一个。
	for key: Vector3i in active:
		var zone: Dictionary = _zones[key]
		if zone["dirty"] and _zone_task < 0:
			_submit_zone(key, zone, grid, buildings)
			break


## 冻结区域周边建筑的几何快照，并提交一个 Worker 任务构建该区域的局部场。
func _submit_zone(key: Vector3i, zone: Dictionary, grid: MechGridState, buildings: Array[MechBuildingState]) -> void:
	var started: int = Time.get_ticks_usec() if profiling_enabled else 0
	var frozen: Array[MechBuildingState] = []
	var bounds: Rect2i = zone["bounds"]
	for building: MechBuildingState in buildings:
		if building.hp <= 0 or building.definition.is_wall_like() or not bounds.grow(1).intersects(Rect2i(building.origin, building.definition.footprint)):
			continue
		var copy := MechBuildingState.new()
		copy.entity_id = building.entity_id
		copy.origin = building.origin
		# 局部场只关心几何不关心耐久，HP 固定为 1 即可。
		copy.hp = 1
		copy.definition = building.definition
		frozen.append(copy)
	var input: Dictionary = {"key": key, "bounds": zone["bounds"], "passes_walls": zone["passes_walls"],
		"grid": grid.navigation_copy(zone["passes_walls"]), "revision": grid.revision(), "buildings": frozen,
		"global": _wall_field if zone["passes_walls"] else _field, "wall_ids": _wall_ids.duplicate(), "profiling": profiling_enabled}
	_zone_task = WorkerThreadPool.add_task(_compute_zone.bind(input), false, "Mech local field")
	if profiling_enabled:
		print("[perf:assault-submit] ms=%.3f bounds=%s" % [(Time.get_ticks_usec() - started) / 1000.0, bounds])


## Worker 任务体：构建单个区域的局部场，结果经互斥锁写回 _zone_result。
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


## 收集已完成的局部场任务；只有影响本区域或其攻击位置外圈的变化才使结果作废。
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
	# 其他区域的事件与纯 HP 变化不会使该结果失效。只校验
	# 影响本区域或其攻击位置外圈的占位变化。
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


## 生成区域周边非墙建筑的几何签名，用于局部场结果的新鲜度校验。
func _zone_source_key(bounds: Rect2i, buildings: Array[MechBuildingState]) -> Dictionary:
	var key: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp > 0 and not building.definition.is_wall_like() and bounds.grow(1).intersects(Rect2i(building.origin, building.definition.footprint)):
			key[building.entity_id] = Vector4i(building.origin.x, building.origin.y,
				building.definition.footprint.x, building.definition.footprint.y)
	return key


## 区域边界上的源点继承全局积分值。核心位于本区域内时，核心攻击位置
## 作为额外出口。这让局部通路与战略进展（包括新出现的缺口）相连。
func _build_zone(zone: Dictionary, grid: MechGridState, buildings: Array[MechBuildingState], global_field: MechMarchField, wall_ids: Dictionary) -> void:
	var bounds: Rect2i = zone["bounds"]
	var ignored: Dictionary = wall_ids if zone["passes_walls"] else {}
	# 出口：边界上可走且全局可达的格子，继承全局积分值。
	var exits: Dictionary = {}
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if x != bounds.position.x and x != bounds.end.x - 1 and y != bounds.position.y and y != bounds.end.y - 1:
				continue
			var cell := Vector2i(x, y)
			if grid.is_walkable(cell, true, ignored) and global_field.is_reachable(cell):
				exits[cell] = global_field.cost_at(cell)
	# owners：建筑占地外一圈的可走攻击格 → 建筑实体 ID；
	# 核心的攻击格直接作为出口，让敌人优先抵达核心。
	var owners: Dictionary = {}
	for building: MechBuildingState in buildings:
		if building.hp <= 0 or building.definition.is_wall_like():
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


## 局部可达出口必须改善战略进展才被采用，且额外路长受限，
## 以免某个区域把虫群诱入漫长的折返或绕行。
func _march_field_for(enemy: MechEntityState) -> MechMarchField:
	var global_field: MechMarchField = _wall_field if enemy.enemy_definition.ignores_rough else _field
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	if zone.is_empty() or zone["dirty"]:
		return global_field
	var local: MechMarchField = zone["forward"]
	var cell := Vector2i(enemy.position.floor())
	var source: Vector2i = local.source_at(cell)
	if source.x < 0:
		return global_field
	var here: float = global_field.cost_at(cell)
	if global_field.cost_at(source) >= here or local.cost_at(cell) > here + BREACH_DETOUR:
		return global_field
	return local


## 附近建筑只是可选的短途支线，绝不是清空整个区域的目标。
## 不连通的目标代价为 INF，无法维持区域活跃。
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
	# 只有严格改善战略进展（progress ≤ 0）且总绕行不超上限，才值得顺手攻击。
	var global_field: MechMarchField = _wall_field if enemy.enemy_definition.ignores_rough else _field
	var progress: float = global_field.cost_at(source) - global_field.cost_at(cell)
	if progress > 0.0 or distance + progress > OPPORTUNISTIC_DETOUR:
		return 0
	return zone["owners"].get(source, 0)


## 创建敌人实体：team=2，按规则初始化 HP 与初始命令（闲逛或行军）。
## ambient 为真时标记为游荡形态：使用同一敌种定义，但不向主脑行军。
func create(registry: MechEntityRegistry, rules: MechEnemyDefinition, position: Vector2, ambient: bool = false) -> int:
	# rvo_speed 保持为 0，让 RVO 管线（registry step/快照）跳过敌人。
	var id: int = registry.create(rules.enemy_id, rules.display_name, position, 0.0, Vector2i.ONE)
	var enemy: MechEntityState = registry.get_entity(id)
	enemy.team = 2
	enemy.enemy_definition = rules
	enemy.hp = rules.max_hp
	enemy.max_hp = rules.max_hp
	enemy.hp_last_tick = rules.max_hp
	# 敌种定义可整体指定游荡型；生成时也可把行军型标为环境散兵。
	enemy.wandering = ambient or not rules.marches_to_core
	enemy.order = &"wandering" if enemy.wandering else &"marching"
	return id


## 推进一步模拟，返回单位死亡与建筑伤害；SimCore 通过自己的移除/经济
## 路径应用它们，使退款与容量遵循既有规则。
func advance(registry: MechEntityRegistry, grid: MechGridState, navigation: MechGridNavigation, buildings: Array[MechBuildingState], hz: int, noises: Array[Dictionary], vision: MechVisionSystem) -> Dictionary:
	_sample_motion = profiling_enabled and _tick_counter % hz == 0
	if _sample_motion:
		_motion_profile = {"direction": 0, "steering": 0, "collision": 0, "target": 0, "marching": 0}
	var sample_start: int = Time.get_ticks_usec() if _sample_motion else 0
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
				if not building.definition.is_wall_like():
					non_wall_cells[building.origin + Vector2i(x, y)] = building.entity_id
				_mark_active_region(building.origin + Vector2i(x, y), active_regions)
	var unit_buckets: Dictionary = {}
	var enemy_buckets: Dictionary = {}
	var enemies: Array[MechEntityState] = []
	var need_main: bool = false
	var need_wall: bool = false
	for entity: MechEntityState in registry.all():
		if entity.hp <= 0 or entity.garrisoned:
			continue
		if entity.team == 1 and entity.unit_definition != null:
			var unit_cell := Vector2i(entity.position.floor())
			if not unit_buckets.has(unit_cell):
				unit_buckets[unit_cell] = []
			unit_buckets[unit_cell].append(entity)
			_mark_active_region(unit_cell, active_regions)
		elif entity.team == 2 and entity.enemy_definition != null:
			enemies.append(entity)
			need_wall = need_wall or entity.enemy_definition.passes_walls
			# 同类敌人共用其通行权重的场，长足者另外豁免墙体碰撞。
			need_main = need_main or not entity.wandering
			var enemy_cell := Vector2i(entity.position.floor())
			if not enemy_buckets.has(enemy_cell):
				enemy_buckets[enemy_cell] = []
			enemy_buckets[enemy_cell].append(entity)
	_index_target_regions(unit_buckets, non_wall_cells)
	if _sample_motion:
		_motion_profile["prepare"] = Time.get_ticks_usec() - sample_start
		sample_start = Time.get_ticks_usec()
	_refresh_field(grid, buildings, need_main, need_wall)
	_refresh_zones(enemies, buildings, grid, active_regions)
	if _sample_motion:
		_motion_profile["navigation"] = Time.get_ticks_usec() - sample_start
		sample_start = Time.get_ticks_usec()
	var dt: float = 1.0 / float(hz)
	var tick: int = _tick_counter
	_tick_counter += 1
	for enemy: MechEntityState in enemies:
		enemy.slow_multiplier = enemy.slow_effect_multiplier
		var cell := Vector2i(enemy.position.floor())
		var near_assets: bool = active_regions.has(_activity_bucket(cell))
		var local_radius: float = maxf(enemy.enemy_definition.vision_radius, enemy.enemy_definition.attack_range)
		# 玩家看不见、远离资产且感知半径小 → 进入低频粗化决策模式以省性能。
		var coarse: bool = not vision.is_visible(enemy.position) and not near_assets and local_radius <= ACTIVITY_BUCKET_SIZE
		# 刚脱离粗化模式时清零寻路计时，立即恢复正常反应速度。
		if enemy.fog_coarse and not coarse:
			enemy.repath_ticks = 0
		enemy.fog_coarse = coarse
		var passes_walls: bool = enemy.enemy_definition.passes_walls
		_advance_one(enemy, registry, grid, _wall_navigation if passes_walls else navigation, buildings_by_id,
			non_wall_cells if passes_walls else building_cells, unit_buckets, enemy_buckets, noises, tick, dt, hz, result, coarse)
		# 效果衰减在上一步移动之后应用，恰好覆盖完整的本步时长。
		enemy.advance_slow()
	if _sample_motion:
		_motion_profile["loop"] = Time.get_ticks_usec() - sample_start
		print("[perf:enemy-sample] tick=%d usec=%s" % [tick, _motion_profile])
	return result


func _activity_bucket(cell: Vector2i) -> Vector2i:
	return Vector2i(Vector2(cell) / float(ACTIVITY_BUCKET_SIZE))


func _mark_active_region(cell: Vector2i, regions: Dictionary) -> void:
	var bucket: Vector2i = _activity_bucket(cell)
	# 至少 16 格余量：即使在玩家的视野盲区，战斗与附近敌人的
	# 感知也保持全速节拍。迷雾从不关闭敌人的感官。
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			regions[bucket + Vector2i(x, y)] = true


## 单个敌人的逐步推进：冷却递减、受击优先，再按状态分派交战/闲逛/行军。
func _advance_one(enemy: MechEntityState, registry: MechEntityRegistry, grid: MechGridState,
		navigation: MechGridNavigation, buildings_by_id: Dictionary,
		building_cells: Dictionary, unit_buckets: Dictionary, enemy_buckets: Dictionary,
		noises: Array[Dictionary], tick: int, dt: float, hz: int, result: Dictionary, coarse: bool) -> void:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	if rules == null:
		return
	if rules.passes_walls and _wall_navigation_revision < 0:
		return
	enemy.cooldown_ticks = maxi(0, enemy.cooldown_ticks - 1)
	enemy.charge_ticks = maxi(0, enemy.charge_ticks - 1)
	enemy.shot_ticks = maxi(0, enemy.shot_ticks - 1)
	enemy.repath_ticks = maxi(0, enemy.repath_ticks - 1)
	# 受到攻击是立即交战条件，即使还没到视野扫描时刻。
	var provoked: bool = enemy.hp < enemy.hp_last_tick
	enemy.hp_last_tick = enemy.hp
	var stride: int = FOG_DECISION_STRIDE if coarse and not provoked else 1
	# 用 entity_id 错开扫描相位，避免大量敌人同 tick 齐扫。
	var scan_due: bool = provoked or (tick + enemy.entity_id) % (VISION_SCAN_INTERVAL * stride) == 0
	if enemy.order == &"engaged":
		_advance_engaged(enemy, registry, grid, navigation, buildings_by_id,
			building_cells, unit_buckets, enemy_buckets, dt, hz, result)
		return
	if scan_due:
		var started: int = Time.get_ticks_usec() if _sample_motion else 0
		var target: int = _acquire_target(enemy, grid, unit_buckets, building_cells, buildings_by_id)
		if _sample_motion:
			_motion_profile["target"] += Time.get_ticks_usec() - started
		if target > 0:
			_engage(enemy, target)
	if enemy.order == &"engaged":
		_advance_engaged(enemy, registry, grid, navigation, buildings_by_id,
			building_cells, unit_buckets, enemy_buckets, dt, hz, result)
		return
	# 游荡形态从不向核心行军：只会闻声聚拢或 TAB 式随机挪动。
	if enemy.wandering:
		var decision_due: bool = (tick + enemy.entity_id) % stride == 0
		_advance_wandering(enemy, noises, grid, navigation, enemy_buckets, buildings_by_id, dt, decision_due, stride)
		return
	_advance_marching(enemy, grid, enemy_buckets, buildings_by_id, dt)


## 闲逛者的待机行为：朝听到的最大声响聚拢（"闻声缓慢聚拢"）；
## 无声响时偶尔以慢节拍挪到附近格子。当前行走必定走完，
## 因此失去声源后它们会停在原地徘徊。
func _advance_wandering(enemy: MechEntityState, noises: Array[Dictionary], grid: MechGridState,
		navigation: MechGridNavigation, enemy_buckets: Dictionary, buildings_by_id: Dictionary,
		dt: float, decision_due: bool, stride: int) -> void:
	if not decision_due:
		_walk_wanderer(enemy, grid, enemy_buckets, buildings_by_id, dt)
		return
	# 采纳声响最大（半径最大）的噪声；同响度取最近。
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
		# 已抵达声源附近：原地停留，等下一次决策节拍再动。
		if enemy.position.distance_to(goal) <= CONVERGE_ARRIVAL:
			enemy.set_move_path(PackedVector2Array())
			enemy.repath_ticks = maxi(1, ceili(CONVERGE_REPATH_SECONDS * stride / dt))
			return
		if enemy.repath_ticks == 0 and (not enemy.has_move_order or enemy.order_goal.distance_to(goal) > 1.0):
			var goal_cell := Vector2i(goal.floor())
			var source_building: MechBuildingState = buildings_by_id.get(grid.occupant_at(goal_cell))
			# 建筑噪声源自实体占位内部。复用战斗接近格，
			# 让 AStarGrid2D 能把听众引导到建筑外围。
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
		# TAB 式闲逛挪动：偶尔漂移到附近的随机可走格。
		enemy.repath_ticks = maxi(1, ceili(SHUFFLE_DECISION_SECONDS / dt))
		var shuffle_target: Vector2i = _shuffle_cell(enemy, grid) if randf() < 0.5 else Vector2i(-1, -1)
		if shuffle_target.x >= 0:
			var path: PackedVector2Array = navigation.find_path(enemy.position, shuffle_target)
			if not path.is_empty():
				enemy.order_goal = Vector2(shuffle_target) + Vector2(0.5, 0.5)
				enemy.set_move_path(path)
	_walk_wanderer(enemy, grid, enemy_buckets, buildings_by_id, dt)


func _walk_wanderer(enemy: MechEntityState, grid: MechGridState, enemy_buckets: Dictionary, buildings_by_id: Dictionary, dt: float) -> void:
	# 移动、碰撞、冷却与伤害仍按正常步长节奏执行。
	if not enemy.has_move_order:
		return
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var speed: float = _movement_speed(enemy, grid, cell) * (1.0 if enemy.charge_ticks > 0 else enemy.enemy_definition.wandering_speed_ratio)
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


## 沿局部或全局行军场推进：流场方向 + 同类分离 + 守卫步。
func _advance_marching(enemy: MechEntityState, grid: MechGridState, enemy_buckets: Dictionary, buildings_by_id: Dictionary, dt: float) -> void:
	var cell: Vector2i = Vector2i(enemy.position.floor())
	if _field_revision < 0:
		return
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	# 短暂等待有界的区域构建任务，而不是在新缺口尚未积分时
	# 就转而啃另一面墙。
	if not zone.is_empty() and zone["dirty"]:
		return
	var field: MechMarchField = _march_field_for(enemy)
	var started: int = Time.get_ticks_usec() if _sample_motion else 0
	var flow_dir: Vector2 = field.flow_at(cell)
	if flow_dir == Vector2.ZERO:
		flow_dir = (_wall_field if enemy.enemy_definition.ignores_rough else _field).flow_at(cell)
	var speed: float = _movement_speed(enemy, grid, cell)
	if _sample_motion:
		_motion_profile["direction"] += Time.get_ticks_usec() - started
		_motion_profile["marching"] += 1
		started = Time.get_ticks_usec()
	var desired: Vector2 = Steering.desired_velocity(flow_dir, speed)
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets), SEPARATION_RADIUS)
	var velocity: Vector2 = Steering.combine(desired, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	if _sample_motion:
		_motion_profile["steering"] += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
	_guarded_step(enemy, velocity, flow_dir, speed, dt, grid, buildings_by_id)
	if _sample_motion:
		_motion_profile["collision"] += Time.get_ticks_usec() - started


## 交战推进：目标存活则射程内站定输出，否则追击。
func _advance_engaged(enemy: MechEntityState, registry: MechEntityRegistry, grid: MechGridState,
		navigation: MechGridNavigation, buildings_by_id: Dictionary,
		building_cells: Dictionary, unit_buckets: Dictionary, enemy_buckets: Dictionary,
		dt: float, hz: int, result: Dictionary) -> void:
	var target_id: int = enemy.attack_target_id
	var target_building: MechBuildingState = buildings_by_id.get(target_id)
	var target_unit: MechEntityState = null
	if target_building == null:
		target_unit = registry.get_entity(target_id)
		if target_unit == null or target_unit.team != 1 or target_unit.hp <= 0 or target_unit.garrisoned:
			target_unit = null
	if target_building == null and target_unit == null:
		# 墙被摧毁后释放攻击者恢复行军。仍存活的墙目标
		# 不会进入这个分支，因此新缺口不会使其改换目标。
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
	# 持有有效可感知目标才刷新冲锋；失去感知只保留一秒余速。
	if enemy.position.distance_to(aim_point) <= rules.vision_radius and grid.terrain_line_clear(enemy.position, aim_point):
		enemy.charge_ticks = maxi(1, ceili(rules.charge_linger_seconds * hz)) if rules.charge_bonus > 0.0 else 0
	# 站定攻击：射程内且地形视线通畅时结算一次伤害。
	if in_range and grid.terrain_line_clear(enemy.position, aim_point):
		enemy.set_move_path(PackedVector2Array())
		if enemy.cooldown_ticks == 0:
			enemy.cooldown_ticks = maxi(1, ceili(rules.attack_seconds * hz))
			# shot_ticks 仅用于表现层的开火闪烁时长（0.1 秒）。
			enemy.shot_ticks = maxi(1, ceili(0.1 * hz))
			enemy.shot_target = aim_point
			if _combat_noise.is_valid():
				_combat_noise.call(aim_point)
			var hit_damage: int = _attack_damage(enemy, rules.building_damage() if target_building != null else rules.damage)
			if target_building != null:
				result["building_hits"].append({"id": target_building.entity_id, "damage": hit_damage})
			else:
				target_unit.hp = maxi(0, target_unit.hp - hit_damage)
				if target_unit.hp == 0:
					result["dead_units"].append(target_unit.entity_id)
			if rules.splash_radius > 0.0:
				_apply_splash(enemy, aim_point, target_id, registry, buildings_by_id, grid, result)
		return
	# 逼近建筑时允许部分重叠，让整个群体都能贴到目标。
	var separation_radius: float = CROWD_SEPARATION_RADIUS if target_building != null else SEPARATION_RADIUS
	_chase(enemy, grid, navigation, target_building, target_unit, enemy_buckets, buildings_by_id, dt, separation_radius)


## 追击目标：无可走路径则脱离，否则沿 A* 路径走向目标。
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
			# 目标可见但不可达：恢复行军；受阻的步子
			# 会转而攻击挡路的建筑。
			_disengage(enemy)
			return
		enemy.set_move_path(path)
	if not enemy.has_move_order:
		return
	var cell: Vector2i = Vector2i(enemy.position.floor())
	var speed: float = _movement_speed(enemy, grid, cell)
	var velocity: Vector2 = enemy.preferred_velocity(speed, dt, navigation.segment_clear)
	if velocity == Vector2.ZERO:
		# 走完的路径让敌人得以朝移动目标重新寻路。
		enemy.finish_path_if_arrived()
		return
	var direction: Vector2 = enemy.position.direction_to(enemy.next_waypoint())
	var separation: Vector2 = Steering.separation(enemy.position, _separation_neighbors(enemy, enemy_buckets, separation_radius), separation_radius)
	var blended: Vector2 = Steering.combine(velocity, separation, FLOW_WEIGHT, SEPARATION_WEIGHT, speed)
	_guarded_step(enemy, blended, direction, speed, dt, grid, buildings_by_id)
	enemy.finish_path_if_arrived()


func _repath_interval(dt: float) -> int:
	return maxi(1, ceili(1.0 / dt))


func _movement_speed(enemy: MechEntityState, grid: MechGridState, cell: Vector2i) -> float:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	var speed: float = rules.move_speed + (rules.charge_bonus if enemy.charge_ticks > 0 else 0.0)
	if enemy.speed_boost_ticks > 0:
		speed = maxf(speed, rules.boost_speed)
	if enemy.frenzy_ticks > 0:
		speed *= 1.0 + enemy.frenzy_speed_bonus
	return speed * enemy.slow_multiplier / (1.0 if rules.ignores_rough else grid.movement_weight(cell))


## 狂暴只放大最终攻击伤害；建筑与单位各自走原伤害基值。
func _attack_damage(enemy: MechEntityState, base: int) -> int:
	if enemy.frenzy_ticks <= 0 or enemy.frenzy_damage_bonus <= 0.0:
		return base
	return ceili(float(base) * (1.0 + enemy.frenzy_damage_bonus))


## 炮击只影响固定落点附近的合法目标；直接命中已单独登记，不重复计伤。
func _apply_splash(enemy: MechEntityState, point: Vector2, primary: int, registry: MechEntityRegistry,
		buildings: Dictionary, grid: MechGridState, result: Dictionary) -> void:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	var building_damage: int = _attack_damage(enemy, rules.building_damage())
	var unit_damage: int = _attack_damage(enemy, rules.damage)
	for building: MechBuildingState in buildings.values():
		if building.entity_id == primary or building.hp <= 0:
			continue
		var area := Rect2(Vector2(building.origin), Vector2(building.definition.footprint))
		var closest: Vector2 = point.clamp(area.position, area.end)
		if point.distance_to(closest) <= rules.splash_radius and grid.terrain_line_clear(point, closest):
			result["building_hits"].append({"id": building.entity_id, "damage": building_damage})
	for unit: MechEntityState in registry.all():
		if unit.entity_id == primary or unit.team != 1 or unit.unit_definition == null or unit.hp <= 0 or unit.garrisoned:
			continue
		if point.distance_to(unit.position) <= rules.splash_radius and grid.terrain_line_clear(point, unit.position):
			unit.hp = maxi(0, unit.hp - unit_damage)
			if unit.hp == 0:
				result["dead_units"].append(unit.entity_id)


func _engage(enemy: MechEntityState, target_id: int) -> void:
	enemy.order = &"engaged"
	enemy.attack_target_id = target_id
	enemy.set_move_path(PackedVector2Array())
	enemy.repath_ticks = 0


func _disengage(enemy: MechEntityState) -> void:
	# 游荡形态在追击终点原地待机；波次敌人恢复向核心行军。
	enemy.order = &"wandering" if enemy.wandering else &"marching"
	enemy.attack_target_id = 0
	enemy.set_move_path(PackedVector2Array())


## 视野扫描锁定目标：最近可见单位或（偏好的）建筑，受地形视线约束。
func _acquire_target(enemy: MechEntityState, grid: MechGridState, unit_buckets: Dictionary, building_cells: Dictionary, buildings_by_id: Dictionary) -> int:
	var rules: MechEnemyDefinition = enemy.enemy_definition
	var center: Vector2i = Vector2i(enemy.position.floor())
	var radius: int = ceili(rules.vision_radius)
	var vision_squared: float = rules.vision_radius * rules.vision_radius
	var best: int = 0
	var best_distance: float = INF
	var best_building: int = _opportunistic_target(enemy) if not enemy.wandering else 0
	var best_building_distance: float = INF
	var best_tower: int = 0
	var best_tower_distance: float = INF
	for cell: Vector2i in _target_cells(center, radius):
		for unit: MechEntityState in unit_buckets.get(cell, []):
			# 同一轮推进中，先手敌人可能已击杀此单位。
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
		if building == null or building.definition.is_wall_like():
			continue
		var cell_center := Vector2(cell) + Vector2(0.5, 0.5)
		var building_distance: float = enemy.position.distance_squared_to(cell_center)
		if building_distance > vision_squared or not grid.terrain_line_clear(enemy.position, cell_center):
			continue
		if rules.prefers_towers and building.definition.attack_damage > 0 and building_distance < best_tower_distance:
			best_tower = building_id
			best_tower_distance = building_distance
		# 行军者只有已在射程内才直接锁定建筑；
		# 更远的接近交给可达且有界的绕行场处理。
		if not enemy.wandering and not _building_in_range(enemy, building, rules.attack_range):
			continue
		if building_distance < best_building_distance:
			best_building = building_id
			best_building_distance = building_distance
	if best_tower > 0:
		return best_tower
	if rules.prefers_buildings and best_building > 0:
		return best_building
	return best if best > 0 else best_building


func _target_region(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / TARGET_REGION_SIZE), floori(float(cell.y) / TARGET_REGION_SIZE))


func _index_target_regions(unit_buckets: Dictionary, non_wall_cells: Dictionary) -> void:
	_target_regions.clear()
	for cell: Vector2i in non_wall_cells:
		var region: Vector2i = _target_region(cell)
		if not _target_regions.has(region):
			_target_regions[region] = []
		_target_regions[region].append(cell)
	for cell: Vector2i in unit_buckets:
		if non_wall_cells.has(cell):
			continue
		var region: Vector2i = _target_region(cell)
		if not _target_regions.has(region):
			_target_regions[region] = []
		_target_regions[region].append(cell)


func _target_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var bounds := Rect2i(center - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))
	var low: Vector2i = _target_region(bounds.position)
	var high: Vector2i = _target_region(bounds.end - Vector2i.ONE)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var region := Vector2i(x, y)
			if not _target_regions.has(region):
				continue
			for cell: Vector2i in _target_regions[region]:
				if bounds.has_point(cell):
					result.append(cell)
	# 保留原先y/x逐格扫描的并列目标顺序，建筑的每个足迹格仍单独接受距离/LOS校验。
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.y == b.y else a.y < b.y)
	return result


func _separation_neighbors(enemy: MechEntityState, enemy_buckets: Dictionary, radius: float = SEPARATION_RADIUS) -> PackedVector2Array:
	var result := PackedVector2Array()
	var cell := Vector2i(enemy.position.floor())
	# 只剔除vendor必定忽略的远邻，边缘留余量，最终半径判定仍交给原Steering。
	var radius_squared: float = radius * radius + 0.000001
	for y: int in range(cell.y - 1, cell.y + 2):
		for x: int in range(cell.x - 1, cell.x + 2):
			var neighbors: Variant = enemy_buckets.get(Vector2i(x, y))
			if neighbors == null:
				continue
			for other: MechEntityState in neighbors:
				if other.entity_id != enemy.entity_id and enemy.position.distance_squared_to(other.position) <= radius_squared:
					result.append(other.position)
	return result


## 逐级升级的受阻防护步（改编自 Crusade 追随者思路）：先混合速度步，
## 再纯方向步，最后是朝更低积分代价的基数滑动。任一级遇到建筑阻挡
## 都改为交战该建筑而非移动；装甲墙拦不住穿墙单位
## （长足者能力见 docs/enemy-roster.md）。
func _guarded_step(enemy: MechEntityState, velocity: Vector2, direction: Vector2, speed: float,
		dt: float, grid: MechGridState, buildings_by_id: Dictionary) -> void:
	if velocity.length_squared() <= 0.0:
		return
	var ignore_walls: bool = enemy.enemy_definition.passes_walls
	var blocker: int = _blocker_at(enemy.position + velocity * dt, grid, buildings_by_id, ignore_walls)
	if blocker > 0:
		_engage(enemy, blocker)
		return
	if blocker == 0:
		enemy.position += velocity * dt
		return
	var direct: Vector2 = Steering.desired_velocity(direction, speed) * dt
	if direct.length_squared() > 0.0:
		blocker = _blocker_at(enemy.position + direct, grid, buildings_by_id, ignore_walls)
		if blocker > 0:
			_engage(enemy, blocker)
			return
		if blocker == 0:
			enemy.position += direct
			return
	_slide_step(enemy, direction, speed, dt, grid, buildings_by_id)


## 滑动步：行军时按行军场代价、追击时按到下一路径点的距离择优基数邻格。
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
		var blocker: int = _blocker_at(candidate, grid, buildings_by_id, ignore_walls)
		if blocker > 0:
			_engage(enemy, blocker)
			return
		if blocker < 0:
			continue
		best_cost = cost
		best_position = candidate
		found = true
	enemy.position = best_position


## 圆形碰撞体检查，与网格移动规则保持一致；对阻挡者分类，
## 以便调用方转而交战建筑。非建筑占用者按静态墙处理。
## 穿墙单位把装甲墙格子视为空地（以正常速度通行）。
## 返回0可移动，正数交战建筑ID，-1静态阻挡；避免每个移动步分配字典。
func _blocker_at(point: Vector2, grid: MechGridState, buildings_by_id: Dictionary, ignore_walls: bool = false) -> int:
	if not grid.point_inside(point):
		return -1
	var radius: float = MechGridState.MOBILE_RADIUS
	var low := Vector2i((point - Vector2.ONE * radius).floor())
	var high := Vector2i((point + Vector2.ONE * radius).floor())
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell := Vector2i(x, y)
			var occupant: int = grid.enemy_blocker_at(cell)
			if occupant == 0:
				continue
			if occupant > 0 and buildings_by_id.has(occupant):
				var blocking: MechBuildingState = buildings_by_id[occupant]
				if ignore_walls and blocking.definition.is_wall_like():
					continue
				if _circle_hits_cell(point, cell, radius):
					return occupant
				continue
			if _circle_hits_cell(point, cell, radius):
				return -1
	return 0


func _circle_hits_cell(point: Vector2, cell: Vector2i, radius: float) -> bool:
	var closest := point.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
	return point.distance_squared_to(closest) < radius * radius


func _building_in_range(enemy: MechEntityState, building: MechBuildingState, attack_range: float) -> bool:
	# 距离按占地矩形计算：对 1 格近战射程，对角相邻（0.71）
	# 也算贴身接触。
	var rect := Rect2(Vector2(building.origin), Vector2(building.definition.footprint))
	var clamped := Vector2(clampf(enemy.position.x, rect.position.x, rect.end.x), clampf(enemy.position.y, rect.position.y, rect.end.y))
	return enemy.position.distance_to(clamped) <= attack_range


## 选取追击建筑的接近格：优先用局部场给出的攻击位，否则取占地周边最近的可走格。
func _building_chase_cell(enemy: MechEntityState, building: MechBuildingState, grid: MechGridState) -> Vector2i:
	var zone: Dictionary = _zones.get(enemy.march_zone, {})
	if not zone.is_empty() and not zone["dirty"]:
		# 局部绕行场已指向该建筑时，直接复用其给出的攻击位。
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
