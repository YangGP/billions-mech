class_name EnemyState
extends RefCounted
## 单个敌人的模拟状态。位置使用世界坐标，由 ThreatSystem 推进。

var enemy_id: int = 0
var position: Vector2 = Vector2.ZERO
var hp: int = 0
var max_hp: int = 0
var speed: float = 90.0
var damage: int = 4
var attack_interval: float = 1.0
var attack_timer: float = 0.0
var target_instance_id: StringName = &""
