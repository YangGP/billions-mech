extends SceneTree
## Run: godot --headless --path . --script validation/vision_checks.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("VISION CHECK FAILED: " + label)


func _run() -> void:
	_check_fields()
	_check_combat()
	_check_distant_decisions()
	await _check_session()
	await process_frame
	print("[vision] %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_fields() -> void:
	var map := MechMapDefinition.new()
	map.dimensions = Vector2i(32, 32)
	map.obstacle_rects = [Rect2i(10, 0, 1, 32), Rect2i(6, 5, 1, 1)]
	map.rough_rects = [Rect2i(5, 8, 1, 1)]
	var grid := MechGridState.new()
	grid.configure(map)
	grid.set_core_coverage(Vector2i(25, 25), Vector2i.ONE, 2)
	var registry := MechEntityRegistry.new()
	var units := MechUnitSystem.new()
	var rules := MechUnitDefinition.new()
	var id: int = units.create(registry, rules, Vector2i(4, 8))
	var vision := MechVisionSystem.new()
	vision.reset(grid)
	vision.update(grid, registry, [], 7.0)
	_check(vision.state_at(Vector2i(25, 25)) == MechVisionSystem.State.EXPLORED, "coverage explores without live sight")
	_check(vision.state_at(Vector2i(5, 8)) == MechVisionSystem.State.VISIBLE, "rough terrain does not block")
	_check(vision.state_at(Vector2i(10, 8)) == MechVisionSystem.State.VISIBLE, "first obstacle face is revealed")
	_check(not vision.is_visible(Vector2(11.5, 8.5)), "rock blocks cells behind it")
	_check(vision.state_at(Vector2i(31, 0)) == MechVisionSystem.State.UNEXPLORED, "distant terrain starts unknown")
	_check(not grid.terrain_line_clear(Vector2(5.5, 5.5), Vector2(6.5, 6.5), true), "no diagonal crack leakage")
	_check(not grid.terrain_line_clear(Vector2(4.5, 8.5), Vector2(10.5, 8.5)), "combat cannot shoot the blocking terrain")
	var revision: int = vision.snapshot()["revision"]
	registry.teleport(id, Vector2(4.8, 8.7))
	_check(not vision.update(grid, registry, [], 7.0), "subtile movement reuses LOS")
	_check(vision.snapshot()["revision"] == revision, "unchanged sight keeps texture revision")
	_check(grid.try_occupy(999, Vector2i(7, 8), Vector2i.ONE)["ok"], "place sight-neutral building")
	vision.update(grid, registry, [], 7.0)
	_check(vision.is_visible(Vector2(9.5, 8.5)), "buildings do not block sight")
	registry.teleport(id, Vector2(24.5, 8.5))
	vision.update(grid, registry, [], 7.0)
	_check(vision.state_at(Vector2i(4, 8)) == MechVisionSystem.State.EXPLORED, "departed sight becomes memory")
	grid.set_core_coverage(Vector2i.ZERO, Vector2i.ONE, -1)
	vision.update(grid, registry, [], 7.0)
	_check(vision.state_at(Vector2i(25, 25)) == MechVisionSystem.State.EXPLORED, "losing coverage never erases exploration")
	var second: int = units.create(registry, rules, Vector2i(23, 8))
	vision.update(grid, registry, [], 7.0)
	registry.remove(id)
	vision.update(grid, registry, [], 7.0)
	_check(vision.is_visible(Vector2(24.5, 8.5)), "overlapping sight survives source removal")
	registry.remove(second)
	vision.update(grid, registry, [], 7.0)
	_check(not vision.is_visible(Vector2(24.5, 8.5)), "last source removal clears live sight")
	var tower_rules: MechBuildingDefinition = load("res://content/buildings/sentry_tower.tres")
	_check(tower_rules.sight_radius == 10.0, "tower resource sight is loaded")
	var tower := MechBuildingState.new()
	tower.configure(100, tower_rules, Vector2i(20, 20), 30)
	vision.update(grid, registry, [tower], 7.0)
	_check(not vision.is_visible(Vector2(21, 21)), "construction provides no sight")
	tower.phase = MechBuildingState.Phase.OPERATING
	vision.update(grid, registry, [tower], 7.0)
	_check(vision.is_visible(Vector2(21, 21)), "completed powered tower provides sight")
	tower.powered = false
	vision.update(grid, registry, [tower], 7.0)
	_check(not vision.is_visible(Vector2(21, 21)), "unpowered tower loses sight")
	vision.reset(grid)
	_check(vision.state_at(Vector2i(25, 25)) == MechVisionSystem.State.UNEXPLORED, "session reset discards old exploration")
	_check(vision.state_at(Vector2i(-1, 0)) == MechVisionSystem.State.UNEXPLORED, "out of bounds query is safe")
	registry.clear()


func _check_combat() -> void:
	var map := MechMapDefinition.new()
	map.dimensions = Vector2i(32, 32)
	map.obstacle_rects = [Rect2i(10, 0, 1, 32)]
	var grid := MechGridState.new()
	grid.configure(map)
	var registry := MechEntityRegistry.new()
	var tower_rules: MechBuildingDefinition = load("res://content/buildings/sentry_tower.tres")
	var tower := MechBuildingState.new()
	tower.configure(100, tower_rules, Vector2i(7, 7), 30, true)
	var enemies := MechEnemySystem.new()
	var enemy_rules: MechEnemyDefinition = load("res://content/enemies/builder.tres")
	var blocked: int = enemies.create(registry, enemy_rules, Vector2(11.5, 8.5))
	var units := MechUnitSystem.new()
	units.create(registry, MechUnitDefinition.new(), Vector2i(12, 8))
	var vision := MechVisionSystem.new()
	vision.reset(grid)
	vision.update(grid, registry, [tower], 7.0)
	var towers := MechTowerSystem.new()
	_check(vision.is_visible(registry.position_of(blocked)), "ally on far side contributes shared sight")
	_check(towers.advance(registry, [tower], 30, grid, vision).is_empty(), "shared sight cannot fire through rock")
	var clear: int = enemies.create(registry, enemy_rules, Vector2(8.5, 12.5))
	var hits: Array[Dictionary] = towers.advance(registry, [tower], 30, grid, vision)
	_check(hits.size() == 1 and hits[0]["id"] == clear, "tower fires at visible unobstructed enemy")
	vision.reset(grid)
	tower.attack_cooldown_ticks = 0
	_check(towers.advance(registry, [tower], 30, grid, vision).is_empty(), "tower cannot acquire a hidden nearby enemy")
	var navigation := MechGridNavigation.new()
	navigation.rebuild(grid)
	var hp: int = registry.get_entity(blocked).hp
	units.advance(registry, grid, navigation, 30, vision)
	_check(registry.get_entity(blocked).hp == hp, "units cannot auto-acquire hidden nearby enemies")
	registry.clear()


func _check_distant_decisions() -> void:
	var map := MechMapDefinition.new()
	map.dimensions = Vector2i(64, 64)
	var grid := MechGridState.new()
	grid.configure(map)
	var registry := MechEntityRegistry.new()
	var navigation := MechGridNavigation.new()
	navigation.rebuild(grid)
	var vision := MechVisionSystem.new()
	vision.reset(grid)
	var enemies := MechEnemySystem.new()
	enemies.reset(grid, Vector2i(2, 2), [])
	var rules: MechEnemyDefinition = load("res://content/enemies/wanderer.tres")
	var id: int = enemies.create(registry, rules, Vector2(50.5, 50.5))
	var enemy: MechEntityState = registry.get_entity(id)
	enemies._tick_counter = 3
	var noises: Array[Dictionary] = [{"position": Vector2(45.5, 50.5), "radius": 24.0}]
	enemies.advance(registry, grid, navigation, [], 30, noises, vision)
	_check(enemy.repath_ticks == 240 and enemy.has_move_order, "distant hidden enemy uses longer path refresh")
	var position: Vector2 = enemy.position
	var cooldown: int = enemy.repath_ticks
	enemies.advance(registry, grid, navigation, [], 30, noises, vision)
	_check(enemy.position.distance_to(position) > 0.0 and enemy.position.distance_to(position) <= rules.move_speed / 30.0 + 0.001, "skipped decisions preserve normal movement steps")
	_check(enemy.repath_ticks == cooldown - 1, "coarse decisions do not slow cooldown time")
	registry.create(&"probe", "scout", enemy.position)
	vision.update(grid, registry, [], 7.0)
	noises[0]["position"] = Vector2(43.5, 50.5)
	enemies.advance(registry, grid, navigation, [], 30, noises, vision)
	_check(not enemy.fog_coarse and enemy.repath_ticks == 60, "re-entering live sight restores normal path refresh immediately")
	vision.reset(grid)
	var units := MechUnitSystem.new()
	units.create(registry, MechUnitDefinition.new(), Vector2i(49, 50))
	enemies._tick_counter = 4
	enemies.advance(registry, grid, navigation, [], 30, noises, vision)
	_check(enemy.order == &"engaged", "hidden enemy near player assets keeps full perception cadence")
	registry.clear()


func _check_session() -> void:
	var settings: MechFoundationSettings = load("res://content/foundation.tres").duplicate(true)
	var map := MechMapDefinition.new()
	map.dimensions = Vector2i(32, 32)
	map.mainbrain_origin = Vector2i(2, 2)
	map.probe_cell = Vector2i(6, 6)
	map.main_gate = Vector2i(20, 4)
	map.flank = Vector2i(20, 20)
	var deposit := MechMineralDefinition.new()
	deposit.mineral_id = &"hidden_ore"
	deposit.cell = Vector2i(28, 29)
	map.minerals = [deposit]
	settings.map_definition = map
	settings.threat_enabled = false
	settings.starting_unit_cells = [Vector2i(8, 8)]
	var sim := MechSimCore.new()
	_check(sim.configure(settings), "configure integrated fog session")
	_check(sim._construction.definition(&"mainbrain").sight_radius == 12.0, "mainbrain sight is loaded")
	var unit: MechEntityState
	for entity: MechEntityState in sim._registry.all():
		if entity.unit_definition != null:
			unit = entity
	var enemy_id: int = sim._enemies.create(sim._registry, settings.enemy_definitions[0], Vector2(12.5, 8.5))
	var attack := MechCommand.new(MechCommand.Type.ISSUE_UNIT_ORDER, {"ids": [unit.entity_id], "kind": &"attack", "goal": Vector2(12.5, 8.5), "target_id": enemy_id})
	_check(sim.execute_command(attack)["ok"], "visible target accepts direct attack")
	sim._registry.teleport(enemy_id, Vector2(28.5, 28.5))
	_check(not sim.validate_command(attack)["ok"], "hidden entity ID cannot bypass command validation")
	var state: Dictionary = sim.snapshot()
	var leaked: bool = false
	for entity: Dictionary in state["entities"]:
		leaked = leaked or entity["id"] == enemy_id
	_check(not leaked, "hidden enemy is absent from presentation snapshot")
	_check(state["minerals"].is_empty(), "unknown minerals absent from presentation snapshot")
	var info: Dictionary = sim.inspect_cell(Vector2i(28, 29))
	_check(info["terrain_name"] == "未探索" and not info.has("mineral") and not info.has("terrain"), "unknown cell inspection hides terrain and deposits")
	_check(sim.preview_build(&"armored_wall", Vector2i(28, 29))["reason"] == "该区域尚未探索", "construction preview cannot probe unknown terrain")
	sim._units.advance(sim._registry, sim._grid, sim._navigation, sim.tick_rate(), sim._vision)
	_check(unit.attack_target_id == 0 and unit.order_goal == Vector2(12.5, 8.5), "lost target does not track hidden movement")
	sim.execute_command(MechCommand.new(MechCommand.Type.SET_PAUSED, {"paused": true}))
	var before: Dictionary = sim.snapshot()
	sim.advance_one_tick()
	_check(sim.snapshot()["vision"] == before["vision"] and sim.snapshot()["clock"] == before["clock"], "pause freezes clock and fog")
	sim._registry.teleport(sim._probe_id, Vector2(28.5, 28.5))
	sim._on_movement_finished()
	_check(sim.snapshot()["minerals"].size() == 1, "native movement completion reveals remote deposit")
	var shown: bool = false
	for entity: Dictionary in sim.snapshot()["entities"]:
		shown = shown or entity["id"] == enemy_id
	_check(shown, "scout reveals an enemy again")
	sim._registry.teleport(sim._probe_id, Vector2(6.5, 6.5))
	sim._on_movement_finished()
	_check(sim.inspect_cell(Vector2i(28, 29))["vision"] == MechVisionSystem.State.EXPLORED, "returning scout leaves gray memory")
	sim._threat._active = true
	sim._infect_asset(Vector4i(20, 0, 0, 0), Vector2(28.5, 28.5))
	_check(sim.snapshot()["alert"].get("text", "").contains("感疫脉冲"), "unseen infection provides a qualitative direction alert")
	sim.execute_command(MechCommand.new(MechCommand.Type.RESET_SESSION))
	_check(sim.snapshot()["alert"].is_empty(), "restart clears old alerts")
	_check(sim.inspect_cell(Vector2i(28, 29))["vision"] == MechVisionSystem.State.UNEXPLORED, "restart rebuilds initial fog")
	sim.configure(load("res://content/training.tres"))
	_check(sim.inspect_cell(Vector2i(28, 29))["vision"] == MechVisionSystem.State.UNEXPLORED, "scenario switch discards previous exploration")
	sim.damage_building(sim._mainbrain_id, 99999)
	_check(sim.session_ended() and sim.snapshot()["vision"]["cells"].count(MechVisionSystem.State.VISIBLE) > 0, "defeat retains surviving scout sight")
	sim.shutdown()
	await physics_frame
	await process_frame
