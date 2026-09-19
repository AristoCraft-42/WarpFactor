class_name Drill
extends Building
## Бур: добывает самую частую доступную руду под собой и отдаёт её только с лицевой стороны (поворот R):
## по кругу соседям, примыкающим к этой стороне. Разгрузчик может забрать добытое с любой стороны.
## Работает от электричества: пока буфер не полон, бодрствует и копит прогресс со скоростью
## удовлетворённости сети. Если отдать некуда и буфер полон — спит до освобождения места у соседей.
##
## Угольный бур (DrillDef.fuel_use > 0) вместо тока жжёт топливо: принимает его с лент и из рук,
## а если добывает топливную руду — сам оставляет себе столько, сколько помещается в топливный
## буфер, остальное отдаёт наружу.

var ore: OreDef
var ore_tiles: int = 0
var ticks_per_item: int = 0
var buffer: int = 0
var blocked: bool = false

var _item: int = -1
## Прогресс добычи текущего предмета 0..1.
var progress: float = 0.0
## Топливо угольного бура: сколько каких предметов лежит и сколько кДж осталось от горящего.
var fuel_counts: PackedInt32Array = PackedInt32Array()
var fuel_energy: float = 0.0


func on_placed() -> void:
	var d := def as DrillDef
	if d.fuel_use > 0.0:
		fuel_counts.resize(Registry.items.size())
		fuel_counts.fill(0)
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
	var d := def as DrillDef
	var capacity := d.item_capacity
	if buffer < capacity or _wants_fuel(_item):
		var rate := 1.0
		if def.power_use > 0.0:
			rate = get_power_satisfaction()
		elif d.fuel_use > 0.0:
			rate = 1.0 if _burn_fuel() else 0.0
		progress += rate / ticks_per_item
		if progress >= 1.0:
			progress -= 1.0
			# Топливная руда сначала идёт в собственный бак, остальное — на выход.
			if _wants_fuel(_item):
				fuel_counts[_item] += 1
			else:
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
	if buffer < capacity or _wants_fuel(_item):
		power_request = def.power_use
		return true
	return false


## Сколько всего единиц топлива лежит в буре.
func total_fuel() -> int:
	var n := 0
	for c in fuel_counts:
		n += c
	return n


## Нужно ли оставить добытый предмет себе на топливо.
func _wants_fuel(item: int) -> bool:
	var d := def as DrillDef
	return d.fuel_use > 0.0 and item >= 0 and Registry.items[item].is_fuel() and total_fuel() < d.fuel_capacity


## Сжечь топливо на один тик. false — топлива нет.
func _burn_fuel() -> bool:
	var d := def as DrillDef
	var need := d.fuel_use * GameConst.TICK_DT
	while fuel_energy < need:
		var item := _take_fuel()
		if item < 0:
			return false
		fuel_energy += Registry.items[item].fuel_value
	fuel_energy = maxf(fuel_energy - need, 0.0)
	return true


func _take_fuel() -> int:
	for item in fuel_counts.size():
		if fuel_counts[item] > 0:
			fuel_counts[item] -= 1
			notify_space()
			return item
	return -1


## Угольный бур принимает топливо с любой стороны.
func accept_item(_source: Building, item: int) -> bool:
	var d := def as DrillDef
	return d.fuel_use > 0.0 and Registry.items[item].is_fuel() and total_fuel() < d.fuel_capacity


func handle_item(_source: Building, item: int) -> void:
	fuel_counts[item] += 1
	wake()


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
	var state := {"buffer": buffer, "progress": progress, "power": power_request}
	if (def as DrillDef).fuel_use > 0.0:
		state["fuel"] = fuel_counts.duplicate()
		state["energy"] = fuel_energy
	return state


func load_state(state: Dictionary) -> void:
	buffer = int(state.get("buffer", 0))
	progress = float(state.get("progress", 0.0))
	power_request = float(state.get("power", 0.0))
	if (def as DrillDef).fuel_use > 0.0:
		var src := SaveContext.counts(state.get("fuel", PackedInt32Array()))
		for i in mini(src.size(), fuel_counts.size()):
			fuel_counts[i] = src[i]
		fuel_energy = float(state.get("energy", 0.0))
	wake()


func get_status() -> Status:
	if ore == null:
		return Status.NO_ORE
	if blocked:
		return Status.OUTPUT_BLOCKED
	if def.power_use > 0.0 and get_power_satisfaction() <= 0.0:
		return Status.NO_POWER
	if (def as DrillDef).fuel_use > 0.0 and fuel_energy <= 0.0 and total_fuel() == 0:
		return Status.NO_FUEL
	return Status.WORKING


func collect_contents(out: PackedInt32Array) -> void:
	if _item >= 0:
		out[_item] += buffer
	for i in fuel_counts.size():
		out[i] += fuel_counts[i]


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
	for item in fuel_counts.size():
		if fuel_counts[item] > 0:
			stacks.append(Vector2i(item, fuel_counts[item]))
	return stacks


func take_player_items(item: int, amount: int) -> int:
	var taken := 0
	if item == _item:
		taken = mini(buffer, amount)
		buffer -= taken
	if item < fuel_counts.size() and fuel_counts[item] > 0:
		var from_fuel := mini(fuel_counts[item], amount - taken)
		fuel_counts[item] -= from_fuel
		taken += from_fuel
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
	if (def as DrillDef).fuel_use > 0.0:
		lines.append(tr("INFO_FUEL") % total_fuel())
	return lines


# --- Окно ---

func get_window_sections() -> Array[WindowSection]:
	var sections: Array[WindowSection] = []
	sections.append(WindowSection.single(tr("WINDOW_MINED"), _item, buffer, _item))
	sections.append(WindowSection.progress(progress if ore != null and buffer < (def as DrillDef).item_capacity else 0.0))
	if def.power_use > 0.0:
		sections.append(WindowSection.power(self))
	if (def as DrillDef).fuel_use > 0.0:
		sections.append(WindowSection.fuel_slot(fuel_counts))
		sections.append(WindowSection.burn(fuel_energy))
	return sections
