class_name MechConstructionSystem
extends RefCounted
## Shared placement rules and independent parallel building lifecycles.

var _definitions: Dictionary[StringName, MechBuildingDefinition] = {}
var _buildings: Dictionary[int, MechBuildingState] = {}


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
	return ""


func clear() -> void:
	_buildings.clear()


func definition(id: StringName) -> MechBuildingDefinition:
	return _definitions.get(id)


func get_building(entity_id: int) -> MechBuildingState:
	return _buildings.get(entity_id)


func all() -> Array[MechBuildingState]:
	var result: Array[MechBuildingState] = []
	result.assign(_buildings.values())
	return result


func add(entity_id: int, id: StringName, origin: Vector2i, hz: int, completed: bool = false) -> MechBuildingState:
	var building := MechBuildingState.new()
	building.configure(entity_id, _definitions[id], origin, hz, completed)
	_buildings[entity_id] = building
	return building


func remove(entity_id: int) -> void:
	_buildings.erase(entity_id)


func catalog(economy: MechEconomySystem) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rules: MechBuildingDefinition in _definitions.values():
		if rules.buildable:
			var entry: Dictionary = rules.snapshot()
			entry["unavailable_reason"] = economy.reservation_error(rules)
			result.append(entry)
	return result


func preview_placement(id: StringName, origin: Vector2i, grid: MechGridState, economy: MechEconomySystem, minerals: MechMineralSystem, available: Dictionary = {}, planned_cells: Dictionary = {}, environment: MechEnvironmentEnergy = null, vision: MechVisionSystem = null) -> Dictionary:
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
				environment_power = environment.score(energy_type, origin, rules.footprint, grid, vision)
				if environment_power <= 0:
					reason = "环境评分不足（需已探索有效地形）"
	if reason.is_empty():
		reason = economy.reservation_error(rules, available)
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
