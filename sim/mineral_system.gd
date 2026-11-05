class_name MechMineralSystem
extends RefCounted
## Finite nonblocking deposits, reserved when a construction order commits.

var _deposits: Dictionary[StringName, Dictionary] = {}
var _cells: Dictionary[Vector2i, StringName] = {}


func reset(definitions: Array[MechMineralDefinition]) -> void:
	_deposits.clear()
	_cells.clear()
	for definition: MechMineralDefinition in definitions:
		_deposits[definition.mineral_id] = definition.snapshot()
		_cells[definition.cell] = definition.mineral_id


func at(cell: Vector2i) -> Dictionary:
	return deposit(_cells.get(cell, &""))


func deposit(id: StringName) -> Dictionary:
	return _deposits.get(id, {}).duplicate(true)


func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in _deposits.values():
		result.append(value.duplicate(true))
	return result


func placement(rules: MechBuildingDefinition, origin: Vector2i) -> Dictionary:
	var matches: Array[Dictionary] = []
	var area := Rect2i(origin, rules.footprint)
	for mineral: Dictionary in _deposits.values():
		if area.has_point(mineral["cell"]) and mineral["remaining"] > 0:
			matches.append(mineral)
	if rules.mined_resource == &"":
		return {"ok": matches.is_empty(), "reason": "矿点需预留给采集站" if not matches.is_empty() else "", "mineral_id": &""}
	if matches.size() != 1:
		return {"ok": false, "reason": "采矿站须覆盖一个未耗竭矿点", "mineral_id": &""}
	var mineral: Dictionary = matches[0]
	if mineral["resource_kind"] != rules.mined_resource:
		return {"ok": false, "reason": "矿点类型与采集站不符", "mineral_id": &""}
	if mineral["assigned_to"] != 0:
		return {"ok": false, "reason": "矿点已被其他采集站预留", "mineral_id": &""}
	return {"ok": true, "reason": "", "mineral_id": mineral["mineral_id"]}


func bind(id: StringName, entity_id: int) -> bool:
	if id == &"":
		return true
	if not _deposits.has(id) or _deposits[id]["assigned_to"] != 0 or _deposits[id]["remaining"] <= 0:
		return false
	_deposits[id]["assigned_to"] = entity_id
	return true


func release(entity_id: int) -> void:
	for mineral: Dictionary in _deposits.values():
		if mineral["assigned_to"] == entity_id:
			mineral["assigned_to"] = 0


func advance(buildings: Array[MechBuildingState], economy: MechEconomySystem, hz: int) -> void:
	var denominator: int = hz * 60
	for building: MechBuildingState in buildings:
		if building.mineral_id == &"" or not building.operating():
			continue
		var mineral: Dictionary = _deposits[building.mineral_id]
		if mineral["remaining"] <= 0:
			building.extraction_remainder = 0
			continue
		building.extraction_remainder += building.definition.extraction_per_minute
		var available: int = floori(float(building.extraction_remainder) / denominator)
		if available <= 0:
			continue
		var extracted: int = mini(available, mineral["remaining"])
		var income := Vector4i.ZERO
		income[MechResources.KEYS.find(building.definition.mined_resource)] = extracted
		economy.credit(income)
		mineral["remaining"] -= extracted
		building.extraction_remainder %= denominator


func production_rate(buildings: Array[MechBuildingState]) -> Vector4i:
	var result := Vector4i.ZERO
	for building: MechBuildingState in buildings:
		if building.mineral_id != &"" and building.operating() and _deposits[building.mineral_id]["remaining"] > 0:
			result[MechResources.KEYS.find(building.definition.mined_resource)] += building.definition.extraction_per_minute
	return result
