class_name MechBattleOverlay3D
extends Control
## 集中绘制屏幕血条与状态，不为每个单位创建Label/ProgressBar节点。

var _state: Dictionary = {}
var _selected: Dictionary = {}
var _bounds: Dictionary = {}
var _camera: MechMapCamera3D
var _hud: MechMapHud
var _font := SystemFont.new()


func _ready() -> void:
	_camera = get_parent().get_parent().get_node("MapCamera")
	_hud = get_parent().get_parent().get_node("HUD")
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func present(state: Dictionary, selected: Array[int], bounds: Dictionary) -> void:
	_state = state
	_bounds = bounds
	_selected.clear()
	for id: int in selected:
		_selected[id] = true
	queue_redraw()


func _process(_delta: float) -> void:
	# 镜头可在暂停时移动；不需要重建模拟快照。
	queue_redraw()


func _draw() -> void:
	if _state.is_empty() or _hud.is_minimap_fullscreen():
		return
	var viewport: Rect2 = get_viewport_rect()
	for entity: Dictionary in _state.get("entities", []):
		var id: int = entity["id"]
		if not _bounds.has(id):
			continue
		var point: Vector2 = entity["position"]
		if not _camera.map_point_on_screen(point):
			continue
		var selected: bool = _selected.has(id)
		var enemy: bool = entity.get("team", 1) == 2
		var hp: int = entity.get("hp", 1)
		var maximum: int = maxi(1, entity.get("max_hp", 1))
		if _camera.zoom_factor() < 0.35 and not selected and hp == maximum and entity.get("jam_ticks", 0) <= 0:
			continue
		var bounds: AABB = _bounds[id]
		var anchor: Vector2 = _camera.map_to_screen(point, bounds.end.y + 0.22)
		if not viewport.has_point(anchor) or _hud.blocks_point(anchor):
			continue
		var width: float = clampf(40.0 * _camera.zoom_factor(), 24.0, 64.0)
		var rect := Rect2(anchor - Vector2(width * 0.5, 6), Vector2(width, 4))
		# 不让血条伸进面板，鼠标和框选的UI边界仍由HUD统一处理。
		if _hud.blocks_point(rect.position) or _hud.blocks_point(rect.end):
			continue
		if hp > 0 and (selected or enemy or hp < maximum):
			draw_rect(rect.grow(1.0), Color("14212b"))
			draw_rect(Rect2(rect.position, Vector2(width * clampf(float(hp) / maximum, 0.0, 1.0), 4)), Color("f27c78") if enemy else Color("72e9d0"))
		var status: String = ""
		var tint := Color("dfe8e8")
		if entity.get("jam_ticks", 0) > 0:
			status = "干扰"
			tint = Color("77c7db")
		elif entity.get("scavenge_stacks", 0) > 0:
			status = "拾荒 %d" % int(entity["scavenge_stacks"])
			tint = Color("e0bd72")
		elif entity.get("sheltered", false):
			status = "偏转保护"
			tint = Color("ae94e0")
		elif entity.get("charge_ticks", 0) > 0:
			status = "冲锋"
			tint = Color("e0bd72")
		elif entity.get("speed_boost_ticks", 0) > 0:
			status = "提速"
			tint = Color("77c7db")
		elif entity.get("is_building", false):
			if hp <= 0:
				status = "基座" if selected else ""
			elif not entity.get("powered", true):
				status = "断覆盖"
				tint = Color("f27c78")
			elif entity.get("garrison_count", 0) > 0:
				status = "驻军 %d" % int(entity["garrison_count"])
			elif entity.get("repairing", false):
				status = "维修"
		if selected and status.is_empty():
			status = entity.get("name", "")
		if not status.is_empty():
			var extent: Vector2 = _font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(_font, anchor - Vector2(extent.x * 0.5, 11), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)
		if hp <= 0:
			continue
		var progress: float = -1.0
		if entity.get("phase", -1) == MechBuildingState.Phase.CONSTRUCTING:
			progress = float(entity.get("build_progress", 0.0))
		elif entity.get("upgrade", {}).get("active", false):
			progress = float(entity["upgrade"]["progress"])
		elif selected:
			var production: Dictionary = entity.get("production", {})
			var queue: Array = production.get("queue", [])
			if not queue.is_empty():
				progress = float(production.get("progress", 0.0))
		if progress >= 0.0:
			var bar := Rect2(rect.position + Vector2(0, 6), Vector2(width, 3))
			draw_rect(bar.grow(1), Color("14212b"))
			draw_rect(Rect2(bar.position, Vector2(width * clampf(progress, 0.0, 1.0), 3)), Color("e0bd72"))
