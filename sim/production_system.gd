class_name MechProductionSystem
extends RefCounted
## 预付费、占容预留、各工厂相互独立的生产队列。

var _queues: Dictionary[int, Array] = {}
var _rallies: Dictionary[int, Vector2i] = {}
var _blocked: Dictionary[int, bool] = {}
var _next_ticket: int = 1
## 终态回执：空退款表示已交付或已损失，绝不表示取消。
var order_finished: Callable


## 清空全部队列与集结点。
func clear() -> void:
	_queues.clear()
	_rallies.clear()
	_blocked.clear()
	_next_ticket = 1


## 注册工厂并初始化空队列；集结点默认在脚印下方一格。
func register_factory(building: MechBuildingState) -> void:
	if building.definition.produced_units.is_empty():
		return
	_queues[building.entity_id] = []
	_rallies[building.entity_id] = building.origin + Vector2i(0, building.definition.footprint.y)
	# 重建的工厂是全新队列；残留的受阻标志会让空工厂永远显示“出口受阻”。
	_blocked.erase(building.entity_id)


## 全部队列合计占用的算力容量。
func reserved_capacity() -> int:
	var result: int = 0
	for queue: Array in _queues.values():
		for item: Dictionary in queue:
			result += item["capacity_cost"]
	return result


## 生产下单校验：工厂、供电、队列上限与经济逐项检查，返回中文原因。
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


## 入队一个生产订单并返回票据号（费用已在下单时原子扣除）。
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


## 取消订单并返回全额退款；同时以退款作为终态回执。
func cancel(factory_id: int, ticket: int) -> Dictionary:
	var queue: Array = _queues.get(factory_id, [])
	for index: int in range(queue.size()):
		var item: Dictionary = queue[index]
		if item["ticket"] == ticket:
			queue.remove_at(index)
			if order_finished.is_valid():
				order_finished.call(ticket, MechResources.copy(item["paid_cost"]))
			_blocked.erase(factory_id)
			# 退款是对外结果；绝不把队列项的可变字典交出去。
			return MechResources.copy(item["paid_cost"])
	return MechResources.empty()


## 拆除工厂：refund_orders 决定未完成订单是否退款；返回合计退款。
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


## 推进队首订单；完成时经 spawn 回调出生，出生失败标记出口受阻。
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
