class_name Drill
extends Building
## Бур: добывает самую частую доступную руду под собой и отдаёт соседям по кругу.
## Между предметами спит до запланированного тика; если отдать некуда — ждёт освобождения места у соседей.

var ore: OreDef
var ore_tiles: int = 0
var ticks_per_item: int = 0
var buffer: int = 0
var blocked: bool = false

var _item: int = -1
var _next_tick: int = 0


func on_placed() -> void:
	var d := def as DrillDef
	var found := d.find_ore(world.grid, origin)
	if found.x == 0:
		return
	ore = Registry.ores[found.x - 1]
	ore_tiles = found.y
	_item = ore.item.index
	ticks_per_item = maxi(1, roundi(d.seconds_per_item(ore, ore_tiles) * GameConst.TICK_RATE))
	_next_tick = world.simulation.tick + ticks_per_item
	sleep_until(_next_tick)


func on_proximity_changed() -> void:
	wake()


func update_tick(tick: int) -> bool:
	if _item < 0:
		return false
	var capacity := (def as DrillDef).item_capacity
	if buffer >= capacity:
		# Склад полон: добыча стоит, отсчёт начнётся заново после освобождения места.
		_next_tick = maxi(_next_tick, tick + ticks_per_item)
	elif tick >= _next_tick:
		buffer += 1
		_next_tick = tick + ticks_per_item
		if world.simulation.has_waiters(id):
			notify_space()

	blocked = false
	if buffer > 0:
		if dump(_item):
			buffer -= 1
			if buffer > 0:
				return true
		else:
			blocked = true
			wait_for_proximity()
	if buffer < capacity:
		sleep_until(_next_tick)
	return false


func save_state() -> Dictionary:
	return {"buffer": buffer, "next_tick": _next_tick}


func load_state(state: Dictionary) -> void:
	buffer = int(state.get("buffer", 0))
	_next_tick = int(state.get("next_tick", _next_tick))
	wake()


func get_status() -> Status:
	if ore == null:
		return Status.NO_ORE
	return Status.OUTPUT_BLOCKED if blocked else Status.WORKING


func collect_contents(out: PackedInt32Array) -> void:
	if _item >= 0:
		out[_item] += buffer


func has_player_window() -> bool:
	return true


func can_unload() -> bool:
	return true


func has_item(item: int) -> bool:
	return item == _item and buffer > 0


func unload_item(item: int) -> bool:
	if item != _item or buffer <= 0:
		return false
	buffer -= 1
	wake()
	return true


func get_load_factor(item: int) -> float:
	return float(buffer) / maxi((def as DrillDef).item_capacity, 1) if item == _item else 0.0


func get_player_stacks() -> Array[Vector2i]:
	var stacks: Array[Vector2i] = []
	if _item >= 0 and buffer > 0:
		stacks.append(Vector2i(_item, buffer))
	return stacks


func take_player_items(item: int, amount: int) -> int:
	if item != _item:
		return 0
	var taken := mini(buffer, amount)
	buffer -= taken
	if taken > 0:
		wake()
	return taken


func get_items_per_second() -> float:
	return float(GameConst.TICK_RATE) / ticks_per_item if ticks_per_item > 0 else 0.0


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if ore == null:
		lines.append(tr("INFO_DRILL_NO_ORE"))
		return lines
	lines.append(tr("INFO_DRILL_ORE") % [tr(ore.item.name_key), ore_tiles, def.size * def.size])
	lines.append(tr("INFO_RATE") % get_items_per_second())
	lines.append(tr("INFO_BUFFER") % [buffer, (def as DrillDef).item_capacity])
	return lines
