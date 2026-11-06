class_name MechBuildingState
extends RefCounted
## Independent construction, health and demolition state.

enum Phase { CONSTRUCTING, OPERATING, DEMOLISHING }

var entity_id: int
var definition: MechBuildingDefinition
var origin: Vector2i
var phase: Phase = Phase.CONSTRUCTING
var hp: int = 1
var paid_cost: Vector4i = Vector4i.ZERO
var paid_refund_ratio: float = 0.5
var mineral_id: StringName = &""
var extraction_remainder: int = 0
var build_ticks: int = 1
var elapsed_build_ticks: int = 0
var demolition_ticks: int = 1
var elapsed_demolition_ticks: int = 0
var built_hp: int = 1
var powered: bool = true
var waiting_for_clearance: bool = false
var repairing: bool = false
var repair_waiting_for_funds: bool = false
var repair_remainder: int = 0
var income_remainder: int = 0
var attack_cooldown_ticks: int = 0
var shot_ticks: int = 0
var shot_target: Vector2 = Vector2.ZERO


func configure(id: int, rules: MechBuildingDefinition, cell: Vector2i, hz: int, completed: bool = false) -> void:
	entity_id = id
	definition = rules
	origin = cell
	paid_cost = Vector4i.ZERO if completed else rules.cost
	paid_refund_ratio = rules.refund_ratio
	build_ticks = maxi(1, ceili(rules.construction_seconds * hz))
	demolition_ticks = maxi(1, ceili(rules.demolition_seconds * hz))
	if completed:
		phase = Phase.OPERATING
		elapsed_build_ticks = build_ticks
		hp = rules.max_hp
		built_hp = hp


func operating() -> bool:
	return phase == Phase.OPERATING and powered


func advance_construction() -> bool:
	elapsed_build_ticks = mini(elapsed_build_ticks + 1, build_ticks)
	var next_built_hp: int = maxi(1, floori(float(definition.max_hp) * elapsed_build_ticks / build_ticks))
	hp = mini(definition.max_hp, hp + next_built_hp - built_hp)
	built_hp = next_built_hp
	return elapsed_build_ticks == build_ticks


func refund() -> Vector4i:
	return MechResources.scaled(paid_cost, paid_refund_ratio)


func status() -> String:
	if phase == Phase.CONSTRUCTING:
		return "等待友军移出" if waiting_for_clearance else "施工中"
	if phase == Phase.DEMOLISHING:
		return "拆除中"
	if not powered:
		return "未通电"
	if repairing:
		return "维修等待资金" if repair_waiting_for_funds else "维修中"
	return "运转中"


func snapshot() -> Dictionary:
	var result: Dictionary = definition.snapshot()
	result.merge({"entity_id": entity_id, "origin": origin, "is_building": true,
		"phase": phase, "status": status(), "hp": hp, "paid_cost": paid_cost,
		"build_progress": float(elapsed_build_ticks) / build_ticks,
		"demolition_progress": float(elapsed_demolition_ticks) / demolition_ticks,
		"demolition_seconds": definition.demolition_seconds, "refund": refund(),
		"repairing": repairing, "powered": powered, "waiting_for_clearance": waiting_for_clearance,
		"shot_ticks": shot_ticks, "shot_target": shot_target}, true)
	return result
