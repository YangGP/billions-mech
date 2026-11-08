@tool
class_name MechTerrainView
extends Node2D
## Static terrain is rendered once into a native SubViewport texture.
## Camera movement samples a Sprite2D instead of replaying all tile draw calls.

var _map: Dictionary = {}
var _font := SystemFont.new()
var _cache_viewport: SubViewport
var _cache_sprite: Sprite2D
var _painter: Node2D
var _labels: Node2D
var _known_markers: Dictionary = {}
const CACHE_MARGIN: float = 160.0
const MAX_CACHE_SIDE: float = 4096.0

@export var preview_map: MechMapDefinition:
	set(value):
		preview_map = value
		if is_inside_tree():
			_refresh_editor_preview()
@export_tool_button("刷新地图预览") var refresh_preview: Callable = _refresh_editor_preview


func _ready() -> void:
	_refresh_editor_preview()


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


func _paint_map() -> void:
	if _map.is_empty():
		return
	var dimensions: Vector2i = _map["dimensions"]
	var terrain: PackedByteArray = _map["terrain"]
	var playable: PackedByteArray = _map["playable"]
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
			var fill := Color("122a34") if (x + y) % 2 == 0 else Color("142e38")
			if kind == MechGridState.Terrain.ROUGH:
				fill = Color("47493a") if (x + y) % 2 == 0 else Color("424535")
			elif kind == MechGridState.Terrain.OBSTACLE:
				fill = Color("293b49")
			_painter.draw_colored_polygon(polygon, fill)
			var outline: PackedVector2Array = polygon.duplicate()
			outline.append(polygon[0])
			_painter.draw_polyline(outline, Color(0.59, 0.61, 0.53, 0.22), 0.9, true)
			var center: Vector2 = MechIsoGeometry.cell_center(cell)
			if kind == MechGridState.Terrain.ROUGH:
				_painter.draw_line(center + Vector2(-11, 2), center + Vector2(-2, -3), Color("83816a"), 1.0, true)
				_painter.draw_line(center + Vector2(3, 5), center + Vector2(13, 0), Color("83816a"), 1.0, true)
	# Short rock facets on a second pass so later ground tiles never erase them.
	for diagonal: int in range(dimensions.x + dimensions.y - 1):
		for x: int in range(maxi(0, diagonal - dimensions.y + 1), mini(dimensions.x, diagonal + 1)):
			var y: int = diagonal - x
			if playable[y * dimensions.x + x] != 0 and terrain[y * dimensions.x + x] == MechGridState.Terrain.OBSTACLE:
				_draw_rock(MechIsoGeometry.cell_center(Vector2i(x, y)), x + y, boundary)
	# A boundary stroke extends outside the fog polygon and leaks unexplored
	# map edges. Keep that authoring guide in the editor only.
	if Engine.is_editor_hint():
		var border: PackedVector2Array = boundary.duplicate()
		border.append(border[0])
		_painter.draw_polyline(border, Color("587b8c"), 2.0, true)


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


func _draw_marker(cell: Vector2i, text: String, color: Color) -> void:
	var point: Vector2 = MechIsoGeometry.cell_center(cell)
	_labels.draw_arc(point, 22.0, 0.0, TAU, 32, color, 2.0, true)
	_labels.draw_string(_font, point + Vector2(30, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, color)
