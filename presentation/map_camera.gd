class_name MechMapCamera
extends Camera2D
## Native Camera2D with view-only controls; never reads or writes sim internals.

const MIN_ZOOM: float = 0.18
const MAX_ZOOM: float = 2.0
const PAN_SPEED: float = 850.0
const EDGE_WIDTH: float = 16.0

var _bounds := Rect2()
var _focus := Vector2.ZERO
var _dragging: bool = false
var _last_drag_position := Vector2.ZERO
var _mouse_inside: bool = false
var _external_gesture: bool = false
var pan_speed_factor: float = 1.0
var zoom_speed_factor: float = 1.0
var edge_scroll_enabled: bool = true
var input_blocked: bool = false:
	set(value):
		input_blocked = value
		if value:
			_stop_drag()


func set_external_gesture(active: bool) -> void:
	_external_gesture = active
	if active:
		_stop_drag()


func _ready() -> void:
	position_smoothing_enabled = false
	limit_enabled = false
	get_window().mouse_entered.connect(_on_mouse_entered)
	get_window().mouse_exited.connect(_on_mouse_exited)
	get_window().focus_exited.connect(_stop_drag)
	get_viewport().size_changed.connect(_clamp_position)


func configure(bounds: Rect2, focus: Vector2) -> void:
	_bounds = bounds.grow(100.0)
	_focus = focus
	zoom = Vector2.ONE * 0.78
	focus_mainbrain()


func focus_mainbrain() -> void:
	_stop_drag()
	position = _focus
	_clamp_position()


func fit_map() -> void:
	_stop_drag()
	var visible: Vector2 = get_viewport_rect().size - Vector2(100.0, 360.0)
	var factor: float = clampf(minf(visible.x / _bounds.size.x, visible.y / _bounds.size.y), MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2.ONE * factor
	position = _bounds.get_center()
	_clamp_position()


func visible_world_rect() -> Rect2:
	var half: Vector2 = get_viewport_rect().size / zoom * 0.5
	return Rect2(position - half, half * 2.0)


func focus_world(world_position: Vector2) -> void:
	_stop_drag()
	position = world_position
	_clamp_position()


func handle_event(event: InputEvent) -> bool:
	if input_blocked or _external_gesture:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_dragging = true
			_last_drag_position = event.position
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector2 = get_global_mouse_position()
			var step: float = pow(1.15, zoom_speed_factor)
			var multiplier: float = step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step
			zoom = Vector2.ONE * clampf(zoom.x * multiplier, MIN_ZOOM, MAX_ZOOM)
			force_update_scroll()
			position += before - get_global_mouse_position()
			_clamp_position()
			return true
	return false


func _input(event: InputEvent) -> void:
	# Capture a world-originated middle drag even when it moves over the HUD.
	# Left-button selection and building gestures belong to the input owner.
	if input_blocked or not _dragging:
		return
	if event is InputEventMouseMotion:
		position -= (event.position - _last_drag_position) / zoom
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
	if Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if edge_scroll_enabled and _mouse_inside and get_viewport().gui_get_hovered_control() == null:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var extent: Vector2 = get_viewport_rect().size
		if mouse.x >= 0.0 and mouse.x < EDGE_WIDTH:
			direction.x -= 1.0
		elif mouse.x > extent.x - EDGE_WIDTH and mouse.x < extent.x:
			direction.x += 1.0
		if mouse.y >= 0.0 and mouse.y < EDGE_WIDTH:
			direction.y -= 1.0
		elif mouse.y > extent.y - EDGE_WIDTH and mouse.y < extent.y:
			direction.y += 1.0
	if not direction.is_zero_approx():
		position += direction.normalized() * PAN_SPEED * pan_speed_factor * delta / zoom.x
		_clamp_position()


func _clamp_position() -> void:
	if _bounds.size.is_zero_approx():
		return
	var half_view: Vector2 = get_viewport_rect().size / zoom * 0.5
	var low: Vector2 = _bounds.position + half_view
	var high: Vector2 = _bounds.end - half_view
	position.x = clampf(position.x, low.x, high.x) if low.x <= high.x else _bounds.get_center().x
	position.y = clampf(position.y, low.y, high.y) if low.y <= high.y else _bounds.get_center().y
	force_update_scroll()


func _on_mouse_entered() -> void:
	_mouse_inside = true


func _on_mouse_exited() -> void:
	_mouse_inside = false
	_stop_drag()


func _stop_drag() -> void:
	_dragging = false
