class_name BuildingInstance
extends RefCounted
## 建筑运行时实例：纯数据，不持有任何视觉节点。
##
## 视觉表现由 BuildingView（M1-03）根据 instance_id / definition_id 创建与销毁。
## 拆除流程必须「先改数据，再通知视图」，不能反过来。

enum ConstructionState {
	COMPLETE,
	UNDER_CONSTRUCTION,
}

var instance_id: StringName = &""
var definition_id: StringName = &""
var origin_cell: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i.ONE
var rotation: int = 0
var construction_state: ConstructionState = ConstructionState.COMPLETE
var active: bool = true
var cells: Array[Vector2i] = []
var hp: int = 0


func get_display_name(definitions: Dictionary) -> String:
	var definition: BuildingDefinition = definitions.get(definition_id)
	if definition == null:
		return String(definition_id)
	return definition.display_name
