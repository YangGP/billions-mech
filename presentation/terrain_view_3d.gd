@tool
class_name MechTerrainView3D
extends Node3D
## 逻辑格地图转静态分块网格；复用原生多边形裁剪/三角化，不创建逐格节点。

const CHUNK_SIZE: int = 16
var _landmarks: Dictionary = {}
var _known: Dictionary = {}
var _labels: Node3D


func present_map(map_state: Dictionary) -> void:
	for child: Node in get_children():
		child.free()
	_known.clear()
	_labels = Node3D.new()
	add_child(_labels)
	_landmarks = {map_state["main_gate"]: "主口", map_state["flank"]: "侧翼",
		map_state["mainbrain_origin"] + Vector2i(1, 5): "初始腹地"}
	var dimensions: Vector2i = map_state["dimensions"]
	var playable: PackedByteArray = map_state["playable"]
	var terrain: PackedByteArray = map_state["terrain"]
	var water: PackedByteArray = map_state.get("water", PackedByteArray())
	var wind: PackedByteArray = map_state.get("wind", PackedByteArray())
	var outline: PackedVector2Array = map_state["outline"]
	var fog: MechFogView3D = get_parent().get_node("Fog")
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 6
	rock.rings = 3
	var rock_groups: Dictionary = {}
	for cy: int in range(0, dimensions.y, CHUNK_SIZE):
		for cx: int in range(0, dimensions.x, CHUNK_SIZE):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var vertices: int = 0
			for y: int in range(cy, mini(cy + CHUNK_SIZE, dimensions.y)):
				for x: int in range(cx, mini(cx + CHUNK_SIZE, dimensions.x)):
					var index: int = y * dimensions.x + x
					var tile := PackedVector2Array([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
					var polygons: Array[PackedVector2Array] = Geometry2D.intersect_polygons(tile, outline)
					if polygons.is_empty():
						continue
					var fill := Color("26414b") if (x + y) % 2 == 0 else Color("2a4650")
					if not water.is_empty() and water[index] != 0:
						fill = Color("265676")
					elif terrain[index] == MechGridState.Terrain.ROUGH:
						fill = Color("626348")
					elif terrain[index] == MechGridState.Terrain.OBSTACLE:
						fill = Color("405563")
						var center := Vector2(x + 0.5, y + 0.5)
						if playable[index] != 0:
							var height: float = 0.45 + float((x * 17 + y * 13) % 5) * 0.1
							var transform := Transform3D(Basis(Vector3.UP, float((x + y) % 6)) * Basis.from_scale(Vector3(0.86, height, 0.86)), Vector3(center.x, height * 0.5, center.y))
							MechInstanceBatches3D.append(rock_groups, "rocks_%d_%d" % [cx, cy], rock, transform, Color("4b606e"))
					elif not wind.is_empty() and wind[index] != 0:
						fill = Color("345c59")
					for polygon: PackedVector2Array in polygons:
						var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
						for vertex: int in triangles:
							surface.set_color(fill)
							surface.set_normal(Vector3.UP)
							surface.add_vertex(Vector3(polygon[vertex].x, 0.0, polygon[vertex].y))
							vertices += 1
			if vertices > 0:
				var chunk := MeshInstance3D.new()
				chunk.mesh = surface.commit()
				chunk.material_override = fog.material(true)
				chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(chunk)
	var rocks := MechInstanceBatches3D.new()
	add_child(rocks)
	rocks.present(rock_groups, fog.material())


func present_vision(vision: Dictionary) -> void:
	if _labels == null:
		return
	var dimensions: Vector2i = vision["dimensions"]
	var cells: PackedByteArray = vision["cells"]
	for cell: Vector2i in _landmarks:
		if _known.has(cell) or not Rect2i(Vector2i.ZERO, dimensions).has_point(cell) or cells[cell.y * dimensions.x + cell.x] == MechVisionSystem.State.UNEXPLORED:
			continue
		_known[cell] = true
		var label := Label3D.new()
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "sans-serif"])
		label.font = font
		label.text = _landmarks[cell]
		label.font_size = 36
		label.pixel_size = 0.012
		label.modulate = Color("72b4a5")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(cell.x + 0.5, 0.15, cell.y + 0.5)
		_labels.add_child(label)
