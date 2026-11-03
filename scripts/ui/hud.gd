class_name HUD
extends CanvasLayer
## HUD 只读取 GameState，并通过信号刷新显示；不直接修改资源或建筑数据。

@onready var resource_panel: ResourcePanel = %ResourcePanel
@onready var build_palette: BuildPalette = %BuildPalette
@onready var building_info: BuildingInfoPanel = %BuildingInfoPanel
@onready var region_panel: RegionPanel = %RegionPanel
@onready var view_banner: Label = %ViewBanner
@onready var threat_panel: ThreatPanel = %ThreatPanel
@onready var defeat_overlay: Control = %DefeatOverlay
@onready var restart_button: Button = %RestartButton

var _game_state: GameState


func _ready() -> void:
	resource_panel.pause_requested.connect(_on_pause_requested)
	resource_panel.speed_requested.connect(_on_speed_requested)
	restart_button.pressed.connect(_on_restart_pressed)
	defeat_overlay.visible = false


func bind(game_state: GameState) -> void:
	if _game_state != null:
		return
	_game_state = game_state
	game_state.resources_changed.connect(_on_resources_changed)
	game_state.capacity_changed.connect(_on_capacity_changed)
	game_state.buildings_changed.connect(_on_buildings_changed)
	game_state.clock.tick.connect(_on_clock_tick)
	game_state.clock.paused_changed.connect(_on_paused_changed)
	game_state.clock.speed_changed.connect(_on_speed_changed)

	_on_resources_changed(game_state.economy.get_resources())
	_on_capacity_changed()
	_on_buildings_changed()
	_on_clock_tick(0)
	_on_paused_changed(game_state.clock.paused)
	_on_speed_changed(game_state.clock.speed)


## 由 World 的悬停信号驱动，显示当前逻辑格坐标。
func show_cursor_cell(cell: Vector2i, inside: bool) -> void:
	resource_panel.display_cursor_cell(cell, inside)


## 建造提示 / 错误原因，显示在建造菜单内。
func set_status(text: String) -> void:
	build_palette.set_status(text)


## 悬停建筑时显示详情；M1-05 只读定义，不展示未实现的运转状态。
func show_building_info(definition: BuildingDefinition) -> void:
	building_info.show_definition(definition)


func hide_building_info() -> void:
	building_info.hide_info()


## 绑定威胁系统：核心生命、波次倒计时与失败状态。
func bind_threat(threat: ThreatSystem) -> void:
	threat.core_hp_changed.connect(_on_core_hp_changed)
	threat.wave_changed.connect(_on_wave_changed)
	threat.defeat.connect(_on_defeat)

	_on_core_hp_changed(threat.core_hp, threat.core_max_hp)
	var snapshot := threat.get_wave_snapshot()
	_on_wave_changed(
		int(snapshot["wave"]),
		float(snapshot["seconds"]),
		int(snapshot["alive"]),
		bool(snapshot["in_wave"])
	)


## 区块视图下隐藏建造菜单与建筑信息，只保留资源栏与区块面板。
func set_region_view_active(active: bool) -> void:
	view_banner.visible = active
	build_palette.visible = not active
	if active:
		building_info.hide_info()


func show_region_stats(stats: Dictionary) -> void:
	region_panel.show_stats(stats)


func hide_region_stats() -> void:
	region_panel.hide_stats()


func _on_resources_changed(resources: Dictionary) -> void:
	if _game_state == null:
		return
	resource_panel.display_resources(resources, _game_state.economy.get_net_rates())


func _on_capacity_changed() -> void:
	if _game_state == null:
		return
	resource_panel.display_capacity(_game_state.economy)
	resource_panel.display_resources(
		_game_state.economy.get_resources(),
		_game_state.economy.get_net_rates()
	)


func _on_buildings_changed() -> void:
	if _game_state == null:
		return
	resource_panel.display_buildings(
		_game_state.get_building_count(),
		_game_state.get_occupied_cell_count()
	)


func _on_clock_tick(_tick_index: int) -> void:
	if _game_state == null:
		return
	resource_panel.display_time(_game_state.clock.elapsed_game_seconds)


func _on_paused_changed(paused: bool) -> void:
	resource_panel.set_paused(paused)


func _on_pause_requested() -> void:
	if _game_state != null:
		_game_state.clock.toggle_pause()


func _on_speed_requested() -> void:
	if _game_state != null:
		_game_state.clock.cycle_speed()


func _on_speed_changed(_speed: float) -> void:
	if _game_state != null:
		resource_panel.set_speed_text(_game_state.clock.get_speed_label())


func _on_core_hp_changed(current: int, maximum: int) -> void:
	threat_panel.display_core(current, maximum)


func _on_wave_changed(
	next_wave: int, seconds_to_next: float, alive: int, in_wave: bool
) -> void:
	threat_panel.display_wave(next_wave, seconds_to_next, alive, in_wave)


func _on_defeat() -> void:
	defeat_overlay.visible = true
	build_palette.visible = false
	building_info.hide_info()
	region_panel.hide_stats()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()
