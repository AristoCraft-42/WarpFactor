class_name CraftQueue
extends RefCounted
## Очередь ручного крафта (как в Factorio).
## Каждая единица очереди — полный план одного крафта: недостающие промежуточные детали
## докрафчиваются в той же единице. Сырьё списывается при постановке в очередь и полностью
## возвращается при отмене. Результат (и лишние промежуточные детали) попадает в инвентарь
## по окончании единицы; если места нет — очередь ждёт.

const MAX_DEPTH := 6


class Unit:
	var recipe: HandRecipe
	var ticks_total: int = 0
	var ticks_done: int = 0
	## Списанное из инвентаря: предмет → количество (возврат при отмене).
	var consumed: Dictionary[int, int] = {}
	## Лишние промежуточные детали (партия больше нужного): предмет → количество.
	var surplus: Dictionary[int, int] = {}


var units: Array[Unit] = []
## Готовый результат не помещается в инвентарь.
var blocked: bool = false
## Увеличивается при любом изменении очереди.
var revision: int = 0

var _inventory: Inventory
var _speed: float = 1.0


func _init(inventory: Inventory, speed: float = 1.0) -> void:
	_inventory = inventory
	_speed = maxf(speed, 0.01)


func is_empty() -> bool:
	return units.is_empty()


## Ставит в очередь до count крафтов. Возвращает, сколько удалось поставить.
func enqueue(recipe: HandRecipe, count: int) -> int:
	var queued := 0
	for i in count:
		var unit := _plan(recipe, {})
		if unit == null:
			break
		for item in unit.consumed:
			_inventory.remove(item, unit.consumed[item])
		units.append(unit)
		queued += 1
	if queued > 0:
		revision += 1
	return queued


## Сколько крафтов можно поставить из текущего инвентаря (не больше limit).
func max_craftable(recipe: HandRecipe, limit: int = 99) -> int:
	var available: Dictionary[int, int] = {}
	var n := 0
	while n < limit and _plan(recipe, available) != null:
		n += 1
	return n


## Отменяет единицу очереди с возвратом сырья.
func cancel(index: int) -> void:
	if index < 0 or index >= units.size():
		return
	var unit := units[index]
	units.remove_at(index)
	for item in unit.consumed:
		_inventory.add(item, unit.consumed[item])
	if index == 0:
		blocked = false
	revision += 1


## Отменяет всю очередь: списанное сырьё добавляется в out (индекс = предмет), а не в инвентарь.
## Нужно, когда дрона сбили: всё уходит в выпавший груз.
func drain_into(out: PackedInt32Array) -> void:
	for unit in units:
		for item in unit.consumed:
			out[item] += unit.consumed[item]
	units.clear()
	blocked = false
	revision += 1


## Отменяет до count последних единиц с этим рецептом (с конца очереди). Возвращает, сколько отменено.
func cancel_last(recipe: HandRecipe, count: int = 1) -> int:
	var cancelled := 0
	for i in range(units.size() - 1, -1, -1):
		if cancelled >= count:
			break
		if units[i].recipe == recipe:
			cancel(i)
			cancelled += 1
	return cancelled


func count_of(recipe: HandRecipe) -> int:
	var n := 0
	for unit in units:
		if unit.recipe == recipe:
			n += 1
	return n


## Группы подряд идущих единиц одного рецепта: [[рецепт, количество], ...].
func get_groups() -> Array[Array]:
	var groups: Array[Array] = []
	for unit in units:
		if not groups.is_empty() and groups[groups.size() - 1][0] == unit.recipe:
			groups[groups.size() - 1][1] += 1
		else:
			groups.append([unit.recipe, 1])
	return groups


## Доля выполнения текущей единицы (0..1).
func get_progress() -> float:
	if units.is_empty() or units[0].ticks_total <= 0:
		return 0.0
	return clampf(float(units[0].ticks_done) / units[0].ticks_total, 0.0, 1.0)


func update_tick() -> void:
	if units.is_empty():
		return
	var unit := units[0]
	if unit.ticks_done < unit.ticks_total:
		unit.ticks_done += 1
		if unit.ticks_done < unit.ticks_total:
			return
	var output := unit.recipe.output.index
	if _inventory.space_for(output) < unit.recipe.amount:
		if not blocked:
			blocked = true
			revision += 1
		return
	blocked = false
	_inventory.add(output, unit.recipe.amount)
	for item in unit.surplus:
		_inventory.add(item, unit.surplus[item])
	units.remove_at(0)
	revision += 1


# --- Сохранение ---

func save_data() -> Dictionary:
	var list: Array = []
	for unit in units:
		list.append({"recipe": unit.recipe.output.index, "total": unit.ticks_total, "done": unit.ticks_done,
			"consumed": unit.consumed.duplicate(), "surplus": unit.surplus.duplicate()})
	return {"units": list, "blocked": blocked}


func load_data(data: Dictionary) -> void:
	units.clear()
	for entry in (data.get("units", []) as Array):
		var d: Dictionary = entry
		var recipe := Registry.get_hand_recipe(SaveContext.item(int(d.get("recipe", -1))))
		var consumed := SaveContext.count_dict(d.get("consumed", {}))
		if recipe == null:
			# Рецепта больше нет — сырьё возвращается в инвентарь.
			for item in consumed:
				_inventory.add(item, consumed[item])
			continue
		var unit := Unit.new()
		unit.recipe = recipe
		unit.ticks_total = int(d.get("total", recipe.ticks))
		unit.ticks_done = int(d.get("done", 0))
		for item in consumed:
			unit.consumed[item] = consumed[item]
		var surplus := SaveContext.count_dict(d.get("surplus", {}))
		for item in surplus:
			unit.surplus[item] = surplus[item]
		units.append(unit)
	blocked = bool(data.get("blocked", false))
	revision += 1


## План одного крафта против доступных предметов available (предмет → остаток; отсутствующий
## ключ — берётся количество из инвентаря). При успехе available уменьшается.
func _plan(recipe: HandRecipe, available: Dictionary[int, int]) -> Unit:
	var unit := Unit.new()
	unit.recipe = recipe
	var trial := available.duplicate()
	if not _require(recipe, 1, trial, unit, 0):
		return null
	for item in trial:
		available[item] = trial[item]
	return unit


func _require(recipe: HandRecipe, crafts: int, available: Dictionary, unit: Unit, depth: int) -> bool:
	for stack in recipe.ingredients:
		var item := stack.item.index
		var need := stack.amount * crafts
		var have: int = available.get(item, _inventory.count(item))
		var used := mini(have, need)
		available[item] = have - used
		if used > 0:
			unit.consumed[item] = unit.consumed.get(item, 0) + used
		var short := need - used
		if short <= 0:
			continue
		var sub := Registry.get_hand_recipe(item)
		if sub == null or depth >= MAX_DEPTH:
			return false
		var sub_crafts := ceili(float(short) / sub.amount)
		if not _require(sub, sub_crafts, available, unit, depth + 1):
			return false
		var extra := sub_crafts * sub.amount - short
		if extra > 0:
			unit.surplus[item] = unit.surplus.get(item, 0) + extra
	unit.ticks_total += maxi(1, ceili(recipe.ticks * crafts / _speed))
	return true
