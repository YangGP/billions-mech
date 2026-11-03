class_name CombatEffects
extends Node2D
## 战斗表现：防御塔射击的短暂光线。只负责画面，不参与伤害计算。

const LIFETIME: float = 0.12

var _shots: Array[Dictionary] = []


func add_shot(from: Vector2, to: Vector2) -> void:
	_shots.append({
		"from": to_local(from),
		"to": to_local(to),
		"life": LIFETIME,
	})
	queue_redraw()


func _process(delta: float) -> void:
	if _shots.is_empty():
		return

	var alive: Array[Dictionary] = []
	for shot in _shots:
		shot["life"] = float(shot["life"]) - delta
		if float(shot["life"]) > 0.0:
			alive.append(shot)
	_shots = alive
	queue_redraw()


func _draw() -> void:
	for shot in _shots:
		var alpha := clampf(float(shot["life"]) / LIFETIME, 0.0, 1.0)
		draw_line(
			shot["from"],
			shot["to"],
			Color(1.0, 0.85, 0.35, alpha),
			3.0,
			true
		)
