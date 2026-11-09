@tool
class_name MechTerrainView
extends Node2D
## 静态地形一次性渲染进原生 SubViewport 纹理；
## 镜头移动只采样一张 Sprite2D，而不重放全部瓦片绘制调用。

var _map: Dictionary = {}
var _font := SystemFont.new()
var _cache_viewport: SubViewport
var _cache_sprite: Sprite2D
var _painter: Node2D
var _labels: Node2D
## 已探索过一次的关键地标（主口、侧翼、初始腹地），解锁后常驻绘制。
var _known_markers: Dictionary = {}
## 缓存纹理向外扩的留白（像素），避免边缘被裁。
const CACHE_MARGIN: float = 160.0
## 缓存纹理单边上限（像素），超大地困自动降分辨率。
const MAX_CACHE_SIDE: float = 4096.0

@export var preview_map: MechMapDefinition:
	set(value):
		preview_map = value
		if is_inside_tree():
			_refresh_editor_preview()
@export_tool_button("刷新地图预览") var refresh_preview: Callable = _refresh_editor_preview


func _ready() -> void:
	_refresh_editor_preview()


## 编辑器预览刷新：仅在编辑器环境下按 preview_map 重绘。
func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_map.clear()
	if preview_map != null and preview_map.validation_error().is_empty():
		present_map(preview_map.terrain_snapshot())
	elif _cache_sprite != null:
		_cache_sprite.hide()


func _init() -> void:
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])


## 接收地形快照并重建缓存纹理（懒创建 SubViewport 管线）。
func present_map(map_state: Dictionary) -> void:
	_map = map_state.duplicate(true)
	_known_markers.clear()
	if not is_inside_tree():
		return
	if _cache_viewport == null:
		_cache_viewport = SubViewport.new()
		_cache_viewport.disable_3d = true
		_cache_viewport.transparent_bg = true
		_cache_viewport.gui_disable_input = true
		_cache_viewport.world_2d = World2D.new()
		add_child(_cache_viewport)
		_painter = Node2D.new()
		_cache_viewport.add_child(_painter)
		_painter.draw.connect(_paint_map)
		_cache_sprite = Sprite2D.new()
		_cache_sprite.centered = false
		_cache_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_cache_sprite.texture = _cache_viewport.get_texture()
		add_child(_cache_sprite)
		_labels = Node2D.new()
		add_child(_labels)
		_labels.draw.connect(_draw_markers)
	var bounds: Rect2 = MechIsoGeometry.map_bounds(_map["dimensions"], _map["outline"]).grow(CACHE_MARGIN)
	var resolution: float = minf(1.0, MAX_CACHE_SIDE / maxf(bounds.size.x, bounds.size.y))
	_cache_viewport.size = Vector2i((bounds.size * resolution).ceil())
	_painter.position = -bounds.position * resolution
	_painter.scale = Vector2.ONE * resolution
	_cache_sprite.position = bounds.position
	_cache_sprite.scale = Vector2.ONE / resolution
	_cache_sprite.show()
	_painter.queue_redraw()
	_cache_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_labels.queue_redraw()


## 依据视野快照解锁关键地标的常驻标记。
func present_vision(vision: Dictionary) -> void:
	var cells: PackedByteArray = vision["cells"]
	var dimensions: Vector2i = vision["dimensions"]
	var changed: bool = false
	for cell: Vector2i in [_map["main_gate"], _map["flank"], _map["mainbrain_origin"] + Vector2i(1, 5)]:
		if Rect2i(Vector2i.ZERO, dimensions).has_point(cell) and cells[cell.y * dimensions.x + cell.x] != MechVisionSystem.State.UNEXPLORED and not _known_markers.has(cell):
			_known_markers[cell] = true
			changed = true
	if changed:
		_labels.queue_redraw()


## 地形绘制主体：底色棋盘格 → 水/风/崎岖/岩石瓦片 → 岩石立面 → 编辑器描边。
func _paint_map() -> void:
	if _map.is_empty():
		return
	var dimensions: Vector2i = _map["dimensions"]
	var terrain: PackedByteArray = _map["terrain"]
	var playable: PackedByteArray = _map["playable"]
	var wind: PackedByteArray = _map.get("wind", PackedByteArray())
	var water: PackedByteArray = _map.get("water", PackedByteArray())
	var boundary: PackedVector2Array = MechIsoGeometry.project_polygon(_map["outline"])
	_painter.draw_colored_polygon(boundary, Color("122a34"))
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			if playable[y * dimensions.x + x] == 0:
				continue
			var cell := Vector2i(x, y)
			var kind: int = terrain[y * dimensions.x + x]
			var polygon: PackedVector2Array = MechIsoGeometry.footprint_polygon(cell, Vector2i.ONE)
			var edge: bool = false
			for point: Vector2 in polygon:
				if not Geometry2D.is_point_in_polygon(point, boundary):
					edge = true
					break
			if edge:
				var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(polygon, boundary)
				if clipped.is_empty() or clipped[0].size() < 3:
					continue
				polygon = clipped[0]
			var is_water: bool = not water.is_empty() and water[y * dimensions.x + x] != 0
			var is_wind: bool = not wind.is_empty() and wind[y * dimensions.x + x] != 0
			var fill := Color("122a34") if (x + y) % 2 == 0 else Color("142e38")
			if is_water:
				fill = Color("183a55") if (x + y) % 2 == 0 else Color("17364e")
			elif kind == MechGridState.Terrain.ROUGH:
				fill = Color("47493a") if (x + y) % 2 == 0 else Color("424535")
			elif kind == MechGridState.Terrain.OBSTACLE:
				fill = Color("293b49")
			_painter.draw_colored_polygon(polygon, fill)
			var outline: PackedVector2Array = polygon.duplicate()
			outline.append(polygon[0])
			_painter.draw_polyline(outline, Color(0.59, 0.61, 0.53, 0.22), 0.9, true)
			var center: Vector2 = MechIsoGeometry.cell_center(cell)
			if is_water:
				_painter.draw_line(center + Vector2(-12, 1), center + Vector2(-1, 1), Color("6fb4d6"), 1.0, true)
				_painter.draw_line(center + Vector2(3, 5), center + Vector2(13, 5), Color("5a9ec0"), 1.0, true)
			elif is_wind:
				_painter.draw_line(center + Vector2(-12, 4), center + Vector2(1, -3), Color("8fe6d6"), 1.2, true)
				_painter.draw_line(center + Vector2(2, 6), center + Vector2(13, 0), Color("65c8ba"), 1.0, true)
			elif kind == MechGridState.Terrain.ROUGH:
				_painter.draw_line(center + Vector2(-11, 2), center + Vector2(-2, -3), Color("83816a"), 1.0, true)
				_painter.draw_line(center + Vector2(3, 5), center + Vector2(13, 0), Color("83816a"), 1.0, true)
	# 岩石短立面放第二轮绘制，后续地面瓦片不会覆盖它们。
	for diagonal: int in range(dimensions.x + dimensions.y - 1):
		for x: int in range(maxi(0, diagonal - dimensions.y + 1), mini(dimensions.x, diagonal + 1)):
			var y: int = diagonal - x
			if playable[y * dimensions.x + x] != 0 and terrain[y * dimensions.x + x] == MechGridState.Terrain.OBSTACLE \
					and (water.is_empty() or water[y * dimensions.x + x] == 0):
				_draw_rock(MechIsoGeometry.cell_center(Vector2i(x, y)), x + y, boundary)
	# 边界描边会伸出迷雾多边形、漏出未探索的地图边缘；该编辑辅助只在编辑器绘制。
	if Engine.is_editor_hint():
		var border: PackedVector2Array = boundary.duplicate()
		border.append(border[0])
		_painter.draw_polyline(border, Color("587b8c"), 2.0, true)


## 绘制已解锁的地标圆圈与文字；编辑器内始终全量显示。
func _draw_markers() -> void:
	if _map.is_empty():
		return
	if Engine.is_editor_hint() or _known_markers.has(_map["main_gate"]):
		_draw_marker(_map["main_gate"], "主口", Color("f0bc79"))
	if Engine.is_editor_hint() or _known_markers.has(_map["flank"]):
		_draw_marker(_map["flank"], "侧翼", Color("f0bc79"))
	var belly: Vector2i = _map["mainbrain_origin"] + Vector2i(1, 5)
	if Engine.is_editor_hint() or _known_markers.has(belly):
		_draw_marker(belly, "初始腹地", Color("72e9d0"))


## 绘制单块岩石的两个短立面（按位置取变体高度），并按边界裁剪。
func _draw_rock(center: Vector2, variation: int, boundary: PackedVector2Array) -> void:
	var rise: float = 7.0 + float(variation % 3) * 2.0
	var peak: Vector2 = center + Vector2(-3, -rise - 9.0)
	var facets: Array[PackedVector2Array] = [PackedVector2Array([center + Vector2(-24, 1), peak, center + Vector2(3, 10)]),
		PackedVector2Array([peak, center + Vector2(23, 0), center + Vector2(3, 10)])]
	var colors: Array[Color] = [Color("465b68"), Color("314653")]
	for index: int in range(facets.size()):
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(facets[index], boundary):
			if clipped.size() >= 3:
				_painter.draw_colored_polygon(clipped, colors[index])
	for segment: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([center + Vector2(-24, 1), peak]), boundary):
		if segment.size() >= 2:
			_painter.draw_polyline(segment, Color("637783"), 1.0, true)


## 绘制单个地标：圆圈加右侧文字。
func _draw_marker(cell: Vector2i, text: String, color: Color) -> void:
	var point: Vector2 = MechIsoGeometry.cell_center(cell)
	_labels.draw_arc(point, 22.0, 0.0, TAU, 32, color, 2.0, true)
	_labels.draw_string(_font, point + Vector2(30, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, color)
