class_name GameState
extends Node
## 唯一世界状态的持有者与装配点。
##
## 这里集中持有网格、模拟时钟、经济、建筑与区块系统；视图层（World / HUD）
## 只读取这里的数据，并通过信号刷新，不直接改写系统内部状态。
## 只有确实需要跨场景持久化时才考虑改成 Autoload，M1 阶段保持主场景内持有。

signal resources_changed(resources: Dictionary)
signal capacity_changed()
signal buildings_changed()

@export var map_width: int = 32
@export var map_height: int = 32
@export var economy_tick_seconds: float = 1.0
@export var starting_resources: Dictionary = {"gold": 500, "wood": 200}
## 开局自动放置的初始建筑；空字符串表示不放置。
@export var starting_building_id: StringName = &"command_center"

@onready var clock: SimulationClock = $SimulationClock
@onready var economy: EconomySystem = $EconomySystem
@onready var buildings: BuildingSystem = $BuildingSystem
@onready var regions: RegionSystem = $RegionSystem

var grid: GridState

var _initialized: bool = false


func _ready() -> void:
	_initialize()


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true

	grid = GridState.new(map_width, map_height)
	regions.setup(map_width, map_height)
	economy.setup(starting_resources)
	buildings.setup(grid, economy)
	_place_starting_building()
	clock.setup(economy_tick_seconds)

	economy.resources_changed.connect(_on_economy_resources_changed)
	economy.capacity_changed.connect(_on_economy_capacity_changed)
	buildings.buildings_changed.connect(_on_buildings_changed)
	clock.tick.connect(_on_clock_tick)

	resources_changed.emit(economy.get_resources())
	capacity_changed.emit()
	buildings_changed.emit()


## 开局把指挥中心放在地图中央（按占地大小居中）。
func _place_starting_building() -> void:
	if starting_building_id == &"":
		return

	var definition := buildings.get_definition(starting_building_id)
	if definition == null:
		push_warning("初始建筑定义不存在：%s" % starting_building_id)
		return

	var origin := Vector2i(
		maxi(0, floori((float(map_width) - float(definition.footprint.x)) * 0.5)),
		maxi(0, floori((float(map_height) - float(definition.footprint.y)) * 0.5))
	)
	if not buildings.try_place_building(starting_building_id, origin):
		push_warning("初始建筑放置失败：%s" % buildings.last_error)


func get_building_count() -> int:
	return buildings.get_building_count()


func get_occupied_cell_count() -> int:
	return grid.get_occupied_count()


func _on_clock_tick(_tick_index: int) -> void:
	economy.process_tick()


func _on_economy_resources_changed(resources: Dictionary) -> void:
	resources_changed.emit(resources)


func _on_economy_capacity_changed() -> void:
	capacity_changed.emit()


func _on_buildings_changed() -> void:
	buildings_changed.emit()
