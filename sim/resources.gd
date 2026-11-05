class_name MechResources
extends RefCounted
## Fixed component order for immutable costs, balances and command receipts.

const KEYS: Array[StringName] = [&"coins", &"ore", &"metal", &"rare"]
const NAMES: Array[String] = ["币", "矿石", "金属", "稀有"]


static func valid(amount: Vector4i) -> bool:
	return amount.x >= 0 and amount.y >= 0 and amount.z >= 0 and amount.w >= 0


static func text(amount: Vector4i) -> String:
	var parts := PackedStringArray()
	for index: int in range(4):
		if amount[index] != 0:
			parts.append("%d %s" % [amount[index], NAMES[index]])
	return " + ".join(parts) if not parts.is_empty() else "0 币"


static func scaled(amount: Vector4i, ratio: float) -> Vector4i:
	var result := Vector4i.ZERO
	for index: int in range(4):
		result[index] = floori(amount[index] * ratio)
	return result
