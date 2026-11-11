class_name MechUnitDefinition
extends Resource
## 首个可玩单位。全部平衡数据保持在模拟系统之外。

@export var unit_id: StringName = &"sentinel"
@export var display_name: String = "卫兵"
@export var cost: Dictionary[StringName, int] = {&"coins": 20}
@export var production_seconds: float = 20.0
@export var capacity_cost: int = 1
@export var max_hp: int = 100
@export var damage: int = 10
@export var attack_seconds: float = 0.8
@export var attack_range: float = 4.0
## 主动索敌范围，不得小于 attack_range。
@export var acquisition_range: float = 6.0
@export var move_speed: float = 2.5
@export_range(0.5, 64.0, 0.5) var sight_radius: float = 7.0
## 主武器命中时的范围伤害半径；0 表示单体。
@export var splash_radius: float = 0.0
## 近战横扫的额外目标数；0 表示单体。
@export var cleave_targets: int = 0
@export_range(0.0, 1.0, 0.05) var cleave_secondary_ratio: float = 0.6
## 主武器射程；0 表示直接使用 attack_range。
@export var primary_range: float = 0.0
## 第二主武器；伤害为 0 表示没有第二主武器。
@export var secondary_damage: int = 0
@export var secondary_attack_seconds: float = 0.0
@export var secondary_range: float = 0.0
@export var secondary_splash_radius: float = 0.0
## 第二主武器只在目标距离大于该值且不超过 secondary_range 时使用。
@export var weapon_switch_range: float = 3.0


## 校验全部字段。返回空字符串表示通过，否则返回中文错误原因。
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
	if not is_finite(sight_radius) or sight_radius <= 0.0 or sight_radius > 64.0:
		return "单位视野半径无效"
	if not is_finite(splash_radius) or splash_radius < 0.0:
		return "单位溅射半径无效"
	if cleave_targets < 0 or cleave_targets > 4 or not is_finite(cleave_secondary_ratio) \
			or cleave_secondary_ratio < 0.0 or cleave_secondary_ratio > 1.0:
		return "单位横扫参数无效"
	if not is_finite(primary_range) or primary_range < 0.0:
		return "单位主武器射程无效"
	if primary_range > 0.0 and primary_range > attack_range:
		return "单位主武器射程不可大于总射程"
	if secondary_damage < 0 or not is_finite(secondary_attack_seconds) \
			or not is_finite(secondary_range) or not is_finite(secondary_splash_radius) \
			or not is_finite(weapon_switch_range):
		return "单位第二主武器参数无效"
	if secondary_damage > 0:
		if secondary_attack_seconds <= 0.0 or secondary_range <= 0.0 or weapon_switch_range <= 0.0:
			return "单位第二主武器缺少间隔或射程"
		if secondary_range < weapon_switch_range or secondary_range > attack_range:
			return "单位第二主武器射程无效"
		if acquisition_range < secondary_range:
			return "单位索敌范围不可小于第二主武器射程"
	return ""


## 导出普通字典快照（供 HUD 使用）。
func snapshot() -> Dictionary:
	return {"unit_id": unit_id, "name": display_name, "cost": MechResources.copy(cost),
		"production_seconds": production_seconds, "capacity_cost": capacity_cost,
		"max_hp": max_hp, "damage": damage, "attack_range": attack_range,
		"splash_radius": splash_radius, "cleave_targets": cleave_targets,
		"primary_range": primary_range if primary_range > 0.0 else attack_range,
		"secondary_damage": secondary_damage, "secondary_attack_seconds": secondary_attack_seconds,
		"secondary_range": secondary_range, "secondary_splash_radius": secondary_splash_radius,
		"weapon_switch_range": weapon_switch_range}
