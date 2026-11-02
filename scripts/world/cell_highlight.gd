class_name CellHighlight
extends Node2D
## 鼠标悬停格高亮：在等距菱形上画半透明填充与描边。
## 只做表现，不参与任何建造合法性或占用判断。

@export var tile_size: Vector2i = Vector2i(128, 64)
@export var fill_color: Color = Color(1.0, 0.95, 0.6, 0.18)
@export var outline_color: Color = Color(1.0, 0.92, 0.45, 0.95)


func _ready() -> void:
	visible = false


func show_at(world_position: Vector2) -> void:
	position = world_position
	visible = true


func hide_highlight() -> void:
	visible = false


func _draw() -> void:
	var half := Vector2(tile_size) * 0.5
	var points := PackedVector2Array([
		Vector2(0.0, -half.y),
		Vector2(half.x, 0.0),
		Vector2(0.0, half.y),
		Vector2(-half.x, 0.0),
	])
	draw_colored_polygon(points, fill_color)

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, outline_color, 2.0, true)
