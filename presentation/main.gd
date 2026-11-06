extends Node2D
## Composition root. Only commands may change simulation state.

const SETTINGS: MechFoundationSettings = preload("res://content/foundation.tres")
const TRAINING_SETTINGS: MechFoundationSettings = preload("res://content/training.tres")

var _sim := MechSimCore.new()
var _commands := MechCommandQueue.new()
@onready var _terrain: MechTerrainView = $Terrain
@onready var _coverage: MechCoverageView = $Coverage
@onready var _world: MechFoundationView = $Entities
@onready var _camera: MechMapCamera = $MapCamera
@onready var _hud: MechMapHud = $HUD
var _last_generation: int = -1
var _last_map_revision: int = -1
var _selected := Vector2i(-1, -1)
var _build_id: StringName = &""
var _wall_dragging: bool = false
var _wall_start := Vector2i.ZERO
var _wall_end := Vector2i.ZERO
var _dimensions := Vector2i.ZERO
var _selection := MechSelectionState.new()
var _selection_dragging: bool = false
var _selection_start := Vector2.ZERO
var _selection_end := Vector2.ZERO
var _selection_additive: bool = false
var _selection_toggle: bool = false
var _attack_move_mode: bool = false
var _last_group: int = -1
var _last_group_time: int = 0
var _last_threat_key: String = ""
var _state: Dictionary = {}
var _state_dirty: bool = true
var _last_session_ended: bool = false


func _ready() -> void:
	var initial_settings: MechFoundationSettings = TRAINING_SETTINGS if OS.get_cmdline_user_args().has("--training") else SETTINGS
	Engine.physics_ticks_per_second = initial_settings.simulation_hz
	if not _sim.configure(initial_settings):
		get_tree().quit(1)
		return
	_commands.configure(_sim.execute_command)
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
	_hud.scenario_requested.connect(_toggle_scenario)
	get_window().focus_exited.connect(_cancel_wall_drag)
	get_window().mouse_exited.connect(_cancel_wall_drag)
	get_window().focus_exited.connect(_cancel_selection_drag)
	get_window().mouse_exited.connect(_cancel_selection_drag)
	_sim.state_changed.connect(_refresh)
	_publish_state()
	print("[Billions Mech] M5 threat and defense ready; 1920x1080; whitebox; ", initial_settings.scenario_name)


func _physics_process(_delta: float) -> void:
	_sim.advance_one_tick()


func _exit_tree() -> void:
	_sim.shutdown()


func _process(_delta: float) -> void:
	_publish_state()
	_update_cursor()
	_hud.present_zoom(_camera.zoom.x)


func _input(event: InputEvent) -> void:
	if _selection_dragging:
		if event is InputEventMouseMotion:
			_selection_end = event.position
			_hud.present_drag(Rect2(_selection_start, _selection_end - _selection_start).abs(), _selection_start.distance_to(_selection_end) >= 6.0)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_selection_end = event.position
			if get_viewport_rect().has_point(event.position) and not _hud.blocks_point(event.position):
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
		var can_commit: bool = not _hud.blocks_point(event.position) and get_viewport_rect().has_point(event.position)
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			_handle_group(event.physical_keycode - KEY_0, event.ctrl_pressed)
			get_viewport().set_input_as_handled()
			return
		if _handle_key(event.physical_keycode):
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
			_select_world_position(_world.get_global_mouse_position())
		elif _attack_move_mode:
			_issue_unit_order(true)
		else:
			_selection_dragging = true
			_selection_start = event.position
			_selection_end = event.position
			_selection_additive = event.shift_pressed
			_selection_toggle = event.ctrl_pressed
			_camera.set_external_gesture(true)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if _build_id != &"":
			_cancel_build()
		elif _attack_move_mode:
			_attack_move_mode = false
			_hud.feedback("已取消攻击移动模式。")
		else:
			_issue_unit_order(false)
		get_viewport().set_input_as_handled()


func _select_world_position(world_position: Vector2) -> void:
	if _hud.blocks_point(get_viewport().get_mouse_position()):
		return
	var cell: Vector2i = MechIsoGeometry.cell_at(_world.to_local(world_position))
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


func _handle_key(key: int) -> bool:
	match key:
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
		KEY_SPACE:
			_toggle_pause()
		KEY_R:
			_restart()
		KEY_F1:
			_focus_mainbrain()
		KEY_HOME:
			_fit_map()
		KEY_ESCAPE:
			if _selection_dragging:
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


func _restart() -> void:
	_cancel_selection_drag()
	_cancel_build()
	_commands.submit(MechCommand.new(MechCommand.Type.RESET_SESSION))


func _focus_mainbrain() -> void:
	_cancel_wall_drag()
	_camera.focus_mainbrain()


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
		_hud.present_build(id)
		_coverage.show()
		_hud.feedback("%s：左键下单，中键拖图；右键退出。%s" % [entry["name"], "Shift＋左键拖线可连放墙。" if id == &"armored_wall" else ""])
		_update_cursor()
		return


func _cancel_wall_drag() -> void:
	_wall_dragging = false
	_camera.set_external_gesture(false)


func _cancel_build() -> void:
	_cancel_wall_drag()
	_build_id = &""
	_hud.present_build(&"")
	_coverage.hide()
	_hud.feedback("已退出建造。左键点选/框选，右键下令；选中工厂右键设集结点。")
	_update_cursor()


func _building_action(action: int, entity_id: int) -> void:
	_commands.submit(MechCommand.new(action as MechCommand.Type, {"entity_id": entity_id}))


func _queue_unit(factory_id: int) -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.QUEUE_UNIT, {"factory_id": factory_id}))


func _cancel_production(factory_id: int, ticket: int) -> void:
	_commands.submit(MechCommand.new(MechCommand.Type.CANCEL_PRODUCTION, {"factory_id": factory_id, "ticket": ticket}))


func _toggle_scenario() -> void:
	_cancel_selection_drag()
	_cancel_build()
	var settings: MechFoundationSettings = TRAINING_SETTINGS if _sim.scenario_name() != TRAINING_SETTINGS.scenario_name else SETTINGS
	_commands.submit(MechCommand.new(MechCommand.Type.LOAD_SCENARIO, {"settings": settings}))


func _select_starting_units() -> void:
	var ids: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity.get("is_unit", false) and entity["team"] == 1:
			ids.append(entity["id"])
	_selection.select(ids)
	_refresh_selection()
	if not ids.is_empty():
		_hud.feedback("训练场：已选择 %d 名卫兵。右键移动/攻击红叉训练靶；选工厂可生产卫兵。" % ids.size())


func _cancel_selection_drag() -> void:
	_selection_dragging = false
	_camera.set_external_gesture(false)
	_hud.present_drag(Rect2(), false)


func _screen_position(entity: Dictionary) -> Vector2:
	return _world.get_global_transform_with_canvas() * MechIsoGeometry.project(entity["position"])


func _hit_entity(point: Vector2, enemy: bool = false) -> int:
	var best: float = INF
	var result: int = 0
	for entity: Dictionary in _state["entities"]:
		if (entity.get("team", 1) == 2) != enemy or entity.get("is_building", false):
			continue
		var distance: float = (_screen_position(entity) - Vector2(0, 15) * _camera.zoom.x).distance_to(point)
		if distance <= 24.0 * _camera.zoom.x and distance < best:
			best = distance
			result = entity["id"]
	return result


func _finish_selection() -> void:
	var ids: Array[int] = []
	if _selection_start.distance_to(_selection_end) < 6.0:
		var hit: int = _hit_entity(_selection_end)
		if hit > 0:
			ids.append(hit)
		else:
			var building_id: int = _world.pick_building(_selection_end)
			if building_id > 0:
				ids.append(building_id)
			else:
				var building: Dictionary = _sim.building_at(_mouse_cell())
				if not building.is_empty():
					ids.append(building["entity_id"])
	else:
		var rect := Rect2(_selection_start, _selection_end - _selection_start).abs()
		for entity: Dictionary in _state["entities"]:
			if entity.get("team", 1) == 1 and rect.has_point(_screen_position(entity)):
				ids.append(entity["id"])
	_selection.select(ids, _selection_additive, _selection_toggle)
	_selected = _mouse_cell() if _sim.inspect_cell(_mouse_cell())["inside"] else Vector2i(-1, -1)
	_refresh_selection()
	_update_cursor()
	_hud.feedback("已选择 %d 个己方实体；右键下令，A＋左键攻击移动。" % _selection.ids.size())


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
	if not ids.is_empty():
		var target_id: int = _hit_entity(get_viewport().get_mouse_position(), true)
		_commands.submit(MechCommand.new(MechCommand.Type.ISSUE_UNIT_ORDER, {
			"ids": ids, "kind": &"attack" if target_id > 0 else (&"attack_move" if attack_move else &"move"),
			"goal": Vector2(cell) + Vector2(0.5, 0.5), "target_id": target_id}))
	else:
		for entity: Dictionary in _state["entities"]:
			if not entity["id"] in _selection.ids:
				continue
			if entity.get("produced_unit", &"") != &"":
				_commands.submit(MechCommand.new(MechCommand.Type.SET_RALLY, {"factory_id": entity["id"], "cell": cell}))
				break
			elif entity["kind"] == &"probe":
				_commands.submit(MechCommand.new(MechCommand.Type.MOVE_ENTITY, {"entity_id": entity["id"], "target": Vector2(cell) + Vector2(0.5, 0.5)}))
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
			_hud.feedback("已开始拆除；建筑停机，工程完成后退款并释放占用。")
		MechCommand.Type.CANCEL_DEMOLISH:
			_hud.feedback("拆除已取消，血量保持，建筑恢复工作。")
		MechCommand.Type.TOGGLE_REPAIR:
			_hud.feedback("维修开关已更新；按模拟时间扣费回血，资金不足时等待。")
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
		MechCommand.Type.SET_RALLY:
			_hud.feedback("集结点已更新，新出厂部队将自动前往。")
		MechCommand.Type.ISSUE_UNIT_ORDER:
			var label: String = {&"move": "移动", &"attack_move": "攻击移动", &"attack": "攻击"}.get(result["kind"], "指令")
			_hud.feedback("%d 名卫兵已收到%s指令。" % [result["count"], label])
	_update_cursor()


func _refresh() -> void:
	# Commands, damage and RVO may all notify during a frame. Pack once from
	# _process; input and rendering keep reading the same published state.
	_state_dirty = true


func _publish_state() -> void:
	if not _state_dirty:
		return
	_state_dirty = false
	_state = _sim.snapshot()
	var state: Dictionary = _state
	var generation_changed: bool = _last_generation != state["generation"]
	var ended: bool = state["session"]["ended"]
	_present_threat(state)
	if _last_generation != state["generation"]:
		_selection.reset()
		_attack_move_mode = false
		_last_group = -1
	_selection.reconcile(state["entities"])
	_world.present(state)
	_hud.present_state(state)
	if _last_generation != state["generation"] or _last_map_revision != state["map_revision"]:
		var map_state: Dictionary = _sim.map_snapshot()
		_terrain.present_map(map_state)
		_coverage.present_map(map_state)
		_hud.present_map(map_state)
		_dimensions = map_state["dimensions"]
		if _last_generation != state["generation"]:
			_selected = Vector2i(-1, -1)
			var focus: Vector2 = MechIsoGeometry.project(Vector2(map_state["mainbrain_origin"]) + Vector2(map_state["mainbrain_footprint"]) * 0.5)
			_camera.configure(MechIsoGeometry.map_bounds(_dimensions), focus)
		_last_generation = state["generation"]
		_last_map_revision = state["map_revision"]
	if generation_changed:
		_select_starting_units()
	else:
		_refresh_selection()
	if ended and not _last_session_ended:
		_cancel_selection_drag()
		_cancel_build()
		_attack_move_mode = false
		_hud.feedback("主脑已被摧毁，本局结束。可查看战场或重新开始。", true)
	_last_session_ended = ended


func _present_threat(state: Dictionary) -> void:
	# Interim announcement: a text line on the transition into "announced".
	# The proper wave-slot HUD arrives with the M5-04 batch.
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
			"repair": _sim.building_action_error(MechCommand.Type.TOGGLE_REPAIR, entity_id)}
	_hud.present_selection(building, errors)
	if building.is_empty() and not units.is_empty():
		_hud.present_units(units)
	_world.present_selection(_selection.ids)


func _mouse_cell() -> Vector2i:
	return MechIsoGeometry.cell_at(_world.get_local_mouse_position())


func _clamped_line_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, -1, _dimensions.x), clampi(cell.y, -1, _dimensions.y))


func _wall_cells() -> Array[Vector2i]:
	return Geometry2D.bresenham_line(_wall_start, _wall_end)


func _update_cursor() -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var cursor_visible: bool = get_window().has_focus() and get_viewport_rect().has_point(mouse) and not _hud.blocks_point(mouse)
	var cell: Vector2i = _mouse_cell()
	var info: Dictionary = {}
	if cursor_visible:
		info = _sim.inspect_cell(cell)
	elif _selected.x >= 0:
		info = _sim.inspect_cell(_selected)
	var preview: Dictionary = {}
	if _wall_dragging:
		preview = _sim.preview_wall_line(_wall_cells())
	elif cursor_visible and _build_id != &"":
		preview = _sim.preview_build(_build_id, cell)
	_world.present_cursor(cell, _selected, preview, cursor_visible or _wall_dragging)
	_hud.present_cell(info, preview)
