class_name RegionPanel
extends PanelContainer
## 区块统计面板：只显示聚合结果，不修改任何世界状态。

const RESOURCE_LABELS := {"gold": "金币", "wood": "木材"}

@onready var _title: Label = %RegionTitle
@onready var _body: Label = %RegionBody


func show_stats(stats: Dictionary) -> void:
	_title.text = String(stats.get("name", "区块"))
	_body.text = _format_stats(stats)
	visible = true


func hide_stats() -> void:
	visible = false


func _format_stats(stats: Dictionary) -> String:
	var lines := PackedStringArray()

	var building_count := int(stats.get("building_count", 0))
	lines.append("建筑：%d" % building_count)

	var type_counts: Dictionary = stats.get("type_counts", {})
	if not type_counts.is_empty():
		var type_names := type_counts.keys()
		type_names.sort()
		var type_parts := PackedStringArray()
		for type_name in type_names:
			type_parts.append("%s×%d" % [String(type_name), int(type_counts[type_name])])
		lines.append("类型：" + "、".join(type_parts))

	var occupied := int(stats.get("occupied_cells", 0))
	var total := int(stats.get("total_cells", 0))
	var buildable := int(stats.get("buildable_cells", 0))
	lines.append("占地：%d/%d 格" % [occupied, total])
	lines.append("可建空地：%d 格" % buildable)

	var output_text := _format_resources(stats.get("output", {}), true)
	if output_text != "":
		lines.append("产出：%s / tick" % output_text)

	var upkeep_text := _format_resources(stats.get("upkeep", {}), false)
	if upkeep_text != "":
		lines.append("维护：%s / tick" % upkeep_text)

	lines.append("")
	lines.append("建筑与产出按锚点归属；占地按实际格数统计")
	return "\n".join(lines)


func _format_resources(values: Dictionary, show_sign: bool) -> String:
	var parts := PackedStringArray()
	for resource_id in values:
		var label: String = RESOURCE_LABELS.get(String(resource_id), String(resource_id))
		var amount := int(values[resource_id])
		var amount_text := str(amount)
		if show_sign and amount >= 0:
			amount_text = "+" + amount_text
		parts.append("%s %s" % [label, amount_text])
	return "、".join(parts)
