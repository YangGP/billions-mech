class_name MechThreatSystem
extends RefCounted
## 环境威胁：建造者游荡形态的种群、噪声事件与感疫转化（values.md §13–§15）。
## 游荡散兵与波次建造者共用同一敌种定义，仅由生成时的游荡标记决定行为：
## TAB 式散布在核心覆盖之外，平时原地挪动（见 MechEnemySystem），
## 边缘缓慢补充，闻声缓慢聚拢。感疫：敌方摧毁有正容量价值的资产时，
## 在残骸处生成建造者（第一幕编成）并发一次战斗级脉冲。
## 噪声是事件列表而非共享场：同时存活的事件最多几十个，
## 每个游荡散兵各自走自己的 A* 路线，行军场保持核心专用（architecture.md §5）。

## 每多少个可走格分配一名游荡散兵。
const CELLS_PER_WANDERER: int = 100
## 边缘补充游荡散兵的间隔（秒）。
const BACKFILL_SECONDS: float = 60.0
## 各类噪声事件的存续时长（秒）。
const COMBAT_NOISE_SECONDS: float = 3.0
const CONSTRUCTION_NOISE_SECONDS: float = 5.0
const OPERATION_NOISE_SECONDS: float = 5.0
const MOVEMENT_NOISE_SECONDS: float = 2.5
## 运行噪声的发射间隔（秒），按建筑错峰。
const OPERATION_NOISE_INTERVAL_SECONDS: float = 5.0

var _active: bool = false
## 建造者定义：既是感疫产物，也是环境散兵；散兵在生成时标记为游荡形态。
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
var _radius_movement: float = 8.0
var _infection_divisor: float = 20.0
var _tick_rate: int = 30


## 从敌种定义表与全局设置装配参数；返回错误描述，空字符串表示成功。
func configure(definitions: Array[MechEnemyDefinition], settings: MechFoundationSettings) -> String:
	_builder = null
	for rules: MechEnemyDefinition in definitions:
		if rules == null:
			continue
		if rules.enemy_id == &"builder":
			_builder = rules
	if _builder == null:
		return "缺少建造者定义（游荡散兵与感疫产出共用）"
	_radius_combat = maxf(1.0, settings.noise_radius_combat)
	_radius_construction = maxf(1.0, settings.noise_radius_construction)
	_radius_operation = maxf(1.0, settings.noise_radius_operation)
	_radius_movement = maxf(1.0, settings.noise_radius_movement)
	_infection_divisor = maxf(1.0, settings.infection_value_divisor)
	_tick_rate = maxi(1, settings.simulation_hz)
	return ""


## 重置种群状态并预生成散布点：eligible 格洗牌后按密度取前 N 个。
func reset(grid: MechGridState, map_definition: MechMapDefinition, active: bool, hz: int) -> void:
	_active = active
	_backfill_ticks = 0
	_tick_counter = 0
	_noises.clear()
	_backfill_interval = maxi(1, ceili(BACKFILL_SECONDS * hz))
	_pending_scatter.clear()
	_edge_cells.clear()
	if not _active or _builder == null:
		return
	# 散布与补充都排除地图固定的基座安全半径，与电力覆盖无关；已有敌人仍可被噪声吸引过来。
	var eligible: Array[Vector2] = []
	for y: int in range(grid.dimensions().y):
		for x: int in range(grid.dimensions().x):
			var cell := Vector2i(x, y)
			if grid.is_walkable(cell) and not grid.is_covered(cell) and map_definition.wanderer_spawn_allowed(Vector2(cell) + Vector2(0.5, 0.5)):
				eligible.append(Vector2(cell) + Vector2(0.5, 0.5))
	eligible.shuffle()
	var count: int = eligible.size() / CELLS_PER_WANDERER
	for index: int in range(mini(count, eligible.size())):
		_pending_scatter.append(eligible[index])
	print("[Billions Mech] ambient spawn: ", _pending_scatter.size(), "; eligible cells=", eligible.size(), "; base exclusion=", map_definition.wanderer_exclusion_radius)
	for cell: Vector2i in grid.boundary_cells():
		var point := Vector2(cell) + Vector2(0.5, 0.5)
		if grid.is_walkable(cell) and map_definition.wanderer_spawn_allowed(point):
			_edge_cells.append(point)


## 推进一个 tick：衰减噪声、发射运行嗡鸣、投放初始散布或边缘补充；
## 返回本 tick 的敌人生成请求。
func advance(buildings: Array[MechBuildingState]) -> Array[Dictionary]:
	if not _active:
		return []
	_tick_counter += 1
	_decay_noises()
	var operation_ticks: int = maxi(1, ceili(OPERATION_NOISE_INTERVAL_SECONDS * _tick_rate))
	for building: MechBuildingState in buildings:
		# 运行中的设施保持微弱的持续嗡鸣，按建筑实体 ID 错峰发射。
		if building.operating() and (_tick_counter + building.entity_id) % operation_ticks == 0:
			note_operation(Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5)
	var requests: Array[Dictionary] = []
	if not _pending_scatter.is_empty():
		var scatter: Array[Vector2] = _pending_scatter.duplicate()
		_pending_scatter.clear()
		for position: Vector2 in scatter:
			requests.append({"enemy_id": _builder.enemy_id, "position": position, "wandering": true})
		return requests
	_backfill_ticks += 1
	if _backfill_ticks < _backfill_interval or _edge_cells.is_empty():
		return requests
	_backfill_ticks = 0
	requests.append({"enemy_id": _builder.enemy_id, "position": _edge_cells[randi() % _edge_cells.size()], "wandering": true})
	return requests


## 当前存活噪声事件列表；消费方应把字典视为只读。
func noises() -> Array[Dictionary]:
	return _noises


## 感疫转化（waves-enemies.md §8.1、values.md §14）：残骸价值折算为
## 在残骸处生成的建造者，并发一次战斗级脉冲。第一幕编成只有建造者；
## 二、三幕的混编随幕落地。
func infect(cost: Dictionary, position: Vector2) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	if not _active or _builder == null or not MechResources.valid(cost):
		return requests
	note_combat(position)
	var worth: int = MechResources.worth(cost)
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


## 玩家单位行军产生微弱的持续嗡鸣（TAB 式移动噪声）。
func note_movement(position: Vector2) -> void:
	_emit(position, _radius_movement, MOVEMENT_NOISE_SECONDS)


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
