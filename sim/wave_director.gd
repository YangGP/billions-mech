class_name MechWaveDirector
extends RefCounted
## 波次调度（依据 waves-enemies.md §2–§6 与 values.md §2/§12）：静默期或
## 发展度触发首波，预算 B(n) = 首波 × growth^(n-1)，预告附带定性规模
## 等级与粗略的进攻边缘方向。TAB 式投放：每波从边缘带（玩家视野外）
## 跨投放窗口连续流入，条目有序且均匀错峰。普通池与主题精英按资源配置
## 花费预算，普通数/精英配额独立约束。生成以请求形式返回；
## 实体创建由 MechEnemySystem 负责。total_waves 为正时导演在该波后
## 停止排程（首切片胜利门槛）；为 0 则保持无尽幕循环。

## "计算节点"建筑编号，用于发展度触发的节点计数。
const NODE_ID: StringName = &"compute_node"
var _active: bool = false
var profiling_enabled: bool = false
var _tick_rate: int = 30
var _defs: Dictionary = {}
var _main_band: Array[Vector2i] = []
var _flank_band: Array[Vector2i] = []
var _all_bands: Array[Vector2i] = []
var _main_edge: StringName = &"north"
var _flank_edge: StringName = &"east"
var _phase: StringName = &"silence"
var _wave_index: int = 0
var _tick_counter: int = 0
var _silence_ticks: int = 18000
var _announce_delay_ticks: int = 900
var _wave_interval_ticks: int = 18000
var _release_window_ticks: int = 9000
var _first_wave_budget: float = 25.0
var _budget_growth: float = 1.6
var _total_waves: int = 0
var _configured_total_waves: int = 0
var _development_nodes: int = 8
var _development_score_threshold: int = 24
var _development_score: int = 0
var _wave_trigger_mode: int = MechFoundationSettings.WaveTrigger.DEVELOPMENT_OR_TIME
var _flank_every: int = 4
var _campaign_mode: bool = false
var _final_wave_budget: float = 2000.0
var _final_requested: bool = false
var _campaign_stage: int = 1
var _tier_label: String = ""
var _edge: StringName = &""
var _edge_name: String = ""
var _pending: Array[Dictionary] = []
var _population: Dictionary[StringName, int] = {}
var _ordinary_since_elite: int = 0
var _ordinary_per_elite: int = 100
var _max_elite_types: int = 3
var _rng := RandomNumberGenerator.new()
var _seed: int = 1


## 校验并装载敌种定义与波次参数，返回错误信息（空串表示成功）。
func configure(settings: MechFoundationSettings) -> String:
	_defs.clear()
	for rules: MechEnemyDefinition in settings.enemy_definitions:
		if rules == null:
			return "空敌种定义"
		var error: String = rules.validation_error()
		if not error.is_empty():
			return error
		if _defs.has(rules.enemy_id):
			return "重复敌种编号"
		_defs[rules.enemy_id] = rules
	if not _defs.has(&"builder") or not _defs.has(&"recycler"):
		return "缺少普通建造者或回收者定义"
	_ordinary_per_elite = maxi(1, settings.ordinary_per_elite)
	_max_elite_types = clampi(settings.max_elite_types, 1, 3)
	_seed = settings.session_seed
	_silence_ticks = maxi(1, ceili(settings.silence_seconds * settings.simulation_hz))
	_announce_delay_ticks = maxi(1, ceili(settings.wave_announce_seconds * settings.simulation_hz))
	_wave_interval_ticks = maxi(1, ceili(settings.wave_interval_seconds * settings.simulation_hz))
	_release_window_ticks = maxi(1, ceili(settings.wave_release_seconds * settings.simulation_hz))
	_first_wave_budget = maxf(1.0, settings.first_wave_budget)
	_budget_growth = maxf(1.0, settings.wave_budget_growth)
	_total_waves = 0 if settings.campaign_mode else maxi(0, settings.total_waves)
	_configured_total_waves = _total_waves
	_development_nodes = maxi(1, settings.development_node_threshold)
	_development_score_threshold = maxi(1, settings.development_score_threshold)
	_wave_trigger_mode = settings.wave_trigger_mode
	_flank_every = maxi(2, settings.flank_wave_interval)
	_campaign_mode = settings.campaign_mode
	_final_wave_budget = maxf(100.0, settings.final_wave_budget)
	return ""


## 重置导演状态并按地图定义收集边缘出生带。
func reset(grid: MechGridState, map_definition: MechMapDefinition, active: bool, hz: int) -> void:
	_active = active
	_tick_rate = maxi(1, hz)
	_phase = &"silence"
	_wave_index = 0
	_tick_counter = 0
	_tier_label = ""
	_final_requested = false
	_total_waves = _configured_total_waves
	_campaign_stage = 1
	_development_score = 0
	_edge = &""
	_edge_name = ""
	_pending.clear()
	_population.clear()
	_ordinary_since_elite = 0
	_rng.seed = _seed
	_collect_bands(grid, map_definition)


## 推进一步：先清空流式投放队列，再按相位时钟（静默→预告→投放）推进。
func advance(grid: MechGridState, buildings: Array[MechBuildingState], entities: Array[MechEntityState] = []) -> Array[Dictionary]:
	if not _active or grid == null:
		return []
	_tick_counter += 1
	_population.clear()
	for entity: MechEntityState in entities:
		if entity.team == 2 and entity.hp > 0 and entity.enemy_definition != null:
			var id: StringName = entity.enemy_definition.enemy_id
			_population[id] = int(_population.get(id, 0)) + 1
	# 在途条目也预占配额，含本tick即将释放的条目，避免跨波超量。
	for entry: Dictionary in _pending:
		var id: StringName = entry["enemy_id"]
		_population[id] = int(_population.get(id, 0)) + 1
	var requests: Array[Dictionary] = []
	# 流式投放先行清空 _pending，与下方的相位时钟无关。
	if not _pending.is_empty():
		var remaining: Array[Dictionary] = []
		for entry: Dictionary in _pending:
			entry["delay"] = int(entry["delay"]) - 1
			if entry["delay"] <= 0:
				requests.append({"enemy_id": entry["enemy_id"], "position": entry["position"]})
			else:
				remaining.append(entry)
		_pending = remaining
	match _phase:
		&"silence":
			var time_due: bool = _tick_counter >= _silence_ticks
			var development_due: bool = _wave_trigger_mode == MechFoundationSettings.WaveTrigger.DEVELOPMENT_OR_TIME \
				and _operating_nodes(buildings) >= _development_nodes
			if _wave_trigger_mode == MechFoundationSettings.WaveTrigger.DEVELOPMENT_SCORE:
				_development_score = _development_progress(buildings)
				development_due = _development_score >= _development_score_threshold
			if time_due or development_due:
				_announce()
		&"announced":
			if _tick_counter >= _announce_delay_ticks:
				_queue_wave()
		&"active":
			# 间隔按投放到投放计量；预告需在该跨度内发出。
			if _tick_counter >= maxi(1, _wave_interval_ticks - _announce_delay_ticks):
				_announce()
	return requests


## 战役模式请求终波：改为全线进攻；非战役模式或已请求/已结束则拒绝。
func request_final_wave() -> bool:
	if not _campaign_mode or _final_requested or _phase == &"done":
		return false
	_final_requested = true
	_total_waves = _wave_index + 1
	if _phase == &"announced":
		_edge = &"all"
		_edge_name = "全线"
		_tier_label = "大量"
	return true


func set_campaign_stage(stage: int) -> void:
	_campaign_stage = clampi(stage, 1, 3)


## 导出 HUD 所需的导演状态快照：相位、倒计时、下一波编号与进攻边缘等。
func state() -> Dictionary:
	var seconds_remaining: float = 0.0
	var next_event: StringName = &"done"
	# 结束相位显示已完成波数，否则显示即将到来的波号。
	var wave_number: int = _wave_index if _phase == &"done" else _wave_index + 1
	var next_wave_number: int = _wave_index + 1
	var next_edge: StringName = _main_edge
	var next_edge_name: String = {"north": "北", "south": "南", "west": "西", "east": "东"}.get(String(_main_edge), "正面")
	if next_wave_number % _flank_every == 0 and not _flank_band.is_empty():
		next_edge = _flank_edge
		next_edge_name = {"north": "北", "south": "南", "west": "西", "east": "东"}.get(String(_flank_edge), "侧翼")
	if _final_requested:
		next_edge = &"all"
		next_edge_name = "全线"
	match _phase:
		&"silence":
			seconds_remaining = maxf(0.0, float(_silence_ticks - _tick_counter) / float(_tick_rate))
			next_event = &"announce"
		&"announced":
			seconds_remaining = maxf(0.0, float(_announce_delay_ticks - _tick_counter) / float(_tick_rate))
			next_event = &"release"
		&"active":
			wave_number = _wave_index
			seconds_remaining = maxf(0.0, float(maxi(1, _wave_interval_ticks - _announce_delay_ticks) - _tick_counter) / float(_tick_rate))
			next_event = &"next_announce"
	return {"active": _active, "phase": _phase, "wave_index": _wave_index,
		"wave_number": wave_number, "next_event": next_event,
		"seconds_remaining": seconds_remaining,
		"next_wave_number": next_wave_number, "next_edge": next_edge,
		"next_edge_name": next_edge_name,
		"final_requested": _final_requested,
		"final_phase": "none" if not _final_requested else ("requested" if _wave_index < _total_waves else ("releasing" if not _pending.is_empty() else "clearing")),
		"campaign_mode": _campaign_mode,
		"campaign_stage": _campaign_stage,
		"development_score": _development_score,
		"development_score_threshold": _development_score_threshold,
		"edge": _edge, "edge_name": _edge_name, "tier": _tier_label,
		"total_waves": _total_waves, "exhausted": exhausted()}


## 首切片胜利门槛（开发计划 M6）：所有排定的波都已入队，
## 且其流式投放已全部流完。
func exhausted() -> bool:
	return _phase == &"done" and _pending.is_empty()


## 预告下一波：确定规模等级与进攻边缘，切换到 announced 相位。
func _announce() -> void:
	# 即将到来的波号为当前索引 + 1（数值曲线见 values.md §12）。
	var wave_number: int = _wave_index + 1
	var budget: float = _budget_for(wave_number)
	# 规模等级按预算阈值划分：小股 <40，常规 <80，其余为大量。
	_tier_label = "小股" if budget < 40.0 else ("常规" if budget < 80.0 else "大量")
	if _final_requested and wave_number >= _total_waves:
		_edge = &"all"
		_edge_name = "全线"
	elif wave_number % _flank_every == 0 and not _flank_band.is_empty():
		_edge = _flank_edge
		_edge_name = {"north": "北", "south": "南", "west": "西", "east": "东"}.get(String(_flank_edge), "侧翼")
	else:
		_edge = _main_edge
		_edge_name = {"north": "北", "south": "南", "west": "西", "east": "东"}.get(String(_main_edge), "正面")
	_phase = &"announced"
	_tick_counter = 0


## 编成并入队下一波：按预算挑选敌种、按边缘带排布流式投放条目。
func _queue_wave() -> void:
	var wave_number: int = _wave_index + 1
	var budget: float = _budget_for(wave_number)
	var band: Array[Vector2i] = _flank_band if wave_number % _flank_every == 0 and not _flank_band.is_empty() else _main_band
	# 终波改从全部边缘带入场。
	if _final_requested and wave_number >= _total_waves and not _all_bands.is_empty():
		band = _all_bands
	if band.is_empty():
		band = _main_band
	if band.is_empty():
		return
	# 配额余数跨波保留；回收者与三形态建造者都计入普通数量。
	var entries: Array[StringName] = []
	var stage: int = _campaign_stage if _campaign_mode else clampi(1 + (_wave_index / 4), 1, 3)
	while budget > 0.0:
		var rules: MechEnemyDefinition
		if _ordinary_since_elite >= _ordinary_per_elite:
			rules = _choose_elite(stage, wave_number, budget)
		if rules != null:
			_ordinary_since_elite -= _ordinary_per_elite
		else:
			rules = _choose_ordinary(stage, wave_number, budget)
			if rules == null:
				break
			_ordinary_since_elite += 1
		entries.append(rules.enemy_id)
		budget -= rules.threat_cost
		_population[rules.enemy_id] = int(_population.get(rules.enemy_id, 0)) + 1
	if profiling_enabled:
		var composition: Dictionary = {}
		for id: StringName in entries:
			composition[id] = int(composition.get(id, 0)) + 1
		print("[wave:composition] wave=", wave_number, " stage=", stage, " budget_remaining=", budget, " ordinary_credit=", _ordinary_since_elite, " entries=", composition)
	# TAB 式细流：条目跨投放窗口从边缘带依次流出，
	# 首条立即生效，其余在其后均匀错峰。
	var spacing: float = float(_release_window_ticks) / maxi(1, entries.size() - 1) if entries.size() > 1 else float(_release_window_ticks)
	for index: int in range(entries.size()):
		var cell: Vector2i = band[index % band.size()]
		var rules: MechEnemyDefinition = _defs[entries[index]]
		_pending.append({"enemy_id": rules.enemy_id,
			"position": Vector2(cell) + Vector2(0.5, 0.5),
			"delay": floori(spacing * index)})
	_wave_index = wave_number
	_phase = &"active"
	_tick_counter = 0
	# 首切片胜利门槛：最后一个排定的波入队后导演永久静默；
	# _pending 清空即视为该波结束。
	if _total_waves > 0 and _wave_index >= _total_waves:
		_phase = &"done"


func _choose_ordinary(stage: int, wave: int, budget: float) -> MechEnemyDefinition:
	var candidates: Array[MechEnemyDefinition] = []
	var total: int = 0
	for rules: MechEnemyDefinition in _defs.values():
		if not rules.elite and rules.minimum_stage <= stage and rules.first_wave <= wave and rules.threat_cost <= budget and rules.stage_weights[stage - 1] > 0:
			candidates.append(rules)
			total += rules.stage_weights[stage - 1]
	if total == 0:
		return null
	var pick: int = _rng.randi_range(1, total)
	for rules: MechEnemyDefinition in candidates:
		pick -= rules.stage_weights[stage - 1]
		if pick <= 0:
			return rules
	return null


func _choose_elite(stage: int, wave: int, budget: float) -> MechEnemyDefinition:
	var types: Dictionary = {}
	for id: StringName in _population:
		var rules: MechEnemyDefinition = _defs.get(id)
		if rules != null and rules.elite and _population[id] > 0:
			types[id] = true
	var candidates: Array[MechEnemyDefinition] = []
	for rules: MechEnemyDefinition in _defs.values():
		if not rules.elite or stage < rules.minimum_stage or wave < rules.first_wave or budget < rules.threat_cost:
			continue
		if int(_population.get(rules.enemy_id, 0)) >= rules.max_alive:
			continue
		if not types.has(rules.enemy_id) and types.size() >= _max_elite_types:
			continue
		candidates.append(rules)
	if candidates.is_empty():
		return null
	# 同一波按波号选择主题，存活/在途配额仍优先于主题选择。
	return candidates[(wave - 1) % candidates.size()]


## 波次预算：B(n) = 首波 × 阶段倍率 × growth^(n-1)；终波使用固定预算。
func _budget_for(wave_number: int) -> float:
	if _final_requested and wave_number >= _total_waves:
		return _final_wave_budget
	# 战役各阶段的预算倍率（一/二/三幕分别为 1.0/1.5/2.2）。
	var stage_multiplier: float = [1.0, 1.5, 2.2][_campaign_stage - 1] if _campaign_mode else 1.0
	return _first_wave_budget * stage_multiplier * pow(_budget_growth, wave_number - 1)


## 发展度评分：运行中的建筑按净容量、产兵与科技等级累加。
func _development_progress(buildings: Array[MechBuildingState]) -> int:
	var score: int = 0
	for building: MechBuildingState in buildings:
		if building.phase != MechBuildingState.Phase.OPERATING or building.definition == null:
			continue
		score += maxi(0, building.definition.capacity_provided - building.definition.capacity_system_reserved)
		if not building.definition.produced_units.is_empty():
			score += 2
		score += maxi(0, building.definition.tech_level)
	return score


func _operating_nodes(buildings: Array[MechBuildingState]) -> int:
	var count: int = 0
	for building: MechBuildingState in buildings:
		if building.definition.building_id == NODE_ID and building.phase == MechBuildingState.Phase.OPERATING:
			count += 1
	return count


## 边缘出生带：按侧分组的可走边界环格子；最靠近地图主门标记的一侧为
## 默认带，最靠近侧翼标记的一侧承担少数波次（map-terrain.md §2/§5）。
func _collect_bands(grid: MechGridState, map_definition: MechMapDefinition) -> void:
	var sides: Dictionary = {}
	for cell: Vector2i in grid.boundary_cells():
		if not grid.is_walkable(cell):
			continue
		var side: StringName = grid.boundary_side(cell)
		if not sides.has(side):
			sides[side] = [] as Array[Vector2i]
		(sides[side] as Array[Vector2i]).append(cell)
	_main_band = _nearest_band(sides, map_definition.main_gate)
	_main_edge = _nearest_side(sides, map_definition.main_gate)
	_flank_band = _nearest_band(sides, map_definition.flank)
	_flank_edge = _nearest_side(sides, map_definition.flank)
	_all_bands.clear()
	for side: StringName in sides:
		_all_bands.append_array(sides[side])


func _nearest_band(sides: Dictionary, marker: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var best: float = INF
	for side: StringName in sides:
		for cell: Vector2i in sides[side]:
			var distance: float = cell.distance_squared_to(marker)
			if distance < best:
				best = distance
				result = sides[side]
	return result


func _nearest_side(sides: Dictionary, marker: Vector2i) -> StringName:
	var result: StringName = &""
	var best: float = INF
	for side: StringName in sides:
		for cell: Vector2i in sides[side]:
			var distance: float = cell.distance_squared_to(marker)
			if distance < best:
				best = distance
				result = side
	return result
