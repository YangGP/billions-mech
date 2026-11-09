class_name MechFoundationView3D
extends Node3D
## 原生几何模型占位与只读快照绑定；首阶段复用同一套模拟，不为实体创建逻辑节点。

const CYAN := Color("72e9d0")
var _state: Dictionary = {}
var _generation: int = -1
var _selection_ids: Array[int] = []
var _bounds: Dictionary = {}
var _entities: Dictionary = {}
var _models := MechInstanceBatches3D.new()
var _selection := MechInstanceBatches3D.new()
var _cursor := MechInstanceBatches3D.new()
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _cursor_key: int = 0
var _fog: MechFogView3D
var _camera: MechMapCamera3D


func _ready() -> void:
	_fog = get_parent().get_node("Fog")
	_camera = get_parent().get_node("MapCamera")
	_box.size = Vector3.ONE
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 12
	add_child(_models)
	add_child(_selection)
	add_child(_cursor)


func present(state: Dictionary) -> void:
	_state = state
	if _generation != int(state["generation"]):
		_models.clear()
		_selection.clear()
		_cursor.clear()
		_cursor_key = 0
		_generation = state["generation"]
	_bounds.clear()
	_entities.clear()
	var groups: Dictionary = {}
	for entity: Dictionary in state.get("entities", []):
		var id: int = entity["id"]
		_entities[id] = entity
		var point: Vector2 = entity["position"]
		var key: String = "%s_%d_%d" % [entity["kind"], floori(point.x / 16.0), floori(point.y / 16.0)]
		var building: bool = entity.get("is_building", false)
		var dimensions: Vector3 = _dimensions(entity)
		var body_color: Color = _color(entity)
		var height: float = dimensions.y
		if building:
			var ruined: bool = entity.get("hp", 1) <= 0
			if ruined:
				dimensions.y = 0.14
				body_color = Color("52606a")
			elif entity.get("phase", -1) == MechBuildingState.Phase.CONSTRUCTING:
				dimensions.y *= 0.25 + float(entity.get("build_progress", 0.0)) * 0.75
				body_color = body_color.darkened(0.35)
			elif not entity.get("powered", true):
				body_color = body_color.darkened(0.3)
			_part(groups, key + "_base", _box, point, Vector3(dimensions.x, 0.14, dimensions.z), 0.07, body_color.darkened(0.35))
			_part(groups, key + "_body", _box, point, Vector3(dimensions.x * 0.88, dimensions.y, dimensions.z * 0.88), dimensions.y * 0.5 + 0.14, body_color)
			if entity["kind"] == &"mainbrain" and not ruined:
				_part(groups, key + "_core", _cylinder, point, Vector3(1.9, 0.65, 1.9), dimensions.y + 0.4, CYAN)
			elif not ruined:
				_part(groups, key + "_roof", _box, point, Vector3(dimensions.x * 0.55, 0.10, dimensions.z * 0.55), dimensions.y + 0.19, body_color.lightened(0.3))
			height = dimensions.y + (0.75 if entity["kind"] == &"mainbrain" else 0.25)
		else:
			var facing: Vector2 = entity.get("facing", Vector2.UP)
			var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y))
			var hover: float = 0.40 if entity["kind"] in [&"probe", &"scout"] else 0.04
			_part(groups, key + "_body", _cylinder, point, dimensions, hover + dimensions.y * 0.5, body_color, basis)
			_part(groups, key + "_nose", _box, point, Vector3(dimensions.x * 0.30, 0.15, dimensions.z * 0.90), hover + dimensions.y, body_color.lightened(0.4), basis)
			if entity["kind"] in [&"probe", &"scout"]:
				_part(groups, key + "_wings", _box, point, Vector3(0.98, 0.08, 0.24), hover + 0.1, CYAN, basis)
			height = hover + dimensions.y + 0.2
		var half: Vector2 = Vector2(dimensions.x, dimensions.z) * 0.5
		if not building:
			half = Vector2.ONE * maxf(0.5, maxf(half.x, half.y))
		_bounds[id] = AABB(Vector3(point.x - half.x, 0.0, point.y - half.y), Vector3(half.x * 2, height, half.y * 2))
	for mineral: Dictionary in state.get("minerals", []):
		if mineral["remaining"] > 0:
			var point: Vector2 = Vector2(mineral["cell"]) + Vector2.ONE * 0.5
			_part(groups, "minerals", _cylinder, point, Vector3(0.45, 0.18, 0.45), 0.09, Color("d8b875"))
	_models.present(groups, _fog.material())
	_present_selection()


func present_selection(ids: Array[int]) -> void:
	if _selection_ids == ids:
		return
	_selection_ids = ids.duplicate()
	_present_selection()


func _present_selection() -> void:
	var groups: Dictionary = {}
	for id: int in _selection_ids:
		if not _entities.has(id):
			continue
		var entity: Dictionary = _entities[id]
		var point: Vector2 = entity["position"]
		var footprint: Vector2 = Vector2(entity["footprint"]) if entity.get("is_building", false) else Vector2(0.85, 0.85)
		_outline(groups, point - footprint * 0.5, footprint, CYAN, "selected")
		if entity.get("has_order", false) or entity.get("order", &"idle") in [&"move", &"attack_move"]:
			_outline(groups, Vector2(entity.get("order_goal", point)) - Vector2(0.25, 0.25), Vector2(0.5, 0.5), Color("f0bc79"), "goals")
	_selection.present(groups, _fog.material())


func present_cursor(hover: Vector2i, selected: Vector2i, preview: Dictionary, visible_cursor: bool) -> void:
	var key: int = hash([hover, selected, preview, visible_cursor])
	if key == _cursor_key:
		return
	_cursor_key = key
	var groups: Dictionary = {}
	if selected.x >= 0 and selected.y >= 0:
		_outline(groups, Vector2(selected), Vector2.ONE, Color("f0bc79"), "cell")
	if visible_cursor:
		if preview.is_empty():
			if hover.x >= 0 and hover.y >= 0:
				_outline(groups, Vector2(hover), Vector2.ONE, Color("e4f6f2"), "hover")
		else:
			for cell: Dictionary in preview.get("cells", []):
				_outline(groups, Vector2(cell["cell"]), Vector2.ONE, CYAN if cell["ok"] else Color("f27c78"), "preview")
			if not preview.get("line", false):
				_outline(groups, Vector2(preview["origin"]), Vector2(preview["footprint"]), CYAN if preview["ok"] else Color("f27c78"), "footprint")
				var footprint: Vector2 = Vector2(preview["footprint"])
				var origin: Vector2 = Vector2(preview["origin"])
				var color: Color = CYAN if preview["ok"] else Color("f27c78")
				_outline(groups, origin, footprint, color, "draft_top", 1.0)
				for corner: Vector2 in [origin, origin + Vector2(footprint.x, 0), origin + footprint, origin + Vector2(0, footprint.y)]:
					_part(groups, "draft_posts", _box, corner, Vector3(0.035, 1.0, 0.035), 0.5, color)
	_cursor.present(groups, _fog.material())


## 模型点选使用原生AABB求交；只遍历玩家快照，视野外敌人没有拾取对象。
func _pick(point: Vector2) -> int:
	var origin: Vector3 = _camera.project_ray_origin(point)
	var direction: Vector3 = _camera.project_ray_normal(point)
	var closest: float = INF
	var result: int = 0
	for id: int in _bounds:
		var bounds: AABB = _bounds[id]
		var hit: Variant = bounds.intersects_ray(origin, direction)
		if hit != null:
			var distance: float = origin.distance_squared_to(hit)
			if distance < closest:
				closest = distance
				result = id
	return result


func pick_unit(point: Vector2, enemy: bool = false) -> int:
	var id: int = _pick(point)
	if id == 0:
		return 0
	var entity: Dictionary = _entities[id]
	return id if not entity.get("is_building", false) and ((entity.get("team", 1) == 2) == enemy) else 0


func pick_building(point: Vector2) -> int:
	var id: int = _pick(point)
	return id if id != 0 and _entities[id].get("is_building", false) else 0


func _dimensions(entity: Dictionary) -> Vector3:
	if entity.get("is_building", false):
		var footprint: Vector2 = Vector2(entity["footprint"])
		var height: float = 1.25
		if entity["kind"] == &"mainbrain":
			height = 1.8
		elif "wall" in String(entity["kind"]) or "gate" in String(entity["kind"]):
			height = 0.65
		elif "tower" in String(entity["kind"]):
			height = 1.8
		return Vector3(maxf(0.2, footprint.x - 0.12), height, maxf(0.2, footprint.y - 0.12))
	if entity["kind"] in [&"probe", &"scout"]:
		return Vector3(0.55, 0.26, 0.55)
	if entity.get("is_enemy", false):
		return Vector3(0.95, 1.0, 0.95) if entity.get("elite", false) else Vector3(0.55, 0.6, 0.55)
	return Vector3(0.6, 0.7, 0.6)


func _color(entity: Dictionary) -> Color:
	if entity.get("is_enemy", false):
		return Color("e1a06b") if entity.get("elite", false) else Color("d96769")
	if entity.get("is_building", false):
		return Color("90b6bd")
	return CYAN


func _part(groups: Dictionary, key: String, mesh: Mesh, point: Vector2, dimensions: Vector3, height: float, color: Color, rotation: Basis = Basis.IDENTITY) -> void:
	var transform := Transform3D(rotation * Basis.from_scale(dimensions), Vector3(point.x, height, point.y))
	MechInstanceBatches3D.append(groups, key, mesh, transform, color)


func _outline(groups: Dictionary, origin: Vector2, footprint: Vector2, color: Color, key: String, height: float = 0.05) -> void:
	var center: Vector2 = origin + footprint * 0.5
	_part(groups, key + "_x", _box, Vector2(center.x, origin.y), Vector3(footprint.x, 0.035, 0.035), height, color)
	_part(groups, key + "_x", _box, Vector2(center.x, origin.y + footprint.y), Vector3(footprint.x, 0.035, 0.035), height, color)
	_part(groups, key + "_z", _box, Vector2(origin.x, center.y), Vector3(0.035, 0.035, footprint.y), height, color)
	_part(groups, key + "_z", _box, Vector2(origin.x + footprint.x, center.y), Vector3(0.035, 0.035, footprint.y), height, color)
