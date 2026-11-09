class_name MechTowerSystem
extends RefCounted
## 哨戒炮塔自动开火（values.md §4/§11）：运行中的炮塔仅在冷却结束时才搜索
## 射程内最近敌人，把扫描成本摊销到开火时刻。命中以结果列表返回；
## 伤害、移除与死亡记账由 SimCore 统一执行。只有可见且地形通视的目标才有效。

## 曳光弹显示时长（秒）；与单位枪口闪光保持一致。
const SHOT_FLASH_SECONDS: float = 0.1

## 战斗级噪声发射器（由 SimCore 注入）；每次命中的落点触发一次。
var combat_noise: Callable = Callable()


## 推进所有炮塔一个 tick，返回本 tick 的命中结果列表。
func advance(registry: MechEntityRegistry, buildings: Array[MechBuildingState], hz: int, grid: MechGridState, vision: MechVisionSystem) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for building: MechBuildingState in buildings:
		if building.definition.attack_damage <= 0:
			continue
		building.attack_cooldown_ticks = maxi(0, building.attack_cooldown_ticks - 1)
		building.shot_ticks = maxi(0, building.shot_ticks - 1)
		if not building.operating() or building.attack_cooldown_ticks > 0:
			continue
		var center: Vector2 = Vector2(building.origin) + Vector2(building.definition.footprint) * 0.5
		var target: MechEntityState = _nearest_enemy(registry, center, building.definition.attack_range, grid, vision)
		if target == null:
			continue
		building.attack_cooldown_ticks = maxi(1, ceili(building.definition.attack_seconds * hz))
		building.shot_ticks = maxi(1, ceili(SHOT_FLASH_SECONDS * hz))
		building.shot_target = target.position
		var impacted: Dictionary[int, bool] = {}
		impacted[target.entity_id] = true
		hits.append({"id": target.entity_id, "damage": building.definition.attack_damage,
			"slow_multiplier": building.definition.slow_multiplier,
			"slow_seconds": building.definition.slow_seconds})
		if building.definition.splash_radius > 0.0:
			for entity: MechEntityState in registry.all():
				if entity.team != 2 or entity.hp <= 0 or impacted.has(entity.entity_id):
					continue
				if not vision.is_visible(entity.position):
					continue
				if target.position.distance_to(entity.position) > building.definition.splash_radius:
					continue
				if not grid.terrain_line_clear(target.position, entity.position):
					continue
				impacted[entity.entity_id] = true
				hits.append({"id": entity.entity_id, "damage": building.definition.attack_damage,
					"slow_multiplier": building.definition.slow_multiplier,
					"slow_seconds": building.definition.slow_seconds})
		if combat_noise.is_valid():
			combat_noise.call(target.position)
	return hits


func _nearest_enemy(registry: MechEntityRegistry, center: Vector2, range_cells: float, grid: MechGridState, vision: MechVisionSystem) -> MechEntityState:
	# 队伍 2 同时覆盖波次敌人和练习靶；训练场景兼作炮塔火力的测试靶场。
	var best: float = range_cells * range_cells
	var result: MechEntityState
	for entity: MechEntityState in registry.all():
		if entity.team != 2 or entity.hp <= 0 or not vision.is_visible(entity.position):
			continue
		var distance: float = center.distance_squared_to(entity.position)
		if distance <= best and grid.terrain_line_clear(center, entity.position):
			best = distance
			result = entity
	return result
