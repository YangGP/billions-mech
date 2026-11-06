class_name MechIsoGeometry
extends RefCounted
## Projection is a presentation concern; sim uses square logical cells.

const HALF_TILE := Vector2(32.0, 16.0)


static func project(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * HALF_TILE.x, (point.x + point.y) * HALF_TILE.y)


static func unproject(point: Vector2) -> Vector2:
	return Vector2((point.x / HALF_TILE.x + point.y / HALF_TILE.y) * 0.5,
		(point.y / HALF_TILE.y - point.x / HALF_TILE.x) * 0.5)


static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(unproject(point).floor())


static func cell_center(cell: Vector2i) -> Vector2:
	return project(Vector2(cell) + Vector2(0.5, 0.5))


static func footprint_polygon(origin: Vector2i, footprint: Vector2i) -> PackedVector2Array:
	var start := Vector2(origin)
	return PackedVector2Array([project(start), project(start + Vector2(footprint.x, 0)),
		project(start + Vector2(footprint)), project(start + Vector2(0, footprint.y))])


static func project_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(project(point))
	return result


static func map_bounds(dimensions: Vector2i, outline: PackedVector2Array = PackedVector2Array()) -> Rect2:
	if not outline.is_empty():
		var bounds := Rect2(project(outline[0]), Vector2.ZERO)
		for point: Vector2 in outline:
			bounds = bounds.expand(project(point))
		return bounds
	return Rect2(Vector2(-dimensions.y * HALF_TILE.x, 0.0),
		Vector2((dimensions.x + dimensions.y) * HALF_TILE.x, (dimensions.x + dimensions.y) * HALF_TILE.y))
