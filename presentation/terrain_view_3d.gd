class_name MechTerrainView3D
extends Node3D
## 逻辑格地图转静态分块网格；复用原生多边形裁剪/三角化，不创建逐格节点。

const CHUNK_SIZE: int = 16


func present_map(map_state: Dictionary) -> void:
	for child: Node in get_children():
		child.free()
	var dimensions: Vector2i = map_state["dimensions"]
	var playable: PackedByteArray = map_state["playable"]
	var terrain: PackedByteArray = map_state["terrain"]
	var water: PackedByteArray = map_state.get("water", PackedByteArray())
	var wind: PackedByteArray = map_state.get("wind", PackedByteArray())
	var outline: PackedVector2Array = map_state["outline"]
	var fog: MechFogView3D = get_parent().get_node("Fog")
	for cy: int in range(0, dimensions.y, CHUNK_SIZE):
		for cx: int in range(0, dimensions.x, CHUNK_SIZE):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var vertices: int = 0
			for y: int in range(cy, mini(cy + CHUNK_SIZE, dimensions.y)):
				for x: int in range(cx, mini(cx + CHUNK_SIZE, dimensions.x)):
					var index: int = y * dimensions.x + x
					if playable[index] == 0:
						continue
					var tile := PackedVector2Array([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
					var fill := Color("26414b") if (x + y) % 2 == 0 else Color("2a4650")
					if not water.is_empty() and water[index] != 0:
						fill = Color("265676")
					elif terrain[index] == MechGridState.Terrain.ROUGH:
						fill = Color("626348")
					elif terrain[index] == MechGridState.Terrain.OBSTACLE:
						fill = Color("405563")
					elif not wind.is_empty() and wind[index] != 0:
						fill = Color("345c59")
					for polygon: PackedVector2Array in Geometry2D.intersect_polygons(tile, outline):
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


func present_vision(_vision: Dictionary) -> void:
	# 视野变化由共享迷雾纹理表达，不重建静态网格。
	pass
