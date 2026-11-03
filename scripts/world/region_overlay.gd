class_name RegionOverlay
extends Node2D
## 区块视图覆盖层：区块填充、边界、名称与建筑数量。
##
## 只读取 RegionSystem / GameState 的聚合结果，不参与任何经济或建造逻辑。
## 覆盖层始终画在实体世界之上（z_index 高），但填充透明度很低，建筑仍可见。

const TILE_WIDTH: float = 128.0
const TILE_HEIGHT: float = 64.0
const INVALID_REGION := Vector2i(-1, -1)

const FILL_EVEN := Color(0.25, 0.55, 0.95, 0.055)
const FILL_ODD := Color(0.25, 0.85, 0.6, 0.055)
const BOUNDARY_COLOR := Color(0.8, 0.9, 1.0, 0.42)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const SELECTED_FILL := Color(1.0, 0.82, 0.25, 0.16)
const SELECTED_COLOR := Color(1.0, 0.85, 0.3, 1.0)
const LABEL_COLOR := Color(0.96, 0.98, 1.0, 0.95)
const LABEL_SHADOW := Color(0.0, 0.0, 0.0, 0.75)

var _world: World
var _game_state: GameState
var _hovered_region: Vector2i = INVALID_REGION
var _selected_region: Vector2i = INVALID_REGION


func _ready() -> void:
	visible = false


func setup(world: World, game_state: GameState) -> void:
	_world = world
	_game_state = game_state
	game_state.buildings.buildings_changed.connect(_on_buildings_changed)
	set_process(false)


func set_active(active: bool) -> void:
	visible = active
	if active:
		queue_redraw()


func set_hovered(region_id: Vector2i) -> void:
	if _hovered_region == region_id:
		return
	_hovered_region = region_id
	queue_redraw()


func set_selected(region_id: Vector2i) -> void:
	_selected_region = region_id
	queue_redraw()


func clear_selection() -> void:
	set_selected(INVALID_REGION)


func _on_buildings_changed() -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _world == null or _game_state == null:
		return

	var regions: RegionSystem = _game_state.regions
	var font := ThemeDB.fallback_font
	var font_size := 20

	for y in range(regions.regions_y):
		for x in range(regions.regions_x):
			var region_id := Vector2i(x, y)
			var points := _region_points(region_id)
			if points.size() < 4:
				continue

			var fill_color := FILL_EVEN if (x + y) % 2 == 0 else FILL_ODD
			if region_id == _selected_region:
				fill_color = SELECTED_FILL
			draw_colored_polygon(points, fill_color)

			var outline := points.duplicate()
			outline.append(points[0])
			var line_color := BOUNDARY_COLOR
			var line_width := 2.0
			if region_id == _selected_region:
				line_color = SELECTED_COLOR
				line_width = 4.0
			elif region_id == _hovered_region:
				line_color = HOVER_COLOR
				line_width = 3.0
			draw_polyline(outline, line_color, line_width, true)

			var center := (points[0] + points[2]) * 0.5
			var label := _region_label(region_id)
			var text_position := Vector2(center.x - 100.0, center.y + font_size * 0.35)
			draw_string(
				font,
				text_position + Vector2(1.0, 1.0),
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				200.0,
				font_size,
				LABEL_SHADOW
			)
			draw_string(
				font,
				text_position,
				label,
				HORIZONTAL_ALIGNMENT_CENTER,
				200.0,
				font_size,
				LABEL_COLOR
			)


func _region_points(region_id: Vector2i) -> PackedVector2Array:
	var regions: RegionSystem = _game_state.regions
	var origin := regions.get_region_origin(region_id)
	var size := regions.get_region_size(region_id)
	if size.x <= 0 or size.y <= 0:
		return PackedVector2Array()

	var top := _world.cell_to_world(origin) + Vector2(0.0, -TILE_HEIGHT * 0.5)
	var right := _world.cell_to_world(origin + Vector2i(size.x - 1, 0)) + Vector2(TILE_WIDTH * 0.5, 0.0)
	var bottom := _world.cell_to_world(origin + size - Vector2i.ONE) + Vector2(0.0, TILE_HEIGHT * 0.5)
	var left := _world.cell_to_world(origin + Vector2i(0, size.y - 1)) + Vector2(-TILE_WIDTH * 0.5, 0.0)

	return PackedVector2Array([
		to_local(top),
		to_local(right),
		to_local(bottom),
		to_local(left),
	])


func _region_label(region_id: Vector2i) -> String:
	var stats := _game_state.regions.get_region_stats(
		region_id,
		_game_state.buildings.instances,
		_game_state.buildings.definitions,
		_game_state.grid
	)
	var label: String = String(stats.get("code", "?"))
	var building_count := int(stats.get("building_count", 0))
	if building_count > 0:
		label += "  %d" % building_count
	return label
