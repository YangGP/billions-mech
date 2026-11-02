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


## 统一的建造入口：全部校验通过后才扣费并写入占地，失败不产生半成品状态。
func try_place_building(definition_id: StringName, origin: Vector2i) -> bool:
	last_error = ""
	if _grid == null or _economy == null:
		last_error = "建筑系统尚未初始化"
		return false

	var key := StringName(definition_id)
	var definition: BuildingDefinition = definitions.get(key)
	if definition == null:
		last_error = "未知建筑类型：%s" % key
		return false
	if not _grid.can_place(origin, definition.footprint):
		last_error = "无法放置：越界、地形阻挡或已被占用"
		return false
	if not _economy.can_afford(definition.build_cost):
		last_error = "资源不足：%s" % _format_resources(definition.build_cost)
		return false

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
	building_placed.emit(instance)
	buildings_changed.emit()
	return true


func remove_building(instance_id: StringName) -> bool:
	last_error = ""
	var instance: BuildingInstance = instances.get(StringName(instance_id))
	if instance == null:
		last_error = "建筑不存在：%s" % instance_id
		return false

	_grid.release(instance.cells)
	instances.erase(instance.instance_id)
	_recompute_capacity()
	building_removed.emit(instance)
	buildings_changed.emit()
	return true


func get_definition(definition_id: StringName) -> BuildingDefinition:
	return definitions.get(StringName(definition_id))


func get_definitions() -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for key in definitions:
		result.append(definitions[key])
	return result


func get_building_count() -> int:
	return instances.size()


func _make_instance_id() -> StringName:
	var instance_id := StringName("building_%d" % _next_instance_number)
	_next_instance_number += 1
	return instance_id


func _recompute_capacity() -> void:
	if _economy != null:
		_economy.recompute_capacity(instances, definitions)


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
