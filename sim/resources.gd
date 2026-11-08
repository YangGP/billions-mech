class_name MechResources
extends RefCounted
## Five stable resource IDs over Godot's native Dictionary. Amounts are integers.

const KEYS: Array[StringName] = [&"coins", &"metal_ore", &"fuel", &"alloy", &"crystals"]
const NAMES: Array[String] = ["算力币", "金属矿", "燃料", "合金", "稀有晶体"]
const WORTH: Array[int] = [1, 2, 2, 3, 10]


static func empty() -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for key: StringName in KEYS:
		result[key] = 0
	return result


static func copy(amount: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = empty()
	for key: StringName in KEYS:
		result[key] = int(amount.get(key, 0))
	return result


static func single(key: StringName, amount: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = empty()
	assert(key in KEYS)
	result[key] = amount
	return result


static func valid(amount: Dictionary) -> bool:
	for key: Variant in amount:
		if not key is StringName and not key is String:
			return false
		if StringName(key) not in KEYS or not amount[key] is int or amount[key] < 0:
			return false
	return true


static func mineable(key: StringName) -> bool:
	return key in [&"metal_ore", &"fuel", &"crystals"]


static func text(amount: Dictionary) -> String:
	var parts := PackedStringArray()
	for index: int in range(KEYS.size()):
		var value: int = int(amount.get(KEYS[index], 0))
		if value != 0:
			parts.append("%d %s" % [value, NAMES[index]])
	return " + ".join(parts) if not parts.is_empty() else "0 算力币"


static func add(left: Dictionary, right: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = copy(left)
	for key: StringName in KEYS:
		result[key] += int(right.get(key, 0))
	return result


static func subtract(left: Dictionary, right: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = copy(left)
	for key: StringName in KEYS:
		result[key] -= int(right.get(key, 0))
	return result


static func scaled(amount: Dictionary, ratio: float) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = empty()
	for key: StringName in KEYS:
		result[key] = floori(int(amount.get(key, 0)) * ratio)
	return result


static func worth(amount: Dictionary) -> int:
	var result: int = 0
	for index: int in range(KEYS.size()):
		result += int(amount.get(KEYS[index], 0)) * WORTH[index]
	return result
