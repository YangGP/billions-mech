class_name MechCoverageView
extends Node2D
## 缓存的供电覆盖只读模型。建造模式之外隐藏。

var _map: Dictionary = {}


## 接收覆盖快照并请求重绘。
func present_map(map_state: Dictionary) -> void:
	_map = map_state.duplicate(true)
	queue_redraw()


func _draw() -> void:
	if _map.is_empty():
		return
	var dimensions: Vector2i = _map["dimensions"]
	var mask: PackedByteArray = _map["coverage"]
	var neighbors: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			var cell := Vector2i(x, y)
			if mask[y * dimensions.x + x] == 0:
				continue
			var polygon: PackedVector2Array = MechIsoGeometry.footprint_polygon(cell, Vector2i.ONE)
			draw_colored_polygon(polygon, Color(0.3, 0.93, 0.72, 0.07))
			for index: int in range(4):
				var neighbor: Vector2i = cell + neighbors[index]
				if not Rect2i(Vector2i.ZERO, dimensions).has_point(neighbor) or mask[neighbor.y * dimensions.x + neighbor.x] == 0:
					draw_line(polygon[index], polygon[(index + 1) % 4], Color("72e9d0"), 2.0, true)
