class_name MechThreatSystem
extends RefCounted
## Wanderer population (values.md §15): TAB-style stationary scatter outside the
## mainbrain's initial coverage on reset, plus slow edge backfill. Noise-driven
## convergence arrives with the tower/infection batch; until then wanderers only
## react to being seen or attacked (vision scan and provocation live in
## MechEnemySystem).

const CELLS_PER_WANDERER: int = 100
const BACKFILL_SECONDS: float = 60.0

var _active: bool = false
var _wanderer: MechEnemyDefinition
var _pending_scatter: Array[Vector2] = []
var _edge_cells: Array[Vector2] = []
var _backfill_ticks: int = 0
var _backfill_interval: int = 1800


func configure(definitions: Array[MechEnemyDefinition]) -> String:
	_wanderer = null
	for rules: MechEnemyDefinition in definitions:
		if rules == null:
			continue
		if rules.enemy_id == &"wanderer":
			_wanderer = rules
	if _wanderer == null:
		return "缺少游荡敌定义"
	return ""


func reset(grid: MechGridState, active: bool, hz: int) -> void:
	_active = active
	_backfill_ticks = 0
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


func advance() -> Array[Dictionary]:
	if not _active or _wanderer == null:
		return []
	var requests: Array[Dictionary] = []
	if not _pending_scatter.is_empty():
		var scatter: Array[Vector2] = _pending_scatter.duplicate()
		_pending_scatter.clear()
		for position: Vector2 in scatter:
			requests.append({"enemy_id": _wanderer.enemy_id, "position": position})
		return requests
	_backfill_ticks += 1
	if _backfill_ticks < _backfill_interval or _edge_cells.is_empty():
		return []
	_backfill_ticks = 0
	requests.append({"enemy_id": _wanderer.enemy_id, "position": _edge_cells[randi() % _edge_cells.size()]})
	return requests
