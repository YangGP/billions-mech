class_name MechTowerSystem
extends RefCounted
## Sentry-tower autofire (values.md §4/§11): an operating tower acquires the
## nearest enemy in range only when its cooldown expires, amortizing the scan
## cost to the firing moment. Hits return as results; SimCore applies damage,
## removal and death bookkeeping. Vision/LOS gating arrives with the M6 vision
## system (values.md §13 keeps tower sight pre-calibrated).

## Tracer lifetime in seconds; matches unit muzzle flashes.
const SHOT_FLASH_SECONDS: float = 0.1

## Combat-level noise emitter (set by SimCore); fired at each shot's impact point.
var combat_noise: Callable = Callable()


func advance(registry: MechEntityRegistry, buildings: Array[MechBuildingState], hz: int) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for building: MechBuildingState in buildings:
		if building.definition.attack_damage <= 0:
			continue
		building.attack_cooldown_ticks = maxi(0, building.attack_cooldown_ticks - 1)
		building.shot_ticks = maxi(0, building.shot_ticks - 1)
		if not building.operating() or building.attack_cooldown_ticks > 0:
			continue
		var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
		var target: MechEntityState = _nearest_enemy(registry, center, building.definition.attack_range)
		if target == null:
			continue
		building.attack_cooldown_ticks = maxi(1, ceili(building.definition.attack_seconds * hz))
		building.shot_ticks = maxi(1, ceili(SHOT_FLASH_SECONDS * hz))
		building.shot_target = target.position
		hits.append({"id": target.entity_id, "damage": building.definition.attack_damage})
		if combat_noise.is_valid():
			combat_noise.call(target.position)
	return hits


func _nearest_enemy(registry: MechEntityRegistry, center: Vector2, range_cells: float) -> MechEntityState:
	# Team 2 covers wave enemies and practice targets; the training scenario
	# doubles as the tower-fire test range.
	var best: float = range_cells * range_cells
	var result: MechEntityState
	for entity: MechEntityState in registry.all():
		if entity.team != 2 or entity.hp <= 0:
			continue
		var distance: float = center.distance_squared_to(entity.position)
		if distance <= best:
			best = distance
			result = entity
	return result
