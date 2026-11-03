class_name BuildingDefinition
extends Resource
## 建筑静态定义：数值与规则放在 .tres 中，不写死在 UI 或建筑 Sprite 里。
##
## 字段语义（M1 简化模型）：
## - build_cost / upkeep_per_tick / output_per_tick：库存资源收支（金币、木材……）。
## - housing_capacity：提供工人容量；required_workers：占用工人。
## - food_capacity / food_demand：食物供给与需求（容量约束，不是库存）。
## - energy_supply / energy_demand：能源供给与需求（容量约束，不是库存）。

@export_group("基础信息")
@export var building_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var scene: PackedScene
## 是否出现在建造菜单中（指挥中心等初始建筑设为 false）。
@export var buildable: bool = true
## 全局唯一，最多存在一座。
@export var unique: bool = false
## 是否允许手动拆除（指挥中心设为 false）。
@export var demolishable: bool = true
## 建造菜单排序，数值小的在前。
@export var palette_order: int = 0

@export_group("占地")
## 以逻辑格为单位的占地大小，与建筑图片像素尺寸无关。
@export var footprint: Vector2i = Vector2i.ONE

@export_group("视觉")
## 占位贴图：底边中点对齐占地菱形的前角。
@export var texture: Texture2D
@export var sprite_scale: float = 1.0
## 贴图相对锚点的微调偏移（像素），正常情况下保持零。
@export var sprite_offset: Vector2 = Vector2.ZERO
## 贴图颜色调制，用于复用贴图区分建筑（例如哨塔）。
@export var sprite_modulate: Color = Color.WHITE

@export_group("经济")
@export var build_cost: Dictionary = {}
@export var upkeep_per_tick: Dictionary = {}
@export var output_per_tick: Dictionary = {}
@export var required_workers: int = 0
@export var housing_capacity: int = 0
@export var food_capacity: int = 0
@export var food_demand: int = 0
@export var energy_supply: int = 0
@export var energy_demand: int = 0
## 仓储上限增量，例：{"gold": 700, "wood": 700}。
@export var storage_capacity: Dictionary = {}

@export_group("运营")
## 供给不足时的保障优先级，数值越大越优先（防御 > 食物 > 核心 > 木材 > 住房）。
@export var operation_priority: int = 0

@export_group("生命与战斗")
## 建筑生命值；<= 0 视为建筑定义未配置，放下时会取 100。
@export var max_hp: int = 100
## 核心建筑：被摧毁即本局失败。
@export var is_core: bool = false
## 防御塔攻击半径（逻辑格）；0 表示不攻击。
@export var attack_range: float = 0.0
@export var attack_damage: int = 0
@export var attack_interval: float = 1.0

@export_group("建设范围")
## 大于 0 时，建成后扩大可建造范围；具体规则在 M1-05 接入。
@export var build_range_radius: int = 0


func get_cell_count() -> int:
	return maxi(0, footprint.x) * maxi(0, footprint.y)


func is_valid() -> bool:
	return (
		building_id != &""
		and display_name != ""
		and footprint.x > 0
		and footprint.y > 0
		and texture != null
	)
