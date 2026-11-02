class_name BuildRangeOverlay
extends Node2D
## 建造覆盖范围：半透明填充 + 边界描边。
##
## 只读取 BuildingSystem.build_coverage，不参与任何合法性判断。

const TILE_WIDTH: float = 128.0
const TILE_HEIGHT: float = 64.0
const FILL_COLOR := Color(0.25, 0.9, 0.45, 0.08)
const EDGE_COLOR := Color(0.35, 1.0, 0.55, 0.55)

var _world: World
var _game_state: GameState


## 只有进入建造模式时才显示覆盖范围。
func _ready() -> void:
	visible = false


func set_active(active: bool) -> void:
	visible = active
	if active:
		queue_redraw()


func setup(world: World, game_state: GameState) -> void:
	_world = world
	_game_state = game_state
	game_state.buildings.buildings_changed.connect(_on_buildings_changed)
	queue_redraw()


func _on_buildings_changed() -> void:
	queue_redraw()


func _draw() -> void:
	if _world == null or _game_state == null:
		return

	var coverage: Dictionary = _game_state.buildings.build_coverage
	var half_w := TILE_WIDTH * 0.5
	var half_h := TILE_HEIGHT * 0.5
	var cells := coverage.keys()

	for cell in cells:
		var center := to_local(_world.cell_to_world(cell))
		draw_colored_polygon(
			PackedVector2Array([
				center + Vector2(0.0, -half_h),
				center + Vector2(half_w, 0.0),
				center + Vector2(0.0, half_h),
				center + Vector2(-half_w, 0.0),
			]),
			FILL_COLOR
		)

	for cell in cells:
		var center := to_local(_world.cell_to_world(cell))
		var top := center + Vector2(0.0, -half_h)
		var right := center + Vector2(half_w, 0.0)
		var bottom := center + Vector2(0.0, half_h)
		var left := center + Vector2(-half_w, 0.0)

		if not coverage.has(cell + Vector2i(1, 0)):
			draw_line(right, bottom, EDGE_COLOR, 2.0, true)
		if not coverage.has(cell + Vector2i(-1, 0)):
			draw_line(top, right, EDGE_COLOR, 2.0, true)
		if not coverage.has(cell + Vector2i(0, 1)):
			draw_line(bottom, left, EDGE_COLOR, 2.0, true)
		if not coverage.has(cell + Vector2i(0, -1)):
			draw_line(left, top, EDGE_COLOR, 2.0, true)
