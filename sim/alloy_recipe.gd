class_name MechAlloyRecipe
extends Resource
## 热能冶炼站的不可变冶炼周期。周期以一次性碳晶扣款开局；
## 金属矿在开局时可选投入，周期中途不可追加。

@export var recipe_id: StringName = &"thermal_smelter_basic"
## 单个冶炼周期的时长（秒）。
@export var cycle_seconds: float = 15.0
## 周期开局一次性扣除的碳晶数。
@export var fuel_cost: int = 2
## 周期开局可选投入的金属矿数。
@export var metal_cost: int = 1
## 周期产出的合金数。
@export var alloy_output: int = 1
## 冶炼同时输出的电力（燃烧发电）。
@export var power_output: int = 30


## 返回配置错误描述；空字符串表示有效。
func validation_error() -> String:
	if recipe_id == &"" or cycle_seconds <= 0.0 or fuel_cost < 1 or metal_cost < 0 or alloy_output < 1 or power_output < 0:
		return "合金配方无效"
	return ""


func snapshot() -> Dictionary:
	return {"recipe_id": recipe_id, "cycle_seconds": cycle_seconds,
		"fuel_cost": fuel_cost, "metal_cost": metal_cost,
		"alloy_output": alloy_output, "power_output": power_output}
