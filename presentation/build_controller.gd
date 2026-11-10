class_name MechBuildController
extends RefCounted
## 建造模式、键盘光标和墙线手势；下单仍由CommandQueue校验提交。

signal cursor_changed

var building_id: StringName = &""
var wall_dragging: bool = false
var dimensions := Vector2i.ZERO
var _build_cell := Vector2i(-1, -1)
var _keyboard_build: bool = false
var _wall_start := Vector2i.ZERO
var _wall_end := Vector2i.ZERO
var _sim: MechSimCore
var _commands: MechCommandQueue
var _hud: MechMapHud
var _world: MechFoundationView3D
var _camera: MechMapCamera3D
var _coverage: MechCoverageView3D
var _viewport: Viewport
var _window: Window


func configure(sim: MechSimCore, commands: MechCommandQueue, hud: MechMapHud, world: MechFoundationView3D, camera: MechMapCamera3D, coverage: MechCoverageView3D, viewport: Viewport, window: Window) -> void:
	_sim = sim
	_commands = commands
	_hud = hud
	_world = world
	_camera = camera
	_coverage = coverage
	_viewport = viewport
	_window = window


func follow_mouse(event: InputEvent) -> void:
	if event is InputEventMouseMotion and building_id != &"" and not event.relative.is_zero_approx() \
			and _viewport.get_visible_rect().has_point(event.position) and not _hud.blocks_point(event.position):
		_keyboard_build = false


func place_at(map_position: Vector2) -> void:
	if _hud.blocks_point(_viewport.get_mouse_position()):
		return
	_keyboard_build = false
	_commands.submit(MechCommand.new(MechCommand.Type.PLACE_BUILDING, {"building_id": building_id, "origin": _map_cell(map_position)}))


func begin_wall(event: InputEvent) -> bool:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT \
			or not event.shift_pressed or building_id != &"armored_wall":
		return false
	var cell: Vector2i = _mouse_cell()
	if not _sim.inspect_cell(cell)["inside"]:
		return false
	wall_dragging = true
	_wall_start = cell
	_wall_end = cell
	_camera.set_external_gesture(true)
	cursor_changed.emit()
	return true


func handle_wall_event(event: InputEvent) -> bool:
	if not wall_dragging:
		return false
	if event is InputEventMouseMotion:
		_wall_end = _clamped_line_cell(_mouse_cell())
		cursor_changed.emit()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_wall_end = _clamped_line_cell(_mouse_cell())
		var cells: Array[Vector2i] = _wall_cells()
		var can_commit: bool = not _hud.blocks_point(event.position) and _viewport.get_visible_rect().has_point(event.position)
		cancel_wall_drag()
		if can_commit:
			_commands.submit(MechCommand.new(MechCommand.Type.PLACE_WALL_LINE, {"cells": cells}))
		else:
			_hud.feedback("已取消墙线，没有下单或扣款。")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel()
	else:
		return false
	return true


func request(id: StringName, catalog: Array) -> void:
	cancel_wall_drag()
	for entry: Dictionary in catalog:
		if entry["building_id"] != id:
			continue
		if not entry["unavailable_reason"].is_empty():
			_hud.feedback(entry["unavailable_reason"], true)
			return
		building_id = id
		_keyboard_build = false
		_build_cell = _mouse_cell()
		_camera.keyboard_pan_blocked = true
		_hud.present_build(id)
		_coverage.show()
		_hud.feedback("%s：左键下单；方向键移动、Enter下单；右键退出。%s" % [entry["name"], "Shift＋左键拖线可连放墙。" if id == &"armored_wall" else ""])
		cursor_changed.emit()
		return


func cancel_wall_drag() -> void:
	wall_dragging = false
	_camera.set_external_gesture(false)


func cancel() -> void:
	cancel_wall_drag()
	building_id = &""
	_keyboard_build = false
	_camera.keyboard_pan_blocked = false
	_hud.present_build(&"")
	_coverage.hide()
	_hud.feedback("已退出建造。左键点选/框选，右键下令；选中工厂右键设集结点。")
	cursor_changed.emit()


func handle_key(key: int) -> bool:
	if building_id != &"" and key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		if not _keyboard_build:
			_build_cell = _mouse_cell()
		_keyboard_build = true
		match key:
			KEY_LEFT:
				_build_cell += Vector2i(-1, 0)
			KEY_RIGHT:
				_build_cell += Vector2i(1, 0)
			KEY_UP:
				_build_cell += Vector2i(0, -1)
			KEY_DOWN:
				_build_cell += Vector2i(0, 1)
		cursor_changed.emit()
		return true
	if building_id != &"" and key == KEY_ENTER:
		var mouse: Vector2 = _viewport.get_mouse_position()
		if not _keyboard_build and (not _viewport.get_visible_rect().has_point(mouse) or _hud.blocks_point(mouse)):
			return true
		var cell: Vector2i = _build_cell if _keyboard_build else _mouse_cell()
		_commands.submit(MechCommand.new(MechCommand.Type.PLACE_BUILDING, {"building_id": building_id, "origin": cell}))
		return true
	return false


func _mouse_cell() -> Vector2i:
	return _map_cell(_camera.screen_to_map(_viewport.get_mouse_position()))


func _map_cell(point: Vector2) -> Vector2i:
	return Vector2i(point.floor()) if point.is_finite() else Vector2i(-1, -1)


func _clamped_line_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, -1, dimensions.x), clampi(cell.y, -1, dimensions.y))


func _wall_cells() -> Array[Vector2i]:
	return Geometry2D.bresenham_line(_wall_start, _wall_end)


func present_cursor(selected_cell: Vector2i, settings_open: bool) -> void:
	var mouse: Vector2 = _viewport.get_mouse_position()
	var cursor_visible: bool = not settings_open and _window.has_focus() and _viewport.get_visible_rect().has_point(mouse) and not _hud.blocks_point(mouse)
	var keyboard_cursor_visible: bool = building_id != &"" and _keyboard_build and not settings_open and _window.has_focus()
	var cell: Vector2i = _build_cell if building_id != &"" and _keyboard_build else _mouse_cell()
	var info: Dictionary = {}
	if cursor_visible or keyboard_cursor_visible:
		info = _sim.inspect_cell(cell)
	elif selected_cell.x >= 0:
		info = _sim.inspect_cell(selected_cell)
	var preview: Dictionary = {}
	if wall_dragging:
		preview = _sim.preview_wall_line(_wall_cells())
	elif (cursor_visible or keyboard_cursor_visible) and building_id != &"":
		preview = _sim.preview_build(building_id, cell)
	_world.present_cursor(cell, selected_cell, preview, cursor_visible or wall_dragging or keyboard_cursor_visible)
	_hud.present_cell(info, preview)
