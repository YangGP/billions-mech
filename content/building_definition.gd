class_name MechBuildingDefinition
extends Resource
## 不可变的内容规则；不含进度、钱包或场景依赖。

@export var building_id: StringName
@export var display_name: String
@export var footprint: Vector2i = Vector2i.ONE
@export var cost: Dictionary[StringName, int] = {}
@export var construction_seconds: float = 1.0
@export var max_hp: int = 100
## 建成后持续占用的算力容量。
@export var capacity_cost: int = 0
@export var power_cost: int = 0
## 提供的算力容量。
@export var capacity_provided: int = 0
## 容量中系统预留的部分，不计入玩家可用容量。
@export var capacity_system_reserved: int = 0
@export var power_provided: int = 0
@export var cooling_cost: int = 0
@export var cooling_provided: int = 0
## 可被敌方感染转化。
@export var infectable: bool = false
## 环境能源类型：none（无）/wind（风力）/solar（太阳能）。
@export_enum("none", "wind", "solar") var environment_energy: String = "none"
## 环境能源输出倍率（不小于 1）。
@export var environment_output_multiplier: int = 1
## 环境能源输出上限（0 表示不设上限）。
@export var environment_output_cap: int = 0
@export var requires_water: bool = false
@export var is_gate: bool = false
@export_range(0.0, 1.0, 0.05) var slow_multiplier: float = 1.0
@export var slow_seconds: float = 0.0
## 可选的独立工艺配方（热熔炉的合金循环）。
@export var alloy_recipe: MechAlloyRecipe
@export var income_per_minute: int = 0
## 采集的资源类型（空表示非采集站）。
@export var mined_resource: StringName = &""
@export var extraction_per_minute: int = 0
## 覆盖半径（格，0 表示不提供覆盖）。
@export var coverage_radius: int = 0
## 普通建筑完工且连通后提供基础视野，专业建筑可覆盖此值。
@export_range(0.0, 64.0, 0.5) var sight_radius: float = 4.0
## 正常拆除命令立即执行；保留字段供旧内容读取。
@export var demolition_seconds: float = 0.0
@export_range(0.0, 1.0) var refund_ratio: float = 0.5
@export var is_core: bool = false
@export var buildable: bool = true
## 等级链与原地升级。2 级及以上的定义保持不可建造，只能经 upgrade_to 达成；
## tech_level 是科技中心的等级。
@export var level: int = 1
@export var tech_level: int = 0
@export var required_tech_level: int = 0
@export var required_mainbrain_level: int = 0
@export var upgrade_to: MechBuildingDefinition
@export var upgrade_cost: Dictionary[StringName, int] = {}
@export var upgrade_seconds: float = 0.0
@export var produced_units: Array[StringName] = []
@export_range(1, 20, 1) var queue_limit: int = 5
## 塔式自动开火；attack_damage 为 0 表示无武装建筑。
@export var attack_damage: int = 0
@export_range(0.1, 10.0, 0.1) var attack_seconds: float = 1.0
@export_range(0.0, 24.0, 0.5) var attack_range: float = 0.0
@export_range(0.0, 8.0, 0.5) var splash_radius: float = 0.0
## 雷达预警提前量（秒）；0 表示非雷达视野源。
@export var radar_warning_seconds: float = 0.0
## 可驻防单位数。
@export var garrison_capacity: int = 0
## 驻防单位带来的射程加成。
@export var garrison_range_bonus: float = 0.0


## 是否属于墙类建筑（装甲墙/合金墙）；敌人系统对墙有特殊的攻击与寻路规则。
func is_wall_like() -> bool:
	return building_id in [&"armored_wall", &"alloy_wall"]


## 校验全部字段。返回空字符串表示通过，否则返回中文错误原因。
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
	if level < 1 or tech_level < 0 or tech_level > 3 or required_tech_level < 0 or required_tech_level > 3 or required_mainbrain_level < 0 or required_mainbrain_level > 3:
		return "建筑等级或科技等级无效"
	if environment_output_multiplier < 1 or environment_output_cap < 0:
		return "环境电源倍率或上限无效"
	if upgrade_to != null:
		if upgrade_seconds <= 0.0 or not MechResources.valid(upgrade_cost) or upgrade_cost.is_empty():
			return "建筑升级费用或工期无效"
		if upgrade_to.footprint != footprint or upgrade_to.level <= level:
			return "建筑升级目标占地或等级无效"
	if not is_finite(sight_radius) or sight_radius < 0.0 or sight_radius > 64.0:
		return "建筑视野半径无效"
	if not is_finite(splash_radius) or splash_radius < 0.0:
		return "建筑范围参数无效"
	if radar_warning_seconds < 0.0:
		return "雷达预警提前量无效"
	if garrison_capacity < 0:
		return "驻防容量无效"
	if extraction_per_minute < 0 or (mined_resource != &"" and not MechResources.mineable(mined_resource)):
		return "采集类型或产率无效"
	if (mined_resource == &"") != (extraction_per_minute == 0):
		return "采集站类型与产率须同时配置"
	if queue_limit < 1:
		return "生产队列长度无效"
	if attack_damage < 0 or (attack_damage > 0 and (attack_seconds <= 0.0 or attack_range <= 0.0)):
		return "建筑攻击参数无效"
	if not is_finite(construction_seconds) or construction_seconds <= 0.0 or not is_finite(demolition_seconds) or demolition_seconds < 0.0:
		return "建筑工程时间无效"
	if not is_finite(refund_ratio) or refund_ratio < 0.0 or refund_ratio > 1.0 or (is_core and buildable):
		return "建筑退款或核心规则无效"
	return ""


## 是否为供给恢复设施（提供容量/电力/冷却/覆盖/环境能源）。
## 算力超载时仅允许建造零占容的此类建筑。
func supply_recovery() -> bool:
	return capacity_provided > capacity_system_reserved or power_provided > 0 or cooling_provided > 0 or coverage_radius > 0 or environment_energy != "none"


## 导出全部关键字段的普通字典快照（供 HUD 与外部读取）。
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
		"radar_warning_seconds": radar_warning_seconds,
		"garrison_capacity": garrison_capacity, "garrison_range_bonus": garrison_range_bonus,
		"environment_energy": environment_energy, "infectable": infectable,
		"environment_output_multiplier": environment_output_multiplier,
		"environment_output_cap": environment_output_cap, "requires_water": requires_water,
		"is_gate": is_gate, "slow_multiplier": slow_multiplier, "slow_seconds": slow_seconds,
		"level": level, "tech_level": tech_level,
		"required_tech_level": required_tech_level,
		"required_mainbrain_level": required_mainbrain_level,
		"upgrade_target": upgrade_to.building_id if upgrade_to != null else &"",
		"upgrade_target_name": upgrade_to.display_name if upgrade_to != null else "",
		"upgrade_cost": MechResources.copy(upgrade_cost),
		"upgrade_seconds": upgrade_seconds,
		"can_upgrade": upgrade_to != null,
		"alloy_recipe": alloy_recipe.snapshot() if alloy_recipe != null else {}}
