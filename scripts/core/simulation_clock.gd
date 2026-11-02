class_name SimulationClock
extends Node
## 固定步长的模拟时钟。
##
## 经济结算、建筑状态与区块统计都必须由这里驱动；不要在任何视图节点里
## 用 _process 的 delta 直接累计收益，否则帧率不同会导致结果不同。

signal tick(tick_index: int)
signal paused_changed(paused: bool)
signal speed_changed(speed: int)

## 单次卡顿最多补算的 tick 数，避免断点/拖动窗口后一次性结算过量。
const MAX_CATCH_UP_TICKS: int = 5

@export var tick_seconds: float = 1.0

var tick_index: int = 0
var elapsed_game_seconds: float = 0.0
var paused: bool = false
var speed: int = 1

var _accumulator: float = 0.0


func setup(seconds_per_tick: float) -> void:
	tick_seconds = maxf(0.05, seconds_per_tick)
	_accumulator = 0.0


func _process(delta: float) -> void:
	if paused or speed <= 0:
		return

	_accumulator += delta * float(speed)
	var processed: int = 0
	while _accumulator >= tick_seconds and processed < MAX_CATCH_UP_TICKS:
		_accumulator -= tick_seconds
		tick_index += 1
		elapsed_game_seconds += tick_seconds
		processed += 1
		tick.emit(tick_index)

	# 长时间卡顿后丢弃堆积，避免一次性补算大量 tick。
	if _accumulator > tick_seconds * float(MAX_CATCH_UP_TICKS):
		_accumulator = fmod(_accumulator, tick_seconds)


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


func set_speed(value: int) -> void:
	var clamped: int = clampi(value, 1, 5)
	if speed == clamped:
		return
	speed = clamped
	speed_changed.emit(speed)


func reset() -> void:
	tick_index = 0
	elapsed_game_seconds = 0.0
	_accumulator = 0.0


func get_time_text() -> String:
	var total: int = int(elapsed_game_seconds)
	return "%02d:%02d" % [int(total / 60.0), total % 60]
