class_name MechBuildMenu
extends Panel
## Presentation-only directory. The simulation catalog alone authorizes orders.

signal build_requested(id: StringName)
signal cancel_requested
signal focus_requested

const DIRECTORY: JSON = preload("res://content/build_menu_catalog.json")
const MATERIAL_LABELS: Array[String] = ["币", "矿", "燃", "合", "晶"]

@export_enum("economy", "extraction", "energy", "defense", "military", "support") var initial_category: String = "economy"

var _entries: Dictionary[StringName, Dictionary] = {}
var _buttons: Dictionary[StringName, Button] = {}
var _category_buttons: Dictionary[StringName, Button] = {}
var _catalog: Dictionary[StringName, Dictionary] = {}
var _category: StringName = &"economy"
var _active_build: StringName = &""
var _ended: bool = false


func _ready() -> void:
	_category = StringName(initial_category)
	var group := ButtonGroup.new()
	for category: Dictionary in DIRECTORY.data["categories"]:
		var id := StringName(category["id"])
		var button := Button.new()
		button.text = category["name"]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_category_pressed.bind(id))
		$Categories.add_child(button)
		_category_buttons[id] = button
	for entry: Dictionary in DIRECTORY.data["buildings"]:
		_add_entry(entry)
	_show_category(_category)
	$CancelBuild.pressed.connect(cancel_requested.emit)


func _add_entry(entry: Dictionary) -> void:
	var id := StringName(entry["id"])
	_entries[id] = entry.duplicate(true)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = entry.get("action", "") != "focus_core"
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(_building_pressed.bind(id))
	$Buildings/Grid.add_child(button)
	_buttons[id] = button


func present_catalog(catalog: Array, ended: bool) -> void:
	_ended = ended
	_catalog.clear()
	for entry: Dictionary in catalog:
		var id: StringName = entry["building_id"]
		_catalog[id] = entry
		if not _entries.has(id):
			# New runtime definitions always get an entry, even before directory metadata is added.
			_add_entry({"id": id, "name": entry["name"], "category": "support", "description": ""})
			_buttons[id].visible = _category == &"support"
	_refresh_buttons()


func present_build(id: StringName) -> void:
	_active_build = id
	if id != &"" and _entries.has(id):
		_show_category(StringName(_entries[id]["category"]))
	for value: StringName in _buttons:
		_buttons[value].set_pressed_no_signal(value == id)
	$CancelBuild.disabled = id == &""


func reset_menu() -> void:
	present_build(&"")
	_show_category(StringName(initial_category))


func _category_pressed(id: StringName) -> void:
	if id != _category and _active_build != &"":
		cancel_requested.emit()
	_show_category(id)


func _show_category(id: StringName) -> void:
	var changed: bool = _category != id
	_category = id
	for key: StringName in _category_buttons:
		_category_buttons[key].set_pressed_no_signal(key == id)
	for key: StringName in _buttons:
		_buttons[key].visible = StringName(_entries[key]["category"]) == id
	if changed:
		$Buildings.scroll_vertical = 0
	_refresh_buttons()


func _refresh_buttons() -> void:
	var count: int = 0
	var available: int = 0
	for id: StringName in _entries:
		var metadata: Dictionary = _entries[id]
		var button: Button = _buttons[id]
		var rules: Dictionary = _catalog.get(id, {})
		var focus_core: bool = metadata.get("action", "") == "focus_core"
		var opened: bool = focus_core or not rules.is_empty()
		if StringName(metadata["category"]) == _category:
			count += 1
			available += int(opened)
		var title: String = rules.get("name", metadata["name"])
		var shortcut: String = metadata.get("shortcut", "")
		if not shortcut.is_empty():
			title = "%s %s" % [shortcut, title]
		var reason: String = "本局已结束" if _ended else rules.get("unavailable_reason", "")
		var subtitle: String = "定位主脑" if focus_core else "暂未开放"
		var details: String = metadata.get("description", "")
		if not rules.is_empty():
			subtitle = _compact_cost(rules["cost"])
			var size: Vector2i = rules["footprint"]
			details += "\n占地%d×%d · 施工%.1f秒\n%s\n预留电力%d · 冷却%d · 调度%d" % [size.x, size.y, rules["construction_seconds"], MechResources.text(rules["cost"]), rules["power_cost"], rules["cooling_cost"], rules["capacity_cost"]]
		elif not focus_core:
			reason = "该建筑暂未开放，当前无法建造。"
		button.text = "%s\n%s" % [title, subtitle]
		button.tooltip_text = details + ("\n" + reason if not reason.is_empty() else "")
		button.disabled = not opened or _ended or not reason.is_empty()
	$Title.text = "建造 · %s  %d/%d已开放" % [_category_buttons[_category].text, available, count]


func _building_pressed(id: StringName) -> void:
	if _ended:
		return
	if _entries[id].get("action", "") == "focus_core":
		cancel_requested.emit()
		focus_requested.emit()
	elif _catalog.has(id) and _catalog[id]["unavailable_reason"].is_empty():
		build_requested.emit(id)
	# The presenter accepts or rejects the intent before the toggle is updated.
	present_build(_active_build)


func _compact_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for index: int in range(MechResources.KEYS.size()):
		var amount: int = cost.get(MechResources.KEYS[index], 0)
		if amount > 0:
			parts.append("%d%s" % [amount, MATERIAL_LABELS[index]])
	return " ".join(parts) if not parts.is_empty() else "免费"
