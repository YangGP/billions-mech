class_name BuildingView
extends Node2D
## 单栋建筑的视觉节点：贴图底边中点对齐占地菱形的前角，节点 y 用于深度排序。
##
## 只读取 BuildingInstance / BuildingDefinition，不修改任何模拟数据。

@onready var sprite: Sprite2D = $Sprite

var instance_id: StringName = &""


func setup(instance: BuildingInstance, definition: BuildingDefinition, anchor: Vector2) -> void:
	instance_id = instance.instance_id
	position = anchor

	if definition == null or definition.texture == null:
		return

	sprite.texture = definition.texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * definition.sprite_scale

	var texture_size := Vector2(definition.texture.get_width(), definition.texture.get_height())
	var scaled_size := texture_size * definition.sprite_scale
	sprite.position = Vector2(-scaled_size.x * 0.5, -scaled_size.y) + definition.sprite_offset
