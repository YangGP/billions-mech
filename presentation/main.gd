extends Node
## 组合根：装配模拟、命令队列与全部表现层视图；只有命令可以改变模拟状态。

const SETTINGS: MechFoundationSettings = preload("res://content/development_128.tres")
var _session_settings: MechFoundationSettings = SETTINGS

var _sim := MechSimCore.new()
var _commands := MechCommandQueue.new()
## 三维战场只消费快照；只有命令可以改变模拟。
@onready var _terrain: MechTerrainView3D = $Terrain
@onready var _coverage: MechCoverageView3D = $Coverage
@onready var _world: MechFoundationView3D = $Entities
@onready var _fog: MechFogView3D = $Fog
@onready var _camera: MechMapCamera3D = $MapCamera
@onready var _hud: MechMapHud = $HUD
@onready var _settings: MechSettingsMenu = $Settings
@onready var _return_dialog: ConfirmationDialog = $ReturnDialog
var _resume_after_settings: bool = false
var _resume_after_return: bool = false
var _last_generation: int = -1
var _last_map_revision: int = -1
var _stress_mode: bool = false
var _stress_timer: float = 0.0
var _stress_step: int = 0
var _stress_enemies: int = 0
var _stress_population_generation: int = -1
var _session_logged: bool = false
var _selected_dispatch_region: int = 0
var _last_coverage_revision: int = -1
var _map_outline := PackedVector2Array()
var _selection := MechSelectionController.new()
var _build := MechBuildController.new()
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
	# 部分 Windows/DPI 配置会把窗口恢复到屏幕外，这里把启动位置钳制回可用区域，确保工具栏始终可及。
	var window := get_window()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect()
	var position: Vector2i = window.position
	position.x = clampi(position.x, usable.position.x, maxi(usable.position.x, usable.end.x - window.size.x))
	position.y = clampi(position.y, usable.position.y, maxi(usable.position.y, usable.end.y - window.size.y))
	window.position = position
	_stress_mode = OS.get_cmdline_user_args().has("--stress")
	_perf_enabled = OS.get_cmdline_user_args().has("--perf")
	if _stress_mode:
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--stress-enemies="):
				_stress_enemies = clampi(argument.get_slice("=", 1).to_int(), 0, 4000)
		if _stress_enemies > 0:
			_perf_enabled = true
	_sim.profiling_enabled = _perf_enabled
	if get_tree().has_meta(&"mech_session_settings"):
		_session_settings = get_tree().get_meta(&"mech_session_settings")
		get_tree().remove_meta(&"mech_session_settings")
	var initial_settings: MechFoundationSettings = _session_settings.duplicate(true)
	var campaign_mode: bool = OS.get_cmdline_user_args().has("--campaign")
	if get_tree().has_meta(&"mech_campaign_mode"):
		campaign_mode = bool(get_tree().get_meta(&"mech_campaign_mode"))
		get_tree().remove_meta(&"mech_campaign_mode")
	if campaign_mode:
		initial_settings.campaign_mode = true
		initial_settings.scenario_name += " · 三阶段战役"
	Engine.physics_ticks_per_second = initial_settings.simulation_hz
	if not _sim.configure(initial_settings):
		get_tree().quit(1)
		return
	_commands.configure(_sim.execute_command)
	_selection.configure(_sim, _commands, _hud, _world, _camera, get_viewport())
	_build.configure(_sim, _commands, _hud, _world, _camera, _coverage, get_viewport(), get_window())
	_selection.cursor_changed.connect(_update_cursor)
	_build.cursor_changed.connect(_update_cursor)
	_world.configure(initial_settings)
	_commands.command_finished.connect(_on_command_finished)
	_coverage.hide()
	_hud.pause_requested.connect(_toggle_pause)
	_hud.restart_requested.connect(_restart)
	_hud.main_menu_requested.connect(_request_main_menu)
	_hud.focus_requested.connect(_focus_mainbrain)
	_hud.fit_requested.connect(_fit_map)
	_hud.build_requested.connect(_request_build)
	_hud.build_cancelled.connect(_build.cancel)
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
	_return_dialog.theme = $HUD/Root.theme
	_return_dialog.confirmed.connect(_return_to_main_menu)
	_return_dialog.canceled.connect(_cancel_return)
	_apply_camera_settings(_settings.preferences())
	_camera.set_play_area(_hud.battle_view_rect())
	get_window().focus_exited.connect(_build.cancel_wall_drag)
	get_window().mouse_exited.connect(_build.cancel_wall_drag)
	get_window().focus_exited.connect(_selection.cancel_drag)
	get_window().mouse_exited.connect(_selection.cancel_drag)
	_sim.state_changed.connect(_refresh)
	_publish_state()
	if OS.get_cmdline_user_args().has("--overview"):
		_fit_map()
	if OS.get_cmdline_user_args().has("--settings"):
		_open_settings()
	print("[Billions Mech] vision fog ready; 1920x1080; ", "3D development whitebox", "; ", initial_settings.scenario_name)


func _physics_process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec() if _perf_enabled else 0
	_sim.advance_one_tick()
	if _perf_enabled:
		var elapsed: int = Time.get_ticks_usec() - started
		_perf_sim_usec += elapsed
		_perf_sim_peak_usec = maxi(_perf_sim_peak_usec, elapsed)
		_perf_sim_ticks += 1
	if _stress_mode and _stress_enemies > 0 and _stress_population_generation != _last_generation:
		# 首个模拟tick先释放正常的初始散兵，再补足目标总数；预置耗时不混入常规tick均值。
		var seed_started: int = Time.get_ticks_usec()
		var seeded: Dictionary = _sim.seed_diagnostic_population(_stress_enemies)
		_stress_population_generation = _last_generation
		print("[stress:population] requested=%d result=%s generation=%d setup_ms=%.3f" % [_stress_enemies, seeded, _last_generation, (Time.get_ticks_usec() - seed_started) / 1000.0])


func _exit_tree() -> void:
	_sim.shutdown()


func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec() if _perf_enabled else 0
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
			print("[perf] fps=%.1f draw_calls=%d sim_cpu_ms=%.3f view_cpu_ms=%.3f native_nav_ms=%.3f sim_peak_ms=%.3f view_peak_ms=%.3f frame_peak_ms=%.3f tick=%d paused=%s ended=%s" % [
				_perf_frames / _perf_seconds, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				float(_perf_sim_usec) / maxi(1, _perf_sim_ticks) / 1000.0,
				float(_perf_view_usec) / maxi(1, _perf_frames) / 1000.0,
				Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
				_perf_sim_peak_usec / 1000.0, _perf_view_peak_usec / 1000.0, _perf_frame_peak * 1000.0,
				_state["clock"]["tick"], _sim.is_paused(), _sim.session_ended()])
			var profile: Dictionary = _sim.consume_profile()
			if not profile.is_empty():
				var visible_enemies: int = 0
				for entity: Dictionary in _state["entities"]:
					if entity.get("team", 1) == 2:
						visible_enemies += 1
				print("[perf:population] total=%s visible_enemies=%d" % [profile["population"], visible_enemies])
				# 只读采样真实模型求交耗时；不合成输入或改变选择。
				var pick_started: int = Time.get_ticks_usec()
				var picked_id: int = _world.pick_entity(_hud.battle_view_rect().get_center())
				print("[perf:pick] center_id=%d cpu_ms=%.3f" % [picked_id, (Time.get_ticks_usec() - pick_started) / 1000.0])
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
		var center: Vector2 = Vector2(_session_settings.map_definition.mainbrain_origin) + Vector2(24, 0)
		var roster: Array[StringName] = [&"builder", &"builder_worn", &"builder_veteran", &"recycler", &"provoker",
			&"scavenger", &"deflector", &"strider", &"mortar", &"silencer"]
		var offset: int = (_stress_step / 4 - 1) * 2
		_sim.spawn_diagnostic_enemy(roster[offset % roster.size()], center + Vector2(0, -6))
		_sim.spawn_diagnostic_enemy(roster[(offset + 1) % roster.size()], center + Vector2(0, 6))
	if _stress_step % 8 == 0:
		var index: int = 0
		for entity: Dictionary in _state["entities"]:
			if not entity.get("is_unit", false) or entity.get("team", 1) != 1:
				continue
			var goal: Vector2 = Vector2(_session_settings.map_definition.mainbrain_origin)
			goal += Vector2(40 if index % 2 == 0 else -40, 40 if (index / 2) % 2 == 0 else -40)
			_commands.submit(MechCommand.new(MechCommand.Type.MOVE_ENTITY,
				{"entity_id": entity["id"], "target": goal}))
			index += 1
	var origin: Vector2i = _session_settings.map_definition.mainbrain_origin
	var footprint: Vector2i = _session_settings.map_definition.mainbrain_footprint
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
	if _return_dialog.visible:
		return
	if _settings.is_open():
		if event is InputEventKey and event.pressed and not event.echo and _event_key(event) == KEY_ESCAPE:
			_close_settings()
			get_viewport().set_input_as_handled()
		return
	_build.follow_mouse(event)
	# 建造快捷键先于获得焦点的HUD按钮；拖墙期间不切换类型。
	if event is InputEventKey and event.pressed and not event.echo and not _build.wall_dragging:
		var key: int = _event_key(event)
		if key in [KEY_Q, KEY_W, KEY_E]:
			_request_build(&"compute_node" if key == KEY_Q else (&"armored_wall" if key == KEY_W else &"sentry_tower"))
			get_viewport().set_input_as_handled()
			return
		if _build.handle_key(key):
			get_viewport().set_input_as_handled()
			return
	if _selection.dragging:
		if _selection.handle_drag_event(event):
			get_viewport().set_input_as_handled()
		return
	if _build.handle_wall_event(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _settings.is_open() or _return_dialog.visible:
		return
	if event is InputEventMouseButton and (not get_viewport().get_visible_rect().has_point(event.position) or _hud.blocks_point(event.position)):
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _build.building_id != &"":
			_build.cancel()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _event_key(event) >= KEY_1 and _event_key(event) <= KEY_9:
			_selection.handle_group(_event_key(event) - KEY_0, event.ctrl_pressed)
			get_viewport().set_input_as_handled()
			return
		if _handle_key(_event_key(event)):
			get_viewport().set_input_as_handled()
			return
	if _build.begin_wall(event):
		get_viewport().set_input_as_handled()
		return
	if _camera.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _build.building_id != &"":
			_build.place_at(_camera.screen_to_map(event.position))
		elif not _selection.left_click(event):
			return
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if _build.building_id != &"":
			_selection.reset_click()
			_build.cancel()
		else:
			_selection.right_click()
		get_viewport().set_input_as_handled()


func _event_key(event: InputEventKey) -> int:
	var key: int = int(event.physical_keycode)
	return key if key != 0 else int(event.keycode)


func _handle_key(key: int) -> bool:
	if _build.handle_key(key):
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
			if not _sim.session_ended() and not _selection.selected_units().is_empty() and _build.building_id == &"":
				_selection.attack_move_mode = true
				_hud.feedback("攻击移动：左键指定目的地，右键或 Esc 取消。")
		KEY_X:
			_hud.request_demolition()
		KEY_G:
			_garrison_selected()
		KEY_U:
			_ungarrison_selected()
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
			elif _selection.dragging:
				_selection.cancel_drag()
			elif _build.building_id != &"" or _build.wall_dragging:
				_build.cancel()
			elif _selection.attack_move_mode:
				_selection.attack_move_mode = false
			else:
				_selection.clear_selection()
		_:
			return false
	return true


func _toggle_pause() -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": not _sim.is_paused()}))


func _open_settings() -> void:
	if _settings.is_open() or _return_dialog.visible:
		return
	_selection.cancel_drag()
	_build.cancel()
	_selection.attack_move_mode = false
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
	_selection.cancel_drag()
	_build.cancel()
	_commands.submit(MechCommand.new(MechCommand.Type.RESET_SESSION))


func _request_main_menu() -> void:
	if _settings.is_open() or _return_dialog.visible:
		return
	_selection.cancel_drag()
	_build.cancel()
	_selection.attack_move_mode = false
	_hud.dismiss_dialogs()
	_resume_after_return = not _sim.is_paused() and not _sim.session_ended()
	if _resume_after_return:
		_commands.submit(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": true}))
	_camera.input_blocked = true
	_return_dialog.popup_centered(Vector2i(600, 220))


func _cancel_return() -> void:
	_return_dialog.hide()
	_camera.input_blocked = false
	if _resume_after_return and not _sim.session_ended():
		_commands.submit(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": false}))
	_resume_after_return = false


func _return_to_main_menu() -> void:
	get_tree().set_meta(&"mech_show_main_menu", true)
	var error: Error = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if error != OK:
		get_tree().remove_meta(&"mech_show_main_menu")
		_cancel_return()
		_hud.feedback("主菜单加载失败（%s），请重试。" % error_string(error))


func _focus_mainbrain() -> void:
	_build.cancel_wall_drag()
	_camera.focus_mainbrain()


func _focus_minimap(map_position: Vector2) -> void:
	# 从小地图跳转镜头不打断建造放置（operations.md §3.2）；此处不取消、也不下发任何命令。
	_camera.focus_map(map_position)


func _fit_map() -> void:
	_build.cancel_wall_drag()
	_camera.fit_map()


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


func _garrison_selected() -> void:
	if _sim.session_ended():
		return
	var units: Array[int] = _selection.selected_units()
	if units.is_empty():
		_hud.feedback("先选择卫兵，再按 G 前往附近碉堡进驻。", true)
		return
	for id: int in units:
		_commands.submit(MechCommand.new(MechCommand.Type.GARRISON_UNIT, {"unit_id": id}))
	_hud.feedback("已请求 %d 个单位进驻附近驻防碉堡。" % units.size())


func _ungarrison_selected() -> void:
	if _sim.session_ended() or _selection.selected_ids.is_empty():
		return
	_commands.submit(MechCommand.new(MechCommand.Type.UNGARRISON_UNIT, {"building_id": _selection.selected_ids[0]}))
	_hud.feedback("已请求撤离该碉堡内的驻防单位。")


func _dispatch_regions() -> Array:
	return _state.get("dispatch", {}).get("regions", [])


func _create_dispatch_region() -> void:
	if _sim.session_ended():
		return
	var origin: Vector2i = _session_settings.map_definition.mainbrain_origin + Vector2i(-2, -2)
	var footprint: Vector2i = _session_settings.map_definition.mainbrain_footprint + Vector2i(4, 4)
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
			_selection.select_building(int(result["entity_id"]), result["origin"])
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
		_stress_timer = 0.0
		_stress_step = 0
		_stress_population_generation = -1
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
	_selection.update_state(state, generation_changed)
	_world.present(state)
	_hud.present_state(state)
	if _last_generation != state["generation"] or _last_map_revision != state["map_revision"] \
			or _last_coverage_revision != state["coverage_revision"]:
		var map_state: Dictionary = _sim.map_snapshot()
		if generation_changed:
			_terrain.present_map(map_state)
		_coverage.present_map(map_state)
		_hud.present_map(map_state)
		_build.dimensions = map_state["dimensions"]
		_map_outline = map_state["outline"]
		if _last_generation != state["generation"]:
			_camera.configure_map(map_state)
		_last_generation = state["generation"]
		_last_map_revision = state["map_revision"]
		_last_coverage_revision = state["coverage_revision"]
	_fog.present(state["vision"], state["generation"], _map_outline)
	_terrain.present_vision(state["vision"])
	if generation_changed:
		_selection.select_starting_units()
	else:
		_selection.present_selection()
	if ended and not _last_session_ended:
		_selection.cancel_drag()
		_build.cancel()
		_selection.attack_move_mode = false
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


func _request_build(id: StringName) -> void:
	if _sim.session_ended():
		_hud.feedback("本局已结束，请重新开始或切换场景。", true)
		return
	_selection.cancel_drag()
	_selection.attack_move_mode = false
	_build.request(id, _state["catalog"])


func _update_cursor() -> void:
	_build.present_cursor(_selection.selected_cell, _settings.is_open())
