extends Node
## 组合根：装配模拟、命令队列与全部表现层视图；只有命令可以改变模拟状态。

const SETTINGS: MechFoundationSettings = preload("res://content/development_128.tres")
## 双击判定窗口（毫秒）与两次按下之间的最大位移（像素）。
const DOUBLE_CLICK_MS: int = 400
const DOUBLE_CLICK_SLOP: float = 8.0
## 双击链式扩选时，屏幕外同类单位与已选单位的最大间距（世界格）。
const SAME_KIND_CHAIN_RADIUS: float = 2.0

var _sim := MechSimCore.new()
var _commands := MechCommandQueue.new()
## 2D基线与3D开发场景共享同一模拟、命令和交互；只读视图使用相同present接口。
@onready var _terrain = $Terrain
@onready var _coverage = $Coverage
@onready var _world = $Entities
@onready var _fog = $Fog
@onready var _camera = $MapCamera
@onready var _hud: MechMapHud = $HUD
@onready var _settings: MechSettingsMenu = $Settings
var _resume_after_settings: bool = false
var _last_generation: int = -1
var _last_map_revision: int = -1
var _stress_mode: bool = false
var _stress_timer: float = 0.0
var _stress_step: int = 0
var _session_logged: bool = false
var _selected_dispatch_region: int = 0
var _last_coverage_revision: int = -1
var _selected := Vector2i(-1, -1)
var _build_id: StringName = &""
var _build_cell := Vector2i(-1, -1)
var _keyboard_build := false
var _wall_dragging: bool = false
var _wall_start := Vector2i.ZERO
var _wall_end := Vector2i.ZERO
var _dimensions := Vector2i.ZERO
var _map_outline := PackedVector2Array()
var _selection := MechSelectionState.new()
var _selection_dragging: bool = false
var _selection_start := Vector2.ZERO
var _selection_end := Vector2.ZERO
var _selection_bounds := Rect2()
var _selection_additive: bool = false
var _selection_toggle: bool = false
var _attack_move_mode: bool = false
var _last_group: int = -1
var _last_group_time: int = 0
## 上一次选择模式左键按下的时间与位置，用于双击判定；0 表示没有可续接的点击。
var _last_click_ms: int = 0
var _last_click_position := Vector2.ZERO
var _last_threat_key: String = ""
var _last_alert_key: String = ""
var _state: Dictionary = {}
var _state_dirty: bool = true
var _last_session_ended: bool = false
var _perf_enabled: bool = false
var _perf_seconds: float = 0.0
var _perf_frames: int = 0
var _perf_sim_usec: int = 0
var _perf_sim_ticks: int = 0
var _perf_view_usec: int = 0
var _perf_sim_peak_usec: int = 0
var _perf_view_peak_usec: int = 0
var _perf_frame_peak: float = 0.0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--3d") and not _camera is Camera3D:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main_3d.tscn")
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	# 部分 Windows/DPI 配置会把窗口恢复到屏幕外，这里把启动位置钳制回可用区域，确保工具栏始终可及。
	var window := get_window()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	var position: Vector2i = window.position
	position.x = clampi(position.x, usable.position.x, maxi(usable.position.x, usable.end.x - window.size.x))
	position.y = clampi(position.y, usable.position.y, maxi(usable.position.y, usable.end.y - window.size.y))
	window.position = position
	_stress_mode = OS.get_cmdline_user_args().has("--stress")
	_perf_enabled = OS.get_cmdline_user_args().has("--perf")
	_sim.profiling_enabled = _perf_enabled
	var initial_settings: MechFoundationSettings = SETTINGS.duplicate(true)
	if OS.get_cmdline_user_args().has("--campaign"):
		initial_settings.campaign_mode = true
		initial_settings.scenario_name += " · 三阶段战役"
	Engine.physics_ticks_per_second = initial_settings.simulation_hz
	if not _sim.configure(initial_settings):
		get_tree().quit(1)
		return
	_commands.configure(_sim.execute_command)
	if _world.has_method("configure"):
		_world.configure(initial_settings)
	_commands.command_finished.connect(_on_command_finished)
	_coverage.hide()
	_hud.pause_requested.connect(_toggle_pause)
	_hud.restart_requested.connect(_restart)
	_hud.focus_requested.connect(_focus_mainbrain)
	_hud.fit_requested.connect(_fit_map)
	_hud.build_requested.connect(_request_build)
	_hud.build_cancelled.connect(_cancel_build)
	_hud.building_action_requested.connect(_building_action)
	_hud.production_requested.connect(_queue_unit)
	_hud.production_cancelled.connect(_cancel_production)
	_hud.upgrade_requested.connect(_upgrade_building)
	_hud.upgrade_cancelled.connect(_cancel_upgrade)
	_hud.settings_requested.connect(_open_settings)
	_hud.minimap_focus_requested.connect(_focus_minimap)
	_hud.dispatch_region_selected.connect(_create_dispatch_region_from_cells)
	_hud.repair_all_requested.connect(_repair_all)
	_settings.close_requested.connect(_close_settings)
	_settings.settings_applied.connect(_apply_camera_settings)
	_apply_camera_settings(_settings.preferences())
	if _camera.has_method("set_play_area"):
		_camera.set_play_area(_hud.battle_view_rect())
	get_window().focus_exited.connect(_cancel_wall_drag)
	get_window().mouse_exited.connect(_cancel_wall_drag)
	get_window().focus_exited.connect(_cancel_selection_drag)
	get_window().mouse_exited.connect(_cancel_selection_drag)
	_sim.state_changed.connect(_refresh)
	_publish_state()
	if OS.get_cmdline_user_args().has("--overview"):
		_fit_map()
	if OS.get_cmdline_user_args().has("--settings"):
		_open_settings()
	print("[Billions Mech] vision fog ready; 1920x1080; ", "3D development whitebox" if _camera is Camera3D else "2D whitebox", "; ", initial_settings.scenario_name)


func _physics_process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec() if _perf_enabled else 0
	_sim.advance_one_tick()
	if _perf_enabled:
		var elapsed: int = Time.get_ticks_usec() - started
		_perf_sim_usec += elapsed
		_perf_sim_peak_usec = maxi(_perf_sim_peak_usec, elapsed)
		_perf_sim_ticks += 1


func _exit_tree() -> void:
	_sim.shutdown()


func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec() if _perf_enabled else 0
	if _camera.has_method("set_play_area"):
		_camera.set_play_area(_hud.battle_view_rect())
	_publish_state()
	_update_cursor()
	_hud.present_zoom(_camera.zoom_factor())
	_hud.present_camera(_camera.visible_map_polygon())
	if _stress_mode:
		_stress_advance(delta)
	if _perf_enabled:
		var elapsed: int = Time.get_ticks_usec() - started
		_perf_view_usec += elapsed
		_perf_view_peak_usec = maxi(_perf_view_peak_usec, elapsed)
		_perf_frame_peak = maxf(_perf_frame_peak, delta)
		_perf_frames += 1
		_perf_seconds += delta
		if _perf_seconds >= 2.0:
			print("[perf] fps=%.1f draw_calls=%d sim_cpu_ms=%.3f view_cpu_ms=%.3f native_nav_ms=%.3f sim_peak_ms=%.3f view_peak_ms=%.3f frame_peak_ms=%.3f" % [
				_perf_frames / _perf_seconds, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				float(_perf_sim_usec) / maxi(1, _perf_sim_ticks) / 1000.0,
				float(_perf_view_usec) / maxi(1, _perf_frames) / 1000.0,
				Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
				_perf_sim_peak_usec / 1000.0, _perf_view_peak_usec / 1000.0, _perf_frame_peak * 1000.0])
			var profile: Dictionary = _sim.consume_profile()
			if not profile.is_empty():
				var avg_stages: Dictionary = {}
				var peak_stages: Dictionary = {}
				for stage: String in profile["stages"]:
					avg_stages[stage] = snappedf(profile["stages"][stage]["avg_ms"], 0.001)
					peak_stages[stage] = snappedf(profile["stages"][stage]["peak_ms"], 0.001)
				var worst: Dictionary = profile["worst"]
				var worst_stages: Dictionary = worst.get("stages", {})
				var rounded_worst: Dictionary = {}
				for stage: String in worst_stages:
					rounded_worst[stage] = snappedf(worst_stages[stage], 0.001)
				print("[perf:stages] ticks=%d worst_ms=%.3f worst=%s avg_ms=%s peak_ms=%s counters=%s" % [
					profile["ticks"], worst.get("total_ms", 0.0), rounded_worst,
					avg_stages, peak_stages, profile["counters"]])
			_perf_seconds = 0.0
			_perf_frames = 0
			_perf_sim_usec = 0
			_perf_sim_ticks = 0
			_perf_view_usec = 0
			_perf_sim_peak_usec = 0
			_perf_view_peak_usec = 0
			_perf_frame_peak = 0.0


func _stress_advance(delta: float) -> void:
	if _sim.session_ended():
		return
	_stress_timer += delta
	if _stress_timer < 0.5:
		return
	_stress_timer = 0.0
	_stress_step += 1
	if _stress_step % 4 == 0:
		var center: Vector2 = Vector2(SETTINGS.map_definition.mainbrain_origin) + Vector2(24, 0)
		var roster: Array[StringName] = [&"builder", &"builder_worn", &"builder_veteran", &"recycler",
			&"scavenger", &"deflector", &"strider", &"mortar", &"silencer"]
		var offset: int = (_stress_step / 4 - 1) * 2
		_sim.spawn_diagnostic_enemy(roster[offset % roster.size()], center + Vector2(0, -6))
		_sim.spawn_diagnostic_enemy(roster[(offset + 1) % roster.size()], center + Vector2(0, 6))
	if _stress_step % 8 == 0:
		var index: int = 0
		for entity: Dictionary in _state["entities"]:
			if not entity.get("is_unit", false) or entity.get("team", 1) != 1:
				continue
			var goal: Vector2 = Vector2(SETTINGS.map_definition.mainbrain_origin)
			goal += Vector2(40 if index % 2 == 0 else -40, 40 if (index / 2) % 2 == 0 else -40)
			_commands.submit(MechCommand.new(MechCommand.Type.MOVE_ENTITY,
				{"entity_id": entity["id"], "target": goal}))
			index += 1
	var origin: Vector2i = SETTINGS.map_definition.mainbrain_origin
	var footprint: Vector2i = SETTINGS.map_definition.mainbrain_footprint
	if _stress_step % 2 == 1:
		var y: int = origin.y + footprint.y + 2 + (_stress_step % 8)
		var cells: Array[Vector2i] = []
		for x: int in range(origin.x - 4, origin.x + footprint.x + 4):
			cells.append(Vector2i(x, y))
		_commands.submit(MechCommand.new(MechCommand.Type.PLACE_WALL_LINE, {"cells": cells}))
	else:
		for entity: Dictionary in _state["entities"]:
			if entity.get("is_building", false) and entity.get("kind", &"") == &"armored_wall":
				_commands.submit(MechCommand.new(MechCommand.Type.DEMOLISH,
					{"entity_id": entity["id"]}))
				break


func _input(event: InputEvent) -> void:
	if _settings.is_open():
		if event is InputEventKey and event.pressed and not event.echo and _event_key(event) == KEY_ESCAPE:
			_close_settings()
			get_viewport().set_input_as_handled()
		return
	# 鼠标回到战场即恢复跟随，不必先放下第一座建筑。
	if event is InputEventMouseMotion and _build_id != &"" and not event.relative.is_zero_approx() \
			and get_viewport().get_visible_rect().has_point(event.position) and not _hud.blocks_point(event.position):
		_keyboard_build = false
	# 建造快捷键必须先于获得焦点的 HUD 按钮处理，否则按键会被按钮吞掉。
	if event is InputEventKey and event.pressed and not event.echo and not _wall_dragging:
		var key: int = _event_key(event)
		if key in [KEY_Q, KEY_W, KEY_E]:
			_request_build(&"compute_node" if key == KEY_Q else (&"armored_wall" if key == KEY_W else &"sentry_tower"))
			get_viewport().set_input_as_handled()
			return
		if _build_id != &"" and key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER]:
			_handle_key(key)
			get_viewport().set_input_as_handled()
			return
	if _selection_dragging:
		if event is InputEventMouseMotion:
			_selection_end = _clamped_selection_point(event.position)
			_hud.present_drag(Rect2(_selection_start, _selection_end - _selection_start).abs(), _selection_start.distance_to(_selection_end) >= 6.0)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_selection_end = _clamped_selection_point(event.position)
			# 从战场开始的框选允许在HUD上松开，仍按裁剪后的战场矩形提交。
			if _selection_bounds.has_area() and get_viewport().get_visible_rect().has_point(event.position):
				_finish_selection()
			_cancel_selection_drag()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_selection_drag()
			get_viewport().set_input_as_handled()
		return
	if not _wall_dragging:
		return
	if event is InputEventMouseMotion:
		_wall_end = _clamped_line_cell(_mouse_cell())
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_wall_end = _clamped_line_cell(_mouse_cell())
		var cells: Array[Vector2i] = _wall_cells()
		var can_commit: bool = not _hud.blocks_point(event.position) and get_viewport().get_visible_rect().has_point(event.position)
		_cancel_wall_drag()
		if can_commit:
			_commands.submit(MechCommand.new(MechCommand.Type.PLACE_WALL_LINE, {"cells": cells}))
		else:
			_hud.feedback("已取消墙线，没有下单或扣款。")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_build()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _settings.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _event_key(event) >= KEY_1 and _event_key(event) <= KEY_9:
			_handle_group(_event_key(event) - KEY_0, event.ctrl_pressed)
			get_viewport().set_input_as_handled()
			return
		if _handle_key(_event_key(event)):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed and _build_id == &"armored_wall":
		var cell: Vector2i = _mouse_cell()
		if _sim.inspect_cell(cell)["inside"]:
			_wall_dragging = true
			_wall_start = cell
			_wall_end = cell
			_camera.set_external_gesture(true)
			_update_cursor()
			get_viewport().set_input_as_handled()
			return
	if _camera.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _build_id != &"":
			_select_map_position(_camera.screen_to_map(event.position))
		elif _attack_move_mode:
			_issue_unit_order(true)
		elif _is_double_click(event.position):
			_select_same_kind(event.position)
		else:
			_selection_bounds = _hud.selection_bounds(event.position, event.position)
			if not _selection_bounds.has_area():
				return
			_selection_dragging = true
			_selection_start = event.position
			_selection_end = event.position
			_selection_additive = event.shift_pressed
			_selection_toggle = event.ctrl_pressed
			_camera.set_external_gesture(true)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_last_click_ms = 0
		if _build_id != &"":
			_cancel_build()
		elif _attack_move_mode:
			_attack_move_mode = false
			_hud.feedback("已取消攻击移动模式。")
		else:
			_issue_unit_order(false)
		get_viewport().set_input_as_handled()


func _select_map_position(map_position: Vector2) -> void:
	if _hud.blocks_point(get_viewport().get_mouse_position()):
		return
	var cell: Vector2i = _map_cell(map_position)
	if _build_id != &"":
		_keyboard_build = false
	if _build_id != &"":
		_commands.submit(MechCommand.new(MechCommand.Type.PLACE_BUILDING, {"building_id": _build_id, "origin": cell}))
		return
	var info: Dictionary = _sim.inspect_cell(cell)
	if info["inside"]:
		_selected = cell
		_hud.feedback("已选中 (%d, %d)；建筑操作在右侧面板。" % [cell.x, cell.y])
		_refresh_selection()
		_update_cursor()
	else:
		_hud.feedback("请选择地图内的格子。", true)


func _event_key(event: InputEventKey) -> int:
	var key: int = int(event.physical_keycode)
	return key if key != 0 else int(event.keycode)


func _handle_key(key: int) -> bool:
	if _build_id != &"" and key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
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
		_update_cursor()
		return true
	if _build_id != &"" and key == KEY_ENTER:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		if not _keyboard_build and (not get_viewport().get_visible_rect().has_point(mouse) or _hud.blocks_point(mouse)):
			return true
		var cell: Vector2i = _build_cell if _keyboard_build else _mouse_cell()
		_commands.submit(MechCommand.new(MechCommand.Type.PLACE_BUILDING, {"building_id": _build_id, "origin": cell}))
		return true
	match key:
		KEY_F10:
			_open_settings()
		KEY_Q:
			_request_build(&"compute_node")
		KEY_W:
			_request_build(&"armored_wall")
		KEY_E:
			_request_build(&"sentry_tower")
		KEY_A:
			if not _sim.session_ended() and not _selected_units().is_empty() and _build_id == &"":
				_attack_move_mode = true
				_hud.feedback("攻击移动：左键指定目的地，右键或 Esc 取消。")
		KEY_X:
			_hud.request_demolition()
		KEY_G:
			_garrison_selected()
		KEY_U:
			_ungarrison_selected()
		KEY_C:
			_contract_selected(true)
		KEY_V:
			_contract_selected(false)
		KEY_T:
			_request_final_wave()
		KEY_F6:
			_hud.begin_dispatch_region_selection()
		KEY_F7:
			_create_dispatch_region()
		KEY_F8:
			_toggle_dispatch_region()
		KEY_F9:
			_delete_dispatch_region()
		KEY_F11:
			_cycle_dispatch_region()
		KEY_SPACE:
			_toggle_pause()
		KEY_R:
			_restart()
		KEY_F1:
			_focus_mainbrain()
		KEY_HOME:
			_fit_map()
		KEY_M:
			_hud.toggle_minimap_fullscreen()
		KEY_ESCAPE:
			if _hud.is_minimap_fullscreen():
				_hud.set_minimap_fullscreen(false)
			elif _selection_dragging:
				_cancel_selection_drag()
			elif _build_id != &"" or _wall_dragging:
				_cancel_build()
			elif _attack_move_mode:
				_attack_move_mode = false
			else:
				_selection.ids.clear()
				_selected = Vector2i(-1, -1)
				_refresh_selection()
				_update_cursor()
		_:
			return false
	return true


func _toggle_pause() -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": not _sim.is_paused()}))


func _open_settings() -> void:
	if _settings.is_open():
		return
	_cancel_selection_drag()
	_cancel_build()
	_attack_move_mode = false
	_hud.dismiss_dialogs()
	_resume_after_settings = not _sim.is_paused() and not _sim.session_ended()
	if _resume_after_settings:
		_commands.submit(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": true}))
	_camera.input_blocked = true
	_settings.open()


func _close_settings() -> void:
	if not _settings.is_open():
		return
	_settings.close()
	_camera.input_blocked = false
	if _resume_after_settings and not _sim.session_ended():
		_commands.submit(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": false}))
	_resume_after_settings = false


func _apply_camera_settings(preferences: Dictionary) -> void:
	_camera.pan_speed_factor = preferences["pan_speed"]
	_camera.zoom_speed_factor = preferences["zoom_speed"]
	_camera.edge_scroll_enabled = preferences["edge_scroll"]


func _restart() -> void:
	_cancel_selection_drag()
	_cancel_build()
	_commands.submit(MechCommand.new(MechCommand.Type.RESET_SESSION))


func _focus_mainbrain() -> void:
	_cancel_wall_drag()
	_camera.focus_mainbrain()


func _focus_minimap(map_position: Vector2) -> void:
	# 从小地图跳转镜头不打断建造放置（operations.md §3.2）；此处不取消、也不下发任何命令。
	_camera.focus_map(map_position)


func _fit_map() -> void:
	_cancel_wall_drag()
	_camera.fit_map()


func _request_build(id: StringName) -> void:
	if _sim.session_ended():
		_hud.feedback("本局已结束，请重新开始或切换场景。", true)
		return
	_cancel_selection_drag()
	_attack_move_mode = false
	_cancel_wall_drag()
	var state: Dictionary = _state
	for entry: Dictionary in state["catalog"]:
		if entry["building_id"] != id:
			continue
		if not entry["unavailable_reason"].is_empty():
			_hud.feedback(entry["unavailable_reason"], true)
			return
		_build_id = id
		_keyboard_build = false
		_build_cell = _mouse_cell()
		_camera.keyboard_pan_blocked = true
		_hud.present_build(id)
		_coverage.show()
		_hud.feedback("%s：左键下单；方向键移动、Enter下单；右键退出。%s" % [entry["name"], "Shift＋左键拖线可连放墙。" if id == &"armored_wall" else ""])
		_update_cursor()
		return


func _cancel_wall_drag() -> void:
	_wall_dragging = false
	_camera.set_external_gesture(false)


func _cancel_build() -> void:
	_cancel_wall_drag()
	_build_id = &""
	_keyboard_build = false
	_camera.keyboard_pan_blocked = false
	_hud.present_build(&"")
	_coverage.hide()
	_hud.feedback("已退出建造。左键点选/框选，右键下令；选中工厂右键设集结点。")
	_update_cursor()


func _building_action(action: int, entity_id: int) -> void:
	_commands.submit(MechCommand.new(action as MechCommand.Type, {"entity_id": entity_id}))


func _repair_all() -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.REPAIR_ALL, {}))


func _queue_unit(factory_id: int, unit_id: StringName = &"") -> void:
	var payload: Dictionary = {"factory_id": factory_id}
	if unit_id != &"":
		payload["unit_id"] = unit_id
	_commands.submit(MechCommand.new(MechCommand.Type.QUEUE_UNIT, payload))


func _cancel_production(factory_id: int, ticket: int) -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.CANCEL_PRODUCTION, {"factory_id": factory_id, "ticket": ticket}))


func _upgrade_building(entity_id: int) -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.UPGRADE_BUILDING, {"entity_id": entity_id}))


func _cancel_upgrade(entity_id: int) -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.CANCEL_UPGRADE, {"entity_id": entity_id}))


func _select_starting_units() -> void:
	var ids: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity.get("is_unit", false) and entity["team"] == 1:
			ids.append(entity["id"])
	var has_units: bool = not ids.is_empty()
	if ids.is_empty():
		ids.append(_state["mainbrain_id"])
	_selection.select(ids)
	_refresh_selection()
	if has_units:
		_hud.feedback("已选择 %d 个单位。右键移动或攻击；选工厂可生产部队。" % ids.size())


func _garrison_selected() -> void:
	if _sim.session_ended():
		return
	var units: Array[int] = _selected_units()
	if units.is_empty():
		_hud.feedback("先选择卫兵，再按 G 前往附近碉堡进驻。", true)
		return
	for id: int in units:
		_commands.submit(MechCommand.new(MechCommand.Type.GARRISON_UNIT, {"unit_id": id}))
	_hud.feedback("已请求 %d 个单位进驻附近驻防碉堡。" % units.size())


func _ungarrison_selected() -> void:
	if _sim.session_ended() or _selection.ids.is_empty():
		return
	_commands.submit(MechCommand.new(MechCommand.Type.UNGARRISON_UNIT, {"building_id": _selection.ids[0]}))
	_hud.feedback("已请求撤离该碉堡内的驻防单位。")


func _dispatch_regions() -> Array:
	return _state.get("dispatch", {}).get("regions", [])


func _create_dispatch_region() -> void:
	if _sim.session_ended():
		return
	var origin: Vector2i = SETTINGS.map_definition.mainbrain_origin + Vector2i(-2, -2)
	var footprint: Vector2i = SETTINGS.map_definition.mainbrain_footprint + Vector2i(4, 4)
	var cells: Array[Vector2i] = []
	for y: int in range(footprint.y):
		for x: int in range(footprint.x):
			cells.append(origin + Vector2i(x, y))
	_create_dispatch_region_from_cells(cells)


func _create_dispatch_region_from_cells(cells: Array[Vector2i]) -> void:
	if _sim.session_ended() or cells.is_empty():
		return
	_commands.submit(MechCommand.new(MechCommand.Type.CONFIGURE_DISPATCH_REGION, {
		"cells": cells, "enabled": true, "name": "框选区域",
		"budget_cap": {&"coins": 300, &"metal_ore": 30, &"fuel": 20, &"alloy": 20, &"crystals": 8}}))
	_hud.feedback("已请求创建 %d 格授权区域。" % cells.size())


func _toggle_dispatch_region() -> void:
	var regions: Array = _dispatch_regions()
	if regions.is_empty():
		_hud.feedback("没有可切换的授权区域；先按 F7 创建。", true)
		return
	var region: Dictionary = _selected_region(regions)
	_commands.submit(MechCommand.new(MechCommand.Type.CONFIGURE_DISPATCH_REGION, {
		"region_id": int(region["id"]), "cells": region["cells"],
		"enabled": not bool(region.get("enabled", true)), "budget_cap": region["budget_cap"]}))
	_hud.feedback("已请求切换区域授权。")


func _delete_dispatch_region() -> void:
	var regions: Array = _dispatch_regions()
	if regions.is_empty():
		_hud.feedback("没有可删除的授权区域。", true)
		return
	_commands.submit(MechCommand.new(MechCommand.Type.DELETE_DISPATCH_REGION,
		{"region_id": int(_selected_region(regions)["id"])}))
	_hud.feedback("已请求删除授权区域。")


func _request_final_wave() -> void:
	if _sim.session_ended():
		return
	_commands.submit(MechCommand.new(MechCommand.Type.REQUEST_FINAL_WAVE))
	_hud.feedback("已请求终波；需主脑 III 与科技 III，且在 campaign 配置下生效。")


func _contract_selected(accept: bool) -> void:
	if _sim.session_ended() or _selection.ids.is_empty():
		return
	var command: MechCommand.Type = MechCommand.Type.ACCEPT_CONTRACT if accept else MechCommand.Type.CANCEL_CONTRACT
	_commands.submit(MechCommand.new(command, {"building_id": _selection.ids[0]}))
	_hud.feedback("已请求接受合同。" if accept else "已请求取消合同并退款。")


func _cancel_selection_drag() -> void:
	_selection_dragging = false
	_camera.set_external_gesture(false)
	_hud.present_drag(Rect2(), false)
	_selection_bounds = Rect2()


func _clamped_selection_point(point: Vector2) -> Vector2:
	_selection_bounds = _hud.selection_bounds(_selection_start, point)
	if not _selection_bounds.has_area():
		return _selection_start
	return point.clamp(_selection_bounds.position, _selection_bounds.end - Vector2.ONE)


func _screen_position(entity: Dictionary) -> Vector2:
	return _camera.map_to_screen(entity["position"])


func _hit_entity(point: Vector2, enemy: bool = false) -> int:
	if _world.has_method("pick_unit"):
		return _world.pick_unit(point, enemy)
	var best: float = INF
	var result: int = 0
	for entity: Dictionary in _state["entities"]:
		if (entity.get("team", 1) == 2) != enemy or entity.get("is_building", false):
			continue
		var factor: float = _camera.zoom_factor()
		var distance: float = (_screen_position(entity) - Vector2(0, 15) * factor).distance_to(point)
		if distance <= 24.0 * factor and distance < best:
			best = distance
			result = entity["id"]
	return result


func _finish_selection() -> void:
	var ids: Array[int] = []
	var release_cell: Vector2i = _map_cell(_camera.screen_to_map(_selection_end))
	if _selection_start.distance_to(_selection_end) < 6.0:
		var hit: int = _hit_entity(_selection_end)
		if hit > 0:
			ids.append(hit)
		else:
			var building_id: int = _world.pick_building(_selection_end)
			if building_id > 0:
				ids.append(building_id)
			else:
				var building: Dictionary = _sim.building_at(release_cell)
				if not building.is_empty():
					ids.append(building["entity_id"])
	else:
		var rect := Rect2(_selection_start, _selection_end - _selection_start).abs()
		var units: Array[int] = []
		var buildings: Array[int] = []
		for entity: Dictionary in _state["entities"]:
			if entity.get("team", 1) != 1 or not rect.has_point(_screen_position(entity)):
				continue
			if entity.get("is_building", false):
				buildings.append(entity["id"])
			else:
				units.append(entity["id"])
		# 框选优先生效于单位：只要矩形内有任一己方单位，建筑就不进入选择集，避免拖拽时整片基地被连带选中。
		ids = units if not units.is_empty() else buildings
		# 拖框不作为点击起点，重置双击状态，避免紧接着的单击被误判为双击。
		_last_click_ms = 0
	_selection.select(ids, _selection_additive, _selection_toggle)
	_selected = release_cell if _sim.inspect_cell(release_cell)["inside"] else Vector2i(-1, -1)
	_refresh_selection()
	_update_cursor()
	_hud.feedback("已选择 %d 个己方实体；右键下令，A＋左键攻击移动。" % _selection.ids.size())


## 双击判定：同一位置窗口内的第二次左键按下算作双击，并清空状态避免三击重复触发。
func _is_double_click(position: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()
	var doubled: bool = _last_click_ms > 0 and now - _last_click_ms <= DOUBLE_CLICK_MS \
		and _last_click_position.distance_to(position) <= DOUBLE_CLICK_SLOP
	_last_click_ms = 0 if doubled else now
	_last_click_position = position
	return doubled


## 双击选择同种：单位按 kind，建筑按升级链族根（升级前后视为同种）。
func _select_same_kind(point: Vector2) -> void:
	if _hud.blocks_point(point):
		return
	var hit: int = _hit_entity(point)
	if hit > 0:
		var kind: StringName = &""
		for entity: Dictionary in _state["entities"]:
			if entity["id"] == hit:
				kind = entity.get("kind", &"")
				break
		if kind == &"":
			return
		# 同类单位先取屏幕内的；屏幕外单位只有与已选单位相邻时才经链式扩选纳入，
		# 避免一次双击把地图远端零散的同种部队也拉进选择集。
		var same_kind: Array[Dictionary] = []
		var positions: Dictionary[int, Vector2] = {}
		for entity: Dictionary in _state["entities"]:
			if entity.get("team", 1) == 1 and not entity.get("is_building", false) and entity.get("kind", &"") == kind:
				same_kind.append(entity)
				positions[entity["id"]] = entity["position"]
		var chosen: Dictionary[int, bool] = {}
		var units: Array[int] = []
		for entity: Dictionary in same_kind:
			# 屏幕范围由实际相机投影判断，命中的单位始终作为扩选起点。
			if entity["id"] == hit or (_camera.map_point_on_screen(entity["position"]) and not _hud.blocks_point(_screen_position(entity))):
				chosen[entity["id"]] = true
				units.append(entity["id"])
		while not units.is_empty():
			var additions: Array[int] = []
			for entity: Dictionary in same_kind:
				var id: int = entity["id"]
				if chosen.get(id, false):
					continue
				for selected_id: int in units:
					if positions[id].distance_to(positions[selected_id]) <= SAME_KIND_CHAIN_RADIUS:
						additions.append(id)
						break
			if additions.is_empty():
				break
			for id: int in additions:
				chosen[id] = true
			units.append_array(additions)
		_selection.select(units)
		_refresh_selection()
		_update_cursor()
		_hud.feedback("已选择 %d 个同类单位；右键下令。" % units.size())
		return
	var building_id: int = _world.pick_building(point)
	var target: Dictionary = {}
	if building_id > 0:
		for entity: Dictionary in _state["entities"]:
			if entity["id"] == building_id:
				target = entity
				break
	else:
		target = _sim.building_at(_mouse_cell())
	var family: StringName = target.get("family_id", &"")
	if family == &"":
		return
	var buildings: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity.get("is_building", false) and entity.get("team", 1) == 1 and entity.get("family_id", &"") == family:
			buildings.append(entity["id"])
	_selection.select(buildings)
	_refresh_selection()
	_update_cursor()
	_hud.feedback("已选择 %d 座同类建筑（升级前后视为同种）。" % buildings.size())


func _selected_units() -> Array[int]:
	var ids: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity["id"] in _selection.ids and entity.get("is_unit", false) and entity["team"] == 1:
			ids.append(entity["id"])
	return ids


func _issue_unit_order(attack_move: bool) -> void:
	if _sim.session_ended():
		_hud.feedback("本局已结束，请重新开始或切换场景。", true)
		return
	var ids: Array[int] = _selected_units()
	var cell: Vector2i = _mouse_cell()
	var goal: Vector2 = _camera.screen_to_map(get_viewport().get_mouse_position())
	if not goal.is_finite():
		return
	if not ids.is_empty():
		var target_id: int = _hit_entity(get_viewport().get_mouse_position(), true)
		_commands.submit(MechCommand.new(MechCommand.Type.ISSUE_UNIT_ORDER, {
			"ids": ids, "kind": &"attack" if target_id > 0 else (&"attack_move" if attack_move else &"move"),
			"goal": goal, "target_id": target_id}))
	else:
		for entity: Dictionary in _state["entities"]:
			if not entity["id"] in _selection.ids:
				continue
			if not entity.get("produced_units", []).is_empty():
				_commands.submit(MechCommand.new(MechCommand.Type.SET_RALLY, {"factory_id": entity["id"], "cell": cell}))
				break
			elif entity["kind"] == &"probe":
				_commands.submit(MechCommand.new(MechCommand.Type.MOVE_ENTITY, {"entity_id": entity["id"], "target": goal}))
	_attack_move_mode = false


func _handle_group(number: int, store: bool) -> void:
	if store:
		var now: int = Time.get_ticks_msec()
		if _last_group == number and now - _last_group_time < 400:
			var kind: StringName = &""
			for entity: Dictionary in _state["entities"]:
				if entity["id"] in _selection.ids and entity.get("is_building", false):
					kind = entity["kind"]
					break
			if kind != &"":
				var ids: Array[int] = []
				for entity: Dictionary in _state["entities"]:
					if entity["kind"] == kind:
						ids.append(entity["id"])
				_selection.select(ids)
		_selection.store_group(number)
		_last_group = number
		_last_group_time = now
		_hud.feedback("编队 %d 已保存：%d 个实体。" % [number, _selection.ids.size()])
	else:
		_selection.recall_group(number)
		_hud.feedback("已召回编队 %d：%d 个实体。" % [number, _selection.ids.size()])
	_refresh_selection()


func _on_command_finished(command_type: int, result: Dictionary) -> void:
	if not result["ok"]:
		_hud.feedback(result["reason"], true)
		return
	match command_type:
		MechCommand.Type.CONFIGURE_DISPATCH_REGION:
			_selected_dispatch_region = int(result["region_id"])
			_hud.feedback("已选择授权区域 #%d；F11切换，F8启停，F9删除。" % _selected_dispatch_region)
		MechCommand.Type.GARRISON_UNIT:
			_hud.feedback("已收到进驻指令；抵达碉堡入口后进驻。")
		MechCommand.Type.UNGARRISON_UNIT:
			_hud.feedback("已撤离 %d 名卫兵；出口被占时其余单位留在碉堡。" % int(result["ejected"]))
		MechCommand.Type.SET_PAUSED:
			_hud.feedback("已暂停，可继续建造、取消和下令；施工与收入已冻结。" if _sim.is_paused() else "模拟已恢复。")
		MechCommand.Type.PLACE_BUILDING:
			_selected = result["origin"]
			_selection.select([int(result["entity_id"])])
			_refresh_selection()
			_hud.feedback("已下单，支付 %s；保持建造模式，可连续放置。" % MechResources.text(result["cost"]))
		MechCommand.Type.PLACE_WALL_LINE:
			_hud.feedback("墙线已下单 %d 段，跳过 %d 格，共支付 %s。" % [result["placed"], result["skipped"], MechResources.text(result["cost"])])
		MechCommand.Type.CANCEL_CONSTRUCTION:
			_hud.feedback("施工已取消，返还 %s 并释放占用。" % MechResources.text(result["refund"]))
		MechCommand.Type.DEMOLISH:
			_hud.feedback("基座已立即清除，无退款，占地与矿点绑定已释放。" if result.get("clearing", false) else "建筑已立即拆除，返还 %s，占用和订单已结清。" % MechResources.text(result["refund"]))
		MechCommand.Type.CANCEL_DEMOLISH:
			_hud.feedback("清除已取消，基座保留原地。" if result.get("was_clearing", false) else "拆除已取消，血量保持，建筑恢复工作。")
		MechCommand.Type.TOGGLE_REPAIR:
			_hud.feedback("维修开关已更新；按模拟时间扣费回血，资金不足时等待。")
		MechCommand.Type.REBUILD:
			_hud.feedback("重建已下单，支付 %s；完工后恢复运行。" % MechResources.text(result["cost"]))
		MechCommand.Type.REPAIR_ALL:
			_hud.feedback("已对 %d 座受损建筑开启维修。" % result["count"])
		MechCommand.Type.MOVE_ENTITY:
			_hud.feedback("移动目标已更新。" if not _sim.is_paused() else "目标已更新，恢复后移动。")
		MechCommand.Type.RESET_SESSION:
			_hud.feedback("当前场景已重置，队列、部队、编队、矿点和账本已恢复。")
		MechCommand.Type.LOAD_SCENARIO:
			Engine.physics_ticks_per_second = _sim.tick_rate()
			_hud.feedback("已进入%s。选择部队右键移动/攻击，选工厂生产或设置集结点。" % result["scenario"])
		MechCommand.Type.QUEUE_UNIT:
			_hud.feedback("已付款并预留容量，卫兵进入工厂队列。")
		MechCommand.Type.CANCEL_PRODUCTION:
			_hud.feedback("生产订单已取消，返还 %s 并释放容量。" % MechResources.text(result["refund"]))
		MechCommand.Type.UPGRADE_BUILDING:
			_hud.feedback("升级已下单，支付差价 %s；旧级服务保持到完工。" % MechResources.text(result["cost"]))
		MechCommand.Type.CANCEL_UPGRADE:
			_hud.feedback("升级已取消，返还本次差价 %s。" % MechResources.text(result["refund"]))
		MechCommand.Type.REQUEST_FINAL_WAVE:
			_hud.feedback("终波已请求；待波次出完并清场后判定胜利。")
		MechCommand.Type.SET_RALLY:
			_hud.feedback("集结点已更新，新出厂部队将自动前往。")
		MechCommand.Type.ISSUE_UNIT_ORDER:
			var label: String = {&"move": "移动", &"attack_move": "攻击移动", &"attack": "攻击"}.get(result["kind"], "指令")
			_hud.feedback("%d 名卫兵已收到%s指令。" % [result["count"], label])
	_update_cursor()


func _refresh() -> void:
	# 命令、伤害与 RVO 都可能在一帧内多次通知；统一由 _process 打包一次发布，输入与渲染始终读取同一份已发布状态。
	_state_dirty = true


func _publish_state() -> void:
	if not _state_dirty:
		return
	_state_dirty = false
	_state = _sim.snapshot()
	var state: Dictionary = _state
	var generation_changed: bool = _last_generation != state["generation"]
	if generation_changed:
		_session_logged = false
		_selected_dispatch_region = 0
	_selected_region(state.get("dispatch", {}).get("regions", []))
	state["dispatch"]["selected_region_id"] = _selected_dispatch_region
	var ended: bool = state["session"]["ended"]
	if ended and not _session_logged:
		_session_logged = true
		var record: Dictionary = {
			"outcome": String(state["session"]["outcome"]),
			"reason": String(state["session"]["reason"]),
			"duration_seconds": float(state["session"].get("duration_seconds", 0.0)),
			"wave_number": int(state["session"].get("wave_number", 0)),
			"final_phase": String(state["session"].get("final_phase", "none")),
			"scenario": String(state["scenario"]),
		}
		var file: FileAccess = FileAccess.open("user://session-record.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(record, "  "))
			file.close()
	_present_threat(state)
	var alert: Dictionary = state.get("alert", {})
	if not alert.is_empty():
		var key: String = "%d_%d" % [state["generation"], alert["sequence"]]
		if key != _last_alert_key:
			_last_alert_key = key
			_hud.feedback(alert["text"], true)
	if _last_generation != state["generation"]:
		_selection.reset()
		_attack_move_mode = false
		_last_group = -1
	_selection.reconcile(state["entities"], state.get("garrisoned_unit_ids", []))
	_world.present(state)
	_hud.present_state(state)
	if _last_generation != state["generation"] or _last_map_revision != state["map_revision"] \
			or _last_coverage_revision != state["coverage_revision"]:
		var map_state: Dictionary = _sim.map_snapshot()
		if generation_changed:
			_terrain.present_map(map_state)
		_coverage.present_map(map_state)
		_hud.present_map(map_state)
		_dimensions = map_state["dimensions"]
		_map_outline = map_state["outline"]
		if _last_generation != state["generation"]:
			_selected = Vector2i(-1, -1)
			_camera.configure_map(map_state)
		_last_generation = state["generation"]
		_last_map_revision = state["map_revision"]
		_last_coverage_revision = state["coverage_revision"]
	_fog.present(state["vision"], state["generation"], _map_outline)
	_terrain.present_vision(state["vision"])
	if generation_changed:
		_select_starting_units()
	else:
		_refresh_selection()
	if ended and not _last_session_ended:
		_cancel_selection_drag()
		_cancel_build()
		_attack_move_mode = false
		if state["session"]["outcome"] == &"victory":
			_hud.feedback("威胁已清除，防守胜利。可查看战场或重新开始。", true)
		else:
			_hud.feedback("主脑已被摧毁，本局结束。可查看战场或重新开始。", true)
	_last_session_ended = ended


func _present_threat(state: Dictionary) -> void:
	# 过渡到"已宣告"阶段的临时播报：一行文字提示；正式的波次槽位 HUD 随 M5-04 批次提供。
	var threat: Dictionary = state.get("threat", {})
	if threat.is_empty() or not threat.get("active", false):
		_last_threat_key = ""
		return
	var key: String = "%s_%d_%s" % [String(threat.get("phase", &"")), int(threat.get("wave_index", 0)), String(threat.get("edge", &""))]
	if key == _last_threat_key:
		return
	_last_threat_key = key
	if threat.get("phase", &"") == &"announced":
		_hud.feedback("侦测到%s机潮，方向：%s。" % [threat.get("tier", ""), threat.get("edge_name", "")])


func _refresh_selection() -> void:
	var state: Dictionary = _state
	var building: Dictionary = {}
	var units: Array[Dictionary] = []
	for entity: Dictionary in state["entities"]:
		if not entity["id"] in _selection.ids:
			continue
		if entity.get("is_building", false) and building.is_empty():
			building = entity
		elif entity.get("is_unit", false):
			units.append(entity)
	var errors: Dictionary = {}
	if not building.is_empty():
		var entity_id: int = building["entity_id"]
		errors = {"cancel": _sim.building_action_error(MechCommand.Type.CANCEL_CONSTRUCTION, entity_id),
			"demolish": _sim.building_action_error(MechCommand.Type.DEMOLISH, entity_id),
			"cancel_demolish": _sim.building_action_error(MechCommand.Type.CANCEL_DEMOLISH, entity_id),
			"repair": _sim.building_action_error(MechCommand.Type.TOGGLE_REPAIR, entity_id),
			"rebuild": _sim.building_action_error(MechCommand.Type.REBUILD, entity_id)}
	_hud.present_selection(building, errors)
	if building.is_empty() and not units.is_empty():
		_hud.present_units(units)
	_world.present_selection(_selection.ids)


func _mouse_cell() -> Vector2i:
	return _map_cell(_camera.screen_to_map(get_viewport().get_mouse_position()))


func _map_cell(point: Vector2) -> Vector2i:
	return Vector2i(point.floor()) if point.is_finite() else Vector2i(-1, -1)


func _clamped_line_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, -1, _dimensions.x), clampi(cell.y, -1, _dimensions.y))


func _wall_cells() -> Array[Vector2i]:
	return Geometry2D.bresenham_line(_wall_start, _wall_end)


func _update_cursor() -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var cursor_visible: bool = not _settings.is_open() and get_window().has_focus() and get_viewport().get_visible_rect().has_point(mouse) and not _hud.blocks_point(mouse)
	var keyboard_cursor_visible: bool = _build_id != &"" and _keyboard_build and not _settings.is_open() and get_window().has_focus()
	var cell: Vector2i = _build_cell if _build_id != &"" and _keyboard_build else _mouse_cell()
	var info: Dictionary = {}
	if cursor_visible or keyboard_cursor_visible:
		info = _sim.inspect_cell(cell)
	elif _selected.x >= 0:
		info = _sim.inspect_cell(_selected)
	var preview: Dictionary = {}
	if _wall_dragging:
		preview = _sim.preview_wall_line(_wall_cells())
	elif (cursor_visible or keyboard_cursor_visible) and _build_id != &"":
		preview = _sim.preview_build(_build_id, cell)
	_world.present_cursor(cell, _selected, preview, cursor_visible or _wall_dragging or keyboard_cursor_visible)
	_hud.present_cell(info, preview)


func _selected_region(regions: Array) -> Dictionary:
	for region: Dictionary in regions:
		if int(region["id"]) == _selected_dispatch_region:
			return region
	if not regions.is_empty():
		_selected_dispatch_region = int(regions[0]["id"])
		return regions[0]
	_selected_dispatch_region = 0
	return {}


func _cycle_dispatch_region() -> void:
	var regions: Array = _dispatch_regions()
	if regions.is_empty():
		_hud.feedback("没有可选择的授权区域。", true)
		return
	_selected_region(regions)
	for index: int in range(regions.size()):
		if int(regions[index]["id"]) == _selected_dispatch_region:
			_selected_dispatch_region = int(regions[(index + 1) % regions.size()]["id"])
			break
	_state_dirty = true
	_hud.feedback("已选择授权区域 #%d；F8启停，F9删除。" % _selected_dispatch_region)
