class_name MechSelectionState
extends RefCounted
## Client-only selection and groups. No simulation mutations.

var ids: Array[int] = []
var groups: Dictionary[int, Array] = {}


func reset() -> void:
	ids.clear()
	groups.clear()


func select(next: Array[int], additive: bool = false, toggle: bool = false) -> void:
	if not additive and not toggle:
		ids.clear()
	for id: int in next:
		if toggle and id in ids:
			ids.erase(id)
		elif not id in ids:
			ids.append(id)


func reconcile(entities: Array) -> void:
	var live: Dictionary = {}
	for entity: Dictionary in entities:
		if entity.get("team", 1) == 1:
			live[entity["id"]] = true
	ids.assign(ids.filter(func(id: int) -> bool: return live.has(id)))
	for key: int in groups:
		groups[key] = groups[key].filter(func(id: int) -> bool: return live.has(id))


func store_group(key: int) -> void:
	groups[key] = ids.duplicate()


func recall_group(key: int) -> void:
	ids.assign(groups.get(key, []))
