class_name ResourcePanel
extends PanelContainer
## 顶部资源栏：库存 + 净变化、工人/食物/能源容量、建筑数量与游戏时间。
## 只负责显示，所有按钮通过信号交给 HUD / GameState 处理。

signal pause_requested()

const DEFICIT_COLOR := Color(1.0, 0.45, 0.45)

@onready var _gold_label: Label = %GoldLabel
@onready var _wood_label: Label = %WoodLabel
@onready var _worker_label: Label = %WorkerLabel
@onready var _food_label: Label = %FoodLabel
@onready var _energy_label: Label = %EnergyLabel
@onready var _building_label: Label = %BuildingLabel
@onready var _cursor_label: Label = %CursorLabel
@onready var _time_label: Label = %TimeLabel
@onready var _pause_button: Button = %PauseButton


func _ready() -> void:
	_pause_button.pressed.connect(_on_pause_pressed)
	display_resources({})
	display_time(0.0)


func display_resources(resources: Dictionary, rates: Dictionary = {}) -> void:
	_gold_label.text = _format_stock("金币", resources, rates, "gold")
	_wood_label.text = _format_stock("木材", resources, rates, "wood")
	_gold_label.modulate = DEFICIT_COLOR if int(resources.get("gold", 0)) < 0 else Color.WHITE
	_wood_label.modulate = DEFICIT_COLOR if int(resources.get("wood", 0)) < 0 else Color.WHITE


func display_capacity(economy: EconomySystem) -> void:
	_worker_label.text = "工人 %d/%d" % [economy.workers_used, economy.workers_total]
	_worker_label.modulate = (
		DEFICIT_COLOR if economy.workers_used > economy.workers_total else Color.WHITE
	)

	_food_label.text = "食物 %d/%d" % [economy.food_demand, economy.food_supply]
	_food_label.modulate = (
		DEFICIT_COLOR if economy.food_demand > economy.food_supply else Color.WHITE
	)

	_energy_label.text = "能源 %d/%d" % [economy.energy_demand, economy.energy_supply]
	_energy_label.modulate = (
		DEFICIT_COLOR if economy.energy_demand > economy.energy_supply else Color.WHITE
	)


func display_buildings(count: int, occupied_cells: int) -> void:
	_building_label.text = "建筑 %d · 占地 %d" % [count, occupied_cells]


func display_cursor_cell(cell: Vector2i, inside: bool) -> void:
	if inside:
		_cursor_label.text = "光标 (%d, %d)" % [cell.x, cell.y]
	else:
		_cursor_label.text = "光标 --"


func display_time(seconds: float) -> void:
	var total: int = int(seconds)
	_time_label.text = "时间 %02d:%02d" % [int(total / 60.0), total % 60]


func set_paused(paused: bool) -> void:
	_pause_button.text = "继续" if paused else "暂停"


func _format_stock(
	label: String, resources: Dictionary, rates: Dictionary, resource_id: String
) -> String:
	var amount := int(resources.get(resource_id, 0))
	var rate := int(rates.get(resource_id, 0))
	if rate == 0:
		return "%s %d" % [label, amount]
	var rate_text := (" (+%d)" % rate) if rate > 0 else (" (%d)" % rate)
	return "%s %d%s" % [label, amount, rate_text]


func _on_pause_pressed() -> void:
	pause_requested.emit()
