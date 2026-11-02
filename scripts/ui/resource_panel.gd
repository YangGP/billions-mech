class_name ResourcePanel
extends PanelContainer
## 顶部资源栏：显示库存资源、工人容量、建筑数量与游戏时间。
## 只负责显示，所有按钮通过信号交给 HUD / GameState 处理。

signal pause_requested()

@onready var _gold_label: Label = %GoldLabel
@onready var _wood_label: Label = %WoodLabel
@onready var _worker_label: Label = %WorkerLabel
@onready var _building_label: Label = %BuildingLabel
@onready var _cursor_label: Label = %CursorLabel
@onready var _time_label: Label = %TimeLabel
@onready var _pause_button: Button = %PauseButton


func _ready() -> void:
	_pause_button.pressed.connect(_on_pause_pressed)
	display_resources({})
	display_time(0.0)


func display_resources(resources: Dictionary) -> void:
	_gold_label.text = "金币 %d" % int(resources.get("gold", 0))
	_wood_label.text = "木材 %d" % int(resources.get("wood", 0))


func display_capacity(economy: EconomySystem) -> void:
	_worker_label.text = "工人 %d/%d" % [economy.workers_used, economy.workers_total]


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


func _on_pause_pressed() -> void:
	pause_requested.emit()
