class_name Boiler
extends Building
## Бойлер: жжёт топливо (с ленты или руками) и превращает воду в пар.
## Вода — из сети труб на левой стороне, пар — в сеть на правой (стороны относительно поворота).
## На полной мощности fuel_power кВт даёт steam_per_second пара в секунду, воды тратит столько же.

const TANK := 60.0

var fuel_counts := PackedInt32Array()
var fuel_energy: float = 0.0
var water: float = 0.0
var steam: float = 0.0
var last_steam_rate: float = 0.0


func _init() -> void:
	fuel_counts.resize(Registry.items.size())
	fuel_counts.fill(0)


func get_boiler_def() -> FluidBuildingDef:
	return def as FluidBuildingDef


func get_water_side() -> int:
	return posmod(2 + rotation, 4)


func get_steam_side() -> int:
	return posmod(rotation, 4)


func on_placed() -> void:
	world.fluids.mark_dirty()
	wake()


func on_removed() -> void:
	world.fluids.mark_dirty()


func on_rotated(_old_rotation: int) -> void:
	world.fluids.mark_dirty()


func get_fluid_ports() -> Array[FluidGraph.Port]:
	var d := get_boiler_def()
	return [FluidGraph.Port.new(get_water_side(), d.water_fluid, 0), FluidGraph.Port.new(get_steam_side(), d.steam_fluid, 1)]


func update_tick(_tick: int) -> bool:
	var d := get_boiler_def()
	var dt := GameConst.TICK_DT
	var water_net := world.fluids.get_port_network(self, get_water_side())
	if water_net != null and water < TANK:
		water += water_net.extract(d.water_fluid.index, TANK - water)
	# Сколько пара можно сделать за тик: мощность, вода, место в баке.
	var energy_per_steam := d.fuel_power / maxf(d.steam_per_second, 0.001)
	var want := minf(d.steam_per_second * dt, minf(water, TANK - steam))
	var made := 0.0
	if want > 0.0:
		var need := want * energy_per_steam
		while fuel_energy < need:
			var item := _take_fuel()
			if item < 0:
				break
			fuel_energy += Registry.items[item].fuel_value
		made = minf(want, fuel_energy / energy_per_steam)
		fuel_energy -= made * energy_per_steam
		water -= made
		steam += made
	var steam_net := world.fluids.get_port_network(self, get_steam_side())
	if steam_net != null and steam > 0.0:
		steam -= steam_net.insert(d.steam_fluid.index, steam)
	last_steam_rate = made / dt
	return true


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


func accept_item(_source: Building, item: int) -> bool:
	return Registry.items[item].is_fuel() and total_fuel() < get_boiler_def().fuel_capacity


func handle_item(_source: Building, item: int) -> void:
	fuel_counts[item] += 1


func accepts_player_items() -> bool:
	return true


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
	return {"fuel": fuel_counts.duplicate(), "energy": fuel_energy, "water": water, "steam": steam}


func load_state(state: Dictionary) -> void:
	var counts := SaveContext.counts(state.get("fuel", PackedInt32Array()))
	for i in mini(counts.size(), fuel_counts.size()):
		fuel_counts[i] = counts[i]
	fuel_energy = float(state.get("energy", 0.0))
	water = float(state.get("water", 0.0))
	steam = float(state.get("steam", 0.0))
	wake()


func get_status() -> Status:
	if last_steam_rate > 0.0:
		return Status.WORKING
	if fuel_energy <= 0.0 and total_fuel() == 0:
		return Status.NO_FUEL
	if water <= 0.0:
		return Status.NO_INPUT
	return Status.OUTPUT_BLOCKED if steam >= TANK else Status.IDLE


func get_info_lines() -> PackedStringArray:
	return PackedStringArray([
		tr("INFO_BOILER") % [last_steam_rate, get_boiler_def().steam_per_second],
		tr("INFO_BOILER_TANKS") % [roundi(water), roundi(steam)],
		tr("INFO_FUEL") % total_fuel(),
	])
