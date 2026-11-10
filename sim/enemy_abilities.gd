class_name MechEnemyAbilities
extends RefCounted
## 小量精英能力的业务适配；只写模拟实例，复用网格LOS及统一伤害入口。

var _scavengers: Array[MechEntityState] = []


## 每战斗tick收集一次精英源，死亡事件只遍历少量拾荒者。
func prepare(registry: MechEntityRegistry) -> void:
	_scavengers.clear()
	for entity: MechEntityState in registry.all():
		if entity.hp > 0 and entity.enemy_definition != null and entity.enemy_definition.scavenge_radius > 0.0:
			_scavengers.append(entity)


func note_death(dead: MechEntityState) -> void:
	for source: MechEntityState in _scavengers:
		if source.hp <= 0 or source.entity_id == dead.entity_id:
			continue
		var rules: MechEnemyDefinition = source.enemy_definition
		if source.position.distance_to(dead.position) <= rules.scavenge_radius:
			var gain: float = float(dead.max_hp) * rules.scavenge_armor_ratio
			source.scavenge_armor = minf(rules.scavenge_max_armor, source.scavenge_armor + gain)


func armor(entity: MechEntityState) -> float:
	if entity.enemy_definition == null:
		return 0.0
	return minf(entity.enemy_definition.scavenge_max_armor, entity.scavenge_armor)


func _end_jam(building: MechBuildingState) -> void:
	building.jam_ticks = 0
	building.jam_source_id = 0
	building.jam_immunity_ticks = maxi(building.jam_immunity_ticks, building.jam_recovery_ticks)
	building.jam_recovery_ticks = 0


## 死亡当次就撤销干扰，后续同tick炮塔可按正常规则开火。
func release_source(id: int, buildings: Array[MechBuildingState]) -> void:
	for building: MechBuildingState in buildings:
		if building.jam_source_id == id:
			_end_jam(building)


## 敌人移动后再验证连接，不重复推进计时；范围/LOS失效当次恢复火力。
func validate_links(registry: MechEntityRegistry, buildings: Array[MechBuildingState], grid: MechGridState) -> void:
	for building: MechBuildingState in buildings:
		if building.jam_source_id <= 0:
			continue
		var source: MechEntityState = registry.get_entity(building.jam_source_id)
		if source == null or source.hp <= 0 or not _can_jam(source, building, grid):
			_end_jam(building)
			if source != null:
				source.jam_target_id = 0


func advance(registry: MechEntityRegistry, buildings: Array[MechBuildingState], grid: MechGridState,
		hz: int, max_jammed: int) -> void:
	var active: int = 0
	for building: MechBuildingState in buildings:
		building.jam_immunity_ticks = maxi(0, building.jam_immunity_ticks - 1)
		if building.jam_source_id <= 0:
			continue
		building.jam_ticks = maxi(0, building.jam_ticks - 1)
		var source: MechEntityState = registry.get_entity(building.jam_source_id)
		if building.jam_ticks == 0 or source == null or source.hp <= 0 or not _can_jam(source, building, grid):
			_end_jam(building)
		else:
			active += 1
	for source: MechEntityState in registry.all():
		if source.hp <= 0 or source.enemy_definition == null:
			continue
		source.speed_boost_ticks = maxi(0, source.speed_boost_ticks - 1)
		source.ability_cooldown_ticks = maxi(0, source.ability_cooldown_ticks - 1)
		var rules: MechEnemyDefinition = source.enemy_definition
		if rules.jam_range <= 0.0:
			continue
		var ongoing: bool = false
		for building: MechBuildingState in buildings:
			if building.entity_id == source.jam_target_id and building.jam_source_id == source.entity_id:
				ongoing = true
				break
		if ongoing:
			continue
		source.jam_target_id = 0
		if active >= max_jammed or source.ability_cooldown_ticks > 0:
			continue
		var nearest: MechBuildingState
		var distance: float = INF
		for building: MechBuildingState in buildings:
			if building.jam_ticks > 0 or building.jam_immunity_ticks > 0 or not _can_jam(source, building, grid):
				continue
			var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
			var next_distance: float = source.position.distance_squared_to(center)
			if next_distance < distance:
				nearest = building
				distance = next_distance
		if nearest == null:
			continue
		nearest.jam_ticks = maxi(1, ceili(rules.jam_seconds * hz))
		nearest.jam_recovery_ticks = maxi(1, ceili(rules.jam_immunity_seconds * hz))
		nearest.jam_source_id = source.entity_id
		source.jam_target_id = nearest.entity_id
		source.speed_boost_ticks = maxi(1, ceili(rules.boost_seconds * hz))
		source.ability_cooldown_ticks = maxi(1, ceili(rules.jam_cooldown_seconds * hz))
		active += 1


func _can_jam(source: MechEntityState, building: MechBuildingState, grid: MechGridState) -> bool:
	if source.enemy_definition == null or not building.operating() or building.definition.attack_damage <= 0:
		return false
	var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
	var radius: float = minf(source.enemy_definition.jam_range, source.enemy_definition.vision_radius)
	return source.position.distance_to(center) <= radius and grid.terrain_line_clear(source.position, center)
