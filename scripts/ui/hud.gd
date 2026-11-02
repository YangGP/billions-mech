class_name HUD
extends CanvasLayer
## HUD 只读取 GameState，并通过信号刷新显示；不直接修改资源或建筑数据。

@onready var resource_panel: ResourcePanel = %ResourcePanel
@onready var hint_label: Label = %HintLabel
@onready var build_palette: PanelContainer = %BuildPalette

var _game_state: GameState


func _ready() -> void:
	resource_panel.pause_requested.connect(_on_pause_requested)


func bind(game_state: GameState) -> void:
	if _game_state != null:
		return
	_game_state = game_state
	game_state.resources_changed.connect(_on_resources_changed)
	game_state.capacity_changed.connect(_on_capacity_changed)
	game_state.buildings_changed.connect(_on_buildings_changed)
	game_state.clock.tick.connect(_on_clock_tick)
	game_state.clock.paused_changed.connect(_on_paused_changed)

	_on_resources_changed(game_state.economy.get_resources())
	_on_capacity_changed()
	_on_buildings_changed()
	_on_clock_tick(0)
	_on_paused_changed(game_state.clock.paused)


func _on_resources_changed(resources: Dictionary) -> void:
	resource_panel.display_resources(resources)


func _on_capacity_changed() -> void:
	if _game_state == null:
		return
	resource_panel.display_capacity(_game_state.economy)


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
