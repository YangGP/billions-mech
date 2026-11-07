class_name MechCommand
extends RefCounted
## Short-lived intent; commands are not recorded or persisted.

enum Type { SET_PAUSED, MOVE_ENTITY, RESET_SESSION, PLACE_BUILDING, PLACE_WALL_LINE,
	CANCEL_CONSTRUCTION, DEMOLISH, CANCEL_DEMOLISH, TOGGLE_REPAIR,
	QUEUE_UNIT, CANCEL_PRODUCTION, SET_RALLY, ISSUE_UNIT_ORDER, LOAD_SCENARIO,
	REBUILD, REPAIR_ALL }

var type: Type
var payload: Dictionary


func _init(command_type: Type, command_payload: Dictionary = {}) -> void:
	type = command_type
	payload = command_payload.duplicate(true)
