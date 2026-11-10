class_name MechSelectionController
extends RefCounted
## 选择、框选、双击、编队与部队指令；复用只读快照和既有命令入口。

signal cursor_changed

const DOUBLE_CLICK_MS: int = 400
const DOUBLE_CLICK_SLOP: float = 8.0
const SAME_KIND_CHAIN_RADIUS: float = 2.0

var selected_cell := Vector2i(-1, -1)
var dragging: bool = false
var attack_move_mode: bool = false
var selected_ids: Array[int]:
	get:
		return _selection.ids

var _selection := MechSelectionState.new()
var _selection_start := Vector2.ZERO
var _selection_end := Vector2.ZERO
var _selection_bounds := Rect2()
var _selection_additive: bool = false
var _selection_toggle: bool = false
var _last_group: int = -1
var _last_group_time: int = 0
var _last_click_ms: int = 0
var _last_click_position := Vector2.ZERO
var _state: Dictionary = {}
var _sim: MechSimCore
var _commands: MechCommandQueue
var _hud: MechMapHud
# 战场拾取统一使用三维模型射线。
var _world: MechFoundationView3D
var _camera: MechMapCamera3D
var _viewport: Viewport


func configure(sim: MechSimCore, commands: MechCommandQueue, hud: MechMapHud, world: MechFoundationView3D, camera: MechMapCamera3D, viewport: Viewport) -> void:
	_sim = sim
	_commands = commands
	_hud = hud
	_world = world
	_camera = camera
	_viewport = viewport


func update_state(state: Dictionary, generation_changed: bool) -> void:
	_state = state
	if generation_changed:
		_selection.reset()
		attack_move_mode = false
		selected_cell = Vector2i(-1, -1)
		_last_group = -1
		_last_group_time = 0
		_last_click_ms = 0
		_last_click_position = Vector2.ZERO
	_selection.reconcile(state["entities"], state.get("garrisoned_unit_ids", []))


func clear_selection() -> void:
	_selection.ids.clear()
	selected_cell = Vector2i(-1, -1)
	present_selection()
	cursor_changed.emit()


func select_building(entity_id: int, origin: Vector2i) -> void:
	selected_cell = origin
	_selection.select([entity_id])
	present_selection()


func reset_click() -> void:
	_last_click_ms = 0


func left_click(event: InputEventMouseButton) -> bool:
	if attack_move_mode:
		issue_unit_order(true)
	elif _is_double_click(event.position):
		_select_same_kind(event.position)
	else:
		_selection_bounds = _hud.selection_bounds(event.position, event.position)
		if not _selection_bounds.has_area():
			return false
		dragging = true
		_selection_start = event.position
		_selection_end = event.position
		_selection_additive = event.shift_pressed
		_selection_toggle = event.ctrl_pressed
		_camera.set_external_gesture(true)
	return true


func right_click() -> void:
	reset_click()
	if attack_move_mode:
		attack_move_mode = false
		_hud.feedback("已取消攻击移动模式。")
	else:
		issue_unit_order(false)


func handle_drag_event(event: InputEvent) -> bool:
	if not dragging:
		return false
	if event is InputEventMouseMotion:
		_selection_end = _clamped_selection_point(event.position)
		_hud.present_drag(Rect2(_selection_start, _selection_end - _selection_start).abs(), _selection_start.distance_to(_selection_end) >= 6.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_selection_end = _clamped_selection_point(event.position)
		# 战场开始的框选允许在HUD上松开，按裁剪后的战场矩形提交。
		if _selection_bounds.has_area() and _viewport.get_visible_rect().has_point(event.position):
			_finish_selection()
		cancel_drag()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_drag()
	else:
		return false
	return true


func select_starting_units() -> void:
	var ids: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity.get("is_unit", false) and entity["team"] == 1:
			ids.append(entity["id"])
	var has_units: bool = not ids.is_empty()
	if ids.is_empty():
		ids.append(_state["mainbrain_id"])
	_selection.select(ids)
	present_selection()
	if has_units:
		_hud.feedback("已选择 %d 个单位。右键移动或攻击；选工厂可生产部队。" % ids.size())


func cancel_drag() -> void:
	dragging = false
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


## 只认可射线实际命中的最前方模型，不回退到地面格建筑。
func _picked_friendly_entity(point: Vector2) -> Dictionary:
	var id: int = _world.pick_entity(point)
	for entity: Dictionary in _state["entities"]:
		if entity["id"] == id and entity.get("team", 1) == 1:
			return entity
	return {}


func _finish_selection() -> void:
	var ids: Array[int] = []
	var release_cell: Vector2i = _map_cell(_camera.screen_to_map(_selection_end))
	if _selection_start.distance_to(_selection_end) < 6.0:
		var picked: Dictionary = _picked_friendly_entity(_selection_end)
		if not picked.is_empty():
			ids.append(picked["id"])
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
	selected_cell = release_cell if _sim.inspect_cell(release_cell)["inside"] else Vector2i(-1, -1)
	present_selection()
	cursor_changed.emit()
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
	var target: Dictionary = _picked_friendly_entity(point)
	if target.is_empty():
		return
	if not target.get("is_building", false):
		var hit: int = target["id"]
		var kind: StringName = target.get("kind", &"")
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
		present_selection()
		cursor_changed.emit()
		_hud.feedback("已选择 %d 个同类单位；右键下令。" % units.size())
		return
	var family: StringName = target.get("family_id", &"")
	if family == &"":
		return
	var buildings: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity.get("is_building", false) and entity.get("team", 1) == 1 and entity.get("family_id", &"") == family:
			buildings.append(entity["id"])
	_selection.select(buildings)
	present_selection()
	cursor_changed.emit()
	_hud.feedback("已选择 %d 座同类建筑（升级前后视为同种）。" % buildings.size())


func selected_units() -> Array[int]:
	var ids: Array[int] = []
	for entity: Dictionary in _state["entities"]:
		if entity["id"] in _selection.ids and entity.get("is_unit", false) and entity["team"] == 1:
			ids.append(entity["id"])
	return ids


func issue_unit_order(attack_move: bool) -> void:
	if _sim.session_ended():
		_hud.feedback("本局已结束，请重新开始或切换场景。", true)
		return
	var ids: Array[int] = selected_units()
	var cell: Vector2i = _mouse_cell()
	var goal: Vector2 = _camera.screen_to_map(_viewport.get_mouse_position())
	if not goal.is_finite():
		return
	if not ids.is_empty():
		var target_id: int = _world.pick_unit(_viewport.get_mouse_position(), true)
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
	attack_move_mode = false


func handle_group(number: int, store: bool) -> void:
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
	present_selection()


func present_selection() -> void:
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
	return _map_cell(_camera.screen_to_map(_viewport.get_mouse_position()))


func _map_cell(point: Vector2) -> Vector2i:
	return Vector2i(point.floor()) if point.is_finite() else Vector2i(-1, -1)
