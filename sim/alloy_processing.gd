class_name MechAlloyProcessing
extends RefCounted
## Thermal-smelter cycles. Fuel is paid atomically at start; metal is optional
## once at start. A started cycle never takes more input and never refunds on
## pause/coverage loss. Only an active demolition refunds the unspent cycle.
## A completed cycle starts the next one in the same tick when fuel remains, so
## a fueled smelter keeps continuous power instead of one-tick gaps.

var ever_produced_alloy: bool = false
var produced_alloy: int = 0


func reset() -> void:
	ever_produced_alloy = false
	produced_alloy = 0


func _try_start(building: MechBuildingState, recipe: MechAlloyRecipe, economy: MechEconomySystem, hz: int) -> bool:
	if building.upgrade_target != null:
		return false
	var fuel_available: int = int(economy.balance().get(&"fuel", 0))
	if fuel_available < recipe.fuel_cost:
		return false
	var paid: Dictionary[StringName, int] = {}
	paid[&"fuel"] = recipe.fuel_cost
	if int(economy.balance().get(&"metal_ore", 0)) >= recipe.metal_cost:
		paid[&"metal_ore"] = recipe.metal_cost
	if not economy.try_spend(paid):
		return false
	building.processing_active = true
	building.processing_elapsed = 0
	building.processing_total = maxi(1, ceili(recipe.cycle_seconds * hz))
	building.processing_paid = MechResources.copy(paid)
	building.processing_power = recipe.power_output
	return true


func advance(buildings: Array[MechBuildingState], economy: MechEconomySystem, hz: int) -> bool:
	var changed: bool = false
	for building: MechBuildingState in buildings:
		var recipe: MechAlloyRecipe = building.definition.alloy_recipe
		if recipe == null or building.phase == MechBuildingState.Phase.RUINED:
			continue
		if not building.operating():
			if building.processing_power != 0:
				building.processing_power = 0
				changed = true
			continue
		if not building.processing_active:
			if _try_start(building, recipe, economy, hz):
				changed = true
			elif building.processing_power != 0:
				building.processing_power = 0
				changed = true
			continue
		building.processing_power = recipe.power_output
		building.processing_elapsed = mini(building.processing_elapsed + 1, building.processing_total)
		if building.processing_elapsed < building.processing_total:
			continue
		if int(building.processing_paid.get(&"metal_ore", 0)) >= recipe.metal_cost:
			economy.credit({&"alloy": recipe.alloy_output})
			produced_alloy += recipe.alloy_output
			ever_produced_alloy = true
		building.processing_active = false
		building.processing_elapsed = 0
		building.processing_total = 0
		building.processing_paid = MechResources.empty()
		building.processing_power = 0
		# A pending upgrade gets the next definition before any old-recipe cycle.
		if building.upgrade_target == null and _try_start(building, recipe, economy, hz):
			pass
		changed = true
	return changed
