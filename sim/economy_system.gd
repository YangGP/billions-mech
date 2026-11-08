class_name MechEconomySystem
extends RefCounted
## Integer ledger and reservations; shortages do not freeze existing facilities.

var _resources: Dictionary[StringName, int] = MechResources.empty()
var _capacity_used: int = 0
var _capacity_supply: int = 0
var _capacity_total: int = 0
var _capacity_system_reserved: int = 0
## Cooling is stored as integer tenths for future 20% load-balancing reductions.
var _cooling_reserved: int = 0
var _cooling_supply: int = 0
var _power_reserved: int = 0
var _power_supply: int = 0
var _income_rate: int = 0


func reset(starting_resources: Dictionary) -> void:
	_resources = MechResources.copy(starting_resources)
	_capacity_used = 0
	_capacity_supply = 0
	_capacity_total = 0
	_capacity_system_reserved = 0
	_cooling_reserved = 0
	_cooling_supply = 0
	_power_reserved = 0
	_power_supply = 0
	_income_rate = 0


func coins() -> int:
	return _resources[&"coins"]


func balance() -> Dictionary[StringName, int]:
	return MechResources.copy(_resources)


func spend_error(amount: Dictionary, available: Dictionary = {}) -> String:
	if not MechResources.valid(amount):
		return "资源造价无效"
	var wallet: Dictionary = _resources if available.is_empty() else available
	for index: int in range(MechResources.KEYS.size()):
		var key: StringName = MechResources.KEYS[index]
		var required: int = int(amount.get(key, 0))
		var owned: int = int(wallet.get(key, 0))
		if required > owned:
			return "%s不足（需要 %d，现有 %d）" % [MechResources.NAMES[index], required, owned]
	return ""


func try_spend(amount: Dictionary) -> bool:
	if not spend_error(amount).is_empty():
		return false
	_resources = MechResources.subtract(_resources, amount)
	return true


func credit(amount: Dictionary) -> void:
	if MechResources.valid(amount):
		_resources = MechResources.add(_resources, amount)


func recompute(buildings: Array[MechBuildingState], grid: MechGridState, unit_capacity: int = 0, queued_capacity: int = 0) -> void:
	_capacity_used = unit_capacity + queued_capacity
	_capacity_supply = 0
	_capacity_total = 0
	_capacity_system_reserved = 0
	_cooling_reserved = 0
	_cooling_supply = 0
	_power_reserved = 0
	_power_supply = 0
	_income_rate = 0
	for building: MechBuildingState in buildings:
		var rules: MechBuildingDefinition = building.definition
		building.powered = rules.is_core or grid.footprint_covered(building.origin, rules.footprint)
		if building.hp <= 0:
			continue
		_capacity_used += rules.capacity_cost
		_power_reserved += rules.power_cost
		_cooling_reserved += rules.cooling_cost * 10
		if building.operating():
			_capacity_total += rules.capacity_provided
			_capacity_system_reserved += rules.capacity_system_reserved
			_capacity_supply += rules.capacity_provided - rules.capacity_system_reserved
			if rules.environment_energy != "none":
				_power_supply += building.environment_power
			else:
				_power_supply += rules.power_provided
			_cooling_supply += rules.cooling_provided * 10
			_income_rate += rules.income_per_minute


func reservation_error(rules: MechBuildingDefinition, available: Dictionary = {}, cost_override: Dictionary = {}) -> String:
	if rules.power_cost > 0 and _power_reserved + rules.power_cost > _power_supply:
		return "电力余量不足"
	if rules.cooling_cost > 0 and _cooling_reserved + rules.cooling_cost * 10 > _cooling_supply:
		return "冷却余量不足"
	if _capacity_used > _capacity_supply:
		if rules.capacity_cost != 0 or not rules.supply_recovery():
			return "算力超载，仅可建造零占容的容量恢复设施"
	elif _capacity_used + rules.capacity_cost > _capacity_supply:
		return "算力容量不足"
	return spend_error(rules.cost if cost_override.is_empty() else cost_override, available)


func production_error(capacity_cost: int, cost: Dictionary) -> String:
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
			credit(MechResources.single(&"coins", floori(float(building.income_remainder) / denominator)))
			building.income_remainder %= denominator


func advance_repairs(buildings: Array[MechBuildingState], hz: int) -> void:
	for building: MechBuildingState in buildings:
		if not building.repairing or building.phase != MechBuildingState.Phase.OPERATING:
			continue
		if building.hp >= building.definition.max_hp:
			building.repairing = false
			building.repair_remainder = 0
			continue
		# In combat (building-economy.md §4.2): healing halts without spending
		# or accumulating remainders until the site is clear of enemies.
		if building.threatened:
			building.repair_waiting_for_funds = false
			continue
		# One coin/sec, two HP/coin. Keep at most one unpaid step.
		building.repair_remainder += 1
		building.repair_waiting_for_funds = coins() == 0
		if building.repair_remainder < hz:
			continue
		if not try_spend(MechResources.single(&"coins", 1)):
			building.repair_remainder = mini(hz, building.repair_remainder)
			continue
		building.repair_remainder -= hz
		building.hp = mini(building.definition.max_hp, building.hp + 2)
		if building.hp == building.definition.max_hp:
			building.repairing = false
			building.repair_remainder = 0


func snapshot() -> Dictionary:
	return {"resources": MechResources.copy(_resources), "coins": coins(),
		"capacity_used": _capacity_used, "capacity_supply": _capacity_supply,
		"capacity_total": _capacity_total, "capacity_system_reserved": _capacity_system_reserved,
		"cooling_reserved": _cooling_reserved, "cooling_supply": _cooling_supply,
		"cooling_free": _cooling_supply - _cooling_reserved, "cooling_deficit": _cooling_reserved > _cooling_supply,
		"power_reserved": _power_reserved, "power_supply": _power_supply,
		"power_free": _power_supply - _power_reserved, "income_rate": _income_rate,
		"overloaded": _capacity_used > _capacity_supply, "power_deficit": _power_reserved > _power_supply}
