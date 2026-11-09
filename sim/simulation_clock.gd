class_name MechSimulationClock
extends RefCounted
## 模拟时钟：固定步长推进的 tick 计数器。暂停模拟不会暂停场景树或输入。

var _tick_rate: int = 30
var _tick_index: int = 0
var _paused: bool = false


func configure(tick_rate: int) -> void:
	_tick_rate = maxi(1, tick_rate)
	reset()


func reset() -> void:
	_tick_index = 0
	_paused = false


func set_paused(value: bool) -> void:
	_paused = value


func is_paused() -> bool:
	return _paused


## 推进一个 tick；暂停时返回 false 且不计数。
func advance() -> bool:
	if _paused:
		return false
	_tick_index += 1
	return true


## 单个 tick 的时长（秒）。
func step_seconds() -> float:
	return 1.0 / float(_tick_rate)


## 导出只读快照，供 HUD 显示时间与暂停状态。
func snapshot() -> Dictionary:
	return {"tick": _tick_index, "tick_rate": _tick_rate,
		"elapsed_seconds": float(_tick_index) / float(_tick_rate), "paused": _paused}
