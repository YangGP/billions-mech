class_name MechInstanceBatches3D
extends Node3D
## 仅集中管理显示实例，无实体逻辑/逐实例节点。批次键由模型和空间块组成。

var _batches: Dictionary = {}


func present(groups: Dictionary, shared_material: Material) -> void:
	for key: String in _batches:
		_batches[key].visible = groups.has(key)
	for key: String in groups:
		var data: Dictionary = groups[key]
		var transforms: Array = data["transforms"]
		var colors: Array = data["colors"]
		if not _batches.has(key):
			var node := MultiMeshInstance3D.new()
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.use_colors = true
			node.multimesh.mesh = data["mesh"]
			node.material_override = shared_material
			# 首阶段关闭投影阴影，避免未探索高模型的阴影泄漏。
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_batches[key] = node
		var node: MultiMeshInstance3D = _batches[key]
		var multi: MultiMesh = node.multimesh
		if multi.instance_count < transforms.size():
			multi.instance_count = maxi(8, nearest_po2(transforms.size()))
		multi.visible_instance_count = transforms.size()
		for index: int in range(transforms.size()):
			multi.set_instance_transform(index, transforms[index])
			multi.set_instance_color(index, colors[index])
		node.visible = true


func clear() -> void:
	for node: MultiMeshInstance3D in _batches.values():
		node.free()
	_batches.clear()


static func append(groups: Dictionary, key: String, mesh: Mesh, transform: Transform3D, color: Color) -> void:
	if not groups.has(key):
		groups[key] = {"mesh": mesh, "transforms": [], "colors": []}
	groups[key]["transforms"].append(transform)
	groups[key]["colors"].append(color)
