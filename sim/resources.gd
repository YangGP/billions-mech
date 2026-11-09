class_name MechResources
extends RefCounted
## 五种稳定资源 ID 的纯静态工具集，基于 Godot 原生 Dictionary；数量均为整数。

## 资源 ID 顺序与 NAMES、WORTH 一一对应。
const KEYS: Array[StringName] = [&"coins", &"metal_ore", &"fuel", &"alloy", &"crystals"]
const NAMES: Array[String] = ["算力币", "金属矿", "燃料", "合金", "稀有晶体"]
## 感疫折算用的价值权重（values.md §14）。
const WORTH: Array[int] = [1, 2, 2, 3, 10]


## 全零资源字典。
static func empty() -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for key: StringName in KEYS:
		result[key] = 0
	return result


## 拷贝为键齐全的类型化资源字典；缺失键按 0 补齐。
static func copy(amount: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = empty()
	for key: StringName in KEYS:
		result[key] = int(amount.get(key, 0))
	return result


## 只含一种资源的字典；断言要求 key 必须是已知资源。
static func single(key: StringName, amount: int) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = empty()
	assert(key in KEYS)
	result[key] = amount
	return result


## 校验字典可安全作为资源金额使用：键已知、值为非负整数。
static func valid(amount: Dictionary) -> bool:
	for key: Variant in amount:
		if not key is StringName and not key is String:
			return false
		if StringName(key) not in KEYS or not amount[key] is int or amount[key] < 0:
			return false
	return true


## 该资源是否为可采集矿物（金属矿、燃料、稀有晶体）。
static func mineable(key: StringName) -> bool:
	return key in [&"metal_ore", &"fuel", &"crystals"]


## 格式化为中文摘要文本，零值省略；全空时显示“0 算力币”。
static func text(amount: Dictionary) -> String:
	var parts := PackedStringArray()
	for index: int in range(KEYS.size()):
		var value: int = int(amount.get(KEYS[index], 0))
		if value != 0:
			parts.append("%d %s" % [value, NAMES[index]])
	return " + ".join(parts) if not parts.is_empty() else "0 算力币"


## 逐项相加，返回新字典。
static func add(left: Dictionary, right: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = copy(left)
	for key: StringName in KEYS:
		result[key] += int(right.get(key, 0))
	return result


## 逐项相减，返回新字典；结果可以为负（调用方自行校验）。
static func subtract(left: Dictionary, right: Dictionary) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = copy(left)
	for key: StringName in KEYS:
		result[key] -= int(right.get(key, 0))
	return result


## 按比例向下取整缩放。
static func scaled(amount: Dictionary, ratio: float) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = empty()
	for key: StringName in KEYS:
		result[key] = floori(int(amount.get(key, 0)) * ratio)
	return result


## 按 WORTH 权重折算总价值（感疫生成数量的基数）。
static func worth(amount: Dictionary) -> int:
	var result: int = 0
	for index: int in range(KEYS.size()):
		result += int(amount.get(KEYS[index], 0)) * WORTH[index]
	return result
