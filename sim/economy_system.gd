class_name MechEconomySystem
extends RefCounted
## Integer ledger and reservations; shortages do not freeze existing facilities.

var _resources: Vector4i = Vector4i.ZERO
var _capacity_used: int = 0
var _capacity_supply: int = 0
var _power_reserved: int = 0
var _power_supply: int = 0
var _income_rate: int = 0


func reset(starting_resources: Vector4i) -> void:
	_resources = starting_resources
	_capacity_used = 0
	_capacity_supply = 0
	_power_reserved = 0
	_power_supply = 0
	_income_rate = 0


func coins() -> int:
	return _resources.x


func balance() -> Vector4i:
	return _resources


func spend_error(amount: Vector4i, available: Vector4i = Vector4i(-1, -1, -1, -1)) -> String:
	if not MechResources.valid(amount):
		return "资源造价无效"
	var wallet: Vector4i = _resources if available.x < 0 else available
	for index: int in range(4):
		if amount[index] > wallet[index]:
			return "%s不足（需要 %d，现有 %d）" % [MechResources.NAMES[index], amount[index], wallet[index]]
	return ""


func try_spend(amount: Vector4i) -> bool:
	if not spend_error(amount).is_empty():
		return false
	_resources -= amount
	return true


func credit(amount: Vector4i) -> void:
	if MechResources.valid(amount):
		_resources += amount


func recompute(buildings: Array[MechBuildingState], grid: MechGridState, unit_capacity: int = 0, queued_capacity: int = 0) -> void:
	_capacity_used = unit_capacity + queued_capacity
	_capacity_supply = 0
	_power_reserved = 0
	_power_supply = 0
	_income_rate = 0
	for building: MechBuildingState in buildings:
		var rules: MechBuildingDefinition = building.definition
		building.powered = rules.is_core or grid.footprint_covered(building.origin, rules.footprint)
		_capacity_used += rules.capacity_cost
		_power_reserved += rules.power_cost
		if building.operating():
			_capacity_supply += rules.capacity_provided
			_power_supply += rules.power_provided
			_income_rate += rules.income_per_minute


func reservation_error(rules: MechBuildingDefinition, available: Vector4i = Vector4i(-1, -1, -1, -1)) -> String:
	if _power_reserved > _power_supply:
		return "电力赤字，禁止新增下单"
	if _power_reserved + rules.power_cost > _power_supply:
		return "电力余量不足"
	if _capacity_used > _capacity_supply:
		if rules.capacity_cost != 0 or rules.capacity_provided <= 0:
			return "算力超载，仅可建造零占容的容量恢复设施"
	elif _capacity_used + rules.capacity_cost > _capacity_supply:
		return "算力容量不足"
	return spend_error(rules.cost, available)


func production_error(capacity_cost: int, cost: Vector4i) -> String:
	if _power_reserved > _power_supply:
		return "电力赤字，禁止新增生产"
	if _capacity_used > _capacity_supply:
		return "算力超载，禁止新增生产"
	if _capacity_used + capacity_cost > _capacity_supply:
		return "算力容量不足（队列下单即占容）"
	return spend_error(cost)


func advance_income(buildings: Array[MechBuildingState], hz: int) -> void:
	var denominator: int = hz * 60
	for building: MechBuildingState in buildings:
		if not building.operating():
			continue
		building.income_remainder += building.definition.income_per_minute
		if building.income_remainder >= denominator:
			credit(Vector4i(floori(float(building.income_remainder) / denominator), 0, 0, 0))
			building.income_remainder %= denominator


func advance_repairs(buildings: Array[MechBuildingState], hz: int) -> void:
	for building: MechBuildingState in buildings:
		if not building.repairing or building.phase != MechBuildingState.Phase.OPERATING:
			continue
		if building.hp >= building.definition.max_hp:
			building.repairing = false
			building.repair_remainder = 0
			continue
		# One coin/sec, two HP/coin. Keep at most one unpaid step.
		building.repair_remainder += 1
		building.repair_waiting_for_funds = coins() == 0
		if building.repair_remainder < hz:
			continue
		if not try_spend(Vector4i(1, 0, 0, 0)):
			building.repair_remainder = mini(hz, building.repair_remainder)
			continue
		building.repair_remainder -= hz
		building.hp = mini(building.definition.max_hp, building.hp + 2)
		if building.hp == building.definition.max_hp:
			building.repairing = false
			building.repair_remainder = 0


func snapshot() -> Dictionary:
	return {"resources": _resources, "coins": coins(), "ore": _resources.y,
		"capacity_used": _capacity_used, "capacity_supply": _capacity_supply,
		"power_reserved": _power_reserved, "power_supply": _power_supply,
		"power_free": _power_supply - _power_reserved, "income_rate": _income_rate,
		"overloaded": _capacity_used > _capacity_supply, "power_deficit": _power_reserved > _power_supply}
