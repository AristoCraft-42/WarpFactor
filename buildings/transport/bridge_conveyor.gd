class_name BridgeConveyor
extends Building
## Мостовой конвейер: переносит предметы над постройками к связанному мосту на расстоянии
## до link_range тайлов по прямой. Мост со связью принимает предметы от соседей (кроме стороны связи)
## и отправляет их по цепочке; последний мост отдаёт соседям, но не назад, откуда пришла связь.
## Настройка — смещение до связанного моста (Vector2i), поэтому копируется пипеткой.
## Предмет уходит дальше не раньше transfer_ticks после входа и не чаще, чем раз в
## get_ticks_per_item() тиков (пропускная способность).

var link: Vector2i = Vector2i.ZERO

var _items := PackedInt32Array()
var _ticks := PackedInt32Array()
var _next_out: int = 0


func get_config_kind() -> ConfigKind:
	return ConfigKind.BRIDGE


func get_config() -> Variant:
	return link if link != Vector2i.ZERO else null


func set_config(value: Variant) -> void:
	link = value if value is Vector2i else Vector2i.ZERO
	wake()


func get_range() -> int:
	return (def as LogisticDef).link_range


## Можно ли связать этот мост с other: тот же ряд или столбец, в пределах дальности.
func can_link_to(other: Building) -> bool:
	if not (other is BridgeConveyor) or other == self:
		return false
	var offset := other.origin - origin
	if (offset.x != 0) == (offset.y != 0):
		return false
	return maxi(absi(offset.x), absi(offset.y)) <= get_range()


func get_link_target() -> BridgeConveyor:
	if link == Vector2i.ZERO or world == null:
		return null
	var target := world.buildings.get_at(origin + link)
	if target is BridgeConveyor and can_link_to(target):
		return target
	return null


func on_placed() -> void:
	_notify_bridges_in_range()


func on_removed() -> void:
	_notify_bridges_in_range()


func on_proximity_changed() -> void:
	wake()


func accept_item(source: Building, _item: int) -> bool:
	if _items.size() >= (def as LogisticDef).capacity or source is BridgeConveyor:
		return false
	if get_link_target() == null:
		return false
	var side := side_of(source)
	return side >= 0 and side != GameConst.dir_from_vector(link)


func handle_item(_source: Building, item: int) -> void:
	_push(item)


## Приём от предыдущего моста цепочки.
func receive(item: int) -> bool:
	if _items.size() >= (def as LogisticDef).capacity:
		return false
	_push(item)
	return true


func update_tick(tick: int) -> bool:
	if _items.is_empty():
		return false
	var ready := maxi(_ticks[0] + (def as LogisticDef).transfer_ticks, _next_out)
	if tick < ready:
		sleep_until(ready)
		return false
	var item := _items[0]
	var target := get_link_target()
	if target != null:
		if target.receive(item):
			_pop()
			_after_output(tick)
			return false
		wait_for(target)
		return false

	# Конец цепочки: отдаём соседям, кроме направлений, откуда приходят связи.
	var blocked := _incoming_mask()
	var n := proximity.size()
	for k in n:
		var other := proximity[(_dump_index + k) % n]
		var side := side_of(other)
		if side < 0 or (blocked & (1 << side)) != 0 or other is BridgeConveyor:
			continue
		if other.accept_item(self, item):
			_pop()
			_dump_index = (_dump_index + k + 1) % n
			other.handle_item(self, item)
			_after_output(tick)
			return false
	for other in proximity:
		var side := side_of(other)
		if side >= 0 and (blocked & (1 << side)) == 0 and not (other is BridgeConveyor):
			wait_for(other)
	return false


func save_state() -> Dictionary:
	return {"items": _items.duplicate(), "ticks": _ticks.duplicate(), "next_out": _next_out}


func load_state(state: Dictionary) -> void:
	_items = (state.get("items", PackedInt32Array()) as PackedInt32Array).duplicate()
	_ticks = (state.get("ticks", PackedInt32Array()) as PackedInt32Array).duplicate()
	_next_out = int(state.get("next_out", 0))
	wake()


func collect_contents(out: PackedInt32Array) -> void:
	for item in _items:
		out[item] += 1


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var target := get_link_target()
	if target != null:
		lines.append(tr("INFO_BRIDGE_LINKED") % maxi(absi(link.x), absi(link.y)))
	else:
		lines.append(tr("INFO_BRIDGE_END"))
	lines.append(tr("INFO_BUFFER") % [_items.size(), (def as LogisticDef).capacity])
	return lines


## Битовая маска направлений, из которых на этот мост указывают связи других мостов.
func _incoming_mask() -> int:
	var mask := 0
	for dir in 4:
		var step := GameConst.dir_vector(dir)
		for distance in range(1, get_range() + 1):
			var other := world.buildings.get_at(origin + step * distance)
			if other is BridgeConveyor and (other as BridgeConveyor).get_link_target() == self:
				mask |= 1 << dir
				break
	return mask


## После выпуска предмета: следующий — не раньше чем через интервал пропускной способности.
func _after_output(tick: int) -> void:
	_next_out = tick + (def as LogisticDef).get_ticks_per_item()
	if not _items.is_empty():
		sleep_until(_next_out)


func _push(item: int) -> void:
	_items.append(item)
	_ticks.append(world.simulation.tick)
	wake()


func _pop() -> void:
	_items.remove_at(0)
	_ticks.remove_at(0)
	notify_space()


## Мосты в пределах дальности, чья связь могла стать (не)действительной, — перерисовать.
func _notify_bridges_in_range() -> void:
	if world == null:
		return
	for dir in 4:
		var step := GameConst.dir_vector(dir)
		for distance in range(1, get_range() + 1):
			var other := world.buildings.get_at(origin + step * distance)
			if other is BridgeConveyor and other.origin + (other as BridgeConveyor).link == origin:
				world.buildings.notify_changed(other)
				other.wake()
