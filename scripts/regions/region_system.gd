class_name RegionSystem
extends Node
## 区块数据层（M2）：把逻辑格映射为固定区块。
##
## 当前只提供划分与命名，不做统计、不产生任何经济结果。
## 区块统计必须从 GameState 的建筑实例聚合，绝不能另开一套经济数据。

## 每 8×8 逻辑格为一个区块；32×32 地图会得到 4×4 个区块。
const REGION_SIZE: int = 8

var regions_x: int = 0
var regions_y: int = 0


func setup(map_width: int, map_height: int) -> void:
	regions_x = ceili(float(map_width) / float(REGION_SIZE))
	regions_y = ceili(float(map_height) / float(REGION_SIZE))


func get_region_id(cell: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(cell.x) / float(REGION_SIZE)),
		floori(float(cell.y) / float(REGION_SIZE))
	)


func get_region_display_name(region_id: Vector2i) -> String:
	return "区块 %d-%d" % [region_id.x + 1, region_id.y + 1]


func is_region_inside_map(region_id: Vector2i) -> bool:
	return region_id.x >= 0 and region_id.y >= 0 and region_id.x < regions_x and region_id.y < regions_y
