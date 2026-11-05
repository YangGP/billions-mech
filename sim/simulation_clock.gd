class_name MechSimulationClock
extends RefCounted
## Pausing the simulation does not pause the scene tree or input.

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


func advance() -> bool:
	if _paused:
		return false
	_tick_index += 1
	return true


func step_seconds() -> float:
	return 1.0 / float(_tick_rate)


func snapshot() -> Dictionary:
	return {"tick": _tick_index, "tick_rate": _tick_rate,
		"elapsed_seconds": float(_tick_index) / float(_tick_rate), "paused": _paused}
