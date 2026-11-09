class_name MechMinimapView
extends Control
## 小地图只读模型：地形/迷雾纹理 + 快照圆点 + 镜头取景框。
## 全部数据经 present_* 到达；视图绝不读取模拟层。
## 全屏模式兼作区域管理操作面，因此一切按当前控件尺寸计算。

signal focus_requested(world_position: Vector2)
signal region_selected(cells: Array[Vector2i])

const TERRAIN_OPEN := Color("16323c")
const TERRAIN_ROUGH := Color("3f4433")
const TERRAIN_OBSTACLE := Color("243b47")
const TERRAIN_VOID := Color("0b1218")
const MINERAL := Color("f0bc79")
const OWN_BUILDING := Color("d5e6eb")
const OWN_UNIT := Color("72e9d0")
const ENEMY := Color("f27c78")
const MAINBRAIN := Color("72e9d0")
const CAMERA_FRAME := Color(1.0, 1.0, 1.0, 0.85)
const REGION_ENABLED := Color(0.45, 0.9, 0.78, 0.35)
const REGION_DISABLED := Color(0.55, 0.6, 0.6, 0.22)

var _dimensions := Vector2i.ZERO
var _outline := PackedVector2Array()
var _bounds := Rect2()
var _terrain_texture: ImageTexture
var _terrain_cache := PackedByteArray()
var _playable_cache := PackedByteArray()
var _fog_texture: ImageTexture
var _fog_revision: int = -1
var _fog_generation: int = -1
var _state: Dictionary = {}
var _map: Dictionary = {}
var _camera_rect := Rect2()
var _map_scale: float = 1.0
var _map_offset := Vector2.ZERO
var _polygon := PackedVector2Array()
var _uvs := PackedVector2Array()
var _dragging: bool = false
## 区域框选模式：左键拖出一个格子矩形并发出 region_selected。
var _region_mode: bool = false
var _region_start := Vector2.ZERO
var _region_end := Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recompute_fit()


func present_map(map_state: Dictionary) -> void:
	_map = {"mainbrain_origin": map_state["mainbrain_origin"], "mainbrain_footprint": map_state["mainbrain_footprint"]}
	var dimensions: Vector2i = map_state["dimensions"]
	if dimensions != _dimensions or map_state["outline"] != _outline:
		_dimensions = dimensions
		_outline = map_state["outline"].duplicate()
		_bounds = MechIsoGeometry.map_bounds(_dimensions, _outline)
		_recompute_fit()
	_rebuild_terrain_texture(map_state)
	queue_redraw()


func present_state(state: Dictionary) -> void:
	_state = state
	var vision: Dictionary = state["vision"]
	if _fog_revision != vision["revision"] or _fog_generation != state["generation"]:
		_fog_revision = vision["revision"]
		_fog_generation = state["generation"]
		_rebuild_fog_texture(vision)
	queue_redraw()


func present_camera(rect: Rect2) -> void:
	if rect.is_equal_approx(_camera_rect):
		return
	_camera_rect = rect
	queue_redraw()


func set_region_mode(enabled: bool) -> void:
	_region_mode = enabled
	_dragging = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _region_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_region_start = event.position
				_region_end = event.position
				_dragging = true
			elif _dragging:
				_dragging = false
				_region_end = event.position
				_emit_region()
			accept_event()
		elif _dragging and event is InputEventMouseMotion:
			_region_end = event.position
			queue_redraw()
			accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_emit_focus(event.position)
		accept_event()
	elif _dragging and event is InputEventMouseMotion:
		_dragging = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if not _dragging:
			return
		_emit_focus(event.position)
		accept_event()


func _emit_region() -> void:
	var a: Vector2i = MechIsoGeometry.cell_at(_local_to_world(_region_start))
	var b: Vector2i = MechIsoGeometry.cell_at(_local_to_world(_region_end))
	var low := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var high := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var cells: Array[Vector2i] = []
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			cells.append(Vector2i(x, y))
	region_selected.emit(cells)
	_region_mode = false
	queue_redraw()


func _draw() -> void:
	if _polygon.size() < 3 or _terrain_texture == null:
		return
	draw_polygon(_polygon, PackedColorArray([Color.WHITE]), _uvs, _terrain_texture)
	for mineral: Dictionary in _state.get("minerals", []):
		if mineral["remaining"] <= 0:
			continue
		draw_colored_polygon(_footprint_local(mineral["cell"], Vector2i.ONE), MINERAL)
	if _fog_texture != null:
		draw_polygon(_polygon, PackedColorArray([Color.WHITE]), _uvs, _fog_texture)
	# 已授权的调度区域：以着色格子足迹绘制，位于迷雾之上、实体圆点之下；停用区域保持可见但变暗。
	for region: Dictionary in _state.get("dispatch", {}).get("regions", []):
		var fill: Color = REGION_ENABLED if region.get("enabled", false) else REGION_DISABLED
		if int(region["id"]) == int(_state.get("dispatch", {}).get("selected_region_id", 0)):
			fill = Color(0.95, 0.76, 0.3, 0.45 if region.get("enabled", false) else 0.23)
		for cell: Vector2i in region.get("cells", []):
			draw_colored_polygon(_footprint_local(cell, Vector2i.ONE), fill)
	for entity: Dictionary in _state.get("entities", []):
		if entity.get("is_building", false):
			var fill: Color = Color(OWN_BUILDING, 0.4) if entity.get("hp", 1) <= 0 else OWN_BUILDING
			draw_colored_polygon(_footprint_local(entity["origin"], entity["footprint"]), fill)
			continue
		var point: Vector2 = _w2l(MechIsoGeometry.project(entity["position"]))
		if entity.get("team", 1) == 2:
			draw_circle(point, 4.0 if entity.get("enemy_id", &"") == &"prototype" else 2.5, ENEMY)
		else:
			draw_circle(point, 2.0, OWN_UNIT)
	if not _map.is_empty():
		var brain: PackedVector2Array = _footprint_local(_map["mainbrain_origin"], _map["mainbrain_footprint"])
		draw_colored_polygon(brain, Color(MAINBRAIN, 0.35))
		brain.append(brain[0])
		draw_polyline(brain, MAINBRAIN, 1.5, true)
	var shown: Rect2 = _camera_rect.intersection(_bounds)
	if shown.has_area():
		draw_rect(Rect2(_w2l(shown.position), shown.size * _map_scale), CAMERA_FRAME, false, 1.5)
	if _region_mode:
		draw_rect(Rect2(_region_start, _region_end - _region_start).abs(), Color(0.45, 0.9, 0.78, 0.9), false, 2.0)


func _recompute_fit() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0 or size.x < 4.0 or size.y < 4.0:
		return
	_map_scale = minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	_map_offset = (size - _bounds.size * _map_scale) * 0.5
	_polygon.clear()
	_uvs.clear()
	for point: Vector2 in _outline:
		_polygon.append(_w2l(MechIsoGeometry.project(point)))
		_uvs.append(point / Vector2(_dimensions))
	queue_redraw()


func _rebuild_terrain_texture(map_state: Dictionary) -> void:
	var dimensions: Vector2i = map_state["dimensions"]
	var terrain: PackedByteArray = map_state["terrain"]
	var playable: PackedByteArray = map_state["playable"]
	if _terrain_texture != null and _terrain_texture.get_size() == Vector2(dimensions) and terrain == _terrain_cache and playable == _playable_cache:
		return
	_terrain_cache = terrain.duplicate()
	_playable_cache = playable.duplicate()
	var pixels := PackedByteArray()
	pixels.resize(terrain.size() * 4)
	for index: int in range(terrain.size()):
		var fill: Color = TERRAIN_VOID
		if playable[index] != 0:
			fill = TERRAIN_OPEN
			if terrain[index] == MechGridState.Terrain.ROUGH:
				fill = TERRAIN_ROUGH
			elif terrain[index] == MechGridState.Terrain.OBSTACLE:
				fill = TERRAIN_OBSTACLE
		var rgba: int = fill.to_rgba32()
		pixels[index * 4] = (rgba >> 24) & 0xFF
		pixels[index * 4 + 1] = (rgba >> 16) & 0xFF
		pixels[index * 4 + 2] = (rgba >> 8) & 0xFF
		pixels[index * 4 + 3] = rgba & 0xFF
	var image: Image = Image.create_from_data(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8, pixels)
	if _terrain_texture == null or _terrain_texture.get_size() != Vector2(dimensions):
		_terrain_texture = ImageTexture.create_from_image(image)
	else:
		_terrain_texture.update(image)


func _rebuild_fog_texture(vision: Dictionary) -> void:
	var dimensions: Vector2i = vision["dimensions"]
	var cells: PackedByteArray = vision["cells"]
	var pixels := PackedByteArray()
	pixels.resize(cells.size() * 4)
	for index: int in range(cells.size()):
		pixels[index * 4] = 3
		pixels[index * 4 + 1] = 6
		pixels[index * 4 + 2] = 9
		pixels[index * 4 + 3] = 0 if cells[index] == MechVisionSystem.State.VISIBLE else (120 if cells[index] == MechVisionSystem.State.EXPLORED else 255)
	var image: Image = Image.create_from_data(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8, pixels)
	if _fog_texture == null or _fog_texture.get_size() != Vector2(dimensions):
		_fog_texture = ImageTexture.create_from_image(image)
	else:
		_fog_texture.update(image)


func _w2l(point: Vector2) -> Vector2:
	return (point - _bounds.position) * _map_scale + _map_offset


func _local_to_world(local: Vector2) -> Vector2:
	var unclamped: Vector2 = (local - _map_offset) / _map_scale + _bounds.position
	return Vector2(clampf(unclamped.x, _bounds.position.x, _bounds.end.x),
		clampf(unclamped.y, _bounds.position.y, _bounds.end.y))


func _footprint_local(origin: Vector2i, footprint: Vector2i) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point: Vector2 in MechIsoGeometry.footprint_polygon(origin, footprint):
		polygon.append(_w2l(point))
	return polygon


func _emit_focus(local: Vector2) -> void:
	if _map_scale <= 0.0 or _polygon.size() < 3:
		return
	focus_requested.emit(_local_to_world(local))
