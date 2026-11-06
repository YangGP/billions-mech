class_name MechBuildingDefinition
extends Resource
## Immutable content rules; no progress, wallet or scene dependencies.

@export var building_id: StringName
@export var display_name: String
@export var footprint: Vector2i = Vector2i.ONE
@export var cost: Vector4i = Vector4i.ZERO
@export var construction_seconds: float = 1.0
@export var max_hp: int = 100
@export var capacity_cost: int = 0
@export var power_cost: int = 0
@export var capacity_provided: int = 0
@export var power_provided: int = 0
@export var income_per_minute: int = 0
@export var mined_resource: StringName = &""
@export var extraction_per_minute: int = 0
@export var coverage_radius: int = 0
@export var demolition_seconds: float = 3.0
@export_range(0.0, 1.0) var refund_ratio: float = 0.5
@export var is_core: bool = false
@export var buildable: bool = true
@export var produced_unit: StringName = &""
@export_range(1, 20, 1) var queue_limit: int = 5
## Tower-style autofire; attack_damage 0 marks an unarmed building.
@export var attack_damage: int = 0
@export_range(0.1, 10.0, 0.1) var attack_seconds: float = 1.0
@export_range(0.0, 24.0, 0.5) var attack_range: float = 0.0


func validation_error() -> String:
	if building_id == &"" or display_name.is_empty():
		return "建筑缺少编号或名称"
	if footprint.x < 1 or footprint.y < 1 or footprint.x > 16 or footprint.y > 16:
		return "建筑占地无效"
	if max_hp < 1 or not MechResources.valid(cost) or mini(capacity_cost, power_cost) < 0:
		return "建筑生命或造价无效"
	if mini(mini(capacity_provided, power_provided), income_per_minute) < 0 or coverage_radius < 0:
		return "建筑供给无效"
	if extraction_per_minute < 0 or (mined_resource != &"" and MechResources.KEYS.find(mined_resource) < 1):
		return "采集类型或产率无效"
	if (mined_resource == &"") != (extraction_per_minute == 0):
		return "采集站类型与产率须同时配置"
	if queue_limit < 1:
		return "生产队列长度无效"
	if attack_damage < 0 or (attack_damage > 0 and (attack_seconds <= 0.0 or attack_range <= 0.0)):
		return "建筑攻击参数无效"
	if not is_finite(construction_seconds) or construction_seconds <= 0.0 or not is_finite(demolition_seconds) or demolition_seconds <= 0.0:
		return "建筑工程时间无效"
	if not is_finite(refund_ratio) or refund_ratio < 0.0 or refund_ratio > 1.0 or (is_core and buildable):
		return "建筑退款或核心规则无效"
	return ""


func snapshot() -> Dictionary:
	return {"building_id": building_id, "name": display_name, "footprint": footprint,
		"cost": cost, "construction_seconds": construction_seconds, "max_hp": max_hp,
		"capacity_cost": capacity_cost, "power_cost": power_cost,
		"capacity_provided": capacity_provided, "power_provided": power_provided,
		"income_per_minute": income_per_minute, "mined_resource": mined_resource,
		"extraction_per_minute": extraction_per_minute, "is_core": is_core, "buildable": buildable,
		"produced_unit": produced_unit, "queue_limit": queue_limit,
		"attack_damage": attack_damage, "attack_seconds": attack_seconds, "attack_range": attack_range}
