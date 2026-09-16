class_name Drill
extends Building
## Бур: добывает самую частую доступную руду под собой и отдаёт её только с лицевой стороны (поворот R):
## по кругу соседям, примыкающим к этой стороне. Разгрузчик может забрать добытое с любой стороны.
## Работает от электричества: пока буфер не полон, бодрствует и копит прогресс со скоростью
## удовлетворённости сети. Если отдать некуда и буфер полон — спит до освобождения места у соседей.

var ore: OreDef
var ore_tiles: int = 0
var ticks_per_item: int = 0
var buffer: int = 0
var blocked: bool = false

var _item: int = -1
## Прогресс добычи текущего предмета 0..1.
var progress: float = 0.0


func on_placed() -> void:
	var d := def as DrillDef
	var found := d.find_ore(world.grid, origin)
	if found.x == 0:
		return
	ore = Registry.ores[found.x - 1]
	ore_tiles = found.y
	_item = ore.item.index
	ticks_per_item = maxi(1, roundi(d.seconds_per_item(ore, ore_tiles) * GameConst.TICK_RATE))
	wake()


func on_proximity_changed() -> void:
	wake()


func on_rotated(_old_rotation: int) -> void:
	wake()


func update_tick(_tick: int) -> bool:
	power_request = 0.0
	if _item < 0:
		return false
	var capacity := (def as DrillDef).item_capacity
	if buffer < capacity:
		var rate := get_power_satisfaction() if def.power_use > 0.0 else 1.0
		progress += rate / ticks_per_item
		if progress >= 1.0:
			progress -= 1.0
			buffer += 1
			if world.simulation.has_waiters(id):
				notify_space()

	blocked = false
	if buffer > 0:
		if _dump_front(_item):
			buffer -= 1
		else:
			blocked = true
			for target in proximity:
				if side_of(target) == rotation:
					wait_for(target)
	if buffer < capacity:
		power_request = def.power_use
		return true
	return false


## Отдать предмет одному из соседей с лицевой стороны по кругу.
func _dump_front(item: int) -> bool:
	var n := proximity.size()
	for k in n:
		var index := (_dump_index + k) % n
		var target := proximity[index]
		if side_of(target) != rotation:
			continue
		if target.accept_item(self, item):
			target.handle_item(self, item)
			_dump_index = (index + 1) % n
			return true
	return false


func save_state() -> Dictionary:
	return {"buffer": buffer, "progress": progress, "power": power_request}


func load_state(state: Dictionary) -> void:
	buffer = int(state.get("buffer", 0))
	progress = float(state.get("progress", 0.0))
	power_request = float(state.get("power", 0.0))
	wake()


func get_status() -> Status:
	if ore == null:
		return Status.NO_ORE
	if blocked:
		return Status.OUTPUT_BLOCKED
	if def.power_use > 0.0 and get_power_satisfaction() <= 0.0:
		return Status.NO_POWER
	return Status.WORKING


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
	if def.power_use > 0.0:
		lines.append(power_info_line())
	return lines


# --- Окно ---

func get_window_sections() -> Array[WindowSection]:
	var sections: Array[WindowSection] = []
	sections.append(WindowSection.single(tr("WINDOW_MINED"), _item, buffer, _item))
	sections.append(WindowSection.progress(progress if ore != null and buffer < (def as DrillDef).item_capacity else 0.0))
	if def.power_use > 0.0:
		sections.append(WindowSection.power(self))
	return sections
