@tool
class_name MechTerrainView
extends Node2D
## Retained static terrain drawing; movement ticks do not redraw the map.

var _map: Dictionary = {}
var _font := SystemFont.new()

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
	queue_redraw()


func _init() -> void:
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])


func present_map(map_state: Dictionary) -> void:
	_map = map_state.duplicate(true)
	queue_redraw()


func _draw() -> void:
	if _map.is_empty():
		return
	var dimensions: Vector2i = _map["dimensions"]
	var terrain: PackedByteArray = _map["terrain"]
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			var cell := Vector2i(x, y)
			var kind: int = terrain[y * dimensions.x + x]
			var polygon: PackedVector2Array = MechIsoGeometry.footprint_polygon(cell, Vector2i.ONE)
			var fill := Color("122a34") if (x + y) % 2 == 0 else Color("142e38")
			if kind == MechGridState.Terrain.ROUGH:
				fill = Color("47493a") if (x + y) % 2 == 0 else Color("424535")
			elif kind == MechGridState.Terrain.OBSTACLE:
				fill = Color("293b49")
			draw_colored_polygon(polygon, fill)
			var outline: PackedVector2Array = polygon.duplicate()
			outline.append(polygon[0])
			draw_polyline(outline, Color(0.24, 0.40, 0.45, 0.25), 0.8, true)
			var center: Vector2 = MechIsoGeometry.cell_center(cell)
			if kind == MechGridState.Terrain.ROUGH:
				draw_line(center + Vector2(-11, 2), center + Vector2(-2, -3), Color("83816a"), 1.0, true)
				draw_line(center + Vector2(3, 5), center + Vector2(13, 0), Color("83816a"), 1.0, true)
	# Short rock facets on a second pass so later ground tiles never erase them.
	for diagonal: int in range(dimensions.x + dimensions.y - 1):
		for x: int in range(maxi(0, diagonal - dimensions.y + 1), mini(dimensions.x, diagonal + 1)):
			var y: int = diagonal - x
			if terrain[y * dimensions.x + x] == MechGridState.Terrain.OBSTACLE:
				_draw_rock(MechIsoGeometry.cell_center(Vector2i(x, y)), x + y)
	var border: PackedVector2Array = MechIsoGeometry.footprint_polygon(Vector2i.ZERO, dimensions)
	border.append(border[0])
	draw_polyline(border, Color("587b8c"), 2.0, true)
	_draw_marker(_map["main_gate"], "主口", Color("f0bc79"))
	_draw_marker(_map["flank"], "侧翼", Color("f0bc79"))
	_draw_marker(_map["mainbrain_origin"] + Vector2i(1, 5), "初始腹地", Color("72e9d0"))


func _draw_rock(center: Vector2, variation: int) -> void:
	var rise: float = 7.0 + float(variation % 3) * 2.0
	var peak: Vector2 = center + Vector2(-3, -rise - 9.0)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-24, 1), peak, center + Vector2(3, 10)]), Color("465b68"))
	draw_colored_polygon(PackedVector2Array([peak, center + Vector2(23, 0), center + Vector2(3, 10)]), Color("314653"))
	draw_line(center + Vector2(-24, 1), peak, Color("637783"), 1.0, true)


func _draw_marker(cell: Vector2i, text: String, color: Color) -> void:
	var point: Vector2 = MechIsoGeometry.cell_center(cell)
	draw_arc(point, 22.0, 0.0, TAU, 32, color, 2.0, true)
	draw_string(_font, point + Vector2(30, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, color)
