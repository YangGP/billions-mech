class_name MechBuildingState
extends RefCounted
## 独立的建筑施工、血量与拆除状态。

enum Phase { CONSTRUCTING, OPERATING, DEMOLISHING, RUINED }

## 废墟重建的费用比例（相对原造价）。
const REBUILD_COST_RATIO: float = 0.5
## 脚印该半径内仍有敌人时，受击建筑保持交战状态
##（building-economy.md §4.2）：维修持续暂停，直至现场肃清。
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
## P3c 材料维修分数：每点 HP 的各资源分子，分母为 4*max_hp。
## 在维修开关、满血与废墟重建之间保留；升级时换算分母。
var repair_material_remainder: Dictionary[StringName, int] = {}
var repair_hp_accumulator: int = 0
var repair_auto_source: int = 0
var repair_manual_hold: bool = false
var garrison_unit_ids: Array[int] = []
var income_remainder: int = 0
## 环境源（风冷/光伏）的运行时输出；定义字段保持不可变且共享，
## 仅在已探索地图变化时重算。按定义进入冷却或电力池。
var environment_power: int = 0
## 热能冶炼周期运行时。已付碳晶/金属在周期开局即移出账本，
## 只有主动拆除完成时才退还。
var processing_active: bool = false
var processing_elapsed: int = 0
var processing_total: int = 0
var processing_paid: Dictionary[StringName, int] = MechResources.empty()
var processing_power: int = 0
## 原地升级：完成前保持旧定义与其服务持续生效。
var upgrade_target: MechBuildingDefinition
var upgrade_elapsed: int = 0
var upgrade_total: int = 0
var upgrade_paid: Dictionary[StringName, int] = MechResources.empty()
var attack_cooldown_ticks: int = 0
## 干扰只暂停火力，不改变运营、供电或经济；免疫窗归目标所有。
var jam_ticks: int = 0
var jam_immunity_ticks: int = 0
var jam_recovery_ticks: int = 0
var jam_source_id: int = 0
var shot_ticks: int = 0
var shot_target: Vector2 = Vector2.ZERO
## 交战状态：受击时置位，敌人保持在 THREAT_RADIUS 内时维持，
## 现场肃清后由 SimCore 扫描清除。
var threatened: bool = false


## 初始化建筑状态；completed 为真时直接以完工状态入场（主脑、废墟重建等）。
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


## 是否处于运行态（完工且有覆盖）。
func operating() -> bool:
	return phase == Phase.OPERATING and powered


func refresh_definition_ticks(hz: int) -> void:
	build_ticks = maxi(1, ceili(definition.construction_seconds * hz))
	demolition_ticks = maxi(1, ceili(definition.demolition_seconds * hz))


## 推进一格施工并同步施工血量；返回是否恰好完工。
func advance_construction() -> bool:
	elapsed_build_ticks = mini(elapsed_build_ticks + 1, build_ticks)
	var next_built_hp: int = maxi(1, floori(float(definition.max_hp) * elapsed_build_ticks / build_ticks))
	hp = mini(definition.max_hp, hp + next_built_hp - built_hp)
	built_hp = next_built_hp
	return elapsed_build_ticks == build_ticks


## 按退款比例折算的拆除退款。
func refund() -> Dictionary[StringName, int]:
	return MechResources.scaled(paid_cost, paid_refund_ratio)


## 废墟重建费用（按 REBUILD_COST_RATIO 折算原造价）。
func rebuild_cost() -> Dictionary[StringName, int]:
	return MechResources.scaled(definition.cost, REBUILD_COST_RATIO)


## 标记为废墟：占用、矿点绑定与注册表实体保留，
## 其余状态全部复位，后续重建从干净的施工状态开始。
func mark_ruined() -> void:
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
	attack_cooldown_ticks = 0
	jam_ticks = 0
	jam_immunity_ticks = 0
	jam_recovery_ticks = 0
	jam_source_id = 0
	shot_ticks = 0


## 复位维修相关的全部临时状态（材料分数余量除外，见字段注释）。
func reset_repair_state() -> void:
	repairing = false
	repair_remainder = 0
	repair_hp_accumulator = 0
	repair_waiting_for_funds = false
	repair_auto_source = 0
	repair_manual_hold = false


## 升级改变 max_hp 时按新分母换算材料维修分数，保持进度无损。
func convert_repair_denominator(old_max_hp: int, new_max_hp: int) -> void:
	if old_max_hp <= 0 or new_max_hp <= 0 or old_max_hp == new_max_hp:
		return
	var old_denominator: int = 4 * old_max_hp
	var new_denominator: int = 4 * new_max_hp
	for key: StringName in repair_material_remainder:
		repair_material_remainder[key] = int(
			repair_material_remainder[key] * new_denominator / old_denominator
		)


## 冶炼周期进行中的退还金额（拆除时使用）；未开周期返回空。
func cycle_refund() -> Dictionary[StringName, int]:
	return MechResources.copy(processing_paid) if processing_active else MechResources.empty()


## 升级进行中的退还金额；未在升级返回空。
func upgrade_refund() -> Dictionary[StringName, int]:
	return MechResources.copy(upgrade_paid) if upgrade_target != null else MechResources.empty()


## HUD 用的中文状态文本，按阶段与运行时标志组合。
func status() -> String:
	if phase == Phase.RUINED:
		return "已摧毁 · 基座占位"
	if phase == Phase.CONSTRUCTING:
		return "等待友军移出" if waiting_for_clearance else "施工中"
	if phase == Phase.DEMOLISHING:
		return "清除基座中" if hp == 0 else "拆除中"
	if jam_ticks > 0:
		return "受到干扰 · 火力暂停"
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
		return "待碳晶"
	return "运转中"


## 导出含定义与全部运行时字段的只读快照。
func snapshot() -> Dictionary:
	var result: Dictionary = definition.snapshot()
	result.merge({"entity_id": entity_id, "origin": origin, "is_building": true,
		"phase": phase, "status": status(), "hp": hp, "paid_cost": MechResources.copy(paid_cost),
		"jam_ticks": jam_ticks, "jam_immunity_ticks": jam_immunity_ticks,
		"build_progress": float(elapsed_build_ticks) / build_ticks,
		"demolition_progress": float(elapsed_demolition_ticks) / demolition_ticks,
		"demolition_seconds": definition.demolition_seconds, "refund": refund(),
		"repairing": repairing, "threatened": threatened, "powered": powered,
		"repair_waiting_for_materials": repair_waiting_for_funds,
		"repair_material_remainder": MechResources.copy(repair_material_remainder),
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
