class_name MechMapHud
extends CanvasLayer
## HUD 的只读展示模型与意图信号；全部授权判定留在模拟层。

signal pause_requested
signal restart_requested
signal main_menu_requested
signal focus_requested
signal fit_requested
signal build_requested(id: StringName)
signal build_cancelled
signal building_action_requested(action: int, entity_id: int)
signal production_requested(factory_id: int, unit_id: StringName)
signal production_cancelled(factory_id: int, ticket: int)
signal upgrade_requested(entity_id: int)
signal upgrade_cancelled(entity_id: int)
signal settings_requested
signal minimap_focus_requested(map_position: Vector2)
signal dispatch_region_selected(cells: Array[Vector2i])
signal repair_all_requested

const INK := Color("dedfd0")
const MUTED := Color("94a49a")
const ACCENT := Color("d9bd81")
const WIN := Color("8fe08f")

var _clock_label: Label
var _map_label: Label
var _state_label: Label
var _coins_label: Label
var _ore_label: Label
var _fuel_label: Label
var _alloy_label: Label
var _crystals_label: Label
var _cooling_label: Label
var _capacity_label: Label
var _power_label: Label
var _cell_label: Label
var _space_label: Label
var _feedback_label: Label
var _zoom_label: Label
var _pause_button: Button
var _repair_all_button: Button
var _build_menu: MechBuildMenu
var _selection_title: Label
var _status_label: Label
var _wave_label: Label
var _dispatch_label: Label
var _build_label: Label
var _build_bar: ProgressBar
var _hp_label: Label
var _hp_bar: ProgressBar
var _details: Label
var _primary: Button
var _upgrade_button: Button
var _upgrade_mode_cancel: bool = false
var _demolish: Button
var _dialog: ConfirmationDialog
var _selection: Dictionary = {}
var _primary_action: int = MechCommand.Type.CANCEL_CONSTRUCTION
var _pending_demolish: int = 0
var _generation: int = -1
var _panels: Array[Control] = []
var _building_widgets: Array[Control] = []
var _product_menu_key: String = ""
var _production_widgets: Array[Control] = []
var _session_ended: bool = false
var _minimap_panel: Panel
var _minimap_view: MechMinimapView
var _expand_button: Button
var _minimap_fullscreen: bool = false
var _minimap_layout: Dictionary = {}
var _portrait_key: String = ""


func _ready() -> void:
	_clock_label = $Root/Header/Clock
	_map_label = $Root/WorldInfo/MapName
	_state_label = $Root/Header/State
	_coins_label = $Root/Resources/Coins
	_ore_label = $Root/Resources/Ore
	_fuel_label = $Root/Resources/Fuel
	_alloy_label = $Root/Resources/Alloy
	_crystals_label = $Root/Resources/Crystals
	_cooling_label = $Root/Resources/Cooling
	_capacity_label = $Root/Resources/Capacity
	_power_label = $Root/Resources/Power
	_cell_label = $Root/Inspector/CellInfo
	_space_label = $Root/StatusStrip/PlacementInfo
	_feedback_label = $Root/StatusStrip/Feedback
	_zoom_label = $Root/Toolbar/Zoom
	_pause_button = $Root/Header/Pause
	_wave_label = Label.new()
	$Root/StatusStrip.add_child(_wave_label)
	_wave_label.anchor_right = 1.0
	_wave_label.offset_left = 12
	_wave_label.offset_top = 45
	_wave_label.offset_right = -12
	_wave_label.offset_bottom = 66
	_wave_label.clip_text = true
	_wave_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_wave_label.add_theme_font_override("font", _state_label.get_theme_font("font"))
	_wave_label.add_theme_font_size_override("font_size", 15)
	_wave_label.add_theme_color_override("font_color", Color("f0bc79"))
	_dispatch_label = Label.new()
	$Root/StatusStrip.add_child(_dispatch_label)
	_dispatch_label.anchor_right = 1.0
	_dispatch_label.offset_left = 12
	_dispatch_label.offset_top = 66
	_dispatch_label.offset_right = -12
	_dispatch_label.offset_bottom = 86
	_dispatch_label.clip_text = true
	_dispatch_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_dispatch_label.add_theme_font_override("font", _state_label.get_theme_font("font"))
	_dispatch_label.add_theme_font_size_override("font_size", 13)
	_dispatch_label.add_theme_color_override("font_color", ACCENT)
	_selection_title = $Root/Inspector/Title
	_status_label = $Root/Inspector/Status
	_build_label = $Root/Inspector/BuildLabel
	_build_bar = $Root/Inspector/BuildProgress
	_hp_label = $Root/Inspector/HpLabel
	_hp_bar = $Root/Inspector/HpProgress
	_details = $Root/Inspector/Details
	_primary = $Root/Inspector/Primary
	_upgrade_button = Button.new()
	_upgrade_button.position = Vector2(16, 214)
	_upgrade_button.size = Vector2(388, 32)
	_upgrade_button.add_theme_font_size_override("font_size", 14)
	_upgrade_button.pressed.connect(_upgrade_pressed)
	$Root/Inspector.add_child(_upgrade_button)
	_demolish = $Root/Inspector/Demolish
	_dialog = $DemolitionDialog
	_panels = [$Root/Header, $Root/Inspector, $Root/Toolbar, $Root/Resources, $Root/System, $Root/WorldInfo, $Root/StatusStrip, $Root/SessionResult, $Root/Minimap]
	_minimap_panel = $Root/Minimap
	_minimap_view = $Root/Minimap/View
	_expand_button = $Root/Minimap/Expand
	_repair_all_button = $Root/Toolbar/RepairAll
	_minimap_view.focus_requested.connect(minimap_focus_requested.emit)
	_minimap_view.region_selected.connect(func(cells: Array[Vector2i]) -> void:
		dispatch_region_selected.emit(cells)
		feedback("已框选 %d 格授权区域。" % cells.size()))
	_expand_button.pressed.connect(toggle_minimap_fullscreen)
	_repair_all_button.pressed.connect(func(): repair_all_requested.emit())
	_minimap_layout = {"anchor_left": _minimap_panel.anchor_left, "anchor_top": _minimap_panel.anchor_top,
		"anchor_right": _minimap_panel.anchor_right, "anchor_bottom": _minimap_panel.anchor_bottom,
		"offset_left": _minimap_panel.offset_left, "offset_top": _minimap_panel.offset_top,
		"offset_right": _minimap_panel.offset_right, "offset_bottom": _minimap_panel.offset_bottom}
	_build_menu = $Root/Toolbar
	_build_menu.build_requested.connect(build_requested.emit)
	_build_menu.cancel_requested.connect(build_cancelled.emit)
	_build_menu.focus_requested.connect(focus_requested.emit)
	_pause_button.pressed.connect(pause_requested.emit)
	$Root/Toolbar/FitMap.pressed.connect(fit_requested.emit)
	$Root/Toolbar/FocusCore.pressed.connect(focus_requested.emit)
	$Root/System/Restart.pressed.connect(restart_requested.emit)
	$Root/System/Settings.pressed.connect(settings_requested.emit)
	$Root/System/MainMenu.pressed.connect(main_menu_requested.emit)
	$Root/SessionResult/Restart.pressed.connect(restart_requested.emit)
	$Root/SessionResult/MainMenu.pressed.connect(main_menu_requested.emit)
	$Root/Inspector/Produce.pressed.connect(_produce_pressed)
	$Root/Inspector/Produce.get_popup().id_pressed.connect(_produce_choice)
	$Root/Inspector/CancelProduction.pressed.connect(_cancel_production_pressed)
	_production_widgets = [$Root/Inspector/Produce, $Root/Inspector/Queue, $Root/Inspector/CancelProduction]
	_primary.pressed.connect(_primary_pressed)
	_demolish.pressed.connect(request_demolition)
	_dialog.confirmed.connect(_confirm_demolition)
	_building_widgets = [_status_label, _build_label, _build_bar, _hp_label, _hp_bar, _details, _primary, _upgrade_button, _demolish]
	$Root/Inspector/Portrait/Viewport.world_2d = World2D.new()
	$Root.resized.connect(_layout_fullscreen_minimap)
	_status_label.clip_text = true
	for label: Label in [_status_label, _space_label, _feedback_label, _capacity_label]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	for child: Node in $Root.find_children("*", "Button", true, false):
		var button: Button = child as Button
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	present_selection({}, {})


func blocks_point(point: Vector2) -> bool:
	if _dialog.visible:
		return true
	for panel: Control in _panels:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point):
			return true
	return false


## 以实际可见HUD面板为边界，取包含起点的战场矩形；不使用固定分辨率常量。
func selection_bounds(start: Vector2, end: Vector2) -> Rect2:
	if blocks_point(start):
		return Rect2()
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var left: float = viewport.position.x
	var top: float = viewport.position.y
	var right: float = viewport.end.x
	var bottom: float = viewport.end.y
	var proposed: Rect2 = Rect2(start, end - start).abs().grow(1.0)
	for panel: Control in _panels:
		if not panel.is_visible_in_tree():
			continue
		var area: Rect2 = panel.get_global_rect().intersection(viewport)
		if not area.has_area() or not area.intersects(proposed):
			continue
		if area.end.y <= start.y:
			top = maxf(top, area.end.y)
		elif area.position.y >= start.y:
			bottom = minf(bottom, area.position.y)
		elif area.end.x <= start.x:
			left = maxf(left, area.end.x)
		elif area.position.x >= start.x:
			right = minf(right, area.position.x)
	return Rect2(Vector2(left, top), Vector2(maxf(0.0, right - left), maxf(0.0, bottom - top)))


func dismiss_dialogs() -> void:
	_pending_demolish = 0
	_dialog.hide()


## 镜头焦点和总览使用包含视口中心的可用战场矩形；选择手势仍逐点裁剪实际面板。
func battle_view_rect() -> Rect2:
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var center: Vector2 = viewport.get_center()
	return selection_bounds(center, viewport.position).intersection(selection_bounds(center, viewport.end))


func present_map(map_state: Dictionary) -> void:
	_map_label.text = map_state["name"]
	_minimap_view.present_map(map_state)


func present_state(state: Dictionary) -> void:
	_session_ended = state["session"]["ended"]
	var threat: Dictionary = state.get("threat", {})
	if _wave_label != null:
		if _session_ended or threat.is_empty() or not threat.get("active", false) or (threat.get("phase", &"") == &"done" and threat.get("final_phase", "none") == "none"):
			_wave_label.hide()
		else:
			var seconds: int = ceili(float(threat.get("seconds_remaining", 0.0)))
			var clock := "%02d:%02d" % [seconds / 60, seconds % 60]
			var edge_name: String = String(threat.get("edge_name", ""))
			var phase: StringName = threat.get("phase", &"")
			if phase == &"done":
				_wave_label.text = "终波出兵中" if threat.get("final_phase", "none") == "releasing" else "终波清场中"
			elif phase == &"announced":
				_wave_label.text = "第%d波 %s · %s" % [int(threat.get("wave_number", 1)), clock, edge_name]
			elif phase == &"active":
				_wave_label.text = "第%d波已出兵%s · 下一波 %s" % [int(threat.get("wave_number", 1)), (" · " + edge_name) if not edge_name.is_empty() else "", clock]
			elif phase == &"silence" and threat.get("next_event", &"") == &"announce":
				_wave_label.text = "首波预告 %s" % clock
			else:
				_wave_label.text = "下一波 %s" % clock
			if threat.get("radar_warning", false):
				_wave_label.text += " · 雷达方向 %s" % String(threat.get("radar_edge_name", ""))
			if threat.get("campaign_mode", false):
				_wave_label.text += " · 阶段%s" % ["I", "II", "III"][clampi(int(threat.get("campaign_stage", 1)), 1, 3) - 1]
				match String(threat.get("final_phase", "none")):
					"requested":
						_wave_label.text += " · 终波已请求"
					"clearing":
						_wave_label.text += " · 终波清场中"
					"releasing":
						_wave_label.text += " · 全线出兵中"
					_:
						_wave_label.text += " · T请求终波"
			_wave_label.show()
			_wave_label.tooltip_text = _wave_label.text
	if _dispatch_label != null:
		var regions: Array = state.get("dispatch", {}).get("regions", [])
		if regions.is_empty():
			_dispatch_label.text = "调度区域 0 · F7创建 F8启停 F9删除"
		else:
			var enabled: int = 0
			var committed: Dictionary = {}
			var spent: Dictionary = {}
			var failure: String = ""
			var last_order: int = 0
			for region: Dictionary in regions:
				last_order = maxi(last_order, int(region.get("last_order_id", 0)))
				if region.get("enabled", false):
					enabled += 1
				for key: StringName in MechResources.KEYS:
					committed[key] = int(committed.get(key, 0)) + int(region.get("committed", {}).get(key, 0))
					spent[key] = int(spent.get(key, 0)) + int(region.get("spent", {}).get(key, 0))
				if failure.is_empty() and not String(region.get("failure_reason", "")).is_empty():
					failure = String(region["failure_reason"])
			_dispatch_label.text = "调度区域 %d · 启用%d · 预授权 %s · 已花 %s" % [
				regions.size(), enabled, MechResources.text(committed), MechResources.text(spent)]
			_dispatch_label.text += " · 当前#%d · F11切换/F8启停/F9删除" % int(state["dispatch"].get("selected_region_id", 0))
			if last_order > 0:
				_dispatch_label.text += " · 最近订单 #%d" % last_order
			if not failure.is_empty():
				_dispatch_label.text += " · " + failure
		_dispatch_label.tooltip_text = _dispatch_label.text
	$Root/SessionResult.visible = _session_ended
	$Root/WorldInfo/Subtitle.text = "%s  /  战术视图" % state["scenario"]
	if _generation != state["generation"]:
		_pending_demolish = 0
		_dialog.hide()
		_generation = state["generation"]
		_build_menu.reset_menu()
	var clock: Dictionary = state["clock"]
	var seconds: float = clock["elapsed_seconds"]
	_clock_label.text = "%02d:%02d" % [int(seconds / 60.0), int(fmod(seconds, 60.0))]
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
	var economy: Dictionary = state["economy"]
	_coins_label.text = "算力币  %d   +%d/分钟" % [economy["coins"], economy["income_rate"]]
	var balances: Dictionary = economy["resources"]
	var rates: Dictionary = economy["production_per_minute"]
	_ore_label.text = "金属矿  %d   +%d/分钟" % [balances[&"metal_ore"], rates[&"metal_ore"]]
	_fuel_label.text = "碳晶  %d   +%d/分钟" % [balances[&"fuel"], rates[&"fuel"]]
	_alloy_label.text = "合金  %d   +%d/分钟" % [balances[&"alloy"], rates[&"alloy"]]
	_crystals_label.text = "超导矿  %d   +%d/分钟" % [balances[&"crystals"], rates[&"crystals"]]
	_capacity_label.text = "调度  %d / %d%s" % [economy["capacity_used"], economy["capacity_supply"], "  超载" if economy["overloaded"] else ""]
	_capacity_label.modulate = Color("f27c78") if economy["overloaded"] else INK
	_capacity_label.tooltip_text = "总算力 %d，系统预留 %d，可调度 %d\n单位占用 %d，队列预留 %d；出厂不重复占用" % [economy["capacity_total"], economy["capacity_system_reserved"], economy["capacity_supply"], economy["unit_capacity"], economy["queued_capacity"]]
	_power_label.text = "电力余量  %d / %d%s" % [economy["power_free"], economy["power_supply"], "  赤字" if economy["power_deficit"] else ""]
	_power_label.modulate = Color("f27c78") if economy["power_deficit"] else INK
	_cooling_label.visible = economy["cooling_supply"] > 0 or economy["cooling_reserved"] > 0
	_cooling_label.text = "冷却  %.1f / %.1f%s" % [economy["cooling_reserved"] / 10.0, economy["cooling_supply"] / 10.0, "  赤字" if economy["cooling_deficit"] else ""]
	_cooling_label.modulate = Color("f27c78") if economy["cooling_deficit"] else INK
	_build_menu.present_catalog(state["catalog"], _session_ended)
	var repair_all: Dictionary = state.get("repair_all", {})
	_repair_all_button.disabled = _session_ended or not repair_all.get("ok", false)
	_repair_all_button.tooltip_text = repair_all.get("reason", "") if _repair_all_button.disabled \
		else "对全部受损完工建筑开启维修（每座 4 HP/秒；满修材料为新建配方25%，按实际修复HP扣）；被攻击后进入交战状态，周边 6 格内有敌军期间自动暂停，脱离后恢复"
	_minimap_view.present_state(state)


func present_camera(polygon: PackedVector2Array) -> void:
	_minimap_view.present_camera(polygon)


func is_minimap_fullscreen() -> bool:
	return _minimap_fullscreen


func begin_dispatch_region_selection() -> void:
	set_minimap_fullscreen(true)
	_minimap_view.set_region_mode(true)
	feedback("区域框选：在全屏小地图按住左键拖出矩形，松开提交；M/Esc取消。")


func toggle_minimap_fullscreen() -> void:
	set_minimap_fullscreen(not _minimap_fullscreen)


func set_minimap_fullscreen(active: bool) -> void:
	if _minimap_fullscreen == active:
		return
	_minimap_fullscreen = active
	if not active:
		_minimap_view.set_region_mode(false)
	if active:
		_layout_fullscreen_minimap()
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


func _layout_fullscreen_minimap() -> void:
	if not _minimap_fullscreen:
		return
	var base: Vector2 = $Root.size
	var side: float = minf(floor(base.x * 0.60), base.y - 368.0)
	_minimap_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_minimap_panel.offset_left = -side * 0.5
	_minimap_panel.offset_right = side * 0.5
	_minimap_panel.offset_top = 80.0
	_minimap_panel.offset_bottom = 80.0 + side


func present_zoom(factor: float) -> void:
	_zoom_label.text = "%d%% · %s" % [roundi(factor * 100.0), "全图" if factor < MechMapCamera3D.MIN_ZOOM else "战术"]


func present_build(id: StringName) -> void:
	_build_menu.present_build(id)


func present_cell(info: Dictionary, preview: Dictionary) -> void:
	if info.is_empty():
		_cell_label.text = "鼠标移至地图查看格子"
	else:
		var cell: Vector2i = info["cell"]
		_cell_label.text = "格子  (%d, %d)  ·  %s" % [cell.x, cell.y, info["terrain_name"]]
		if info.get("wind", false):
			_cell_label.text += " · 风口"
		if info.get("water", false):
			_cell_label.text += " · 水域（不可通行/建造）"
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
		_space_label.text = "%d×%d  ·  %s  ·  %s" % [footprint.x, footprint.y, MechResources.text(preview.get("cost", {})), "可下单；左键轻点确认" if preview["ok"] else preview["reason"]]
		var energy_type: String = String(preview.get("environment_energy", "none"))
		if energy_type != "none":
			var bounds: Rect2i = preview.get("collection_bounds", Rect2i())
			_space_label.text += "\n环境预计 +%d %s · 采集区 %d×%d%s" % [
				int(preview.get("environment_power", 0)),
				"冷" if preview.get("environment_output_is_cooling", false) else "电",
				bounds.size.x, bounds.size.y,
				" · 同类采集区冲突" if not preview.get("conflict_cells", []).is_empty() else ""]
		_space_label.modulate = ACCENT if preview["ok"] else Color("f27c78")

	_space_label.tooltip_text = _space_label.text


func present_selection(building: Dictionary, errors: Dictionary) -> void:
	_selection = building.duplicate(true)
	_cell_label.visible = building.is_empty()
	_present_portrait(building)
	for widget: Control in _production_widgets:
		widget.hide()
	for widget: Control in _building_widgets:
		widget.visible = not building.is_empty()
	if building.is_empty():
		_selection_title.text = "区域信息"
		_upgrade_button.hide()
		return
	var footprint: Vector2i = building["footprint"]
	_selection_title.text = "%s · %d×%d" % [building["name"], footprint.x, footprint.y]
	_status_label.text = building["status"]
	_status_label.tooltip_text = _status_label.text
	_status_label.modulate = Color("f27c78") if building["phase"] == MechBuildingState.Phase.RUINED or not building.get("powered", true) \
		else (ACCENT if building["phase"] == MechBuildingState.Phase.OPERATING else Color("f0bc79"))
	_build_bar.value = 100.0 * float(building["demolition_progress"] if building["phase"] == MechBuildingState.Phase.DEMOLISHING else building["build_progress"])
	_build_label.text = "%s  %d%%" % ["清除基座进度" if building["phase"] == MechBuildingState.Phase.DEMOLISHING and building["hp"] <= 0 else ("拆除进度" if building["phase"] == MechBuildingState.Phase.DEMOLISHING else "施工进度"), roundi(_build_bar.value)]
	var show_progress: bool = building["phase"] in [MechBuildingState.Phase.CONSTRUCTING, MechBuildingState.Phase.DEMOLISHING]
	_build_label.visible = show_progress
	_build_bar.visible = show_progress
	_hp_bar.value = 100.0 * float(building["hp"]) / float(building["max_hp"])
	_hp_label.text = "血量  %d / %d" % [building["hp"], building["max_hp"]]
	_details.text = "预留  电力 %d · 容量 %d\n供给  电力 +%d · 容量 +%d\n运行收入  +%d 币/分钟" % [building["power_cost"], building["capacity_cost"], building["power_provided"], building["capacity_provided"], building["income_per_minute"]]
	if int(building.get("cooling_cost", 0)) > 0:
		_details.text += "\n冷却预留  %.1f" % (float(building["cooling_cost"]))
	if int(building.get("cooling_provided", 0)) > 0:
		_details.text += "\n冷却供给  +%.1f（全基地共享）" % (float(building["cooling_provided"]))
	_present_upgrade(building)
	if int(building.get("coverage_radius", 0)) > 0 and not building.get("is_core", false):
		_details.text += "\n覆盖扩展  +%d 格（需与主脑连通）" % int(building["coverage_radius"])
	if building["hp"] < building["max_hp"] or building.get("repairing", false):
		_details.text += "\n维修 4 HP/秒 · 满修材料为新建配方25%（按实际HP扣，余数保留）"
		if building.get("repair_waiting_for_materials", false):
			_details.text += "\n维修等待材料"
	if String(building.get("environment_energy", "none")) != "none":
		_details.text += "\n环境%s  +%d（已探索选址）" % [
			"供冷" if building.get("environment_output_is_cooling", false) else "供电",
			int(building.get("environment_power", 0))]
	if int(building.get("garrison_capacity", 0)) > 0:
		_details.text += "\n驻防  %d/%d名卫兵 · 射程+%.0f · G进驻/U撤离" % [
			int(building.get("garrison_count", 0)), int(building.get("garrison_capacity", 0)),
			float(building.get("garrison_range_bonus", 0.0))]
	var recipe: Dictionary = building.get("alloy_recipe", {})
	if not recipe.is_empty():
		var processing: Dictionary = building.get("processing", {})
		_details.text += "\n周期 %.0fs · 碳晶%d + 金属%d → 合金%d · 燃烧 +%d电" % [
			float(recipe.get("cycle_seconds", 15.0)), int(recipe.get("fuel_cost", 2)),
			int(recipe.get("metal_cost", 1)), int(recipe.get("alloy_output", 1)),
			int(recipe.get("power_output", 30))]
		if processing.get("active", false):
			_details.text += "\n燃烧进度 %d%% · 已投入 %s" % [
				roundi(float(processing.get("progress", 0.0)) * 100.0),
				MechResources.text(processing.get("paid", {}))]
		else:
			_details.text += "\n待碳晶；满负荷 %.0f 合金/分钟" % (
				60.0 * float(recipe.get("alloy_output", 1)) / float(recipe.get("cycle_seconds", 15.0)))
	var mineral: Dictionary = building.get("mineral", {})
	if building["phase"] == MechBuildingState.Phase.RUINED:
		_build_label.hide()
		_build_bar.hide()
		_details.text = "已摧毁 · 保留占位与矿点绑定，不阻挡通行\n重建支付全额 50%%，施工 %.1f 秒，血量随进度爬升\n清除基座不退款，完成时释放占地与矿点绑定" % building["construction_seconds"]
		if not mineral.is_empty():
			_details.text += "\n矿点绑定保留 · 剩余 %d / %d" % [mineral["remaining"], mineral["initial_amount"]]
	elif not mineral.is_empty():
		_details.text = "预留  电力 %d · 容量 %d\n采集产率  %d 金属矿/分钟\n剩余储量  %d / %d\n%s" % [building["power_cost"], building["capacity_cost"], building["extraction_per_minute"], mineral["remaining"], mineral["initial_amount"], "矿点耗竭，可拆除" if mineral["remaining"] == 0 else "完工且供电后采集"]
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
		_primary.text = "停止维修" if building["repairing"] else "维修 · 4 HP/秒，材料25%"
		_primary.tooltip_text = errors.get("repair", "")
	_primary.disabled = not _primary.tooltip_text.is_empty()
	_demolish.text = "清除基座 [X] · 无退款" if building["phase"] == MechBuildingState.Phase.RUINED else "拆除 [X] · 返还 %s" % MechResources.text(building["refund"])
	_demolish.tooltip_text = errors.get("demolish", "")
	_demolish.disabled = not _demolish.tooltip_text.is_empty()
	if not _primary.disabled:
		_primary.tooltip_text = _primary.text
	if not _demolish.disabled:
		_demolish.tooltip_text = _demolish.text
	var production: Dictionary = building.get("production", {})
	if not production.is_empty():
		for widget: Control in _production_widgets:
			widget.show()
		var queue: Array = production["queue"]
		var options: Array = building["unit_options"]
		var product: Dictionary = options[0]
		var choices: MenuButton = $Root/Inspector/Produce
		choices.text = "选择生产单位" if options.size() > 1 else "生产%s · %s" % [product["name"], MechResources.text(product["cost"])]
		var unavailable: bool = true
		var names := PackedStringArray()
		for option: Dictionary in options:
			unavailable = unavailable and not option["production_error"].is_empty()
			names.append(option["name"])
		choices.disabled = unavailable
		choices.tooltip_text = product["production_error"] if options.size() == 1 else "选择兵种；下单即支付资源并预留调度"
		var menu_key: String = str(building["entity_id"]) + str(options)
		if menu_key != _product_menu_key:
			_product_menu_key = menu_key
			var popup: PopupMenu = choices.get_popup()
			popup.clear()
			if options.size() > 1:
				for index: int in range(options.size()):
					var option: Dictionary = options[index]
					popup.add_item("%s · %s" % [option["name"], MechResources.text(option["cost"])], index)
					popup.set_item_metadata(index, option["unit_id"])
					popup.set_item_disabled(index, not option["production_error"].is_empty())
		$Root/Inspector/CancelProduction.disabled = _session_ended or queue.is_empty()
		$Root/Inspector/Queue.text = "队列 %d / %d · %d%%" % [queue.size(), building["queue_limit"], roundi(production["progress"] * 100)]
		$Root/Inspector/Queue.tooltip_text = "出口受阻，订单保留" if production["blocked"] else "选厂后右键设置集结点"
		if building["phase"] == MechBuildingState.Phase.OPERATING:
			_build_label.show()
			_build_bar.show()
			_build_label.text = "生产进度  %d%%" % roundi(production["progress"] * 100)
			_build_bar.value = production["progress"] * 100
			if production["blocked"]:
				_status_label.text = "出口受阻 · 等待空位"
		var rally: Vector2i = production["rally"]
		_details.text = "预留 电力 %d · 调度 %d\n集结点 (%d, %d)\n可生产：%s\n取消队首全额退资源并释放调度" % [building["power_cost"], building["capacity_cost"], rally.x, rally.y, " / ".join(names)]


func _present_upgrade(building: Dictionary) -> void:
	var upgrade: Dictionary = building.get("upgrade", {})
	var active: bool = upgrade.get("active", false)
	var can_upgrade: bool = building.get("can_upgrade", false)
	_upgrade_mode_cancel = false
	if active:
		var progress: int = roundi(float(upgrade.get("progress", 0.0)) * 100.0)
		if building.get("is_core", false):
			_upgrade_button.text = "主脑升级中 %d%% · 不可取消" % progress
			_upgrade_button.disabled = true
			_upgrade_button.tooltip_text = "主脑升级沿旧设计不可取消"
		else:
			_upgrade_mode_cancel = true
			_upgrade_button.text = "取消升级 %d%% · 退还 %s" % [progress, MechResources.text(upgrade.get("paid", {}))]
			_upgrade_button.disabled = _session_ended
			_upgrade_button.tooltip_text = "取消只退本次未完成升级差价，不退原建筑"
		_upgrade_button.show()
		_details.text += "\n升级目标  %s · %d%%" % [upgrade.get("target_name", ""), progress]
	elif can_upgrade:
		_upgrade_button.text = "升级至 %s · %s" % [building.get("upgrade_target_name", ""), MechResources.text(building.get("upgrade_cost", {}))]
		var upgrade_error: String = building.get("upgrade_error", "")
		_upgrade_button.disabled = _session_ended or not upgrade_error.is_empty()
		_upgrade_button.tooltip_text = upgrade_error if not upgrade_error.is_empty() else \
			"工期 %.0fs；保持旧级服务，完成后原子切换" % float(building.get("upgrade_seconds", 0.0))
		_upgrade_button.show()
		_details.text += "\n等级 %d · 升级差价 %s · 工期 %.0fs" % [
			int(building.get("level", 1)), MechResources.text(building.get("upgrade_cost", {})),
			float(building.get("upgrade_seconds", 0.0))]
		if not upgrade_error.is_empty():
			_details.text += "\n升级条件：%s" % upgrade_error
	else:
		_upgrade_button.hide()


func _upgrade_pressed() -> void:
	if _selection.is_empty():
		return
	var entity_id: int = int(_selection["entity_id"])
	if _upgrade_mode_cancel:
		upgrade_cancelled.emit(entity_id)
	else:
		upgrade_requested.emit(entity_id)


func present_units(units: Array[Dictionary]) -> void:
	_cell_label.hide()
	_present_portrait(units[0])
	var hp: int = 0
	var max_hp: int = 0
	var capacity: int = 0
	var orders: Dictionary = {}
	for unit: Dictionary in units:
		hp += unit["hp"]
		max_hp += unit["max_hp"]
		capacity += unit["capacity_cost"]
		orders[unit["order"]] = true
	var same_type: bool = true
	for unit: Dictionary in units:
		same_type = same_type and unit["name"] == units[0]["name"]
	_selection_title.text = "%s × %d" % [units[0]["name"] if same_type else "混合部队", units.size()]
	_status_label.show()
	_status_label.text = {&"idle": "待命 / 射程内开火 · 不追击", &"move": "移动中", &"attack_move": "攻击移动中", &"attack": "攻击指定目标"}.get(orders.keys()[0], "待命") if orders.size() == 1 else "多种指令执行中"
	_status_label.modulate = ACCENT
	_status_label.tooltip_text = _status_label.text
	_hp_label.show()
	_hp_label.text = "总血量 %d / %d · 占容 %d" % [hp, max_hp, capacity]
	_hp_bar.show()
	_hp_bar.value = 100.0 * hp / maxi(1, max_hp)
	_details.show()
	_details.text = "右键：移动 / 攻击目标\n移动抵达后：射程内开火，不追击\nA＋左键：沿途索敌追击后继续前进\nCtrl＋数字：编队，数字：召回\nShift 追加，Ctrl 点击切换选择"


func _present_portrait(entity: Dictionary) -> void:
	var portrait: SubViewportContainer = $Root/Inspector/Portrait
	portrait.visible = not entity.is_empty()
	if entity.is_empty():
		return
	var key: String = "%s_%s_%d_%d_%s" % [entity["kind"], entity["footprint"], entity.get("phase", -1), int(entity.get("build_progress", 1.0) * 10), entity.get("hp", 1) <= 0]
	if key == _portrait_key:
		return
	_portrait_key = key
	var model: MechPortraitView2D = $Root/Inspector/Portrait/Viewport/Model
	var copy: Dictionary = entity.duplicate(true)
	copy["position"] = Vector2(copy["footprint"]) * 0.5 if copy.get("is_building", false) else Vector2.ZERO
	copy["origin"] = Vector2i.ZERO
	copy["has_order"] = false
	copy["order"] = &"idle"
	copy["shot_ticks"] = 0
	copy["hp"] = 0 if copy.get("hp", 1) <= 0 else copy.get("max_hp", 1)
	var factor: float = 0.75 if copy["kind"] == &"mainbrain" else (1.1 if copy.get("is_building", false) else 2.7)
	factor *= portrait.size.x / 160.0
	model.scale = Vector2.ONE * factor
	model.position = portrait.size * Vector2(0.5, 0.725) - MechIsoGeometry.project(copy["position"]) * factor
	model.present(copy)
	$Root/Inspector/Portrait/Viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func present_drag(rect: Rect2, active: bool) -> void:
	$Root/SelectionBox.visible = active
	$Root/SelectionBox.position = rect.position
	$Root/SelectionBox.size = rect.size


func _produce_pressed() -> void:
	var options: Array = _selection.get("unit_options", [])
	if options.size() == 1:
		production_requested.emit(_selection["entity_id"], options[0]["unit_id"])


func _produce_choice(index: int) -> void:
	if not _selection.is_empty():
		production_requested.emit(_selection["entity_id"], $Root/Inspector/Produce.get_popup().get_item_metadata(index))


func _cancel_production_pressed() -> void:
	if _selection.is_empty():
		return
	var queue: Array = _selection.get("production", {}).get("queue", [])
	if not queue.is_empty():
		production_cancelled.emit(_selection["entity_id"], queue[0]["ticket"])


func feedback(message: String, failed: bool = false) -> void:
	_feedback_label.text = message
	_feedback_label.modulate = Color("f0bc79") if failed else ACCENT
	_feedback_label.tooltip_text = message


func request_demolition() -> void:
	if _selection.is_empty() or _demolish.disabled:
		feedback("请先选择可拆除的完工建筑或基座。", true)
		return
	_pending_demolish = _selection["entity_id"]
	if _selection.get("phase", MechBuildingState.Phase.OPERATING) == MechBuildingState.Phase.RUINED:
		_dialog.dialog_text = "立即清除「%s」基座，无退款。\n确认后释放占地、矿点及环境采集区预约。" % _selection["name"]
	else:
		_dialog.dialog_text = "立即拆除「%s」，返还 %s。\n确认后建筑移除、占用释放，未交付订单与未结周期投入一并结清。" % [_selection["name"], MechResources.text(_selection["refund"])]
	_dialog.popup_centered(Vector2i(540, 210))


func _confirm_demolition() -> void:
	var id: int = _pending_demolish
	_pending_demolish = 0
	if id > 0:
		building_action_requested.emit(MechCommand.Type.DEMOLISH, id)


func _primary_pressed() -> void:
	if not _selection.is_empty():
		building_action_requested.emit(_primary_action, _selection["entity_id"])
