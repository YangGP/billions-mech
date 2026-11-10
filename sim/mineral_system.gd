class_name MechMineralSystem
extends RefCounted
## 有限矿点，不阻挡通行；建造订单提交时完成预留绑定。

## mineral_id -> 矿点快照字典。
var _deposits: Dictionary[StringName, Dictionary] = {}
var _cells: Dictionary[Vector2i, StringName] = {}
var _produced: Dictionary[StringName, int] = {}


## 按定义列表重建全部矿点。
func reset(definitions: Array[MechMineralDefinition]) -> void:
	_deposits.clear()
	_produced.clear()
	_cells.clear()
	for definition: MechMineralDefinition in definitions:
		_deposits[definition.mineral_id] = definition.snapshot()
		_cells[definition.cell] = definition.mineral_id


## 返回指定格上的矿点快照；无矿点时返回空字典。
func at(cell: Vector2i) -> Dictionary:
	return deposit(_cells.get(cell, &""))


## 按 ID 返回矿点快照的深拷贝；不存在时返回空字典。
func deposit(id: StringName) -> Dictionary:
	return _deposits.get(id, {}).duplicate(true)


## 导出全部矿点快照列表（深拷贝）。
func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in _deposits.values():
		result.append(value.duplicate(true))
	return result


## 建造下单前的矿点校验：非采集建筑不得压矿，采集站须恰好覆盖
## 一个未耗竭、类型匹配且未被预留的矿点。
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


## 建造提交时将矿点绑定到采集站实体；已被占用或耗竭则失败。
func bind(id: StringName, entity_id: int) -> bool:
	if id == &"":
		return true
	if not _deposits.has(id) or _deposits[id]["assigned_to"] != 0 or _deposits[id]["remaining"] <= 0:
		return false
	_deposits[id]["assigned_to"] = entity_id
	return true


## 解除某实体对矿点的全部占用（拆除或失效时调用）。
func release(entity_id: int) -> void:
	for mineral: Dictionary in _deposits.values():
		if mineral["assigned_to"] == entity_id:
			mineral["assigned_to"] = 0


## 按每分钟产量推进采集：余数累加到整数产出才入账，矿耗竭即停。
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
		var income := MechResources.empty()
		income[building.definition.mined_resource] = extracted
		_produced[building.definition.mined_resource] = int(
			_produced.get(building.definition.mined_resource, 0)
		) + extracted
		economy.credit(income)
		mineral["remaining"] -= extracted
		building.extraction_remainder %= denominator


## 开局至今是否产出过指定资源（用于进度门槛判定）。
func has_produced(resource: StringName) -> bool:
	return int(_produced.get(resource, 0)) > 0


## 汇总当前运行的采集站的每分钟名义产出。
func production_rate(buildings: Array[MechBuildingState]) -> Dictionary:
	var result := MechResources.empty()
	for building: MechBuildingState in buildings:
		if building.mineral_id != &"" and building.operating() and _deposits[building.mineral_id]["remaining"] > 0:
			result[building.definition.mined_resource] += building.definition.extraction_per_minute
	return result
