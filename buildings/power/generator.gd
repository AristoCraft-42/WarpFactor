class_name Generator
extends Building
## Генератор электросети. Сам не тикает: PowerGraph каждый тик спрашивает, сколько энергии он может
## дать (get_power_capacity_kj), и забирает нужную долю (draw_power_kj).
## Термогенератор: топливо принимается с ленты и руками, сгорает по мере нагрузки.
## Паровой генератор: пар берётся из сети труб, подключённой к левой или правой стороне
## (обе стороны — одна сеть, генераторы можно ставить цепочкой без труб).

var fuel_counts := PackedInt32Array()
## Остаток энергии горящего топлива, кДж.
var fuel_energy: float = 0.0
## Выработка на прошлом тике, кВт (для интерфейса).
var last_output_kw: float = 0.0


func _init() -> void:
	fuel_counts.resize(Registry.items.size())
	fuel_counts.fill(0)


func get_generator_def() -> GeneratorDef:
	return def as GeneratorDef


func is_power_generator() -> bool:
	return true


func on_placed() -> void:
	if get_generator_def().kind == GeneratorDef.Kind.STEAM:
		world.fluids.mark_dirty()


func on_removed() -> void:
	if get_generator_def().kind == GeneratorDef.Kind.STEAM:
		world.fluids.mark_dirty()


func on_rotated(_old_rotation: int) -> void:
	if get_generator_def().kind == GeneratorDef.Kind.STEAM:
		world.fluids.mark_dirty()


# --- Энергия ---

func get_power_capacity_kj(dt: float) -> float:
	var d := get_generator_def()
	var limit := d.max_output * dt
	if d.kind == GeneratorDef.Kind.STEAM:
		var net := world.fluids.get_port_network(self, get_steam_side(0))
		if net == null or d.steam_fluid == null or net.fluid != d.steam_fluid.index:
			return 0.0
		return minf(limit, net.amount * d.steam_energy)
	if fuel_energy <= 0.0 and total_fuel() == 0:
		return 0.0
	# Энергии горящего топлива и запаса хватает минимум на один тик.
	return limit


func draw_power_kj(kj: float) -> void:
	var d := get_generator_def()
	last_output_kw = kj / GameConst.TICK_DT
	if kj <= 0.0:
		return
	if d.kind == GeneratorDef.Kind.STEAM:
		var net := world.fluids.get_port_network(self, get_steam_side(0))
		if net != null:
			net.extract(d.steam_fluid.index, kj / d.steam_energy)
		return
	var need := kj / maxf(d.efficiency, 0.01)
	while fuel_energy < need:
		var item := _take_fuel()
		if item < 0:
			need = fuel_energy
			break
		fuel_energy += Registry.items[item].fuel_value
	fuel_energy -= need


func total_fuel() -> int:
	var sum := 0
	for c in fuel_counts:
		sum += c
	return sum


func _take_fuel() -> int:
	for item in fuel_counts.size():
		if fuel_counts[item] > 0:
			fuel_counts[item] -= 1
			notify_space()
			return item
	return -1


# --- Пар ---

## Стороны с паром: 0 — левая, 1 — правая (относительно поворота).
func get_steam_side(index: int) -> int:
	return posmod((2 if index == 0 else 0) + rotation, 4)


func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	var d := get_generator_def()
	if d.kind == GeneratorDef.Kind.STEAM:
		ports.append(FluidGraph.Port.new(get_steam_side(0), d.steam_fluid, 0))
		ports.append(FluidGraph.Port.new(get_steam_side(1), d.steam_fluid, 0))
	return ports


# --- Топливо ---

func accept_item(_source: Building, item: int) -> bool:
	var d := get_generator_def()
	return d.kind == GeneratorDef.Kind.FUEL and Registry.items[item].is_fuel() and total_fuel() < d.fuel_capacity


func handle_item(_source: Building, item: int) -> void:
	fuel_counts[item] += 1


func accepts_player_items() -> bool:
	return get_generator_def().kind == GeneratorDef.Kind.FUEL


func get_player_stacks() -> Array[Vector2i]:
	var stacks: Array[Vector2i] = []
	for item in fuel_counts.size():
		if fuel_counts[item] > 0:
			stacks.append(Vector2i(item, fuel_counts[item]))
	return stacks


func take_player_items(item: int, amount: int) -> int:
	var taken := mini(fuel_counts[item], amount)
	fuel_counts[item] -= taken
	if taken > 0:
		notify_space()
	return taken


func collect_contents(out: PackedInt32Array) -> void:
	for item in fuel_counts.size():
		out[item] += fuel_counts[item]


func save_state() -> Dictionary:
	return {"fuel": fuel_counts.duplicate(), "energy": fuel_energy}


func load_state(state: Dictionary) -> void:
	var counts := SaveContext.counts(state.get("fuel", PackedInt32Array()))
	for i in mini(counts.size(), fuel_counts.size()):
		fuel_counts[i] = counts[i]
	fuel_energy = float(state.get("energy", 0.0))


func get_status() -> Status:
	if power_net == null:
		return Status.NO_POWER
	if get_power_capacity_kj(GameConst.TICK_DT) <= 0.0:
		return Status.NO_FUEL if get_generator_def().kind == GeneratorDef.Kind.FUEL else Status.NO_INPUT
	return Status.WORKING if last_output_kw > 0.0 else Status.IDLE


func get_info_lines() -> PackedStringArray:
	var d := get_generator_def()
	var lines := PackedStringArray([tr("INFO_POWER_OUTPUT") % [roundi(last_output_kw), roundi(d.max_output)]])
	if d.kind == GeneratorDef.Kind.FUEL:
		lines.append(tr("INFO_FUEL") % total_fuel())
	if power_net == null:
		lines.append(tr("INFO_NO_POLE"))
	return lines
