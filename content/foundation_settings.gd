class_name MechFoundationSettings
extends Resource
## Boot data for the rebuild; no scenes or legacy resources.

@export_range(10, 120, 1) var simulation_hz: int = 30
@export var map_definition: MechMapDefinition
@export var building_definitions: Array[MechBuildingDefinition] = []
@export var starting_resources: Vector4i = Vector4i(250, 50, 0, 0)
@export var scenario_name: String = "标准开局"
@export var unit_definition: MechUnitDefinition
@export var starting_buildings: Dictionary[Vector2i, StringName] = {}
@export var starting_unit_cells: Array[Vector2i] = []
@export var practice_target_cells: Array[Vector2i] = []
@export_range(0.1, 10.0, 0.1) var probe_speed: float = 2.5

## Threat side (values.md §2/§12/§15). Training keeps threat_enabled off.
@export var enemy_definitions: Array[MechEnemyDefinition] = []
@export var threat_enabled: bool = true
@export_range(0.0, 3600.0, 1.0) var silence_seconds: float = 600.0
@export_range(1.0, 300.0, 1.0) var wave_announce_seconds: float = 30.0
@export_range(10.0, 600.0, 1.0) var wave_interval_seconds: float = 150.0
@export_range(1.0, 500.0, 1.0) var first_wave_budget: float = 25.0
@export_range(1.0, 3.0, 0.01) var wave_budget_growth: float = 1.14
@export_range(1, 32, 1) var development_node_threshold: int = 8
@export_range(2, 32, 1) var flank_wave_interval: int = 4
