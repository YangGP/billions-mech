class_name MechEnvironmentEnergy
extends RefCounted
## 风冷/太阳能的集能区计分与同类型预留。计分只读取地图地形与探索状态，
## 绝不读取实时敌人或单位状态。

## 集能区向建筑脚印外扩的格数。
const EXTENSION: int = 3
## 风冷/太阳能的环境输出上限。
const WIND_CAP: int = 18
const SOLAR_CAP: int = 20

## 索引结构：energy_type（能量类型）→ { 格子坐标: 实体 ID }。
var _reserved: Dictionary[StringName, Dictionary] = {}


## 清空全部预留。
func clear() -> void:
	_reserved.clear()


## 建筑的集能区范围：脚印向外扩 EXTENSION 格。
func collection_bounds(origin: Vector2i, footprint: Vector2i) -> Rect2i:
	return Rect2i(origin - Vector2i(EXTENSION, EXTENSION), footprint + Vector2i(EXTENSION * 2, EXTENSION * 2))


## 列出集能区内被其他同类型建筑占用的格子；ignore_id 用于排除自身。
func conflicts(energy_type: StringName, origin: Vector2i, footprint: Vector2i, ignore_id: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if energy_type == &"" or energy_type == &"none":
		return result
	var occupied: Dictionary = _reserved.get(energy_type, {})
	var bounds: Rect2i = collection_bounds(origin, footprint)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var owner: int = int(occupied.get(Vector2i(x, y), 0))
			if owner != 0 and owner != ignore_id:
				result.append(Vector2i(x, y))
	return result


## 为建筑预留整个集能区；与同类型既有预留冲突则失败。
func reserve(entity_id: int, energy_type: StringName, origin: Vector2i, footprint: Vector2i) -> bool:
	if energy_type == &"" or energy_type == &"none":
		return true
	if not conflicts(energy_type, origin, footprint, entity_id).is_empty():
		return false
	var occupied: Dictionary = _reserved.get(energy_type, {})
	var bounds: Rect2i = collection_bounds(origin, footprint)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			occupied[Vector2i(x, y)] = entity_id
	_reserved[energy_type] = occupied
	return true


## 解除某实体的全部集能区预留；清空的类型键随之移除。
func release(entity_id: int) -> void:
	for energy_type: StringName in _reserved.keys():
		var occupied: Dictionary = _reserved[energy_type]
		for cell: Vector2i in occupied.keys():
			if int(occupied[cell]) == entity_id:
				occupied.erase(cell)
		if occupied.is_empty():
			_reserved.erase(energy_type)
		else:
			_reserved[energy_type] = occupied


## 计算建筑当前集能区的发电功率：只统计已探索、非障碍且不在自身脚印内的格子。
## multiplier 为升级倍率，cap 为正时覆盖默认上限。
func score(energy_type: StringName, origin: Vector2i, footprint: Vector2i, grid: MechGridState, vision: MechVisionSystem, multiplier: int = 1, cap: int = 0) -> int:
	if energy_type == &"" or energy_type == &"none" or grid == null or vision == null:
		return 0
	var points: int = 0
	var body := Rect2i(origin, footprint)
	var bounds: Rect2i = collection_bounds(origin, footprint)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if not grid.contains(cell) or body.has_point(cell):
				continue
			if vision.state_at(cell) == MechVisionSystem.State.UNEXPLORED:
				continue
			var terrain: int = grid.terrain_at(cell)
			if terrain == MechGridState.Terrain.OBSTACLE:
				continue
			if energy_type == &"wind":
				# 显式风区格与崎岖地形是高分格；同一格只计一次，不叠加。
				points += 2 if grid.is_wind(cell) or terrain == MechGridState.Terrain.ROUGH else 1
			elif energy_type == &"solar":
				if terrain == MechGridState.Terrain.OPEN:
					points += 1
	if energy_type == &"wind":
		var base_power: int = mini(WIND_CAP, points / 4)
		return mini(cap if cap > 0 else WIND_CAP, base_power * maxi(1, multiplier))
	if energy_type == &"solar":
		var base_power: int = mini(SOLAR_CAP, points / 2)
		return mini(cap if cap > 0 else SOLAR_CAP, base_power * maxi(1, multiplier))
	return 0
