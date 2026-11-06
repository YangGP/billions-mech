class_name MechWaveDirector
extends RefCounted
## Wave scheduling per waves-enemies.md §2–§6 and values.md §2/§12: silence or
## development triggers the first wave, budget B(n) = first × growth^(n-1),
## announcements carry a qualitative tier plus a coarse edge direction. TAB-style
## release: each wave streams in from the edge band (outside the player's view)
## across a release window, entries ordered and staggered evenly. Composition is
## act-one: builders fill the budget, one prototype joins from WAVE 3. Spawns are
## returned as requests; MechEnemySystem owns entity creation.

const NODE_ID: StringName = &"compute_node"
const PROTOTYPE_FROM_WAVE: int = 3

var _active: bool = false
var _tick_rate: int = 30
var _defs: Dictionary = {}
var _main_band: Array[Vector2i] = []
var _flank_band: Array[Vector2i] = []
var _main_edge: StringName = &"north"
var _flank_edge: StringName = &"east"
var _phase: StringName = &"silence"
var _wave_index: int = 0
var _tick_counter: int = 0
var _silence_ticks: int = 18000
var _announce_delay_ticks: int = 900
var _wave_interval_ticks: int = 18000
var _release_window_ticks: int = 9000
var _first_wave_budget: float = 25.0
var _budget_growth: float = 1.6
var _development_nodes: int = 8
var _flank_every: int = 4
var _tier_label: String = ""
var _edge: StringName = &""
var _edge_name: String = ""
var _pending: Array[Dictionary] = []


func configure(settings: MechFoundationSettings) -> String:
	_defs.clear()
	for rules: MechEnemyDefinition in settings.enemy_definitions:
		if rules == null:
			return "空敌种定义"
		var error: String = rules.validation_error()
		if not error.is_empty():
			return error
		if _defs.has(rules.enemy_id):
			return "重复敌种编号"
		_defs[rules.enemy_id] = rules
	if not _defs.has(&"builder") or not _defs.has(&"prototype"):
		return "缺少建造者或原型机定义"
	_silence_ticks = maxi(1, ceili(settings.silence_seconds * settings.simulation_hz))
	_announce_delay_ticks = maxi(1, ceili(settings.wave_announce_seconds * settings.simulation_hz))
	_wave_interval_ticks = maxi(1, ceili(settings.wave_interval_seconds * settings.simulation_hz))
	_release_window_ticks = maxi(1, ceili(settings.wave_release_seconds * settings.simulation_hz))
	_first_wave_budget = maxf(1.0, settings.first_wave_budget)
	_budget_growth = maxf(1.0, settings.wave_budget_growth)
	_development_nodes = maxi(1, settings.development_node_threshold)
	_flank_every = maxi(2, settings.flank_wave_interval)
	return ""


func reset(grid: MechGridState, map_definition: MechMapDefinition, active: bool, hz: int) -> void:
	_active = active
	_tick_rate = maxi(1, hz)
	_phase = &"silence"
	_wave_index = 0
	_tick_counter = 0
	_tier_label = ""
	_edge = &""
	_edge_name = ""
	_pending.clear()
	_collect_bands(grid, map_definition)


func advance(grid: MechGridState, buildings: Array[MechBuildingState]) -> Array[Dictionary]:
	if not _active or grid == null:
		return []
	_tick_counter += 1
	var requests: Array[Dictionary] = []
	# Streaming release drains first, independent of the phase clock below.
	if not _pending.is_empty():
		var remaining: Array[Dictionary] = []
		for entry: Dictionary in _pending:
			entry["delay"] = int(entry["delay"]) - 1
			if entry["delay"] <= 0:
				requests.append({"enemy_id": entry["enemy_id"], "position": entry["position"]})
			else:
				remaining.append(entry)
		_pending = remaining
	match _phase:
		&"silence":
			if _tick_counter >= _silence_ticks or _operating_nodes(buildings) >= _development_nodes:
				_announce()
		&"announced":
			if _tick_counter >= _announce_delay_ticks:
				_queue_wave()
		&"active":
			if _tick_counter >= _wave_interval_ticks:
				_announce()
	return requests


func state() -> Dictionary:
	return {"active": _active, "phase": _phase, "wave_index": _wave_index,
		"edge": _edge, "edge_name": _edge_name, "tier": _tier_label}


func _announce() -> void:
	# The upcoming wave number is the current index + 1 (values.md §12 curve).
	var wave_number: int = _wave_index + 1
	var budget: float = _first_wave_budget * pow(_budget_growth, wave_number - 1)
	_tier_label = "小股" if budget < 40.0 else ("常规" if budget < 80.0 else "大量")
	if wave_number % _flank_every == 0 and not _flank_band.is_empty():
		_edge = _flank_edge
		_edge_name = {"north": "北", "south": "南", "west": "西", "east": "东"}.get(String(_flank_edge), "侧翼")
	else:
		_edge = _main_edge
		_edge_name = {"north": "北", "south": "南", "west": "西", "east": "东"}.get(String(_main_edge), "正面")
	_phase = &"announced"
	_tick_counter = 0


func _queue_wave() -> void:
	var wave_number: int = _wave_index + 1
	var budget: float = _first_wave_budget * pow(_budget_growth, wave_number - 1)
	var builder: MechEnemyDefinition = _defs[&"builder"]
	var band: Array[Vector2i] = _flank_band if wave_number % _flank_every == 0 and not _flank_band.is_empty() else _main_band
	if band.is_empty():
		band = _main_band
	# Composition: prototype first from WAVE 3, builders fill the remaining budget.
	var entries: Array[StringName] = []
	if wave_number >= PROTOTYPE_FROM_WAVE:
		entries.append(&"prototype")
		budget -= _defs[&"prototype"].threat_cost
	var builders: int = maxi(0, floori(budget / builder.threat_cost))
	for index: int in range(builders):
		entries.append(&"builder")
	# TAB-style trickle: entries stream from the band across the release window,
	# first entry due immediately, the rest staggered evenly after it.
	var spacing: float = float(_release_window_ticks) / maxi(1, entries.size() - 1) if entries.size() > 1 else float(_release_window_ticks)
	for index: int in range(entries.size()):
		var cell: Vector2i = band[index % band.size()]
		var rules: MechEnemyDefinition = _defs[entries[index]]
		_pending.append({"enemy_id": rules.enemy_id,
			"position": Vector2(cell) + Vector2(0.5, 0.5),
			"delay": floori(spacing * index)})
	_wave_index = wave_number
	_phase = &"active"
	_tick_counter = 0


func _operating_nodes(buildings: Array[MechBuildingState]) -> int:
	var count: int = 0
	for building: MechBuildingState in buildings:
		if building.definition.building_id == NODE_ID and building.phase == MechBuildingState.Phase.OPERATING:
			count += 1
	return count


## Edge spawn bands: walkable border-ring cells grouped by side; the band nearest
## the map's main-gate marker is the default, the one nearest the flank marker
## carries the minority of waves (map-terrain.md §2/§5).
func _collect_bands(grid: MechGridState, map_definition: MechMapDefinition) -> void:
	var sides: Dictionary = {}
	for cell: Vector2i in _border_ring(grid.dimensions()):
		if grid.terrain_at(cell) == MechGridState.Terrain.OBSTACLE:
			continue
		var side: StringName = &"north"
		if cell.y == 0:
			side = &"north"
		elif cell.y == grid.dimensions().y - 1:
			side = &"south"
		elif cell.x == 0:
			side = &"west"
		else:
			side = &"east"
		if not sides.has(side):
			sides[side] = [] as Array[Vector2i]
		(sides[side] as Array[Vector2i]).append(cell)
	_main_band = _nearest_band(sides, map_definition.main_gate)
	_main_edge = _nearest_side(sides, map_definition.main_gate)
	_flank_band = _nearest_band(sides, map_definition.flank)
	_flank_edge = _nearest_side(sides, map_definition.flank)


func _border_ring(dimensions: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(dimensions.x):
		cells.append(Vector2i(x, 0))
		cells.append(Vector2i(x, dimensions.y - 1))
	for y: int in range(1, dimensions.y - 1):
		cells.append(Vector2i(0, y))
		cells.append(Vector2i(dimensions.x - 1, y))
	return cells


func _nearest_band(sides: Dictionary, marker: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var best: float = INF
	for side: StringName in sides:
		for cell: Vector2i in sides[side]:
			var distance: float = cell.distance_squared_to(marker)
			if distance < best:
				best = distance
				result = sides[side]
	return result


func _nearest_side(sides: Dictionary, marker: Vector2i) -> StringName:
	var result: StringName = &""
	var best: float = INF
	for side: StringName in sides:
		for cell: Vector2i in sides[side]:
			var distance: float = cell.distance_squared_to(marker)
			if distance < best:
				best = distance
				result = side
	return result
