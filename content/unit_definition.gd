class_name MechUnitDefinition
extends Resource
## First playable unit. All balance data stays outside the simulation systems.

@export var unit_id: StringName = &"sentinel"
@export var display_name: String = "卫兵"
@export var cost: Vector4i = Vector4i(20, 0, 0, 0)
@export var production_seconds: float = 20.0
@export var capacity_cost: int = 1
@export var max_hp: int = 100
@export var damage: int = 10
@export var attack_seconds: float = 0.8
@export var attack_range: float = 4.0
@export var acquisition_range: float = 6.0
@export var move_speed: float = 2.5


func validation_error() -> String:
	if unit_id == &"" or display_name.is_empty() or not MechResources.valid(cost):
		return "单位编号、名称或造价无效"
	if max_hp <= 0 or damage <= 0 or capacity_cost < 0:
		return "单位生命、伤害或占容无效"
	for value: float in [production_seconds, attack_seconds, attack_range, acquisition_range, move_speed]:
		if not is_finite(value) or value <= 0.0:
			return "单位时间、射程或移速无效"
	if acquisition_range < attack_range:
		return "单位索敌范围不可小于射程"
	return ""


func snapshot() -> Dictionary:
	return {"unit_id": unit_id, "name": display_name, "cost": cost,
		"production_seconds": production_seconds, "capacity_cost": capacity_cost,
		"max_hp": max_hp, "damage": damage, "attack_range": attack_range}
