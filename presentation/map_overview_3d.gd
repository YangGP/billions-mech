@tool
extends Node3D
## 地图编辑预览，显示真实地图数据与全图地标；不创建模拟或修改正常游戏迷雾。

@export var preview_map: MechMapDefinition = preload("res://content/maps/development_basin_128.tres"):
	set(value):
		preview_map = value
		if is_inside_tree():
			call_deferred("_refresh")
@export_tool_button("刷新三维地图预览") var refresh: Callable = _refresh

var _generated: Node3D
var _catalog := MechModelCatalog3D.new()


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	if not is_inside_tree() or preview_map == null or not preview_map.validation_error().is_empty():
		return
	if is_instance_valid(_generated):
		_generated.free()
	_generated = Node3D.new()
	add_child(_generated)
	var fog := MechFogView3D.new()
	fog.name = "Fog"
	_generated.add_child(fog)
	var terrain := MechTerrainView3D.new()
	_generated.add_child(terrain)
	var map: Dictionary = preview_map.terrain_snapshot()
	var cells := PackedByteArray()
	cells.resize(preview_map.dimensions.x * preview_map.dimensions.y)
	cells.fill(MechVisionSystem.State.VISIBLE)
	var vision: Dictionary = {"dimensions": preview_map.dimensions, "cells": cells, "revision": 0}
	terrain.present_map(map)
	fog.present(vision, 0, map["outline"])
	terrain.present_vision(vision)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	var brain := MeshInstance3D.new()
	brain.mesh = _catalog.model({"kind": &"mainbrain", "is_building": true, "footprint": preview_map.mainbrain_footprint})
	brain.material_override = material
	brain.position = Vector3(preview_map.mainbrain_origin.x + preview_map.mainbrain_footprint.x * 0.5, 0,
		preview_map.mainbrain_origin.y + preview_map.mainbrain_footprint.y * 0.5)
	_generated.add_child(brain)
	var deposits := MechInstanceBatches3D.new()
	_generated.add_child(deposits)
	var mineral := PrismMesh.new()
	mineral.size = Vector3(0.7, 0.55, 0.7)
	var groups: Dictionary = {}
	for entry: Dictionary in map["minerals"]:
		var tint: Color = {&"metal_ore": Color("c4cdd2"), &"fuel": Color("d8b875"), &"crystals": Color("ae94e0")}.get(entry["resource_kind"], Color.WHITE)
		MechInstanceBatches3D.append(groups, "minerals", mineral, Transform3D(Basis.IDENTITY, Vector3(entry["cell"].x + 0.5, 0.3, entry["cell"].y + 0.5)), tint)
	deposits.present(groups, material)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	_generated.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0c1923")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bbcbd1")
	environment.environment.ambient_light_energy = 0.65
	_generated.add_child(environment)
	var projected: Rect2 = MechIsoGeometry.map_bounds(preview_map.dimensions, preview_map.outline())
	var logical_center: Vector2 = MechIsoGeometry.unproject(projected.get_center())
	var center := Vector3(logical_center.x, 0, logical_center.y)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var span: Vector2 = projected.size / (32.0 * sqrt(2.0))
	camera.size = maxf(span.y, span.x * viewport_size.y / maxf(1.0, viewport_size.x)) * 1.1
	camera.far = 1000
	camera.position = center + MechMapCamera3D.VIEW_BACK.normalized() * 300.0
	_generated.add_child(camera)
	camera.look_at(center)
	camera.current = true
