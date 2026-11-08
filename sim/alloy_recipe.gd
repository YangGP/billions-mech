class_name MechAlloyRecipe
extends Resource
## Immutable thermal-smelter cycle. A cycle starts with an atomic fuel purchase;
## metal is optional at start and cannot be added mid-cycle.

@export var recipe_id: StringName = &"thermal_smelter_basic"
@export var cycle_seconds: float = 15.0
@export var fuel_cost: int = 2
@export var metal_cost: int = 1
@export var alloy_output: int = 1
@export var power_output: int = 30


func validation_error() -> String:
	if recipe_id == &"" or cycle_seconds <= 0.0 or fuel_cost < 1 or metal_cost < 0 or alloy_output < 1 or power_output < 0:
		return "合金配方无效"
	return ""


func snapshot() -> Dictionary:
	return {"recipe_id": recipe_id, "cycle_seconds": cycle_seconds,
		"fuel_cost": fuel_cost, "metal_cost": metal_cost,
		"alloy_output": alloy_output, "power_output": power_output}
