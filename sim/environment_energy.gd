class_name MechEnvironmentEnergy
extends RefCounted
## Wind/solar collection-area scoring and same-type reservations. Scoring only
## reads map terrain and explored state; it never reads live enemy/unit state.

const EXTENSION: int = 3
const WIND_CAP: int = 18
const SOLAR_CAP: int = 20

## energy_type -> {cell: entity_id}
var _reserved: Dictionary[StringName, Dictionary] = {}


func clear() -> void:
	_reserved.clear()


func collection_bounds(origin: Vector2i, footprint: Vector2i) -> Rect2i:
	return Rect2i(origin - Vector2i(EXTENSION, EXTENSION), footprint + Vector2i(EXTENSION * 2, EXTENSION * 2))


func conflicts(energy_type: StringName, origin: Vector2i, footprint: Vector2i, ignore_id: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if energy_type == &"" or energy_type == &"none":
		return result
	var occupied: Dictionary = _reserved.get(energy_type, {})
	var bounds: Rect2i = collection_bounds(origin, footprint)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var owner: int = int(occupied.get(Vector2i(x, y), 0))
			if owner != 0 and owner != ignore_id:
				result.append(Vector2i(x, y))
	return result


func reserve(entity_id: int, energy_type: StringName, origin: Vector2i, footprint: Vector2i) -> bool:
	if energy_type == &"" or energy_type == &"none":
		return true
	if not conflicts(energy_type, origin, footprint, entity_id).is_empty():
		return false
	var occupied: Dictionary = _reserved.get(energy_type, {})
	var bounds: Rect2i = collection_bounds(origin, footprint)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			occupied[Vector2i(x, y)] = entity_id
	_reserved[energy_type] = occupied
	return true


func release(entity_id: int) -> void:
	for energy_type: StringName in _reserved.keys():
		var occupied: Dictionary = _reserved[energy_type]
		for cell: Vector2i in occupied.keys():
			if int(occupied[cell]) == entity_id:
				occupied.erase(cell)
		if occupied.is_empty():
			_reserved.erase(energy_type)
		else:
			_reserved[energy_type] = occupied


func score(energy_type: StringName, origin: Vector2i, footprint: Vector2i, grid: MechGridState, vision: MechVisionSystem) -> int:
	if energy_type == &"" or energy_type == &"none" or grid == null or vision == null:
		return 0
	var points: int = 0
	var body := Rect2i(origin, footprint)
	var bounds: Rect2i = collection_bounds(origin, footprint)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if not grid.contains(cell) or body.has_point(cell):
				continue
			if vision.state_at(cell) == MechVisionSystem.State.UNEXPLORED:
				continue
			var terrain: int = grid.terrain_at(cell)
			if terrain == MechGridState.Terrain.OBSTACLE:
				continue
			if energy_type == &"wind":
				# Explicit wind cells and rough terrain are the high-value cells;
				# never add both for the same cell.
				points += 2 if grid.is_wind(cell) or terrain == MechGridState.Terrain.ROUGH else 1
			elif energy_type == &"solar":
				if terrain == MechGridState.Terrain.OPEN:
					points += 1
	if energy_type == &"wind":
		return mini(WIND_CAP, points / 4)
	if energy_type == &"solar":
		return mini(SOLAR_CAP, points / 2)
	return 0
