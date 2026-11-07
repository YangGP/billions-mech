class_name RTSFormation
extends RefCounted
## Formation slot generators. All slots lie on the XZ plane (y = target.y) and face
## the direction of travel (from `from` to `target`).

## Near-square grid ("box") centred on target, rows perpendicular to travel.
static func box(from: Vector3, target: Vector3, count: int, spacing: float = 2.0) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	if count <= 0:
		return slots
	var cols: int = ceili(sqrt(float(count)))
	var rows: int = ceili(float(count) / cols)
	var fwd: Vector2 = _forward(from, target)
	var side: Vector2 = Vector2(fwd.y, -fwd.x)
	for i: int in count:
		var r: int = i / cols
		var c: int = i % cols
		var in_row: int = cols if r < rows - 1 else count - r * cols
		var off: Vector2 = side * (float(c) - float(in_row - 1) / 2.0) * spacing - fwd * (float(r) - float(rows - 1) / 2.0) * spacing
		slots.append(Vector3(target.x + off.x, target.y, target.z + off.y))
	return slots

## Single line perpendicular to travel.
static func line(from: Vector3, target: Vector3, count: int, spacing: float = 2.0) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var fwd: Vector2 = _forward(from, target)
	var side: Vector2 = Vector2(fwd.y, -fwd.x)
	for i: int in count:
		var off: Vector2 = side * (float(i) - float(count - 1) / 2.0) * spacing
		slots.append(Vector3(target.x + off.x, target.y, target.z + off.y))
	return slots

## Pairs units to slots greedily by distance so paths cross as little as possible.
## Returns an Array of slot indices, one per unit position.
static func assign(unit_positions: Array[Vector3], slots: Array[Vector3]) -> Array[int]:
	var result: Array[int] = []
	result.resize(unit_positions.size())
	result.fill(-1)
	var free: Array[int] = []
	for i: int in slots.size():
		free.append(i)
	var order: Array[int] = []
	for i: int in unit_positions.size():
		order.append(i)
	for u: int in order:
		var best: int = -1
		var best_d: float = INF
		for s: int in free:
			var d: float = unit_positions[u].distance_squared_to(slots[s])
			if d < best_d:
				best_d = d
				best = s
		if best >= 0:
			result[u] = best
			free.erase(best)
	return result

static func _forward(from: Vector3, target: Vector3) -> Vector2:
	var d: Vector2 = Vector2(target.x - from.x, target.z - from.z)
	return Vector2(0, -1) if d.length_squared() < 0.0001 else d.normalized()
