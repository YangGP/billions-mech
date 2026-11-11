extends SceneTree
## 视野系统回归检查脚本。运行方式：godot --headless --path . --script validation/vision_checks.gd

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
	await _check_menu_flow()
	await _check_new_levels()
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
	var rules: MechEnemyDefinition = load("res://content/enemies/builder.tres")
	var id: int = enemies.create(registry, rules, Vector2(50.5, 50.5), true)
	var enemy: MechEntityState = registry.get_entity(id)
	enemies._tick_counter = 3
	var noises: Array[Dictionary] = [{"position": Vector2(45.5, 50.5), "radius": 24.0}]
	enemies.advance(registry, grid, navigation, [], 30, noises, vision)
	_check(enemy.repath_ticks == 240 and enemy.has_move_order, "distant hidden enemy uses longer path refresh")
	var position: Vector2 = enemy.position
	var cooldown: int = enemy.repath_ticks
	enemies.advance(registry, grid, navigation, [], 30, noises, vision)
	_check(enemy.position.distance_to(position) > 0.0 and enemy.position.distance_to(position) <= rules.move_speed * rules.wandering_speed_ratio / 30.0 + 0.001, "skipped decisions preserve normal movement steps")
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
	var settings: MechFoundationSettings = load("res://content/development_128.tres").duplicate(true)
	var map := MechMapDefinition.new()
	map.dimensions = Vector2i(32, 32)
	map.mainbrain_origin = Vector2i(2, 2)
	map.probe_cell = Vector2i(7, 7)
	map.main_gate = Vector2i(20, 4)
	map.flank = Vector2i(20, 20)
	var deposit := MechMineralDefinition.new()
	deposit.mineral_id = &"hidden_ore"
	deposit.cell = Vector2i(28, 29)
	map.minerals = [deposit]
	settings.map_definition = map
	settings.threat_enabled = false
	settings.starting_unit_cells = [Vector2i(8, 8)]
	settings.diagnostic_probe_enabled = true
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
	sim._registry.teleport(sim._probe_id, Vector2(7.5, 7.5))
	sim._on_movement_finished()
	_check(sim.inspect_cell(Vector2i(28, 29))["vision"] == MechVisionSystem.State.EXPLORED, "returning scout leaves gray memory")
	sim._threat._active = true
	sim._infect_asset(MechResources.single(&"coins", 20), Vector2(28.5, 28.5))
	_check(sim.snapshot()["alert"].get("text", "").contains("感疫脉冲"), "unseen infection provides a qualitative direction alert")
	sim.execute_command(MechCommand.new(MechCommand.Type.RESET_SESSION))
	_check(sim.snapshot()["alert"].is_empty(), "restart clears old alerts")
	_check(sim.inspect_cell(Vector2i(28, 29))["vision"] == MechVisionSystem.State.UNEXPLORED, "restart rebuilds initial fog")
	sim.configure(settings.duplicate(true))
	_check(sim.inspect_cell(Vector2i(28, 29))["vision"] == MechVisionSystem.State.UNEXPLORED, "scenario switch discards previous exploration")
	sim.damage_building(sim._mainbrain_id, 99999)
	_check(sim.session_ended() and sim.snapshot()["vision"]["cells"].count(MechVisionSystem.State.VISIBLE) > 0, "defeat retains surviving scout sight")
	sim.shutdown()
	await physics_frame
	await process_frame


func _check_menu_flow() -> void:
	_check(change_scene_to_file("res://scenes/main_menu.tscn") == OK, "main menu scene loads")
	await scene_changed
	var menu: Node = current_scene
	_check(menu.find_child("Home").visible and not menu.find_child("Levels").visible, "startup shows home without battlefield")
	await _capture_menu("main-menu")
	menu.find_child("Play").pressed.emit()
	_check(menu.find_child("Levels").visible and not menu.find_child("Home").visible, "play opens level selection")
	menu.find_child("Back").pressed.emit()
	menu.find_child("SettingsButton").pressed.emit()
	_check(menu.get_node("Settings").is_open() and not menu.get_node("Layout").visible, "menu settings hides underlying focus targets")
	await process_frame
	menu.get_node("Settings").close_requested.emit()
	_check(not menu.get_node("Settings").is_open() and menu.get_node("Layout").visible, "closing settings restores menu")
	await process_frame
	for campaign: bool in [false, true, false]:
		menu.find_child("Play").pressed.emit()
		var mode: OptionButton = menu.find_child("Mode")
		mode.select(1 if campaign else 0)
		mode.item_selected.emit(mode.selected)
		await _capture_menu("level-select-campaign" if campaign else "level-select-standard")
		menu.find_child("Start").pressed.emit()
		await scene_changed
		var battle: Node = current_scene
		var sim: MechSimCore = battle.get("_sim")
		if campaign:
			_check_square_boundary(battle)
		_check(sim._settings.campaign_mode == campaign, "selected mode reaches simulation: %s" % campaign)
		_check(not has_meta(&"mech_campaign_mode"), "launch selection is consumed")
		_check(not load("res://content/development_128.tres").campaign_mode, "launch does not mutate shared settings")
		battle.call("_restart")
		_check(sim._settings.campaign_mode == campaign and sim.snapshot()["clock"]["tick"] == 0, "restart retains mode and resets clock")
		battle.get_node("HUD/Root/System/MainMenu").pressed.emit()
		_check(sim.is_paused() and battle.get_node("MapCamera").input_blocked, "return confirmation pauses and blocks battlefield")
		battle.get_node("ReturnDialog").canceled.emit()
		_check(not sim.is_paused() and not battle.get_node("MapCamera").input_blocked, "cancel return resumes running session")
		battle.call("_toggle_pause")
		battle.call("_request_main_menu")
		battle.call("_cancel_return")
		_check(sim.is_paused(), "cancel return preserves previously paused session")
		sim.damage_building(sim._mainbrain_id, 99999)
		battle.get_node("HUD/Root/SessionResult/MainMenu").pressed.emit()
		battle.get_node("ReturnDialog").canceled.emit()
		_check(sim.session_ended() and sim.is_paused(), "cancel return after defeat does not resume simulation")
		battle.call("_request_main_menu")
		battle.get_node("ReturnDialog").confirmed.emit()
		await scene_changed
		menu = current_scene
		_check(menu.find_child("Home").visible and sim._registry.all().is_empty(), "return clears old simulation and shows home")
	_check(change_scene_to_file("res://scenes/main_menu.tscn") == OK, "menu can reload after repeated sessions")
	await scene_changed


func _capture_menu(filename: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture-menu") or DisplayServer.get_name() == "headless":
		return
	# 场景/可见性切换后等待布局与渲染队列都提交，再取实际画面。
	for frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	print("[menu capture] %s window=%s image=%s" % [filename, root.size, picture.get_size()])
	var error: Error = picture.save_png("res://validation/screens/%s.png" % filename)
	_check(error == OK, "native menu capture: " + filename)


func _check_new_levels() -> void:
	for index: int in [1, 2]:
		var menu: Node = current_scene
		menu.find_child("Play").pressed.emit()
		var choice: OptionButton = menu.find_child("MapChoice")
		choice.select(index)
		choice.item_selected.emit(index)
		var mode: OptionButton = menu.find_child("Mode")
		_check(mode.selected == 0 and mode.is_item_disabled(1), "new level keeps its authored wave schedule")
		await _capture_menu("level-select-coast" if index == 1 else "level-select-river")
		menu.find_child("Start").pressed.emit()
		await scene_changed
		var battle: Node = current_scene
		var sim: MechSimCore = battle.get("_sim")
		var map: MechMapDefinition = sim._settings.map_definition
		_check(map.map_id == (&"tutorial_coast_64" if index == 1 else &"validation_river_96"), "selected level reaches terrain and simulation")
		_check(not has_meta(&"mech_session_settings"), "selected settings are consumed")
		var edge_distance: float = INF
		for offset: Vector2 in [Vector2.ZERO, Vector2(5, 0), Vector2(5, 5), Vector2(0, 5)]:
			var corner: Vector2 = Vector2(map.mainbrain_origin) + offset
			for edge: int in range(4):
				edge_distance = minf(edge_distance, corner.distance_to(Geometry2D.get_closest_point_to_segment(corner, map.outline()[edge], map.outline()[(edge + 1) % 4])))
		_check(edge_distance <= 4, "new level base is near a map edge")
		_check(sim._settings.total_waves == (2 if index == 1 else 4), "new level uses authored victory wave count")
		_check(sim.map_snapshot()["dimensions"] == map.dimensions, "snapshot uses selected map dimensions")
		_check(sim._registry.get_entity(sim._mainbrain_id).position.floor() == Vector2(map.mainbrain_origin) + Vector2(2, 2), "mainbrain spawns at the authored edge base")
		var camera: MechMapCamera3D = battle.get_node("MapCamera")
		camera.focus_mainbrain()
		var brain_screen: Vector2 = camera.map_to_screen(Vector2(map.mainbrain_origin) + Vector2(2.5, 2.5))
		_check(battle.get_node("HUD").battle_view_rect().has_point(brain_screen), "edge mainbrain stays visible above HUD with square camera limits")
		_check_square_boundary(battle)
		var safe_edges: bool = true
		for cell: Vector2i in sim._grid.boundary_cells():
			if sim._grid.is_walkable(cell) and not map.wanderer_spawn_allowed(Vector2(cell) + Vector2(0.5, 0.5)):
				safe_edges = false
		_check(safe_edges, "reachable spawn edges stay outside the base safety radius")
		var mining_origin: Vector2i = Vector2i(11, 42) if index == 1 else Vector2i(109, 72)
		var solar_origin: Vector2i = Vector2i(10, 38) if index == 1 else Vector2i(111, 64)
		var node_origin: Vector2i = Vector2i(19, 47) if index == 1 else Vector2i(109, 69)
		for placement: Dictionary in [{"id": &"mining_station", "origin": mining_origin}, {"id": &"solar_station", "origin": solar_origin}, {"id": &"compute_node", "origin": node_origin}]:
			var preview: Dictionary = sim.preview_build(placement["id"], placement["origin"])
			_check(preview["ok"], "initial economic placement %s: %s" % [placement["id"], preview["reason"]])
		battle.call("_toggle_pause")
		await _capture_menu("coast-start" if index == 1 else "river-start")
		battle.call("_restart")
		_check(sim._settings.map_definition.map_id == map.map_id and sim.snapshot()["clock"]["tick"] == 0, "restart retains selected map and resets its session")
		if OS.get_cmdline_user_args().has("--level-smoke"):
			for frame: int in range(600):
				await process_frame
			_check(not sim.session_ended() and sim.snapshot()["clock"]["tick"] > 0, "new level runs 600 engine frames")
		battle.call("_request_main_menu")
		battle.get_node("ReturnDialog").confirmed.emit()
		await scene_changed
	for scene: String in ["res://scenes/tutorial_coast_overview.tscn", "res://scenes/validation_river_overview.tscn"]:
		_check(change_scene_to_file(scene) == OK, "native level overview loads")
		await scene_changed
		await _capture_menu("coast-overview" if scene.contains("coast") else "river-overview")


func _check_square_boundary(battle: Node) -> void:
	var sim: MechSimCore = battle.get("_sim")
	var map: MechMapDefinition = sim._settings.map_definition
	var camera: MechMapCamera3D = battle.get_node("MapCamera")
	var bounds: Rect2 = MechIsoGeometry.map_bounds(map.dimensions, map.outline())
	_check(is_equal_approx(bounds.size.x, bounds.size.y), "logical slanted outline projects to a square")
	var screen_bounds := Rect2(camera.map_to_screen(map.outline()[0]), Vector2.ZERO)
	for corner: Vector2 in map.outline():
		screen_bounds = screen_bounds.expand(camera.map_to_screen(corner))
	_check(absf(screen_bounds.size.x - screen_bounds.size.y) < 0.1, "native Camera3D projection is square")
	var clipped_cell: Vector2i = Vector2i(map.outline()[0])
	_check(not sim._grid.contains(clipped_cell) and not sim._grid.preview_footprint(clipped_cell, Vector2i(2, 2))["ok"], "partial border cells reject building footprints")
	var before: Dictionary = sim.snapshot()["economy"]["resources"].duplicate()
	var denied: Dictionary = sim.execute_command(MechCommand.new(MechCommand.Type.PLACE_BUILDING, {"building_id": &"compute_node", "origin": Vector2i.ZERO}))
	_check(not denied["ok"] and before == sim.snapshot()["economy"]["resources"], "outside square construction rejects without payment")
	for entity: MechEntityState in sim._registry.all():
		if entity.unit_definition != null and entity.team == 1:
			var move: Dictionary = sim.validate_command(MechCommand.new(MechCommand.Type.MOVE_ENTITY, {"entity_id": entity.entity_id, "target": Vector2(0.5, 0.5)}))
			_check(not move["ok"], "outside square movement target rejects")
			break
	var paths: Dictionary = {&"development_basin_128": "development-map-128", &"tutorial_coast_64": "tutorial-maps/coast", &"validation_river_96": "tutorial-maps/river"}
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://validation/%s/layout-report.json" % paths[map.map_id]))
	_check(map.playable_cells().count(1) == int(report["playable_cells"]), "compiled full-cell mask matches native polygon containment")
	var original_area: float = {&"development_basin_128": 16384.0, &"tutorial_coast_64": 4096.0, &"validation_river_96": 7680.0}[map.map_id]
	var native_area: float = 0.0
	for triangle: int in [1, 2]:
		native_area += absf((map.outline()[triangle] - map.outline()[0]).cross(map.outline()[triangle + 1] - map.outline()[0])) * 0.5
	_check(absf(native_area - original_area) < 0.02 and absf(float(report["geometric_area"]) - original_area) < 0.00001, "expanded square retains original geometric area")
	for factor: float in [0.5, 0.7, 2.0]:
		camera.set("_factor", factor)
		var limited: bool = true
		for target: Vector2 in [Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)]:
			camera.focus_map(target)
			var view := Rect2(MechIsoGeometry.project(camera.visible_map_polygon()[0]), Vector2.ZERO)
			for point: Vector2 in camera.visible_map_polygon():
				view = view.expand(MechIsoGeometry.project(point))
			for axis: int in range(2):
				if view.size[axis] <= bounds.size[axis] + 0.1:
					limited = limited and view.position[axis] >= bounds.position[axis] - 0.1 and view.end[axis] <= bounds.end[axis] + 0.1
				else:
					limited = limited and absf(view.get_center()[axis] - bounds.get_center()[axis]) < 0.1
		_check(limited, "screen-axis camera limits hold at zoom %.1f" % factor)
	camera.fit_map()
	var fitted: bool = true
	for corner: Vector2 in map.outline():
		fitted = fitted and battle.get_node("HUD").battle_view_rect().has_point(camera.map_to_screen(corner))
	_check(fitted, "Home overview fits the square outline above HUD")
	camera.configure_map(sim.map_snapshot())
