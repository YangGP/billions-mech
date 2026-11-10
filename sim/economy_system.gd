class_name MechEconomySystem
extends RefCounted
## 整数账本与各项预留；短缺不冻结既有设施。

var _resources: Dictionary[StringName, int] = MechResources.empty()
var _capacity_used: int = 0
var _capacity_supply: int = 0
var _capacity_total: int = 0
var _capacity_system_reserved: int = 0
## 冷却按十分之一整数存储，与 HUD 单位保持一致。
var _cooling_reserved: int = 0
var _cooling_supply: int = 0
var _power_reserved: int = 0
var _power_supply: int = 0
var _income_rate: int = 0
var repair_authorized: Callable
var repair_paid: Callable


## 按开局资源重置账本与全部预留。
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


## 当前资源余额的拷贝。
func balance() -> Dictionary[StringName, int]:
	return MechResources.copy(_resources)


## 校验一笔支出是否可付；返回中文错误描述，空字符串表示可付。
## available 非空时按该虚拟钱包校验（不影响真实账本）。
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


## 原子扣款：任一资源不足即整体失败。
func try_spend(amount: Dictionary) -> bool:
	if not spend_error(amount).is_empty():
		return false
	_resources = MechResources.subtract(_resources, amount)
	return true


## 入账（金额无效时静默忽略）。
func credit(amount: Dictionary) -> void:
	if MechResources.valid(amount):
		_resources = MechResources.add(_resources, amount)


## 依据建筑列表重算覆盖、容量、电力、冷却与收入速率的全部供给与预留。
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
		if building.upgrade_target != null:
			# 升级期间旧等级持续服务，只为正增量部分预留。
			_capacity_used += maxi(0, building.upgrade_target.capacity_cost - rules.capacity_cost)
			_power_reserved += maxi(0, building.upgrade_target.power_cost - rules.power_cost)
			_cooling_reserved += maxi(0, building.upgrade_target.cooling_cost * 10
				- rules.cooling_cost * 10)
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
			_income_rate += rules.income_per_minute


## 建造校验：按电力、冷却、调度和材料检查；超载只放行零占容恢复设施。
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


## 升级下单校验：只对容量/电力/冷却的正增量检查预留。
func upgrade_error(current: MechBuildingDefinition, target: MechBuildingDefinition, cost: Dictionary) -> String:
	if current == null or target == null:
		return "升级目标无效"
	var capacity_delta: int = maxi(0, target.capacity_cost - current.capacity_cost)
	var power_delta: int = maxi(0, target.power_cost - current.power_cost)
	var cooling_delta: int = maxi(0, target.cooling_cost * 10
		- current.cooling_cost * 10)
	if capacity_delta > 0 and (_capacity_used > _capacity_supply or _capacity_used + capacity_delta > _capacity_supply):
		return "算力容量不足以预留升级增量"
	if power_delta > 0 and _power_reserved + power_delta > _power_supply:
		return "电力不足以预留升级增量"
	if cooling_delta > 0 and _cooling_reserved + cooling_delta > _cooling_supply:
		return "冷却不足以预留升级增量"
	return spend_error(cost)


## 生产下单校验：算力超载禁新单，队列下单即占容。
func production_error(capacity_cost: int, cost: Dictionary) -> String:
	if _capacity_used > _capacity_supply:
		return "算力超载，禁止新增生产"
	if _capacity_used + capacity_cost > _capacity_supply:
		return "算力容量不足（队列下单即占容）"
	return spend_error(cost)


## 推进算力币收入：每分钟产量按 tick 累加余数，攒够整数才入账。
func advance_income(buildings: Array[MechBuildingState], hz: int) -> void:
	var denominator: int = hz * 60
	for building: MechBuildingState in buildings:
		if not building.operating():
			continue
		building.income_remainder += building.definition.income_per_minute
		if building.income_remainder >= denominator:
			credit(MechResources.single(&"coins", floori(float(building.income_remainder) / denominator)))
			building.income_remainder %= denominator


## 推进材料维修：默认 4 HP/s，材料消耗为有效配方 × 25% 摊到整段维修，
## 各资源以 分子/(4*max_hp) 的分数形式保留进度。
func advance_repairs(buildings: Array[MechBuildingState], hz: int) -> void:
	for building: MechBuildingState in buildings:
		if not building.repairing or building.phase != MechBuildingState.Phase.OPERATING:
			continue
		if building.hp >= building.definition.max_hp:
			building.repairing = false
			building.repair_hp_accumulator = 0
			continue
		# 交战中（building-economy.md §4.2）：不扣材料也不累积未付维修，
		# 直到现场无敌才恢复。
		if building.threatened:
			building.repair_waiting_for_funds = false
			building.repair_hp_accumulator = 0
			continue
		building.repair_hp_accumulator += 4
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
			# 材料步骤付不起时不提交分数与 HP。
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


## 导出账本与供需余量的只读快照（含超载/缺口标志）。
func snapshot() -> Dictionary:
	return {"resources": MechResources.copy(_resources), "coins": coins(),
		"capacity_used": _capacity_used, "capacity_supply": _capacity_supply,
		"capacity_total": _capacity_total, "capacity_system_reserved": _capacity_system_reserved,
		"cooling_reserved": _cooling_reserved, "cooling_supply": _cooling_supply,
		"cooling_free": _cooling_supply - _cooling_reserved, "cooling_deficit": _cooling_reserved > _cooling_supply,
		"power_reserved": _power_reserved, "power_supply": _power_supply,
		"power_free": _power_supply - _power_reserved, "income_rate": _income_rate,
		"overloaded": _capacity_used > _capacity_supply, "power_deficit": _power_reserved > _power_supply}
