class_name MechMapHud
extends CanvasLayer
## UI read models and intent signals; all authorization stays in sim.

signal pause_requested
signal restart_requested
signal focus_requested
signal fit_requested
signal build_requested(id: StringName)
signal build_cancelled
signal building_action_requested(action: int, entity_id: int)
signal production_requested(factory_id: int)
signal production_cancelled(factory_id: int, ticket: int)
signal scenario_requested
signal settings_requested
signal minimap_focus_requested(world_position: Vector2)

const INK := Color("d5e6eb")
const MUTED := Color("819ca9")
const ACCENT := Color("72e9d0")
const WIN := Color("8fe08f")
const BUILD_IDS: Array[StringName] = [&"compute_node", &"armored_wall", &"sentry_tower", &"mining_station", &"assembly_plant"]
const SHORTCUTS: Array[String] = ["Q", "W", "E", "", ""]

var _clock_label: Label
var _map_label: Label
var _state_label: Label
var _coins_label: Label
var _ore_label: Label
var _capacity_label: Label
var _power_label: Label
var _cell_label: Label
var _space_label: Label
var _feedback_label: Label
var _zoom_label: Label
var _pause_button: Button
var _build_buttons: Dictionary[StringName, Button] = {}
var _selection_title: Label
var _status_label: Label
var _build_label: Label
var _build_bar: ProgressBar
var _hp_label: Label
var _hp_bar: ProgressBar
var _details: Label
var _primary: Button
var _demolish: Button
var _dialog: ConfirmationDialog
var _selection: Dictionary = {}
var _primary_action: int = MechCommand.Type.CANCEL_CONSTRUCTION
var _pending_demolish: int = 0
var _generation: int = -1
var _panels: Array[Control] = []
var _building_widgets: Array[Control] = []
var _unit_catalog: Dictionary = {}
var _production_widgets: Array[Control] = []
var _session_ended: bool = false
var _minimap_panel: Panel
var _minimap_view: MechMinimapView
var _expand_button: Button
var _minimap_fullscreen: bool = false
var _minimap_layout: Dictionary = {}


func _ready() -> void:
	_clock_label = $Root/Header/Clock
	_map_label = $Root/Header/MapName
	_state_label = $Root/Header/State
	_coins_label = $Root/Header/Coins
	_ore_label = $Root/Header/Ore
	_capacity_label = $Root/Header/Capacity
	_power_label = $Root/Header/Power
	_cell_label = $Root/Inspector/CellInfo
	_space_label = $Root/Toolbar/PlacementInfo
	_feedback_label = $Root/Feedback
	_zoom_label = $Root/Toolbar/Zoom
	_pause_button = $Root/Header/Pause
	_selection_title = $Root/Inspector/Title
	_status_label = $Root/Inspector/Status
	_build_label = $Root/Inspector/BuildLabel
	_build_bar = $Root/Inspector/BuildProgress
	_hp_label = $Root/Inspector/HpLabel
	_hp_bar = $Root/Inspector/HpProgress
	_details = $Root/Inspector/Details
	_primary = $Root/Inspector/Primary
	_demolish = $Root/Inspector/Demolish
	_dialog = $DemolitionDialog
	_panels = [$Root/Header, $Root/Inspector, $Root/Toolbar, $Root/SessionResult, $Root/Minimap]
	_minimap_panel = $Root/Minimap
	_minimap_view = $Root/Minimap/View
	_expand_button = $Root/Minimap/Expand
	_repair_all_button = $Root/Toolbar/RepairAll
	_minimap_view.focus_requested.connect(minimap_focus_requested.emit)
	_expand_button.pressed.connect(toggle_minimap_fullscreen)
	_repair_all_button.pressed.connect(func(): repair_all_requested.emit())
	_minimap_layout = {"anchor_left": _minimap_panel.anchor_left, "anchor_top": _minimap_panel.anchor_top,
		"anchor_right": _minimap_panel.anchor_right, "anchor_bottom": _minimap_panel.anchor_bottom,
		"offset_left": _minimap_panel.offset_left, "offset_top": _minimap_panel.offset_top,
		"offset_right": _minimap_panel.offset_right, "offset_bottom": _minimap_panel.offset_bottom}
	_build_buttons = {&"compute_node": $Root/Toolbar/ComputeNode, &"armored_wall": $Root/Toolbar/ArmoredWall,
		&"sentry_tower": $Root/Toolbar/SentryTower, &"mining_station": $Root/Toolbar/MiningStation,
		&"assembly_plant": $Root/Toolbar/AssemblyPlant}
	for id: StringName in _build_buttons:
		_build_buttons[id].pressed.connect(build_requested.emit.bind(id))
	_pause_button.pressed.connect(pause_requested.emit)
	$Root/Toolbar/CancelBuild.pressed.connect(build_cancelled.emit)
	$Root/Toolbar/FitMap.pressed.connect(fit_requested.emit)
	$Root/Toolbar/FocusCore.pressed.connect(focus_requested.emit)
	$Root/Toolbar/Restart.pressed.connect(restart_requested.emit)
	$Root/Header/Scenario.pressed.connect(scenario_requested.emit)
	$Root/Header/Settings.pressed.connect(settings_requested.emit)
	$Root/SessionResult/Restart.pressed.connect(restart_requested.emit)
	$Root/SessionResult/Scenario.pressed.connect(scenario_requested.emit)
	$Root/Inspector/Produce.pressed.connect(_produce_pressed)
	$Root/Inspector/CancelProduction.pressed.connect(_cancel_production_pressed)
	_production_widgets = [$Root/Inspector/Produce, $Root/Inspector/Queue, $Root/Inspector/CancelProduction]
	_primary.pressed.connect(_primary_pressed)
	_demolish.pressed.connect(request_demolition)
	_dialog.confirmed.connect(_confirm_demolition)
	_building_widgets = [_status_label, _build_label, _build_bar, _hp_label, _hp_bar, _details, _primary, _demolish]
	present_selection({}, {})


func blocks_point(point: Vector2) -> bool:
	if _dialog.visible:
		return true
	for panel: Control in _panels:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point):
			return true
	return false


func dismiss_dialogs() -> void:
	_pending_demolish = 0
	_dialog.hide()


func present_map(map_state: Dictionary) -> void:
	var dimensions: Vector2i = map_state["dimensions"]
	var bounds: Rect2 = MechIsoGeometry.map_bounds(dimensions, map_state["outline"])
	_map_label.text = "%s   /   正方形地图" % map_state["name"] if is_equal_approx(bounds.size.x, bounds.size.y) else "%s   /   %d × %d" % [map_state["name"], dimensions.x, dimensions.y]
	_minimap_view.present_map(map_state)


func present_state(state: Dictionary) -> void:
	_unit_catalog = state["unit_catalog"]
	_session_ended = state["session"]["ended"]
	$Root/SessionResult.visible = _session_ended
	$Root/Header/Subtitle.text = "白模开发  /  %s" % state["scenario"]
	$Root/Header/Scenario.text = "单位训练场" if state["scenario"] == "标准开局" else "返回标准开局"
	if _generation != state["generation"]:
		_pending_demolish = 0
		_dialog.hide()
		_generation = state["generation"]
	var clock: Dictionary = state["clock"]
	var seconds: float = clock["elapsed_seconds"]
	_clock_label.text = "%02d:%05.2f" % [int(seconds / 60.0), fmod(seconds, 60.0)]
	_state_label.text = "已暂停 · 可规划" if clock["paused"] else "运行中"
	_state_label.modulate = Color("f0bc79") if clock["paused"] else ACCENT
	_pause_button.text = "继续 [空格]" if clock["paused"] else "暂停 [空格]"
	_pause_button.disabled = _session_ended
	if _session_ended:
		_pending_demolish = 0
		_dialog.hide()
		var victory: bool = state["session"]["outcome"] == &"victory"
		_state_label.text = "防守胜利 · 本局结束" if victory else "防守失败 · 本局结束"
		_state_label.modulate = WIN if victory else Color("f27c78")
		_pause_button.text = "本局已结束"
		$Root/SessionResult/Title.text = "防守胜利" if victory else "防守失败"
		$Root/SessionResult/Title.add_theme_color_override("font_color", WIN if victory else Color("f27c78"))
		var summary: String = "威胁已清除，幕一防线守住了" if victory else "%s" % state["session"]["reason"]
		$Root/SessionResult/Details.text = "%s\n坚守了 %02d:%02d · 战场已停止\n可继续查看战场，或开始新的一局。" % [summary, int(seconds / 60.0), int(fmod(seconds, 60.0))]
		$Root/SessionResult/Scenario.text = "进入训练场" if state["scenario"] == "标准开局" else "返回标准开局"
	var economy: Dictionary = state["economy"]
	_coins_label.text = "算力币  %d   +%d/分钟" % [economy["coins"], economy["income_rate"]]
	_ore_label.text = "矿石  %d   +%d/分钟" % [economy["ore"], economy["production_per_minute"].y]
	_capacity_label.text = "算力容量  %d / %d%s" % [economy["capacity_used"], economy["capacity_supply"], "  超载" if economy["overloaded"] else ""]
	_capacity_label.modulate = Color("f27c78") if economy["overloaded"] else INK
	_capacity_label.tooltip_text = "单位占容 %d，队列预留 %d；出厂仅转移预留，不重复占用" % [economy["unit_capacity"], economy["queued_capacity"]]
	_power_label.text = "电力余量  %d / %d%s" % [economy["power_free"], economy["power_supply"], "  赤字" if economy["power_deficit"] else ""]
	_power_label.modulate = Color("f27c78") if economy["power_deficit"] else INK
	for entry: Dictionary in state["catalog"]:
		var id: StringName = entry["building_id"]
		if not _build_buttons.has(id):
			continue
		var button: Button = _build_buttons[id]
		var index: int = BUILD_IDS.find(id)
		button.text = "%s %s\n%s" % [SHORTCUTS[index], entry["name"], MechResources.text(entry["cost"])]
		button.disabled = _session_ended or not entry["unavailable_reason"].is_empty()
		button.tooltip_text = "本局已结束" if _session_ended else (entry["unavailable_reason"] if button.disabled else "占地 %d×%d；施工 %.1f 秒；预留电力 %d、容量 %d" % [entry["footprint"].x, entry["footprint"].y, entry["construction_seconds"], entry["power_cost"], entry["capacity_cost"]])
	var repair_all: Dictionary = state.get("repair_all", {})
	_repair_all_button.disabled = _session_ended or not repair_all.get("ok", false)
	_repair_all_button.tooltip_text = repair_all.get("reason", "") if _repair_all_button.disabled \
		else "对全部受损完工建筑开启维修（每座 2 HP/秒 · 1 币/秒）；被攻击后进入交战状态，周边 6 格内有敌军期间自动暂停，脱离后恢复"
	_minimap_view.present_state(state)


func present_camera(rect: Rect2) -> void:
	_minimap_view.present_camera(rect)


func is_minimap_fullscreen() -> bool:
	return _minimap_fullscreen


func toggle_minimap_fullscreen() -> void:
	set_minimap_fullscreen(not _minimap_fullscreen)


func set_minimap_fullscreen(active: bool) -> void:
	if _minimap_fullscreen == active:
		return
	_minimap_fullscreen = active
	if active:
		var base: Vector2 = $Root.size
		var side: float = minf(floor(base.x * 0.6), base.y - 330.0)
		_minimap_panel.anchor_left = 0.5
		_minimap_panel.anchor_right = 0.5
		_minimap_panel.anchor_top = 0.0
		_minimap_panel.anchor_bottom = 1.0
		_minimap_panel.offset_left = -side * 0.5
		_minimap_panel.offset_right = side * 0.5
		_minimap_panel.offset_top = 150.0
		_minimap_panel.offset_bottom = -180.0
		feedback("小地图全屏：左键点击/拖动跳转镜头；M 或 Esc 返回。")
	else:
		_minimap_panel.anchor_left = _minimap_layout["anchor_left"]
		_minimap_panel.anchor_top = _minimap_layout["anchor_top"]
		_minimap_panel.anchor_right = _minimap_layout["anchor_right"]
		_minimap_panel.anchor_bottom = _minimap_layout["anchor_bottom"]
		_minimap_panel.offset_left = _minimap_layout["offset_left"]
		_minimap_panel.offset_top = _minimap_layout["offset_top"]
		_minimap_panel.offset_right = _minimap_layout["offset_right"]
		_minimap_panel.offset_bottom = _minimap_layout["offset_bottom"]
		feedback("小地图已还原。")
	_expand_button.text = "还原 [M]" if active else "全屏 [M]"


func present_zoom(factor: float) -> void:
	_zoom_label.text = "%d%%" % roundi(factor * 100.0)


func present_build(id: StringName) -> void:
	for value: StringName in _build_buttons:
		_build_buttons[value].set_pressed_no_signal(value == id)


func present_cell(info: Dictionary, preview: Dictionary) -> void:
	if info.is_empty():
		_cell_label.text = "鼠标移至地图查看格子"
	else:
		var cell: Vector2i = info["cell"]
		_cell_label.text = "格子  (%d, %d)  ·  %s" % [cell.x, cell.y, info["terrain_name"]]
		if info["inside"] and info.get("vision", MechVisionSystem.State.VISIBLE) == MechVisionSystem.State.UNEXPLORED:
			_cell_label.text += "\n派遣单位探索；未知区域不显示地形与矿点。"
		elif info["inside"]:
			_cell_label.text += " · " + ("实时视野" if info.get("vision", MechVisionSystem.State.VISIBLE) == MechVisionSystem.State.VISIBLE else "已探索 · 无实时视野")
			_cell_label.text += "\n%s  ·  %s" % ["供电覆盖内" if info["covered"] else "覆盖外", "空地" if info["occupied_by"] == 0 else "建筑占用"]
			_cell_label.text += "\n%s" % ("可通行 · 速度 %d%%" % roundi(100.0 / float(info["movement_weight"])) if info["walkable"] else "不可通行")
			var mineral: Dictionary = info.get("mineral", {})
			if not mineral.is_empty():
				_cell_label.text += "\n矿石储量 %d / %d%s" % [mineral["remaining"], mineral["initial_amount"], " · 已预留" if mineral["assigned_to"] != 0 else ""]
	if preview.is_empty():
		_space_label.text = "选择建筑以显示供电覆盖；点击建筑查看施工、血量与维护操作。"
		_space_label.modulate = MUTED
	elif preview.get("line", false):
		_space_label.text = "墙线预览  %d 段可建 · 跳过 %d 格 · 总价 %s；松开下单" % [preview["planned_count"], preview["skipped_count"], MechResources.text(preview["cost"])]
		_space_label.modulate = ACCENT if preview["ok"] else Color("f27c78")
	else:
		var footprint: Vector2i = preview["footprint"]
		_space_label.text = "%d×%d  ·  %s  ·  %s" % [footprint.x, footprint.y, MechResources.text(preview.get("cost", Vector4i.ZERO)), "可下单；左键轻点确认" if preview["ok"] else preview["reason"]]
		_space_label.modulate = ACCENT if preview["ok"] else Color("f27c78")


func present_selection(building: Dictionary, errors: Dictionary) -> void:
	_selection = building.duplicate(true)
	for widget: Control in _production_widgets:
		widget.hide()
	for widget: Control in _building_widgets:
		widget.visible = not building.is_empty()
	if building.is_empty():
		_selection_title.text = "空间信息"
		return
	var footprint: Vector2i = building["footprint"]
	_selection_title.text = "%s · %d×%d" % [building["name"], footprint.x, footprint.y]
	_status_label.text = building["status"]
	_status_label.modulate = Color("f27c78") if building["phase"] == MechBuildingState.Phase.RUINED else (ACCENT if building["phase"] == MechBuildingState.Phase.OPERATING else Color("f0bc79"))
	_build_bar.value = 100.0 * float(building["demolition_progress"] if building["phase"] == MechBuildingState.Phase.DEMOLISHING else building["build_progress"])
	_build_label.text = "%s  %d%%" % ["清除基座进度" if building["phase"] == MechBuildingState.Phase.DEMOLISHING and building["hp"] <= 0 else ("拆除进度" if building["phase"] == MechBuildingState.Phase.DEMOLISHING else "施工进度"), roundi(_build_bar.value)]
	_hp_bar.value = 100.0 * float(building["hp"]) / float(building["max_hp"])
	_hp_label.text = "血量  %d / %d" % [building["hp"], building["max_hp"]]
	_details.text = "预留  电力 %d · 容量 %d\n供给  电力 +%d · 容量 +%d\n运行收入  +%d 币/分钟" % [building["power_cost"], building["capacity_cost"], building["power_provided"], building["capacity_provided"], building["income_per_minute"]]
	var mineral: Dictionary = building.get("mineral", {})
	if building["phase"] == MechBuildingState.Phase.RUINED:
		_build_label.hide()
		_build_bar.hide()
		_details.text = "已摧毁 · 保留占位与矿点绑定，不阻挡通行\n重建支付全额 50%%，施工 %.1f 秒，血量随进度爬升\n清除基座不退款，完成时释放占地与矿点绑定" % building["construction_seconds"]
		if not mineral.is_empty():
			_details.text += "\n矿点绑定保留 · 剩余 %d / %d" % [mineral["remaining"], mineral["initial_amount"]]
	elif not mineral.is_empty():
		_details.text = "预留  电力 %d · 容量 %d\n采集产率  %d 矿石/分钟\n剩余储量  %d / %d\n%s" % [building["power_cost"], building["capacity_cost"], building["extraction_per_minute"], mineral["remaining"], mineral["initial_amount"], "矿点耗竭，可拆除" if mineral["remaining"] == 0 else "完工且供电后采集"]
	if building["phase"] == MechBuildingState.Phase.CONSTRUCTING:
		_primary_action = MechCommand.Type.CANCEL_CONSTRUCTION
		_primary.text = "取消施工 · 全退 %s" % MechResources.text(building["paid_cost"])
		_primary.tooltip_text = errors.get("cancel", "")
	elif building["phase"] == MechBuildingState.Phase.RUINED:
		_primary_action = MechCommand.Type.REBUILD
		_primary.text = "重建 · %s" % MechResources.text(building["rebuild_cost"])
		_primary.tooltip_text = errors.get("rebuild", "")
	elif building["phase"] == MechBuildingState.Phase.DEMOLISHING:
		_primary_action = MechCommand.Type.CANCEL_DEMOLISH
		_primary.text = "取消清除 · 保留基座" if building["hp"] <= 0 else "取消拆除 · 恢复运行"
		_primary.tooltip_text = errors.get("cancel_demolish", "")
	else:
		_primary_action = MechCommand.Type.TOGGLE_REPAIR
		_primary.text = "停止维修" if building["repairing"] else "维修 · 2 HP/秒，1 币/秒"
		_primary.tooltip_text = errors.get("repair", "")
	_primary.disabled = not _primary.tooltip_text.is_empty()
	_demolish.text = "清除基座 [X] · 无退款" if building["phase"] == MechBuildingState.Phase.RUINED else "拆除 [X] · 返还 %s" % MechResources.text(building["refund"])
	_demolish.tooltip_text = errors.get("demolish", "")
	_demolish.disabled = not _demolish.tooltip_text.is_empty()
	var production: Dictionary = building.get("production", {})
	if not production.is_empty():
		for widget: Control in _production_widgets:
			widget.show()
		var queue: Array = production["queue"]
		$Root/Inspector/Produce.text = "生产%s · %s" % [_unit_catalog["name"], MechResources.text(_unit_catalog["cost"])]
		$Root/Inspector/Produce.disabled = not building["production_error"].is_empty()
		$Root/Inspector/Produce.tooltip_text = building["production_error"]
		$Root/Inspector/CancelProduction.disabled = _session_ended or queue.is_empty()
		$Root/Inspector/Queue.text = "队列 %d / %d · %d%%\n%s" % [queue.size(), building["queue_limit"], roundi(production["progress"] * 100), "出口受阻，订单保留" if production["blocked"] else "选厂后右键设置集结点"]
		if building["phase"] == MechBuildingState.Phase.OPERATING:
			_build_label.text = "生产进度  %d%%" % roundi(production["progress"] * 100)
			_build_bar.value = production["progress"] * 100
			if production["blocked"]:
				_status_label.text = "出口受阻 · 等待空位"
		var rally: Vector2i = production["rally"]
		_details.text = "预留 电力 %d · 容量 %d\n集结点 (%d, %d)\n每名卫兵占容 %d，生产 %.0f 秒\n取消队首全额退资源并释放容量" % [building["power_cost"], building["capacity_cost"], rally.x, rally.y, _unit_catalog["capacity_cost"], _unit_catalog["production_seconds"]]


func present_units(units: Array[Dictionary]) -> void:
	var hp: int = 0
	var max_hp: int = 0
	var capacity: int = 0
	var orders: Dictionary = {}
	for unit: Dictionary in units:
		hp += unit["hp"]
		max_hp += unit["max_hp"]
		capacity += unit["capacity_cost"]
		orders[unit["order"]] = true
	_selection_title.text = "卫兵 × %d" % units.size()
	_status_label.show()
	_status_label.text = {&"idle": "待命 / 射程内开火 · 不追击", &"move": "移动中", &"attack_move": "攻击移动中", &"attack": "攻击指定目标"}.get(orders.keys()[0], "待命") if orders.size() == 1 else "多种指令执行中"
	_status_label.modulate = ACCENT
	_hp_label.show()
	_hp_label.text = "总血量 %d / %d · 占容 %d" % [hp, max_hp, capacity]
	_hp_bar.show()
	_hp_bar.value = 100.0 * hp / maxi(1, max_hp)
	_details.show()
	_details.text = "右键：移动 / 攻击目标\n移动抵达后：射程内开火，不追击\nA＋左键：沿途索敌追击后继续前进\nCtrl＋数字：编队，数字：召回\nShift 追加，Ctrl 点击切换选择"


func present_drag(rect: Rect2, active: bool) -> void:
	$Root/SelectionBox.visible = active
	$Root/SelectionBox.position = rect.position
	$Root/SelectionBox.size = rect.size


func _produce_pressed() -> void:
	if not _selection.is_empty():
		production_requested.emit(_selection["entity_id"])


func _cancel_production_pressed() -> void:
	if _selection.is_empty():
		return
	var queue: Array = _selection.get("production", {}).get("queue", [])
	if not queue.is_empty():
		production_cancelled.emit(_selection["entity_id"], queue[0]["ticket"])


func feedback(message: String, failed: bool = false) -> void:
	_feedback_label.text = message
	_feedback_label.modulate = Color("f0bc79") if failed else ACCENT


func request_demolition() -> void:
	if _selection.is_empty() or _demolish.disabled:
		feedback("请先选择可拆除的完工建筑或基座。", true)
		return
	_pending_demolish = _selection["entity_id"]
	if _selection.get("phase", MechBuildingState.Phase.OPERATING) == MechBuildingState.Phase.RUINED:
		_dialog.dialog_text = "清除「%s」基座需要 %.1f 游戏秒，完成时不退款。\n占地与矿点绑定在清除完成时释放；可取消清除保留基座。" % [_selection["name"], _selection["demolition_seconds"]]
	else:
		_dialog.dialog_text = "拆除「%s」需要 %.1f 游戏秒，完成后返还 %s。\n期间建筑停机，占用与矿点绑定在拆除完成时释放。" % [_selection["name"], _selection["demolition_seconds"], MechResources.text(_selection["refund"])]
	_dialog.popup_centered(Vector2i(540, 210))


func _confirm_demolition() -> void:
	var id: int = _pending_demolish
	_pending_demolish = 0
	if id > 0:
		building_action_requested.emit(MechCommand.Type.DEMOLISH, id)


func _primary_pressed() -> void:
	if not _selection.is_empty():
		building_action_requested.emit(_primary_action, _selection["entity_id"])
