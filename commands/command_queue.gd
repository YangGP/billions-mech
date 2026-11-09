class_name MechCommandQueue
extends RefCounted
## 串行化请求，包括暂停期间发出的请求。

## 每条命令执行完毕时发出，携带命令类型与结果副本。
signal command_finished(command_type: int, result: Dictionary)

var _executor: Callable
var _pending: Array[MechCommand] = []
## 正在排空队列的标志；重入提交只入队不执行。
var _draining: bool = false


func configure(executor: Callable) -> void:
	_executor = executor


## 提交一条命令并驱动队列直至清空。返回本次提交命令（队首）的执行结果。
func submit(command: MechCommand) -> Dictionary:
	if not _executor.is_valid():
		return {"ok": false, "reason": "模拟尚未就绪"}
	_pending.append(MechCommand.new(command.type, command.payload))
	# 已在排空中：只入队，由外层循环统一执行。
	if _draining:
		return {"ok": true, "queued": true}
	_draining = true
	var first_result: Dictionary = {}
	while not _pending.is_empty():
		var next_command: MechCommand = _pending.pop_front()
		var result: Dictionary = _executor.call(next_command)
		# 只记录队首命令的结果作为本次 submit 的返回值。
		if first_result.is_empty():
			first_result = result.duplicate(true)
		# 重入的监听者只能入队，无法打断正在进行的提交。
		command_finished.emit(next_command.type, result.duplicate(true))
	_draining = false
	return first_result
