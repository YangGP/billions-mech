class_name MechIsoGeometry
extends RefCounted
## 等距投影是表现层关注点；模拟使用正方形逻辑格。

## 参考截图的网格斜率约为 ±37 度（3:4）。
const HALF_TILE := Vector2(32.0, 24.0)
## 纵横比（用于计算菱形地面的高度）。
const GROUND_RATIO: float = HALF_TILE.y / HALF_TILE.x


## 逻辑坐标 → 等距屏幕坐标。
static func project(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * HALF_TILE.x, (point.x + point.y) * HALF_TILE.y)


## 等距屏幕坐标 → 逻辑坐标。
static func unproject(point: Vector2) -> Vector2:
	return Vector2((point.x / HALF_TILE.x + point.y / HALF_TILE.y) * 0.5,
		(point.y / HALF_TILE.y - point.x / HALF_TILE.x) * 0.5)


## 屏幕坐标所在的逻辑格。
static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(unproject(point).floor())


## 逻辑格中心点的等距屏幕坐标。
static func cell_center(cell: Vector2i) -> Vector2:
	return project(Vector2(cell) + Vector2(0.5, 0.5))


## 建筑脚印（origin + 尺寸）的等距菱形多边形。
static func footprint_polygon(origin: Vector2i, footprint: Vector2i) -> PackedVector2Array:
	var start := Vector2(origin)
	return PackedVector2Array([project(start), project(start + Vector2(footprint.x, 0)),
		project(start + Vector2(footprint)), project(start + Vector2(0, footprint.y))])


static func project_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(project(point))
	return result


## 地图的等距包围盒；优先用真实轮廓计算，否则按尺寸估算。
static func map_bounds(dimensions: Vector2i, outline: PackedVector2Array = PackedVector2Array()) -> Rect2:
	if not outline.is_empty():
		var bounds := Rect2(project(outline[0]), Vector2.ZERO)
		for point: Vector2 in outline:
			bounds = bounds.expand(project(point))
		return bounds
	return Rect2(Vector2(-dimensions.y * HALF_TILE.x, 0.0),
		Vector2((dimensions.x + dimensions.y) * HALF_TILE.x, (dimensions.x + dimensions.y) * HALF_TILE.y))
