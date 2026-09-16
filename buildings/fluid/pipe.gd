class_name Pipe
extends Building
## Труба: соединяется с соседними трубами и портами машин во все стороны, объём — часть сети (FluidGraph).
## Сама не тикает. Проходима для врагов как лента.


func on_placed() -> void:
	world.fluids.register_pipe(self)


func on_removed() -> void:
	world.fluids.unregister_pipe(self)


## Соединяется ли труба со стороны side (обычная — со всех сторон).
func connects_side(_side: int) -> bool:
	return true


func get_fluid_capacity() -> float:
	return (def as FluidBuildingDef).fluid_capacity


func get_info_lines() -> PackedStringArray:
	var net := world.fluids.get_pipe_network(self)
	if net == null or net.fluid < 0:
		return PackedStringArray([tr("INFO_PIPE_EMPTY") % roundi(net.capacity if net != null else 0.0)])
	return PackedStringArray([tr("INFO_PIPE_FLUID") % [tr(Registry.fluids[net.fluid].name_key), roundi(net.amount), roundi(net.capacity)]])


# --- Окно ---

func get_window_sections() -> Array[WindowSection]:
	return [WindowSection.fluid(tr("WINDOW_NETWORK_FLUID"), world.fluids.get_pipe_network(self))]
