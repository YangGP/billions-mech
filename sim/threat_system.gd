class_name MechThreatSystem
extends RefCounted
## Wanderer population, noise events and infection conversion (values.md
## §13–§15). Wanderers: TAB-style stationary scatter outside core coverage,
## slow edge backfill, and noise-driven convergence ("闻声缓慢聚拢", leave the
## source and they linger where they stopped). Infection: assets with positive
## capacity destroyed by enemies spawn builders at the wreck (act-one
## composition) and emit a combat-level pulse. Noise is an event list, not a
## shared field: a few dozen live events at most, each wanderer walks its own
## A* route, keeping the march field core-only (architecture.md §5).

const CELLS_PER_WANDERER: int = 100
const BACKFILL_SECONDS: float = 60.0
const COMBAT_NOISE_SECONDS: float = 3.0
const CONSTRUCTION_NOISE_SECONDS: float = 5.0
const OPERATION_NOISE_SECONDS: float = 5.0
const OPERATION_EVERY_TICKS: int = 150

var _active: bool = false
var _wanderer: MechEnemyDefinition
var _builder: MechEnemyDefinition
var _pending_scatter: Array[Vector2] = []
var _edge_cells: Array[Vector2] = []
var _backfill_ticks: int = 0
var _backfill_interval: int = 1800
var _tick_counter: int = 0
var _noises: Array[Dictionary] = []
var _radius_combat: float = 24.0
var _radius_construction: float = 12.0
var _radius_operation: float = 6.0
var _infection_divisor: float = 20.0
var _tick_rate: int = 30


func configure(definitions: Array[MechEnemyDefinition], settings: MechFoundationSettings) -> String:
	_wanderer = null
	_builder = null
	for rules: MechEnemyDefinition in definitions:
		if rules == null:
			continue
		if rules.enemy_id == &"wanderer":
			_wanderer = rules
		elif rules.enemy_id == &"builder":
			_builder = rules
	if _wanderer == null:
		return "缺少游荡敌定义"
	if _builder == null:
		return "缺少建造者定义（感疫产出）"
	_radius_combat = maxf(1.0, settings.noise_radius_combat)
	_radius_construction = maxf(1.0, settings.noise_radius_construction)
	_radius_operation = maxf(1.0, settings.noise_radius_operation)
	_infection_divisor = maxf(1.0, settings.infection_value_divisor)
	_tick_rate = maxi(1, settings.simulation_hz)
	return ""


func reset(grid: MechGridState, active: bool, hz: int) -> void:
	_active = active
	_backfill_ticks = 0
	_tick_counter = 0
	_noises.clear()
	_backfill_interval = maxi(1, ceili(BACKFILL_SECONDS * hz))
	_pending_scatter.clear()
	_edge_cells.clear()
	if not _active or _wanderer == null:
		return
	# Scatter positions: walkable cells outside the initial core coverage, taken in
	# shuffled order at 1 wanderer per CELLS_PER_WANDERER eligible cells.
	var eligible: Array[Vector2] = []
	for y: int in range(grid.dimensions().y):
		for x: int in range(grid.dimensions().x):
			var cell := Vector2i(x, y)
			if grid.terrain_at(cell) != MechGridState.Terrain.OBSTACLE and not grid.is_covered(cell):
				eligible.append(Vector2(cell) + Vector2(0.5, 0.5))
	eligible.shuffle()
	var count: int = eligible.size() / CELLS_PER_WANDERER
	for index: int in range(mini(count, eligible.size())):
		_pending_scatter.append(eligible[index])
	for y: int in range(grid.dimensions().y):
		for x: int in range(grid.dimensions().x):
			var cell := Vector2i(x, y)
			if (cell.x == 0 or cell.y == 0 or cell.x == grid.dimensions().x - 1 or cell.y == grid.dimensions().y - 1) and grid.terrain_at(cell) != MechGridState.Terrain.OBSTACLE:
				_edge_cells.append(Vector2(cell) + Vector2(0.5, 0.5))


func advance(buildings: Array[MechBuildingState]) -> Array[Dictionary]:
	if not _active:
		return []
	_tick_counter += 1
	_decay_noises()
	for building: MechBuildingState in buildings:
		# Operating facilities keep a weak continuous hum, staggered per building.
		if building.operating() and (_tick_counter + building.entity_id) % OPERATION_EVERY_TICKS == 0:
			note_operation(Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5)
	var requests: Array[Dictionary] = []
	if not _pending_scatter.is_empty():
		var scatter: Array[Vector2] = _pending_scatter.duplicate()
		_pending_scatter.clear()
		for position: Vector2 in scatter:
			requests.append({"enemy_id": _wanderer.enemy_id, "position": position})
		return requests
	_backfill_ticks += 1
	if _backfill_ticks < _backfill_interval or _edge_cells.is_empty():
		return requests
	_backfill_ticks = 0
	requests.append({"enemy_id": _wanderer.enemy_id, "position": _edge_cells[randi() % _edge_cells.size()]})
	return requests


## Live noise events; consumers treat the dictionaries as read-only.
func noises() -> Array[Dictionary]:
	return _noises


## 感疫转化 (waves-enemies.md §8.1, values.md §14): wreck value → builders at
## the wreck, plus one combat-level pulse. Act-one composition is builders only;
## act two/three mixing lands with those acts.
func infect(cost: Vector4i, position: Vector2) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	if not _active or _builder == null or not MechResources.valid(cost):
		return requests
	note_combat(position)
	var worth: int = cost.x + cost.y * 2 + cost.z * 3 + cost.w * 10
	var count: int = maxi(1, floori(float(worth) / _infection_divisor))
	for index: int in range(count):
		requests.append({"enemy_id": _builder.enemy_id, "position": position})
	return requests


func note_combat(position: Vector2) -> void:
	_emit(position, _radius_combat, COMBAT_NOISE_SECONDS)


func note_construction(position: Vector2) -> void:
	_emit(position, _radius_construction, CONSTRUCTION_NOISE_SECONDS)


func note_operation(position: Vector2) -> void:
	_emit(position, _radius_operation, OPERATION_NOISE_SECONDS)


func _emit(position: Vector2, radius: float, seconds: float) -> void:
	if not _active:
		return
	_noises.append({"position": position, "radius": radius, "remaining": maxi(1, ceili(seconds * _tick_rate))})


func _decay_noises() -> void:
	var alive: Array[Dictionary] = []
	for noise: Dictionary in _noises:
		noise["remaining"] = int(noise["remaining"]) - 1
		if noise["remaining"] > 0:
			alive.append(noise)
	_noises = alive
