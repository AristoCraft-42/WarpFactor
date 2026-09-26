class_name Pump
extends Building
## Насос на месторождении жидкости: каждый тик кладёт жидкость в сети, подключённые к его сторонам
## (по кругу, начиная с той, что приняла в прошлый раз). Обычный насос берёт воду и тока не просит;
## нефтяная вышка — тот же насос, но на нефти (FluidBuildingDef.pump_fluid) и с электричеством:
## выдача умножается на удовлетворённость сети.

var fluid: FluidDef
var tiles: int = 0
var last_rate: float = 0.0
var _cursor: int = 0


func on_placed() -> void:
	var d := def as FluidBuildingDef
	tiles = d.count_fluid_tiles(world.grid, origin)
	for y in range(origin.y, origin.y + def.size):
		for x in range(origin.x, origin.x + def.size):
			var ore := world.grid.get_ore_def(x, y)
			if d.pumps(ore):
				fluid = ore.fluid
	world.fluids.mark_dirty()
	wake()


func on_removed() -> void:
	world.fluids.mark_dirty()


func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	for side in 4:
		ports.append(FluidGraph.Port.new(side, fluid, side))
	return ports


func update_tick(_tick: int) -> bool:
	power_request = 0.0
	if fluid == null or tiles <= 0:
		return false
	var rate := 1.0
	if def.power_use > 0.0:
		power_request = def.power_use
		rate = get_power_satisfaction()
	var left := (def as FluidBuildingDef).pump_per_tile * tiles * GameConst.TICK_DT * rate
	var produced := 0.0
	for k in 4:
		var side := (_cursor + k) % 4
		var net := world.fluids.get_port_network(self, side)
		if net == null:
			continue
		var put := net.insert(fluid.index, left)
		if put > 0.0:
			_cursor = side
		left -= put
		produced += put
		if left <= 0.0:
			break
	last_rate = produced / GameConst.TICK_DT
	return true


func save_state() -> Dictionary:
	var state := {"cursor": _cursor}
	if def.power_use > 0.0:
		state["power"] = power_request
	return state


func load_state(state: Dictionary) -> void:
	_cursor = int(state.get("cursor", 0))
	power_request = float(state.get("power", 0.0))
	wake()


func get_status() -> Status:
	if fluid == null:
		return Status.NO_ORE
	if def.power_use > 0.0 and get_power_satisfaction() <= 0.0:
		return Status.NO_POWER
	return Status.WORKING if last_rate > 0.0 else Status.OUTPUT_BLOCKED


func get_info_lines() -> PackedStringArray:
	if fluid == null:
		return PackedStringArray([tr("INFO_DRILL_NO_ORE")])
	var lines := PackedStringArray([tr("INFO_PUMP_RATE") % [tr(fluid.name_key), last_rate, (def as FluidBuildingDef).pump_per_tile * tiles]])
	if def.power_use > 0.0:
		lines.append(power_info_line())
	return lines


# --- Окно ---

func get_window_sections() -> Array[WindowSection]:
	var d := def as FluidBuildingDef
	var full := d.pump_per_tile * tiles
	var net: FluidGraph.FluidNetwork = null
	for side in 4:
		net = world.fluids.get_port_network(self, side)
		if net != null:
			break
	var rate := WindowSection.bar(tr("WINDOW_PUMP_RATE"), last_rate / maxf(full, 0.001), tr("WINDOW_PER_SECOND_OF") % [last_rate, full],
		fluid.color if fluid != null else WindowSection.COLOR_PROGRESS)
	var sections: Array[WindowSection] = [rate, WindowSection.fluid(tr("WINDOW_NETWORK_FLUID"), net)]
	if def.power_use > 0.0:
		sections.append(WindowSection.power(self))
	return sections
