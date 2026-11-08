class_name MechBuildingDefinition
extends Resource
## Immutable content rules; no progress, wallet or scene dependencies.

@export var building_id: StringName
@export var display_name: String
@export var footprint: Vector2i = Vector2i.ONE
@export var cost: Dictionary[StringName, int] = {}
@export var construction_seconds: float = 1.0
@export var max_hp: int = 100
@export var capacity_cost: int = 0
@export var power_cost: int = 0
@export var capacity_provided: int = 0
@export var capacity_system_reserved: int = 0
@export var power_provided: int = 0
@export var cooling_cost: int = 0
@export var cooling_provided: int = 0
@export var infectable: bool = false
@export_enum("none", "wind", "solar") var environment_energy: String = "none"
@export var environment_output_multiplier: int = 1
@export var environment_output_cap: int = 0
@export var requires_water: bool = false
@export var is_gate: bool = false
@export_enum("none", "emp", "blast") var trap_kind: String = "none"
@export_range(0.0, 8.0, 0.5) var trigger_radius: float = 2.0
@export var trap_damage: int = 0
@export_range(0.0, 1.0, 0.05) var slow_multiplier: float = 1.0
@export var slow_seconds: float = 0.0
@export var one_shot: bool = true
## Optional independent process recipe (thermal smelter alloy cycles).
@export var alloy_recipe: MechAlloyRecipe
@export var income_per_minute: int = 0
@export var mined_resource: StringName = &""
@export var extraction_per_minute: int = 0
@export var coverage_radius: int = 0
@export_range(0.0, 64.0, 0.5) var sight_radius: float = 0.0
@export var demolition_seconds: float = 3.0
@export_range(0.0, 1.0) var refund_ratio: float = 0.5
@export var is_core: bool = false
@export var buildable: bool = true
## Level chain and in-place upgrade. Level-2+ definitions stay non-buildable and
## are reached only through upgrade_to; tech_level is the tech-center rank.
@export var level: int = 1
@export var tech_level: int = 0
@export var upgrade_to: MechBuildingDefinition
@export var upgrade_cost: Dictionary[StringName, int] = {}
@export var upgrade_seconds: float = 0.0
@export var produced_units: Array[StringName] = []
@export_range(1, 20, 1) var queue_limit: int = 5
## Tower-style autofire; attack_damage 0 marks an unarmed building.
@export var attack_damage: int = 0
@export_range(0.1, 10.0, 0.1) var attack_seconds: float = 1.0
@export_range(0.0, 24.0, 0.5) var attack_range: float = 0.0
@export_range(0.0, 8.0, 0.5) var splash_radius: float = 0.0
@export_range(0.0, 16.0, 0.5) var repair_radius: float = 0.0
@export var repair_rate: float = 0.0
## Radar pre-warning lead in seconds; 0 marks a non-radar sight source.
@export var radar_warning_seconds: float = 0.0


func validation_error() -> String:
	if building_id == &"" or display_name.is_empty():
		return "建筑缺少编号或名称"
	if footprint.x < 1 or footprint.y < 1 or footprint.x > 16 or footprint.y > 16:
		return "建筑占地无效"
	if max_hp < 1 or not MechResources.valid(cost) or mini(capacity_cost, power_cost) < 0:
		return "建筑生命或造价无效"
	if mini(mini(capacity_provided, power_provided), income_per_minute) < 0 or coverage_radius < 0:
		return "建筑供给无效"
	if capacity_system_reserved < 0 or capacity_system_reserved > capacity_provided or mini(cooling_cost, cooling_provided) < 0:
		return "建筑系统预留或冷却无效"
	if alloy_recipe != null and not alloy_recipe.validation_error().is_empty():
		return "建筑合金配方无效"
	if level < 1 or tech_level < 0 or tech_level > 2:
		return "建筑等级或科技等级无效"
	if environment_output_multiplier < 1 or environment_output_cap < 0:
		return "环境电源倍率或上限无效"
	if trap_kind == "emp" and (slow_multiplier <= 0.0 or slow_seconds <= 0.0):
		return "电磁陷阱减速参数无效"
	if trap_kind == "blast" and trap_damage <= 0:
		return "爆破地雷伤害无效"
	if upgrade_to != null:
		if upgrade_seconds <= 0.0 or not MechResources.valid(upgrade_cost) or upgrade_cost.is_empty():
			return "建筑升级费用或工期无效"
		if upgrade_to.footprint != footprint or upgrade_to.level <= level:
			return "建筑升级目标占地或等级无效"
	if not is_finite(sight_radius) or sight_radius < 0.0 or sight_radius > 64.0:
		return "建筑视野半径无效"
	if not is_finite(splash_radius) or splash_radius < 0.0 or not is_finite(repair_radius) or repair_radius < 0.0 or repair_rate < 0.0:
		return "建筑范围或维修参数无效"
	if radar_warning_seconds < 0.0:
		return "雷达预警提前量无效"
	if extraction_per_minute < 0 or (mined_resource != &"" and not MechResources.mineable(mined_resource)):
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


func supply_recovery() -> bool:
	return capacity_provided > capacity_system_reserved or power_provided > 0 or cooling_provided > 0 or coverage_radius > 0 or environment_energy != "none"


func snapshot() -> Dictionary:
	return {"building_id": building_id, "name": display_name, "footprint": footprint,
		"cost": MechResources.copy(cost), "construction_seconds": construction_seconds, "max_hp": max_hp,
		"capacity_cost": capacity_cost, "power_cost": power_cost,
		"capacity_provided": capacity_provided, "capacity_system_reserved": capacity_system_reserved,
		"power_provided": power_provided, "cooling_cost": cooling_cost, "cooling_provided": cooling_provided,
		"income_per_minute": income_per_minute, "mined_resource": mined_resource,
		"extraction_per_minute": extraction_per_minute, "is_core": is_core, "buildable": buildable,
		"produced_units": produced_units.duplicate(), "queue_limit": queue_limit,
		"attack_damage": attack_damage, "attack_seconds": attack_seconds, "attack_range": attack_range,
		"splash_radius": splash_radius, "sight_radius": sight_radius, "coverage_radius": coverage_radius,
		"repair_radius": repair_radius, "repair_rate": repair_rate,
		"radar_warning_seconds": radar_warning_seconds,
		"environment_energy": environment_energy, "infectable": infectable,
		"environment_output_multiplier": environment_output_multiplier,
		"environment_output_cap": environment_output_cap, "requires_water": requires_water,
		"is_gate": is_gate, "trap_kind": trap_kind, "trigger_radius": trigger_radius,
		"trap_damage": trap_damage, "slow_multiplier": slow_multiplier,
		"slow_seconds": slow_seconds, "one_shot": one_shot,
		"level": level, "tech_level": tech_level,
		"upgrade_target": upgrade_to.building_id if upgrade_to != null else &"",
		"upgrade_target_name": upgrade_to.display_name if upgrade_to != null else "",
		"upgrade_cost": MechResources.copy(upgrade_cost),
		"upgrade_seconds": upgrade_seconds,
		"can_upgrade": upgrade_to != null,
		"alloy_recipe": alloy_recipe.snapshot() if alloy_recipe != null else {}}
