class_name MechDispatchModel
extends RefCounted
## P7a 的纯数据区域授权模型。绝不改动世界、钱包或实体表；
## 自动化消费方必须通过常规命令生效。

var _regions: Dictionary[int, Dictionary] = {}
var _next_region_id: int = 1
## 会话代号：重开局后旧授权全部失效。
var _generation: int = 0


## 清空全部区域并推进会话代号。
func reset() -> void:
	_regions.clear()
	_next_region_id = 1
	_generation += 1


func generation() -> int:
	return _generation


## 创建区域并返回新 ID；预算上限、已提交与已花费各自独立记账。
func create_region(cells: Array[Vector2i], budget_cap: Dictionary, name: String = "", enabled: bool = true) -> int:
	var id: int = _next_region_id
	_next_region_id += 1
	_regions[id] = {"id": id, "name": name, "cells": cells.duplicate(),
		"enabled": enabled, "budget_cap": MechResources.copy(budget_cap),
		"committed": MechResources.empty(), "spent": MechResources.empty(), "tasks": {},
		"generation": _generation, "failure_reason": "",
		"failure_count": 0, "retry_at_tick": 0,
		"last_order_id": 0, "last_order_tick": 0}
	return id


func remove_region(id: int) -> void:
	_regions.erase(id)


func has_region(id: int) -> bool:
	return _regions.has(id)


func update_region(id: int, cells: Array[Vector2i], budget_cap: Dictionary, enabled: bool) -> bool:
	if not _regions.has(id):
		return false
	var spent: Dictionary = _regions[id].get("spent", MechResources.empty())
	_regions[id]["cells"] = cells.duplicate()
	_regions[id]["budget_cap"] = MechResources.copy(budget_cap)
	_regions[id]["enabled"] = enabled
	# 重新授权不抹除已花费预算，否则切换 F8 会重置上限、放开无限支出。
	_regions[id]["spent"] = MechResources.copy(spent)
	_regions[id]["failure_count"] = 0
	_regions[id]["retry_at_tick"] = 0
	return true


func set_enabled(id: int, enabled: bool) -> bool:
	if not _regions.has(id):
		return false
	_regions[id]["enabled"] = enabled
	if not enabled:
		_regions[id]["failure_reason"] = "手动接管"
	return true


## 失败后是否已到退避重试时间。
func can_retry(id: int, tick: int) -> bool:
	return _regions.has(id) and tick >= int(_regions[id].get("retry_at_tick", 0))


## 记录一次失败并按指数退避安排重试（30 tick 起，上限 300）。
func note_failure(id: int, tick: int) -> void:
	if not _regions.has(id):
		return
	var count: int = int(_regions[id].get("failure_count", 0)) + 1
	_regions[id]["failure_count"] = count
	var delay: int = mini(300, 30 << mini(4, count - 1))
	_regions[id]["retry_at_tick"] = tick + delay


## 记录一次成功，清零失败计数与退避。
func note_success(id: int) -> void:
	if _regions.has(id):
		_regions[id]["failure_count"] = 0
		_regions[id]["retry_at_tick"] = 0


## 预算提交：在 已花费＋已提交＋本次 上限内锁定一个任务；重复任务号拒绝。
func commit(id: int, task_id: String, cost: Dictionary, generation: int) -> bool:
	if not _regions.has(id) or not _regions[id]["enabled"] or generation != _generation or not MechResources.valid(cost):
		return false
	var committed: Dictionary = _regions[id]["committed"]
	var spent: Dictionary = _regions[id]["spent"]
	var cap: Dictionary = _regions[id]["budget_cap"]
	for key: StringName in MechResources.KEYS:
		if int(cost.get(key, 0)) <= 0:
			continue
		if int(spent.get(key, 0)) + int(committed.get(key, 0)) + int(cost[key]) > int(cap.get(key, 0)):
			_regions[id]["failure_reason"] = "预算上限不足"
			return false
	var tasks: Dictionary = _regions[id]["tasks"]
	if tasks.has(task_id):
		return false
	for key: StringName in MechResources.KEYS:
		if int(cost.get(key, 0)) > 0:
			committed[key] = int(committed.get(key, 0)) + int(cost[key])
	tasks[task_id] = {"generation": generation, "cost": MechResources.copy(cost)}
	_regions[id]["failure_reason"] = ""
	return true


func rename_task(id: int, old_task: String, new_task: String) -> bool:
	if not _regions.has(id):
		return false
	var tasks: Dictionary = _regions[id]["tasks"]
	if not tasks.has(old_task) or tasks.has(new_task):
		return false
	tasks[new_task] = tasks[old_task]
	tasks.erase(old_task)
	return true


## 任务成交结算：提交转已花费，记录最近一次下单号与 tick。
func settle(id: int, task_id: String, order_id: int = 0, tick: int = 0) -> bool:
	if not _regions.has(id):
		return false
	var tasks: Dictionary = _regions[id]["tasks"]
	if not tasks.has(task_id):
		return false
	var cost: Dictionary = tasks[task_id]["cost"]
	var committed: Dictionary = _regions[id]["committed"]
	var spent: Dictionary = _regions[id]["spent"]
	for key: StringName in MechResources.KEYS:
		var amount: int = int(cost.get(key, 0))
		committed[key] = maxi(0, int(committed.get(key, 0)) - amount)
		spent[key] = int(spent.get(key, 0)) + amount
	tasks.erase(task_id)
	if order_id > 0:
		_regions[id]["last_order_id"] = order_id
		_regions[id]["last_order_tick"] = tick
	return true


## 放弃任务：解除提交但不计为已花费（未成交）。
func release(id: int, task_id: String) -> bool:
	if not _regions.has(id):
		return false
	var tasks: Dictionary = _regions[id]["tasks"]
	if not tasks.has(task_id):
		return false
	var cost: Dictionary = tasks[task_id]["cost"]
	var committed: Dictionary = _regions[id]["committed"]
	for key: StringName in MechResources.KEYS:
		committed[key] = maxi(0, int(committed.get(key, 0)) - int(cost.get(key, 0)))
	tasks.erase(task_id)
	return true


func task_ids(id: int) -> Array[String]:
	var result: Array[String] = []
	if _regions.has(id):
		for task_id: String in _regions[id]["tasks"]:
			result.append(task_id)
	return result


func set_budget_cap(id: int, cap: Dictionary) -> bool:
	if not _regions.has(id):
		return false
	_regions[id]["budget_cap"] = MechResources.copy(cap)
	return true


func set_failure(id: int, reason: String) -> void:
	if _regions.has(id):
		_regions[id]["failure_reason"] = reason


func region_ids() -> Array[int]:
	var result: Array[int] = []
	for id: int in _regions:
		result.append(id)
	return result


func snapshot() -> Dictionary:
	var regions: Array[Dictionary] = []
	for id: int in _regions:
		var region: Dictionary = _regions[id].duplicate(true)
		region["budget_cap"] = MechResources.copy(region["budget_cap"])
		region["committed"] = MechResources.copy(region["committed"])
		region["spent"] = MechResources.copy(region["spent"])
		regions.append(region)
	return {"generation": _generation, "regions": regions}


## 维修预留只在钱包交易成功时才消耗。额外损伤可能需要补价；
## 补价部分仍按同一上限授权。
func can_consume(id: int, task_id: String, cost: Dictionary) -> bool:
	if not _regions.has(id) or not _regions[id]["enabled"] or not MechResources.valid(cost):
		return false
	var region: Dictionary = _regions[id]
	var task: Dictionary = region["tasks"].get(task_id, {})
	if task.is_empty() or int(task["generation"]) != _generation:
		return false
	for key: StringName in MechResources.KEYS:
		var extra: int = maxi(0, int(cost.get(key, 0)) - int(task["cost"].get(key, 0)))
		if int(region["spent"].get(key, 0)) + int(region["committed"].get(key, 0)) + extra > int(region["budget_cap"].get(key, 0)):
			_regions[id]["failure_reason"] = "维修预算已用尽"
			return false
	return true


## 消耗维修预留：实际花费超出预留的部分计入已花费。
func consume(id: int, task_id: String, cost: Dictionary) -> bool:
	if not can_consume(id, task_id, cost):
		return false
	var region: Dictionary = _regions[id]
	var held: Dictionary = region["tasks"][task_id]["cost"]
	for key: StringName in MechResources.KEYS:
		var amount: int = int(cost.get(key, 0))
		var used: int = mini(amount, int(held.get(key, 0)))
		held[key] = int(held.get(key, 0)) - used
		region["committed"][key] = maxi(0, int(region["committed"].get(key, 0)) - used)
		region["spent"][key] = int(region["spent"].get(key, 0)) + amount
	return true


## 退款冲减已花费（拆除退款回流区域预算）。
func refund_spent(id: int, refund: Dictionary) -> void:
	if not _regions.has(id) or not MechResources.valid(refund):
		return
	var spent: Dictionary = _regions[id]["spent"]
	for key: StringName in MechResources.KEYS:
		spent[key] = maxi(0, int(spent.get(key, 0)) - int(refund.get(key, 0)))
