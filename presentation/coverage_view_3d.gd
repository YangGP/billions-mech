class_name MechCoverageView3D
extends Node3D
## 建造时的供电覆盖；只显示快照中已探索的覆盖格。

var _batches := MechInstanceBatches3D.new()
var _tile := BoxMesh.new()


func _ready() -> void:
	add_child(_batches)
	_tile.size = Vector3(0.96, 0.015, 0.96)


func present_map(map_state: Dictionary) -> void:
	var dimensions: Vector2i = map_state["dimensions"]
	var mask: PackedByteArray = map_state["coverage"]
	var groups: Dictionary = {}
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			if mask[y * dimensions.x + x] != 0:
				MechInstanceBatches3D.append(groups, "coverage_%d_%d" % [x / 16, y / 16], _tile,
					Transform3D(Basis.IDENTITY, Vector3(x + 0.5, 0.025, y + 0.5)), Color("4e9b84"))
	var fog: MechFogView3D = get_parent().get_node("Fog")
	_batches.present(groups, fog.material())
