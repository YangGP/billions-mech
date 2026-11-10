class_name MechBalanceCatalog
extends RefCounted
## 集中单位数值表加载器。JSON 存在时覆盖 settings 的单位/敌种定义；
## 缺省字段沿用对应 Resource 的默认值，便于只写需要调优的项。

static func apply(settings: MechFoundationSettings) -> String:
	if settings == null:
		return "缺少开局设置"
	var path: String = settings.balance_data_path
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return "单位数值配置为空：%s" % path
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "单位数值配置不是合法 JSON 对象：%s" % path
	var data: Dictionary = parsed
	var units: Array[MechUnitDefinition] = []
	var error: String = _read_units(data.get("units", null), units)
	if not error.is_empty():
		return error
	var enemies: Array[MechEnemyDefinition] = []
	error = _read_enemies(data.get("enemies", null), enemies)
	if not error.is_empty():
		return error
	settings.unit_definitions = units
	settings.enemy_definitions = enemies
	return ""


static func _read_units(value: Variant, output: Array[MechUnitDefinition]) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "单位数值配置缺少 units 数组"
	var items: Array = value
	if items.is_empty():
		return "单位数值配置的 units 数组为空"
	var ids: Dictionary = {}
	for item: Variant in items:
		if typeof(item) != TYPE_DICTIONARY:
			return "units 条目必须是对象"
		var entry: Dictionary = item
		var rules := MechUnitDefinition.new()
		var error: String = _fill_unit(entry, rules)
		if not error.is_empty():
			return "玩家单位配置错误：%s" % error
		error = rules.validation_error()
		if not error.is_empty():
			return "玩家单位 %s：%s" % [rules.unit_id, error]
		if ids.has(rules.unit_id):
			return "重复玩家单位编号：%s" % rules.unit_id
		ids[rules.unit_id] = true
		output.append(rules)
	return ""


static func _read_enemies(value: Variant, output: Array[MechEnemyDefinition]) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "单位数值配置缺少 enemies 数组"
	var items: Array = value
	if items.is_empty():
		return "单位数值配置的 enemies 数组为空"
	var ids: Dictionary = {}
	for item: Variant in items:
		if typeof(item) != TYPE_DICTIONARY:
			return "enemies 条目必须是对象"
		var entry: Dictionary = item
		var rules := MechEnemyDefinition.new()
		var error: String = _fill_enemy(entry, rules)
		if not error.is_empty():
			return "敌种配置错误：%s" % error
		error = rules.validation_error()
		if not error.is_empty():
			return "敌种 %s：%s" % [rules.enemy_id, error]
		if ids.has(rules.enemy_id):
			return "重复敌种编号：%s" % rules.enemy_id
		ids[rules.enemy_id] = true
		output.append(rules)
	return ""


static func _fill_unit(entry: Dictionary, rules: MechUnitDefinition) -> String:
	var type_error: String = _validate_entry(entry, rules)
	if not type_error.is_empty():
		return type_error
	rules.unit_id = StringName(str(entry.get("unit_id", "")))
	rules.display_name = str(entry.get("display_name", ""))
	var cost_data: Variant = entry.get("cost", rules.cost)
	if typeof(cost_data) != TYPE_DICTIONARY:
		return "cost 必须是对象"
	var cost_entries: Dictionary = cost_data
	var cost: Dictionary[StringName, int] = {}
	for key: Variant in cost_entries:
		if not _is_integer(cost_entries[key]):
			return "cost.%s 必须是整数" % str(key)
		cost[StringName(str(key))] = int(cost_entries[key])
	rules.cost = cost
	rules.production_seconds = _f(entry, "production_seconds", rules.production_seconds)
	rules.capacity_cost = _i(entry, "capacity_cost", rules.capacity_cost)
	rules.max_hp = _i(entry, "max_hp", rules.max_hp)
	rules.damage = _i(entry, "damage", rules.damage)
	rules.attack_seconds = _f(entry, "attack_seconds", rules.attack_seconds)
	rules.attack_range = _f(entry, "attack_range", rules.attack_range)
	rules.acquisition_range = _f(entry, "acquisition_range", rules.acquisition_range)
	rules.move_speed = _f(entry, "move_speed", rules.move_speed)
	rules.sight_radius = _f(entry, "sight_radius", rules.sight_radius)
	return ""


static func _fill_enemy(entry: Dictionary, rules: MechEnemyDefinition) -> String:
	var type_error: String = _validate_entry(entry, rules)
	if not type_error.is_empty():
		return type_error
	rules.enemy_id = StringName(str(entry.get("enemy_id", "")))
	rules.display_name = str(entry.get("display_name", ""))
	rules.max_hp = _i(entry, "max_hp", rules.max_hp)
	rules.damage = _i(entry, "damage", rules.damage)
	rules.damage_vs_building = _i(entry, "damage_vs_building", rules.damage_vs_building)
	rules.attack_seconds = _f(entry, "attack_seconds", rules.attack_seconds)
	rules.attack_range = _f(entry, "attack_range", rules.attack_range)
	rules.move_speed = _f(entry, "move_speed", rules.move_speed)
	rules.vision_radius = _f(entry, "vision_radius", rules.vision_radius)
	rules.threat_cost = _f(entry, "threat_cost", rules.threat_cost)
	rules.elite = _b(entry, "elite", rules.elite)
	rules.max_alive = _i(entry, "max_alive", rules.max_alive)
	rules.minimum_stage = _i(entry, "minimum_stage", rules.minimum_stage)
	rules.first_wave = _i(entry, "first_wave", rules.first_wave)
	rules.charge_bonus = _f(entry, "charge_bonus", rules.charge_bonus)
	rules.charge_linger_seconds = _f(entry, "charge_linger_seconds", rules.charge_linger_seconds)
	rules.ignores_rough = _b(entry, "ignores_rough", rules.ignores_rough)
	rules.prefers_towers = _b(entry, "prefers_towers", rules.prefers_towers)
	rules.splash_radius = _f(entry, "splash_radius", rules.splash_radius)
	rules.scavenge_radius = _f(entry, "scavenge_radius", rules.scavenge_radius)
	rules.scavenge_armor_ratio = _f(entry, "scavenge_armor_ratio", rules.scavenge_armor_ratio)
	rules.scavenge_max_armor = _f(entry, "scavenge_max_armor", rules.scavenge_max_armor)
	rules.jam_range = _f(entry, "jam_range", rules.jam_range)
	rules.jam_seconds = _f(entry, "jam_seconds", rules.jam_seconds)
	rules.jam_immunity_seconds = _f(entry, "jam_immunity_seconds", rules.jam_immunity_seconds)
	rules.jam_cooldown_seconds = _f(entry, "jam_cooldown_seconds", rules.jam_cooldown_seconds)
	rules.boost_seconds = _f(entry, "boost_seconds", rules.boost_seconds)
	rules.boost_speed = _f(entry, "boost_speed", rules.boost_speed)
	rules.prefers_buildings = _b(entry, "prefers_buildings", rules.prefers_buildings)
	rules.marches_to_core = _b(entry, "marches_to_core", rules.marches_to_core)
	rules.wandering_speed_ratio = _f(entry, "wandering_speed_ratio", rules.wandering_speed_ratio)
	rules.shelter_radius = _f(entry, "shelter_radius", rules.shelter_radius)
	rules.shelter_self = _b(entry, "shelter_self", rules.shelter_self)
	rules.shelter_reduction = _f(entry, "shelter_reduction", rules.shelter_reduction)
	rules.passes_walls = _b(entry, "passes_walls", rules.passes_walls)
	rules.evasion_chance = _f(entry, "evasion_chance", rules.evasion_chance)
	rules.frenzy_radius = _f(entry, "frenzy_radius", rules.frenzy_radius)
	rules.frenzy_seconds = _f(entry, "frenzy_seconds", rules.frenzy_seconds)
	rules.frenzy_speed_bonus = _f(entry, "frenzy_speed_bonus", rules.frenzy_speed_bonus)
	rules.frenzy_damage_bonus = _f(entry, "frenzy_damage_bonus", rules.frenzy_damage_bonus)
	var weights: Variant = entry.get("stage_weights", null)
	if entry.has("stage_weights"):
		if typeof(weights) != TYPE_ARRAY:
			return "stage_weights 必须是长度为 3 的数组"
		var values: Array = weights
		if values.size() != 3:
			return "stage_weights 必须是长度为 3 的数组"
		for value: Variant in values:
			if not _is_integer(value):
				return "stage_weights 必须包含整数"
			if value < 0 or value > 2147483647:
				return "stage_weights 必须是非负 32 位整数"
		rules.stage_weights = Vector3i(int(values[0]), int(values[1]), int(values[2]))
	return ""


## JSON 将数字解析为浮点数；整数栏位允许 20.0，但不允许截断或溢出。
static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value \
		and value >= -9223372036854775808.0 and value < 9223372036854775808.0


## 复用 Resource 的属性类型，在任何强制转换前校验 JSON 原值。
static func _validate_entry(entry: Dictionary, rules: Resource) -> String:
	for property: Dictionary in rules.get_property_list():
		var key: String = property["name"]
		if not entry.has(key):
			continue
		var value: Variant = entry[key]
		match int(property["type"]):
			TYPE_INT:
				if not _is_integer(value):
					return "%s 必须是整数" % key
			TYPE_FLOAT:
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
					return "%s 必须是数值" % key
				if not is_finite(float(value)):
					return "%s 必须是有限数值" % key
			TYPE_BOOL:
				if typeof(value) != TYPE_BOOL:
					return "%s 必须是布尔值" % key
			TYPE_STRING, TYPE_STRING_NAME:
				if typeof(value) != TYPE_STRING:
					return "%s 必须是字符串" % key
	return ""


static func _f(entry: Dictionary, key: String, fallback: float) -> float:
	return float(entry.get(key, fallback))


static func _i(entry: Dictionary, key: String, fallback: int) -> int:
	return int(entry.get(key, fallback))


static func _b(entry: Dictionary, key: String, fallback: bool) -> bool:
	return bool(entry.get(key, fallback))
