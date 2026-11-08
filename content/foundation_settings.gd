class_name MechFoundationSettings
extends Resource
## Boot data for the rebuild; no scenes or legacy resources.

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

## Threat side (values.md §2/§12/§13/§15). Training keeps threat_enabled off.
@export var enemy_definitions: Array[MechEnemyDefinition] = []
@export var threat_enabled: bool = true
@export_range(0.0, 3600.0, 1.0) var silence_seconds: float = 600.0
@export_range(1.0, 300.0, 1.0) var wave_announce_seconds: float = 30.0
@export_range(10.0, 1200.0, 1.0) var wave_interval_seconds: float = 600.0
## TAB-style: each wave streams in from the edge band over this window.
@export_range(5.0, 600.0, 1.0) var wave_release_seconds: float = 300.0
@export_range(1.0, 500.0, 1.0) var first_wave_budget: float = 25.0
@export_range(1.0, 3.0, 0.01) var wave_budget_growth: float = 1.6
@export_range(1, 32, 1) var development_node_threshold: int = 8
@export_range(2, 32, 1) var flank_wave_interval: int = 4
## First-slice victory gate (development-plan M6): 0 = endless waves; otherwise
## the director stops after this many waves and a cleared field wins.
@export_range(0, 32, 1) var total_waves: int = 4
## Noise radii and infection conversion (values.md §13/§14).
@export_range(1.0, 64.0, 1.0) var noise_radius_combat: float = 24.0
@export_range(1.0, 64.0, 1.0) var noise_radius_construction: float = 12.0
@export_range(1.0, 64.0, 1.0) var noise_radius_operation: float = 6.0
@export_range(1.0, 32.0, 1.0) var noise_radius_movement: float = 8.0
@export_range(1.0, 100.0, 1.0) var infection_value_divisor: float = 20.0
