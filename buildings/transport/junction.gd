class_name Junction
extends Building
## Перекрёсток: пропускает предметы насквозь на противоположную сторону, не смешивая потоки.
## У каждого направления своя очередь; предмет выходит не раньше transfer_ticks после входа
## и не чаще, чем раз в get_ticks_per_item() тиков по каждому направлению (пропускная способность).

## Очереди по стороне прихода (направление от перекрёстка к источнику).
var _items: Array[PackedInt32Array] = []
var _ticks: Array[PackedInt32Array] = []
## Тик, с которого направление может выпустить следующий предмет.
var _next_out := PackedInt32Array([0, 0, 0, 0])


func _init() -> void:
	for side in 4:
		_items.append(PackedInt32Array())
		_ticks.append(PackedInt32Array())


func accept_item(source: Building, _item: int) -> bool:
	var side := side_of(source)
	if side < 0 or _items[side].size() >= (def as LogisticDef).capacity:
		return false
	return _neighbor((side + 2) % 4) != null


func handle_item(source: Building, item: int) -> void:
	var side := side_of(source)
	if side < 0:
		return
	_items[side].append(item)
	_ticks[side].append(world.simulation.tick)
	wake()


func on_proximity_changed() -> void:
	wake()


func update_tick(tick: int) -> bool:
	var delay := (def as LogisticDef).transfer_ticks
	var interval := (def as LogisticDef).get_ticks_per_item()
	var next_wake := -1
	var passed := false
	for side in 4:
		if _items[side].is_empty():
			continue
		var ready := maxi(_ticks[side][0] + delay, _next_out[side])
		if tick < ready:
			next_wake = ready if next_wake < 0 else mini(next_wake, ready)
			continue
		var target := _neighbor((side + 2) % 4)
		var item := _items[side][0]
		if target != null and target.accept_item(self, item):
			_items[side].remove_at(0)
			_ticks[side].remove_at(0)
			target.handle_item(self, item)
			passed = true
			_next_out[side] = tick + interval
			if not _items[side].is_empty():
				var next_ready := maxi(_next_out[side], _ticks[side][0] + delay)
				next_wake = next_ready if next_wake < 0 else mini(next_wake, next_ready)
		elif target != null:
			wait_for(target)
	if passed:
		notify_space()
	if next_wake > 0:
		sleep_until(next_wake)
	return false


func save_state() -> Dictionary:
	var queues: Array = []
	var ticks: Array = []
	for side in 4:
		queues.append(_items[side].duplicate())
		ticks.append(_ticks[side].duplicate())
	return {"items": queues, "ticks": ticks, "next_out": _next_out.duplicate()}


func load_state(state: Dictionary) -> void:
	var queues: Array = state.get("items", [])
	var ticks: Array = state.get("ticks", [])
	for side in mini(4, mini(queues.size(), ticks.size())):
		var src_items: PackedInt32Array = queues[side]
		var src_ticks: PackedInt32Array = ticks[side]
		_items[side] = PackedInt32Array()
		_ticks[side] = PackedInt32Array()
		for i in mini(src_items.size(), src_ticks.size()):
			var item := SaveContext.item(src_items[i])
			if item >= 0:
				_items[side].append(item)
				_ticks[side].append(src_ticks[i])
	var next_out: PackedInt32Array = state.get("next_out", PackedInt32Array())
	if next_out.size() == 4:
		_next_out = next_out.duplicate()
	wake()


func collect_contents(out: PackedInt32Array) -> void:
	for side in 4:
		for item in _items[side]:
			out[item] += 1


func get_info_lines() -> PackedStringArray:
	var total := 0
	for side in 4:
		total += _items[side].size()
	return PackedStringArray([tr("INFO_BUFFERED") % total])


func _neighbor(dir: int) -> Building:
	return world.buildings.get_at(origin + GameConst.dir_vector(dir))
