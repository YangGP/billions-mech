@tool
extends Node3D
## 内容预览入口：直接展示活动图纸的共享模型，供工程模型检查和后续资产替换使用。
## 不运行模拟或生成测试实体，不作为玩法/性能验证场景。

const SETTINGS: MechFoundationSettings = preload("res://content/development_128.tres")
var _catalog := MechModelCatalog3D.new()
var _models: Node3D
var _camera: Camera3D
var _caption: Label
var _material := StandardMaterial3D.new()
var _sample_count: int = 0
var _sample_seconds: float = 0.0
var _sample_frames: int = 0


func _ready() -> void:
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.9
	_models = Node3D.new()
	add_child(_models)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101d29")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bbcbd1")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var layer := CanvasLayer.new()
	add_child(layer)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	_caption = Label.new()
	_caption.position = Vector2(24, 18)
	_caption.add_theme_font_override("font", font)
	_caption.add_theme_font_size_override("font_size", 22)
	layer.add_child(_caption)
	var choice := OptionButton.new()
	choice.position = Vector2(24, 58)
	choice.add_theme_font_override("font", font)
	for title: String in ["全部模型", "建筑与升级", "玩家单位", "机械敌人"]:
		choice.add_item(title)
	layer.add_child(choice)
	choice.item_selected.connect(_show_group)
	var group: int = 0
	if not Engine.is_editor_hint():
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--model-group="):
				group = clampi(argument.get_slice("=", 1).to_int(), 0, 3)
			elif argument.begins_with("--model-count="):
				_sample_count = clampi(argument.get_slice("=", 1).to_int(), 0, 4000)
	set_process(_sample_count > 0)
	choice.select(group)
	_show_group(group)


func _process(delta: float) -> void:
	_sample_seconds += delta
	_sample_frames += 1
	if _sample_seconds >= 2.0:
		print("[models:render-only] instances=%d fps=%.1f draw_calls=%d render_objects=%d" % [_sample_count,
			_sample_frames / _sample_seconds, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		_sample_seconds = 0.0
		_sample_frames = 0


func _show_group(group: int) -> void:
	for child: Node in _models.get_children():
		child.free()
	var entries: Array[Dictionary] = []
	var buildings: Dictionary = {}
	if group in [0, 1]:
		for root: MechBuildingDefinition in SETTINGS.building_definitions:
			var rules: MechBuildingDefinition = root
			while rules != null and not buildings.has(rules.building_id):
				var entry: Dictionary = rules.snapshot()
				entry.merge({"kind": rules.building_id, "name": rules.display_name, "is_building": true})
				buildings[rules.building_id] = entry
				rules = rules.upgrade_to
		for id: StringName in buildings:
			entries.append(buildings[id])
	if group in [0, 2]:
		for rules: MechUnitDefinition in SETTINGS.unit_definitions:
			var entry: Dictionary = rules.snapshot()
			entry.merge({"kind": rules.unit_id, "name": rules.display_name, "footprint": Vector2i.ONE})
			entries.append(entry)
	if group in [0, 3]:
		for rules: MechEnemyDefinition in SETTINGS.enemy_definitions:
			var entry: Dictionary = rules.snapshot()
			entry.merge({"kind": rules.enemy_id, "name": rules.display_name, "footprint": Vector2i.ONE})
			entries.append(entry)
	var columns: int = mini(11, maxi(1, ceili(sqrt(entries.size() * 1.6))))
	var rows: int = ceili(float(entries.size()) / columns)
	if _sample_count > 0:
		_show_instances(entries)
		return
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var point := Vector3((index % columns) * 6.0, 0, (index / columns) * 6.0)
		var node := MeshInstance3D.new()
		node.mesh = _catalog.model(entry)
		node.material_override = _material
		node.position = point
		_models.add_child(node)
		var label := Label3D.new()
		label.text = entry["name"]
		label.font = font
		label.font_size = 40
		label.pixel_size = 0.014
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = point + Vector3(0, 0.08, 2.4)
		_models.add_child(label)
	var center := Vector3((columns - 1) * 3.0, 0, (rows - 1) * 3.0)
	_camera.position = center + Vector3(45, 72, 45)
	_camera.look_at(center)
	_camera.size = maxf(14.0, (columns + rows) * 3.8 + 4.0)
	_caption.text = "三维工程模型目录 · %d 个图纸/形态（原生几何体，可替换为正式资产）" % entries.size()
	if not Engine.is_editor_hint():
		print("[models] group=%d entries=%d buildings=%d" % [group, entries.size(), buildings.size()])


func _show_instances(entries: Array[Dictionary]) -> void:
	var groups: Dictionary = {}
	var columns: int = ceili(sqrt(_sample_count))
	var rows: int = ceili(float(_sample_count) / columns)
	var spacing: float = 1.5
	for index: int in range(_sample_count):
		var mesh: Mesh = _catalog.model(entries[index % entries.size()])
		var point := Vector3((index % columns) * spacing, 0, (index / columns) * spacing)
		var key: String = "%d_%d_%d" % [mesh.get_instance_id(), floori(point.x / 16), floori(point.z / 16)]
		MechInstanceBatches3D.append(groups, key, mesh, Transform3D(Basis.IDENTITY, point), Color.WHITE)
	var batches := MechInstanceBatches3D.new()
	_models.add_child(batches)
	batches.present(groups, _material)
	var center := Vector3((columns - 1) * spacing * 0.5, 0, (rows - 1) * spacing * 0.5)
	_camera.position = center + Vector3(75, 120, 75)
	_camera.look_at(center)
	_camera.size = maxf(12, (columns + rows) * spacing * 0.62)
	_caption.text = "三维模型批量预览 · %d 个实例 · 仅测几何绘制（不含模拟、视野和战斗）" % _sample_count
	print("[models:render-only] instances=%d batches=%d" % [_sample_count, groups.size()])
