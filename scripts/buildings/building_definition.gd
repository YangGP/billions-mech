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

@export_group("占地")
## 以逻辑格为单位的占地大小，与建筑图片像素尺寸无关。
@export var footprint: Vector2i = Vector2i.ONE

@export_group("视觉")
## 占位贴图：底边中点对齐占地菱形的前角。
@export var texture: Texture2D
@export var sprite_scale: float = 1.0
## 贴图相对锚点的微调偏移（像素），正常情况下保持零。
@export var sprite_offset: Vector2 = Vector2.ZERO

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
