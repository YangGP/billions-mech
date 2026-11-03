class_name ThreatPanel
extends PanelContainer
## 威胁状态条：核心生命 / 波次倒计时 / 存活敌人。

@onready var _core_label: Label = %CoreLabel
@onready var _wave_label: Label = %WaveLabel


func display_core(current: int, maximum: int) -> void:
	_core_label.text = "核心 %d/%d" % [current, maximum]
	var ratio := float(current) / maxf(1.0, float(maximum))
	_core_label.modulate = (
		Color(1.0, 0.45, 0.4, 1.0) if ratio < 0.3 else Color.WHITE
	)


func display_wave(next_wave: int, seconds_to_next: float, alive: int, in_wave: bool) -> void:
	if in_wave:
		_wave_label.text = "第 %d 波 · 敌人 %d" % [next_wave, alive]
		_wave_label.modulate = Color(1.0, 0.75, 0.35, 1.0)
	else:
		_wave_label.text = "第 %d 波 · %02d 秒" % [next_wave, int(ceil(seconds_to_next))]
		_wave_label.modulate = Color.WHITE
