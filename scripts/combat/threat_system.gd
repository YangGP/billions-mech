class_name ThreatSystem
extends Node
## 威胁与防守切片：波次、敌人、核心生命、防御塔。
##
## 只操作 BuildingSystem 的公开伤害接口，不直接修改资源或占地。
## 敌人从地图下边缘直线接近核心；遇到建筑就停下攻击，因此围墙可以挡住它们。
## 没有寻路：这是刻意的切片简化，用来先验证“建造—防守—失败”是否有压力。

signal enemy_spawned(enemy: EnemyState)
signal enemy_removed(enemy: EnemyState)
signal core_hp_changed(current: int, maximum: int)
signal wave_changed(next_wave: int, seconds_to_next: float, enemies_alive: int, in_wave: bool)
signal tower_fired(from: Vector2, to: Vector2)
signal wave_cleared(wave_number: int)
signal defeat()

const FIRST_WAVE_DELAY: float = 40.0
const WAVE_INTERVAL: float = 50.0
const SPAWN_INTERVAL: float = 0.6
const BASE_ENEMY_COUNT: int = 6
const ENEMY_COUNT_PER_WAVE: int = 3
const BASE_ENEMY_HP: int = 40
const ENEMY_HP_PER_WAVE: int = 6
const ENEMY_DAMAGE: int = 4
const ENEMY_ATTACK_INTERVAL: float = 1.0
const ENEMY_SPEED: float = 90.0
const SPAWN_CELLS: Array[Vector2i] = [
	Vector2i(8, 31),
	Vector2i(16, 31),
	Vector2i(24, 31),
]

var enemies: Array[EnemyState] = []
var core_hp: int = 0
var core_max_hp: int = 0
var current_wave: int = 0
var in_wave: bool = false
var next_wave_timer: float = FIRST_WAVE_DELAY
var defeated: bool = false

var _game_state: GameState
var _world: World
var _core_id: StringName = &""
var _core_position: Vector2 = Vector2.ZERO
var _spawn_remaining: int = 0
var _spawn_timer: float = 0.0
var _next_enemy_id: int = 1
var _tower_timers: Dictionary = {}
var _last_wave_second: int = -1
var _last_wave_state: int = -1
var _last_enemy_count: int = -1


func setup(game_state: GameState, world: World) -> void:
	_game_state = game_state
	_world = world

	var core := game_state.buildings.get_core_instance()
	if core == null:
		push_warning("威胁系统：找不到核心建筑，波次不会启动")
		return

	_core_id = core.instance_id
	core_hp = core.hp
	core_max_hp = maxi(1, core.hp)
	_core_position = world.get_footprint_anchor(core.origin_cell, core.footprint)
	next_wave_timer = FIRST_WAVE_DELAY

	game_state.buildings.building_damaged.connect(_on_building_damaged)
	game_state.buildings.building_removed.connect(_on_building_removed)

	core_hp_changed.emit(core_hp, core_max_hp)
	_emit_wave_state(true)


func _process(delta: float) -> void:
	if _game_state == null or defeated:
		return

	var clock := _game_state.clock
	if clock.paused:
		return

	var scaled_delta := delta * clock.speed
	if in_wave:
		_update_spawning(scaled_delta)
		_update_enemies(scaled_delta)
		_update_towers(scaled_delta)
		_remove_dead_enemies()
		if _spawn_remaining <= 0 and enemies.is_empty():
			_finish_wave()
	else:
		next_wave_timer = maxf(0.0, next_wave_timer - scaled_delta)
		if next_wave_timer <= 0.0:
			_start_wave()

	_emit_wave_state(false)


## 测试与调试入口：立即开始下一波。
func start_wave() -> void:
	if defeated or in_wave or _game_state == null:
		return
	next_wave_timer = 0.0
	_start_wave()
	_emit_wave_state(true)


func get_wave_snapshot() -> Dictionary:
	return {
		"wave": current_wave if in_wave else current_wave + 1,
		"seconds": 0.0 if in_wave else next_wave_timer,
		"alive": enemies.size(),
		"in_wave": in_wave,
	}


func _start_wave() -> void:
	in_wave = true
	current_wave += 1
	_spawn_remaining = BASE_ENEMY_COUNT + (current_wave - 1) * ENEMY_COUNT_PER_WAVE
	_spawn_timer = 0.0
	_emit_wave_state(true)


func _update_spawning(scaled_delta: float) -> void:
	if _spawn_remaining <= 0:
		return

	_spawn_timer -= scaled_delta
	while _spawn_timer <= 0.0 and _spawn_remaining > 0:
		_spawn_enemy()
		_spawn_timer += SPAWN_INTERVAL


func _spawn_enemy() -> void:
	var spawn_cell: Vector2i = SPAWN_CELLS[randi() % SPAWN_CELLS.size()]
	var enemy := EnemyState.new()
	enemy.enemy_id = _next_enemy_id
	_next_enemy_id += 1
	enemy.position = (
		_world.cell_to_world(spawn_cell)
		+ Vector2(randf_range(-24.0, 24.0), randf_range(-12.0, 12.0))
	)
	enemy.max_hp = BASE_ENEMY_HP + (current_wave - 1) * ENEMY_HP_PER_WAVE
	enemy.hp = enemy.max_hp
	enemy.speed = ENEMY_SPEED
	enemy.damage = ENEMY_DAMAGE
	enemy.attack_interval = ENEMY_ATTACK_INTERVAL
	enemy.attack_timer = 0.0

	enemies.append(enemy)
	_spawn_remaining -= 1
	enemy_spawned.emit(enemy)


func _update_enemies(scaled_delta: float) -> void:
	for enemy in enemies:
		if enemy.hp <= 0:
			continue

		if (
			enemy.target_instance_id != &""
			and not _game_state.buildings.instances.has(enemy.target_instance_id)
		):
			enemy.target_instance_id = &""
			enemy.attack_timer = 0.0

		if enemy.target_instance_id != &"":
			_attack_target(enemy, scaled_delta)
		else:
			_move_enemy(enemy, scaled_delta)


func _move_enemy(enemy: EnemyState, scaled_delta: float) -> void:
	var to_core := _core_position - enemy.position
	if to_core.length() < 2.0:
		enemy.target_instance_id = _core_id
		enemy.attack_timer = 0.0
		return

	var next_position := enemy.position + to_core.normalized() * enemy.speed * scaled_delta
	var cell := _world.world_to_cell(next_position)
	var occupant: StringName = _game_state.grid.get_occupant(cell)

	if occupant != &"":
		enemy.target_instance_id = occupant
		enemy.attack_timer = 0.0
	else:
		enemy.position = next_position


func _attack_target(enemy: EnemyState, scaled_delta: float) -> void:
	enemy.attack_timer -= scaled_delta
	if enemy.attack_timer > 0.0:
		return
	enemy.attack_timer += enemy.attack_interval
	_game_state.buildings.damage_building(enemy.target_instance_id, enemy.damage)


func _update_towers(scaled_delta: float) -> void:
	for instance in _game_state.buildings.instances.values():
		var building: BuildingInstance = instance
		var definition: BuildingDefinition = _game_state.buildings.definitions.get(
			building.definition_id
		)
		if definition == null or definition.attack_damage <= 0 or definition.attack_range <= 0.0:
			continue
		if not building.operating:
			continue

		var cooldown: float = float(_tower_timers.get(building.instance_id, 0.0)) - scaled_delta
		var target := _find_tower_target(building, definition.attack_range)
		if target != null and cooldown <= 0.0:
			cooldown = maxf(0.1, definition.attack_interval)
			target.hp = maxi(0, target.hp - definition.attack_damage)
			var from := _world.cell_to_world(building.origin_cell) + Vector2(0.0, -40.0)
			tower_fired.emit(from, target.position)

		_tower_timers[building.instance_id] = maxf(0.0, cooldown)


func _find_tower_target(building: BuildingInstance, attack_range: float) -> EnemyState:
	var best: EnemyState = null
	var best_distance := INF
	var tower_cell := building.origin_cell

	for enemy in enemies:
		if enemy.hp <= 0:
			continue
		var enemy_cell := _world.world_to_cell(enemy.position)
		var distance := Vector2(enemy_cell - tower_cell).length()
		if distance <= attack_range and distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _remove_dead_enemies() -> void:
	if enemies.is_empty():
		return

	var alive: Array[EnemyState] = []
	for enemy in enemies:
		if enemy.hp > 0:
			alive.append(enemy)
		else:
			enemy_removed.emit(enemy)
	enemies = alive


func _finish_wave() -> void:
	in_wave = false
	next_wave_timer = WAVE_INTERVAL
	wave_cleared.emit(current_wave)
	_emit_wave_state(true)


func _on_building_damaged(instance: BuildingInstance, _amount: int) -> void:
	if instance.instance_id != _core_id:
		return
	core_hp = maxi(0, instance.hp)
	core_hp_changed.emit(core_hp, core_max_hp)


func _on_building_removed(instance: BuildingInstance) -> void:
	if instance.instance_id == _core_id:
		_defeat()


func _defeat() -> void:
	if defeated:
		return
	defeated = true
	in_wave = false
	_game_state.clock.set_paused(true)
	defeat.emit()


func _emit_wave_state(force: bool) -> void:
	var display_wave := current_wave if in_wave else current_wave + 1
	var seconds := 0.0 if in_wave else next_wave_timer
	var alive := enemies.size()
	var state := 1 if in_wave else 0
	var second_int := int(ceil(seconds))

	if (
		force
		or state != _last_wave_state
		or second_int != _last_wave_second
		or alive != _last_enemy_count
	):
		_last_wave_state = state
		_last_wave_second = second_int
		_last_enemy_count = alive
		wave_changed.emit(display_wave, seconds, alive, in_wave)
