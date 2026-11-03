class_name BuildController
extends Node
## 手动建造输入：选择建筑 → 跟随鼠标预览 → 左键放置；右键/Esc 取消；右键拆除。
##
## 所有合法性判断与资源扣除都调用 BuildingSystem，控制器只负责输入与提示。

var _game_state: GameState
var _world: World
var _hud: HUD
var _camera: CameraController
var _selected: BuildingDefinition
var _last_info_id: StringName = &""
var input_enabled: bool = true


func setup(
	game_state: GameState, world: World, hud: HUD, camera: CameraController
) -> void:
	_game_state = game_state
	_world = world
	_hud = hud
	_camera = camera

	hud.build_palette.building_selected.connect(select_definition)
	hud.build_palette.setup(game_state.buildings.get_buildable_definitions())
	world.build_range_overlay.set_active(false)
	hud.set_status("选择建筑开始建造；右键拆除建筑")


## 区块视图期间关闭建造输入，返回实体视图时恢复。
func set_input_enabled(value: bool) -> void:
	if input_enabled == value:
		return
	input_enabled = value
	if not value:
		cancel()
		_hud.hide_building_info()
		_last_info_id = &""


func select_definition(definition_id: StringName) -> void:
	var definition := _game_state.buildings.get_definition(definition_id)
	if definition == null:
		return
	_selected = definition
	_hud.build_palette.set_selected(definition_id)
	_world.build_range_overlay.set_active(true)
	_hud.set_status("放置 %s：左键确定，右键/Esc 取消" % definition.display_name)
	_update_preview()


func cancel() -> void:
	_selected = null
	_world.build_preview.hide_preview()
	_world.build_range_overlay.set_active(false)
	_hud.build_palette.clear_selection()
	_hud.set_status("选择建筑开始建造；右键拆除建筑")


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	if _selected != null:
		_update_preview()
	_update_info_panel()


func _update_info_panel() -> void:
	var cell := _world.mouse_to_cell()
	var instance_id: StringName = _game_state.grid.get_occupant(cell)
	if instance_id == _last_info_id:
		return
	_last_info_id = instance_id

	if instance_id == &"":
		_hud.hide_building_info()
		return

	var instance: BuildingInstance = _game_state.buildings.instances.get(instance_id)
	if instance == null:
		_hud.hide_building_info()
		return
	_hud.show_building_info(_game_state.buildings.get_definition(instance.definition_id))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _select_by_hotkey(event):
			get_viewport().set_input_as_handled()
			return

	if _selected != null:
		if event.is_action_pressed("cancel_action"):
			cancel()
			get_viewport().set_input_as_handled()
		elif (
			event is InputEventMouseButton
			and not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			# 拖动地图时不放置；松开事件继续交给相机重置拖动状态。
			if not _camera.is_dragging():
				_try_place()
		return

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		_demolish_under_mouse()
		get_viewport().set_input_as_handled()


func _try_place() -> void:
	var origin := _placement_origin(_world.mouse_to_cell())
	if _game_state.buildings.try_place_building(_selected.building_id, origin):
		_hud.set_status("已建造 %s" % _selected.display_name)
	else:
		_hud.set_status(_game_state.buildings.last_error)


func _demolish_under_mouse() -> void:
	var cell := _world.mouse_to_cell()
	var instance_id: StringName = _game_state.grid.get_occupant(cell)
	if instance_id == &"":
		_hud.set_status("这里没有可拆除的建筑")
		return

	var instance: BuildingInstance = _game_state.buildings.instances.get(instance_id)
	var display_name := ""
	if instance != null:
		display_name = instance.get_display_name(_game_state.buildings.definitions)

	if _game_state.buildings.remove_building(instance_id):
		_hud.set_status("已拆除 %s" % display_name)


func _update_preview() -> void:
	var hovered := _world.mouse_to_cell()
	if not _game_state.grid.is_inside_map(hovered):
		_world.build_preview.hide_preview()
		return

	var origin := _placement_origin(hovered)
	var error := _game_state.buildings.get_placement_error(_selected.building_id, origin)
	_world.build_preview.show_preview(
		_selected,
		origin,
		_world.get_footprint_anchor(origin, _selected.footprint),
		error == ""
	)

	if error != "":
		_hud.set_status(error)
	else:
		_hud.set_status("放置 %s：左键确定，右键/Esc 取消" % _selected.display_name)


## 1×1 直接落在光标格；偶数边长时向右下扩展（3×3 等奇数边长会居中）。
func _placement_origin(hovered: Vector2i) -> Vector2i:
	if _selected == null:
		return hovered
	var offset_x := floori((float(_selected.footprint.x) - 1.0) * 0.5)
	var offset_y := floori((float(_selected.footprint.y) - 1.0) * 0.5)
	return hovered - Vector2i(offset_x, offset_y)


func _select_by_hotkey(event: InputEventKey) -> bool:
	var index := -1
	match event.keycode:
		KEY_1:
			index = 0
		KEY_2:
			index = 1
		KEY_3:
			index = 2
		KEY_4:
			index = 3
		KEY_5:
			index = 4
		KEY_6:
			index = 5
	if index < 0:
		return false

	var definitions := _game_state.buildings.get_buildable_definitions()
	if index >= definitions.size():
		return false
	select_definition(definitions[index].building_id)
	return true
