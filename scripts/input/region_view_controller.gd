class_name RegionViewController
extends Node
## A/B 视图控制：Tab 在实体视图与区块视图之间切换。
##
## 区块视图只是同一世界上的信息层：不暂停、不改资源、不重建建筑。
## 切换时相机与模拟时钟完全不动，只切换覆盖层、面板与输入归属。

const INVALID_REGION := Vector2i(-1, -1)

var _game_state: GameState
var _world: World
var _hud: HUD
var _build_controller: BuildController

var active: bool = false
var selected_region: Vector2i = INVALID_REGION
var hovered_region: Vector2i = INVALID_REGION


func setup(
	game_state: GameState,
	world: World,
	hud: HUD,
	build_controller: BuildController
) -> void:
	_game_state = game_state
	_world = world
	_hud = hud
	_build_controller = build_controller
	_game_state.buildings.buildings_changed.connect(_on_buildings_changed)


func _process(_delta: float) -> void:
	if not active:
		return

	var region := _region_under_mouse()
	if region == hovered_region:
		return
	hovered_region = region
	_world.region_overlay.set_hovered(region)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_region_view"):
		set_active(not active)
		get_viewport().set_input_as_handled()
		return

	if not active:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_region_at_mouse()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			clear_selection()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cancel_action"):
		clear_selection()
		get_viewport().set_input_as_handled()


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value

	_world.region_overlay.set_active(active)
	_world.set_hover_highlight_enabled(not active)
	_hud.set_region_view_active(active)

	if active:
		_build_controller.set_input_enabled(false)
		_hud.hide_building_info()
		_world.build_preview.hide_preview()
		_world.build_range_overlay.set_active(false)
		_hud.set_status("区块视图：点击区块查看统计，Tab 返回")
		if selected_region != INVALID_REGION:
			_refresh_panel()
		else:
			_hud.hide_region_stats()
	else:
		_build_controller.set_input_enabled(true)
		hovered_region = INVALID_REGION
		_world.region_overlay.set_hovered(INVALID_REGION)
		_hud.hide_region_stats()
		_hud.set_status("选择建筑开始建造；右键拆除建筑")


func select_region(region_id: Vector2i) -> void:
	if not _game_state.regions.is_region_inside_map(region_id):
		clear_selection()
		return
	selected_region = region_id
	_world.region_overlay.set_selected(region_id)
	_refresh_panel()


func clear_selection() -> void:
	selected_region = INVALID_REGION
	_world.region_overlay.clear_selection()
	_hud.hide_region_stats()


func _select_region_at_mouse() -> void:
	var cell := _world.mouse_to_cell()
	if not _game_state.grid.is_inside_map(cell):
		clear_selection()
		return
	select_region(_game_state.regions.get_region_id(cell))


func _region_under_mouse() -> Vector2i:
	var cell := _world.mouse_to_cell()
	if not _game_state.grid.is_inside_map(cell):
		return INVALID_REGION
	var region := _game_state.regions.get_region_id(cell)
	if not _game_state.regions.is_region_inside_map(region):
		return INVALID_REGION
	return region


func _refresh_panel() -> void:
	if selected_region == INVALID_REGION:
		return
	var stats := _game_state.regions.get_region_stats(
		selected_region,
		_game_state.buildings.instances,
		_game_state.buildings.definitions,
		_game_state.grid
	)
	_hud.show_region_stats(stats)


func _on_buildings_changed() -> void:
	if active and selected_region != INVALID_REGION:
		_refresh_panel()
