@tool
class_name MechMineralDefinition
extends Resource
## Initial map content only. Remaining stock and ownership belong to sim.

@export var mineral_id: StringName
@export var cell: Vector2i
@export_enum("metal_ore", "fuel", "crystals") var resource_kind: String = "metal_ore"
@export_range(1, 1000000, 1) var amount: int = 400


func snapshot() -> Dictionary:
	return {"mineral_id": mineral_id, "cell": cell, "resource_kind": StringName(resource_kind),
		"remaining": amount, "initial_amount": amount, "assigned_to": 0}
