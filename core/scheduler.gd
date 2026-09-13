class_name Scheduler
extends RefCounted
## Отложенные пробуждения зданий («timing wheel»): здание просит разбудить его на тике N.
## Корзина выбирается по N mod SIZE; записи с более поздним тиком остаются в корзине до своего оборота.
## Повторные и устаревшие записи безвредны — лишнее пробуждение здание просто проигнорирует.

const SIZE := 256
const MASK := SIZE - 1

var _ids: Array[PackedInt32Array] = []
var _ticks: Array[PackedInt32Array] = []


func _init() -> void:
	_ids.resize(SIZE)
	_ticks.resize(SIZE)
	for i in SIZE:
		_ids[i] = PackedInt32Array()
		_ticks[i] = PackedInt32Array()


func schedule(building_id: int, tick: int) -> void:
	var slot := tick & MASK
	_ids[slot].append(building_id)
	_ticks[slot].append(tick)


## Добавляет в out id зданий, чьё время пришло на этом тике.
func pop_due(tick: int, out: PackedInt32Array) -> void:
	var slot := tick & MASK
	var ids := _ids[slot]
	if ids.is_empty():
		return
	var ticks := _ticks[slot]
	var keep_ids := PackedInt32Array()
	var keep_ticks := PackedInt32Array()
	for i in ids.size():
		if ticks[i] <= tick:
			out.append(ids[i])
		else:
			keep_ids.append(ids[i])
			keep_ticks.append(ticks[i])
	_ids[slot] = keep_ids
	_ticks[slot] = keep_ticks


func clear() -> void:
	for i in SIZE:
		_ids[i] = PackedInt32Array()
		_ticks[i] = PackedInt32Array()
