class_name MechMapCamera3D
extends Camera3D
## 只读三维镜头：逻辑地图在XZ平面，所有投影/求交复用引擎。

const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 2.0
const OVERVIEW_MIN_ZOOM: float = 0.08
const BASE_SPAN: float = 1080.0 / (32.0 * sqrt(2.0))
const HUD_BOTTOM: float = 280.0
const PAN_SPEED: float = 850.0
const EDGE_WIDTH: float = 16.0
const GROUND := Plane(Vector3.UP, 0.0)
const VIEW_BACK := Vector3(1.0, 1.60356745, 1.0)

var pan_speed_factor: float = 1.0
var zoom_speed_factor: float = 1.0
var edge_scroll_enabled: bool = true
var keyboard_pan_blocked: bool = false
var input_blocked: bool = false:
	set(value):
		input_blocked = value
		if value:
			_stop_drag()

var _bounds := Rect2()
var _mainbrain := Vector2.ZERO
var _focus := Vector2.ZERO
var _factor: float = 0.7
var _dragging: bool = false
var _last_drag_position := Vector2.ZERO
var _external_gesture: bool = false
var _mouse_inside: bool = false


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	keep_aspect = Camera3D.KEEP_HEIGHT
	near = 0.1
	far = 800.0
	current = true
	get_window().mouse_entered.connect(func(): _mouse_inside = true)
	get_window().mouse_exited.connect(_on_mouse_exited)
	get_window().focus_exited.connect(_stop_drag)
	get_viewport().size_changed.connect(_clamp_position)
	_update_transform()


func configure_map(map_state: Dictionary) -> void:
	_bounds = Rect2(Vector2.ZERO, Vector2(map_state["dimensions"]))
	_mainbrain = Vector2(map_state["mainbrain_origin"]) + Vector2(map_state["mainbrain_footprint"]) * 0.5
	_factor = 0.7
	focus_mainbrain()


func screen_to_map(point: Vector2) -> Vector2:
	var hit: Variant = GROUND.intersects_ray(project_ray_origin(point), project_ray_normal(point))
	return Vector2(hit.x, hit.z) if hit != null else Vector2(INF, INF)


func map_to_screen(point: Vector2, height: float = 0.0) -> Vector2:
	return unproject_position(Vector3(point.x, height, point.y))


func map_point_on_screen(point: Vector2) -> bool:
	var world := Vector3(point.x, 0.0, point.y)
	return not is_position_behind(world) and _play_area().has_point(map_to_screen(point))


func visible_map_polygon() -> PackedVector2Array:
	var area: Rect2 = _play_area()
	var polygon := PackedVector2Array()
	for point: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
		var mapped: Vector2 = screen_to_map(point)
		if not mapped.is_finite():
			return PackedVector2Array()
		polygon.append(mapped)
	return polygon


func zoom_factor() -> float:
	return _factor


func focus_mainbrain() -> void:
	focus_map(_mainbrain)


func focus_map(point: Vector2) -> void:
	if not point.is_finite():
		return
	_stop_drag()
	_focus = point
	_clamp_position()


func fit_map() -> void:
	_stop_drag()
	_focus = _bounds.get_center()
	_factor = 1.0
	_update_transform()
	var projected := Rect2(map_to_screen(_bounds.position), Vector2.ZERO)
	for corner: Vector2 in [_bounds.end, Vector2(_bounds.end.x, _bounds.position.y), Vector2(_bounds.position.x, _bounds.end.y)]:
		projected = projected.expand(map_to_screen(corner))
	var available: Vector2 = _play_area().size - Vector2(80, 80)
	_factor = clampf(minf(available.x / projected.size.x, available.y / projected.size.y), OVERVIEW_MIN_ZOOM, MAX_ZOOM)
	_clamp_position()


func set_external_gesture(active: bool) -> void:
	_external_gesture = active
	if active:
		_stop_drag()


func handle_event(event: InputEvent) -> bool:
	if input_blocked or _external_gesture:
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = true
			_last_drag_position = event.position
			return true
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _factor < MIN_ZOOM and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return true
			var before: Vector2 = screen_to_map(event.position)
			var step: float = pow(1.15, zoom_speed_factor)
			_factor = clampf(_factor * (step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step), MIN_ZOOM, MAX_ZOOM)
			_update_transform()
			var after: Vector2 = screen_to_map(event.position)
			if before.is_finite() and after.is_finite():
				_focus += before - after
			_clamp_position()
			return true
	return false


func _input(event: InputEvent) -> void:
	if input_blocked or not _dragging:
		return
	if event is InputEventMouseMotion:
		var before: Vector2 = screen_to_map(_last_drag_position)
		var after: Vector2 = screen_to_map(event.position)
		if before.is_finite() and after.is_finite():
			_focus += before - after
		_last_drag_position = event.position
		_clamp_position()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_stop_drag()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if input_blocked or _dragging or _external_gesture or not get_window().has_focus():
		return
	var direction := Vector2.ZERO
	if not keyboard_pan_blocked:
		direction.x = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		direction.y = float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	if edge_scroll_enabled and _mouse_inside and get_viewport().gui_get_hovered_control() == null:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var extent: Vector2 = get_viewport().get_visible_rect().size
		if mouse.x >= 0.0 and mouse.x < EDGE_WIDTH:
			direction.x -= 1.0
		elif mouse.x > extent.x - EDGE_WIDTH and mouse.x < extent.x:
			direction.x += 1.0
		if mouse.y >= 0.0 and mouse.y < EDGE_WIDTH:
			direction.y -= 1.0
		elif mouse.y > extent.y - EDGE_WIDTH and mouse.y < extent.y:
			direction.y += 1.0
	if not direction.is_zero_approx():
		var center: Vector2 = _play_area().get_center()
		_focus += screen_to_map(center + direction.normalized() * PAN_SPEED * pan_speed_factor * delta) - screen_to_map(center)
		_clamp_position()


func _play_area() -> Rect2:
	var extent: Vector2 = get_viewport().get_visible_rect().size
	return Rect2(Vector2.ZERO, Vector2(extent.x, maxf(240.0, extent.y - HUD_BOTTOM)))


func _update_transform() -> void:
	size = BASE_SPAN / _factor
	var height: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
	var down := Vector3(1.0, 0.0, 1.0).normalized()
	var target := Vector3(_focus.x, 0.0, _focus.y) + down * (HUD_BOTTOM * 0.5 * size / height / 0.75)
	position = target + VIEW_BACK.normalized() * 300.0
	look_at(target, Vector3.UP)


func _clamp_position() -> void:
	_update_transform()
	if not _bounds.has_area():
		return
	var polygon: PackedVector2Array = visible_map_polygon()
	if polygon.size() < 3:
		return
	var span := Rect2(polygon[0] - _focus, Vector2.ZERO)
	for point: Vector2 in polygon:
		span = span.expand(point - _focus)
	var low: Vector2 = _bounds.position - span.position
	var high: Vector2 = _bounds.end - span.end
	_focus.x = clampf(_focus.x, low.x, high.x) if low.x <= high.x else _bounds.get_center().x
	_focus.y = clampf(_focus.y, low.y, high.y) if low.y <= high.y else _bounds.get_center().y
	_update_transform()


func _on_mouse_exited() -> void:
	_mouse_inside = false
	_stop_drag()


func _stop_drag() -> void:
	_dragging = false
