class_name MechFoundationView3D
extends Node3D
## 原生几何模型占位与只读快照绑定；首阶段复用同一套模拟，不为实体创建逻辑节点。

const CYAN := Color("72e9d0")
var _state: Dictionary = {}
var _generation: int = -1
var _selection_ids: Array[int] = []
var _bounds: Dictionary = {}
var _entities: Dictionary = {}
var _instance_meshes: Dictionary = {}
var _instance_transforms: Dictionary = {}
var _pick_meshes: Dictionary = {}
var _models := MechInstanceBatches3D.new()
var _selection := MechInstanceBatches3D.new()
var _cursor := MechInstanceBatches3D.new()
var _effects := MechInstanceBatches3D.new()
var _catalog := MechModelCatalog3D.new()
var _rules: Dictionary = {}
var _enemy_rules: Dictionary = {}
var _ring := TorusMesh.new()
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _mineral := PrismMesh.new()
var _cursor_key: int = 0
var _fog: MechFogView3D
var _camera: MechMapCamera3D
var _overlay: MechBattleOverlay3D
var _ghost := MeshInstance3D.new()


func _ready() -> void:
	_fog = get_parent().get_node("Fog")
	_camera = get_parent().get_node("MapCamera")
	_overlay = get_parent().get_node("BattleOverlay/Draw")
	_box.size = Vector3.ONE
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 12
	_mineral.size = Vector3.ONE
	_ring.inner_radius = 0.495
	_ring.outer_radius = 0.5
	_ring.rings = 48
	_ring.ring_segments = 6
	add_child(_models)
	add_child(_selection)
	add_child(_cursor)
	add_child(_effects)
	_ghost.material_override = _fog.preview_material()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func configure(settings: MechFoundationSettings) -> void:
	for rules: MechBuildingDefinition in settings.building_definitions:
		while rules != null and not _rules.has(rules.building_id):
			_rules[rules.building_id] = rules.snapshot()
			rules = rules.upgrade_to
	for rules: MechEnemyDefinition in settings.enemy_definitions:
		_enemy_rules[rules.enemy_id] = rules.snapshot()


func present(state: Dictionary) -> void:
	_state = state
	if _generation != int(state["generation"]):
		_models.clear()
		_selection.clear()
		_cursor.clear()
		_effects.clear()
		_cursor_key = 0
		_generation = state["generation"]
	_bounds.clear()
	_entities.clear()
	_instance_meshes.clear()
	_instance_transforms.clear()
	var groups: Dictionary = {}
	for entity: Dictionary in state.get("entities", []):
		var id: int = entity["id"]
		_entities[id] = entity
		var point: Vector2 = entity["position"]
		var building: bool = entity.get("is_building", false)
		var mesh: Mesh = _catalog.model(entity)
		var basis: Basis = Basis.IDENTITY
		if not building:
			var facing: Vector2 = entity.get("facing", Vector2.UP)
			basis = Basis(Vector3.UP, atan2(-facing.x, -facing.y))
		var tint := Color.WHITE
		if building and entity.get("phase", -1) == MechBuildingState.Phase.CONSTRUCTING:
			basis = basis * Basis.from_scale(Vector3(1, 0.25 + float(entity.get("build_progress", 0.0)) * 0.75, 1))
			tint = Color(0.65, 0.8, 0.8)
		elif building and not entity.get("powered", true):
			tint = Color(0.4, 0.4, 0.4)
		var transform := Transform3D(basis, Vector3(point.x, 0.0, point.y))
		var key: String = "%d_%d_%d" % [mesh.get_instance_id(), floori(point.x / 16.0), floori(point.y / 16.0)]
		MechInstanceBatches3D.append(groups, key, mesh, transform, tint)
		_bounds[id] = transform * mesh.get_aabb()
		_instance_meshes[id] = mesh
		_instance_transforms[id] = transform
	for mineral: Dictionary in state.get("minerals", []):
		if mineral["remaining"] > 0 and mineral.get("assigned_to", 0) == 0:
			var point: Vector2 = Vector2(mineral["cell"]) + Vector2.ONE * 0.5
			var kind: StringName = mineral["resource_kind"]
			var tint: Color = {&"metal_ore": Color("c4cdd2"), &"fuel": Color("d8b875"), &"crystals": Color("ae94e0")}.get(kind, Color("c4cdd2"))
			if kind == &"fuel":
				_part(groups, "mineral_fuel", _cylinder, point, Vector3(0.5, 0.18, 0.5), 0.09, tint)
			else:
				for offset: Vector2 in [Vector2(-0.2, 0), Vector2(0.15, -0.15), Vector2(0.2, 0.18)]:
					_part(groups, "mineral_" + String(kind), _mineral, point + offset, Vector3(0.28, 0.38 if kind == &"crystals" else 0.24, 0.28), 0.15, tint)
	_models.present(groups, _fog.material())
	_present_selection()
	_present_effects()
	_overlay.present(state, _selection_ids, _bounds)


func present_selection(ids: Array[int]) -> void:
	if _selection_ids == ids:
		return
	_selection_ids = ids.duplicate()
	_present_selection()
	_overlay.present(_state, _selection_ids, _bounds)


func _present_selection() -> void:
	var groups: Dictionary = {}
	for id: int in _selection_ids:
		if not _entities.has(id):
			continue
		var entity: Dictionary = _entities[id]
		var point: Vector2 = entity["position"]
		var footprint: Vector2 = Vector2(entity["footprint"]) if entity.get("is_building", false) else Vector2(0.85, 0.85)
		_outline(groups, point - footprint * 0.5, footprint, CYAN, "selected")
		if entity.get("hp", 1) > 0:
			for field: String in ["attack_range", "coverage_radius", "repair_radius", "aura_radius"]:
				var radius: float = float(entity.get(field, 0.0))
				if radius > 0.0:
					_circle(groups, point, radius, Color("e0bd72") if field == "attack_range" else CYAN, field)
		if entity.get("has_order", false) or entity.get("order", &"idle") in [&"move", &"attack_move"]:
			_outline(groups, Vector2(entity.get("order_goal", point)) - Vector2(0.25, 0.25), Vector2(0.5, 0.5), Color("f0bc79"), "goals")
			var previous: Vector2 = point
			for waypoint: Vector2 in entity.get("path", []):
				_line(groups, Vector3(previous.x, 0.08, previous.y), Vector3(waypoint.x, 0.08, waypoint.y), CYAN, "path", 0.025)
				previous = waypoint
		var production: Dictionary = entity.get("production", {})
		if not production.is_empty():
			var rally: Vector2 = Vector2(production["rally"]) + Vector2.ONE * 0.5
			_outline(groups, rally - Vector2(0.3, 0.3), Vector2(0.6, 0.6), Color("e0bd72"), "rally")
			_line(groups, Vector3(point.x, 0.1, point.y), Vector3(rally.x, 0.1, rally.y), Color("e0bd72"), "rally_line", 0.025)
	_selection.present(groups, _fog.material())


func present_cursor(hover: Vector2i, selected: Vector2i, preview: Dictionary, visible_cursor: bool) -> void:
	var key: int = hash([hover, selected, preview, visible_cursor])
	if key == _cursor_key:
		return
	_cursor_key = key
	_ghost.hide()
	var groups: Dictionary = {}
	if selected.x >= 0 and selected.y >= 0:
		_outline(groups, Vector2(selected), Vector2.ONE, Color("f0bc79"), "cell")
	if visible_cursor:
		if preview.is_empty():
			if hover.x >= 0 and hover.y >= 0:
				_outline(groups, Vector2(hover), Vector2.ONE, Color("e4f6f2"), "hover")
		else:
			var collection: Rect2i = preview.get("collection_bounds", Rect2i())
			if collection.has_area():
				_outline(groups, Vector2(collection.position), Vector2(collection.size), Color("4b9787"), "collection")
			for conflict: Vector2i in preview.get("conflict_cells", []):
				_outline(groups, Vector2(conflict), Vector2.ONE, Color("f27c78"), "conflict")
			for cell: Dictionary in preview.get("cells", []):
				_outline(groups, Vector2(cell["cell"]), Vector2.ONE, CYAN if cell["ok"] else Color("f27c78"), "preview")
			if not preview.get("line", false):
				_outline(groups, Vector2(preview["origin"]), Vector2(preview["footprint"]), CYAN if preview["ok"] else Color("f27c78"), "footprint")
				var footprint: Vector2 = Vector2(preview["footprint"])
				var origin: Vector2 = Vector2(preview["origin"])
				var color: Color = CYAN if preview["ok"] else Color("f27c78")
				var definition: Dictionary = _rules.get(preview.get("building_id", &""), {}).duplicate()
				definition.merge({"kind": preview.get("building_id", &""), "is_building": true, "footprint": preview["footprint"]}, true)
				var mesh: Mesh = _catalog.model(definition)
				_ghost.mesh = mesh
				_ghost.position = Vector3(origin.x + footprint.x * 0.5, 0, origin.y + footprint.y * 0.5)
				_fog.preview_material().set_shader_parameter("preview_tint", Color(color, 0.26))
				_ghost.show()
				var height: float = mesh.get_aabb().end.y
				_outline(groups, origin, footprint, color, "draft_top", height)
				for corner: Vector2 in [origin, origin + Vector2(footprint.x, 0), origin + footprint, origin + Vector2(0, footprint.y)]:
					_part(groups, "draft_posts", _box, corner, Vector3(0.035, height, 0.035), height * 0.5, color)
				for field: String in ["attack_range", "coverage_radius", "repair_radius", "aura_radius"]:
					var radius: float = float(definition.get(field, 0.0))
					if radius > 0.0:
						_circle(groups, origin + footprint * 0.5, radius, color, field)
	_cursor.present(groups, _fog.material())


## AABB粗筛后复用引擎TriangleMesh的BVH求交；不让空心模型的包围盒挡住空隙。
func pick_entity(point: Vector2) -> int:
	var origin: Vector3 = _camera.project_ray_origin(point)
	var direction: Vector3 = _camera.project_ray_normal(point)
	var closest: float = INF
	var result: int = 0
	for id: int in _bounds:
		var bounds: AABB = _bounds[id]
		var hit: Variant = bounds.intersects_ray(origin, direction)
		if hit == null or origin.distance_squared_to(hit) > closest:
			continue
		var mesh: Mesh = _instance_meshes[id]
		var mesh_id: int = mesh.get_instance_id()
		if not _pick_meshes.has(mesh_id):
			var triangles := TriangleMesh.new()
			if not triangles.create_from_faces(mesh.get_faces()):
				continue
			_pick_meshes[mesh_id] = triangles
		var transform: Transform3D = _instance_transforms[id]
		var inverse: Transform3D = transform.affine_inverse()
		var triangles: TriangleMesh = _pick_meshes[mesh_id]
		var contact: Dictionary = triangles.intersect_ray(inverse * origin, (inverse.basis * direction).normalized())
		if contact.is_empty():
			continue
		var world_contact: Vector3 = transform * Vector3(contact["position"])
		var dimensions: Vector2i = _state["vision"]["dimensions"]
		var cell := Vector2i(floori(world_contact.x), floori(world_contact.z))
		if not Rect2i(Vector2i.ZERO, dimensions).has_point(cell) or _state["vision"]["cells"][cell.y * dimensions.x + cell.x] == MechVisionSystem.State.UNEXPLORED:
			continue
		var distance: float = origin.distance_squared_to(world_contact)
		if distance < closest:
			closest = distance
			result = id
	return result


func pick_unit(point: Vector2, enemy: bool = false) -> int:
	var id: int = pick_entity(point)
	if id == 0:
		return 0
	var entity: Dictionary = _entities[id]
	return id if not entity.get("is_building", false) and ((entity.get("team", 1) == 2) == enemy) else 0


func pick_building(point: Vector2) -> int:
	var id: int = pick_entity(point)
	return id if id != 0 and _entities[id].get("is_building", false) else 0


func _present_effects() -> void:
	var groups: Dictionary = {}
	for id: int in _entities:
		var entity: Dictionary = _entities[id]
		var point: Vector2 = entity["position"]
		var bounds: AABB = _bounds[id]
		var muzzle := Vector3(point.x, bounds.end.y * 0.8, point.y)
		var rules: Dictionary = _enemy_rules.get(entity.get("enemy_id", &""), {})
		if entity.get("shot_ticks", 0) > 0:
			var target: Vector2 = entity["shot_target"]
			var shot_color: Color = Color("ae94e0") if entity["kind"] in [&"emp_tower", &"arc_tower"] else (Color("77c7db") if entity["kind"] == &"rail_mech" else Color("f0d594"))
			_line(groups, muzzle, Vector3(target.x, 0.45, target.y), shot_color, "shots", 0.045)
			var splash: float = float(rules.get("splash_radius", entity.get("splash_radius", 0.0)))
			if splash > 0.0:
				_circle(groups, target, splash, shot_color, "splash")
		if entity.get("jam_ticks", 0) > 0:
			_circle(groups, point, 0.65, Color("77c7db"), "jammed", bounds.end.y + 0.12)
		if entity.get("charge_ticks", 0) > 0 or entity.get("speed_boost_ticks", 0) > 0:
			_circle(groups, point, 0.4, Color("f0d594"), "charge")
		if entity.get("sheltered", false):
			_circle(groups, point, 0.48, Color("ae94e0"), "shelter", bounds.end.y * 0.5)
		if float(rules.get("shelter_radius", 0.0)) > 0.0:
			_circle(groups, point, rules["shelter_radius"], Color("ae94e0"), "deflector")
		var jam_target: int = int(entity.get("jam_target_id", 0))
		if jam_target > 0 and _entities.has(jam_target):
			var target: Vector2 = _entities[jam_target]["position"]
			_line(groups, muzzle, Vector3(target.x, 1.0, target.y), Color("77c7db"), "jam_link", 0.06)
		var stacks: int = int(entity.get("scavenge_stacks", 0))
		if stacks > 0:
			_circle(groups, point, 0.6 + minf(stacks, 10) * 0.02, Color("e0bd72"), "scavenge", bounds.end.y * 0.7)
	_effects.present(groups, _fog.material())


func _circle(groups: Dictionary, point: Vector2, radius: float, color: Color, key: String, height: float = 0.07) -> void:
	_part(groups, key, _ring, point, Vector3(radius * 2, 0.7, radius * 2), height, color)


func _line(groups: Dictionary, start: Vector3, end: Vector3, color: Color, key: String, width: float) -> void:
	var delta: Vector3 = end - start
	if delta.length_squared() < 0.000001:
		return
	var up: Vector3 = Vector3.FORWARD if absf(delta.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	var basis: Basis = Basis.looking_at(delta.normalized(), up) * Basis.from_scale(Vector3(width, width, delta.length()))
	MechInstanceBatches3D.append(groups, key, _box, Transform3D(basis, (start + end) * 0.5), color)


func _part(groups: Dictionary, key: String, mesh: Mesh, point: Vector2, dimensions: Vector3, height: float, color: Color, rotation: Basis = Basis.IDENTITY) -> void:
	var transform := Transform3D(rotation * Basis.from_scale(dimensions), Vector3(point.x, height, point.y))
	MechInstanceBatches3D.append(groups, key, mesh, transform, color)


func _outline(groups: Dictionary, origin: Vector2, footprint: Vector2, color: Color, key: String, height: float = 0.05) -> void:
	var center: Vector2 = origin + footprint * 0.5
	_part(groups, key + "_x", _box, Vector2(center.x, origin.y), Vector3(footprint.x, 0.035, 0.035), height, color)
	_part(groups, key + "_x", _box, Vector2(center.x, origin.y + footprint.y), Vector3(footprint.x, 0.035, 0.035), height, color)
	_part(groups, key + "_z", _box, Vector2(origin.x, center.y), Vector3(0.035, 0.035, footprint.y), height, color)
	_part(groups, key + "_z", _box, Vector2(origin.x + footprint.x, center.y), Vector3(0.035, 0.035, footprint.y), height, color)
