class_name BuildPalette
extends PanelContainer
## 建造菜单：根据 BuildingDefinition 动态生成按钮，点击后发出选择信号。
## 只负责显示与转发，不判断资源或占地。

signal building_selected(definition_id: StringName)

const RESOURCE_LABELS := {"gold": "金", "wood": "木"}

@onready var _buttons: VBoxContainer = %BuildButtons
@onready var _status_label: Label = %StatusLabel

var _button_by_id: Dictionary = {}
var _group: ButtonGroup


func setup(definitions: Array[BuildingDefinition]) -> void:
	for child in _buttons.get_children():
		child.queue_free()
	_button_by_id.clear()
	_group = ButtonGroup.new()

	for definition in definitions:
		var button := Button.new()
		button.text = "%s   %s" % [definition.display_name, _format_cost(definition.build_cost)]
		button.tooltip_text = definition.description
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_button_pressed.bind(definition.building_id))
		_buttons.add_child(button)
		_button_by_id[definition.building_id] = button


func set_selected(definition_id: StringName) -> void:
	var button: Button = _button_by_id.get(definition_id)
	if button != null:
		button.set_pressed_no_signal(true)


func clear_selection() -> void:
	if _group == null:
		return
	var pressed := _group.get_pressed_button()
	if pressed != null:
		pressed.set_pressed_no_signal(false)


func set_status(text: String) -> void:
	_status_label.text = text


func _on_button_pressed(definition_id: StringName) -> void:
	building_selected.emit(definition_id)


func _format_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource_id in cost:
		var label: String = RESOURCE_LABELS.get(String(resource_id), String(resource_id))
		parts.append("%s%d" % [label, int(cost[resource_id])])
	return " ".join(parts)
