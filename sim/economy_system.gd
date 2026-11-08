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
var repair_authorized: Callable
var repair_paid: Callable


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
		_cooling_reserved += roundi(float(rules.cooling_cost * 10 * building.cooling_multiplier_percent) / 100.0)
		if building.upgrade_target != null:
			# Reserve only the positive delta while the old level keeps serving.
			_capacity_used += maxi(0, building.upgrade_target.capacity_cost - rules.capacity_cost)
			_power_reserved += maxi(0, building.upgrade_target.power_cost - rules.power_cost)
			_cooling_reserved += maxi(0, roundi(float(
				building.upgrade_target.cooling_cost * 10 * building.cooling_multiplier_percent) / 100.0)
				- roundi(float(rules.cooling_cost * 10 * building.cooling_multiplier_percent) / 100.0))
		if building.operating():
			_capacity_total += rules.capacity_provided
			_capacity_system_reserved += rules.capacity_system_reserved
			_capacity_supply += rules.capacity_provided - rules.capacity_system_reserved
			if rules.alloy_recipe != null:
				_power_supply += building.processing_power
			elif rules.environment_energy != "none":
				_power_supply += building.environment_power
			else:
				_power_supply += rules.power_provided
			_cooling_supply += rules.cooling_provided * 10
			_income_rate += rules.income_per_minute * building.income_multiplier_percent / 100


func contract_error(capacity_cost: int, price: Dictionary) -> String:
	if _capacity_used > _capacity_supply:
		return "算力超载，禁止新增合同"
	if _capacity_used + capacity_cost > _capacity_supply:
		return "算力容量不足（合同接受即预留）"
	return spend_error(price)


func reservation_error(rules: MechBuildingDefinition, available: Dictionary = {}, cost_override: Dictionary = {}, cooling_multiplier: float = 1.0) -> String:
	if rules.power_cost > 0 and _power_reserved + rules.power_cost > _power_supply:
		return "电力余量不足"
	if rules.cooling_cost > 0 and _cooling_reserved + roundi(rules.cooling_cost * 10 * cooling_multiplier) > _cooling_supply:
		return "冷却余量不足"
	if _capacity_used > _capacity_supply:
		if rules.capacity_cost != 0 or not rules.supply_recovery():
			return "算力超载，仅可建造零占容的容量恢复设施"
	elif _capacity_used + rules.capacity_cost > _capacity_supply:
		return "算力容量不足"
	return spend_error(rules.cost if cost_override.is_empty() else cost_override, available)


func upgrade_error(current: MechBuildingDefinition, target: MechBuildingDefinition, cost: Dictionary, cooling_multiplier: float = 1.0) -> String:
	if current == null or target == null:
		return "升级目标无效"
	var capacity_delta: int = maxi(0, target.capacity_cost - current.capacity_cost)
	var power_delta: int = maxi(0, target.power_cost - current.power_cost)
	var cooling_delta: int = maxi(0, roundi(target.cooling_cost * 10 * cooling_multiplier)
		- roundi(current.cooling_cost * 10 * cooling_multiplier))
	if capacity_delta > 0 and (_capacity_used > _capacity_supply or _capacity_used + capacity_delta > _capacity_supply):
		return "算力容量不足以预留升级增量"
	if power_delta > 0 and _power_reserved + power_delta > _power_supply:
		return "电力不足以预留升级增量"
	if cooling_delta > 0 and _cooling_reserved + cooling_delta > _cooling_supply:
		return "冷却不足以预留升级增量"
	return spend_error(cost)


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
		building.income_remainder += building.definition.income_per_minute * building.income_multiplier_percent
		var income_denominator: int = denominator * 100
		if building.income_remainder >= income_denominator:
			credit(MechResources.single(&"coins", floori(float(building.income_remainder) / income_denominator)))
			building.income_remainder %= income_denominator


func advance_repairs(buildings: Array[MechBuildingState], hz: int) -> void:
	for building: MechBuildingState in buildings:
		if not building.repairing or building.phase != MechBuildingState.Phase.OPERATING:
			continue
		if building.hp >= building.definition.max_hp:
			building.repairing = false
			building.repair_hp_accumulator = 0
			continue
		# In combat (building-economy.md §4.2): healing halts without spending
		# or accumulating unpaid repair until the site is clear of enemies.
		if building.threatened:
			building.repair_waiting_for_funds = false
			building.repair_hp_accumulator = 0
			continue
		# 4 HP/s; material cost is the effective build recipe × 25% over a full
		# repair. Fractions are kept per resource as numerator / (4*max_hp).
		building.repair_hp_accumulator += roundi(building.repair_rate_override if building.repair_rate_override > 0.0 else 4.0)
		if building.repair_hp_accumulator < hz:
			continue
		var denominator: int = 4 * maxi(1, building.definition.max_hp)
		var due := {}
		var next_remainder := MechResources.copy(building.repair_material_remainder)
		for key: StringName in MechResources.KEYS:
			var amount: int = int(building.definition.cost.get(key, 0))
			if amount <= 0:
				continue
			var total: int = int(next_remainder.get(key, 0)) + amount
			var units: int = total / denominator
			if units > 0:
				due[key] = units
			next_remainder[key] = total - units * denominator
		if repair_authorized.is_valid() and not repair_authorized.call(building, due):
			building.repair_waiting_for_funds = true
			building.repair_hp_accumulator = 0
			continue
		if not due.is_empty() and not try_spend(due):
			# Do not commit fractions or HP when the material step cannot be paid.
			building.repair_waiting_for_funds = true
			building.repair_hp_accumulator = 0
			continue
		if repair_paid.is_valid():
			repair_paid.call(building, due)
		building.repair_material_remainder = next_remainder
		building.repair_hp_accumulator -= hz
		building.hp = mini(building.definition.max_hp, building.hp + 1)
		building.repair_waiting_for_funds = false
		if building.hp >= building.definition.max_hp:
			building.repairing = false
			building.repair_hp_accumulator = 0


func snapshot() -> Dictionary:
	return {"resources": MechResources.copy(_resources), "coins": coins(),
		"capacity_used": _capacity_used, "capacity_supply": _capacity_supply,
		"capacity_total": _capacity_total, "capacity_system_reserved": _capacity_system_reserved,
		"cooling_reserved": _cooling_reserved, "cooling_supply": _cooling_supply,
		"cooling_free": _cooling_supply - _cooling_reserved, "cooling_deficit": _cooling_reserved > _cooling_supply,
		"power_reserved": _power_reserved, "power_supply": _power_supply,
		"power_free": _power_supply - _power_reserved, "income_rate": _income_rate,
		"overloaded": _capacity_used > _capacity_supply, "power_deficit": _power_reserved > _power_supply}
