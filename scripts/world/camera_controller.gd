class_name CameraController
extends Camera2D
## 跟随主相机的 RTS 镜头控制：左键拖动 / WASD 平移、滚轮缩放、地图边界限制。
##
## 相机位置与缩放属于表现层，不写入 GameState。

signal zoom_changed(zoom_value: float)

@export var pan_speed: float = 900.0
@export var zoom_step: float = 1.12
@export var zoom_min: float = 0.45
@export var zoom_max: float = 3.0
@export var zoom_smoothing: float = 12.0
## 左键按住后移动超过该像素才视为拖动，避免和点击冲突。
@export var drag_threshold: float = 6.0

var _target_zoom: float = 1.0
var _world: World
var _left_pressed: bool = false
var _dragging: bool = false
## 本次左键手势是否为拖动；保持到下一次按下，避免点击处理器与相机顺序不同步。
var _drag_consumed: bool = false
var _press_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_target_zoom = zoom.x


## 根据世界视图的地图范围设置初始位置与 Camera2D 边界。
func setup(world: World) -> void:
	_world = world
	var rect := world.get_map_world_rect()
	if rect.size == Vector2.ZERO:
		return

	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)
	position = rect.get_center()


func _process(delta: float) -> void:
	if _world == null:
		return

	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if direction != Vector2.ZERO:
		# 按世界像素平移，除以缩放让不同缩放级别的手感一致。
		position += direction * pan_speed * delta / zoom.x

	if not is_equal_approx(zoom.x, _target_zoom):
		var next_zoom := lerpf(zoom.x, _target_zoom, clampf(delta * zoom_smoothing, 0.0, 1.0))
		zoom = Vector2(next_zoom, next_zoom)

	# 窗口外松开鼠标时收不到 release，这里兜底清理拖动状态。
	if _left_pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_consumed = _dragging
		_end_drag()

	_clamp_to_map_limits()


## 本次左键手势是否为拖动（松开后仍保持到下一次按下）。
func is_dragging() -> bool:
	return _dragging or _drag_consumed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_pressed = true
				_dragging = false
				_drag_consumed = false
				_press_position = event.position
			else:
				_drag_consumed = _dragging
				if _dragging:
					get_viewport().set_input_as_handled()
				_end_drag()
			return

	if event is InputEventMouseMotion and _left_pressed:
		if not _dragging and (event.position - _press_position).length() >= drag_threshold:
			_dragging = true
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)

		if _dragging:
			# 抓住地图拖动：鼠标向右拖，地图跟随向右，相机世界坐标反向移动。
			position -= event.relative / zoom.x
			_clamp_to_map_limits()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("camera_zoom_in"):
		_set_target_zoom(_target_zoom * zoom_step)
	elif event.is_action_pressed("camera_zoom_out"):
		_set_target_zoom(_target_zoom / zoom_step)


func _end_drag() -> void:
	_left_pressed = false
	_dragging = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## Camera2D 的 limit 只在绘制时裁剪，不会修正 position 本身；
## 这里同步钳制位置，避免镜头顶到边界后需要反向移动一大段才响应。
func _clamp_to_map_limits() -> void:
	if limit_right <= limit_left or limit_bottom <= limit_top:
		return

	var half_view := get_viewport_rect().size / (2.0 * zoom.x)
	var min_x := float(limit_left) + half_view.x
	var max_x := float(limit_right) - half_view.x
	var min_y := float(limit_top) + half_view.y
	var max_y := float(limit_bottom) - half_view.y

	position.x = (float(limit_left) + float(limit_right)) * 0.5 if min_x > max_x else clampf(position.x, min_x, max_x)
	position.y = (float(limit_top) + float(limit_bottom)) * 0.5 if min_y > max_y else clampf(position.y, min_y, max_y)


func _set_target_zoom(value: float) -> void:
	var clamped := clampf(value, zoom_min, zoom_max)
	if is_equal_approx(clamped, _target_zoom):
		return
	_target_zoom = clamped
	zoom_changed.emit(_target_zoom)
