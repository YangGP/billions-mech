class_name EconomySystem
extends Node
## 全局经济：库存资源 + 容量约束。
##
## 金币/木材是库存（会积累、会消耗）；工人/食物/能源是容量约束（供给 vs 占用）。
## 建筑不会直接修改库存，所有资源变化都必须经过这里，方便统一结算与 UI 通知。

signal resources_changed(resources: Dictionary)
signal capacity_changed()

var resources: Dictionary = {}

# 容量类数据：total/supply 为供给，used/demand 为占用。
var workers_total: int = 0
var workers_used: int = 0
var food_supply: int = 0
var food_demand: int = 0
var energy_supply: int = 0
var energy_demand: int = 0


func setup(initial_resources: Dictionary) -> void:
	resources.clear()
	for key in initial_resources:
		resources[String(key)] = int(initial_resources[key])
	_ensure_resource("gold")
	_ensure_resource("wood")
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


## 每个模拟 tick 结算一次所有建筑的产出与维护费。
func process_tick(instances: Dictionary, definitions: Dictionary) -> void:
	if instances.is_empty():
		return

	var changed: bool = false
	for instance in instances.values():
		var definition: BuildingDefinition = definitions.get(instance.definition_id)
		if definition == null:
			continue
		for resource_id in definition.output_per_tick:
			var output: int = int(definition.output_per_tick[resource_id])
			if output != 0:
				add_resource(String(resource_id), output)
				changed = true
		for resource_id in definition.upkeep_per_tick:
			var upkeep: int = int(definition.upkeep_per_tick[resource_id])
			if upkeep != 0:
				add_resource(String(resource_id), -upkeep)
				changed = true

	if changed:
		resources_changed.emit(get_resources())


## 建造/拆除后全量重算容量，避免长期累加产生漂移。
func recompute_capacity(instances: Dictionary, definitions: Dictionary) -> void:
	var new_workers_total: int = 0
	var new_workers_used: int = 0
	var new_food_supply: int = 0
	var new_food_demand: int = 0
	var new_energy_supply: int = 0
	var new_energy_demand: int = 0

	for instance in instances.values():
		var definition: BuildingDefinition = definitions.get(instance.definition_id)
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
	capacity_changed.emit()


func _ensure_resource(resource_id: String) -> void:
	if not resources.has(resource_id):
		resources[resource_id] = 0
