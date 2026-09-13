class_name CoreStorage
extends RefCounted
## Глобальный склад ядра: запасы с лимитом на каждый предмет, счётчики доставки.
## Сверх лимита предметы сжигаются, но доставка всё равно засчитывается (для разблокировок и контрактов).
## Возврат стоимости при сносе доставкой не считается — иначе стройка/снос давали бы бесконечный прогресс.


## Бюджет для планирования ряда построек (протягивание): копия запасов, из которой вычитается стоимость.
class Budget:
	var counts: PackedInt32Array

	func _init(p_counts: PackedInt32Array) -> void:
		counts = p_counts.duplicate()

	func can_afford(cost: Array[ItemStack]) -> bool:
		for stack in cost:
			if counts[stack.item.index] < stack.amount:
				return false
		return true

	func reserve(cost: Array[ItemStack]) -> bool:
		if not can_afford(cost):
			return false
		for stack in cost:
			counts[stack.item.index] -= stack.amount
		return true

	func add(cost: Array[ItemStack]) -> void:
		for stack in cost:
			counts[stack.item.index] += stack.amount


var capacity: int = 4000
var counts: PackedInt32Array
var delivered: PackedInt64Array
var burned: PackedInt64Array
## Увеличивается при любом изменении запасов — интерфейс сравнивает и обновляется.
var revision: int = 0

var _stats: ItemStats


func _init(item_count: int, p_capacity: int, stats: ItemStats) -> void:
	capacity = p_capacity
	_stats = stats
	counts.resize(item_count)
	counts.fill(0)
	delivered.resize(item_count)
	delivered.fill(0)
	burned.resize(item_count)
	burned.fill(0)


func get_count(item: int) -> int:
	return counts[item]


## Предмет доставлен в ядро (лентой или содержимым снесённого здания).
func deliver(item: int, amount: int = 1) -> void:
	delivered[item] += amount
	_stats.record_income(item, amount)
	_store(item, amount)


## Начальный запас уровня или возврат стоимости — без учёта доставки.
func add_without_delivery(item: int, amount: int) -> void:
	_store(item, amount)


func can_afford(cost: Array[ItemStack]) -> bool:
	for stack in cost:
		if counts[stack.item.index] < stack.amount:
			return false
	return true


func spend(cost: Array[ItemStack]) -> bool:
	if not can_afford(cost):
		return false
	for stack in cost:
		counts[stack.item.index] -= stack.amount
		_stats.record_outcome(stack.item.index, stack.amount)
	revision += 1
	return true


func refund(cost: Array[ItemStack]) -> void:
	for stack in cost:
		_store(stack.item.index, stack.amount)


func make_budget() -> Budget:
	return Budget.new(counts)


func _store(item: int, amount: int) -> void:
	var space := capacity - counts[item]
	var stored := clampi(amount, 0, maxi(space, 0))
	counts[item] += stored
	if stored < amount:
		burned[item] += amount - stored
	revision += 1
