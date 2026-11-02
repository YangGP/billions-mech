class_name BuildingSystem
extends Node
## 建筑实例的唯一入口：校验、扣费、占格、拆除都在这里完成。
##
## 手动建造与未来的规划层必须调用同一套 try_place_building() / remove_building()，
## 不要在 UI 或建筑视图中自行判断合法性或修改资源。
## 建筑定义从 res://data/buildings/*.tres 自动加载。

signal building_placed(instance: BuildingInstance)
signal building_removed(instance: BuildingInstance)
signal buildings_changed()

const DEFINITION_DIR: String = "res://data/buildings"

## StringName(building_id) -> BuildingDefinition
var definitions: Dictionary = {}
## StringName(instance_id) -> BuildingInstance
var instances: Dictionary = {}
## 最近一次失败原因，供 HUD / 调试面板直接显示。
var last_error: String = ""
## 全局可建造格集合，由带 build_range_radius 的建筑覆盖生成。
## 键为 Vector2i，值为 true。
var build_coverage: Dictionary = {}

var _grid: GridState
var _economy: EconomySystem
var _next_instance_number: int = 1


func setup(grid: GridState, economy: EconomySystem) -> void:
	_grid = grid
	_economy = economy
	definitions.clear()
	instances.clear()
	_next_instance_number = 1
	_load_definitions()
	_recompute_build_coverage()


## 只做校验、不修改任何状态；供预览和 try_place_building 共用同一套规则。
func get_placement_error(definition_id: StringName, origin: Vector2i) -> String:
	return _validate_placement(StringName(definition_id), origin, false)


func can_place_building(definition_id: StringName, origin: Vector2i) -> bool:
	return get_placement_error(definition_id, origin) == ""


## 统一的建造入口：全部校验通过后才扣费并写入占地，失败不产生半成品状态。
func try_place_building(definition_id: StringName, origin: Vector2i) -> bool:
	var key := StringName(definition_id)
	last_error = _validate_placement(key, origin, false)
	if last_error != "":
		return false
	return _commit_placement(key, origin)


## 开局初始建筑专用：此时还没有任何建造覆盖，跳过范围检查，其余规则一致。
func place_initial_building(definition_id: StringName, origin: Vector2i) -> bool:
	var key := StringName(definition_id)
	last_error = _validate_placement(key, origin, true)
	if last_error != "":
		return false
	return _commit_placement(key, origin)


func is_in_build_range(cell: Vector2i) -> bool:
	return build_coverage.has(cell)


func _validate_placement(
	key: StringName, origin: Vector2i, ignore_range: bool
) -> String:
	if _grid == null or _economy == null:
		return "建筑系统尚未初始化"

	var definition: BuildingDefinition = definitions.get(key)
	if definition == null:
		return "未知建筑类型：%s" % key
	if definition.unique and _has_instance_of(key):
		return "该建筑只能建造一座"
	if not _grid.can_place(origin, definition.footprint):
		return "无法放置：越界、地形阻挡或已被占用"
	if not ignore_range and not _is_footprint_in_range(origin, definition.footprint):
		return "超出建造范围：靠近指挥中心或电力中继塔后才能建造"

	var capacity_error := _get_capacity_error(definition)
	if capacity_error != "":
		return capacity_error
	if not _economy.can_afford(definition.build_cost):
		return "资源不足：%s" % _format_resources(definition.build_cost)
	return ""


func _commit_placement(key: StringName, origin: Vector2i) -> bool:
	var definition: BuildingDefinition = definitions.get(key)
	var instance := BuildingInstance.new()
	instance.instance_id = _make_instance_id()
	instance.definition_id = key
	instance.origin_cell = origin
	instance.footprint = definition.footprint
	instance.cells = _grid.cells_for_footprint(origin, definition.footprint)

	# 扣费与占格都成功后才对外发信号，保证「数据先于表现」。
	if not _economy.spend(definition.build_cost):
		last_error = "资源不足：%s" % _format_resources(definition.build_cost)
		return false

	_grid.occupy(instance.cells, instance.instance_id)
	instances[instance.instance_id] = instance
	_recompute_capacity()
	_recompute_build_coverage()
	building_placed.emit(instance)
	buildings_changed.emit()
	return true


func remove_building(instance_id: StringName) -> bool:
	last_error = ""
	var instance: BuildingInstance = instances.get(StringName(instance_id))
	if instance == null:
		last_error = "建筑不存在：%s" % instance_id
		return false

	var definition := get_definition(instance.definition_id)
	if definition != null and not definition.demolishable:
		last_error = "该建筑不可拆除"
		return false

	_grid.release(instance.cells)
	instances.erase(instance.instance_id)
	_recompute_capacity()
	_recompute_build_coverage()
	building_removed.emit(instance)
	buildings_changed.emit()
	return true


func get_definition(definition_id: StringName) -> BuildingDefinition:
	return definitions.get(StringName(definition_id))


func get_definitions() -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for key in definitions:
		result.append(definitions[key])
	result.sort_custom(_sort_definitions)
	return result


## 建造菜单只显示 buildable = true 的定义；指挥中心等初始建筑不在其中。
func get_buildable_definitions() -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for key in definitions:
		var definition: BuildingDefinition = definitions[key]
		if definition.buildable:
			result.append(definition)
	result.sort_custom(_sort_definitions)
	return result


func _sort_definitions(a: BuildingDefinition, b: BuildingDefinition) -> bool:
	if a.palette_order != b.palette_order:
		return a.palette_order < b.palette_order
	return String(a.building_id) < String(b.building_id)


func get_building_count() -> int:
	return instances.size()


## 容量检查按“建成后”的总量判断：新增建筑自身的供给也算进去。
func _get_capacity_error(definition: BuildingDefinition) -> String:
	var next_workers_used := _economy.workers_used + definition.required_workers
	var next_workers_total := _economy.workers_total + definition.housing_capacity
	if next_workers_used > next_workers_total:
		return "工人不足：需要 %d 名工人（当前 %d/%d）" % [
			definition.required_workers, _economy.workers_used, _economy.workers_total
		]

	var next_food_demand := _economy.food_demand + definition.food_demand
	var next_food_supply := _economy.food_supply + definition.food_capacity
	if next_food_demand > next_food_supply:
		return "食物不足：需要 %d 食物供给（当前 %d/%d）" % [
			definition.food_demand, _economy.food_demand, _economy.food_supply
		]

	var next_energy_demand := _economy.energy_demand + definition.energy_demand
	var next_energy_supply := _economy.energy_supply + definition.energy_supply
	if next_energy_demand > next_energy_supply:
		return "能源不足：需要 %d 能源供给（当前 %d/%d）" % [
			definition.energy_demand, _economy.energy_demand, _economy.energy_supply
		]
	return ""


func _has_instance_of(definition_id: StringName) -> bool:
	for instance in instances.values():
		if instance.definition_id == definition_id:
			return true
	return false


func _make_instance_id() -> StringName:
	var instance_id := StringName("building_%d" % _next_instance_number)
	_next_instance_number += 1
	return instance_id


func _recompute_capacity() -> void:
	if _economy != null:
		_economy.recompute_capacity(instances, definitions)


## 用带 build_range_radius 的建筑重算覆盖范围（欧氏半径，按占地所有格为圆心）。
func _recompute_build_coverage() -> void:
	build_coverage.clear()
	if _grid == null:
		return

	for instance in instances.values():
		var definition: BuildingDefinition = definitions.get(instance.definition_id)
		if definition == null or definition.build_range_radius <= 0:
			continue
		var radius := definition.build_range_radius
		var radius_squared := radius * radius
		var source_cells: Array[Vector2i] = instance.cells
		for source_cell in source_cells:
			for offset_y in range(-radius, radius + 1):
				for offset_x in range(-radius, radius + 1):
					if offset_x * offset_x + offset_y * offset_y > radius_squared:
						continue
					var cell: Vector2i = source_cell + Vector2i(offset_x, offset_y)
					if (
						cell.x < 0
						or cell.y < 0
						or cell.x >= _grid.map_width
						or cell.y >= _grid.map_height
					):
						continue
					build_coverage[cell] = true


func _is_footprint_in_range(origin: Vector2i, size: Vector2i) -> bool:
	for cell in _grid.cells_for_footprint(origin, size):
		if not build_coverage.has(cell):
			return false
	return true


func _format_resources(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource_id in cost:
		parts.append("%s×%d" % [resource_id, int(cost[resource_id])])
	return "、".join(parts)


func _load_definitions() -> void:
	var dir := DirAccess.open(DEFINITION_DIR)
	if dir == null:
		# 目录为空或尚未创建时允许启动，M1-04 再补充正式建筑数据。
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource: Resource = load(DEFINITION_DIR.path_join(file_name))
			if resource is BuildingDefinition:
				var definition := resource as BuildingDefinition
				if definition.is_valid():
					definitions[definition.building_id] = definition
				else:
					push_warning("建筑定义无效，已跳过：%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
