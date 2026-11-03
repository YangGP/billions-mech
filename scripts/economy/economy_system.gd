class_name EconomySystem
extends Node
## 全局经济：库存资源 + 容量约束 + 每 tick 收支 + 建筑运营状态。
##
## 金币/木材是库存（会积累、会消耗）；工人/食物/能源是容量约束（供给 vs 占用）。
## 工人/能源按 operation_priority 分配，分不到的建筑停产；食物不足时生产者降效。
## 建筑的产出与维护费统一在这里按 tick 结算，建筑视图不得直接改库存。

signal resources_changed(resources: Dictionary)
signal capacity_changed()

var resources: Dictionary = {}

# 容量类数据：total/supply 为供给，used/demand 为占用（需求总量，不代表都被满足）。
var workers_total: int = 0
var workers_used: int = 0
var food_supply: int = 0
var food_demand: int = 0
var energy_supply: int = 0
var energy_demand: int = 0
## 因缺工/缺电/缺食物而完全停产的建筑数。
var stopped_building_count: int = 0

## 每 tick 的资源收入 / 维护费，由 recompute_capacity() 从建筑定义汇总。
var income_per_tick: Dictionary = {}
var upkeep_per_tick: Dictionary = {}
## income - upkeep，供 UI 直接显示净变化。
var _net_rates: Dictionary = {}


func setup(initial_resources: Dictionary) -> void:
	resources.clear()
	for key in initial_resources:
		resources[String(key)] = int(initial_resources[key])
	_ensure_resource("gold")
	_ensure_resource("wood")
	_rebuild_net_rates()
	resources_changed.emit(get_resources())


func get_resources() -> Dictionary:
	return resources.duplicate(true)


func get_amount(resource_id: String) -> int:
	return int(resources.get(resource_id, 0))


func add_resource(resource_id: String, amount: int) -> void:
	if amount == 0:
		return
	resources[resource_id] = get_amount(resource_id) + amount


func can_afford(cost: Dictionary) -> bool:
	for resource_id in cost:
		if get_amount(String(resource_id)) < int(cost[resource_id]):
			return false
	return true


## 只在资源足够时扣除，并立即通知 UI；调用方应先 can_afford()。
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for resource_id in cost:
		resources[String(resource_id)] = get_amount(String(resource_id)) - int(cost[resource_id])
	resources_changed.emit(get_resources())
	return true


func get_net_rate(resource_id: String) -> int:
	return int(_net_rates.get(resource_id, 0))


func get_net_rates() -> Dictionary:
	return _net_rates.duplicate(true)


## 每个模拟 tick 结算一次所有建筑的产出与维护费。
func process_tick() -> void:
	if income_per_tick.is_empty() and upkeep_per_tick.is_empty():
		return

	var changed: bool = false
	for resource_id in income_per_tick:
		var income: int = int(income_per_tick[resource_id])
		if income != 0:
			add_resource(String(resource_id), income)
			changed = true
	for resource_id in upkeep_per_tick:
		var upkeep: int = int(upkeep_per_tick[resource_id])
		if upkeep != 0:
			add_resource(String(resource_id), -upkeep)
			changed = true

	if changed:
		resources_changed.emit(get_resources())


## 建造/拆除/建筑被毁后全量重算：容量、运营状态、每 tick 收支。
func recompute_capacity(instances: Dictionary, definitions: Dictionary) -> void:
	var new_workers_total: int = 0
	var new_workers_used: int = 0
	var new_food_supply: int = 0
	var new_food_demand: int = 0
	var new_energy_supply: int = 0
	var new_energy_demand: int = 0

	for instance in instances.values():
		var building: BuildingInstance = instance
		var definition: BuildingDefinition = definitions.get(building.definition_id)
		if definition == null:
			continue
		new_workers_total += definition.housing_capacity
		new_workers_used += definition.required_workers
		new_food_supply += definition.food_capacity
		new_food_demand += definition.food_demand
		new_energy_supply += definition.energy_supply
		new_energy_demand += definition.energy_demand

	workers_total = new_workers_total
	workers_used = new_workers_used
	food_supply = new_food_supply
	food_demand = new_food_demand
	energy_supply = new_energy_supply
	energy_demand = new_energy_demand

	_compute_operation(instances, definitions)
	_rebuild_rates(instances, definitions)
	_rebuild_net_rates()
	capacity_changed.emit()


## 工人/能源按优先级贪心分配；食物不足时对生产者施加全局效率惩罚。
func _compute_operation(instances: Dictionary, definitions: Dictionary) -> void:
	var buildings: Array = instances.values()
	buildings.sort_custom(
		func(a, b): return _priority_of(a, definitions) > _priority_of(b, definitions)
	)

	var workers_left := workers_total
	var energy_left := energy_supply
	stopped_building_count = 0

	for instance in buildings:
		var building: BuildingInstance = instance
		var definition: BuildingDefinition = definitions.get(building.definition_id)
		building.operating = true
		building.operation_state = BuildingInstance.OperationState.OPERATING
		building.efficiency = 1.0
		if definition == null:
			continue

		var can_workers := workers_left >= definition.required_workers
		var can_energy := energy_left >= definition.energy_demand
		if can_workers and can_energy:
			workers_left -= definition.required_workers
			energy_left -= definition.energy_demand
			continue

		building.operating = false
		building.efficiency = 0.0
		building.operation_state = (
			BuildingInstance.OperationState.NO_WORKERS
			if not can_workers
			else BuildingInstance.OperationState.NO_ENERGY
		)

	if food_demand > food_supply:
		var food_ratio := clampf(
			float(food_supply) / float(maxi(1, food_demand)), 0.0, 1.0
		)
		for instance in buildings:
			var building: BuildingInstance = instance
			if not building.operating:
				continue
			var definition: BuildingDefinition = definitions.get(building.definition_id)
			if definition == null or definition.output_per_tick.is_empty():
				continue
			building.efficiency = food_ratio
			if building.operation_state == BuildingInstance.OperationState.OPERATING:
				building.operation_state = BuildingInstance.OperationState.FOOD_SHORTAGE

	for instance in buildings:
		var building: BuildingInstance = instance
		if not building.operating or building.efficiency <= 0.0:
			stopped_building_count += 1


func _rebuild_rates(instances: Dictionary, definitions: Dictionary) -> void:
	income_per_tick.clear()
	upkeep_per_tick.clear()

	for instance in instances.values():
		var building: BuildingInstance = instance
		var definition: BuildingDefinition = definitions.get(building.definition_id)
		if definition == null:
			continue

		# 维护费对停产建筑照常收取，形成经营压力。
		for resource_id in definition.upkeep_per_tick:
			var upkeep_key := String(resource_id)
			upkeep_per_tick[upkeep_key] = (
				int(upkeep_per_tick.get(upkeep_key, 0))
				+ int(definition.upkeep_per_tick[resource_id])
			)

		if not building.operating:
			continue

		for resource_id in definition.output_per_tick:
			var income_key := String(resource_id)
			var amount := int(
				floor(float(definition.output_per_tick[resource_id]) * building.efficiency)
			)
			if amount == 0:
				continue
			income_per_tick[income_key] = int(income_per_tick.get(income_key, 0)) + amount


func _priority_of(building, definitions: Dictionary) -> int:
	var instance: BuildingInstance = building
	var definition: BuildingDefinition = definitions.get(instance.definition_id)
	if definition == null:
		return 0
	return definition.operation_priority


func _rebuild_net_rates() -> void:
	_net_rates.clear()
	for resource_id in income_per_tick:
		var income_key := String(resource_id)
		_net_rates[income_key] = int(_net_rates.get(income_key, 0)) + int(income_per_tick[income_key])
	for resource_id in upkeep_per_tick:
		var upkeep_key := String(resource_id)
		_net_rates[upkeep_key] = int(_net_rates.get(upkeep_key, 0)) - int(upkeep_per_tick[upkeep_key])


func _ensure_resource(resource_id: String) -> void:
	if not resources.has(resource_id):
		resources[resource_id] = 0
