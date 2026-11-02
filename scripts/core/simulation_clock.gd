class_name SimulationClock
extends Node
## 固定步长的模拟时钟。
##
## 经济结算、建筑状态与区块统计都必须由这里驱动；不要在任何视图节点里
## 用 _process 的 delta 直接累计收益，否则帧率不同会导致结果不同。
##
## 速度只提供 1× 与更慢的档位（0.5×、0.25×），不提供加速。

signal tick(tick_index: int)
signal paused_changed(paused: bool)
signal speed_changed(speed: float)

const SPEED_OPTIONS: Array[float] = [1.0, 0.5, 0.25]
const MIN_SPEED: float = 0.1
const MAX_SPEED: float = 1.0
## 单次卡顿最多补算的 tick 数，避免断点/拖动窗口后一次性结算过量。
const MAX_CATCH_UP_TICKS: int = 5

@export var tick_seconds: float = 1.0

var tick_index: int = 0
var elapsed_game_seconds: float = 0.0
var paused: bool = false
var speed: float = 1.0

var _accumulator: float = 0.0


func setup(seconds_per_tick: float) -> void:
	tick_seconds = maxf(0.05, seconds_per_tick)
	_accumulator = 0.0


func _process(delta: float) -> void:
	if paused or speed <= 0.0:
		return

	_accumulator += delta * speed
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


func set_speed(value: float) -> void:
	var clamped := clampf(value, MIN_SPEED, MAX_SPEED)
	if is_equal_approx(speed, clamped):
		return
	speed = clamped
	speed_changed.emit(speed)


## 在 1× → 0.5× → 0.25× 之间循环，只降速不加速。
func cycle_speed() -> void:
	var index := SPEED_OPTIONS.find(speed)
	if index < 0:
		index = 0
	set_speed(SPEED_OPTIONS[(index + 1) % SPEED_OPTIONS.size()])


func get_speed_label() -> String:
	if is_equal_approx(speed, 1.0):
		return "1×"
	if is_equal_approx(speed, 0.5):
		return "0.5×"
	if is_equal_approx(speed, 0.25):
		return "0.25×"
	return "%s×" % String.num(speed, 2)


func reset() -> void:
	tick_index = 0
	elapsed_game_seconds = 0.0
	_accumulator = 0.0


func get_time_text() -> String:
	var total: int = int(elapsed_game_seconds)
	return "%02d:%02d" % [int(total / 60.0), total % 60]
