class_name MechCommand
extends RefCounted
## 短生命周期的意图表达；命令不做记录或持久化。

## 命令类型；各类型的 payload 结构由对应的处理函数定义。
enum Type { SET_PAUSED, MOVE_ENTITY, RESET_SESSION, PLACE_BUILDING, PLACE_WALL_LINE,
	CANCEL_CONSTRUCTION, DEMOLISH, CANCEL_DEMOLISH, TOGGLE_REPAIR,
	QUEUE_UNIT, CANCEL_PRODUCTION, SET_RALLY, ISSUE_UNIT_ORDER, LOAD_SCENARIO,
	REBUILD, REPAIR_ALL, UPGRADE_BUILDING, CANCEL_UPGRADE, CONFIGURE_DISPATCH_REGION,
	REQUEST_FINAL_WAVE, GARRISON_UNIT, UNGARRISON_UNIT, ACCEPT_CONTRACT, CANCEL_CONTRACT,
	DELETE_DISPATCH_REGION }

var type: Type
var payload: Dictionary


## 构造命令；payload 深拷贝以防外部修改。
func _init(command_type: Type, command_payload: Dictionary = {}) -> void:
	type = command_type
	payload = command_payload.duplicate(true)
