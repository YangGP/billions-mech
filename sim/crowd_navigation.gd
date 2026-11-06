class_name MechCrowdNavigation
extends RefCounted
## Adapter to Godot's built-in RVO2 solver. No local steering/separation solver.
## Source: https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html

signal velocities_ready(request_id: int, velocities: Dictionary)

const NEIGHBOR_DISTANCE: float = 1.5
const MAX_NEIGHBORS: int = 16
const AGENT_HORIZON: float = 0.4
const OBSTACLE_HORIZON: float = 0.3

var _map: RID
var _agents: Dictionary[int, RID] = {}
var _obstacles: Array[RID] = []
var _grid_revision: int = -1
var _request_id: int = 0
var _pending: Dictionary[int, bool] = {}
var _velocities: Dictionary[int, Vector2] = {}


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
		# Native priority makes idle units yield while keeping their own order.
		NavigationServer2D.agent_set_avoidance_priority(agent, 0.5 if entity.has_move_order else 0.2)
		NavigationServer2D.agent_set_velocity(agent, preferred[id])
		NavigationServer2D.agent_set_avoidance_callback(agent, _on_velocity.bind(id, _request_id))
		_pending[id] = true
	for id: int in _agents.keys():
		if not present.has(id):
			remove(id)
	return _request_id if not _pending.is_empty() else 0


func cancel_pending() -> void:
	_request_id += 1
	_pending.clear()
	_velocities.clear()
	for agent: RID in _agents.values():
		NavigationServer2D.agent_set_avoidance_callback(agent, Callable())


func suspend() -> void:
	cancel_pending()
	if _map.is_valid():
		NavigationServer2D.map_set_active(_map, false)


func remove(id: int) -> void:
	if not _agents.has(id):
		return
	NavigationServer2D.agent_set_avoidance_callback(_agents[id], Callable())
	NavigationServer2D.free_rid(_agents[id])
	_agents.erase(id)
	_pending.erase(id)
	_velocities.erase(id)


func teleport(id: int, position: Vector2) -> void:
	if _agents.has(id):
		NavigationServer2D.agent_set_position(_agents[id], position)
		# Forced velocity is reserved for teleports, never normal per-tick updates.
		NavigationServer2D.agent_set_velocity_forced(_agents[id], Vector2.ZERO)


func dispose() -> void:
	suspend()
	for id: int in _agents.keys():
		remove(id)
	_clear_obstacles()
	if _map.is_valid():
		NavigationServer2D.free_rid(_map)
		_map = RID()
	_grid_revision = -1


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


func _on_velocity(velocity: Vector2, id: int, request_id: int) -> void:
	if request_id != _request_id or not _pending.has(id):
		return
	_pending.erase(id)
	_velocities[id] = velocity
	if _pending.is_empty():
		var result: Dictionary = _velocities.duplicate()
		_velocities.clear()
		# Commit one batch after all callbacks, independent of callback order.
		velocities_ready.emit(request_id, result)


func _sync_obstacles(grid: MechGridState) -> void:
	if _grid_revision == grid.revision():
		return
	_clear_obstacles()
	# Coalesce blocked cells into row rectangles; the native solver owns avoidance.
	for y: int in range(grid.dimensions().y):
		var x: int = 0
		while x < grid.dimensions().x:
			if grid.is_walkable(Vector2i(x, y)):
				x += 1
				continue
			var start: int = x
			while x < grid.dimensions().x and not grid.is_walkable(Vector2i(x, y)):
				x += 1
			_add_obstacle(Rect2(Vector2(start, y), Vector2(x - start, 1)))
	# The map boundary also constrains agents displaced by avoidance.
	var size := Vector2(grid.dimensions())
	_add_obstacle(Rect2(Vector2(-1, -1), Vector2(size.x + 2, 1)))
	_add_obstacle(Rect2(Vector2(-1, size.y), Vector2(size.x + 2, 1)))
	_add_obstacle(Rect2(Vector2(-1, 0), Vector2(1, size.y)))
	_add_obstacle(Rect2(Vector2(size.x, 0), Vector2(1, size.y)))
	_grid_revision = grid.revision()


func _add_obstacle(area: Rect2) -> void:
	var obstacle: RID = NavigationServer2D.obstacle_create()
	var vertices := PackedVector2Array([Vector2.ZERO, Vector2(area.size.x, 0), area.size, Vector2(0, area.size.y)])
	# NavigationServer requires counterclockwise winding to push agents outside.
	if Geometry2D.is_polygon_clockwise(vertices):
		vertices.reverse()
	NavigationServer2D.obstacle_set_map(obstacle, _map)
	NavigationServer2D.obstacle_set_position(obstacle, area.position)
	NavigationServer2D.obstacle_set_vertices(obstacle, vertices)
	NavigationServer2D.obstacle_set_avoidance_layers(obstacle, 1)
	NavigationServer2D.obstacle_set_avoidance_enabled(obstacle, true)
	_obstacles.append(obstacle)


func _clear_obstacles() -> void:
	for obstacle: RID in _obstacles:
		NavigationServer2D.free_rid(obstacle)
	_obstacles.clear()
