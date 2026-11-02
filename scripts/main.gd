extends Node2D
## 主场景入口：装配 GameState 与视图层，并处理全局输入。

@onready var game_state: GameState = $GameState
@onready var world: World = $World
@onready var camera: CameraController = $Camera2D
@onready var hud: HUD = $HUD
@onready var build_controller: BuildController = $BuildController


func _ready() -> void:
	world.setup(game_state)
	hud.bind(game_state)
	world.hovered_cell_changed.connect(hud.show_cursor_cell)
	camera.setup(world)
	build_controller.setup(game_state, world, hud)

	print(
		"Billions Mech 启动：地图 %d×%d，经济 tick %.2f 秒，世界范围 %s"
		% [
			game_state.map_width,
			game_state.map_height,
			game_state.clock.tick_seconds,
			world.get_map_world_rect(),
		]
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		game_state.clock.toggle_pause()
		get_viewport().set_input_as_handled()
