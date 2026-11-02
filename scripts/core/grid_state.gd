class_name GridState
extends RefCounted
## 二维逻辑网格：占地、地形阻挡与建造合法性判断的唯一来源。
##
## 建筑占地始终按「左上逻辑格 origin + footprint」计算，与贴图像素尺寸无关。
## 键使用 Vector2i，值是建筑实例 ID（StringName）。

var map_width: int
var map_height: int
## Vector2i -> StringName（建筑实例 ID）
var occupied_cells: Dictionary = {}
## Vector2i -> true（不可建造地形，例如森林、水面）
var blocked_cells: Dictionary = {}


func _init(width: int = 32, height: int = 32) -> void:
	map_width = maxi(1, width)
	map_height = maxi(1, height)


func is_inside_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_width and cell.y < map_height


func is_terrain_buildable(cell: Vector2i) -> bool:
	return not blocked_cells.has(cell)


func set_terrain_blocked(cells: Array[Vector2i], blocked: bool) -> void:
	for cell in cells:
		if blocked:
			blocked_cells[cell] = true
		else:
			blocked_cells.erase(cell)


## 返回 footprint 覆盖的全部格子（左上角为 origin）。
func cells_for_footprint(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			cells.append(origin + Vector2i(x, y))
	return cells


## 仅检查占地合法性：范围、重叠、地形。资源与建设范围由上层系统另行校验。
func can_place(origin: Vector2i, size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	for cell in cells_for_footprint(origin, size):
		if not is_inside_map(cell):
			return false
		if occupied_cells.has(cell):
			return false
		if not is_terrain_buildable(cell):
			return false
	return true


func occupy(cells: Array[Vector2i], instance_id: StringName) -> void:
	for cell in cells:
		occupied_cells[cell] = instance_id


func release(cells: Array[Vector2i]) -> void:
	for cell in cells:
		occupied_cells.erase(cell)


## 兜底清理：按实例 ID 释放所有格子，避免出现“幽灵占地”。
func release_all_for(instance_id: StringName) -> void:
	for cell in occupied_cells.keys():
		if occupied_cells[cell] == instance_id:
			occupied_cells.erase(cell)


func get_occupant(cell: Vector2i) -> StringName:
	return occupied_cells.get(cell, &"")


func get_occupied_count() -> int:
	return occupied_cells.size()
