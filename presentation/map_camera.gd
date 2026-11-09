class_name MechMapCamera
extends Camera2D
## 原生 Camera2D 的只读视图控制；绝不读写模拟内部状态。

## 常规战术缩放下限；全图总览是另一模式，可缩到更小。
const MIN_ZOOM: float = 0.5
const OVERVIEW_MIN_ZOOM: float = 0.12
const MAX_ZOOM: float = 2.0
## 底部 HUD 预留高度（像素），镜头可视区据此裁剪。
const HUD_BOTTOM: float = 280.0
const PAN_SPEED: float = 850.0
## 边缘滚屏触发宽度（像素）。
const EDGE_WIDTH: float = 16.0

@export_range(0.5, 2.0, 0.01) var initial_zoom: float = 0.70

var _bounds := Rect2()
var _focus := Vector2.ZERO
var _dragging: bool = false
var _last_drag_position := Vector2.ZERO
var _mouse_inside: bool = false
## 外部手势占用期间（框选、墙线等）镜头停用手动输入。
var _external_gesture: bool = false
var pan_speed_factor: float = 1.0
var zoom_speed_factor: float = 1.0
var edge_scroll_enabled: bool = true
var input_blocked: bool = false:
	set(value):
		input_blocked = value
		if value:
			_stop_drag()
## 建造时方向键调整放置格，不能同时被连续按键平移读取。
var keyboard_pan_blocked: bool = false


## 通知镜头外部手势的占用状态；占用期间停用拖拽。
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


## 按地图包围盒与主脑焦点初始化镜头。
func configure(bounds: Rect2, focus: Vector2) -> void:
	_bounds = bounds.grow(100.0)
	_focus = focus
	zoom = Vector2.ONE * clampf(initial_zoom, MIN_ZOOM, MAX_ZOOM)
	focus_mainbrain()


func focus_mainbrain() -> void:
	_stop_drag()
	position = _focus
	_clamp_position()


## 全图总览：缩放并居中到整张地图。
func fit_map() -> void:
	_stop_drag()
	var visible: Vector2 = _play_area_size() - Vector2(80.0, 80.0)
	var factor: float = clampf(minf(visible.x / _bounds.size.x, visible.y / _bounds.size.y), OVERVIEW_MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2.ONE * factor
	position = _bounds.get_center()
	_clamp_position()


## 当前可视的世界坐标矩形（扣除 HUD 区域）。
func visible_world_rect() -> Rect2:
	var half: Vector2 = _play_area_size() / zoom * 0.5
	return Rect2(position - half, half * 2.0)


## 主画面统一使用逻辑地图坐标；等距投影仅由2D适配器处理。
func configure_map(map_state: Dictionary) -> void:
	var focus: Vector2 = Vector2(map_state["mainbrain_origin"]) + Vector2(map_state["mainbrain_footprint"]) * 0.5
	configure(MechIsoGeometry.map_bounds(map_state["dimensions"], map_state["outline"]), MechIsoGeometry.project(focus))


func screen_to_map(point: Vector2) -> Vector2:
	return MechIsoGeometry.unproject(get_viewport().get_canvas_transform().affine_inverse() * point)


func map_to_screen(point: Vector2, _height: float = 0.0) -> Vector2:
	return get_viewport().get_canvas_transform() * MechIsoGeometry.project(point)


func focus_map(point: Vector2) -> void:
	focus_world(MechIsoGeometry.project(point))


func zoom_factor() -> float:
	return zoom.x


func visible_map_polygon() -> PackedVector2Array:
	var viewport: Rect2 = get_viewport_rect()
	viewport.size = _play_area_size()
	var polygon := PackedVector2Array()
	for point: Vector2 in [viewport.position, Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)]:
		polygon.append(screen_to_map(point))
	return polygon


func map_point_on_screen(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, _play_area_size()).has_point(map_to_screen(point))


func focus_world(world_position: Vector2) -> void:
	_stop_drag()
	position = world_position
	_clamp_position()


## 处理中键拖拽与滚轮缩放；返回是否消费了该事件。
func handle_event(event: InputEvent) -> bool:
	if input_blocked or _external_gesture:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_dragging = true
			_last_drag_position = event.position
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# 全图总览是独立模式；向外滚动绝不反向跳回常规战术最小缩放。
			if zoom.x < MIN_ZOOM and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return true
			var before: Vector2 = get_global_mouse_position()
			var step: float = pow(1.15, zoom_speed_factor)
			var multiplier: float = step if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step
			zoom = Vector2.ONE * clampf(zoom.x * multiplier, MIN_ZOOM, MAX_ZOOM)
			_update_view_offset()
			force_update_scroll()
			position += before - get_global_mouse_position()
			_clamp_position()
			return true
	return false


func _input(event: InputEvent) -> void:
	# 即使中键拖拽移入 HUD 区域也持续接管；左键选择与建造手势归输入属主。
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


## 每帧处理方向键平移与边缘滚屏。
func _process(delta: float) -> void:
	if input_blocked or _dragging or _external_gesture or not get_window().has_focus():
		return
	var direction := Vector2.ZERO
	if not keyboard_pan_blocked and Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if not keyboard_pan_blocked and Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if not keyboard_pan_blocked and Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if not keyboard_pan_blocked and Input.is_physical_key_pressed(KEY_DOWN):
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


## 把镜头位置钳制在地图包围盒内。
func _clamp_position() -> void:
	_update_view_offset()
	if _bounds.size.is_zero_approx():
		return
	var half_view: Vector2 = _play_area_size() / zoom * 0.5
	var low: Vector2 = _bounds.position + half_view
	var high: Vector2 = _bounds.end - half_view
	position.x = clampf(position.x, low.x, high.x) if low.x <= high.x else _bounds.get_center().x
	position.y = clampf(position.y, low.y, high.y) if low.y <= high.y else _bounds.get_center().y
	force_update_scroll()


## 扣除底部 HUD 后的实际游玩区尺寸。
func _play_area_size() -> Vector2:
	var extent: Vector2 = get_viewport_rect().size
	return Vector2(extent.x, maxf(240.0, extent.y - HUD_BOTTOM))


## 保持焦点位于指令坞上方战场的中心。
func _update_view_offset() -> void:
	offset = Vector2(0.0, (get_viewport_rect().size.y - _play_area_size().y) * 0.5 / zoom.y)


func _on_mouse_entered() -> void:
	_mouse_inside = true


func _on_mouse_exited() -> void:
	_mouse_inside = false
	_stop_drag()


func _stop_drag() -> void:
	_dragging = false
