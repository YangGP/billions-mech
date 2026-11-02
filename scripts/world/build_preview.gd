class_name BuildPreview
extends Node2D
## 建造预览：半透明建筑贴图 + 占地菱形描边。
## 只表现，不写入任何数据；合法性由 BuildingSystem 计算后传入。

const TILE_WIDTH: float = 128.0
const TILE_HEIGHT: float = 64.0

@onready var footprint: Polygon2D = $Footprint
@onready var outline: Line2D = $Outline
@onready var ghost: Sprite2D = $Ghost

var _definition: BuildingDefinition


func _ready() -> void:
	visible = false


func show_preview(
	definition: BuildingDefinition,
	_origin: Vector2i,
	anchor: Vector2,
	valid: bool
) -> void:
	_definition = definition
	position = anchor
	visible = true
	_update_ghost(valid)
	_update_footprint(definition.footprint, valid)


func hide_preview() -> void:
	visible = false


func _update_ghost(valid: bool) -> void:
	if _definition == null or _definition.texture == null:
		ghost.visible = false
		return

	ghost.visible = true
	ghost.texture = _definition.texture
	ghost.centered = false
	ghost.scale = Vector2.ONE * _definition.sprite_scale

	var scaled_size := Vector2(
		_definition.texture.get_width(), _definition.texture.get_height()
	) * _definition.sprite_scale
	ghost.position = Vector2(-scaled_size.x * 0.5, -scaled_size.y) + _definition.sprite_offset
	ghost.modulate = (
		Color(0.55, 1.0, 0.55, 0.6) if valid else Color(1.0, 0.35, 0.35, 0.6)
	)


func _update_footprint(size_cells: Vector2i, valid: bool) -> void:
	var size := Vector2(size_cells)
	var points := PackedVector2Array([
		Vector2((size.y - size.x) * TILE_WIDTH * 0.5, -(size.x + size.y) * TILE_HEIGHT * 0.5),
		Vector2(size.y * TILE_WIDTH * 0.5, -size.y * TILE_HEIGHT * 0.5),
		Vector2.ZERO,
		Vector2(-size.x * TILE_WIDTH * 0.5, -size.x * TILE_HEIGHT * 0.5),
	])

	footprint.polygon = points
	footprint.color = (
		Color(0.3, 1.0, 0.35, 0.22) if valid else Color(1.0, 0.25, 0.2, 0.25)
	)

	var closed := points.duplicate()
	closed.append(points[0])
	outline.points = closed
	outline.default_color = (
		Color(0.5, 1.0, 0.5, 0.9) if valid else Color(1.0, 0.4, 0.3, 0.9)
	)
