class_name MechAlloyProcessing
extends RefCounted
## 热能冶炼周期。燃料在开局一次性原子扣款；金属矿开局可选投入一次。
## 已开始的周期不再接收投入，暂停或失去覆盖也不退款；
## 只有主动拆除才退还未完成的周期投入。
## 周期完成且燃料充足时在同一 tick 内开启下一周期，
## 保证有燃料的冶炼站持续发电而不是隔 tick 断电。

## 开局至今是否产出过合金（用于进度门槛判定）。
var ever_produced_alloy: bool = false
var produced_alloy: int = 0


## 清空产出统计。
func reset() -> void:
	ever_produced_alloy = false
	produced_alloy = 0


## 尝试开启冶炼周期：一次性扣除燃料，金属充足时一并投入；任一不足则不开。
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


## 推进所有冶炼站一个周期；返回是否有状态变化（触发快照刷新）。
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
		if building.processing_power != recipe.power_output:
			building.processing_power = recipe.power_output
			changed = true
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
		# 待升级的建筑先拿到新定义，避免再按旧配方开新周期。
		if building.upgrade_target == null and _try_start(building, recipe, economy, hz):
			pass
		changed = true
	return changed
