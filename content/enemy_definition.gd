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
## 普通池各阶段相对权重；精英改用出场阶段、波序及存活配额。
@export var stage_weights := Vector3i(35, 55, 55)
@export var elite: bool = false
@export_range(1, 6, 1) var max_alive: int = 6
@export_range(1, 3, 1) var minimum_stage: int = 1
@export_range(1, 32, 1) var first_wave: int = 1
@export var charge_bonus: float = 0.0
@export var charge_linger_seconds: float = 1.0
@export var ignores_rough: bool = false
@export var prefers_towers: bool = false
@export var splash_radius: float = 0.0
@export var scavenge_radius: float = 0.0
## 拾荒护甲池：附近同阵营单位死亡时，按死亡单位最大生命值的该比例累积护甲。
@export var scavenge_armor_ratio: float = 0.5
## 护甲池上限（点）。
@export var scavenge_max_armor: float = 300.0
@export var jam_range: float = 0.0
@export var jam_seconds: float = 4.0
@export var jam_immunity_seconds: float = 8.0
@export var jam_cooldown_seconds: float = 14.0
@export var boost_seconds: float = 6.0
@export var boost_speed: float = 0.0
## 优先攻击建筑而非单位。
@export var prefers_buildings: bool = false
## false = 游荡型：从不向主脑行军；以缓慢的 TAB 式挪动待机，
## 闻声聚集，被发现或受击时交战。
@export var marches_to_core: bool = true
## 仅用于未接战时的游荡/闻声聚集；战斗追击仍用 move_speed。
@export_range(0.1, 1.0, 0.05) var wandering_speed_ratio: float = 1.0
## 电磁偏转场：处于该单位 shelter_radius 内的敌方受到的所有来源
## 伤害降低；击杀该单位后庇护解除。
@export var shelter_radius: float = 0.0
@export var shelter_self: bool = false
@export_range(0.0, 1.0, 0.01) var shelter_reduction: float = 0.5
## 长足者穿墙：以正常速度越过墙；其他建筑与障碍地形仍然阻挡
## （一路攻击开道）。
@export var passes_walls: bool = false
## 受玩家攻击时的闪避概率（0–1）；陷阱等非攻击伤害不判定。
@export_range(0.0, 1.0, 0.01) var evasion_chance: float = 0.0
## 死亡时以死亡位置为中心，为周围同阵营敌人附加狂暴。
@export var frenzy_radius: float = 0.0
@export var frenzy_seconds: float = 6.0
## 狂暴期的移速加成比例（0.2 = +20%）。
@export_range(0.0, 2.0, 0.01) var frenzy_speed_bonus: float = 0.2
## 狂暴期的伤害加成比例（0.1 = +10%）。
@export_range(0.0, 2.0, 0.01) var frenzy_damage_bonus: float = 0.1


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
	if not is_finite(threat_cost) or stage_weights.x < 0 or stage_weights.y < 0 or stage_weights.z < 0:
		return "敌种预算或阶段权重无效"
	if max_alive < 1 or max_alive > 6 or minimum_stage < 1 or minimum_stage > 3 or first_wave < 1:
		return "敌种配额或出场阶段无效"
	for value: float in [charge_bonus, charge_linger_seconds, splash_radius, scavenge_radius, jam_range, boost_speed, frenzy_radius]:
		if not is_finite(value) or value < 0.0:
			return "敌种特殊距离或速度无效"
	for value: float in [jam_seconds, jam_immunity_seconds, jam_cooldown_seconds, boost_seconds, frenzy_seconds]:
		if not is_finite(value) or value <= 0.0:
			return "敌种特殊计时无效"
	if not is_finite(frenzy_speed_bonus) or frenzy_speed_bonus < 0.0 or not is_finite(frenzy_damage_bonus) or frenzy_damage_bonus < 0.0:
		return "敌种狂暴加成无效"
	if scavenge_armor_ratio <= 0.0 or not is_finite(scavenge_armor_ratio) or scavenge_max_armor <= 0.0 or not is_finite(scavenge_max_armor):
		return "拾荒护甲参数无效"
	if not is_finite(evasion_chance) or evasion_chance < 0.0 or evasion_chance > 1.0:
		return "敌种闪避率无效"
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
		"elite": elite, "charge_bonus": charge_bonus, "ignores_rough": ignores_rough,
		"splash_radius": splash_radius, "jam_range": jam_range,
		"stage_weights": stage_weights, "minimum_stage": minimum_stage, "first_wave": first_wave, "max_alive": max_alive,
		"charge_linger_seconds": charge_linger_seconds, "prefers_towers": prefers_towers,
		"scavenge_radius": scavenge_radius, "scavenge_armor_ratio": scavenge_armor_ratio,
		"scavenge_max_armor": scavenge_max_armor, "jam_seconds": jam_seconds,
		"jam_immunity_seconds": jam_immunity_seconds, "jam_cooldown_seconds": jam_cooldown_seconds,
		"boost_seconds": boost_seconds, "boost_speed": boost_speed,
		"marches_to_core": marches_to_core, "wandering_speed_ratio": wandering_speed_ratio, "shelter_radius": shelter_radius,
		"shelter_reduction": shelter_reduction, "shelter_self": shelter_self, "passes_walls": passes_walls,
		"evasion_chance": evasion_chance, "frenzy_radius": frenzy_radius,
		"frenzy_seconds": frenzy_seconds, "frenzy_speed_bonus": frenzy_speed_bonus,
		"frenzy_damage_bonus": frenzy_damage_bonus}
