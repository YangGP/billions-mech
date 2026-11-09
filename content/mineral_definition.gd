@tool
class_name MechMineralDefinition
extends Resource
## 仅定义初始地图内容。余量与归属属于模拟层。

@export var mineral_id: StringName
@export var cell: Vector2i
@export_enum("metal_ore", "fuel", "crystals") var resource_kind: String = "metal_ore"
@export_range(1, 1000000, 1) var amount: int = 400


## 导出初始数据快照（assigned_to 为模拟层占位字段）。
func snapshot() -> Dictionary:
	return {"mineral_id": mineral_id, "cell": cell, "resource_kind": StringName(resource_kind),
		"remaining": amount, "initial_amount": amount, "assigned_to": 0}
