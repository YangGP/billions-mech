extends Node2D
## 主场景入口：装配 GameState 与视图层，并处理全局输入。

@onready var game_state: GameState = $GameState
@onready var world: World = $World
@onready var hud: HUD = $HUD


func _ready() -> void:
	hud.bind(game_state)
	world.setup(game_state)
	print(
		"Billions Mech 启动：地图 %d×%d，经济 tick %.2f 秒"
		% [game_state.map_width, game_state.map_height, game_state.clock.tick_seconds]
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		game_state.clock.toggle_pause()
		get_viewport().set_input_as_handled()
