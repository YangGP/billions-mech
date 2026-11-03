class_name BuildingInfoPanel
extends PanelContainer
## 建筑信息面板：显示名称、说明、占地、成本、产出与容量影响。
## 只做展示，数据全部来自 BuildingDefinition。

const RESOURCE_LABELS := {"gold": "金币", "wood": "木材"}

@onready var _title: Label = %InfoTitle
@onready var _body: Label = %InfoBody

var _current_id: StringName = &""


func show_definition(
	definition: BuildingDefinition, instance: BuildingInstance = null
) -> void:
	if definition == null:
		hide_info()
		return
	_current_id = definition.building_id
	_title.text = definition.display_name
	_body.text = _format_definition(definition, instance)
	visible = true


func hide_info() -> void:
	_current_id = &""
	visible = false


func get_current_id() -> StringName:
	return _current_id


func _format_definition(
	definition: BuildingDefinition, instance: BuildingInstance
) -> String:
	var lines := PackedStringArray()

	if definition.description != "":
		lines.append(definition.description)
		lines.append("")

	lines.append("占地：%d×%d" % [definition.footprint.x, definition.footprint.y])
	if instance != null:
		lines.append("状态：%s" % instance.get_operation_text())

	if not definition.build_cost.is_empty():
		lines.append("建造：%s" % _format_resources(definition.build_cost))
	if not definition.output_per_tick.is_empty():
		lines.append("产出：%s / tick" % _format_resources(definition.output_per_tick))
	if not definition.upkeep_per_tick.is_empty():
		lines.append("维护：%s / tick" % _format_resources(definition.upkeep_per_tick))

	var capacity_lines := PackedStringArray()
	if definition.housing_capacity != 0:
		capacity_lines.append("住房 +%d" % definition.housing_capacity)
	if definition.required_workers != 0:
		capacity_lines.append("占用工人 %d" % definition.required_workers)
	if definition.food_capacity != 0:
		capacity_lines.append("食物供给 +%d" % definition.food_capacity)
	if definition.energy_supply != 0:
		capacity_lines.append("能源供给 +%d" % definition.energy_supply)
	if definition.energy_demand != 0:
		capacity_lines.append("能源需求 +%d" % definition.energy_demand)
	if definition.build_range_radius != 0:
		capacity_lines.append("建造范围 +%d" % definition.build_range_radius)

	if not capacity_lines.is_empty():
		lines.append("")
		lines.append("容量")
		for line in capacity_lines:
			lines.append("· " + line)

	if not definition.storage_capacity.is_empty():
		lines.append("")
		lines.append("仓储：%s" % _format_resources(definition.storage_capacity))

	if definition.max_hp > 0:
		lines.append("")
		if instance != null:
			lines.append("生命：%d/%d" % [instance.hp, definition.max_hp])
		else:
			lines.append("生命：%d" % definition.max_hp)
	if definition.attack_damage > 0:
		lines.append("攻击：%d / %.1f 秒 · 射程 %d 格" % [
			definition.attack_damage,
			definition.attack_interval,
			int(definition.attack_range),
		])
	if definition.is_core:
		lines.append("核心：被摧毁则本局失败")

	if not definition.demolishable:
		lines.append("")
		lines.append("不可拆除")

	return "\n".join(lines)


func _format_resources(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource_id in cost:
		var label: String = RESOURCE_LABELS.get(String(resource_id), String(resource_id))
		parts.append("%s %d" % [label, int(cost[resource_id])])
	return "、".join(parts)
