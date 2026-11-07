class_name MechSimCore
extends RefCounted
## Authoritative session. Commands commit all state before notifying views.

signal state_changed

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
var _towers := MechTowerSystem.new()
var _waves := MechWaveDirector.new()
var _threat := MechThreatSystem.new()
var _vision := MechVisionSystem.new()
var _enemy_defs: Dictionary = {}
var _tick_counter: int = 0

## Marching player units emit weak movement noise every two seconds (staggered).
const MOVEMENT_NOISE_SECONDS: float = 2.0
## Combat-state rescan interval: attacked buildings leave combat once no
## enemy remains within MechBuildingState.THREAT_RADIUS (twice per second).
const COMBAT_SCAN_TICKS: int = 15
var _settings: MechFoundationSettings
var _unit_definition: MechUnitDefinition
var _map_definition: MechMapDefinition
var _probe_speed: float = 2.5
var _probe_id: int = 0
var _mainbrain_id: int = 0
var _generation: int = 0
var _tick_rate: int = 30
var _starting_resources := Vector4i.ZERO
var _navigation_revision: int = -1
var _outcome: StringName = &"ongoing"
var _alert: Dictionary = {}
var _alert_sequence: int = 0


func _init() -> void:
	_registry.movement_finished.connect(_on_movement_finished)


func shutdown() -> void:
	_registry.clear()


func _on_movement_finished() -> void:
	_sync_vision()
	state_changed.emit()


func session_ended() -> bool:
	return _outcome != &"ongoing"


func is_paused() -> bool:
	return _clock.is_paused()


func scenario_name() -> String:
	return _settings.scenario_name


func tick_rate() -> int:
	return _tick_rate


func configure(settings: MechFoundationSettings) -> bool:
	var settings_error: String = _settings_error(settings)
	if not settings_error.is_empty():
		return _configuration_error(settings_error)
	_settings = settings
	_unit_definition = settings.unit_definition
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
	# Combat noise flows to the threat system from every firing side.
	_enemies.configure_noise(_threat.note_combat)
	_units.combat_noise = _threat.note_combat
	_towers.combat_noise = _threat.note_combat
	_probe_speed = maxf(0.1, settings.probe_speed)
	_tick_rate = maxi(1, settings.simulation_hz)
	_starting_resources = settings.starting_resources
	_clock.configure(_tick_rate)
	_reset()
	return true


func execute_command(command: MechCommand) -> Dictionary:
	var result: Dictionary = validate_command(command)
	if not result["ok"]:
		return result
	# Commands invalidate any native avoidance result submitted before the change.
	_registry.cancel_pending_motion()
	match command.type:
		MechCommand.Type.SET_PAUSED:
			_clock.set_paused(command.payload["paused"])
			if command.payload["paused"]:
				_registry.suspend_motion()
		MechCommand.Type.MOVE_ENTITY:
			var mover: MechEntityState = _registry.get_entity(command.payload["entity_id"])
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
			if not _economy.try_spend(_unit_definition.cost):
				return _reject("资源不足，生产未下单")
			var ticket: int = _production.enqueue(command.payload["factory_id"], _unit_definition, _tick_rate)
			_recompute_economy()
			result = {"ok": true, "reason": "", "ticket": ticket}
		MechCommand.Type.CANCEL_PRODUCTION:
			var refund: Vector4i = _production.cancel(command.payload["factory_id"], command.payload["ticket"])
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
			var spent := Vector4i.ZERO
			var noise_origin := Vector2i.ZERO
			for cell: Vector2i in result["origins"]:
				var placement: Dictionary = _place(&"armored_wall", cell)
				if placement["ok"]:
					if placed == 0:
						noise_origin = cell
					placed += 1
					spent += placement["cost"]
			if placed > 0:
				_threat.note_construction(Vector2(noise_origin) + Vector2(0.5, 0.5))
			result = {"ok": placed > 0, "reason": "" if placed > 0 else "墙线没有可下单的格子",
				"placed": placed, "skipped": result["origins"].size() - placed, "cost": spent}
		MechCommand.Type.CANCEL_CONSTRUCTION:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var refund: Vector4i = building.paid_cost
			_remove_building(building.entity_id, refund)
			result = {"ok": true, "reason": "", "refund": refund}
		MechCommand.Type.DEMOLISH:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var clearing: bool = building.phase == MechBuildingState.Phase.RUINED
			if clearing:
				# Clearing a base never refunds (values.md §7); paid_cost zero makes
				# the demolition-completion refund path come out empty.
				building.paid_cost = Vector4i.ZERO
			building.phase = MechBuildingState.Phase.DEMOLISHING
			building.elapsed_demolition_ticks = 0
			building.repairing = false
			building.repair_remainder = 0
			_threat.note_construction(Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5)
			_recompute_economy()
			result["clearing"] = clearing
			result["refund"] = building.refund()
		MechCommand.Type.CANCEL_DEMOLISH:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var was_clearing: bool = building.hp <= 0
			building.phase = MechBuildingState.Phase.RUINED if was_clearing else MechBuildingState.Phase.OPERATING
			building.elapsed_demolition_ticks = 0
			_recompute_economy()
			result["was_clearing"] = was_clearing
		MechCommand.Type.TOGGLE_REPAIR:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			building.repairing = not building.repairing
			building.repair_remainder = 0
			building.repair_waiting_for_funds = _economy.coins() == 0
		MechCommand.Type.REBUILD:
			var building: MechBuildingState = _construction.get_building(command.payload["entity_id"])
			var cost: Vector4i = building.rebuild_cost()
			if not _economy.try_spend(cost):
				return _reject("资源不足，重建未下单")
			building.paid_cost = cost
			building.phase = MechBuildingState.Phase.CONSTRUCTING
			building.elapsed_build_ticks = 0
			building.elapsed_demolition_ticks = 0
			building.hp = 1
			building.built_hp = 1
			building.waiting_for_clearance = false
			building.reset_repair_state()
			# A rebuild is fresh construction: blocking resumes from the order on.
			_grid.set_pass_through(building.entity_id, false)
			_production.register_factory(building)
			_threat.note_construction(Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5)
			_recompute_economy()
			result = {"ok": true, "reason": "", "entity_id": building.entity_id, "cost": cost}
		MechCommand.Type.REPAIR_ALL:
			var count: int = 0
			for target: MechBuildingState in _construction.all():
				if target.phase == MechBuildingState.Phase.OPERATING and target.hp < target.definition.max_hp:
					target.repairing = true
					target.repair_remainder = 0
					count += 1
			result = {"ok": true, "reason": "", "count": count}
	_sync_navigation()
	_sync_vision()
	state_changed.emit()
	# Internal pathfinding data never needs to leave the command executor.
	result.erase("path")
	result.erase("origins")
	return result


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
		MechCommand.Type.REPAIR_ALL:
			var repair_all: Dictionary = _repair_all_status()
			if not repair_all["ok"]:
				return _reject(repair_all["reason"])
		MechCommand.Type.RESET_SESSION:
			pass
		_:
			return _reject("未知命令")
	return {"ok": true, "reason": ""}


func advance_one_tick() -> void:
	if session_ended() or not _clock.advance():
		return
	# Income precedes completions: newly finished nodes start accruing next tick.
	_economy.advance_income(_construction.all(), _tick_rate)
	_minerals.advance(_construction.all(), _economy, _tick_rate)
	var changes: Dictionary = _construction.advance(_clear_building_footprint)
	for entity_id: int in changes["demolished"]:
		var building: MechBuildingState = _construction.get_building(entity_id)
		_remove_building(entity_id, building.refund(), true)
	if not changes["completed"].is_empty():
		_recompute_economy()
	if _tick_counter % COMBAT_SCAN_TICKS == 0:
		_scan_combat_threat()
	_economy.advance_repairs(_construction.all(), _tick_rate)
	_sync_navigation()
	if _production.advance(_construction, _spawn_unit):
		_recompute_economy()
	_release_enemies()
	_sync_vision()
	# Noise emitted last tick reaches wanderers this tick (combat during the
	# units/enemies passes below lands next tick).
	var noises: Array[Dictionary] = _threat.noises()
	var dead: Array[int] = _units.advance(_registry, _grid, _navigation, _tick_rate, _vision)
	for id: int in dead:
		_remove_entity(id)
	if not dead.is_empty():
		_recompute_economy()
		_sync_navigation()
	var enemy_result: Dictionary = _enemies.advance(_registry, _grid, _navigation, _construction.all(), _tick_rate, noises, _vision)
	for hit: Dictionary in enemy_result["building_hits"]:
		damage_building(hit["id"], hit["damage"])
	for id: int in enemy_result["dead_units"]:
		# Units destroyed by enemies feed infection at the wreck (values.md §14).
		_infect_asset(_unit_definition.cost, _registry.position_of(id))
		_remove_entity(id)
	if not enemy_result["dead_units"].is_empty():
		_recompute_economy()
		_sync_navigation()
	# Finish removal bookkeeping for this combat pass, but never fire towers or
	# submit a new native movement batch after the core has fallen.
	if session_ended():
		_sync_vision()
		state_changed.emit()
		return
	# Towers fire after enemy movement; hits return as results and share the
	# unit-kill removal bookkeeping (grid release, economy, navigation).
	_sync_vision()
	var tower_hits: Array[Dictionary] = _towers.advance(_registry, _construction.all(), _tick_rate, _grid, _vision)
	var tower_dead: Array[int] = []
	for hit: Dictionary in tower_hits:
		var target: MechEntityState = _registry.get_entity(hit["id"])
		if target == null or target.hp <= 0:
			continue
		target.hp = maxi(0, target.hp - hit["damage"])
		if target.hp == 0:
			tower_dead.append(target.entity_id)
	for id: int in tower_dead:
		_remove_entity(id)
	if not tower_dead.is_empty():
		_recompute_economy()
		_sync_navigation()
	_registry.step(_clock.step_seconds(), _grid)
	# Marching units hum: the expansion itself attracts wanderers (values.md §13).
	_tick_counter += 1
	var movement_noise_ticks: int = maxi(1, ceili(MOVEMENT_NOISE_SECONDS * _tick_rate))
	for entity: MechEntityState in _registry.all():
		if entity.team == 1 and entity.unit_definition != null and entity.has_move_order and (_tick_counter + entity.entity_id) % movement_noise_ticks == 0:
			_threat.note_movement(entity.position)


func snapshot() -> Dictionary:
	var entities: Array[Dictionary] = []
	for current: MechEntityState in _registry.all():
		if current.team == 2 and not _vision.is_visible(current.position):
			continue
		entities.append(current.snapshot())
	for entity: Dictionary in entities:
		var building: MechBuildingState = _construction.get_building(entity["id"])
		if building != null:
			entity.merge(_building_snapshot(building), true)
			if building.definition.building_id == &"armored_wall":
				entity["connections"] = _wall_connections(building.origin)
		if entity.get("shot_ticks", 0) > 0 and not _vision.is_visible(entity["shot_target"]):
			entity["shot_ticks"] = 0
	var economy: Dictionary = _economy.snapshot()
	var production: Vector4i = _minerals.production_rate(_construction.all())
	production.x = economy["income_rate"]
	economy["production_per_minute"] = production
	economy["unit_capacity"] = _units.capacity_used(_registry)
	economy["queued_capacity"] = _production.reserved_capacity()
	var minerals: Array[Dictionary] = []
	for mineral: Dictionary in _minerals.snapshots():
		if _vision.state_at(mineral["cell"]) != MechVisionSystem.State.UNEXPLORED:
			mineral["visible"] = _vision.state_at(mineral["cell"]) == MechVisionSystem.State.VISIBLE
			minerals.append(mineral)
	return {"clock": _clock.snapshot(), "entities": entities, "economy": economy, "minerals": minerals,
		"vision": _vision.snapshot(),
		"scenario": _settings.scenario_name, "unit_catalog": _unit_definition.snapshot(),
		"catalog": _construction.catalog(_economy), "probe_id": _probe_id,
		"mainbrain_id": _mainbrain_id, "generation": _generation,
		"session": {"outcome": _outcome, "ended": session_ended(),
			"reason": "主脑已被摧毁" if _outcome == &"defeat" else ""},
		"threat": _waves.state(),
		"alert": _alert.duplicate(),
		"map_revision": _grid.revision(), "map_name": _map_definition.display_name}


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
	var mineral: Dictionary = _minerals.deposit(building.mineral_id)
	result["mineral"] = mineral
	result["production"] = _production.snapshot(building.entity_id)
	if building.definition.produced_unit != &"":
		result["production_error"] = "本局已结束" if session_ended() else _production.order_error(building, _unit_definition, _economy)
	if not mineral.is_empty() and mineral["remaining"] == 0 and building.operating():
		result["status"] = "矿点已耗竭 · 停产"
	return result


func _recompute_economy() -> void:
	_economy.recompute(_construction.all(), _grid, _units.capacity_used(_registry), _production.reserved_capacity())


func _spawn_unit(building: MechBuildingState, rally: Vector2i) -> bool:
	return _units.spawn(building, rally, _unit_definition, _registry, _grid, _navigation)


## Wave releases, wanderer backfill and infection arrive as spawn requests;
## creation stays in the enemy system so definitions, teams and march orders
## live in one place.
func _release_enemies() -> void:
	var requests: Array[Dictionary] = []
	requests.append_array(_waves.advance(_grid, _construction.all()))
	requests.append_array(_threat.advance(_construction.all()))
	_release_spawns(requests)


func _release_spawns(requests: Array[Dictionary]) -> void:
	if session_ended():
		return
	for request: Dictionary in requests:
		var rules: MechEnemyDefinition = _enemy_defs.get(request["enemy_id"])
		if rules != null:
			_enemies.create(_registry, rules, request["position"])


func _infect_asset(cost: Vector4i, position: Vector2) -> void:
	var requests: Array[Dictionary] = _threat.infect(cost, position)
	if requests.is_empty():
		return
	_release_spawns(requests)
	# Terrain blind spots must not silently hide an infection event. Report a
	# qualitative direction without exposing enemy counts or hidden positions.
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
	if building == null or building.definition.produced_unit == &"":
		return _reject("请选择有效组装厂")
	if command.type == MechCommand.Type.QUEUE_UNIT:
		var error: String = _production.order_error(building, _unit_definition, _economy)
		if not error.is_empty():
			return _reject(error)
	elif command.type == MechCommand.Type.CANCEL_PRODUCTION:
		if typeof(command.payload.get("ticket")) != TYPE_INT or not _production.has_ticket(building.entity_id, command.payload["ticket"]):
			return _reject("生产订单已不存在")
	else:
		if building.phase == MechBuildingState.Phase.DEMOLISHING:
			return _reject("拆除期间不可修改集结点")
		if typeof(command.payload.get("cell")) != TYPE_VECTOR2I or not _grid.is_walkable(command.payload["cell"]):
			return _reject("集结点须为地图内可通行格")
	return {"ok": true, "reason": ""}


func _remove_entity(id: int) -> void:
	var entity: MechEntityState = _registry.get_entity(id)
	if entity == null:
		return
	if _construction.get_building(id) != null:
		_remove_building(id, Vector4i.ZERO)
		return
	if _grid.occupant_at(Vector2i(entity.position.floor())) == id:
		_grid.release(id)
	_registry.remove(id)


func preview_footprint(origin: Vector2i, footprint: Vector2i) -> Dictionary:
	var result: Dictionary = _grid.preview_footprint(origin, footprint)
	_mask_unknown_preview(result)
	return result


func preview_build(id: StringName, origin: Vector2i) -> Dictionary:
	var result: Dictionary = _construction.preview_placement(id, origin, _grid, _economy, _minerals)
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


func damage_building(entity_id: int, amount: int) -> Dictionary:
	# Simulation-side hook for enemy attacks, not a player damage/debug command.
	if session_ended():
		return _reject("本局已结束")
	var building: MechBuildingState = _construction.get_building(entity_id)
	if building == null or amount <= 0:
		return _reject("伤害目标或数值无效")
	if building.phase == MechBuildingState.Phase.RUINED:
		return _reject("基座无法被攻击")
	building.hp = maxi(0, building.hp - amount)
	# Any hit puts the building into combat: repairs stay suspended while
	# enemies remain within THREAT_RADIUS (building-economy.md §4.2).
	building.threatened = true
	if building.hp == 0:
		# Infection: capacity-bearing assets destroyed by enemies spawn builders at
		# the wreck plus a combat pulse (values.md §14). Demolish/cancel paths never
		# pass through here, so controlled teardown stays infection-free.
		var rules: MechBuildingDefinition = building.definition
		if not rules.is_core and rules.capacity_cost > 0:
			_infect_asset(rules.cost, Vector2(building.origin) + Vector2(rules.footprint) * 0.5)
		if rules.is_core:
			_remove_building(entity_id, Vector4i.ZERO)
		elif building.phase == MechBuildingState.Phase.CONSTRUCTING:
			# Under-construction losses leave no base: nothing has sunk
			# into the site yet, so it is removed outright.
			_remove_building(entity_id, Vector4i.ZERO)
		else:
			# Finished buildings leave an occupying base (building-economy.md
			# §4.1): cells and the mineral binding stay held, but the base
			# itself never blocks movement.
			_ruin_building(building)
		_sync_navigation()
	_sync_vision()
	state_changed.emit()
	return {"ok": true, "reason": ""}


func _ruin_building(building: MechBuildingState) -> void:
	building.mark_ruined()
	# Destroyed factories lose their queue without refunds (building-economy.md §5).
	_economy.credit(_production.remove_factory(building.entity_id, false))
	# The base keeps its cells for placement and mineral binding but never
	# blocks movement (building-economy.md §4.1).
	_grid.set_pass_through(building.entity_id, true)
	_recompute_economy()


func _scan_combat_threat() -> void:
	# Attacked buildings leave the combat state only once no enemy remains
	# within THREAT_RADIUS of their footprint (building-economy.md §4.2).
	# Enemies passing by later without attacking do not re-enter combat.
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
	_production.register_factory(building)
	_recompute_economy()
	return {"ok": true, "reason": "", "entity_id": entity_id, "origin": origin, "cost": rules.cost}


func _remove_building(entity_id: int, refund: Vector4i, refund_orders: bool = false) -> void:
	_grid.release(entity_id)
	_minerals.release(entity_id)
	_construction.remove(entity_id)
	_registry.remove(entity_id)
	_economy.credit(refund + _production.remove_factory(entity_id, refund_orders))
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
			# Reservations stay held by the base itself; only funds gate a rebuild.
			var funds_error: String = _economy.spend_error(building.rebuild_cost())
			if not funds_error.is_empty():
				return _reject(funds_error)
	return {"ok": true, "reason": ""}


func _repair_all_status() -> Dictionary:
	if session_ended():
		return {"ok": false, "reason": "本局已结束", "count": 0}
	var count: int = 0
	for building: MechBuildingState in _construction.all():
		# Any live building still in combat blocks the button; bases (hp == 0)
		# are never attacked and never block.
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
	if not _grid.is_walkable(Vector2i(_registry.position_of(entity_id).floor())):
		return _reject("实体位于施工占地内，完工时将自动移出")
	var cell := Vector2i(target.floor())
	if not _grid.is_walkable(cell):
		return _reject("目标被障碍或建筑阻挡")
	if not _grid.mobile_position_clear(target):
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
	for unit: Dictionary in _registry.movable_snapshots():
		var entity_id: int = unit["id"]
		if not _grid.is_walkable(Vector2i(unit["position"].floor())):
			_registry.stop(entity_id)
		elif unit["has_order"]:
			_registry.set_move_path(entity_id, _navigation.find_path_to_point(unit["position"], unit["target"]))


func _sync_vision() -> void:
	_vision.update(_grid, _registry, _construction.all(), _settings.probe_sight_radius)


func _clear_building_footprint(building: MechBuildingState) -> bool:
	var area := Rect2i(building.origin, building.definition.footprint)
	var assignments: Dictionary[int, Vector2] = {}
	var taken: Dictionary = {}
	var displaced: Dictionary = {}
	# Player units and wave enemies are both displaced on completion.
	var movers: Array[MechEntityState] = []
	for entity: MechEntityState in _registry.all():
		if entity.hp > 0 and (entity.unit_definition != null or entity.enemy_definition != null):
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
	_construction.clear()
	_production.clear()
	_grid.configure(_map_definition)
	_economy.reset(_starting_resources)
	_minerals.reset(_map_definition.minerals)
	var brain: MechBuildingDefinition = _construction.definition(&"mainbrain")
	var center: Vector2 = Vector2(_map_definition.mainbrain_origin) + Vector2(brain.footprint) * 0.5
	_mainbrain_id = _registry.create(&"mainbrain", brain.display_name, center, 0.0, brain.footprint)
	_grid.try_occupy(_mainbrain_id, _map_definition.mainbrain_origin, brain.footprint)
	_construction.add(_mainbrain_id, &"mainbrain", _map_definition.mainbrain_origin, _tick_rate, true)
	_grid.set_core_coverage(_map_definition.mainbrain_origin, brain.footprint, brain.coverage_radius)
	for origin: Vector2i in _settings.starting_buildings:
		var id: StringName = _settings.starting_buildings[origin]
		var rules: MechBuildingDefinition = _construction.definition(id)
		var initial_center: Vector2 = Vector2(origin) + Vector2(rules.footprint) * 0.5
		var entity_id: int = _registry.create(id, rules.display_name, initial_center, 0.0, rules.footprint)
		_grid.try_occupy(entity_id, origin, rules.footprint)
		_production.register_factory(_construction.add(entity_id, id, origin, _tick_rate, true))
	_probe_id = _registry.create(&"probe", "验证实体", Vector2(_map_definition.probe_cell) + Vector2(0.5, 0.5), _probe_speed)
	for cell: Vector2i in _settings.starting_unit_cells:
		_units.create(_registry, _unit_definition, cell)
	for cell: Vector2i in _settings.practice_target_cells:
		var id: int = _registry.create(&"practice_target", "训练靶", Vector2(cell) + Vector2(0.5, 0.5))
		var target: MechEntityState = _registry.get_entity(id)
		target.team = 2
		target.hp = 200
		target.max_hp = 200
		_grid.try_occupy(id, cell, Vector2i.ONE)
	_recompute_economy()
	_navigation_revision = -1
	_sync_navigation()
	# Weighted march field toward the fixed mainbrain cell; rebuilt on building changes.
	_enemies.reset(_grid, _map_definition.mainbrain_origin + (brain.footprint - Vector2i.ONE) / 2, _construction.all())
	_waves.reset(_grid, _map_definition, _settings.threat_enabled, _tick_rate)
	_threat.reset(_grid, _map_definition, _settings.threat_enabled, _tick_rate)
	_vision.reset(_grid)
	_sync_vision()
	print("[Billions Mech] playable cells=", _grid.playable_cell_count())


func _settings_error(settings: MechFoundationSettings) -> String:
	if settings == null or settings.map_definition == null or settings.unit_definition == null:
		return "缺少场景、地图或单位定义"
	var error: String = settings.map_definition.validation_error()
	if not error.is_empty():
		return error
	error = settings.unit_definition.validation_error()
	if not error.is_empty():
		return error
	if not MechResources.valid(settings.starting_resources):
		return "开局资源无效"
	if settings.simulation_hz < 10 or settings.simulation_hz > 120 or not is_finite(settings.probe_speed) or settings.probe_speed <= 0.0:
		return "模拟频率或验证实体速度无效"
	if not is_finite(settings.probe_sight_radius) or settings.probe_sight_radius <= 0.0 or settings.probe_sight_radius > 64.0:
		return "验证实体视野半径无效"
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
		if rules.produced_unit != &"" and rules.produced_unit != settings.unit_definition.unit_id:
			return "工厂与单位类型不一致"
		if not grid.footprint_covered(origin, rules.footprint) or not minerals.placement(rules, origin)["ok"]:
			return "初始建筑超出覆盖或占用矿点"
		if not grid.try_occupy(next_id, origin, rules.footprint)["ok"]:
			return "初始建筑重叠或地形无效"
		next_id += 1
	for rules: MechBuildingDefinition in settings.building_definitions:
		if rules.produced_unit != &"" and rules.produced_unit != settings.unit_definition.unit_id:
			return "工厂生产类型未配置"
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
