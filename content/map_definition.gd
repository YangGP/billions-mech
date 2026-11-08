@tool
class_name MechMapDefinition
extends Resource
## Hand-authored rectangular terrain stamps, not a random map generator.

@export var map_id: StringName = &"development_basin_128"
@export var display_name: String = "四隘盆地 · 128开发图"
@export var dimensions: Vector2i = Vector2i(128, 128)
## Clockwise boundary in logical coordinates; edges are north/east/south/west.
## Empty preserves the rectangular grid used by older maps.
@export var playable_polygon := PackedVector2Array()
@export_range(0.0, 64.0, 1.0) var wanderer_exclusion_radius: float = 20.0
@export var obstacle_rects: Array[Rect2i] = []
@export var rough_rects: Array[Rect2i] = []
## Explicit environment layers. Water is also forced to obstacle terrain;
## wind is a scoring/visual layer and does not change movement.
@export var wind_cells: Array[Vector2i] = []
@export var water_cells: Array[Vector2i] = []
@export_range(1.0, 10.0, 0.1) var rough_movement_weight: float = 2.0
@export var mainbrain_origin: Vector2i = Vector2i(61, 61)
@export var mainbrain_footprint: Vector2i = Vector2i(5, 5)
@export var probe_cell: Vector2i = Vector2i(60, 68)
@export var main_gate: Vector2i = Vector2i(64, 43)
@export var flank: Vector2i = Vector2i(89, 64)
@export var minerals: Array[MechMineralDefinition] = []


func validation_error() -> String:
	if dimensions.x < 8 or dimensions.y < 8 or dimensions.x > 256 or dimensions.y > 256:
		return "地图尺寸必须在 8–256 格之间"
	var bounds := Rect2i(Vector2i.ZERO, dimensions)
	if not playable_polygon.is_empty():
		if playable_polygon.size() != 4 or Geometry2D.triangulate_polygon(playable_polygon).size() != 6:
			return "可玩边界必须是有效的四边形"
		for point: Vector2 in playable_polygon:
			if not point.is_finite() or point.x < 0 or point.y < 0 or point.x > dimensions.x or point.y > dimensions.y:
				return "可玩边界超出网格"
	if not is_finite(wanderer_exclusion_radius) or wanderer_exclusion_radius < 0.0:
		return "基地游荡敌禁刷半径无效"
	if mainbrain_footprint.x < 1 or mainbrain_footprint.y < 1:
		return "主脑占地无效"
	if not bounds.encloses(Rect2i(mainbrain_origin, mainbrain_footprint)):
		return "主脑占地超出地图"
	for y: int in range(mainbrain_footprint.y):
		for x: int in range(mainbrain_footprint.x):
			if not contains_cell(mainbrain_origin + Vector2i(x, y)):
				return "主脑占地超出可玩边界"
	for cell: Vector2i in [probe_cell, main_gate, flank]:
		if not contains_cell(cell):
			return "出生点或地图标记超出边界"
	for rectangles: Array[Rect2i] in [obstacle_rects, rough_rects]:
		for rectangle: Rect2i in rectangles:
			if rectangle.size.x < 1 or rectangle.size.y < 1 or not bounds.encloses(rectangle):
				return "地形区域超出地图或尺寸无效"
	for cell: Vector2i in wind_cells:
		if not bounds.has_point(cell) or not contains_cell(cell):
			return "风口格超出可玩边界"
		if Rect2i(mainbrain_origin, mainbrain_footprint).has_point(cell):
			return "风口格与主脑重叠"
	for cell: Vector2i in water_cells:
		if not bounds.has_point(cell) or not contains_cell(cell):
			return "水域格超出可玩边界"
		if Rect2i(mainbrain_origin, mainbrain_footprint).has_point(cell):
			return "水域格与主脑重叠"
	if not is_finite(rough_movement_weight) or rough_movement_weight < 1.0:
		return "崎岖地移动权重无效"
	var ids: Dictionary = {}
	var occupied_cells: Dictionary = {}
	var terrain: PackedByteArray = terrain_cells()
	for mineral: MechMineralDefinition in minerals:
		if mineral == null or mineral.mineral_id == &"" or mineral.amount < 1:
			return "矿点定义或储量无效"
		if not MechResources.mineable(StringName(mineral.resource_kind)):
			return "矿点类型无效"
		if not contains_cell(mineral.cell) or Rect2i(mainbrain_origin, mainbrain_footprint).has_point(mineral.cell):
			return "矿点超界或与主脑重叠"
		if terrain[mineral.cell.y * dimensions.x + mineral.cell.x] != MechGridState.Terrain.OPEN:
			return "矿点必须位于可建造地形"
		if ids.has(mineral.mineral_id) or occupied_cells.has(mineral.cell):
			return "矿点编号或位置重复"
		ids[mineral.mineral_id] = true
		occupied_cells[mineral.cell] = true
	return ""


func outline() -> PackedVector2Array:
	if not playable_polygon.is_empty():
		return playable_polygon.duplicate()
	return PackedVector2Array([Vector2.ZERO, Vector2(dimensions.x, 0), Vector2(dimensions), Vector2(0, dimensions.y)])


func contains_cell(cell: Vector2i) -> bool:
	if not Rect2i(Vector2i.ZERO, dimensions).has_point(cell):
		return false
	if playable_polygon.is_empty():
		return true
	# Gameplay uses complete tiles, so spawn bodies and building footprints
	# never start on a tile cut in half by the visible boundary.
	for offset: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		if not Geometry2D.is_point_in_polygon(Vector2(cell) + offset, playable_polygon):
			return false
	return true


func playable_cells() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(dimensions.x * dimensions.y)
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			mask[y * dimensions.x + x] = int(contains_cell(Vector2i(x, y)))
	return mask


func wanderer_spawn_allowed(point: Vector2) -> bool:
	var core := Rect2(Vector2(mainbrain_origin), Vector2(mainbrain_footprint))
	return point.distance_squared_to(point.clamp(core.position, core.end)) > wanderer_exclusion_radius * wanderer_exclusion_radius


func terrain_cells() -> PackedByteArray:
	# Shared by the editor preview and the authoritative runtime grid.
	var cells := PackedByteArray()
	cells.resize(dimensions.x * dimensions.y)
	cells.fill(MechGridState.Terrain.OPEN)
	for kind: int in [MechGridState.Terrain.ROUGH, MechGridState.Terrain.OBSTACLE]:
		var rectangles: Array[Rect2i] = rough_rects if kind == MechGridState.Terrain.ROUGH else obstacle_rects
		for rectangle: Rect2i in rectangles:
			for y: int in range(rectangle.position.y, rectangle.end.y):
				for x: int in range(rectangle.position.x, rectangle.end.x):
					cells[y * dimensions.x + x] = kind
	for cell: Vector2i in water_cells:
		if Rect2i(Vector2i.ZERO, dimensions).has_point(cell):
			cells[cell.y * dimensions.x + cell.x] = MechGridState.Terrain.OBSTACLE
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			if not contains_cell(Vector2i(x, y)):
				cells[y * dimensions.x + x] = MechGridState.Terrain.OBSTACLE
	return cells


func wind_mask() -> PackedByteArray:
	return _cell_mask(wind_cells)


func water_mask() -> PackedByteArray:
	return _cell_mask(water_cells)


func _cell_mask(cells: Array[Vector2i]) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(dimensions.x * dimensions.y)
	mask.fill(0)
	for cell: Vector2i in cells:
		if Rect2i(Vector2i.ZERO, dimensions).has_point(cell):
			mask[cell.y * dimensions.x + cell.x] = 1
	return mask


func terrain_snapshot() -> Dictionary:
	return {"dimensions": dimensions, "terrain": terrain_cells(), "name": display_name,
		"playable": playable_cells(), "outline": outline(),
		"wind": wind_mask(), "water": water_mask(),
		"main_gate": main_gate, "flank": flank, "mainbrain_origin": mainbrain_origin,
		"mainbrain_footprint": mainbrain_footprint, "minerals": mineral_snapshots()}


func mineral_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mineral: MechMineralDefinition in minerals:
		result.append(mineral.snapshot())
	return result
