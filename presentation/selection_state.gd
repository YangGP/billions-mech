class_name MechSelectionState
extends RefCounted
## 纯客户端的选择与编组状态。不产生任何模拟层变更。

var ids: Array[int] = []
var groups: Dictionary[int, Array] = {}


## 清空选择与编组。
func reset() -> void:
	ids.clear()
	groups.clear()


## 更新选择集：additive 追加、toggle 切换，默认整体替换。
func select(next: Array[int], additive: bool = false, toggle: bool = false) -> void:
	if not additive and not toggle:
		ids.clear()
	for id: int in next:
		if toggle and id in ids:
			ids.erase(id)
		elif not id in ids:
			ids.append(id)


## 按存活实体裁剪选择；驻防中的友军不可下达地面指令，
## 但其编组必须在整个进出碉堡期间保留。
func reconcile(entities: Array, garrisoned_unit_ids: Array = []) -> void:
	var live: Dictionary = {}
	for entity: Dictionary in entities:
		if entity.get("team", 1) == 1:
			live[entity["id"]] = true
	ids.assign(ids.filter(func(id: int) -> bool: return live.has(id)))
	# 驻防的友军不可下达地面指令，但其编组在进出碉堡期间必须保留。
	for id: int in garrisoned_unit_ids:
		live[id] = true
	for key: int in groups:
		groups[key] = groups[key].filter(func(id: int) -> bool: return live.has(id))


func store_group(key: int) -> void:
	groups[key] = ids.duplicate()


func recall_group(key: int) -> void:
	ids.assign(groups.get(key, []))
