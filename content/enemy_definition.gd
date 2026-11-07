class_name MechEnemyDefinition
extends Resource
## Threat-side combat data (values.md §11); behavior rules stay in waves-enemies.md §8.

@export var enemy_id: StringName = &"builder"
@export var display_name: String = "建造者"
@export var max_hp: int = 30
@export var damage: int = 6
## 0 = same damage against buildings; flat form of architecture.md §7 damage modifier table.
@export var damage_vs_building: int = 0
@export var attack_seconds: float = 1.0
@export var attack_range: float = 1.0
@export var move_speed: float = 1.5
@export var vision_radius: float = 6.0
@export var threat_cost: float = 1.0
@export var prefers_buildings: bool = false
## false = wanderer-style: never marches to the core; idles with slow TAB-style
## shuffling, converges on noise, and engages when seen or attacked.
@export var marches_to_core: bool = true
## Electromagnetic shelter (prototype): enemies within shelter_radius of this
## unit take reduced damage from every source; killing it lifts the shelter.
@export var shelter_radius: float = 0.0
@export_range(0.0, 1.0, 0.01) var shelter_reduction: float = 0.5
## Wall pass-through (prototype): walks over armored walls at normal speed;
## other buildings and obstacle terrain still block (attacks its way through).
@export var passes_walls: bool = false


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
	if shelter_radius < 0.0 or not is_finite(shelter_radius):
		return "敌种庇护半径无效"
	if shelter_radius > 0.0 and (shelter_reduction <= 0.0 or shelter_reduction > 1.0):
		return "敌种庇护减伤比例无效"
	return ""


func building_damage() -> int:
	return damage_vs_building if damage_vs_building > 0 else damage


func snapshot() -> Dictionary:
	return {"enemy_id": enemy_id, "name": display_name, "max_hp": max_hp,
		"damage": damage, "damage_vs_building": building_damage(),
		"attack_seconds": attack_seconds, "attack_range": attack_range,
		"move_speed": move_speed, "vision_radius": vision_radius,
		"threat_cost": threat_cost, "prefers_buildings": prefers_buildings,
		"marches_to_core": marches_to_core, "shelter_radius": shelter_radius,
		"shelter_reduction": shelter_reduction, "passes_walls": passes_walls}
