class_name MechSimCore
extends RefCounted
## 权威会话核心。命令先提交全部状态，然后才通知视图。

signal state_changed

var profiling_enabled: bool = false
var _clock := MechSimulationClock.new()
var _registry := MechEntityRegistry.new()
var _grid := MechGridState.new()
var _navigation := MechGridNavigation.new()
var _construction := MechConstructionSystem.new()
var _economy := MechEconomySystem.new()
var _minerals := MechMineralSystem.new()
var _production := MechProductionSystem.new()
var _units := MechUnitSystem.new()
var _enemies := MechEnemySystem.new()
var _enemy_abilities := MechEnemyAbilities.new()
var _towers := MechTowerSystem.new()
var _waves := MechWaveDirector.new()
var _threat := MechThreatSystem.new()
var _vision := MechVisionSystem.new()
var _enemy_defs: Dictionary = {}
var _tick_counter: int = 0

## 行军中的玩家单位每两秒发一次微弱移动噪声（按实体错峰）。
const MOVEMENT_NOISE_SECONDS: float = 2.0
## 交战状态复扫间隔：受击建筑在脚印 MechBuildingState.THREAT_RADIUS
## 范围内无敌后才脱离交战（每秒两次）。
const COMBAT_SCAN_SECONDS: float = 0.5
var _settings: MechFoundationSettings
var _unit_definitions: Dictionary[StringName, MechUnitDefinition] = {}
var _map_definition: MechMapDefinition
var _probe_speed: float = 2.5
var _probe_id: int = 0
var _mainbrain_id: int = 0
var _generation: int = 0
var _tick_rate: int = 30
var _in_tick: bool = false
var _starting_resources := MechResources.empty()
var _navigation_revision: int = -1
var _coverage_dirty: bool = true
var _auras_dirty: bool = true
var _repair_stations_dirty: bool = true
var _dispatch_dirty: bool = true
var _repair_station_ids: Array[int] = []
var _repair_station_targets: Dictionary[int, int] = {}
var _environment := MechEnvironmentEnergy.new()
var _alloy_processing := MechAlloyProcessing.new()
var _dispatch := MechDispatchModel.new()
var _dispatch_unit_orders: Dictionary[int, int] = {}
var _dispatch_buildings: Dictionary[int, Dictionary] = {}
var _contract_rng := RandomNumberGenerator.new()
var _garrison_pending: Dictionary[int, bool] = {}
var _environment_dirty: bool = true
var _environment_full_refresh: bool = true
var _environment_pending_cells: Array[Vector2i] = []
var _environment_explored_revision: int = -1
var _outcome: StringName = &"ongoing"
var _alert: Dictionary = {}
var _alert_sequence: int = 0

# --perf 阶段统计。所有数值单位为微秒；仅在启用性能分析时更新，
# 正常游玩不承担任何计时器或字典开销。
var _profile_tick_start: int = 0
var _profile_mark_at: int = 0
var _profile_tick_stages: Dictionary = {}
var _profile_stage_totals: Dictionary = {}
var _profile_stage_peaks: Dictionary = {}
var _profile_ticks: int = 0
var _profile_worst: Dictionary = {}
var _profile_counters: Dictionary = {}


func _init() -> void:
	_registry.movement_finished.connect(_on_movement_finished)
	_production.order_finished = _on_production_finished
	_economy.repair_authorized = _repair_authorized
	_economy.repair_paid = _repair_paid


func shutdown() -> void:
	_enemies.shutdown()
	_registry.clear()
	_enemy_abilities = MechEnemyAbilities.new()


func _on_movement_finished() -> void:
	# 注册表在整批原生移动完成后只发一次信号，而非每实体一次。
	# 在已提交的位置发布视野（含暂停前的最后一帧）；源缓存让无变化的更新几乎零开销。
	_finish_garrison_arrivals()
	_sync_vision()
	state_changed.emit()


func _profile_begin() -> void:
	_profile_tick_start = Time.get_ticks_usec()
	_profile_mark_at = _profile_tick_start
	_profile_tick_stages.clear()


func _profile_mark(stage: StringName) -> void:
	if not profiling_enabled:
		return
	var now: int = Time.get_ticks_usec()
	_profile_tick_stages[stage] = int(_profile_tick_stages.get(stage, 0)) + now - _profile_mark_at
	_profile_mark_at = now


func _profile_counter(stage: StringName) -> void:
	if profiling_enabled:
		_profile_counters[stage] = int(_profile_counters.get(stage, 0)) + 1


func _profile_end() -> void:
	if not profiling_enabled:
		return
	_profile_mark(&"tail")
	var total: int = Time.get_ticks_usec() - _profile_tick_start
	_profile_ticks += 1
	for stage: StringName in _profile_tick_stages:
		var usec: int = int(_profile_tick_stages[stage])
		_profile_stage_totals[stage] = int(_profile_stage_totals.get(stage, 0)) + usec
		_profile_stage_peaks[stage] = maxi(int(_profile_stage_peaks.get(stage, 0)), usec)
	if total > int(_profile_worst.get("total_usec", 0)):
		_profile_worst = {"total_usec": total, "stages": _profile_tick_stages.duplicate()}


## 取走并清空表现层性能行所需的累计阶段数据。最差模拟 tick 连同其完整
## 阶段拆分一并保留，无需重跑即可归因残留的耗时尖峰。
func consume_profile() -> Dictionary:
	if not profiling_enabled or _profile_ticks == 0:
		return {}
	var stages: Dictionary = {}
	for stage: StringName in _profile_stage_totals:
		stages[String(stage)] = {
			"avg_ms": float(_profile_stage_totals[stage]) / float(_profile_ticks) / 1000.0,
			"peak_ms": float(_profile_stage_peaks.get(stage, 0)) / 1000.0,
		}
	var worst: Dictionary = {}
	if not _profile_worst.is_empty():
		var worst_stages: Dictionary = {}
		for stage: StringName in _profile_worst["stages"]:
			worst_stages[String(stage)] = float(_profile_worst["stages"][stage]) / 1000.0
		worst = {"total_ms": float(_profile_worst["total_usec"]) / 1000.0,
			"stages": worst_stages}
	var counters: Dictionary = {}
	for name: StringName in _profile_counters:
		counters[String(name)] = int(_profile_counters[name])
	var result: Dictionary = {"ticks": _profile_ticks, "stages": stages,
		"worst": worst, "counters": counters}
	_profile_stage_totals.clear()
	_profile_stage_peaks.clear()
	_profile_counters.clear()
	_profile_worst.clear()
	_profile_ticks = 0
	return result


func session_ended() -> bool:
	return _outcome != &"ongoing"


func is_paused() -> bool:
	return _clock.is_paused()


func scenario_name() -> String:
	return _settings.scenario_name


func tick_rate() -> int:
	return _tick_rate


## 装配全局设置并重置开局；返回配置是否成功（失败时进入错误态）。
func configure(settings: MechFoundationSettings) -> bool:
	var settings_error: String = _settings_error(settings)
	if not settings_error.is_empty():
		return _configuration_error(settings_error)
	_settings = settings
	_unit_definitions.clear()
	for rules: MechUnitDefinition in settings.unit_definitions:
		_unit_definitions[rules.unit_id] = rules
	_map_definition = settings.map_definition
	_construction.configure(settings.building_definitions)
	var wave_error: String = _waves.configure(settings)
	if not wave_error.is_empty():
		return _configuration_error(wave_error)
	var threat_error: String = _threat.configure(settings.enemy_definitions, settings)
	if not threat_error.is_empty():
		return _configuration_error(threat_error)
	_enemy_defs.clear()
	for rules: MechEnemyDefinition in settings.enemy_definitions:
		_enemy_defs[rules.enemy_id] = rules
	# 每个开火方的战斗噪声都汇入威胁系统。
	_enemies.configure_noise(_threat.note_combat)
	_enemies.profiling_enabled = profiling_enabled
	_waves.profiling_enabled = profiling_enabled
	_units.combat_noise = _threat.note_combat
	_towers.combat_noise = _threat.note_combat
	_probe_speed = maxf(0.1, settings.probe_speed)
	_tick_rate = maxi(1, settings.simulation_hz)
	_starting_resources = MechResources.copy(settings.starting_resources)
	_clock.configure(_tick_rate)
	_reset()
	return true


## 执行一条命令：先校验，再按类型提交状态变更，最后统一刷新并广播。
func execute_command(command: MechCommand, cancel_motion: bool = true) -> Dictionary:
	var result: Dictionary = validate_command(command)
	if not result["ok"]:
		return result
	# 玩家命令使变更前提交的原生避让失效；自动化保留当前 RVO 批次，
	# 避免每秒一次的建造/队列 tick 让所有移动单位卡顿。
	if cancel_motion:
		_registry.cancel_pending_motion()
	match command.type:
		MechCommand.Type.SET_PAUSED:
			_clock.set_paused(command.payload["paused"])
			if command.payload["paused"]:
				_registry.suspend_motion()
		MechCommand.Type.MOVE_ENTITY:
			var mover: MechEntityState = _registry.get_entity(command.payload["entity_id"])
			mover.garrison_target_id = 0
			mover.order_goal = command.payload["target"]
			mover.arrival_facing = mover.position.direction_to(mover.order_goal)
			if mover.arrival_facing.is_zero_approx():
				mover.arrival_facing = mover.facing
			mover.has_arrival_facing = true
			_registry.set_move_path(command.payload["entity_id"], result["path"])
		MechCommand.Type.LOAD_SCENARIO:
			configure(command.payload["settings"])
			result = {"ok": true, "reason": "", "scenario": _settings.scenario_name}
		MechCommand.Type.QUEUE_UNIT:
			var rules: MechUnitDefinition = _unit_definitions[result["unit_id"]]
			if not _economy.try_spend(rules.cost):
				return _reject("资源不足，生产未下单")
			var ticket: int = _production.enqueue(command.payload["factory_id"], rules, _tick_rate)
			_recompute_economy()
			result = {"ok": true, "reason": "", "ticket": ticket}
		MechCommand.Type.CANCEL_PRODUCTION:
			var refund: Dictionary = _production.cancel(command.payload["factory_id"], command.payload["ticket"])
			_economy.credit(refund)
			_recompute_economy()
			result = {"ok": true, "reason": "", "refund": refund}
		MechCommand.Type.SET_RALLY:
			_production.set_rally(command.payload["factory_id"], command.payload["cell"])
		MechCommand.Type.ISSUE_UNIT_ORDER:
			_units.apply_order(result, _registry)
			result = {"ok": true, "reason": "", "count": result["ids"].size(), "kind": result["kind"]}
		MechCommand.Type.RESET_SESSION:
			_reset()
		MechCommand.Type.PLACE_BUILDING:
			result = _place(command.payload["building_id"], command.payload["origin"])
			if result["ok"]:
				_threat.note_construction(Vector2(command.payload["origin"]) + Vector2(0.5, 0.5))
		MechCommand.Type.PLACE_WALL_LINE:
			var placed: int = 0
			var spent := MechResources.empty()
			var noise_origin := Vector2i.ZERO
			for cell: Vector2i in result["origins"]:
				var placement: Dictionary = _place(&"armored_wall", cell)
				if placement["ok"]:
					if placed == 0:
						noise_origin = cell
					placed += 1
					spent = MechResources.add(spent, placement["cost"])
			if placed > 0:
				_threat.note_construction(Vector2(noise_origin) + Vector2(0.5, 0.5))
			result = {"ok": placed > 0, "reason": "" if placed > 0 else "墙线没有可下单的格子",
				"placed": placed, "skipped": result["origins"].size() - placed, "cost": spent}
		MechCommand.Type.CANCEL_CONSTRUCTION:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var refund: Dictionary = MechResources.copy(building.paid_cost)
			_remove_building(building.entity_id, refund)
			result = {"ok": true, "reason": "", "refund": refund}
		MechCommand.Type.DEMOLISH:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var clearing: bool = building.phase == MechBuildingState.Phase.RUINED
			if clearing:
				# 清基座绝不退款（values.md §7）；paid_cost 置零让拆除完成的退款路径自然为空。
				building.paid_cost = MechResources.empty()
			building.phase = MechBuildingState.Phase.DEMOLISHING
			building.elapsed_demolition_ticks = 0
			building.repairing = false
			building.repair_remainder = 0
			building.repair_hp_accumulator = 0
			if _affects_coverage(building.definition):
				_coverage_dirty = true
			_auras_dirty = true
			_repair_stations_dirty = true
			_dispatch_dirty = true
			_threat.note_construction(Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5)
			_recompute_economy()
			result["clearing"] = clearing
			result["refund"] = building.refund()
		MechCommand.Type.CANCEL_DEMOLISH:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var was_clearing: bool = building.hp <= 0
			building.phase = MechBuildingState.Phase.RUINED if was_clearing else MechBuildingState.Phase.OPERATING
			building.elapsed_demolition_ticks = 0
			if _affects_coverage(building.definition):
				_coverage_dirty = true
			if _affects_environment(building.definition):
				_environment_dirty = true
			_environment_full_refresh = true
			_auras_dirty = true
			_repair_stations_dirty = true
			_dispatch_dirty = true
			_recompute_economy()
			result["was_clearing"] = was_clearing
		MechCommand.Type.TOGGLE_REPAIR:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			_take_manual_repair(building)
			building.repairing = not building.repairing
			building.repair_manual_hold = true
			building.repair_remainder = 0
			building.repair_hp_accumulator = 0
			building.repair_waiting_for_funds = false
		MechCommand.Type.REBUILD:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var cost: Dictionary = building.rebuild_cost()
			if not _economy.try_spend(cost):
				return _reject("资源不足，重建未下单")
			building.paid_cost = MechResources.copy(cost)
			building.phase = MechBuildingState.Phase.CONSTRUCTING
			building.refresh_definition_ticks(_tick_rate)
			building.elapsed_build_ticks = 0
			building.elapsed_demolition_ticks = 0
			building.hp = 1
			building.built_hp = 1
			building.waiting_for_clearance = false
			building.reset_repair_state()
			# 重建是全新的施工，但可穿越设施在其整个生命周期内必须保持可穿越。
			var passable: bool = building.definition.trap_kind != "none" or building.definition.slow_fence_ratio < 1.0
			_grid.set_pass_through(building.entity_id, passable)
			if building.definition.is_gate:
				_grid.set_friendly_pass(building.entity_id, true)
			_production.register_factory(building)
			if _affects_coverage(building.definition):
				_coverage_dirty = true
			if _affects_environment(building.definition):
				_environment_dirty = true
			_environment_full_refresh = true
			_auras_dirty = true
			_repair_stations_dirty = true
			_dispatch_dirty = true
			_threat.note_construction(Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5)
			_recompute_economy()
			result = {"ok": true, "reason": "", "entity_id": building.entity_id, "cost": cost}
		MechCommand.Type.REPAIR_ALL:
			var count: int = 0
			for target: MechBuildingState in _construction.all():
				if target.phase == MechBuildingState.Phase.OPERATING and target.hp < target.definition.max_hp:
					_take_manual_repair(target)
					target.repairing = true
					target.repair_manual_hold = true
					target.repair_remainder = 0
					target.repair_hp_accumulator = 0
					target.repair_waiting_for_funds = false
					count += 1
			result = {"ok": true, "reason": "", "count": count}
		MechCommand.Type.UPGRADE_BUILDING:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var cost: Dictionary = MechResources.copy(result["cost"])
			if not _economy.try_spend(cost):
				return _reject("资源不足，升级未下单")
			building.upgrade_target = building.definition.upgrade_to
			building.upgrade_elapsed = 0
			building.upgrade_total = maxi(1, ceili(building.definition.upgrade_seconds * _tick_rate))
			building.upgrade_paid = cost
			_recompute_economy()
			result = {"ok": true, "reason": "", "entity_id": building.entity_id, "cost": cost}
		MechCommand.Type.CANCEL_UPGRADE:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var refund: Dictionary = building.upgrade_refund()
			building.upgrade_target = null
			building.upgrade_elapsed = 0
			building.upgrade_total = 0
			building.upgrade_paid = MechResources.empty()
			_economy.credit(refund)
			_recompute_economy()
			result = {"ok": true, "reason": "", "refund": refund}
		MechCommand.Type.REQUEST_FINAL_WAVE:
			if not _waves.request_final_wave():
				return _reject("终波请求失败")
			result = {"ok": true, "reason": "", "final_wave": true}
		MechCommand.Type.GARRISON_UNIT:
			var unit: MechEntityState = _registry.get_entity(command.payload["unit_id"])
			_units.apply_order({"ids": [unit.entity_id], "kind": &"move", "goal": result["entry"],
				"target_id": 0, "paths": {unit.entity_id: result["path"]}}, _registry)
			unit.garrison_target_id = int(result["building_id"])
			_garrison_pending[unit.entity_id] = true
			_finish_garrison_arrivals()
			result = {"ok": true, "reason": "", "building_id": unit.garrison_building_id if unit.garrisoned else unit.garrison_target_id}
		MechCommand.Type.UNGARRISON_UNIT:
			var bunker: MechBuildingState = _construction.get_building(command.payload["building_id"])
			var count: int = _eject_all_garrison(bunker)
			result = {"ok": true, "reason": "", "ejected": count}
		MechCommand.Type.ACCEPT_CONTRACT:
			var dock: MechBuildingState = _construction.get_building(command.payload["building_id"])
			var offer: Dictionary = dock.contract_offer.duplicate(true)
			if not _economy.try_spend(offer["price"]):
				return _reject("资源不足，合同未接受")
			dock.contract_unit_id = StringName(offer["unit_id"])
			dock.contract_paid = MechResources.copy(offer["price"])
			dock.contract_normal_cost = MechResources.copy(offer["normal_cost"])
			dock.contract_delivery_ticks = maxi(1, ceili(dock.definition.contract_delivery_seconds * _tick_rate))
			dock.contract_offer = {}
			_recompute_economy()
			result = {"ok": true, "reason": "", "unit_id": dock.contract_unit_id}
		MechCommand.Type.CANCEL_CONTRACT:
			var dock: MechBuildingState = _construction.get_building(command.payload["building_id"])
			var refund: Dictionary = MechResources.copy(dock.contract_paid)
			dock.contract_unit_id = &""
			dock.contract_paid = {}
			dock.contract_normal_cost = {}
			dock.contract_delivery_ticks = 0
			dock.contract_timer_ticks = maxi(1, ceili(dock.definition.contract_interval_seconds * _tick_rate))
			_economy.credit(refund)
			_recompute_economy()
			result = {"ok": true, "reason": "", "refund": refund}
		MechCommand.Type.DELETE_DISPATCH_REGION:
			var region_id: int = int(command.payload.get("region_id", 0))
			_clear_dispatch_region(region_id)
			_dispatch.remove_region(region_id)
			_dispatch_dirty = true
			result = {"ok": true, "reason": "", "region_id": region_id}
		MechCommand.Type.CONFIGURE_DISPATCH_REGION:
			var cells: Array[Vector2i] = []
			for cell: Variant in command.payload.get("cells", []):
				cells.append(cell)
			var budget: Dictionary = command.payload.get("budget_cap", {})
			var region_id: int = int(command.payload.get("region_id", 0))
			_dispatch_dirty = true
			if region_id <= 0:
				region_id = _dispatch.create_region(cells, budget, String(command.payload.get("name", "")),
					bool(command.payload.get("enabled", true)))
			else:
				_clear_dispatch_region(region_id)
				_dispatch.update_region(region_id, cells, budget, bool(command.payload.get("enabled", true)))
			for building: MechBuildingState in _construction.all():
				for y: int in range(building.definition.footprint.y):
					for x: int in range(building.definition.footprint.x):
						if building.origin + Vector2i(x, y) in cells:
							building.repair_manual_hold = false
			result = {"ok": true, "reason": "", "region_id": region_id}
	# 只有改变占用、阶段或视野源的命令才需要迷雾/导航刷新；
	# 暂停、移动、生产与维修开关不需要。
	if command.type in [
		MechCommand.Type.PLACE_BUILDING, MechCommand.Type.PLACE_WALL_LINE,
		MechCommand.Type.CANCEL_CONSTRUCTION, MechCommand.Type.DEMOLISH,
		MechCommand.Type.CANCEL_DEMOLISH, MechCommand.Type.REBUILD,
	]:
		_sync_navigation()
		_sync_vision()
	state_changed.emit()
	# 内部寻路数据绝不外泄到命令执行器之外。
	result.erase("path")
	result.erase("origins")
	return result


## 纯校验入口：复用 execute_command 的前置检查但不产生任何变更。
func validate_command(command: MechCommand) -> Dictionary:
	if session_ended() and command.type not in [MechCommand.Type.RESET_SESSION, MechCommand.Type.LOAD_SCENARIO]:
		return _reject("本局已结束，请重新开始或切换场景")
	match command.type:
		MechCommand.Type.LOAD_SCENARIO:
			if not command.payload.get("settings") is MechFoundationSettings:
				return _reject("场景配置无效")
			var error: String = _settings_error(command.payload["settings"])
			if not error.is_empty():
				return _reject(error)
		MechCommand.Type.QUEUE_UNIT, MechCommand.Type.CANCEL_PRODUCTION, MechCommand.Type.SET_RALLY:
			return _validate_production_command(command)
		MechCommand.Type.ISSUE_UNIT_ORDER:
			if not command.payload.get("ids") is Array or typeof(command.payload.get("goal")) != TYPE_VECTOR2:
				return _reject("单位指令参数无效")
			if not command.payload.get("kind") is StringName and not command.payload.get("kind") is String:
				return _reject("单位指令类型无效")
			if typeof(command.payload.get("target_id", 0)) != TYPE_INT:
				return _reject("攻击目标编号无效")
			if command.payload["kind"] == &"attack":
				var target: MechEntityState = _registry.get_entity(command.payload.get("target_id", 0))
				if target == null or not _vision.is_visible(target.position):
					return _reject("攻击目标不在当前视野内")
			return _units.plan_order(command.payload["ids"], command.payload["kind"], command.payload["goal"], command.payload.get("target_id", 0), _registry, _grid, _navigation)
		MechCommand.Type.SET_PAUSED:
			if typeof(command.payload.get("paused")) != TYPE_BOOL:
				return _reject("暂停参数无效")
		MechCommand.Type.MOVE_ENTITY:
			return _validate_move(command.payload)
		MechCommand.Type.PLACE_BUILDING:
			if not command.payload.get("building_id") is StringName and not command.payload.get("building_id") is String:
				return _reject("建筑编号无效")
			if typeof(command.payload.get("origin")) != TYPE_VECTOR2I:
				return _reject("建筑坐标无效")
			return preview_build(command.payload["building_id"], command.payload["origin"])
		MechCommand.Type.PLACE_WALL_LINE:
			var raw_cells: Variant = command.payload.get("cells")
			if not raw_cells is Array or raw_cells.is_empty() or raw_cells.size() > _grid.dimensions().x * _grid.dimensions().y:
				return _reject("墙线数据无效")
			var cells: Array[Vector2i] = []
			for cell: Variant in raw_cells:
				if typeof(cell) != TYPE_VECTOR2I:
					return _reject("墙线坐标无效")
				cells.append(cell)
			var plan: Dictionary = preview_wall_line(cells)
			plan["origins"] = cells
			return plan
		MechCommand.Type.CANCEL_CONSTRUCTION, MechCommand.Type.DEMOLISH, MechCommand.Type.CANCEL_DEMOLISH, MechCommand.Type.TOGGLE_REPAIR, MechCommand.Type.REBUILD:
			return _validate_building_action(command)
		MechCommand.Type.UPGRADE_BUILDING:
			return _validate_upgrade_command(command)
		MechCommand.Type.CANCEL_UPGRADE:
			return _validate_cancel_upgrade(command)
		MechCommand.Type.CONFIGURE_DISPATCH_REGION:
			return _validate_dispatch_region(command)
		MechCommand.Type.DELETE_DISPATCH_REGION:
			if not _dispatch_center_operating():
				return _reject("调度中心须已完工运行")
			if not _dispatch.has_region(int(command.payload.get("region_id", 0))):
				return _reject("区域不存在")
			return {"ok": true, "reason": ""}
		MechCommand.Type.REQUEST_FINAL_WAVE:
			if not _settings.campaign_mode:
				return _reject("当前为四波配置，不能请求终波")
			if _mainbrain_level() < 3 or _tech_level() < 3:
				return _reject("终波需要主脑 III 与科技 III")
			if _waves.state().get("final_requested", false):
				return _reject("终波已请求")
			return {"ok": true, "reason": ""}
		MechCommand.Type.GARRISON_UNIT, MechCommand.Type.UNGARRISON_UNIT:
			return _validate_garrison(command)
		MechCommand.Type.ACCEPT_CONTRACT, MechCommand.Type.CANCEL_CONTRACT:
			return _validate_contract(command)
		MechCommand.Type.REPAIR_ALL:
			var repair_all: Dictionary = _repair_all_status()
			if not repair_all["ok"]:
				return _reject(repair_all["reason"])
		MechCommand.Type.RESET_SESSION:
			pass
		_:
			return _reject("未知命令")
	return {"ok": true, "reason": ""}


## 推进一个固定步长 tick：收入 → 施工 → 生产 → 敌我战斗 → 炮塔 → 移动 → 结算。
func advance_one_tick() -> void:
	if session_ended() or not _clock.advance():
		return
	_in_tick = true
	if profiling_enabled:
		_profile_begin()
	# 收入先于完工结算：新完工的节点从下一 tick 开始计息。
	_economy.advance_income(_construction.all(), _tick_rate)
	_minerals.advance(_construction.all(), _economy, _tick_rate)
	_profile_mark(&"income")
	var changes: Dictionary = _construction.advance(_clear_building_footprint)
	for entity_id: int in changes["demolished"]:
		var building: MechBuildingState = _construction.get_building(entity_id)
		_remove_building(entity_id, building.refund(), true)
	if not changes["completed"].is_empty():
		_dispatch_dirty = true
		for entity_id: int in changes["completed"]:
			var completed: MechBuildingState = _construction.get_building(entity_id)
			if completed != null and _affects_coverage(completed.definition):
				_coverage_dirty = true
			if completed != null and _affects_environment(completed.definition):
				_environment_dirty = true
		_environment_full_refresh = true
		_auras_dirty = true
		_repair_stations_dirty = true
		_dispatch_dirty = true
		_recompute_economy()
	if _alloy_processing.advance(_construction.all(), _economy, _tick_rate):
		if profiling_enabled:
			print("[alloy] ever=%s produced=%d" % [
				_alloy_processing.ever_produced_alloy, _alloy_processing.produced_alloy])
		_recompute_economy()
	_advance_upgrades()
	_advance_contracts()
	_profile_mark(&"construction")
	if _tick_counter % maxi(1, ceili(COMBAT_SCAN_SECONDS * _tick_rate)) == 0:
		_scan_combat_threat()
	_prepare_repair_stations()
	_economy.advance_repairs(_construction.all(), _tick_rate)
	_advance_dispatch_automation()
	_profile_mark(&"economy")
	_sync_navigation()
	_profile_mark(&"nav")
	if _production.advance(_construction, _spawn_unit):
		_dispatch_dirty = true
		_recompute_economy()
	_profile_mark(&"production")
	_release_enemies()
	_sync_vision()
	_profile_mark(&"vision_pre")
	# 上一 tick 发出的噪声本 tick 到达游荡敌（下方单位/敌人阶段中的战斗噪声则落在下一 tick）。
	var noises: Array[Dictionary] = _threat.noises()
	# 精英源每tick收集一次；统一伤害入口复核存活状态。
	_enemy_abilities.prepare(_registry)
	var shelters: Array[MechEntityState] = _collect_shelter_sources()
	var unit_result: Dictionary = _units.advance(_registry, _grid, _navigation, _tick_rate, _vision)
	for hit: Dictionary in unit_result["enemy_hits"]:
		_damage_enemy(hit["id"], hit["damage"], shelters)
	_enemy_abilities.advance(_registry, _construction.all(), _grid, _tick_rate, _settings.max_jammed_towers)
	_profile_mark(&"units")
	var enemy_result: Dictionary = _enemies.advance(_registry, _grid, _navigation, _construction.all(), _tick_rate, noises, _vision)
	for hit: Dictionary in enemy_result["building_hits"]:
		damage_building(hit["id"], hit["damage"])
	for id: int in enemy_result["dead_units"]:
		# 被敌人摧毁的单位在残骸处喂入感疫（values.md §14）。
		var dead: MechEntityState = _registry.get_entity(id)
		if dead != null and dead.unit_definition != null:
			_infect_asset(dead.unit_definition.cost, dead.position)
		_remove_entity(id)
	if not enemy_result["dead_units"].is_empty():
		_recompute_economy()
	_enemy_abilities.validate_links(_registry, _construction.all(), _grid)
	_advance_slow_fences()
	if _trigger_traps():
		_recompute_economy()
	_profile_mark(&"enemies")
	# 本阶段批量建筑死亡已改变穿越/占用；整批结算一次导航刷新，而非逐命中刷新。
	_sync_navigation()
	_profile_mark(&"nav_combat")
	# 完成本战斗阶段的移除记账，但主脑陷落后绝不再开火或提交新的原生移动批次。
	if session_ended():
		_sync_vision()
		_profile_mark(&"vision_post")
		_profile_end()
		_in_tick = false
		state_changed.emit()
		return
	# 炮塔在敌方移动后开火；命中以结果返回，与单位击杀共用移除记账（释放格子、经济、导航）。
	_sync_vision()
	_profile_mark(&"vision_post")
	var tower_hits: Array[Dictionary] = _towers.advance(_registry, _construction.all(), _tick_rate, _grid, _vision)
	for hit: Dictionary in tower_hits:
		_damage_enemy(hit["id"], hit["damage"], shelters)
		if float(hit.get("slow_multiplier", 1.0)) < 1.0:
			var target: MechEntityState = _registry.get_entity(hit["id"])
			if target != null and target.hp > 0:
				target.apply_slow(float(hit.get("slow_multiplier", 1.0)), maxi(1, ceili(float(hit.get("slow_seconds", 0.0)) * _tick_rate)))
	_advance_garrison_fire(_collect_shelter_sources())
	_profile_mark(&"towers")
	_registry.step(_clock.step_seconds(), _grid)
	_profile_mark(&"step")
	# 行军单位嗡鸣：扩张本身就会吸引游荡敌（values.md §13）。
	_tick_counter += 1
	var movement_noise_ticks: int = maxi(1, ceili(MOVEMENT_NOISE_SECONDS * _tick_rate))
	for entity: MechEntityState in _registry.all():
		if entity.team == 1 and entity.unit_definition != null and entity.has_move_order and (_tick_counter + entity.entity_id) % movement_noise_ticks == 0:
			_threat.note_movement(entity.position)
	_check_victory()
	_profile_end()
	_in_tick = false


## 首切片胜利门槛（development-plan M6）：所有排程波次已投放完毕、
## 无波次敌人存活且无人交战——落单的游荡敌不阻止结算。
## 感疫建造者计入波次敌人；训练场不排程波次。
func _check_victory() -> void:
	if _outcome != &"ongoing" or not _waves.exhausted():
		return
	for entity: MechEntityState in _registry.all():
		if entity.team != 2 or entity.hp <= 0 or entity.enemy_definition == null:
			continue
		if not entity.wandering or entity.order == &"engaged":
			return
	_outcome = &"victory"
	_clock.set_paused(true)
	_registry.suspend_motion()
	print("[Billions Mech] session ended: victory; tick=", _clock.snapshot()["tick"])
	# 在 tick 最末尾、所有其他信号之后执行；立即发布让表现层在本帧打开胜利面板。
	state_changed.emit()


func spawn_diagnostic_enemy(enemy_id: StringName, position: Vector2) -> int:
	# 性能诊断入口；正常游玩只经波次生成敌人。
	if not _enemy_defs.has(enemy_id):
		return 0
	if profiling_enabled:
		print("[enemy:diagnostic] ", enemy_id, " at=", position)
	return _enemies.create(_registry, _enemy_defs[enemy_id], position)


## 导出整局只读快照（经济、可见实体、建筑、区域、波次与告警等），供表现层轮询。
func snapshot() -> Dictionary:
	var entities: Array[Dictionary] = []
	var garrisoned_unit_ids: Array[int] = []
	var shelters: Array[MechEntityState] = _collect_shelter_sources()
	for current: MechEntityState in _registry.all():
		if current.garrisoned:
			garrisoned_unit_ids.append(current.entity_id)
			continue
		if current.team == 2 and not _vision.is_visible(current.position):
			continue
		var entry: Dictionary = current.snapshot()
		if current.team == 2 and current.enemy_definition != null and _sheltered_by(current, shelters) != null:
			entry["sheltered"] = true
		entities.append(entry)
	for entity: Dictionary in entities:
		var building: MechBuildingState = _construction.get_building(entity["id"])
		if building != null:
			entity.merge(_building_snapshot(building), true)
			if building.definition.is_wall_like():
				entity["connections"] = _wall_connections(building.origin)
		if entity.get("shot_ticks", 0) > 0 and not _vision.is_visible(entity["shot_target"]):
			entity["shot_ticks"] = 0
	var economy: Dictionary = _economy.snapshot()
	var production: Dictionary = _minerals.production_rate(_construction.all())
	production[&"coins"] = economy["income_rate"]
	economy["production_per_minute"] = production
	economy["unit_capacity"] = _units.capacity_used(_registry)
	economy["queued_capacity"] = _production.reserved_capacity()
	var minerals: Array[Dictionary] = []
	for mineral: Dictionary in _minerals.snapshots():
		if _vision.state_at(mineral["cell"]) != MechVisionSystem.State.UNEXPLORED:
			mineral["visible"] = _vision.state_at(mineral["cell"]) == MechVisionSystem.State.VISIBLE
			minerals.append(mineral)
	var wave_state: Dictionary = _waves.state()
	return {"clock": _clock.snapshot(), "entities": entities, "economy": economy, "minerals": minerals,
		"garrisoned_unit_ids": garrisoned_unit_ids,
		"vision": _vision.snapshot(), "repair_all": _repair_all_status(),
		"scenario": _settings.scenario_name, "unit_catalog": _unit_catalog(),
		"catalog": _catalog_snapshot(), "probe_id": _probe_id,
		"alloy_processing": {"ever_produced_alloy": _alloy_processing.ever_produced_alloy,
			"produced_alloy": _alloy_processing.produced_alloy},
		"dispatch": _dispatch.snapshot(),
		"mainbrain_id": _mainbrain_id, "generation": _generation,
		"session": {"outcome": _outcome, "ended": session_ended(),
			"reason": {"defeat": "主脑已被摧毁", "victory": "威胁已清除"}.get(String(_outcome), ""),
			"duration_seconds": float(_clock.snapshot()["tick"]) / float(_tick_rate),
			"wave_number": int(wave_state.get("wave_number", 0)),
			"final_phase": _final_phase(wave_state)},
		"threat": _threat_snapshot(),
		"alert": _alert.duplicate(),
		"map_revision": _grid.revision(), "coverage_revision": _grid.coverage_revision(),
		"map_name": _map_definition.display_name}


func map_snapshot() -> Dictionary:
	var result: Dictionary = _grid.snapshot()
	result["name"] = _map_definition.display_name
	result["mainbrain_origin"] = _map_definition.mainbrain_origin
	result["mainbrain_footprint"] = _map_definition.mainbrain_footprint
	result["main_gate"] = _map_definition.main_gate
	result["flank"] = _map_definition.flank
	return result


func inspect_cell(cell: Vector2i) -> Dictionary:
	var vision: MechVisionSystem.State = _vision.state_at(cell)
	if _grid.contains(cell) and vision == MechVisionSystem.State.UNEXPLORED:
		return {"cell": cell, "inside": true, "terrain_name": "未探索", "vision": vision, "reason": "派遣单位探索该区域"}
	var info: Dictionary = _grid.inspect_cell(cell)
	info["vision"] = vision
	info["mineral"] = _minerals.at(cell)
	return info


func building_at(cell: Vector2i) -> Dictionary:
	if _vision.state_at(cell) == MechVisionSystem.State.UNEXPLORED:
		return {}
	var building: MechBuildingState = _construction.get_building(_grid.occupant_at(cell))
	return _building_snapshot(building) if building != null else {}


func _building_snapshot(building: MechBuildingState) -> Dictionary:
	var result: Dictionary = building.snapshot()
	result["family_id"] = _construction.family_root(building.definition.building_id)
	var mineral: Dictionary = _minerals.deposit(building.mineral_id)
	result["mineral"] = mineral
	result["upgrade_error"] = _upgrade_error_for(building)
	result["production"] = _production.snapshot(building.entity_id)
	result["garrison_count"] = building.garrison_unit_ids.size()
	result["contract"] = {"offer": building.contract_offer.duplicate(true),
		"delivery_seconds": float(building.contract_delivery_ticks) / _tick_rate,
		"unit_id": building.contract_unit_id, "accept_error": _contract_offer_error(building)}
	if not building.definition.produced_units.is_empty():
		var options: Array[Dictionary] = []
		for unit_id: StringName in building.definition.produced_units:
			var rules: MechUnitDefinition = _unit_definitions[unit_id]
			var option: Dictionary = rules.snapshot()
			var factory_error: String = _prerequisite_error_for(building.definition)
			if session_ended():
				option["production_error"] = "本局已结束"
			elif not factory_error.is_empty():
				option["production_error"] = factory_error
			else:
				option["production_error"] = _production.order_error(building, rules, _economy)
			options.append(option)
		result["unit_options"] = options
		result["production_error"] = options[0]["production_error"]
	if not mineral.is_empty() and mineral["remaining"] == 0 and building.operating():
		result["status"] = "矿点已耗竭 · 停产"
	return result


func _threat_snapshot() -> Dictionary:
	var threat: Dictionary = _waves.state()
	threat["final_phase"] = _final_phase(threat)
	var radar_lead: float = 0.0
	for building: MechBuildingState in _construction.all():
		if building.operating():
			radar_lead = maxf(radar_lead, building.definition.radar_warning_seconds)
	var phase: StringName = threat.get("phase", &"")
	var announce_seconds: float = _settings.wave_announce_seconds
	var release_seconds: float = float(threat.get("seconds_remaining", 0.0))
	if phase in [&"silence", &"active"]:
		release_seconds += announce_seconds
	if radar_lead > 0.0 and phase in [&"silence", &"active"] \
			and release_seconds > announce_seconds \
			and release_seconds <= announce_seconds + radar_lead:
		threat["radar_warning"] = true
		threat["radar_lead_seconds"] = radar_lead
		threat["radar_edge_name"] = threat.get("next_edge_name", "")
		threat["radar_wave_number"] = threat.get("next_wave_number", 1)
		threat["radar_seconds_remaining"] = release_seconds
	return threat


func _catalog_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = _construction.catalog(_economy)
	for entry: Dictionary in result:
		if entry["building_id"] == &"tech_center" and not _alloy_processing.ever_produced_alloy:
			entry["unavailable_reason"] = "需先产出第一份合金"
		elif entry["building_id"] == &"crystal_extractor" and _mainbrain_level() < 3:
			entry["unavailable_reason"] = "晶体采掘需要主脑 III"
		elif entry["building_id"] == &"dispatch_center" and _tech_level() < 3:
			entry["unavailable_reason"] = "调度中心需要科技 III"
		elif entry.get("unavailable_reason", "").is_empty():
			var prerequisite: String = _prerequisite_error_for(_construction.definition(entry["building_id"]))
			if not prerequisite.is_empty():
				entry["unavailable_reason"] = prerequisite
	return result


func _contract_reserved_capacity() -> int:
	var total: int = 0
	for building: MechBuildingState in _construction.all():
		if building.contract_unit_id != &"" and _unit_definitions.has(building.contract_unit_id):
			total += _unit_definitions[building.contract_unit_id].capacity_cost
	return total


func _advance_contracts() -> void:
	for building: MechBuildingState in _construction.all():
		if building.definition.contract_interval_seconds <= 0.0 or not building.operating():
			continue
		var interval_ticks: int = maxi(1, ceili(building.definition.contract_interval_seconds * _tick_rate))
		if building.contract_timer_ticks < 0:
			building.contract_timer_ticks = interval_ticks
		if building.contract_unit_id != &"":
			if building.contract_delivery_ticks > 0:
				building.contract_delivery_ticks -= 1
			if building.contract_delivery_ticks <= 0 and _spawn_unit(
				building, building.origin + building.definition.footprint, building.contract_unit_id
			):
				building.contract_unit_id = &""
				building.contract_paid = {}
				building.contract_normal_cost = {}
				building.contract_timer_ticks = interval_ticks
				_recompute_economy()
			continue
		if not building.contract_offer.is_empty():
			continue
		building.contract_timer_ticks = maxi(0, building.contract_timer_ticks - 1)
		if building.contract_timer_ticks == 0:
			_create_contract_offer(building)


func _create_contract_offer(building: MechBuildingState) -> void:
	var candidates: Array[StringName] = []
	for unit_id: StringName in [&"sentinel", &"heavy_mech", &"rail_mech"]:
		if not _unit_definitions.has(unit_id):
			continue
		if not _contract_unit_error(unit_id).is_empty():
			continue
		candidates.append(unit_id)
	if candidates.is_empty():
		return
	var chosen: StringName = candidates[_contract_rng.randi_range(0, candidates.size() - 1)]
	var rules: MechUnitDefinition = _unit_definitions[chosen]
	var price: Dictionary = MechResources.copy(rules.cost)
	price[&"coins"] = ceili(float(price.get(&"coins", 0)) * building.definition.contract_price_multiplier)
	building.contract_offer = {"unit_id": chosen, "unit_name": rules.display_name,
		"price": price, "normal_cost": MechResources.copy(rules.cost), "capacity": rules.capacity_cost}
	building.contract_normal_cost = MechResources.copy(rules.cost)


func _prepare_repair_stations() -> void:
	if not _repair_stations_dirty:
		for source_id: int in _repair_station_ids:
			var station: MechBuildingState = _construction.get_building(source_id)
			if station == null or not station.operating() or station.definition.repair_rate <= 0.0:
				_repair_stations_dirty = true
				break
			var target_id: int = int(_repair_station_targets.get(source_id, 0))
			if target_id == 0:
				continue
			var target: MechBuildingState = _construction.get_building(target_id)
			if target == null or not target.operating() or target.hp >= target.definition.max_hp:
				_repair_stations_dirty = true
				break
		if not _repair_stations_dirty:
			return
	var all: Array[MechBuildingState] = _construction.all()
	# 重分配由事件驱动：受击、结构变化或目标满员。
	for building: MechBuildingState in all:
		if building.repair_auto_source > 0:
			building.repairing = false
			building.repair_rate_override = 0.0
			building.repair_auto_source = 0
	_repair_station_ids.clear()
	_repair_station_targets.clear()
	for station: MechBuildingState in all:
		if station.definition.repair_rate <= 0.0 or not station.operating():
			continue
		_repair_station_ids.append(station.entity_id)
		var station_center: Vector2 = Vector2(station.origin) + Vector2(station.definition.footprint) * 0.5
		var target: MechBuildingState = null
		var best: float = station.definition.repair_radius * station.definition.repair_radius
		for candidate: MechBuildingState in all:
			if candidate.entity_id == station.entity_id or candidate.phase != MechBuildingState.Phase.OPERATING:
				continue
			if candidate.repair_auto_source < 0 or candidate.repair_manual_hold:
				continue
			if candidate.hp >= candidate.definition.max_hp:
				continue
			var center: Vector2 = Vector2(candidate.origin) + Vector2(candidate.definition.footprint) * 0.5
			var distance: float = station_center.distance_squared_to(center)
			if distance <= best:
				best = distance
				target = candidate
		if target != null:
			target.repairing = true
			target.repair_rate_override = station.definition.repair_rate
			target.repair_auto_source = station.entity_id
			_repair_station_targets[station.entity_id] = target.entity_id
	_repair_stations_dirty = false


func _dispatch_center_operating() -> bool:
	for building: MechBuildingState in _construction.all():
		if building.operating() and building.definition.building_id == &"dispatch_center":
			return true
	return false


func _validate_dispatch_region(command: MechCommand) -> Dictionary:
	if not _dispatch_center_operating():
		return _reject("调度中心须已完工运行")
	var cells: Variant = command.payload.get("cells", [])
	if not cells is Array or cells.is_empty():
		return _reject("区域格集合不能为空")
	for cell: Variant in cells:
		if typeof(cell) != TYPE_VECTOR2I or not _grid.contains(cell):
			return _reject("区域格无效")
		if _vision.state_at(cell) == MechVisionSystem.State.UNEXPLORED:
			return _reject("区域不能包含未探索格")
	var budget: Variant = command.payload.get("budget_cap", {})
	if not budget is Dictionary or not MechResources.valid(budget):
		return _reject("区域预算无效")
	if int(command.payload.get("region_id", 0)) > 0 and not _dispatch.has_region(int(command.payload["region_id"])):
		return _reject("区域不存在")
	return {"ok": true, "reason": ""}


func _advance_garrison_fire(shelters: Array[MechEntityState]) -> void:
	for building: MechBuildingState in _construction.all():
		if building.definition.garrison_capacity <= 0 or not building.operating():
			continue
		var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
		for id: int in building.garrison_unit_ids:
			var unit: MechEntityState = _registry.get_entity(id)
			if unit == null or unit.hp <= 0:
				continue
			unit.shot_ticks = maxi(0, unit.shot_ticks - 1)
			unit.cooldown_ticks = maxi(0, unit.cooldown_ticks - 1)
			if unit.cooldown_ticks > 0:
				continue
			var range_sq: float = pow(unit.unit_definition.attack_range + building.definition.garrison_range_bonus, 2.0)
			var target: MechEntityState = null
			var best: float = range_sq
			for enemy: MechEntityState in _registry.all():
				if enemy.team != 2 or enemy.hp <= 0 or not _vision.is_visible(enemy.position):
					continue
				var distance: float = center.distance_squared_to(enemy.position)
				if distance <= best and _grid.terrain_line_clear(center, enemy.position):
					best = distance
					target = enemy
			if target == null:
				continue
			unit.cooldown_ticks = maxi(1, ceili(unit.unit_definition.attack_seconds * _tick_rate))
			unit.shot_ticks = 4
			unit.face_direction(target.position - center)
			_threat.note_combat(target.position)
			unit.shot_target = target.position
			_damage_enemy(target.entity_id, unit.unit_definition.damage, shelters)


func _auto_queue_unit(region_id: int, cells: Dictionary) -> void:
	for building: MechBuildingState in _construction.all():
		if not building.operating() or building.definition.produced_units.is_empty():
			continue
		var in_region: bool = false
		for y: int in range(building.definition.footprint.y):
			for x: int in range(building.definition.footprint.x):
				if cells.has(building.origin + Vector2i(x, y)):
					in_region = true
					break
			if in_region:
				break
		if not in_region:
			continue
		var production: Dictionary = _production.snapshot(building.entity_id)
		if not production.get("queue", []).is_empty():
			continue
		var unit_id: StringName = building.definition.produced_units[0]
		var rules: MechUnitDefinition = _unit_definitions.get(unit_id)
		if rules == null:
			continue
		var error: String = _production.order_error(building, rules, _economy)
		if not error.is_empty():
			continue
		var pending := "unit-pending:%d:%d" % [region_id, _tick_counter]
		if not _dispatch.commit(region_id, pending, rules.cost, _dispatch.generation()):
			_dispatch.note_failure(region_id, _tick_counter)
			continue
		var queued: Dictionary = execute_command(MechCommand.new(MechCommand.Type.QUEUE_UNIT,
			{"factory_id": building.entity_id, "unit_id": unit_id}), false)
		if queued.get("ok", false):
			var ticket: int = int(queued["ticket"])
			_dispatch.settle(region_id, pending, ticket, _tick_counter)
			_dispatch_unit_orders[ticket] = region_id
			_dispatch.note_success(region_id)
		else:
			_dispatch.release(region_id, pending)
			_dispatch.note_failure(region_id, _tick_counter)
		return


func _validate_garrison(command: MechCommand) -> Dictionary:
	if command.type == MechCommand.Type.GARRISON_UNIT:
		if typeof(command.payload.get("unit_id")) != TYPE_INT:
			return _reject("单位编号无效")
		var unit: MechEntityState = _registry.get_entity(command.payload["unit_id"])
		if unit == null or unit.team != 1 or unit.unit_definition == null or unit.hp <= 0 or unit.garrisoned:
			return _reject("请选择未驻防的卫兵")
		if unit.unit_definition.unit_id != &"sentinel":
			return _reject("只有卫兵可以进驻，侦察和重型单位不可驻防")
		var plan: Dictionary = _garrison_entry_plan(unit)
		if plan.is_empty():
			return _reject("附近没有尚有空位且入口可达的驻防碉堡")
		plan["ok"] = true
		plan["reason"] = ""
		return plan
	if typeof(command.payload.get("building_id")) != TYPE_INT:
		return _reject("碉堡编号无效")
	var bunker: MechBuildingState = _construction.get_building(command.payload["building_id"])
	if bunker == null or bunker.definition.garrison_capacity <= 0:
		return _reject("请选择驻防碉堡")
	if bunker.garrison_unit_ids.is_empty():
		return _reject("碉堡内没有驻防单位")
	return {"ok": true, "reason": ""}


func _contract_offer_error(dock: MechBuildingState) -> String:
	if dock == null or not dock.operating() or dock.definition.contract_interval_seconds <= 0.0:
		return "请选择运行中的远征接驳站"
	if dock.contract_offer.is_empty() or dock.contract_unit_id != &"":
		return "当前没有可接受的合同"
	var prerequisite: String = _prerequisite_error_for(dock.definition)
	if not prerequisite.is_empty():
		return prerequisite
	var unit_id := StringName(dock.contract_offer["unit_id"])
	var rules: MechUnitDefinition = _unit_definitions.get(unit_id)
	if rules == null:
		return "合同单位无效"
	var unit_error: String = _contract_unit_error(unit_id)
	if not unit_error.is_empty():
		return unit_error
	return _economy.contract_error(rules.capacity_cost, dock.contract_offer["price"])


func _contract_unit_error(unit_id: StringName) -> String:
	var required: int = 3 if unit_id == &"rail_mech" else (2 if unit_id == &"heavy_mech" else 0)
	if _tech_level() < required or _mainbrain_level() < required:
		return "合同单位需要主脑和科技等级 %d" % required
	return ""


func _validate_contract(command: MechCommand) -> Dictionary:
	if typeof(command.payload.get("building_id")) != TYPE_INT:
		return _reject("接驳站编号无效")
	var dock: MechBuildingState = _construction.get_building(command.payload["building_id"])
	if command.type == MechCommand.Type.ACCEPT_CONTRACT:
		var error: String = _contract_offer_error(dock)
		return {"ok": true, "reason": ""} if error.is_empty() else _reject(error)
	# 断电或失去前置后仍必须可取消已付费订单，包括拆除待定期间。
	if dock == null or dock.contract_unit_id == &"":
		return _reject("没有未交付合同")
	return {"ok": true, "reason": ""}


func _garrison_reservations(bunker: MechBuildingState, ignored_id: int = 0) -> int:
	var count: int = bunker.garrison_unit_ids.size()
	for id: int in _garrison_pending:
		var unit: MechEntityState = _registry.get_entity(id)
		if unit != null and id != ignored_id and unit.hp > 0 and unit.garrison_target_id == bunker.entity_id:
			count += 1
	return count


func _garrison_perimeter(bunker: MechBuildingState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var area := Rect2i(bunker.origin, bunker.definition.footprint)
	for x: int in range(area.position.x, area.end.x):
		cells.append(Vector2i(x, area.position.y - 1))
		cells.append(Vector2i(x, area.end.y))
	for y: int in range(area.position.y, area.end.y):
		cells.append(Vector2i(area.position.x - 1, y))
		cells.append(Vector2i(area.end.x, y))
	return cells


func _garrison_entry_plan(unit: MechEntityState) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for bunker: MechBuildingState in _construction.all():
		if not bunker.operating() or bunker.definition.garrison_capacity <= 0:
			continue
		if _garrison_reservations(bunker, unit.entity_id) >= bunker.definition.garrison_capacity:
			continue
		var center: Vector2 = Vector2(bunker.origin) + Vector2(bunker.definition.footprint) * 0.5
		if unit.position.distance_to(center) > 12.0:
			continue
		for cell: Vector2i in _garrison_perimeter(bunker):
			var entry: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
			if not _grid.mobile_position_clear(entry, {}, true):
				continue
			var path: PackedVector2Array = _navigation.find_path(unit.position, cell)
			if path.is_empty():
				continue
			var length: float = 0.0
			var previous: Vector2 = unit.position
			for point: Vector2 in path:
				length += previous.distance_to(point)
				previous = point
			if length < best_distance:
				best_distance = length
				best = {"building_id": bunker.entity_id, "entry": entry, "path": path}
	return best


func _finish_garrison_arrivals() -> void:
	if session_ended():
		return
	for id: int in _garrison_pending.keys():
		var unit: MechEntityState = _registry.get_entity(id)
		if unit == null or unit.garrison_target_id == 0:
			_garrison_pending.erase(id)
			continue
		var bunker: MechBuildingState = _construction.get_building(unit.garrison_target_id)
		if unit.hp <= 0 or bunker == null or not bunker.operating() or unit.order not in [&"move", &"idle"]:
			unit.garrison_target_id = 0
			_garrison_pending.erase(id)
			continue
		if unit.position.distance_to(unit.order_goal) > MechEntityState.ARRIVAL_TOLERANCE:
			continue
		var entry_cell := Vector2i(unit.order_goal.floor())
		if entry_cell not in _garrison_perimeter(bunker) or bunker.garrison_unit_ids.size() >= bunker.definition.garrison_capacity:
			unit.garrison_target_id = 0
			_garrison_pending.erase(id)
			continue
		_garrison_unit(unit, bunker)


func _garrison_unit(unit: MechEntityState, bunker: MechBuildingState) -> void:
	_garrison_pending.erase(unit.entity_id)
	unit.garrison_saved_speed = unit.rvo_speed
	unit.rvo_speed = 0.0
	unit.order = &"garrisoned"
	unit.attack_target_id = 0
	unit.garrison_target_id = 0
	unit.garrisoned = true
	unit.garrison_building_id = bunker.entity_id
	unit.formation_id = 0
	unit.has_arrival_facing = false
	_registry.teleport(unit.entity_id, Vector2(bunker.origin) + Vector2(bunker.definition.footprint) * 0.5)
	bunker.garrison_unit_ids.append(unit.entity_id)


func _eject_all_garrison(bunker: MechBuildingState, forced: bool = false, infect_losses: bool = false) -> int:
	var count: int = 0
	for id: int in bunker.garrison_unit_ids.duplicate():
		var unit: MechEntityState = _registry.get_entity(id)
		if unit == null:
			bunker.garrison_unit_ids.erase(id)
			continue
		var cell: Vector2i = _garrison_eject_cell(bunker)
		if cell.x < 0:
			# 主动撤离等待空位；被摧毁/移除的碉堡不能藏匿单位，也不能隔墙传送。
			if forced:
				if infect_losses:
					_infect_asset(unit.unit_definition.cost, unit.position)
				_remove_entity(id)
			continue
		unit.garrisoned = false
		unit.garrison_building_id = 0
		unit.garrison_target_id = 0
		unit.rvo_speed = unit.garrison_saved_speed if unit.garrison_saved_speed > 0.0 else unit.unit_definition.move_speed
		unit.order = &"idle"
		unit.attack_target_id = 0
		_registry.teleport(id, Vector2(cell) + Vector2(0.5, 0.5))
		unit.order_goal = unit.position
		bunker.garrison_unit_ids.erase(id)
		count += 1
	return count


func _garrison_eject_cell(bunker: MechBuildingState) -> Vector2i:
	for cell: Vector2i in _garrison_perimeter(bunker):
		var point: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
		if _grid.mobile_position_clear(point, {}, true) and _registry.mobile_space_free(point):
			return cell
	return Vector2i(-1, -1)


func _clear_dispatch_region(region_id: int) -> void:
	for building: MechBuildingState in _construction.all():
		if building.repair_auto_source == -region_id:
			building.repairing = false
			building.repair_auto_source = 0
			building.repair_rate_override = 0.0
	for task_id: String in _dispatch.task_ids(region_id):
		_dispatch.release(region_id, task_id)


func _advance_dispatch_automation() -> void:
	if not _dispatch_dirty and _tick_counter % 30 != 0:
		return
	_dispatch_dirty = false
	if not _dispatch_center_operating():
		for region_id: int in _dispatch.region_ids():
			_clear_dispatch_region(region_id)
		return
	var regions: Array = _dispatch.snapshot()["regions"]
	for region: Dictionary in regions:
		var region_id: int = int(region["id"])
		if not region.get("enabled", false):
			_clear_dispatch_region(region_id)
			continue
		var cells: Dictionary = {}
		for cell: Vector2i in region.get("cells", []):
			cells[cell] = true
		# 释放目标满员、消失或被手动接管的任务。
		for task_id: String in region.get("tasks", {}).keys():
			if not task_id.begins_with("repair:"):
				continue
			var target_id: int = int(task_id.trim_prefix("repair:"))
			var target: MechBuildingState = _construction.get_building(target_id)
			if target == null or not target.operating() or target.hp >= target.definition.max_hp \
					or not target.repairing or target.repair_auto_source != -region_id:
				_dispatch.release(region_id, task_id)
				if target != null and target.repair_auto_source == -region_id:
					target.repairing = false
					target.repair_auto_source = 0
					target.repair_rate_override = 0.0
		if not _dispatch.can_retry(region_id, _tick_counter):
			continue
		for building: MechBuildingState in _construction.all():
			if building.phase != MechBuildingState.Phase.OPERATING or building.hp >= building.definition.max_hp:
				continue
			if building.threatened or building.repairing or building.repair_manual_hold:
				continue
			var in_region: bool = false
			for y: int in range(building.definition.footprint.y):
				for x: int in range(building.definition.footprint.x):
					if cells.has(building.origin + Vector2i(x, y)):
						in_region = true
						break
				if in_region:
					break
			if not in_region:
				continue
			var estimate := {}
			var missing_hp: int = building.definition.max_hp - building.hp
			var denominator: int = 4 * maxi(1, building.definition.max_hp)
			for key: StringName in MechResources.KEYS:
				estimate[key] = (int(building.repair_material_remainder.get(key, 0))
					+ missing_hp * int(building.definition.cost.get(key, 0))) / denominator
			var task_id := "repair:%d" % building.entity_id
			if not _dispatch.commit(region_id, task_id, estimate, _dispatch.generation()):
				_dispatch.note_failure(region_id, _tick_counter)
				break
			_dispatch.note_success(region_id)
			building.repairing = true
			building.repair_hp_accumulator = 0
			building.repair_waiting_for_funds = false
			building.repair_rate_override = 0.0
			building.repair_auto_source = -region_id
		_auto_queue_unit(region_id, cells)
		if _tick_counter % 30 != 0:
			continue
		var has_build_task: bool = false
		for pending: MechBuildingState in _construction.all():
			if pending.phase != MechBuildingState.Phase.CONSTRUCTING or pending.definition.building_id not in [&"relay_node", &"compute_node"]:
				continue
			for cell: Vector2i in region.get("cells", []):
				if Rect2i(pending.origin, pending.definition.footprint).has_point(cell):
					has_build_task = true
					break
			if has_build_task:
				break
		if has_build_task:
			continue
		var has_relay: bool = false
		for building: MechBuildingState in _construction.all():
			if building.definition.building_id != &"relay_node" or not building.operating():
				continue
			for y: int in range(building.definition.footprint.y):
				for x: int in range(building.definition.footprint.x):
					if cells.has(building.origin + Vector2i(x, y)):
						has_relay = true
						break
				if has_relay:
					break
			if has_relay:
				break
		var build_id: StringName = &"compute_node" if has_relay else &"relay_node"
		var rules: MechBuildingDefinition = _construction.definition(build_id)
		if rules == null:
			continue
		var site := Vector2i(-1, -1)
		for cell: Vector2i in region.get("cells", []):
			if preview_build(build_id, cell)["ok"]:
				site = cell
				break
		if site.x < 0:
			continue
		var task_id := "build:%d:%d" % [site.x, site.y]
		var estimate := MechResources.copy(rules.cost)
		if not _dispatch.commit(region_id, task_id, estimate, _dispatch.generation()):
			_dispatch.note_failure(region_id, _tick_counter)
			continue
		var placed: Dictionary = execute_command(MechCommand.new(MechCommand.Type.PLACE_BUILDING,
			{"building_id": build_id, "origin": site}), false)
		if placed.get("ok", false):
			var entity_id: int = int(placed["entity_id"])
			_dispatch.settle(region_id, task_id, entity_id, _tick_counter)
			_dispatch_buildings[entity_id] = {"region_id": region_id, "cost": MechResources.copy(placed["cost"])}
			_dispatch.note_success(region_id)
		else:
			_dispatch.release(region_id, task_id)
			_dispatch.note_failure(region_id, _tick_counter)


func _upgrade_error_for(building: MechBuildingState) -> String:
	if building.definition.upgrade_to == null:
		return ""
	if building.upgrade_target != null:
		return "该建筑已在升级"
	if building.phase != MechBuildingState.Phase.OPERATING:
		return "只有完工建筑可升级"
	if building.definition.is_core:
		if _tech_level() < 1:
			return "主脑升级需要运行中的科技中心 I"
	elif building.definition.tech_level == 1:
		if _mainbrain_level() < 2:
			return "科技中心 II 需要主脑 II"
	if building.definition.upgrade_to.requires_water and not _has_water_edge(
		building.definition.upgrade_to, building.origin
	):
		return "水冷站需与水域正交相邻"
	var prerequisite: String = _prerequisite_error_for(building.definition.upgrade_to)
	if not prerequisite.is_empty():
		return prerequisite
	return _economy.upgrade_error(
		building.definition, building.definition.upgrade_to, building.definition.upgrade_cost,
		_cooling_aura_multiplier_at(building.origin, building.definition.upgrade_to.footprint)
	)


func _recompute_economy() -> void:
	# 覆盖是以主脑为根的连通图，先于经济读取更新；覆盖修订号独立于占用/导航修订号，
	# 生产与单位变化绝不弄脏它。
	if _coverage_dirty:
		var coverage_changes: Array[Vector2i] = _grid.recompute_coverage(_construction.all())
		_coverage_dirty = false
		if not coverage_changes.is_empty():
			_auras_dirty = true
			_repair_stations_dirty = true
			_dispatch_dirty = true
		if profiling_enabled and not coverage_changes.is_empty():
			print("[coverage] changed_cells=%d revision=%d" % [
				coverage_changes.size(), _grid.coverage_revision()])
	if _environment_dirty:
		_refresh_environment_power()
		_environment_dirty = false
	if _auras_dirty:
		_refresh_auras()
		_auras_dirty = false
	_economy.recompute(_construction.all(), _grid, _units.capacity_used(_registry),
		_production.reserved_capacity() + _contract_reserved_capacity())


func _refresh_auras() -> void:
	var all: Array[MechBuildingState] = _construction.all()
	var sources: Array[Dictionary] = []
	for source: MechBuildingState in all:
		if source.definition.aura_kind == "none" or source.phase != MechBuildingState.Phase.OPERATING:
			continue
		if not _grid.footprint_covered(source.origin, source.definition.footprint):
			continue
		sources.append({"building": source, "center": Vector2(source.origin)
			+ Vector2(source.definition.footprint) * 0.5})
	for target: MechBuildingState in all:
		target.income_multiplier_percent = 100
		target.extraction_multiplier_percent = 100
		target.cooling_multiplier_percent = 100
		if target.phase == MechBuildingState.Phase.RUINED:
			continue
		if not _grid.footprint_covered(target.origin, target.definition.footprint):
			continue
		var target_center: Vector2 = Vector2(target.origin) + Vector2(target.definition.footprint) * 0.5
		var is_node: bool = target.definition.capacity_provided > 0 and not target.definition.is_core
		var is_extractor: bool = target.definition.mined_resource in [&"metal_ore", &"fuel"]
		var best_income: float = 1.0
		var best_extraction: float = 1.0
		var best_cooling: float = 1.0
		for entry: Dictionary in sources:
			var source: MechBuildingState = entry["building"]
			if source.entity_id == target.entity_id:
				continue
			if source.definition.aura_kind == "mining" and not is_extractor:
				continue
			if source.definition.aura_kind in ["cooling", "income"] and not is_node:
				continue
			if entry["center"].distance_to(target_center) > source.definition.aura_radius:
				continue
			match source.definition.aura_kind:
				"mining":
					best_extraction = maxf(best_extraction, source.definition.aura_multiplier)
				"cooling":
					best_cooling = minf(best_cooling, source.definition.aura_multiplier)
				"income":
					best_income = maxf(best_income, source.definition.aura_multiplier)
		target.extraction_multiplier_percent = roundi(best_extraction * 100.0)
		target.income_multiplier_percent = roundi(best_income * 100.0)
		target.cooling_multiplier_percent = roundi(best_cooling * 100.0)


func _refresh_environment_power() -> void:
	var pending: Array[Vector2i] = _environment_pending_cells.duplicate()
	_environment_pending_cells.clear()
	var full: bool = _environment_full_refresh
	_environment_full_refresh = false
	for building: MechBuildingState in _construction.all():
		if building.hp <= 0:
			continue
		var energy_type := StringName(building.definition.environment_energy)
		if energy_type == &"none":
			continue
		if not full and not pending.is_empty():
			var bounds: Rect2i = _environment.collection_bounds(building.origin, building.definition.footprint)
			var affected: bool = false
			for cell: Vector2i in pending:
				if bounds.has_point(cell):
					affected = true
					break
			if not affected:
				continue
		var previous_power: int = building.environment_power
		building.environment_power = _environment.score(
			energy_type, building.origin, building.definition.footprint, _grid, _vision,
			building.definition.environment_output_multiplier,
			building.definition.environment_output_cap
		)
		if profiling_enabled and building.environment_power != previous_power:
			print("[environment] id=%d type=%s power=%d" % [
				building.entity_id, energy_type, building.environment_power])


func _spawn_unit(building: MechBuildingState, rally: Vector2i, unit_id: StringName) -> bool:
	return _units.spawn(building, rally, _unit_definitions[unit_id], _registry, _grid, _navigation)


## 导出全部单位定义的只读快照，供 HUD 组装生产菜单。
func _unit_catalog() -> Dictionary:
	var result: Dictionary = {}
	for id: StringName in _unit_definitions:
		result[id] = _unit_definitions[id].snapshot()
	return result


## 波次投放、游荡敌补充与感疫都以生成请求到达；实体创建留在敌人系统，
## 使定义、队伍与行军指令集中一处。
func _release_enemies() -> void:
	var requests: Array[Dictionary] = []
	if _settings.campaign_mode:
		_waves.set_campaign_stage(_mainbrain_level())
	requests.append_array(_waves.advance(_grid, _construction.all(), _registry.all()))
	requests.append_array(_threat.advance(_construction.all()))
	_release_spawns(requests)


func _release_spawns(requests: Array[Dictionary]) -> void:
	if session_ended():
		return
	for request: Dictionary in requests:
		var rules: MechEnemyDefinition = _enemy_defs.get(request["enemy_id"])
		if rules != null:
			_enemies.create(_registry, rules, request["position"], bool(request.get("wandering", false)))


func _infect_asset(cost: Dictionary, position: Vector2) -> void:
	var requests: Array[Dictionary] = _threat.infect(cost, position)
	if requests.is_empty():
		return
	_release_spawns(requests)
	# 地形盲区绝不能默默吞掉感疫事件；只报告定性方向，不暴露敌人数量或隐匿位置。
	var center: Vector2 = Vector2(_map_definition.mainbrain_origin) + Vector2(_map_definition.mainbrain_footprint) * 0.5
	var offset: Vector2 = position - center
	var delta := Vector2(offset.x - offset.y, (offset.x + offset.y) * 0.5)
	var direction: String
	if delta.length_squared() < 1.0:
		direction = "基地附近"
	elif absf(delta.x) > absf(delta.y) * 2.0:
		direction = "基地东侧" if delta.x > 0.0 else "基地西侧"
	elif absf(delta.y) > absf(delta.x) * 2.0:
		direction = "基地南侧" if delta.y > 0.0 else "基地北侧"
	else:
		direction = "基地" + ("东" if delta.x > 0.0 else "西") + ("南侧" if delta.y > 0.0 else "北侧")
	_alert_sequence += 1
	_alert = {"sequence": _alert_sequence, "text": "%s发生感疫脉冲，注意来袭威胁。" % direction}


func _validate_production_command(command: MechCommand) -> Dictionary:
	if typeof(command.payload.get("factory_id")) != TYPE_INT:
		return _reject("工厂编号无效")
	var building: MechBuildingState = _construction.get_building(command.payload["factory_id"])
	if building == null or building.definition.produced_units.is_empty():
		return _reject("请选择有效组装厂")
	if command.type == MechCommand.Type.QUEUE_UNIT:
		var factory_prerequisite: String = _prerequisite_error_for(building.definition)
		if not factory_prerequisite.is_empty():
			return _reject("工厂前置失效：" + factory_prerequisite)
		var requested: Variant = command.payload.get("unit_id", building.definition.produced_units[0])
		if not requested is StringName and not requested is String:
			return _reject("单位类型无效")
		var unit_id := StringName(requested)
		if unit_id not in building.definition.produced_units or not _unit_definitions.has(unit_id):
			return _reject("该工厂不能生产此单位")
		var error: String = _production.order_error(building, _unit_definitions[unit_id], _economy)
		if not error.is_empty():
			return _reject(error)
		return {"ok": true, "reason": "", "unit_id": unit_id}
	elif command.type == MechCommand.Type.CANCEL_PRODUCTION:
		if typeof(command.payload.get("ticket")) != TYPE_INT or not _production.has_ticket(building.entity_id, command.payload["ticket"]):
			return _reject("生产订单已不存在")
	else:
		if building.phase == MechBuildingState.Phase.DEMOLISHING:
			return _reject("拆除期间不可修改集结点")
		if typeof(command.payload.get("cell")) != TYPE_VECTOR2I or not _grid.is_walkable(command.payload["cell"], true, {}, true):
			return _reject("集结点须为地图内可通行格")
	return {"ok": true, "reason": ""}


func _remove_entity(id: int) -> void:
	_garrison_pending.erase(id)
	var entity: MechEntityState = _registry.get_entity(id)
	if entity == null:
		return
	if _construction.get_building(id) != null:
		_remove_building(id, MechResources.empty())
		return
	if entity.garrison_building_id != 0:
		var bunker: MechBuildingState = _construction.get_building(entity.garrison_building_id)
		if bunker != null:
			bunker.garrison_unit_ids.erase(id)
	if _grid.occupant_at(Vector2i(entity.position.floor())) == id:
		_grid.release(id)
	_registry.remove(id)


## 当前活跃偏转场源；普通敌人不承担范围减伤能力。
func _collect_shelter_sources() -> Array[MechEntityState]:
	var sources: Array[MechEntityState] = []
	for entity: MechEntityState in _registry.all():
		if entity.team == 2 and entity.hp > 0 and entity.enemy_definition != null and entity.enemy_definition.shelter_radius > 0.0:
			sources.append(entity)
	return sources


## 敌人的唯一伤害入口（单位与炮塔火力同样适用）：每次命中只应用一次
## 庇护减伤，随后经共享移除路径结算死亡。感疫绝不在此触发；
## 它只覆盖玩家资产。
func _damage_enemy(entity_id: int, damage: int, shelters: Array[MechEntityState]) -> void:
	var entity: MechEntityState = _registry.get_entity(entity_id)
	if entity == null or entity.hp <= 0 or damage <= 0:
		return
	var source: MechEntityState = _sheltered_by(entity, shelters)
	var reduction: float = _enemy_abilities.defense(entity)
	if source != null:
		reduction = maxf(reduction, source.enemy_definition.shelter_reduction)
	damage = maxi(1, ceili(damage * (1.0 - reduction)))
	entity.hp = maxi(0, entity.hp - damage)
	if entity.hp > 0:
		return
	if entity.enemy_definition != null:
		_enemy_abilities.note_death(entity)
	if entity.enemy_definition != null and entity.enemy_definition.jam_range > 0.0:
		_enemy_abilities.release_source(entity_id, _construction.all())
	# 敌人不持有格子或经济容量；只有注册表变化。建筑死亡由调用方的批量阶段结算。
	_remove_entity(entity_id)


## 覆盖该实体的活跃庇护源（若有）；首个命中即生效，重叠庇护绝不叠加。
func _sheltered_by(entity: MechEntityState, shelters: Array[MechEntityState]) -> MechEntityState:
	var best: MechEntityState
	for source: MechEntityState in shelters:
		if source.entity_id == entity.entity_id and not source.enemy_definition.shelter_self:
			continue
		if source.hp > 0 and entity.position.distance_to(source.position) <= source.enemy_definition.shelter_radius:
			if best == null or source.enemy_definition.shelter_reduction > best.enemy_definition.shelter_reduction:
				best = source
	return best


func preview_footprint(origin: Vector2i, footprint: Vector2i) -> Dictionary:
	var result: Dictionary = _grid.preview_footprint(origin, footprint)
	_mask_unknown_preview(result)
	return result


func _affects_coverage(rules: MechBuildingDefinition) -> bool:
	return rules != null and rules.coverage_radius > 0


func _affects_environment(rules: MechBuildingDefinition) -> bool:
	return rules != null and rules.environment_energy != "none"


func _cooling_aura_multiplier_at(origin: Vector2i, footprint: Vector2i) -> float:
	var target_center: Vector2 = Vector2(origin) + Vector2(footprint) * 0.5
	var best: float = 1.0
	for source: MechBuildingState in _construction.all():
		if source.definition.aura_kind != "cooling" or source.phase != MechBuildingState.Phase.OPERATING:
			continue
		if not _grid.footprint_covered(source.origin, source.definition.footprint):
			continue
		var source_center: Vector2 = Vector2(source.origin) + Vector2(source.definition.footprint) * 0.5
		if source_center.distance_to(target_center) <= source.definition.aura_radius:
			best = minf(best, source.definition.aura_multiplier)
	return best


func _prerequisite_error_for(rules: MechBuildingDefinition) -> String:
	if rules == null:
		return "建筑定义无效"
	if _tech_level() < rules.required_tech_level:
		return "需要科技等级 %d" % rules.required_tech_level
	if _mainbrain_level() < rules.required_mainbrain_level:
		return "需要主脑等级 %d" % rules.required_mainbrain_level
	return ""


func preview_build(id: StringName, origin: Vector2i) -> Dictionary:
	var rules: MechBuildingDefinition = _construction.definition(id)
	var cooling_multiplier: float = _cooling_aura_multiplier_at(origin, rules.footprint) if rules != null else 1.0
	var result: Dictionary = _construction.preview_placement(
		id, origin, _grid, _economy, _minerals, {}, {}, _environment, _vision, cooling_multiplier
	)
	var prerequisite: String = _prerequisite_error_for(_construction.definition(id))
	if not prerequisite.is_empty():
		result["ok"] = false
		result["reason"] = prerequisite
		for cell_info: Dictionary in result["cells"]:
			cell_info["ok"] = false
			cell_info["reason"] = prerequisite
	if id == &"tech_center" and not _alloy_processing.ever_produced_alloy:
		result["ok"] = false
		result["reason"] = "需先产出第一份合金"
		for cell_info: Dictionary in result["cells"]:
			cell_info["ok"] = false
			cell_info["reason"] = result["reason"]
	elif id == &"crystal_extractor" and _mainbrain_level() < 3:
		result["ok"] = false
		result["reason"] = "晶体采掘需要主脑 III"
		for cell_info: Dictionary in result["cells"]:
			cell_info["ok"] = false
			cell_info["reason"] = result["reason"]
	elif id == &"dispatch_center" and _tech_level() < 3:
		result["ok"] = false
		result["reason"] = "调度中心需要科技 III"
		for cell_info: Dictionary in result["cells"]:
			cell_info["ok"] = false
			cell_info["reason"] = result["reason"]
	_mask_unknown_preview(result)
	if session_ended():
		result["ok"] = false
		result["reason"] = "本局已结束"
	return result


func preview_wall_line(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = _construction.preview_wall_line(cells, _grid, _economy, _minerals)
	_mask_unknown_preview(result)
	if session_ended():
		result["ok"] = false
		result["reason"] = "本局已结束"
	return result


func _mask_unknown_preview(preview: Dictionary) -> void:
	for info: Dictionary in preview["cells"]:
		if _grid.contains(info["cell"]) and _vision.state_at(info["cell"]) == MechVisionSystem.State.UNEXPLORED:
			info["ok"] = false
			info["reason"] = "该区域尚未探索"
			if not preview.get("line", false):
				preview["ok"] = false
				preview["reason"] = "该区域尚未探索"
				preview["mineral_id"] = &""


func building_action_error(type: MechCommand.Type, entity_id: int) -> String:
	return validate_command(MechCommand.new(type, {"entity_id": entity_id})).get("reason", "")


## 敌方对建筑造成伤害的唯一权威入口；含交战、摧毁、感疫与废墟结算。
func damage_building(entity_id: int, amount: int) -> Dictionary:
	# 模拟侧的敌方攻击入口，不是玩家的伤害/调试命令。
	if session_ended():
		return _reject("本局已结束")
	var building: MechBuildingState = _construction.get_building(entity_id)
	if building == null or amount <= 0:
		return _reject("伤害目标或数值无效")
	if building.hp <= 0:
		return _reject("基座无法被攻击")
	building.hp = maxi(0, building.hp - amount)
	_repair_stations_dirty = true
	_dispatch_dirty = true
	# 任何命中都使建筑进入交战：敌人在 THREAT_RADIUS 内时维修持续暂停（building-economy.md §4.2）。
	building.threatened = true
	if building.hp == 0:
		# 感疫：带容量的资产被敌人摧毁时在残骸处生成建造者并发一次战斗脉冲（values.md §14）。
		# 拆除/取消路径绝不经过这里，受控拆除不产生感疫。
		var rules: MechBuildingDefinition = building.definition
		if not rules.is_core and rules.infectable:
			_infect_asset(rules.cost, Vector2(building.origin) + Vector2(rules.footprint) * 0.5)
		if rules.is_core:
			_remove_building(entity_id, MechResources.empty())
		elif building.phase == MechBuildingState.Phase.CONSTRUCTING:
			# 施工中损失不留基座：尚未投入任何资源，直接整体移除。
			_remove_building(entity_id, MechResources.empty())
		else:
			# 完工建筑留下占位基座（building-economy.md §4.1）：格子与矿点绑定保持持有，但基座绝不阻挡移动。
			_ruin_building(building)
	# 战斗阶段会连续结算多次命中；tick 外的直接调用方仍获得即时刷新，tick 内则批量结算一次。
	if not _in_tick:
		_sync_navigation()
		_sync_vision()
	state_changed.emit()
	return {"ok": true, "reason": ""}


func _ruin_building(building: MechBuildingState) -> void:
	_dispatch_buildings.erase(building.entity_id)
	_eject_all_garrison(building, true, true)
	building.contract_offer = {}
	building.contract_unit_id = &""
	building.contract_paid = {}
	building.contract_delivery_ticks = 0
	building.mark_ruined()
	# 被摧毁的工厂失去队列且不退款（building-economy.md §5）。
	_economy.credit(_production.remove_factory(building.entity_id, false))
	# 基座为放置与矿点绑定保留格子，但绝不阻挡移动（building-economy.md §4.1）。
	_grid.set_pass_through(building.entity_id, true)
	if _affects_coverage(building.definition):
		_coverage_dirty = true
	if _affects_environment(building.definition):
		_environment_dirty = true
		_environment_full_refresh = true
	_auras_dirty = true
	_dispatch_dirty = true
	_recompute_economy()


func _scan_combat_threat() -> void:
	# 受击建筑只有在脚印 THREAT_RADIUS 范围内无敌后才脱离交战状态（building-economy.md §4.2）；
	# 之后路过的敌人若未攻击，不会重新进入交战。
	var radius_sq: float = MechBuildingState.THREAT_RADIUS * MechBuildingState.THREAT_RADIUS
	for building: MechBuildingState in _construction.all():
		if not building.threatened or building.hp <= 0:
			continue
		var rect := Rect2(Vector2(building.origin), Vector2(building.definition.footprint))
		var engaged := false
		for entity: MechEntityState in _registry.all():
			if entity.enemy_definition == null or entity.hp <= 0:
				continue
			var clamped := Vector2(clampf(entity.position.x, rect.position.x, rect.end.x),
				clampf(entity.position.y, rect.position.y, rect.end.y))
			if entity.position.distance_squared_to(clamped) <= radius_sq:
				engaged = true
				break
		if not engaged:
			building.threatened = false


func _place(id: StringName, origin: Vector2i) -> Dictionary:
	var check: Dictionary = preview_build(id, origin)
	if not check["ok"]:
		return check
	var rules: MechBuildingDefinition = _construction.definition(id)
	var center: Vector2 = Vector2(origin) + Vector2(rules.footprint) * 0.5
	var entity_id: int = _registry.create(id, rules.display_name, center, 0.0, rules.footprint)
	var occupied: Dictionary = _grid.try_occupy(entity_id, origin, rules.footprint)
	if not occupied["ok"]:
		_registry.remove(entity_id)
		return occupied
	if not _minerals.bind(check["mineral_id"], entity_id):
		_grid.release(entity_id)
		_registry.remove(entity_id)
		return _reject("矿点已被预留或耗竭")
	if not _economy.try_spend(rules.cost):
		_grid.release(entity_id)
		_minerals.release(entity_id)
		_registry.remove(entity_id)
		return _reject("资源不足")
	var building: MechBuildingState = _construction.add(entity_id, id, origin, _tick_rate)
	building.mineral_id = check["mineral_id"]
	building.environment_power = int(check.get("environment_power", 0))
	if rules.trap_kind != "none" or rules.slow_fence_ratio < 1.0:
		_grid.set_pass_through(entity_id, true)
	if rules.is_gate:
		_grid.set_friendly_pass(entity_id, true)
	var energy_type := StringName(rules.environment_energy)
	if energy_type != &"none" and not _environment.reserve(
		entity_id, energy_type, origin, rules.footprint
	):
		# 预览本应拒绝；若预览与提交之间状态发生竞态，保持事务原子性。
		_construction.remove(entity_id)
		_grid.release(entity_id)
		_minerals.release(entity_id)
		_registry.remove(entity_id)
		_economy.credit(rules.cost)
		return _reject("同类环境电源采集区重叠")
	_production.register_factory(building)
	if _affects_coverage(rules):
		_coverage_dirty = true
	if _affects_environment(rules):
		_environment_dirty = true
	_auras_dirty = true
	_dispatch_dirty = true
	_recompute_economy()
	return {"ok": true, "reason": "", "entity_id": entity_id, "origin": origin, "cost": MechResources.copy(rules.cost)}


func _remove_building(entity_id: int, refund: Dictionary, refund_orders: bool = false) -> void:
	var cycle_refund := MechResources.empty()
	var building: MechBuildingState = _construction.get_building(entity_id)
	var removed_rules: MechBuildingDefinition = null
	if _dispatch_buildings.has(entity_id):
		var receipt: Dictionary = _dispatch_buildings[entity_id]
		var ratio: float = 0.0
		if building != null:
			ratio = 1.0 if building.phase == MechBuildingState.Phase.CONSTRUCTING else building.paid_refund_ratio
		var paid_refund: Dictionary = MechResources.scaled(receipt["cost"], ratio)
		for key: StringName in MechResources.KEYS:
			paid_refund[key] = mini(int(paid_refund.get(key, 0)), int(refund.get(key, 0)))
		_dispatch.refund_spent(int(receipt["region_id"]), paid_refund)
		_dispatch_buildings.erase(entity_id)
	if building != null:
		cycle_refund = building.cycle_refund()
		removed_rules = building.definition
		_eject_all_garrison(building, true)
		if not building.contract_paid.is_empty():
			cycle_refund = MechResources.add(cycle_refund, building.contract_paid)
			building.contract_paid = {}
	_grid.release(entity_id)
	_minerals.release(entity_id)
	_environment.release(entity_id)
	_construction.remove(entity_id)
	_registry.remove(entity_id)
	if _affects_coverage(removed_rules):
		_coverage_dirty = true
	if _affects_environment(removed_rules):
		_environment_dirty = true
		_environment_full_refresh = true
	_auras_dirty = true
	_dispatch_dirty = true
	_economy.credit(MechResources.add(MechResources.add(refund, cycle_refund), _production.remove_factory(entity_id, refund_orders)))
	if entity_id == _mainbrain_id:
		_grid.set_core_coverage(Vector2i.ZERO, Vector2i.ONE, -1)
		_outcome = &"defeat"
		_clock.set_paused(true)
		_registry.suspend_motion()
		print("[Billions Mech] session ended: defeat; tick=", _clock.snapshot()["tick"])
	_recompute_economy()


func _validate_building_action(command: MechCommand) -> Dictionary:
	if typeof(command.payload.get("entity_id")) != TYPE_INT:
		return _reject("建筑编号无效")
	var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
	if building == null:
		return _reject("建筑已不存在")
	match command.type:
		MechCommand.Type.CANCEL_CONSTRUCTION:
			if building.phase != MechBuildingState.Phase.CONSTRUCTING:
				return _reject("只有施工中的建筑可取消")
		MechCommand.Type.DEMOLISH:
			if building.definition.is_core:
				return _reject("主脑不可拆除")
			if building.upgrade_target != null:
				return _reject("升级中不可拆除")
			if building.phase != MechBuildingState.Phase.OPERATING and building.phase != MechBuildingState.Phase.RUINED:
				return _reject("只有完工建筑或基座可拆除")
		MechCommand.Type.CANCEL_DEMOLISH:
			if building.phase != MechBuildingState.Phase.DEMOLISHING:
				return _reject("建筑未在拆除")
		MechCommand.Type.TOGGLE_REPAIR:
			if building.phase != MechBuildingState.Phase.OPERATING:
				return _reject("施工或拆除期间不可维修")
			if not building.repairing and building.hp >= building.definition.max_hp:
				return _reject("建筑完好，无需维修")
		MechCommand.Type.REBUILD:
			if building.phase != MechBuildingState.Phase.RUINED:
				return _reject("仅摧毁基座可重建")
			# 基座保留土地/矿点所有权，但已释放运行预留；重建须按折扣价重新预留。
			if not _grid.footprint_covered(building.origin, building.definition.footprint):
				return _reject("超出供电覆盖")
			if building.definition.requires_water and not _has_water_edge(building.definition, building.origin):
				return _reject("水冷站需与水域正交相邻")
			var energy_type := StringName(building.definition.environment_energy)
			if energy_type != &"none":
				if not _environment.conflicts(
					energy_type, building.origin, building.definition.footprint, building.entity_id
				).is_empty():
					return _reject("同类环境电源采集区重叠")
				if _environment.score(
					energy_type, building.origin, building.definition.footprint, _grid, _vision,
					building.definition.environment_output_multiplier,
					building.definition.environment_output_cap
				) <= 0:
					return _reject("环境评分不足（需已探索有效地形）")
			var rebuild_error: String = _economy.reservation_error(
				building.definition, {}, building.rebuild_cost(),
				_cooling_aura_multiplier_at(building.origin, building.definition.footprint)
			)
			if not rebuild_error.is_empty():
				return _reject(rebuild_error)
	return {"ok": true, "reason": ""}


func _advance_upgrades() -> bool:
	var changed: bool = false
	for building: MechBuildingState in _construction.all():
		if building.upgrade_target == null or not building.operating():
			continue
		building.upgrade_elapsed = mini(building.upgrade_elapsed + 1, building.upgrade_total)
		if building.upgrade_elapsed < building.upgrade_total:
			continue
		var target: MechBuildingDefinition = building.upgrade_target
		# 冶炼站升级在当前燃烧周期边界结算；旧配方与发电保持到该周期结束。
		if target.alloy_recipe != null and building.processing_active:
			continue
		var old_definition: MechBuildingDefinition = building.definition
		var old_max_hp: int = building.definition.max_hp
		var lost_hp: int = maxi(0, old_max_hp - building.hp)
		building.paid_cost = MechResources.add(building.paid_cost, building.upgrade_paid)
		building.definition = target
		building.refresh_definition_ticks(_tick_rate)
		building.convert_repair_denominator(old_max_hp, target.max_hp)
		building.hp = clampi(target.max_hp - lost_hp, 1, target.max_hp)
		building.built_hp = building.hp
		building.upgrade_target = null
		building.upgrade_elapsed = 0
		building.upgrade_total = 0
		building.upgrade_paid = MechResources.empty()
		if _affects_coverage(old_definition) or _affects_coverage(target):
			_coverage_dirty = true
		if _affects_environment(old_definition) or _affects_environment(target):
			_environment_dirty = true
			_environment_full_refresh = true
		_auras_dirty = true
		_repair_stations_dirty = true
		_dispatch_dirty = true
		changed = true
	if changed:
		_recompute_economy()
		state_changed.emit()
	return changed


func _has_water_edge(rules: MechBuildingDefinition, origin: Vector2i) -> bool:
	var body := Rect2i(origin, rules.footprint)
	for y: int in range(origin.y, origin.y + rules.footprint.y):
		for x: int in range(origin.x, origin.x + rules.footprint.x):
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var cell: Vector2i = Vector2i(x, y) + offset
				if not body.has_point(cell) and _grid.is_water(cell):
					return true
	return false


func _advance_slow_fences() -> void:
	var fences: Dictionary[Vector2i, MechBuildingState] = {}
	for building: MechBuildingState in _construction.all():
		if building.definition.slow_fence_ratio < 1.0 and building.operating():
			for y: int in range(building.definition.footprint.y):
				for x: int in range(building.definition.footprint.x):
					fences[building.origin + Vector2i(x, y)] = building
	for enemy: MechEntityState in _registry.all():
		if enemy.team != 2 or enemy.hp <= 0:
			continue
		var cell: Vector2i = enemy.position.floor()
		var fence: MechBuildingState = fences.get(cell)
		if fence == null or not fence.operating():
			enemy.last_fence_cell = Vector2i(-999, -999)
			enemy.fence_slow_multiplier = 1.0
			continue
		if enemy.last_fence_cell != cell:
			enemy.last_fence_cell = cell
			fence.hp = maxi(0, fence.hp - 10)
			if fence.hp <= 0:
				_ruin_building(fence)
		enemy.fence_slow_multiplier = fence.definition.slow_fence_ratio if fence.operating() else 1.0


func _trigger_traps() -> bool:
	var triggered_traps: Array[MechBuildingState] = []
	for building: MechBuildingState in _construction.all():
		if building.definition.trap_kind == "none" or not building.operating():
			continue
		var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
		var enemies_hit: Array[MechEntityState] = []
		for entity: MechEntityState in _registry.all():
			if entity.team != 2 or entity.hp <= 0:
				continue
			if entity.position.distance_to(center) <= building.definition.trigger_radius:
				enemies_hit.append(entity)
		if enemies_hit.is_empty():
			continue
		var shelters: Array[MechEntityState] = _collect_shelter_sources()
		for enemy: MechEntityState in enemies_hit:
			if building.definition.trap_kind == "blast":
				_damage_enemy(enemy.entity_id, building.definition.trap_damage, shelters)
			elif building.definition.trap_kind == "emp":
				var ticks: int = maxi(1, ceili(building.definition.slow_seconds * _tick_rate))
				enemy.apply_slow(building.definition.slow_multiplier, ticks)
		triggered_traps.append(building)
	for building: MechBuildingState in triggered_traps:
		if _construction.get_building(building.entity_id) != null:
			_remove_building(building.entity_id, MechResources.empty())
	return not triggered_traps.is_empty()


func _tech_level() -> int:
	var result: int = 0
	for building: MechBuildingState in _construction.all():
		if building.operating():
			result = maxi(result, building.definition.tech_level)
	return result


func _mainbrain_level() -> int:
	var core: MechBuildingState = _construction.get_building(_mainbrain_id)
	return core.definition.level if core != null else 1


func _validate_upgrade_command(command: MechCommand) -> Dictionary:
	if typeof(command.payload.get("entity_id")) != TYPE_INT:
		return _reject("建筑编号无效")
	var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
	if building == null:
		return _reject("建筑已不存在")
	if building.phase != MechBuildingState.Phase.OPERATING:
		return _reject("只有完工建筑可升级")
	if building.upgrade_target != null:
		return _reject("该建筑已在升级")
	var target: MechBuildingDefinition = building.definition.upgrade_to
	if target == null:
		return _reject("该建筑没有可用升级")
	if target.footprint != building.definition.footprint:
		return _reject("升级目标占地不一致")
	var prerequisite: String = _prerequisite_error_for(target)
	if not prerequisite.is_empty():
		return _reject(prerequisite)
	if target.requires_water and not _has_water_edge(target, building.origin):
		return _reject("水冷站需与水域正交相邻")
	if building.definition.is_core:
		if building.definition.level == 1 and _tech_level() < 1:
			return _reject("主脑升级需要运行中的科技中心 I")
		if building.definition.level == 2 and _tech_level() < 2:
			return _reject("主脑 III 需要科技中心 II")
	elif building.definition.tech_level == 1:
		if _mainbrain_level() < 2:
			return _reject("科技中心 II 需要主脑 II")
	elif building.definition.tech_level == 2:
		if _mainbrain_level() < 3:
			return _reject("科技中心 III 需要主脑 III")
		if not _minerals.has_produced(&"crystals"):
			return _reject("科技中心 III 需要先产出晶体")
	elif target.level >= 3 and _tech_level() < 3:
		return _reject("三级升级需要科技中心 III")
	var error: String = _economy.upgrade_error(
		building.definition, target, building.definition.upgrade_cost,
		_cooling_aura_multiplier_at(building.origin, target.footprint)
	)
	if not error.is_empty():
		return _reject(error)
	return {"ok": true, "reason": "", "cost": MechResources.copy(building.definition.upgrade_cost)}


func _validate_cancel_upgrade(command: MechCommand) -> Dictionary:
	if typeof(command.payload.get("entity_id")) != TYPE_INT:
		return _reject("建筑编号无效")
	var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
	if building == null:
		return _reject("建筑已不存在")
	if building.upgrade_target == null:
		return _reject("该建筑没有进行中的升级")
	if building.definition.is_core:
		return _reject("主脑升级不可取消")
	return {"ok": true, "reason": ""}


func _repair_all_status() -> Dictionary:
	if session_ended():
		return {"ok": false, "reason": "本局已结束", "count": 0}
	var count: int = 0
	for building: MechBuildingState in _construction.all():
		# 任何仍在交战的存活建筑都会禁用按钮；基座（hp == 0）不会被攻击也不阻止。
		if building.hp > 0 and building.threatened:
			return {"ok": false, "reason": "有建筑交战中，周边 6 格内仍有敌军", "count": 0}
		if building.phase == MechBuildingState.Phase.OPERATING and building.hp < building.definition.max_hp:
			count += 1
	if count == 0:
		return {"ok": false, "reason": "没有受损的完工建筑", "count": 0}
	return {"ok": true, "reason": "", "count": count}


func _validate_move(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("entity_id")) != TYPE_INT or not _registry.can_move(payload.get("entity_id", 0)):
		return _reject("该实体不可移动")
	if typeof(payload.get("target")) != TYPE_VECTOR2:
		return _reject("目标坐标无效")
	var target: Vector2 = payload["target"]
	if not target.is_finite() or not _grid.point_inside(target):
		return _reject("超出地图边界")
	var entity_id: int = payload["entity_id"]
	if not _grid.is_walkable(Vector2i(_registry.position_of(entity_id).floor()), true, {}, true):
		return _reject("实体位于施工占地内，完工时将自动移出")
	var cell := Vector2i(target.floor())
	if not _grid.is_walkable(cell, true, {}, true):
		return _reject("目标被障碍或建筑阻挡")
	if not _grid.mobile_position_clear(target, {}, true):
		return _reject("目标过于贴近障碍，无法容纳单位")
	var path: PackedVector2Array = _navigation.find_path_to_point(_registry.position_of(entity_id), target)
	if path.is_empty():
		return _reject("目标无法到达")
	return {"ok": true, "reason": "", "path": path}


func _sync_navigation() -> void:
	if _navigation_revision == _grid.revision():
		return
	_navigation.rebuild(_grid)
	_navigation_revision = _grid.revision()
	_profile_counter(&"nav_rebuild")
	for unit: Dictionary in _registry.movable_snapshots():
		var entity_id: int = unit["id"]
		var position: Vector2 = unit["position"]
		if not _grid.is_walkable(Vector2i(position.floor()), true, {}, true):
			_registry.stop(entity_id)
			continue
		if not unit["has_order"]:
			continue
		# 只有新占用真正切断剩余路线时才重跑 A*：远处建墙不影响已排队的路径点，大多数单位保留原路径，避免每次建墙引发全场 A* 风暴。
		var path: PackedVector2Array = unit["path"]
		if _path_is_blocked(position, path):
			_profile_counter(&"nav_repath")
			_registry.set_move_path(
				entity_id, _navigation.find_path_to_point(position, unit["target"])
			)


func _path_is_blocked(position: Vector2, path: PackedVector2Array) -> bool:
	var previous: Vector2 = position
	for point: Vector2 in path:
		if not _grid.mobile_segment_clear(previous, point, {}, true):
			return true
		previous = point
	return false


func _sync_vision() -> void:
	_profile_counter(&"vision")
	_vision.update(_grid, _registry, _construction.all(), _settings.probe_sight_radius)
	if _vision.explored_revision() != _environment_explored_revision:
		_environment_explored_revision = _vision.explored_revision()
		_environment_pending_cells.append_array(_vision.consume_explored_changes())
		_environment_dirty = true
		_recompute_economy()


func _clear_building_footprint(building: MechBuildingState) -> bool:
	var area := Rect2i(building.origin, building.definition.footprint)
	var assignments: Dictionary[int, Vector2] = {}
	var taken: Dictionary = {}
	var displaced: Dictionary = {}
	# 完工时玩家单位与波次敌人都会被挤出。
	var movers: Array[MechEntityState] = []
	for entity: MechEntityState in _registry.all():
		if entity.hp > 0 and not entity.garrisoned and (entity.unit_definition != null or entity.enemy_definition != null):
			movers.append(entity)
	for mover: MechEntityState in movers:
		var cell := Vector2i(mover.position.floor())
		taken[cell] = true
		if area.has_point(cell):
			displaced[mover.entity_id] = true
	for mover: MechEntityState in movers:
		if not area.has_point(Vector2i(mover.position.floor())):
			continue
		var nearest := Vector2i(-1, -1)
		var best: float = INF
		for y: int in range(area.position.y - 1, area.end.y + 1):
			for x: int in range(area.position.x - 1, area.end.x + 1):
				var cell := Vector2i(x, y)
				var outside_x: bool = x < area.position.x or x >= area.end.x
				var outside_y: bool = y < area.position.y or y >= area.end.y
				if outside_x and outside_y:
					continue
				if area.has_point(cell) or not _grid.is_walkable(cell) or taken.has(cell):
					continue
				var candidate: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
				if not _registry.mobile_space_free(candidate, displaced):
					continue
				var distance: float = candidate.distance_squared_to(mover.position)
				if distance < best:
					best = distance
					nearest = cell
		if nearest.x < 0:
			return false
		assignments[mover.entity_id] = Vector2(nearest) + Vector2(0.5, 0.5)
		taken[nearest] = true
	for entity_id: int in assignments:
		_registry.teleport(entity_id, assignments[entity_id])
	return true


func _wall_connections(origin: Vector2i) -> int:
	var mask: int = 0
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
	for index: int in range(directions.size()):
		var adjacent: MechBuildingState = _construction.get_building(_grid.occupant_at(origin + directions[index]))
		if adjacent != null and adjacent.hp > 0 and adjacent.definition.building_id == &"armored_wall":
			mask |= 1 << index
	return mask


func _reset() -> void:
	_generation += 1
	_outcome = &"ongoing"
	_alert.clear()
	_alert_sequence = 0
	_tick_counter = 0
	_clock.reset()
	_registry.clear()
	_enemy_abilities = MechEnemyAbilities.new()
	_construction.clear()
	_production.clear()
	_grid.configure(_map_definition)
	_navigation.set_friendly_pass(true)
	_registry.set_friendly_pass(true)
	_coverage_dirty = true
	_auras_dirty = true
	_repair_stations_dirty = true
	_dispatch_dirty = true
	_environment.clear()
	_environment_dirty = true
	_environment_full_refresh = true
	_environment_pending_cells.clear()
	_environment_explored_revision = -1
	_alloy_processing.reset()
	_dispatch.reset()
	_dispatch_unit_orders.clear()
	_dispatch_buildings.clear()
	_garrison_pending.clear()
	_contract_rng.seed = _settings.session_seed
	_economy.reset(_starting_resources)
	_minerals.reset(_map_definition.minerals)
	var brain: MechBuildingDefinition = _construction.definition(&"mainbrain")
	var center: Vector2 = Vector2(_map_definition.mainbrain_origin) + Vector2(brain.footprint) * 0.5
	_mainbrain_id = _registry.create(&"mainbrain", brain.display_name, center, 0.0, brain.footprint)
	_grid.try_occupy(_mainbrain_id, _map_definition.mainbrain_origin, brain.footprint)
	_construction.add(_mainbrain_id, &"mainbrain", _map_definition.mainbrain_origin, _tick_rate, true)
	for origin: Vector2i in _settings.starting_buildings:
		var id: StringName = _settings.starting_buildings[origin]
		var rules: MechBuildingDefinition = _construction.definition(id)
		var initial_center: Vector2 = Vector2(origin) + Vector2(rules.footprint) * 0.5
		var entity_id: int = _registry.create(id, rules.display_name, initial_center, 0.0, rules.footprint)
		_grid.try_occupy(entity_id, origin, rules.footprint)
		var starting_building: MechBuildingState = _construction.add(entity_id, id, origin, _tick_rate, true)
		_production.register_factory(starting_building)
		var energy_type := StringName(rules.environment_energy)
		if energy_type != &"none":
			_environment.reserve(entity_id, energy_type, origin, rules.footprint)
			starting_building.environment_power = 0
	_probe_id = 0
	if _settings.diagnostic_probe_enabled:
		_probe_id = _registry.create(&"probe", "验证实体", Vector2(_map_definition.probe_cell) + Vector2(0.5, 0.5), _probe_speed)
	for cell: Vector2i in _settings.starting_unit_cells:
		_units.create(_registry, _unit_definitions[_settings.starting_unit_id], cell)
	for cell: Vector2i in _settings.practice_target_cells:
		var id: int = _registry.create(&"practice_target", "训练靶", Vector2(cell) + Vector2(0.5, 0.5))
		var target: MechEntityState = _registry.get_entity(id)
		target.team = 2
		target.hp = 200
		target.max_hp = 200
		_grid.try_occupy(id, cell, Vector2i.ONE)
	# 环境计分前先重置视野，避免开局视野源读到上一局的探索记忆。
	_vision.reset(_grid)
	_recompute_economy()
	_navigation_revision = -1
	_sync_navigation()
	# 指向固定主脑格的加权行军场；建筑变化时重建。
	_enemies.reset(_grid, _map_definition.mainbrain_origin + (brain.footprint - Vector2i.ONE) / 2, _construction.all())
	_waves.reset(_grid, _map_definition, _settings.threat_enabled, _tick_rate)
	_threat.reset(_grid, _map_definition, _settings.threat_enabled, _tick_rate)
	_sync_vision()
	if profiling_enabled:
		var economy_state: Dictionary = _economy.snapshot()
		var player_units: int = 0
		for entity: MechEntityState in _registry.all():
			if entity.unit_definition != null:
				player_units += 1
		print("[p2d] player_units=%d capacity_used=%d capacity_supply=%d power=%d cooling=%.1f wave=%s remaining=%.1f" % [
			player_units, _units.capacity_used(_registry), int(economy_state["capacity_supply"]),
			int(economy_state["power_supply"]), float(economy_state["cooling_supply"]) / 10.0,
			String(_waves.state()["phase"]), float(_waves.state()["seconds_remaining"])])
	print("[Billions Mech] playable cells=", _grid.playable_cell_count())


func _settings_error(settings: MechFoundationSettings) -> String:
	if settings == null or settings.map_definition == null or settings.unit_definitions.is_empty():
		return "缺少场景、地图或单位定义"
	var error: String = settings.map_definition.validation_error()
	if not error.is_empty():
		return error
	var units: Dictionary[StringName, MechUnitDefinition] = {}
	for rules: MechUnitDefinition in settings.unit_definitions:
		if rules == null:
			return "空单位定义"
		error = rules.validation_error()
		if not error.is_empty():
			return error
		if units.has(rules.unit_id):
			return "重复单位编号"
		units[rules.unit_id] = rules
	if not units.has(settings.starting_unit_id):
		return "初始单位类型未配置"
	if not MechResources.valid(settings.starting_resources):
		return "开局资源无效"
	if settings.simulation_hz < 10 or settings.simulation_hz > 120 or not is_finite(settings.probe_speed) or settings.probe_speed <= 0.0:
		return "模拟频率或验证实体速度无效"
	if not is_finite(settings.probe_sight_radius) or settings.probe_sight_radius <= 0.0 or settings.probe_sight_radius > 64.0:
		return "验证实体视野半径无效"
	if settings.ordinary_per_elite < 1 or settings.max_elite_types < 1 or settings.max_elite_types > 3 or settings.max_jammed_towers < 2 or settings.max_jammed_towers > 3:
		return "精英配额或干扰上限无效"
	var construction := MechConstructionSystem.new()
	error = construction.configure(settings.building_definitions)
	if not error.is_empty():
		return error
	var grid := MechGridState.new()
	grid.configure(settings.map_definition)
	if not grid.is_walkable(settings.map_definition.main_gate) or not grid.is_walkable(settings.map_definition.flank):
		return "地图入口标记必须可通行"
	if settings.threat_enabled:
		var has_spawn_edge: bool = false
		for cell: Vector2i in grid.boundary_cells():
			if grid.is_walkable(cell):
				has_spawn_edge = true
				break
		if not has_spawn_edge:
			return "地图边界没有可用的机潮出生格"
	var brain: MechBuildingDefinition = construction.definition(&"mainbrain")
	if brain.footprint != settings.map_definition.mainbrain_footprint:
		return "地图与主脑占地不一致"
	if not grid.try_occupy(1, settings.map_definition.mainbrain_origin, brain.footprint)["ok"]:
		return "主脑位置无效"
	grid.set_core_coverage(settings.map_definition.mainbrain_origin, brain.footprint, brain.coverage_radius)
	var minerals := MechMineralSystem.new()
	minerals.reset(settings.map_definition.minerals)
	var next_id: int = 2
	for origin: Vector2i in settings.starting_buildings:
		var rules: MechBuildingDefinition = construction.definition(settings.starting_buildings[origin])
		if rules == null or rules.is_core or rules.mined_resource != &"":
			return "场景初始建筑定义无效"
		if not grid.footprint_covered(origin, rules.footprint) or not minerals.placement(rules, origin)["ok"]:
			return "初始建筑超出覆盖或占用矿点"
		if not grid.try_occupy(next_id, origin, rules.footprint)["ok"]:
			return "初始建筑重叠或地形无效"
		next_id += 1
	for rules: MechBuildingDefinition in settings.building_definitions:
		var products: Dictionary = {}
		for product: StringName in rules.produced_units:
			if not units.has(product) or products.has(product):
				return "工厂生产类型未配置或重复"
			products[product] = true
	var positions: Dictionary = {}
	var movable: Array[Vector2i] = settings.starting_unit_cells.duplicate()
	movable.append(settings.map_definition.probe_cell)
	for cell: Vector2i in movable:
		if not grid.is_walkable(cell) or positions.has(cell):
			return "初始单位位置重叠或不可通行"
		positions[cell] = true
	for cell: Vector2i in settings.practice_target_cells:
		if positions.has(cell) or not minerals.at(cell).is_empty() or not grid.try_occupy(next_id, cell, Vector2i.ONE)["ok"]:
			return "训练靶位置无效"
		next_id += 1
	return ""


func _configuration_error(reason: String) -> bool:
	push_error(reason)
	return false


func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _on_production_finished(ticket: int, refund: Dictionary) -> void:
	if not _dispatch_unit_orders.has(ticket):
		return
	_dispatch.refund_spent(_dispatch_unit_orders[ticket], refund)
	_dispatch_unit_orders.erase(ticket)
	_dispatch_dirty = true


func _repair_authorized(building: MechBuildingState, due: Dictionary) -> bool:
	if building.repair_auto_source >= 0:
		return true
	return _dispatch_center_operating() and _dispatch.can_consume(
		-building.repair_auto_source, "repair:%d" % building.entity_id, due)


func _repair_paid(building: MechBuildingState, due: Dictionary) -> void:
	if building.repair_auto_source < 0:
		_dispatch.consume(-building.repair_auto_source, "repair:%d" % building.entity_id, due)


func _take_manual_repair(building: MechBuildingState) -> void:
	if building.repair_auto_source < 0:
		_dispatch.release(-building.repair_auto_source, "repair:%d" % building.entity_id)
	building.repair_auto_source = 0
	building.repair_rate_override = 0.0
	_repair_stations_dirty = true


func _final_phase(wave_state: Dictionary) -> String:
	if not wave_state.get("final_requested", false):
		return "none"
	if _outcome == &"victory":
		return "complete"
	if _outcome == &"defeat":
		return "failed"
	return String(wave_state.get("final_phase", "requested"))
