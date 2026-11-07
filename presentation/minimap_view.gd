class_name MechMinimapView
extends Control
## Minimap read model: terrain/fog textures plus snapshot dots and the camera
## frame. All data arrives through present_* calls; the view never reads the
## simulation. Fullscreen mode is reserved as the region-management surface,
## so everything is computed from the current control size.

signal focus_requested(world_position: Vector2)

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

var _dimensions := Vector2i.ZERO
var _outline := PackedVector2Array()
var _bounds := Rect2()
var _terrain_texture: ImageTexture
var _terrain_cache := PackedByteArray()
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_emit_focus(event.position)
		accept_event()
	elif _dragging and event is InputEventMouseMotion:
		_emit_focus(event.position)
		accept_event()


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
	# Future region overlays (command-node ranges, development-plan M10) are
	# drawn here, above the fog and below the entity dots.
	for entity: Dictionary in _state.get("entities", []):
		if entity.get("is_building", false):
			var fill: Color = Color(OWN_BUILDING, 0.4) if entity.get("phase", 1) == MechBuildingState.Phase.RUINED else OWN_BUILDING
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
	if dimensions == _dimensions and terrain == _terrain_cache:
		return
	_terrain_cache = terrain.duplicate()
	var playable: PackedByteArray = map_state["playable"]
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
		pixels[index * 4] = rgba & 0xFF
		pixels[index * 4 + 1] = (rgba >> 8) & 0xFF
		pixels[index * 4 + 2] = (rgba >> 16) & 0xFF
		pixels[index * 4 + 3] = (rgba >> 24) & 0xFF
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
		pixels[index * 4 + 3] = 0 if cells[index] == MechVisionSystem.State.VISIBLE else (120 if cells[index] == MechVisionSystem.State.EXPLORED else 245)
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
