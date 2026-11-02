class_name World
extends Node2D
## 视图层根节点：只负责坐标投影与视觉节点，不修改任何模拟数据。
##
## Ground 图层是等距投影的唯一参照：逻辑格 -> 世界坐标、鼠标 -> 逻辑格
## 都必须通过它转换，不要自己另写一份等距换算公式。

signal hovered_cell_changed(cell: Vector2i, inside: bool)

const INVALID_CELL := Vector2i(-1, -1)

@onready var ground: TileMapLayer = $Ground
@onready var highlight: CellHighlight = $Highlight
@onready var decorations: TileMapLayer = $Decorations
@onready var buildings_root: Node2D = $Buildings
@onready var build_preview: Node2D = $BuildPreview
@onready var region_overlay: Node2D = $RegionOverlay

var _game_state: GameState
var _hovered_cell: Vector2i = INVALID_CELL


func setup(game_state: GameState) -> void:
	_game_state = game_state
	_build_ground()


func _process(_delta: float) -> void:
	if _game_state == null or ground.tile_set == null:
		return

	var cell := mouse_to_cell()
	if cell == _hovered_cell:
		return
	_hovered_cell = cell

	var inside := _game_state.grid.is_inside_map(cell)
	if inside:
		highlight.show_at(cell_to_world(cell))
	else:
		highlight.hide_highlight()
	hovered_cell_changed.emit(cell if inside else INVALID_CELL, inside)


## 鼠标位置对应的逻辑格；地图瓦片尚未配置时返回 (-1, -1)。
func mouse_to_cell() -> Vector2i:
	if ground.tile_set == null:
		return INVALID_CELL
	var local_mouse := ground.to_local(get_global_mouse_position())
	return ground.local_to_map(local_mouse)


## 逻辑格中心对应的世界坐标（注意：这是格中心，不是建筑视觉中心）。
func cell_to_world(cell: Vector2i) -> Vector2:
	if ground.tile_set == null:
		return ground.to_global(Vector2.ZERO)
	return ground.to_global(ground.map_to_local(cell))


## 地图在全局坐标中的矩形范围，供相机边界限制使用。
## 等距菱形地图的极值在四个角上，不能只取左上/右下两格。
func get_map_world_rect() -> Rect2:
	if _game_state == null or ground.tile_set == null:
		return Rect2()

	var max_x := _game_state.map_width - 1
	var max_y := _game_state.map_height - 1
	var corners := [
		cell_to_world(Vector2i(0, 0)),
		cell_to_world(Vector2i(max_x, 0)),
		cell_to_world(Vector2i(0, max_y)),
		cell_to_world(Vector2i(max_x, max_y)),
	]
	var rect := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		rect = rect.expand(corner)
	# 菱形瓦片的四个角会超出中心点包围盒，按半格宽高外扩。
	return rect.grow(64.0)


func _build_ground() -> void:
	if ground.tile_set == null:
		push_warning("Ground 图层未配置 TileSet，跳过地面生成")
		return

	ground.clear()
	for y in range(_game_state.map_height):
		for x in range(_game_state.map_width):
			ground.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
