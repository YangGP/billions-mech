class_name MechBuildingState
extends RefCounted
## Independent construction, health and demolition state.

enum Phase { CONSTRUCTING, OPERATING, DEMOLISHING, RUINED }

const REBUILD_COST_RATIO: float = 0.5
## Enemies within this radius of the footprint keep an attacked building in
## its combat state (building-economy.md §4.2): repairs stay suspended until
## the site is clear.
const THREAT_RADIUS: float = 6.0

var entity_id: int
var definition: MechBuildingDefinition
var origin: Vector2i
var phase: Phase = Phase.CONSTRUCTING
var hp: int = 1
var paid_cost: Dictionary[StringName, int] = MechResources.empty()
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
## P3c material-repair fraction: per-resource numerator over 4*max_hp per HP.
## Kept across repair toggles, full HP and ruin/rebuild; converted on upgrade.
var repair_material_remainder: Dictionary[StringName, int] = {}
var repair_hp_accumulator: int = 0
var income_remainder: int = 0
## Runtime output of an environment source (wind/solar); definition fields stay
## immutable and shared. Recomputed only when the explored map changes.
var environment_power: int = 0
## Thermal-smelter cycle runtime. paid fuel/metal are removed from the ledger
## at cycle start and refunded only if an active demolition completes.
var processing_active: bool = false
var processing_elapsed: int = 0
var processing_total: int = 0
var processing_paid: Dictionary[StringName, int] = MechResources.empty()
var processing_power: int = 0
## In-place upgrade keeps the old definition and service active until complete.
var upgrade_target: MechBuildingDefinition
var upgrade_elapsed: int = 0
var upgrade_total: int = 0
var upgrade_paid: Dictionary[StringName, int] = MechResources.empty()
## Aura runtime multipliers in tenths; reset to 10 when no aura applies.
var income_multiplier_tenths: int = 10
var extraction_multiplier_tenths: int = 10
var cooling_multiplier_tenths: int = 10
var attack_cooldown_ticks: int = 0
var shot_ticks: int = 0
var shot_target: Vector2 = Vector2.ZERO
## Combat state: set on taking damage, held while enemies stay within
## THREAT_RADIUS, cleared by the SimCore scan once the site is clear.
var threatened: bool = false


func configure(id: int, rules: MechBuildingDefinition, cell: Vector2i, hz: int, completed: bool = false) -> void:
	entity_id = id
	definition = rules
	origin = cell
	paid_cost = MechResources.empty() if completed else MechResources.copy(rules.cost)
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


func refund() -> Dictionary[StringName, int]:
	return MechResources.scaled(paid_cost, paid_refund_ratio)


func rebuild_cost() -> Dictionary[StringName, int]:
	return MechResources.scaled(definition.cost, REBUILD_COST_RATIO)


func mark_ruined() -> void:
	# Occupancy, the mineral binding and the registry entity stay; everything
	# else resets so a later rebuild starts from a clean construction state.
	phase = Phase.RUINED
	hp = 0
	built_hp = 1
	elapsed_build_ticks = 0
	elapsed_demolition_ticks = 0
	waiting_for_clearance = false
	reset_repair_state()
	threatened = false
	paid_cost = MechResources.empty()
	extraction_remainder = 0
	income_remainder = 0
	environment_power = 0
	processing_active = false
	processing_elapsed = 0
	processing_total = 0
	processing_paid = MechResources.empty()
	processing_power = 0
	upgrade_target = null
	upgrade_elapsed = 0
	upgrade_total = 0
	upgrade_paid = MechResources.empty()
	income_multiplier_tenths = 10
	extraction_multiplier_tenths = 10
	cooling_multiplier_tenths = 10
	attack_cooldown_ticks = 0
	shot_ticks = 0


func reset_repair_state() -> void:
	repairing = false
	repair_remainder = 0
	repair_hp_accumulator = 0
	repair_waiting_for_funds = false


func convert_repair_denominator(old_max_hp: int, new_max_hp: int) -> void:
	if old_max_hp <= 0 or new_max_hp <= 0 or old_max_hp == new_max_hp:
		return
	var old_denominator: int = 4 * old_max_hp
	var new_denominator: int = 4 * new_max_hp
	for key: StringName in repair_material_remainder:
		repair_material_remainder[key] = int(
			repair_material_remainder[key] * new_denominator / old_denominator
		)


func cycle_refund() -> Dictionary[StringName, int]:
	return MechResources.copy(processing_paid) if processing_active else MechResources.empty()


func upgrade_refund() -> Dictionary[StringName, int]:
	return MechResources.copy(upgrade_paid) if upgrade_target != null else MechResources.empty()


func status() -> String:
	if phase == Phase.RUINED:
		return "已摧毁 · 基座占位"
	if phase == Phase.CONSTRUCTING:
		return "等待友军移出" if waiting_for_clearance else "施工中"
	if phase == Phase.DEMOLISHING:
		return "清除基座中" if hp == 0 else "拆除中"
	if threatened:
		return "交战中 · 维修暂停" if repairing else "交战中"
	if not powered:
		return "断覆盖"
	if repairing:
		return "维修等待材料" if repair_waiting_for_funds else "维修中"
	if upgrade_target != null:
		return "升级中"
	if definition.alloy_recipe != null:
		if processing_active:
			return "燃烧中 · 缺金属" if int(processing_paid.get(&"metal_ore", 0)) <= 0 else "燃烧中"
		return "待燃料"
	return "运转中"


func snapshot() -> Dictionary:
	var result: Dictionary = definition.snapshot()
	result.merge({"entity_id": entity_id, "origin": origin, "is_building": true,
		"phase": phase, "status": status(), "hp": hp, "paid_cost": MechResources.copy(paid_cost),
		"build_progress": float(elapsed_build_ticks) / build_ticks,
		"demolition_progress": float(elapsed_demolition_ticks) / demolition_ticks,
		"demolition_seconds": definition.demolition_seconds, "refund": refund(),
		"repairing": repairing, "threatened": threatened, "powered": powered,
		"repair_waiting_for_materials": repair_waiting_for_funds,
		"repair_material_remainder": MechResources.copy(repair_material_remainder),
		"income_multiplier_tenths": income_multiplier_tenths,
		"extraction_multiplier_tenths": extraction_multiplier_tenths,
		"cooling_multiplier_tenths": cooling_multiplier_tenths,
		"environment_power": environment_power,
		"processing": {"active": processing_active, "elapsed": processing_elapsed,
			"total": processing_total, "paid": MechResources.copy(processing_paid),
			"power": processing_power,
			"progress": float(processing_elapsed) / float(maxi(1, processing_total))},
		"upgrade": {"active": upgrade_target != null, "target": upgrade_target.building_id if upgrade_target != null else &"",
			"target_name": upgrade_target.display_name if upgrade_target != null else "",
			"elapsed": upgrade_elapsed, "total": upgrade_total,
			"paid": MechResources.copy(upgrade_paid),
			"progress": float(upgrade_elapsed) / float(maxi(1, upgrade_total))},
		"waiting_for_clearance": waiting_for_clearance, "rebuild_cost": rebuild_cost(),
		"shot_ticks": shot_ticks, "shot_target": shot_target}, true)
	return result
