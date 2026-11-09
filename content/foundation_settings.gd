class_name MechFoundationSettings
extends Resource
## 开局与全局设置：一局的全部启动数据。

## 会话随机种子。
@export var session_seed: int = 1
## 重建用的启动数据；不含场景或旧资源。

## 模拟固定步频（Hz）。
@export_range(10, 120, 1) var simulation_hz: int = 30
@export var map_definition: MechMapDefinition
@export var building_definitions: Array[MechBuildingDefinition] = []
@export var starting_resources: Dictionary[StringName, int] = {&"coins": 250, &"metal_ore": 50}
@export var scenario_name: String = "标准开局"
@export var unit_definitions: Array[MechUnitDefinition] = []
@export var starting_unit_id: StringName = &"sentinel"
@export var starting_buildings: Dictionary[Vector2i, StringName] = {}
@export var starting_unit_cells: Array[Vector2i] = []
@export var practice_target_cells: Array[Vector2i] = []
@export_range(0.1, 10.0, 0.1) var probe_speed: float = 2.5
@export_range(0.5, 64.0, 0.5) var probe_sight_radius: float = 7.0
## 仅供旧视野测试/诊断使用的免费校验实体。正常游戏绝不能把它算作额外单位。
@export var diagnostic_probe_enabled: bool = false

## 首波触发模式的迁移开关。开发模式保留旧的“静默或 8 个运转节点”触发；
## 定时模式无视开发指标，只用 silence_seconds + wave_announce_seconds
## （P2d 切换标准配置）。
enum WaveTrigger { DEVELOPMENT_OR_TIME, TIME_ONLY, DEVELOPMENT_SCORE }

## 威胁方（values.md 	2/	12/	13/	15）。训练关卡保持 threat_enabled 关闭。
@export var enemy_definitions: Array[MechEnemyDefinition] = []
@export var threat_enabled: bool = true
@export var wave_trigger_mode: WaveTrigger = WaveTrigger.DEVELOPMENT_OR_TIME
@export_range(0.0, 3600.0, 1.0) var silence_seconds: float = 600.0
@export_range(1.0, 300.0, 1.0) var wave_announce_seconds: float = 30.0
@export_range(10.0, 1200.0, 1.0) var wave_interval_seconds: float = 600.0
## TAB 式：每一波在此时长内从边缘带持续涌入。
@export_range(5.0, 600.0, 1.0) var wave_release_seconds: float = 300.0
@export_range(1.0, 500.0, 1.0) var first_wave_budget: float = 25.0
## 波次预算的逐波增长倍率。
@export_range(1.0, 3.0, 0.01) var wave_budget_growth: float = 1.6
@export_range(1, 32, 1) var development_node_threshold: int = 8
## P8 候选指标：净调度 + 军事规模。正式首波规则仍待交接验收；
## development_node_threshold 仅供旧模式使用。
@export_range(1, 200, 1) var development_score_threshold: int = 24
## 每隔多少波附加一次侧翼波。
@export_range(2, 32, 1) var flank_wave_interval: int = 4
## 战役模式下波次持续到来，直至显式请求终波；现有验收切片仍以四波模式为默认。
@export var campaign_mode: bool = false
@export_range(100.0, 5000.0, 10.0) var final_wave_budget: float = 2000.0
## 首切片胜利门槛（开发计划 M6）：0 = 无尽波次；否则导演在这么多波后停止，清场即胜。
@export_range(0, 32, 1) var total_waves: int = 4
## 噪声半径与感染转化（values.md 	13/	14）。
@export_range(1.0, 64.0, 1.0) var noise_radius_combat: float = 24.0
@export_range(1.0, 64.0, 1.0) var noise_radius_construction: float = 12.0
@export_range(1.0, 64.0, 1.0) var noise_radius_operation: float = 6.0
@export_range(1.0, 32.0, 1.0) var noise_radius_movement: float = 8.0
@export_range(1.0, 100.0, 1.0) var infection_value_divisor: float = 20.0
