@tool
class_name MechPortraitView2D
extends Node2D
## HUD单对象肖像；保留既有二维外观，不承担战场绘制或拾取。

const CYAN := Color("72e9d0")
const MAINBRAIN_REFERENCE_SIZE := Vector2(3, 3)

var _entity: Dictionary = {}


func present(entity: Dictionary) -> void:
	_entity = entity.duplicate(true)
	queue_redraw()


func _draw() -> void:
	if _entity.is_empty():
		return
	var point: Vector2 = _project(_entity["position"])
	if _entity["kind"] == &"mainbrain":
		var footprint: Vector2i = _entity["footprint"]
		var origin := Vector2i((_entity["position"] - Vector2(footprint) * 0.5).floor())
		_outline_cell(origin, footprint, CYAN, 2.0)
		_draw_mainbrain(point, footprint)
	elif _entity.get("is_building", false):
		_draw_building(_entity, point)
	elif _entity.get("is_enemy", false):
		_draw_enemy(_entity, point)
	elif _entity.get("is_unit", false):
		_draw_sentinel(_entity, point)
	else:
		_draw_probe(point, _entity.get("facing", Vector2.UP))


func _is_wall_id(id: StringName) -> bool:
	return id in [&"armored_wall", &"alloy_wall"]


func _building_metrics(id: StringName) -> Vector3:
	if _is_wall_id(id):
		return Vector3(25, 31, 31 * MechIsoGeometry.GROUND_RATIO)
	match id:
		&"sentry_tower": return Vector3(30, 47, 47 * MechIsoGeometry.GROUND_RATIO)
		&"mining_station": return Vector3(36, 47, 47 * MechIsoGeometry.GROUND_RATIO)
		&"assembly_plant": return Vector3(48, 75, 75 * MechIsoGeometry.GROUND_RATIO)
	return Vector3(58, 47, 47 * MechIsoGeometry.GROUND_RATIO)


func _project(point: Vector2) -> Vector2:
	return MechIsoGeometry.project(point)


func _draw_sentinel(entity: Dictionary, point: Vector2) -> void:
	_draw_shadow(point, Vector2(18, 9))
	var body := PackedVector2Array([point + Vector2(-12, -9), point + Vector2(-12, -29),
		point + Vector2(0, -36), point + Vector2(12, -29), point + Vector2(12, -9), point])
	draw_colored_polygon(body, Color("d8e0e4"))
	var direction: Vector2 = _project(entity.get("facing", Vector2.UP)).normalized()
	var side := Vector2(-direction.y, direction.x)
	var visor: Vector2 = point + Vector2(0, -25) + direction * 7.0
	draw_line(visor - side * 5.0, visor + side * 5.0, CYAN, 3.0, true)
	var weapon: Vector2 = point + Vector2(0, -21)
	draw_line(weapon, weapon + direction * 25.0, Color("8d9ea9"), 5.0, true)
	if entity["hp"] < entity["max_hp"]:
		draw_rect(Rect2(point + Vector2(-18, -46), Vector2(36, 3)), Color("213540"))
		draw_rect(Rect2(point + Vector2(-18, -46), Vector2(36.0 * float(entity["hp"]) / entity["max_hp"], 3)), CYAN)


func _draw_enemy(entity: Dictionary, point: Vector2) -> void:
	if entity.get("elite", false):
		_draw_elite(entity, point)
		return
	_draw_shadow(point, Vector2(16, 8))
	var body := PackedVector2Array([point + Vector2(-10, -8), point + Vector2(-10, -24),
		point + Vector2(0, -32), point + Vector2(10, -24), point + Vector2(10, -8), point])
	var color: Color = {&"builder_worn": Color("8b7770"), &"builder_veteran": Color("db6464"),
		&"recycler": Color("d9a15d"), &"provoker": Color("e0a35e")}.get(entity.get("enemy_id", &""), Color("c9908b"))
	draw_colored_polygon(body, color)
	if entity.get("enemy_id", &"") == &"recycler":
		draw_rect(Rect2(point + Vector2(-17, -16), Vector2(34, 10)), color.darkened(0.3))
	if entity.get("charge_ticks", 0) > 0:
		draw_line(point + Vector2(-6, 3), point + Vector2(6, 3), Color("f0d594"), 3.0, true)
	if entity.get("frenzy_ticks", 0) > 0:
		draw_arc(point + Vector2(0, -10), 18, 0, TAU, 16, Color("e07a5f"), 2.0, true)
	draw_line(point + Vector2(-6, -21), point + Vector2(6, -21), Color("7a2e28"), 3.0, true)
	draw_line(point + Vector2(-6, -13), point + Vector2(6, -13), Color("7a2e28"), 3.0, true)
	draw_rect(Rect2(point + Vector2(-16, -42), Vector2(32, 3)), Color("213540"))
	draw_rect(Rect2(point + Vector2(-16, -42), Vector2(32.0 * float(entity["hp"]) / entity["max_hp"], 3)), Color("f27c78"))
	if entity.get("sheltered", false):
		_draw_shelter_mark(point)




func _draw_elite(entity: Dictionary, point: Vector2) -> void:
	var id: StringName = entity.get("enemy_id", &"")
	var tint: Color = {&"scavenger": Color("cc9d61"), &"deflector": Color("a78dde"),
		&"strider": Color("77bf96"), &"mortar": Color("c67c66"), &"silencer": Color("77c7db")}.get(id, Color("c9a0e8"))
	_draw_shadow(point, Vector2(26, 13))
	var body := PackedVector2Array([point + Vector2(-18, -6), point + Vector2(-18, -34),
		point + Vector2(0, -48), point + Vector2(18, -34), point + Vector2(18, -6), point])
	draw_colored_polygon(body, tint.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([point + Vector2(-11, -28), point + Vector2(-11, -40),
		point + Vector2(0, -44), point + Vector2(11, -40), point + Vector2(11, -28)]), Color("4a3a55"))
	draw_line(point + Vector2(-8, -34), point + Vector2(8, -34), tint, 3.0, true)
	match id:
		&"strider":
			for side: int in [-1, 1]:
				draw_polyline(PackedVector2Array([point + Vector2(side * 10, -22), point + Vector2(side * 29, -13), point + Vector2(side * 31, 5)]), tint, 4.0, true)
		&"mortar":
			draw_line(point + Vector2(0, -26), point + Vector2(18, -57), tint, 9.0, true)
		&"silencer":
			draw_line(point + Vector2(0, -36), point + Vector2(0, -68), tint, 3.0, true)
			draw_arc(point + Vector2(0, -58), 11, PI, TAU, 12, tint, 2.0, true)
		&"deflector":
			draw_arc(point + Vector2(0, -25), 29, 0, TAU, 24, tint, 2.0, true)
		&"scavenger":
			draw_rect(Rect2(point + Vector2(-22, -29), Vector2(44, 12)), tint)
			if entity.get("scavenge_armor", 0.0) > 0.0:
				draw_arc(point + Vector2(0, -17), 25, 0, TAU, 20, tint, 3.0, true)
	draw_rect(Rect2(point + Vector2(-24, -58), Vector2(48, 4)), Color("213540"))
	draw_rect(Rect2(point + Vector2(-24, -58), Vector2(48.0 * float(entity["hp"]) / entity["max_hp"], 4)), tint)
	if entity.get("sheltered", false):
		_draw_shelter_mark(point)




func _draw_shelter_mark(point: Vector2) -> void:
	draw_arc(point + Vector2(0, -10), 20.0, PI * 0.15, PI * 0.85, 16, Color("c9a0e8", 0.55), 2.0, true)


func _draw_ruin(building: Dictionary, footprint: Vector2i) -> void:
	# 被摧毁的基地：肖像使用带叉号的扁平底座，跳过主体、状态条与墙体连线。
	var polygon: PackedVector2Array = MechIsoGeometry.footprint_polygon(building["origin"], footprint)
	draw_colored_polygon(polygon, Color("3c4a53"))
	draw_polyline(PackedVector2Array([polygon[0], polygon[2]]), Color("f27c78"), 2.0, true)
	draw_polyline(PackedVector2Array([polygon[1], polygon[3]]), Color("f27c78"), 2.0, true)
	_outline_cell(building["origin"], footprint, Color("6a7a84"), 1.5)


func _draw_building(building: Dictionary, point: Vector2) -> void:
	var id: StringName = building["building_id"]
	var footprint: Vector2i = building["footprint"]
	var constructing: bool = building["phase"] == MechBuildingState.Phase.CONSTRUCTING
	var progress: float = building["build_progress"]
	var scale_height: float = 0.25 + progress * 0.75 if constructing else 1.0
	var color := Color("bdc8cd")
	var metrics: Vector3 = _building_metrics(id)
	var height: float = metrics.x
	var half_width: float = metrics.y
	var depth: float = metrics.z
	if building.get("hp", 1) <= 0:
		_draw_ruin(building, footprint)
		return
	if _is_wall_id(id):
		color = Color("84939c")
	elif id == &"sentry_tower":
		color = Color("a9b6bf")
	elif id == &"mining_station":
		color = Color("d1d7da")
	elif id == &"assembly_plant":
		color = Color("c6d0d6")
	if building["phase"] == MechBuildingState.Phase.DEMOLISHING:
		color = Color("986c66")
	color.a = 0.45 + progress * 0.55 if constructing else 1.0
	height *= scale_height
	_draw_shadow(point, Vector2(footprint.x * 29.0, footprint.y * 14.0))
	if _is_wall_id(id):
		var half: Vector2 = MechIsoGeometry.HALF_TILE
		var directions: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]
		var mask: int = building.get("connections", 0)
		for index: int in range(directions.size()):
			if mask & (1 << index):
				draw_line(point + Vector2(0, -height), point + Vector2(0, -height) + directions[index] * 0.55, color.darkened(0.25), 11.0, true)
	var top := PackedVector2Array([point + Vector2(0, -height - depth), point + Vector2(half_width, -height),
		point + Vector2(0, -height + depth), point + Vector2(-half_width, -height)])
	draw_colored_polygon(PackedVector2Array([top[3], top[2], point + Vector2(0, depth), point + Vector2(-half_width, 0)]), color.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([top[2], top[1], point + Vector2(half_width, 0), point + Vector2(0, depth)]), color.darkened(0.5))
	draw_colored_polygon(top, color)
	var rim: PackedVector2Array = top.duplicate()
	rim.append(top[0])
	draw_polyline(rim, color.lightened(0.25), 1.5, true)
	if id == &"compute_node":
		for index: int in range(3):
			var offset := Vector2(-28.0 + index * 12.0, -height + 12.0 + index * 6.0)
			draw_line(point + offset, point + offset + Vector2(0, 14), Color(CYAN, color.a), 2.5, true)
	elif id == &"sentry_tower":
		var turret: Vector2 = point + Vector2(0, -height - 13.0 * scale_height)
		draw_circle(turret, 12.0 * scale_height, color.lightened(0.2))
		draw_line(turret, turret + Vector2(30, -15) * scale_height, color.lightened(0.1), 8.0, true)
	elif id == &"mining_station":
		var tip: Vector2 = point + Vector2(0, -height - 27.0 * scale_height)
		draw_line(point + Vector2(-19, -height), tip, Color("5e727e"), 5.0, true)
		draw_line(point + Vector2(19, -height), tip, Color("5e727e"), 5.0, true)
		draw_line(tip, tip + Vector2(0, 28) * scale_height, CYAN, 4.0, true)
	elif id == &"assembly_plant":
		draw_line(point + Vector2(8, -12), point + Vector2(8, 20), Color("536a79"), 15.0, true)
		draw_line(point + Vector2(26, -21), point + Vector2(26, 11), Color("536a79"), 15.0, true)
		draw_line(point + Vector2(-46, -height), point + Vector2(-12, -height + 17), CYAN, 4.0, true)
	var bar_position: Vector2 = point + Vector2(-28.0, -height - depth - 12.0)
	if constructing or building["phase"] == MechBuildingState.Phase.DEMOLISHING:
		var fraction: float = progress if constructing else float(building["demolition_progress"])
		draw_rect(Rect2(bar_position, Vector2(56, 4)), Color("14232b"))
		draw_rect(Rect2(bar_position, Vector2(56.0 * fraction, 4)), CYAN if constructing else Color("f0bc79"))
	if building["hp"] < building["max_hp"]:
		bar_position.y -= 7.0
		var health: float = float(building["hp"]) / float(building["max_hp"])
		draw_rect(Rect2(bar_position, Vector2(56, 3)), Color("14232b"))
		draw_rect(Rect2(bar_position, Vector2(56.0 * health, 3)), Color("f0bc79"))


func _outline_cell(origin: Vector2i, footprint: Vector2i, color: Color, width: float) -> void:
	var polygon: PackedVector2Array = MechIsoGeometry.footprint_polygon(origin, footprint)
	polygon.append(polygon[0])
	draw_polyline(polygon, color, width, true)


func _draw_mainbrain(world_point: Vector2, footprint: Vector2i) -> void:
	draw_set_transform(world_point, 0.0, Vector2(footprint) / MAINBRAIN_REFERENCE_SIZE)
	var point := Vector2.ZERO
	_draw_shadow(point, Vector2(82.0, 34.0))
	var hull: PackedVector2Array = _mainbrain_hull()
	var depth: float = 65.0 * MechIsoGeometry.GROUND_RATIO
	var top := PackedVector2Array([hull[0], hull[1], Vector2(0, -68 + depth), hull[5]])
	var left := PackedVector2Array([hull[5], top[2], hull[3], hull[4]])
	var right := PackedVector2Array([top[2], hull[1], hull[2], hull[3]])
	draw_colored_polygon(left, Color("a3b0b8"))
	draw_colored_polygon(right, Color("748792"))
	draw_colored_polygon(top, Color("d6dfe3"))
	var rim: PackedVector2Array = top.duplicate()
	rim.append(top[0])
	draw_polyline(rim, CYAN, 2.0, true)
	draw_line(point + Vector2(0, -80), point + Vector2(0, -57), CYAN, 4.0, true)
	draw_line(point + Vector2(-20, -69), point + Vector2(20, -69), CYAN, 4.0, true)
	draw_circle(point + Vector2(-43, -31), 3.0, CYAN)
	draw_circle(point + Vector2(-29, -24), 3.0, CYAN)
	draw_set_transform(Vector2.ZERO)


func _mainbrain_hull() -> PackedVector2Array:
	var depth: float = 65.0 * MechIsoGeometry.GROUND_RATIO
	return PackedVector2Array([Vector2(0, -68 - depth), Vector2(65, -68),
		Vector2(65, -20), Vector2(0, -20 + depth), Vector2(-65, -20), Vector2(-65, -68)])


func _draw_probe(point: Vector2, facing: Vector2 = Vector2.UP) -> void:
	_draw_shadow(point, Vector2(24.0, 11.0))
	draw_arc(point, 23.0, 0.0, TAU, 40, Color(0.45, 0.91, 0.82, 0.45), 1.0, true)
	var body := PackedVector2Array([point + Vector2(0, -29), point + Vector2(14, -18), point + Vector2(10, -6), point + Vector2(-10, -6), point + Vector2(-14, -18)])
	draw_colored_polygon(body, Color("d9f2ec"))
	draw_line(point + Vector2(-7, -16), point + Vector2(7, -16), Color("173942"), 4.0, true)
	draw_circle(point + Vector2(0, -17), 2.0, CYAN)
	var direction: Vector2 = _project(facing).normalized()
	draw_line(point + Vector2(0, -19), point + Vector2(0, -19) + direction * 16.0, CYAN, 2.0, true)


func _draw_shadow(point: Vector2, radius: Vector2) -> void:
	var polygon := PackedVector2Array()
	for index: int in range(32):
		var angle: float = TAU * float(index) / 32.0
		polygon.append(point + Vector2(cos(angle), sin(angle) * MechIsoGeometry.GROUND_RATIO / 0.5) * radius)
	draw_colored_polygon(polygon, Color(0.0, 0.0, 0.0, 0.35))
