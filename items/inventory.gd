class_name Inventory
extends RefCounted
## Инвентарь из ячеек (как в Factorio): в ячейке один тип предмета, не больше его размера стака.
## Суммы и число занятых ячеек по каждому предмету кэшируются, поэтому «сколько ещё влезет» — O(1):
## это важно для складов, в которые ленты грузят каждый тик.
## auto_sort: после каждого изменения ячейки пересобираются по порядку предметов (инвентарь дрона).

const EMPTY := -1


## Бюджет для планирования ряда построек: копия количеств, из которой вычитаются расходы.
class Budget:
	var counts: PackedInt32Array

	func _init(p_counts: PackedInt32Array) -> void:
		counts = p_counts.duplicate()

	func take(item: int, amount: int) -> bool:
		if counts[item] < amount:
			return false
		counts[item] -= amount
		return true

	func give(item: int, amount: int) -> void:
		counts[item] += amount


var slot_items: PackedInt32Array = PackedInt32Array()
var slot_counts: PackedInt32Array = PackedInt32Array()
## Сколько предметов каждого типа лежит всего.
var totals: PackedInt32Array = PackedInt32Array()
## Сколько ячеек занято предметом каждого типа.
var slots_used: PackedInt32Array = PackedInt32Array()
var free_slots: int = 0
var auto_sort: bool = false
## Увеличивается при любом изменении — интерфейс сравнивает и обновляется.
var revision: int = 0

## Последняя неполная ячейка предмета: частый случай «добавить один» не сканирует все ячейки.
var _hint: PackedInt32Array = PackedInt32Array()


func _init(slot_count: int, p_auto_sort: bool = false) -> void:
	auto_sort = p_auto_sort
	var item_count := Registry.items.size()
	slot_items.resize(maxi(slot_count, 0))
	slot_items.fill(EMPTY)
	slot_counts.resize(maxi(slot_count, 0))
	slot_counts.fill(0)
	totals.resize(item_count)
	totals.fill(0)
	slots_used.resize(item_count)
	slots_used.fill(0)
	_hint.resize(item_count)
	_hint.fill(0)
	free_slots = slot_items.size()


func size() -> int:
	return slot_items.size()


func count(item: int) -> int:
	return totals[item]


func used_slots() -> int:
	return slot_items.size() - free_slots


func is_empty() -> bool:
	return free_slots == slot_items.size()


## Сколько ещё предметов item можно положить.
func space_for(item: int) -> int:
	var stack := Registry.stack_sizes[item]
	return slots_used[item] * stack - totals[item] + free_slots * stack


func can_add(item: int, amount: int) -> bool:
	return space_for(item) >= amount


## Кладёт до amount предметов. Возвращает, сколько поместилось.
func add(item: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var stack := Registry.stack_sizes[item]
	var left := amount
	if slots_used[item] > 0:
		var h := _hint[item]
		if slot_items[h] == item and slot_counts[h] < stack:
			var put := mini(stack - slot_counts[h], left)
			slot_counts[h] += put
			left -= put
		if left > 0:
			for i in slot_items.size():
				if slot_items[i] == item and slot_counts[i] < stack:
					var put := mini(stack - slot_counts[i], left)
					slot_counts[i] += put
					left -= put
					_hint[item] = i
					if left == 0:
						break
	if left > 0 and free_slots > 0:
		for i in slot_items.size():
			if slot_items[i] == EMPTY:
				var put := mini(stack, left)
				slot_items[i] = item
				slot_counts[i] = put
				slots_used[item] += 1
				free_slots -= 1
				left -= put
				_hint[item] = i
				if left == 0 or free_slots == 0:
					break
	var added := amount - left
	if added > 0:
		totals[item] += added
		_changed()
	return added


## Забирает до amount предметов (сначала из последних ячеек). Возвращает, сколько забрано.
func remove(item: int, amount: int) -> int:
	if amount <= 0 or totals[item] == 0:
		return 0
	var left := amount
	for i in range(slot_items.size() - 1, -1, -1):
		if slot_items[i] != item:
			continue
		var taken := mini(slot_counts[i], left)
		slot_counts[i] -= taken
		left -= taken
		if slot_counts[i] == 0:
			_clear_slot(i)
		else:
			_hint[item] = i
		if left == 0:
			break
	var removed := amount - left
	if removed > 0:
		totals[item] -= removed
		_changed()
	return removed


## Забирает до amount предметов из конкретной ячейки. Возвращает Vector2i(предмет, количество).
func take_from_slot(slot: int, amount: int) -> Vector2i:
	if slot < 0 or slot >= slot_items.size() or slot_items[slot] == EMPTY or amount <= 0:
		return Vector2i(EMPTY, 0)
	var item := slot_items[slot]
	var taken := mini(slot_counts[slot], amount)
	slot_counts[slot] -= taken
	totals[item] -= taken
	if slot_counts[slot] == 0:
		_clear_slot(slot)
	_changed()
	return Vector2i(item, taken)


func has_stacks(stacks: Array[ItemStack], times: int = 1) -> bool:
	for stack in stacks:
		if totals[stack.item.index] < stack.amount * times:
			return false
	return true


## Добавляет в out (индекс = индекс предмета) всё содержимое.
func collect_into(out: PackedInt32Array) -> void:
	for item in totals.size():
		out[item] += totals[item]


func make_budget() -> Budget:
	return Budget.new(totals)


func clear() -> void:
	slot_items.fill(EMPTY)
	slot_counts.fill(0)
	totals.fill(0)
	slots_used.fill(0)
	free_slots = slot_items.size()
	_changed()


## Пересобирает ячейки: предметы по порядку реестра, сначала полные стопки.
func sort_slots() -> void:
	slot_items.fill(EMPTY)
	slot_counts.fill(0)
	slots_used.fill(0)
	var cursor := 0
	for item in totals.size():
		var left := totals[item]
		var stack := Registry.stack_sizes[item]
		while left > 0 and cursor < slot_items.size():
			var put := mini(stack, left)
			slot_items[cursor] = item
			slot_counts[cursor] = put
			slots_used[item] += 1
			_hint[item] = cursor
			left -= put
			cursor += 1
		if left > 0:
			# Ячеек не хватает (не должно случаться: пересборка не увеличивает число стопок).
			totals[item] -= left
	free_slots = slot_items.size() - cursor


func _clear_slot(slot: int) -> void:
	slots_used[slot_items[slot]] -= 1
	slot_items[slot] = EMPTY
	slot_counts[slot] = 0
	free_slots += 1


func _changed() -> void:
	if auto_sort:
		sort_slots()
	revision += 1
