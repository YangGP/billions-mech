@tool
class_name MechModelCatalog3D
extends RefCounted
## 工程模型目录：原生几何体合并成共享Mesh，实例只应用位置/朝向/状态。
## 所有尺寸均为表现单位，模型包围盒不参与模拟占地或导航。

const STEEL := Color("748b99")
const DARK := Color("283d4b")
const LIGHT := Color("d6e3e8")
const CYAN := Color("72e9d0")
const GOLD := Color("e0bd72")
const BLUE := Color("6cabe0")
const VIOLET := Color("ae94e0")
const RED := Color("d97872")

var _cache: Dictionary = {}
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _sphere := SphereMesh.new()
var _parts: Array[Dictionary] = []


func _init() -> void:
	_box.size = Vector3.ONE
	_cylinder.height = 1.0
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.radial_segments = 12
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6


func model(entity: Dictionary) -> Mesh:
	var id: String = String(entity.get("kind", entity.get("building_id", "unknown")))
	var footprint: Vector2 = Vector2(entity.get("footprint", Vector2i.ONE))
	var level: int = int(entity.get("level", 1))
	if id.ends_with("_iii"):
		level = maxi(3, level)
	elif id.ends_with("_ii") or id.ends_with("_deep") or id.begins_with("alloy_") or id == "advanced_heavy_factory":
		level = maxi(2, level)
	var ruined: bool = int(entity.get("hp", 1)) <= 0
	var key: String = "%s_%s_%d_%d_%s" % [id, footprint, level, int(entity.get("connections", 0)), ruined]
	if _cache.has(key):
		return _cache[key]
	_parts.clear()
	if ruined:
		_block(Vector3(footprint.x - 0.1, 0.12, footprint.y - 0.1), Vector3(0, 0.06, 0), DARK)
		for side: float in [-1.0, 1.0]:
			_block(Vector3(footprint.x * 0.65, 0.16, 0.12), Vector3(side * 0.15, 0.16, 0), STEEL, Vector3(0, side * 0.65, 0))
	elif entity.get("is_building", false):
		_building(id.trim_suffix("_iii").trim_suffix("_ii").trim_suffix("_deep"), footprint, level, int(entity.get("connections", 0)))
	else:
		_unit(id)
	var mesh: ArrayMesh = _bake()
	_cache[key] = mesh
	return mesh


func _building(id: String, footprint: Vector2, level: int, connections: int) -> void:
	var width: float = maxf(0.3, footprint.x - 0.14)
	var depth: float = maxf(0.3, footprint.y - 0.14)
	_block(Vector3(width, 0.16, depth), Vector3(0, 0.08, 0), DARK)
	match id:
		"mainbrain":
			_block(Vector3(width * 0.84, 0.7, depth * 0.84), Vector3(0, 0.50, 0), STEEL)
			_cyl(Vector3(2.2, 0.65, 2.2), Vector3(0, 1.15, 0), LIGHT)
			_sph(Vector3(1.2, 0.7, 1.2), Vector3(0, 1.58, 0), CYAN)
			for side: float in [-1.0, 1.0]:
				_block(Vector3(0.4, 1.2, 2.6), Vector3(side * 1.55, 0.8, 0), DARK)
				_block(Vector3(0.18, 0.12, 2.2), Vector3(side * 1.55, 1.44, 0), CYAN)
		"compute_node":
			for side: float in [-1.0, 1.0]:
				_block(Vector3(0.52, 1.1, depth * 0.82), Vector3(side * 0.45, 0.72, 0), STEEL)
				for stripe: int in range(3):
					_block(Vector3(0.4, 0.06, 0.06), Vector3(side * 0.45, 0.5 + stripe * 0.25, -depth * 0.43), CYAN)
		"relay_node":
			_cyl(Vector3(width * 0.65, 0.25, depth * 0.65), Vector3(0, 0.28, 0), STEEL)
			_block(Vector3(0.16, 1.5, 0.16), Vector3(0, 1.05, 0), LIGHT)
			_block(Vector3(width * 0.8, 0.1, 0.12), Vector3(0, 1.65, 0), CYAN)
		"mining_station", "crystal_extractor":
			_block(Vector3(width * 0.8, 0.35, depth * 0.8), Vector3(0, 0.35, 0), STEEL)
			for side: float in [-1.0, 1.0]:
				_block(Vector3(0.16, 1.4, 0.18), Vector3(side * width * 0.34, 0.9, 0), LIGHT)
			_block(Vector3(width * 0.8, 0.18, 0.22), Vector3(0, 1.6, 0), GOLD if id == "mining_station" else VIOLET)
			_cyl(Vector3(0.38, 1.1, 0.38), Vector3(0, 0.94, 0), GOLD if id == "mining_station" else VIOLET)
		"fuel_extractor":
			_cyl(Vector3(width * 0.65, 0.9, depth * 0.65), Vector3(-width * 0.12, 0.65, 0), GOLD)
			_block(Vector3(0.2, 1.5, 0.2), Vector3(width * 0.3, 0.9, 0), STEEL)
			_block(Vector3(width * 0.7, 0.15, 0.2), Vector3(0, 1.6, 0), LIGHT, Vector3(0, 0, -0.2))
		"wind_station":
			_block(Vector3(0.15, 1.7, 0.15), Vector3(0, 1.0, 0), LIGHT)
			for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				_block(Vector3(0.12, 0.84, 0.09), Vector3(sin(angle) * 0.32, 1.9 + cos(angle) * 0.32, 0), CYAN, Vector3(0, 0, -angle))
			_sph(Vector3(0.22, 0.22, 0.22), Vector3(0, 1.9, 0), STEEL)
		"solar_station":
			for side: float in [-1.0, 1.0]:
				_block(Vector3(width * 0.43, 0.12, depth * 0.85), Vector3(side * width * 0.24, 0.62, 0), BLUE, Vector3(-0.28, 0, 0))
				_block(Vector3(0.14, 0.4, 0.14), Vector3(side * width * 0.24, 0.32, 0), STEEL)
		"thermal_smelter":
			_block(Vector3(width * 0.82, 0.7, depth * 0.76), Vector3(0, 0.55, 0), STEEL)
			for side: float in [-1.0, 1.0]:
				_cyl(Vector3(0.52, 1.4, 0.52), Vector3(side * width * 0.27, 1.2, depth * 0.2), DARK)
			_block(Vector3(width * 0.45, 0.3, 0.08), Vector3(0, 0.58, -depth * 0.4), Color("f1a05b"))
		"cooling_tower", "water_cooler":
			for side: float in [-1.0, 1.0]:
				_cyl(Vector3(width * 0.4, 1.0, depth * 0.65), Vector3(side * width * 0.24, 0.7, 0), LIGHT)
				_cyl(Vector3(width * 0.3, 0.12, depth * 0.5), Vector3(side * width * 0.24, 1.25, 0), BLUE)
			if id == "water_cooler":
				_block(Vector3(width * 0.8, 0.15, 0.16), Vector3(0, 0.3, -depth * 0.4), BLUE)
		"armored_wall", "alloy_wall":
			var metal: Color = VIOLET if id.begins_with("alloy") else STEEL
			_block(Vector3(0.78, 0.65, 0.3), Vector3(0, 0.48, 0), metal)
			for direction: int in range(4):
				if (connections & (1 << direction)) != 0:
					# 快照位序为左、上、右、下，与地图XZ坐标一致。
					var offset: Vector2 = [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN][direction]
					_block(Vector3(0.3 if offset.x == 0 else 0.55, 0.6, 0.55 if offset.x == 0 else 0.3), Vector3(offset.x * 0.3, 0.4, offset.y * 0.3), metal)
		"gate", "alloy_gate":
			for side: float in [-1.0, 1.0]:
				_block(Vector3(width * 0.82, 1.0, 0.2), Vector3(0, 0.65, side * depth * 0.4), VIOLET if id == "alloy_gate" else STEEL)
			_block(Vector3(width * 0.8, 0.18, depth), Vector3(0, 1.2, 0), CYAN)
		"garrison_bunker", "alloy_bunker":
			_block(Vector3(width * 0.88, 0.6, depth * 0.88), Vector3(0, 0.48, 0), STEEL)
			_block(Vector3(width, 0.18, depth), Vector3(0, 0.9, 0), VIOLET if id == "alloy_bunker" else LIGHT)
			_block(Vector3(width * 0.55, 0.1, 0.06), Vector3(0, 0.6, -depth * 0.46), DARK)
		"sentry_tower", "arc_tower", "heavy_tower", "annihilator_tower", "emp_tower":
			var tint: Color = VIOLET if id in ["arc_tower", "emp_tower"] else GOLD
			_cyl(Vector3(width * 0.7, 0.9, depth * 0.7), Vector3(0, 0.7, 0), STEEL)
			_block(Vector3(width * 0.72, 0.35, depth * 0.65), Vector3(0, 1.3, 0), tint)
			if id == "emp_tower":
				_sph(Vector3(0.65, 0.65, 0.65), Vector3(0, 1.85, 0), VIOLET)
			else:
				var barrels: int = 2 if id == "annihilator_tower" else 1
				for barrel: int in range(barrels):
					_block(Vector3(0.17, 0.17, 1.0 if id == "heavy_tower" else 0.7), Vector3((barrel - (barrels - 1) * 0.5) * 0.28, 1.4, -depth * 0.35), LIGHT)
		"radar_station":
			_block(Vector3(0.2, 1.7, 0.2), Vector3(0, 1.0, 0), LIGHT)
			_cyl(Vector3(1.1, 0.16, 1.1), Vector3(0, 1.95, 0), BLUE, Vector3(0.6, 0, 0))
		"tech_center", "dispatch_center":
			_block(Vector3(width * 0.8, 0.7, depth * 0.8), Vector3(0, 0.55, 0), STEEL)
			_sph(Vector3(width * 0.6, 0.8, depth * 0.6), Vector3(0, 1.1, 0), VIOLET if id == "tech_center" else CYAN)
			if id == "dispatch_center":
				_block(Vector3(0.12, 0.8, 0.12), Vector3(width * 0.3, 1.35, 0), LIGHT)
		"assembly_plant", "heavy_factory", "advanced_heavy_factory":
			_block(Vector3(width * 0.9, 0.9, depth * 0.8), Vector3(0, 0.65, 0), STEEL)
			_block(Vector3(width * 0.55, 0.6, 0.08), Vector3(0, 0.48, -depth * 0.43), DARK)
			var count: int = 1 if id == "assembly_plant" else (3 if id == "advanced_heavy_factory" else 2)
			for index: int in range(count):
				_cyl(Vector3(0.4, 0.4, 0.4), Vector3((index - (count - 1) * 0.5) * 0.65, 1.3, 0), GOLD)
		_:
			push_warning("Missing 3D building binding: " + id)
			_block(Vector3(width * 0.8, 0.8, depth * 0.8), Vector3(0, 0.6, 0), Color.MAGENTA)
	for index: int in range(level):
		_block(Vector3(0.13, 0.05, 0.22), Vector3((index - (level - 1) * 0.5) * 0.2, 0.18, -depth * 0.43), GOLD)


func _unit(id: String) -> void:
	match id:
		"probe", "scout":
			_cyl(Vector3(0.5, 0.24, 0.5), Vector3(0, 0.55, 0), LIGHT)
			_block(Vector3(0.98, 0.08, 0.22), Vector3(0, 0.55, 0), CYAN)
			_block(Vector3(0.15, 0.12, 0.35), Vector3(0, 0.68, -0.15), BLUE)
		"sentinel", "heavy_mech", "rail_mech":
			var heavy: bool = id == "heavy_mech"
			var width: float = 0.85 if heavy else 0.55
			for side: float in [-1.0, 1.0]:
				_block(Vector3(width * 0.35, 0.46, 0.35), Vector3(side * width * 0.4, 0.23, 0), DARK)
			_block(Vector3(width, 0.5 if heavy else 0.4, 0.5), Vector3(0, 0.7, 0), STEEL if heavy else LIGHT)
			_block(Vector3(0.3, 0.25, 0.28), Vector3(0, 1.05, 0), LIGHT)
			_block(Vector3(0.22, 0.07, 0.04), Vector3(0, 1.08, -0.16), CYAN)
			_block(Vector3(0.16, 0.16, 1.0 if id == "rail_mech" else 0.5), Vector3(width * 0.55, 0.85, -0.3), BLUE if id == "rail_mech" else GOLD)
		"grenadier":
			_legs(0.28, 0.22, 0.42, 2, DARK)
			_block(Vector3(0.62, 0.42, 0.52), Vector3(0, 0.64, 0), Color("c9a06b"))
			_block(Vector3(0.28, 0.26, 0.28), Vector3(0, 0.98, 0), LIGHT)
			_block(Vector3(0.16, 0.16, 0.16), Vector3(0, 1.16, 0), GOLD)
			_cyl(Vector3(0.16, 0.72, 0.16), Vector3(0.28, 0.84, -0.18), STEEL, Vector3(-0.55, 0, 0.25))
		"fortress_mech":
			_legs(0.48, 0.38, 0.5, 2, DARK)
			_block(Vector3(1.15, 0.62, 0.85), Vector3(0, 0.78, 0), STEEL)
			_block(Vector3(0.55, 0.38, 0.55), Vector3(0, 1.18, 0.05), LIGHT)
			_block(Vector3(0.22, 0.2, 0.3), Vector3(0, 1.42, -0.12), CYAN)
			_block(Vector3(0.18, 0.18, 0.78), Vector3(0.38, 0.94, -0.5), GOLD)
			for side: float in [-1.0, 1.0]:
				_cyl(Vector3(0.13, 0.7, 0.13), Vector3(side * 0.5, 0.8, -0.48), BLUE, Vector3(-0.4, 0, 0))
		"builder", "builder_worn", "builder_veteran", "provoker":
			var tint: Color = {"builder_worn": Color("8b7770"), "builder_veteran": RED, "provoker": Color("e0a35e")}.get(id, Color("c9908b"))
			_legs(0.27, 0.18, 0.45, 2, DARK)
			_block(Vector3(0.48, 0.38, 0.38), Vector3(0, 0.6, 0), tint)
			_block(Vector3(0.48, 0.12, 0.15), Vector3(0, 0.48, -0.3), STEEL)
			if id == "builder_veteran":
				_block(Vector3(0.65, 0.12, 0.28), Vector3(0, 0.83, 0), GOLD)
			if id == "provoker":
				_block(Vector3(0.1, 0.5, 0.1), Vector3(0, 1.02, 0), Color("e07a5f"))
		"recycler", "scavenger":
			_legs(0.4, 0.32, 0.45, 2, DARK)
			_block(Vector3(0.85, 0.55, 0.62), Vector3(0, 0.7, 0), GOLD)
			for side: float in [-1.0, 1.0]:
				_block(Vector3(0.14, 0.2, 0.65), Vector3(side * 0.54, 0.5, -0.23), LIGHT, Vector3(0, side * 0.3, 0))
			if id == "scavenger":
				_block(Vector3(1.1, 0.25, 0.6), Vector3(0, 1.07, 0), RED)
		"strider":
			_legs(0.64, 0.5, 1.35, 2, Color("77bf96"))
			_block(Vector3(0.6, 0.32, 0.7), Vector3(0, 1.5, 0), Color("77bf96"))
			_block(Vector3(0.2, 0.12, 0.4), Vector3(0, 1.66, -0.3), LIGHT)
		"mortar":
			for side: float in [-1.0, 1.0]:
				_block(Vector3(0.24, 0.3, 1.0), Vector3(side * 0.5, 0.2, 0), DARK)
			_block(Vector3(0.85, 0.55, 0.8), Vector3(0, 0.65, 0), RED)
			_cyl(Vector3(0.4, 1.2, 0.4), Vector3(0, 1.3, -0.3), STEEL, Vector3(-0.55, 0, 0))
		"deflector", "silencer":
			_legs(0.38, 0.26, 0.6, 2, DARK)
			var tint: Color = VIOLET if id == "deflector" else BLUE
			_cyl(Vector3(0.7, 0.65, 0.7), Vector3(0, 0.85, 0), tint)
			_block(Vector3(0.1, 0.9, 0.1), Vector3(0, 1.45, 0), LIGHT)
			if id == "deflector":
				_sph(Vector3(0.65, 0.3, 0.65), Vector3(0, 1.85, 0), VIOLET)
			else:
				_block(Vector3(0.8, 0.08, 0.1), Vector3(0, 1.8, 0), BLUE)
				_block(Vector3(0.6, 0.08, 0.1), Vector3(0, 1.55, 0), BLUE)
		_:
			push_warning("Missing 3D unit binding: " + id)
			_block(Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), Color.MAGENTA)


func _legs(width: float, depth: float, height: float, rows: int, tint: Color) -> void:
	for side: float in [-1.0, 1.0]:
		for row: int in range(rows):
			_block(Vector3(0.1, height, 0.1), Vector3(side * width, height * 0.5, (row - (rows - 1) * 0.5) * depth * 2), tint, Vector3(0, 0, side * 0.18))


func _block(dimensions: Vector3, at: Vector3, tint: Color, rotation: Vector3 = Vector3.ZERO) -> void:
	_add(_box, dimensions, at, tint, rotation)


func _cyl(dimensions: Vector3, at: Vector3, tint: Color, rotation: Vector3 = Vector3.ZERO) -> void:
	_add(_cylinder, dimensions, at, tint, rotation)


func _sph(dimensions: Vector3, at: Vector3, tint: Color) -> void:
	_add(_sphere, dimensions, at, tint, Vector3.ZERO)


func _add(mesh: Mesh, dimensions: Vector3, at: Vector3, tint: Color, rotation: Vector3) -> void:
	_parts.append({"mesh": mesh, "transform": Transform3D(Basis.from_euler(rotation) * Basis.from_scale(dimensions), at), "color": tint})


func _bake() -> ArrayMesh:
	var merged := SurfaceTool.new()
	merged.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Dictionary in _parts:
		var source: Mesh = part["mesh"]
		var arrays: Array = source.surface_get_arrays(0)
		var colors := PackedColorArray()
		colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
		colors.fill(part["color"])
		arrays[Mesh.ARRAY_COLOR] = colors
		var painted := ArrayMesh.new()
		painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		merged.append_from(painted, 0, part["transform"])
	merged.index()
	return merged.commit()
