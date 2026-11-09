class_name MechCrowdNavigation
extends RefCounted
## Godot 内置 RVO2 求解器的适配器，不含本地转向/分离求解器。
## 来源：https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html

## 一批 agent 的避障速度全部就绪时发出；velocities 为 {entity_id: Vector2}。
signal velocities_ready(request_id: int, velocities: Dictionary)

## 邻居搜索距离（格）。
const NEIGHBOR_DISTANCE: float = 1.5
## 参与避障计算的最大邻居数。
const MAX_NEIGHBORS: int = 16
## 与其他 agent 的避让预测时窗（秒）。
const AGENT_HORIZON: float = 0.4
## 与障碍物的避让预测时窗（秒）。
const OBSTACLE_HORIZON: float = 0.3

var _map: RID
## entity_id 到 agent RID 的映射。
var _agents: Dictionary[int, RID] = {}
## 地图四周边界的障碍 RID，仅在换网格或地形变化时重建。
var _obstacles: Array[RID] = []
## 上次同步的网格版本号，用于增量同步。
var _grid_revision: int = -1
var _terrain_revision: int = -1
var _source_grid: MechGridState
## 每行的障碍 RID 列表（同行相邻阻挡格合并为一个矩形），支持按脏行重建。
var _row_obstacles: Dictionary[int, Array] = {}
## 当前请求代号；自增后旧请求的回调一律作废。
var _request_id: int = 0
## 本批尚未回调的 entity_id 集合。
var _pending: Dictionary[int, bool] = {}
## 本批已回调收集到的速度结果。
var _velocities: Dictionary[int, Vector2] = {}
## 友军可穿越模式：被网格标记为可穿越的占用者不再阻挡寻路与障碍同步。
var _friendly_pass: bool = false


func set_friendly_pass(enabled: bool) -> void:
	_friendly_pass = enabled


## 为一批实体求解避障速度：同步障碍与 agent 状态后交给 RVO 计算。
## preferred 中没有期望速度的实体会被暂停，rvo_speed 不大于 0 的实体直接跳过；
## 结果经 velocities_ready 信号整批返回。返回请求 id，无待处理实体时返回 0。
func request(entities: Array[MechEntityState], preferred: Dictionary[int, Vector2], grid: MechGridState) -> int:
	cancel_pending()
	if not _map.is_valid():
		_map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(_map, true)
	_sync_obstacles(grid)
	var present: Dictionary[int, bool] = {}
	for entity: MechEntityState in entities:
		if entity.rvo_speed <= 0.0:
			continue
		var id: int = entity.entity_id
		present[id] = true
		if not _agents.has(id):
			_agents[id] = _create_agent()
		var agent: RID = _agents[id]
		NavigationServer2D.agent_set_position(agent, entity.position)
		var paused: bool = not preferred.has(id)
		NavigationServer2D.agent_set_paused(agent, paused)
		if paused:
			continue
		var speed: float = entity.rvo_speed / grid.movement_weight(Vector2i(entity.position.floor()))
		NavigationServer2D.agent_set_max_speed(agent, speed)
		# 原生优先级让静止单位给移动单位让路，同时不打乱自身次序。
		NavigationServer2D.agent_set_avoidance_priority(agent, 0.5 if entity.has_move_order else 0.2)
		NavigationServer2D.agent_set_velocity(agent, preferred[id])
		NavigationServer2D.agent_set_avoidance_callback(agent, _on_velocity.bind(id, _request_id))
		_pending[id] = true
	for id: int in _agents.keys():
		if not present.has(id):
			remove(id)
	return _request_id if not _pending.is_empty() else 0


## 作废所有在途回调并清空批量结果；请求代号自增使旧回调失效。
func cancel_pending() -> void:
	_request_id += 1
	_pending.clear()
	_velocities.clear()
	for agent: RID in _agents.values():
		NavigationServer2D.agent_set_avoidance_callback(agent, Callable())


## 停用 RVO 地图求解（配合模拟暂停），先作废在途请求。
func suspend() -> void:
	cancel_pending()
	if _map.is_valid():
		NavigationServer2D.map_set_active(_map, false)


## 释放指定实体的 agent 及其相关状态。
func remove(id: int) -> void:
	if not _agents.has(id):
		return
	NavigationServer2D.agent_set_avoidance_callback(_agents[id], Callable())
	NavigationServer2D.free_rid(_agents[id])
	_agents.erase(id)
	_pending.erase(id)
	_velocities.erase(id)


## 瞬移实体到新位置并强制清零速度，避免旧速度残留影响避障。
func teleport(id: int, position: Vector2) -> void:
	if _agents.has(id):
		NavigationServer2D.agent_set_position(_agents[id], position)
		# 强制设速仅用于瞬移，常规逐 tick 更新绝不使用。
		NavigationServer2D.agent_set_velocity_forced(_agents[id], Vector2.ZERO)


## 释放全部 agent、障碍与地图，并重置增量同步游标。
func dispose() -> void:
	# 释放地图本身已会将其移除；若在 free_rid 前紧接排队 map_set_active，
	# 可能残留一条指向已释放地图的延迟命令。
	cancel_pending()
	for id: int in _agents.keys():
		remove(id)
	_clear_obstacles()
	if _map.is_valid():
		NavigationServer2D.free_rid(_map)
		_map = RID()
	_grid_revision = -1
	_terrain_revision = -1
	_source_grid = null


## 创建一个按类常量配置的 RVO agent；半径取 MechGridState.MOBILE_RADIUS。
func _create_agent() -> RID:
	var agent: RID = NavigationServer2D.agent_create()
	NavigationServer2D.agent_set_map(agent, _map)
	NavigationServer2D.agent_set_radius(agent, MechGridState.MOBILE_RADIUS)
	NavigationServer2D.agent_set_neighbor_distance(agent, NEIGHBOR_DISTANCE)
	NavigationServer2D.agent_set_max_neighbors(agent, MAX_NEIGHBORS)
	NavigationServer2D.agent_set_time_horizon_agents(agent, AGENT_HORIZON)
	NavigationServer2D.agent_set_time_horizon_obstacles(agent, OBSTACLE_HORIZON)
	NavigationServer2D.agent_set_avoidance_layers(agent, 1)
	NavigationServer2D.agent_set_avoidance_mask(agent, 1)
	NavigationServer2D.agent_set_avoidance_enabled(agent, true)
	return agent


## 单个 agent 的避障回调；过期请求或已完成的实体直接丢弃。
func _on_velocity(velocity: Vector2, id: int, request_id: int) -> void:
	if request_id != _request_id or not _pending.has(id):
		return
	_pending.erase(id)
	_velocities[id] = velocity
	if _pending.is_empty():
		var result: Dictionary = _velocities.duplicate()
		_velocities.clear()
		# 全部回调到齐后统一提交整批结果，与回调先后顺序无关。
		velocities_ready.emit(request_id, result)


## 把网格阻挡同步为 RVO 障碍：同一网格只重建脏行，换网格或地形版本变化时清空后全量重建。
func _sync_obstacles(grid: MechGridState) -> void:
	if _source_grid == grid and _grid_revision == grid.revision():
		return
	if _source_grid != grid or _terrain_revision != grid.terrain_revision():
		_clear_obstacles()
		for y: int in range(grid.dimensions().y):
			_sync_row(y, grid)
		# 边界障碍 RID 在普通的放置/拆除更新中保留复用。
		var size := Vector2(grid.dimensions())
		_obstacles.append(_add_obstacle(Rect2(Vector2(-1, -1), Vector2(size.x + 2, 1))))
		_obstacles.append(_add_obstacle(Rect2(Vector2(-1, size.y), Vector2(size.x + 2, 1))))
		_obstacles.append(_add_obstacle(Rect2(Vector2(-1, 0), Vector2(1, size.y))))
		_obstacles.append(_add_obstacle(Rect2(Vector2(size.x, 0), Vector2(1, size.y))))
	else:
		var dirty_rows: Dictionary[int, bool] = {}
		for cell: Vector2i in grid.navigation_changes_since(_grid_revision):
			dirty_rows[cell.y] = true
		for y: int in dirty_rows:
			_sync_row(y, grid)
	_grid_revision = grid.revision()
	_terrain_revision = grid.terrain_revision()
	_source_grid = grid


## 重建指定行的障碍。
func _sync_row(y: int, grid: MechGridState) -> void:
	for obstacle: RID in _row_obstacles.get(y, []):
		NavigationServer2D.free_rid(obstacle)
	var row: Array[RID] = []
	# 保持既有的同行阻挡格合并为矩形障碍的策略，只重建受影响的行。
	var x: int = 0
	while x < grid.dimensions().x:
		if grid.is_walkable(Vector2i(x, y), true, {}, _friendly_pass):
			x += 1
			continue
		var start: int = x
		while x < grid.dimensions().x and not grid.is_walkable(Vector2i(x, y), true, {}, _friendly_pass):
			x += 1
		row.append(_add_obstacle(Rect2(Vector2(start, y), Vector2(x - start, 1))))
	_row_obstacles[y] = row


## 以矩形区域创建一个 RVO 障碍并挂到当前地图。
func _add_obstacle(area: Rect2) -> RID:
	var obstacle: RID = NavigationServer2D.obstacle_create()
	var vertices := PackedVector2Array([Vector2.ZERO, Vector2(area.size.x, 0), area.size, Vector2(0, area.size.y)])
	# NavigationServer 要求逆时针绕序，才能把 agent 推向多边形外侧。
	if Geometry2D.is_polygon_clockwise(vertices):
		vertices.reverse()
	NavigationServer2D.obstacle_set_map(obstacle, _map)
	NavigationServer2D.obstacle_set_position(obstacle, area.position)
	NavigationServer2D.obstacle_set_vertices(obstacle, vertices)
	NavigationServer2D.obstacle_set_avoidance_layers(obstacle, 1)
	NavigationServer2D.obstacle_set_avoidance_enabled(obstacle, true)
	return obstacle


func _clear_obstacles() -> void:
	for row: Array in _row_obstacles.values():
		for obstacle: RID in row:
			NavigationServer2D.free_rid(obstacle)
	_row_obstacles.clear()
	for obstacle: RID in _obstacles:
		NavigationServer2D.free_rid(obstacle)
	_obstacles.clear()
