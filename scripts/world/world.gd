class_name World
extends Node2D
## 视图层根节点：只负责坐标投影与视觉节点，不修改任何模拟数据。
##
## Ground 图层是等距投影的唯一参照：逻辑格 -> 世界坐标、鼠标 -> 逻辑格
## 都必须通过它转换，不要自己另写一份等距换算公式。

@onready var ground: TileMapLayer = $Ground
@onready var decorations: TileMapLayer = $Decorations
@onready var buildings_root: Node2D = $Buildings
@onready var build_preview: Node2D = $BuildPreview
@onready var region_overlay: Node2D = $RegionOverlay

var _game_state: GameState


func setup(game_state: GameState) -> void:
	_game_state = game_state


## 鼠标位置对应的逻辑格；地图瓦片尚未配置时返回 (-1, -1)。
func mouse_to_cell() -> Vector2i:
	if ground.tile_set == null:
		return Vector2i(-1, -1)
	var local_mouse := ground.to_local(get_global_mouse_position())
	return ground.local_to_map(local_mouse)


## 逻辑格中心对应的世界坐标（注意：这是格中心，不是建筑视觉中心）。
func cell_to_world(cell: Vector2i) -> Vector2:
	if ground.tile_set == null:
		return ground.to_global(Vector2.ZERO)
	return ground.to_global(ground.map_to_local(cell))


## 地图在全局坐标中的矩形范围，供相机边界限制使用（M1-02）。
func get_map_world_rect() -> Rect2:
	if _game_state == null or ground.tile_set == null:
		return Rect2()
	var first := cell_to_world(Vector2i.ZERO)
	var last := cell_to_world(Vector2i(_game_state.map_width - 1, _game_state.map_height - 1))
	var rect := Rect2(first, Vector2.ZERO)
	rect = rect.expand(last)
	return rect.grow(64.0)
