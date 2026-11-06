@tool
class_name MechFoundationView
extends Node2D
## Disposable projection of snapshots; never writes simulation state.

const CYAN := Color("72e9d0")

var _state: Dictionary = {}
var _preview: Dictionary = {}
var _hover: Vector2i = Vector2i(-1, -1)
var _selected: Vector2i = Vector2i(-1, -1)
var _cursor_visible: bool = false
var _selection_ids: Array[int] = []

@export var preview_map: MechMapDefinition:
	set(value):
		preview_map = value
		if is_inside_tree():
			_refresh_editor_preview()
@export_tool_button("刷新开局实体预览") var refresh_preview: Callable = _refresh_editor_preview


func _ready() -> void:
	_refresh_editor_preview()


func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_state.clear()
	if preview_map != null and preview_map.validation_error().is_empty():
		var center: Vector2 = Vector2(preview_map.mainbrain_origin) + Vector2(preview_map.mainbrain_footprint) * 0.5
		present({"minerals": preview_map.mineral_snapshots(), "entities": [
			{"kind": &"mainbrain", "position": center, "footprint": preview_map.mainbrain_footprint, "has_order": false},
			{"kind": &"probe", "position": Vector2(preview_map.probe_cell) + Vector2(0.5, 0.5), "has_order": false},
		]})
	queue_redraw()


func present(state: Dictionary) -> void:
	_state = state.duplicate(true)
	queue_redraw()


func present_selection(ids: Array[int]) -> void:
	_selection_ids = ids.duplicate()
	queue_redraw()


func _building_metrics(id: StringName) -> Vector3:
	match id:
		&"armored_wall": return Vector3(25, 31, 15.5)
		&"sentry_tower": return Vector3(30, 47, 23.5)
		&"mining_station": return Vector3(36, 47, 23.5)
		&"assembly_plant": return Vector3(48, 75, 37.5)
	return Vector3(58, 47, 23.5)


func pick_building(screen_point: Vector2) -> int:
	var entities: Array = _state.get("entities", []).duplicate()
	entities.sort_custom(_visual_sort)
	entities.reverse()
	for entity: Dictionary in entities:
		if not entity.get("is_building", false):
			continue
		var point: Vector2 = _project(entity["position"])
		var hull := PackedVector2Array()
		if entity["kind"] == &"mainbrain":
			hull = PackedVector2Array([Vector2(0, -100), Vector2(65, -68), Vector2(65, -20), Vector2(0, 12), Vector2(-65, -20), Vector2(-65, -68)])
		else:
			var metrics: Vector3 = _building_metrics(entity["kind"])
			var height: float = metrics.x
			if entity["phase"] == MechBuildingState.Phase.CONSTRUCTING:
				height *= 0.25 + float(entity["build_progress"]) * 0.75
			hull = PackedVector2Array([Vector2(0, -height - metrics.z), Vector2(metrics.y, -height), Vector2(metrics.y, 0), Vector2(0, metrics.z), Vector2(-metrics.y, 0), Vector2(-metrics.y, -height)])
		for index: int in range(hull.size()):
			hull[index] = get_global_transform_with_canvas() * (point + hull[index])
		if Geometry2D.is_point_in_polygon(screen_point, hull):
			return entity["id"]
	return 0


func present_cursor(hover: Vector2i, selected: Vector2i, preview: Dictionary, visible_cursor: bool) -> void:
	_hover = hover
	_selected = selected
	_preview = preview.duplicate(true)
	_cursor_visible = visible_cursor
	queue_redraw()


func _project(point: Vector2) -> Vector2:
	return MechIsoGeometry.project(point)


func _draw() -> void:
	if _state.is_empty():
		return
	_draw_minerals()
	_draw_cursor()
	var entities: Array = _state["entities"]
	for entity: Dictionary in entities:
		if (entity["has_order"] or entity.get("order", &"idle") in [&"move", &"attack_move"]) and entity.get("id", 0) in _selection_ids:
			_draw_target(entity)
	entities.sort_custom(_visual_sort)
	for entity: Dictionary in entities:
		var point: Vector2 = _project(entity["position"])
		if entity.get("id", 0) in _selection_ids:
			draw_arc(point, 23.0, 0.0, TAU, 36, CYAN, 2.0, true)
			var production: Dictionary = entity.get("production", {})
			if not production.is_empty():
				var rally: Vector2 = MechIsoGeometry.cell_center(production["rally"])
				draw_line(point, rally, Color(CYAN, 0.4), 1.5, true)
				draw_arc(rally, 16.0, 0.0, TAU, 24, CYAN, 2.0, true)
		if entity["kind"] == &"mainbrain":
			var footprint: Vector2i = entity["footprint"]
			var origin := Vector2i((entity["position"] - Vector2(footprint) * 0.5).floor())
			_outline_cell(origin, footprint, CYAN, 2.0)
			_draw_mainbrain(point)
		elif entity.get("is_building", false):
			_draw_building(entity, point)
		elif entity["kind"] == &"practice_target":
			_draw_practice_target(entity, point)
		elif entity.get("is_enemy", false):
			_draw_enemy(entity, point)
		elif entity.get("is_unit", false):
			_draw_sentinel(entity, point)
		else:
			_draw_probe(point)
		if entity.get("shot_ticks", 0) > 0:
			var target: Vector2 = _project(entity["shot_target"]) + Vector2(0, -20)
			draw_line(point + Vector2(0, -24), target, Color("f0d594"), 2.0, true)
			draw_circle(target, 5.0, Color("f0d594"))


func _draw_sentinel(entity: Dictionary, point: Vector2) -> void:
	_draw_shadow(point, Vector2(18, 9))
	var body := PackedVector2Array([point + Vector2(-12, -9), point + Vector2(-12, -29),
		point + Vector2(0, -36), point + Vector2(12, -29), point + Vector2(12, -9), point])
	draw_colored_polygon(body, Color("d8e0e4"))
	draw_line(point + Vector2(-7, -25), point + Vector2(7, -25), CYAN, 3.0, true)
	draw_line(point + Vector2(7, -18), point + Vector2(24, -26), Color("8d9ea9"), 5.0, true)
	if entity["hp"] < entity["max_hp"] or entity["id"] in _selection_ids:
		draw_rect(Rect2(point + Vector2(-18, -46), Vector2(36, 3)), Color("213540"))
		draw_rect(Rect2(point + Vector2(-18, -46), Vector2(36.0 * float(entity["hp"]) / entity["max_hp"], 3)), CYAN)


func _draw_practice_target(entity: Dictionary, point: Vector2) -> void:
	_draw_shadow(point, Vector2(25, 12))
	var body := PackedVector2Array([point + Vector2(-17, 0), point + Vector2(-17, -29),
		point + Vector2(0, -38), point + Vector2(17, -29), point + Vector2(17, 0), point + Vector2(0, 8)])
	draw_colored_polygon(body, Color("a9b1b7"))
	draw_line(point + Vector2(-9, -25), point + Vector2(9, -8), Color("f27c78"), 3.0, true)
	draw_line(point + Vector2(9, -25), point + Vector2(-9, -8), Color("f27c78"), 3.0, true)
	draw_rect(Rect2(point + Vector2(-23, -48), Vector2(46, 4)), Color("213540"))
	draw_rect(Rect2(point + Vector2(-23, -48), Vector2(46.0 * float(entity["hp"]) / entity["max_hp"], 4)), Color("f27c78"))


func _draw_enemy(entity: Dictionary, point: Vector2) -> void:
	_draw_shadow(point, Vector2(16, 8))
	var body := PackedVector2Array([point + Vector2(-10, -8), point + Vector2(-10, -24),
		point + Vector2(0, -32), point + Vector2(10, -24), point + Vector2(10, -8), point])
	draw_colored_polygon(body, Color("c9908b"))
	draw_line(point + Vector2(-6, -21), point + Vector2(6, -21), Color("7a2e28"), 3.0, true)
	draw_line(point + Vector2(-6, -13), point + Vector2(6, -13), Color("7a2e28"), 3.0, true)
	draw_rect(Rect2(point + Vector2(-16, -42), Vector2(32, 3)), Color("213540"))
	draw_rect(Rect2(point + Vector2(-16, -42), Vector2(32.0 * float(entity["hp"]) / entity["max_hp"], 3)), Color("f27c78"))


func _draw_minerals() -> void:
	for mineral: Dictionary in _state.get("minerals", []):
		if mineral["remaining"] <= 0 or mineral["assigned_to"] != 0:
			continue
		var point: Vector2 = MechIsoGeometry.cell_center(mineral["cell"])
		_outline_cell(mineral["cell"], Vector2i.ONE, Color("b9c5ce"), 2.0)
		for offset: Vector2 in [Vector2(-12, 0), Vector2(6, -6), Vector2(15, 5)]:
			var rock := PackedVector2Array([point + offset + Vector2(-10, 2), point + offset + Vector2(-2, -14), point + offset + Vector2(11, 2)])
			draw_colored_polygon(rock, Color("c4cdd2"))
			draw_line(point + offset + Vector2(-2, -14), point + offset + Vector2(0, 2), Color("85939c"), 2.0, true)


func _visual_sort(a: Dictionary, b: Dictionary) -> bool:
	var point_a: Vector2 = a["position"]
	var point_b: Vector2 = b["position"]
	return point_a.x + point_a.y < point_b.x + point_b.y


func _draw_target(entity: Dictionary) -> void:
	var goal: Vector2 = entity["order_goal"] if entity.get("order", &"idle") in [&"move", &"attack_move"] else entity["target"]
	var target: Vector2 = _project(goal)
	var line := PackedVector2Array([_project(entity["position"])])
	for waypoint: Vector2 in entity["path"]:
		line.append(_project(waypoint))
	if line.size() > 1:
		draw_polyline(line, Color(0.45, 0.91, 0.82, 0.45), 1.8, true)
	draw_arc(target, 14.0, 0.0, TAU, 32, CYAN, 1.5, true)
	draw_line(target + Vector2(-20.0, 0.0), target + Vector2(20.0, 0.0), CYAN, 1.0, true)
	draw_line(target + Vector2(0.0, -10.0), target + Vector2(0.0, 10.0), CYAN, 1.0, true)


func _draw_cursor() -> void:
	if _selected.x >= 0 and _selected.y >= 0:
		_outline_cell(_selected, Vector2i.ONE, Color("f0bc79"), 2.5)
	if not _cursor_visible:
		return
	if _preview.is_empty():
		_outline_cell(_hover, Vector2i.ONE, Color("e4f6f2"), 1.5)
		return
	for cell_info: Dictionary in _preview["cells"]:
		var color: Color = CYAN if cell_info["ok"] else Color("f27c78")
		draw_colored_polygon(MechIsoGeometry.footprint_polygon(cell_info["cell"], Vector2i.ONE), Color(color, 0.24))
		_outline_cell(cell_info["cell"], Vector2i.ONE, Color(color, 0.7), 1.5)
	if not _preview.get("line", false):
		_outline_cell(_preview["origin"], _preview["footprint"], CYAN if _preview["ok"] else Color("f27c78"), 2.5)
		if _preview.has("building_id"):
			var draft: Dictionary = {"building_id": _preview["building_id"], "footprint": _preview["footprint"],
				"phase": MechBuildingState.Phase.OPERATING, "build_progress": 1.0, "connections": 0}
			var center: Vector2 = Vector2(_preview["origin"]) + Vector2(_preview["footprint"]) * 0.5
			_draw_building(draft, _project(center), 0.35)


func _draw_building(building: Dictionary, point: Vector2, opacity: float = 1.0) -> void:
	var id: StringName = building["building_id"]
	var footprint: Vector2i = building["footprint"]
	var constructing: bool = building["phase"] == MechBuildingState.Phase.CONSTRUCTING
	var progress: float = building["build_progress"]
	var scale_height: float = 0.25 + progress * 0.75 if constructing else 1.0
	var color := Color("bdc8cd")
	var metrics: Vector3 = _building_metrics(id)
	var height: float = metrics.x
	var half_width: float = metrics.y
	var depth: float = metrics.z
	if id == &"armored_wall":
		color = Color("84939c")
	elif id == &"sentry_tower":
		color = Color("a9b6bf")
	elif id == &"mining_station":
		color = Color("d1d7da")
	elif id == &"assembly_plant":
		color = Color("c6d0d6")
	if building["phase"] == MechBuildingState.Phase.DEMOLISHING:
		color = Color("986c66")
	color.a = opacity * (0.45 + progress * 0.55 if constructing else 1.0)
	height *= scale_height
	_draw_shadow(point, Vector2(footprint.x * 29.0, footprint.y * 14.0))
	if id == &"armored_wall":
		var directions: Array[Vector2] = [Vector2(-32, -16), Vector2(32, -16), Vector2(32, 16), Vector2(-32, 16)]
		var mask: int = building.get("connections", 0)
		for index: int in range(directions.size()):
			if mask & (1 << index):
				draw_line(point + Vector2(0, -height), point + Vector2(0, -height) + directions[index] * 0.55, color.darkened(0.25), 11.0, true)
	var top := PackedVector2Array([point + Vector2(0, -height - depth), point + Vector2(half_width, -height),
		point + Vector2(0, -height + depth), point + Vector2(-half_width, -height)])
	draw_colored_polygon(PackedVector2Array([top[3], top[2], point + Vector2(0, depth), point + Vector2(-half_width, 0)]), color.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([top[2], top[1], point + Vector2(half_width, 0), point + Vector2(0, depth)]), color.darkened(0.5))
	draw_colored_polygon(top, color)
	var rim: PackedVector2Array = top.duplicate()
	rim.append(top[0])
	draw_polyline(rim, color.lightened(0.25), 1.5, true)
	if id == &"compute_node":
		for index: int in range(3):
			var offset := Vector2(-28.0 + index * 12.0, -height + 12.0 + index * 6.0)
			draw_line(point + offset, point + offset + Vector2(0, 14), Color(CYAN, color.a), 2.5, true)
	elif id == &"sentry_tower":
		var turret: Vector2 = point + Vector2(0, -height - 13.0 * scale_height)
		draw_circle(turret, 12.0 * scale_height, color.lightened(0.2))
		draw_line(turret, turret + Vector2(30, -15) * scale_height, color.lightened(0.1), 8.0, true)
	elif id == &"mining_station":
		var tip: Vector2 = point + Vector2(0, -height - 27.0 * scale_height)
		draw_line(point + Vector2(-19, -height), tip, Color("5e727e"), 5.0, true)
		draw_line(point + Vector2(19, -height), tip, Color("5e727e"), 5.0, true)
		draw_line(tip, tip + Vector2(0, 28) * scale_height, CYAN, 4.0, true)
	elif id == &"assembly_plant":
		draw_line(point + Vector2(8, -12), point + Vector2(8, 20), Color("536a79"), 15.0, true)
		draw_line(point + Vector2(26, -21), point + Vector2(26, 11), Color("536a79"), 15.0, true)
		draw_line(point + Vector2(-46, -height), point + Vector2(-12, -height + 17), CYAN, 4.0, true)
	if opacity < 1.0:
		return
	var bar_position: Vector2 = point + Vector2(-28.0, -height - depth - 12.0)
	if constructing or building["phase"] == MechBuildingState.Phase.DEMOLISHING:
		var fraction: float = progress if constructing else float(building["demolition_progress"])
		draw_rect(Rect2(bar_position, Vector2(56, 4)), Color("14232b"))
		draw_rect(Rect2(bar_position, Vector2(56.0 * fraction, 4)), CYAN if constructing else Color("f0bc79"))
	if building["hp"] < building["max_hp"]:
		bar_position.y -= 7.0
		var health: float = float(building["hp"]) / float(building["max_hp"])
		draw_rect(Rect2(bar_position, Vector2(56, 3)), Color("14232b"))
		draw_rect(Rect2(bar_position, Vector2(56.0 * health, 3)), Color("f0bc79"))


func _outline_cell(origin: Vector2i, footprint: Vector2i, color: Color, width: float) -> void:
	var polygon: PackedVector2Array = MechIsoGeometry.footprint_polygon(origin, footprint)
	polygon.append(polygon[0])
	draw_polyline(polygon, color, width, true)


func _draw_mainbrain(point: Vector2) -> void:
	_draw_shadow(point, Vector2(82.0, 34.0))
	var top := PackedVector2Array([point + Vector2(0, -100), point + Vector2(65, -68), point + Vector2(0, -36), point + Vector2(-65, -68)])
	var left := PackedVector2Array([point + Vector2(-65, -68), point + Vector2(0, -36), point + Vector2(0, 12), point + Vector2(-65, -20)])
	var right := PackedVector2Array([point + Vector2(0, -36), point + Vector2(65, -68), point + Vector2(65, -20), point + Vector2(0, 12)])
	draw_colored_polygon(left, Color("a3b0b8"))
	draw_colored_polygon(right, Color("748792"))
	draw_colored_polygon(top, Color("d6dfe3"))
	var rim: PackedVector2Array = top.duplicate()
	rim.append(top[0])
	draw_polyline(rim, CYAN, 2.0, true)
	draw_line(point + Vector2(0, -80), point + Vector2(0, -57), CYAN, 4.0, true)
	draw_line(point + Vector2(-20, -69), point + Vector2(20, -69), CYAN, 4.0, true)
	draw_circle(point + Vector2(-43, -31), 3.0, CYAN)
	draw_circle(point + Vector2(-29, -24), 3.0, CYAN)


func _draw_probe(point: Vector2) -> void:
	_draw_shadow(point, Vector2(24.0, 11.0))
	draw_arc(point, 23.0, 0.0, TAU, 40, Color(0.45, 0.91, 0.82, 0.45), 1.0, true)
	var body := PackedVector2Array([point + Vector2(0, -29), point + Vector2(14, -18), point + Vector2(10, -6), point + Vector2(-10, -6), point + Vector2(-14, -18)])
	draw_colored_polygon(body, Color("d9f2ec"))
	draw_line(point + Vector2(-7, -16), point + Vector2(7, -16), Color("173942"), 4.0, true)
	draw_circle(point + Vector2(0, -17), 2.0, CYAN)


func _draw_shadow(point: Vector2, radius: Vector2) -> void:
	var polygon := PackedVector2Array()
	for index: int in range(32):
		var angle: float = TAU * float(index) / 32.0
		polygon.append(point + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(polygon, Color(0.0, 0.0, 0.0, 0.35))
