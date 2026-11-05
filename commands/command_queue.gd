class_name MechCommandQueue
extends RefCounted
## Serializes requests, including requests made while paused.

signal command_finished(command_type: int, result: Dictionary)

var _executor: Callable
var _pending: Array[MechCommand] = []
var _draining: bool = false


func configure(executor: Callable) -> void:
	_executor = executor


func submit(command: MechCommand) -> Dictionary:
	if not _executor.is_valid():
		return {"ok": false, "reason": "模拟尚未就绪"}
	_pending.append(MechCommand.new(command.type, command.payload))
	if _draining:
		return {"ok": true, "queued": true}
	_draining = true
	var first_result: Dictionary = {}
	while not _pending.is_empty():
		var next_command: MechCommand = _pending.pop_front()
		var result: Dictionary = _executor.call(next_command)
		if first_result.is_empty():
			first_result = result.duplicate(true)
		# Reentrant listeners enqueue; they cannot interrupt the active commit.
		command_finished.emit(next_command.type, result.duplicate(true))
	_draining = false
	return first_result
