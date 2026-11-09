class_name MechEnemyDefinition
extends Resource
## 威胁方战斗数据（values.md 	11）；行为规则在 waves-enemies.md 	8。

@export var enemy_id: StringName = &"builder"
@export var display_name: String = "建造者"
@export var max_hp: int = 30
@export var damage: int = 6
## 0 = 对建筑伤害与常规伤害相同；architecture.md 	7 伤害修正表的平铺形式。
@export var damage_vs_building: int = 0
@export var attack_seconds: float = 1.0
@export var attack_range: float = 1.0
@export var move_speed: float = 1.5
@export var vision_radius: float = 6.0
## 波次预算的威胁单价，用于按预算凑敌。
@export var threat_cost: float = 1.0
## 优先攻击建筑而非单位。
@export var prefers_buildings: bool = false
## false = 游荡型：从不向主脑行军；以缓慢的 TAB 式挪动待机，
## 闻声聚集，被发现或受击时交战。
@export var marches_to_core: bool = true
## 仅用于未接战时的游荡/闻声聚集；战斗追击仍用 move_speed。
@export_range(0.1, 1.0, 0.05) var wandering_speed_ratio: float = 1.0
## 电磁庇护（原型）：处于该单位 shelter_radius 内的敌方受到的所有来源
## 伤害降低；击杀该单位后庇护解除。
@export var shelter_radius: float = 0.0
@export_range(0.0, 1.0, 0.01) var shelter_reduction: float = 0.5
## 穿墙（原型）：以正常速度越过装甲墙；其他建筑与障碍地形仍然阻挡
## （一路攻击开道）。
@export var passes_walls: bool = false


## 校验全部字段。返回空字符串表示通过，否则返回中文错误原因。
func validation_error() -> String:
	if enemy_id == &"" or display_name.is_empty():
		return "敌种编号或名称无效"
	if max_hp <= 0 or damage <= 0:
		return "敌种生命或伤害无效"
	if damage_vs_building < 0:
		return "敌种对建筑伤害无效"
	for value: float in [attack_seconds, attack_range, move_speed, vision_radius]:
		if not is_finite(value) or value <= 0.0:
			return "敌种时间、射程或移速无效"
	if threat_cost <= 0.0:
		return "敌种威胁单价无效"
	if not is_finite(wandering_speed_ratio) or wandering_speed_ratio < 0.1 or wandering_speed_ratio > 1.0:
		return "游荡速度倍率无效"
	if shelter_radius < 0.0 or not is_finite(shelter_radius):
		return "敌种庇护半径无效"
	if shelter_radius > 0.0 and (not is_finite(shelter_reduction) or shelter_reduction <= 0.0 or shelter_reduction > 1.0):
		return "敌种庇护减伤比例无效"
	return ""


## 对建筑的实际伤害；damage_vs_building 为 0 时退回 damage。
func building_damage() -> int:
	return damage_vs_building if damage_vs_building > 0 else damage


## 导出全部关键字段的普通字典快照。
func snapshot() -> Dictionary:
	return {"enemy_id": enemy_id, "name": display_name, "max_hp": max_hp,
		"damage": damage, "damage_vs_building": building_damage(),
		"attack_seconds": attack_seconds, "attack_range": attack_range,
		"move_speed": move_speed, "vision_radius": vision_radius,
		"threat_cost": threat_cost, "prefers_buildings": prefers_buildings,
		"marches_to_core": marches_to_core, "wandering_speed_ratio": wandering_speed_ratio, "shelter_radius": shelter_radius,
		"shelter_reduction": shelter_reduction, "passes_walls": passes_walls}
