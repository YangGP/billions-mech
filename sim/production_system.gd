class_name MechProductionSystem
extends RefCounted
## Prepaid, capacity-reserved, independent factory queues.

var _queues: Dictionary[int, Array] = {}
var _rallies: Dictionary[int, Vector2i] = {}
var _blocked: Dictionary[int, bool] = {}
var _next_ticket: int = 1
## Terminal receipt: an empty refund means delivered or lost, never cancelled.
var order_finished: Callable


func clear() -> void:
	_queues.clear()
	_rallies.clear()
	_blocked.clear()
	_next_ticket = 1


func register_factory(building: MechBuildingState) -> void:
	if building.definition.produced_units.is_empty():
		return
	_queues[building.entity_id] = []
	_rallies[building.entity_id] = building.origin + Vector2i(0, building.definition.footprint.y)
	# A rebuilt factory is a fresh queue; a stale blocked flag would otherwise
	# keep the empty factory reporting "出口受阻" forever.
	_blocked.erase(building.entity_id)


func reserved_capacity() -> int:
	var result: int = 0
	for queue: Array in _queues.values():
		for item: Dictionary in queue:
			result += item["capacity_cost"]
	return result


func order_error(building: MechBuildingState, rules: MechUnitDefinition, economy: MechEconomySystem) -> String:
	if building == null or rules == null or rules.unit_id not in building.definition.produced_units:
		return "请选择组装厂"
	if not building.operating():
		return "工厂须已完工且正常供电"
	if not _queues.has(building.entity_id):
		return "工厂未注册生产队列"
	var queue: Array = _queues.get(building.entity_id, [])
	if queue.size() >= building.definition.queue_limit:
		return "生产队列已满"
	return economy.production_error(rules.capacity_cost, rules.cost)


func enqueue(factory_id: int, rules: MechUnitDefinition, hz: int) -> int:
	var ticket: int = _next_ticket
	_next_ticket += 1
	_queues[factory_id].append({"ticket": ticket, "unit_id": rules.unit_id, "paid_cost": MechResources.copy(rules.cost),
		"capacity_cost": rules.capacity_cost, "elapsed": 0,
		"total": maxi(1, ceili(rules.production_seconds * hz))})
	return ticket


func has_ticket(factory_id: int, ticket: int) -> bool:
	for item: Dictionary in _queues.get(factory_id, []):
		if item["ticket"] == ticket:
			return true
	return false


func cancel(factory_id: int, ticket: int) -> Dictionary:
	var queue: Array = _queues.get(factory_id, [])
	for index: int in range(queue.size()):
		var item: Dictionary = queue[index]
		if item["ticket"] == ticket:
			queue.remove_at(index)
			if order_finished.is_valid():
				order_finished.call(ticket, MechResources.copy(item["paid_cost"]))
			_blocked.erase(factory_id)
			# Refund is an external result; never hand out the queue item's
			# mutable dictionary.
			return MechResources.copy(item["paid_cost"])
	return MechResources.empty()


func remove_factory(factory_id: int, refund_orders: bool) -> Dictionary:
	var refund := MechResources.empty()
	for item: Dictionary in _queues.get(factory_id, []):
		var paid_refund: Dictionary = MechResources.copy(item["paid_cost"]) if refund_orders else MechResources.empty()
		refund = MechResources.add(refund, paid_refund)
		if order_finished.is_valid():
			order_finished.call(int(item["ticket"]), paid_refund)
	_queues.erase(factory_id)
	_rallies.erase(factory_id)
	_blocked.erase(factory_id)
	return refund


func set_rally(factory_id: int, cell: Vector2i) -> void:
	_rallies[factory_id] = cell


func snapshot(factory_id: int) -> Dictionary:
	if not _queues.has(factory_id):
		return {}
	var queue: Array = _queues[factory_id]
	var progress: float = 0.0
	if not queue.is_empty():
		progress = float(queue[0]["elapsed"]) / float(queue[0]["total"])
	return {"queue": queue.duplicate(true), "progress": progress,
		"blocked": _blocked.get(factory_id, false), "rally": _rallies[factory_id]}


func advance(construction: MechConstructionSystem, spawn: Callable) -> bool:
	var changed: bool = false
	for factory_id: int in _queues:
		var building: MechBuildingState = construction.get_building(factory_id)
		var queue: Array = _queues[factory_id]
		if building == null or not building.operating() or queue.is_empty():
			continue
		var item: Dictionary = queue[0]
		item["elapsed"] = mini(item["elapsed"] + 1, item["total"])
		if item["elapsed"] < item["total"]:
			continue
		if spawn.call(building, _rallies[factory_id], item["unit_id"]):
			queue.pop_front()
			if order_finished.is_valid():
				order_finished.call(int(item["ticket"]), MechResources.empty())
			_blocked.erase(factory_id)
			changed = true
		else:
			_blocked[factory_id] = true
	return changed
