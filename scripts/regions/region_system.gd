class_name RegionSystem
extends Node
## 区块数据层（M2）：把逻辑格映射为固定区块，并聚合只读统计。
##
## 区块只用于信息与指挥，不产生任何经济结果。统计必须从建筑实例与网格聚合：
## - 建筑数量与产出：按建筑锚点（origin_cell）归属的区块统计一次；
## - 占地面积：按每个被占用的逻辑格实际所属区块统计，跨区建筑会分摊到多个区块。

const REGION_SIZE: int = 8
const COLUMN_LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var regions_x: int = 0
var regions_y: int = 0
var map_width: int = 0
var map_height: int = 0


func setup(width: int, height: int) -> void:
	map_width = width
	map_height = height
	regions_x = ceili(float(map_width) / float(REGION_SIZE))
	regions_y = ceili(float(map_height) / float(REGION_SIZE))


func get_region_id(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(REGION_SIZE)),
		floori(float(cell.y) / float(REGION_SIZE))
	)


func get_region_origin(region_id: Vector2i) -> Vector2i:
	return region_id * REGION_SIZE


func get_region_size(region_id: Vector2i) -> Vector2i:
	var origin := get_region_origin(region_id)
	return Vector2i(
		clampi(map_width - origin.x, 0, REGION_SIZE),
		clampi(map_height - origin.y, 0, REGION_SIZE)
	)


func get_region_code(region_id: Vector2i) -> String:
	var column := COLUMN_LETTERS.substr(region_id.x % COLUMN_LETTERS.length(), 1)
	return "%s%d" % [column, region_id.y + 1]


func get_region_display_name(region_id: Vector2i) -> String:
	return "区块 %s" % get_region_code(region_id)


func get_region_count() -> int:
	return regions_x * regions_y


func is_region_inside_map(region_id: Vector2i) -> bool:
	return (
		region_id.x >= 0
		and region_id.y >= 0
		and region_id.x < regions_x
		and region_id.y < regions_y
	)


## 聚合一个区块的只读统计，供覆盖层与面板显示。
func get_region_stats(
	region_id: Vector2i,
	instances: Dictionary,
	definitions: Dictionary,
	grid: GridState
) -> Dictionary:
	var origin := get_region_origin(region_id)
	var size := get_region_size(region_id)
	var total_cells := maxi(0, size.x) * maxi(0, size.y)
	var occupied_cells := 0
	var buildable_cells := 0

	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var cell := Vector2i(x, y)
			if grid.occupied_cells.has(cell):
				occupied_cells += 1
			elif grid.is_terrain_buildable(cell):
				buildable_cells += 1

	var building_count := 0
	var type_counts: Dictionary = {}
	var output: Dictionary = {}
	var upkeep: Dictionary = {}

	for instance in instances.values():
		var building: BuildingInstance = instance
		if get_region_id(building.origin_cell) != region_id:
			continue

		building_count += 1
		var definition: BuildingDefinition = definitions.get(building.definition_id)
		if definition == null:
			continue

		var type_name := definition.display_name
		type_counts[type_name] = int(type_counts.get(type_name, 0)) + 1

		for resource_id in definition.output_per_tick:
			var output_key := String(resource_id)
			output[output_key] = (
				int(output.get(output_key, 0))
				+ int(definition.output_per_tick[resource_id])
			)
		for resource_id in definition.upkeep_per_tick:
			var upkeep_key := String(resource_id)
			upkeep[upkeep_key] = (
				int(upkeep.get(upkeep_key, 0))
				+ int(definition.upkeep_per_tick[resource_id])
			)

	return {
		"region_id": region_id,
		"code": get_region_code(region_id),
		"name": get_region_display_name(region_id),
		"total_cells": total_cells,
		"occupied_cells": occupied_cells,
		"buildable_cells": buildable_cells,
		"building_count": building_count,
		"type_counts": type_counts,
		"output": output,
		"upkeep": upkeep,
	}
