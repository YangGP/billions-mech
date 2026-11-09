class_name MechConstructionSystem
extends RefCounted
## 共享的放置规则与各自独立的并行建筑生命周期。

var _definitions: Dictionary[StringName, MechBuildingDefinition] = {}
var _buildings: Dictionary[int, MechBuildingState] = {}
## 升级链族根：同一建筑的各等级形态（含升级前后）映射到同一个根 id。
var _family_roots: Dictionary[StringName, StringName] = {}


## 装配建筑定义表；返回错误描述，空字符串表示成功。
func configure(definitions: Array[MechBuildingDefinition]) -> String:
	_definitions.clear()
	for rules: MechBuildingDefinition in definitions:
		if rules == null:
			return "空建筑定义"
		var error: String = rules.validation_error()
		if not error.is_empty():
			return error
		if _definitions.has(rules.building_id):
			return "重复建筑编号"
		_definitions[rules.building_id] = rules
	if not _definitions.has(&"mainbrain") or not _definitions[&"mainbrain"].is_core:
		return "缺少主脑定义"
	_rebuild_family_roots()
	return ""


func clear() -> void:
	_buildings.clear()


func definition(id: StringName) -> MechBuildingDefinition:
	return _definitions.get(id)


## 升级链族根：同一族的各级形态返回同一个 id，用于"同种建筑"判定。
func family_root(id: StringName) -> StringName:
	return _family_roots.get(id, id)


## 遍历全部 upgrade_to 引用收集各级定义，再逐级上溯到族根。
func _rebuild_family_roots() -> void:
	_family_roots.clear()
	var parents: Dictionary[StringName, StringName] = {}
	var ids: Dictionary[StringName, bool] = {}
	var pending: Array[MechBuildingDefinition] = []
	pending.assign(_definitions.values())
	while not pending.is_empty():
		var rules: MechBuildingDefinition = pending.pop_back()
		if ids.has(rules.building_id):
			continue
		ids[rules.building_id] = true
		if rules.upgrade_to != null:
			parents[rules.upgrade_to.building_id] = rules.building_id
			pending.append(rules.upgrade_to)
	for id: StringName in ids:
		var root: StringName = id
		var guard: int = 0
		while parents.has(root) and guard < ids.size():
			root = parents[root]
			guard += 1
		_family_roots[id] = root


func get_building(entity_id: int) -> MechBuildingState:
	return _buildings.get(entity_id)


func all() -> Array[MechBuildingState]:
	var result: Array[MechBuildingState] = []
	result.assign(_buildings.values())
	return result


## 创建并登记一栋建筑；completed 为真时直接完工入场。
func add(entity_id: int, id: StringName, origin: Vector2i, hz: int, completed: bool = false) -> MechBuildingState:
	var building := MechBuildingState.new()
	building.configure(entity_id, _definitions[id], origin, hz, completed)
	_buildings[entity_id] = building
	return building


func remove(entity_id: int) -> void:
	_buildings.erase(entity_id)


## 可下单建筑目录：定义快照附带当前资源下的不可下单原因。
func catalog(economy: MechEconomySystem) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rules: MechBuildingDefinition in _definitions.values():
		if rules.buildable:
			var entry: Dictionary = rules.snapshot()
			entry["unavailable_reason"] = economy.reservation_error(rules)
			result.append(entry)
	return result


## 建造预览：逐格校验地形、覆盖、占用，再校验水冷邻水、矿点、
## 环境源评分与经济预留；错误按 地形→覆盖→占用 的优先级返回。
## planned_cells 用于墙线等连续下单时排除本批已计划的格子。
func preview_placement(id: StringName, origin: Vector2i, grid: MechGridState, economy: MechEconomySystem, minerals: MechMineralSystem, available: Dictionary = {}, planned_cells: Dictionary = {}, environment: MechEnvironmentEnergy = null, vision: MechVisionSystem = null, cooling_multiplier: float = 1.0) -> Dictionary:
	var rules: MechBuildingDefinition = definition(id)
	if rules == null or not rules.buildable:
		return {"ok": false, "reason": "该建筑不可下单", "cells": [], "origin": origin, "footprint": Vector2i.ONE}
	var result: Dictionary = grid.preview_footprint(origin, rules.footprint)
	var terrain_error: String = ""
	var coverage_error: String = ""
	var overlap_error: String = ""
	for cell_info: Dictionary in result["cells"]:
		var cell: Vector2i = cell_info["cell"]
		var error: String = grid.terrain_build_error(cell)
		if not error.is_empty():
			terrain_error = error if terrain_error.is_empty() else terrain_error
		elif not grid.is_covered(cell):
			error = "超出供电覆盖"
			coverage_error = error
		elif grid.occupant_at(cell) != 0 or planned_cells.has(cell):
			error = "已有建筑占用"
			overlap_error = error
		cell_info["ok"] = error.is_empty()
		cell_info["reason"] = error
	var reason: String = terrain_error
	if reason.is_empty():
		reason = coverage_error
	if reason.is_empty():
		reason = overlap_error
	if reason.is_empty() and rules.requires_water and not _has_water_edge(rules, origin, grid):
		reason = "水冷站需与水域正交相邻"
	var mineral_check: Dictionary = minerals.placement(rules, origin)
	if reason.is_empty() and not mineral_check["ok"]:
		reason = mineral_check["reason"]
	var energy_type := StringName(rules.environment_energy)
	var environment_power: int = 0
	var collection_bounds := Rect2i()
	var conflict_cells: Array[Vector2i] = []
	if reason.is_empty() and energy_type != &"none":
		if environment == null or vision == null:
			reason = "环境采集规则未就绪"
		else:
			collection_bounds = environment.collection_bounds(origin, rules.footprint)
			conflict_cells = environment.conflicts(energy_type, origin, rules.footprint)
			if not conflict_cells.is_empty():
				reason = "同类环境电源采集区重叠"
			else:
				environment_power = environment.score(
					energy_type, origin, rules.footprint, grid, vision,
					rules.environment_output_multiplier, rules.environment_output_cap
				)
				if environment_power <= 0:
					reason = "环境评分不足（需已探索有效地形）"
	if reason.is_empty():
		reason = economy.reservation_error(rules, available, {}, cooling_multiplier)
	if not reason.is_empty() and terrain_error.is_empty() and coverage_error.is_empty() and overlap_error.is_empty():
		for cell_info: Dictionary in result["cells"]:
			cell_info["ok"] = false
			cell_info["reason"] = reason
	result["ok"] = reason.is_empty()
	result["reason"] = reason
	result["cost"] = MechResources.copy(rules.cost)
	result["building_id"] = id
	result["mineral_id"] = mineral_check["mineral_id"]
	result["environment_energy"] = String(energy_type)
	result["environment_power"] = environment_power
	result["collection_bounds"] = collection_bounds
	result["conflict_cells"] = conflict_cells
	return result


## 水冷站是否与水域正交相邻（不含对角）。
func _has_water_edge(rules: MechBuildingDefinition, origin: Vector2i, grid: MechGridState) -> bool:
	var body := Rect2i(origin, rules.footprint)
	for y: int in range(origin.y, origin.y + rules.footprint.y):
		for x: int in range(origin.x, origin.x + rules.footprint.x):
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var cell: Vector2i = Vector2i(x, y) + offset
				if body.has_point(cell):
					continue
				if grid.is_water(cell):
					return true
	return false


## 墙线批量预览：沿格子逐段预览，前序可下单段会扣减虚拟钱包并占用 planned，
## 返回合计费用与 可下单/跳过 数量。
func preview_wall_line(cells: Array[Vector2i], grid: MechGridState, economy: MechEconomySystem, minerals: MechMineralSystem) -> Dictionary:
	var planned: Dictionary = {}
	var combined: Array[Dictionary] = []
	var available: Dictionary = economy.balance()
	var count: int = 0
	for cell: Vector2i in cells:
		var preview: Dictionary = preview_placement(&"armored_wall", cell, grid, economy, minerals, available, planned)
		combined.append_array(preview["cells"])
		if preview["ok"]:
			planned[cell] = true
			available = MechResources.subtract(available, preview["cost"])
			count += 1
	return {"ok": count > 0, "reason": "" if count > 0 else "墙线没有可下单的格子",
		"cells": combined, "planned_count": count, "skipped_count": cells.size() - count,
		"cost": MechResources.subtract(economy.balance(), available), "line": true}


## 推进全部建筑的施工/拆除；完工时经回调确认脚印内无阻挡才转运行态。
## 返回本 tick 完工与拆完的实体 ID 列表。
func advance(try_clear_footprint: Callable) -> Dictionary:
	var completed: Array[int] = []
	var demolished: Array[int] = []
	for building: MechBuildingState in _buildings.values():
		if building.phase == MechBuildingState.Phase.CONSTRUCTING:
			if building.advance_construction():
				building.waiting_for_clearance = not try_clear_footprint.call(building)
				if not building.waiting_for_clearance:
					building.phase = MechBuildingState.Phase.OPERATING
					completed.append(building.entity_id)
		elif building.phase == MechBuildingState.Phase.DEMOLISHING:
			building.elapsed_demolition_ticks += 1
			if building.elapsed_demolition_ticks >= building.demolition_ticks:
				demolished.append(building.entity_id)
	return {"completed": completed, "demolished": demolished}
