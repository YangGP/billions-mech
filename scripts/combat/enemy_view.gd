class_name EnemyView
extends Node2D
## 敌人视觉：灰盒圆形 + 血条。只读取 EnemyState，不修改模拟数据。

var _enemy: EnemyState


func setup(enemy: EnemyState) -> void:
	_enemy = enemy
	position = enemy.position
	queue_redraw()


func _process(_delta: float) -> void:
	if _enemy == null:
		return
	position = _enemy.position
	queue_redraw()


func _draw() -> void:
	if _enemy == null:
		return

	# 地面阴影（压扁的椭圆）
	draw_set_transform(Vector2(0.0, 0.0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2(0.0, 0.0), 14.0, Color(0.0, 0.0, 0.0, 0.25))
	draw_set_transform(Vector2(0.0, 0.0), 0.0, Vector2.ONE)

	# 身体与头部
	draw_circle(Vector2(0.0, -10.0), 11.0, Color(0.12, 0.2, 0.08, 1.0))
	draw_circle(Vector2(0.0, -11.0), 9.0, Color(0.45, 0.75, 0.3, 1.0))
	draw_circle(Vector2(-3.0, -13.0), 1.6, Color(0.1, 0.05, 0.05, 1.0))
	draw_circle(Vector2(3.0, -13.0), 1.6, Color(0.1, 0.05, 0.05, 1.0))

	var ratio := clampf(float(_enemy.hp) / float(maxi(1, _enemy.max_hp)), 0.0, 1.0)
	draw_rect(Rect2(-14.0, -34.0, 28.0, 4.0), Color(0.0, 0.0, 0.0, 0.75))
	draw_rect(Rect2(-14.0, -34.0, 28.0 * ratio, 4.0), Color(0.9, 0.2, 0.15, 1.0))
