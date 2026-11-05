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
