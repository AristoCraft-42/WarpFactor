class_name PowerPole
extends Building
## Опора ЛЭП. Провода хранятся смещениями до других опор (настройка здания: переносится пипеткой,
## переездом площадки и сохранением). Опора, поставленная игроком, сама соединяется с ближайшими
## (GameWorld.build → PowerGraph.auto_link); при загрузке и переезде связи берутся из настройки.

var link_offsets: Array[Vector2i] = []


func get_pole_def() -> PowerPoleDef:
	return def as PowerPoleDef


func on_placed() -> void:
	world.power.register_pole(self)


func on_removed() -> void:
	world.power.unregister_pole(self)


## Прямоугольник тайлов зоны питания.
func get_supply_rect() -> Rect2i:
	var s := get_pole_def().supply_size
	var center := origin + Vector2i.ONE * (def.size / 2)
	return Rect2i(center - Vector2i.ONE * (s / 2), Vector2i(s, s))


func link_count() -> int:
	return link_offsets.size()


func is_linked(other: PowerPole) -> bool:
	return link_offsets.has(other.origin - origin)


func link(other: PowerPole) -> void:
	var offset := other.origin - origin
	if offset != Vector2i.ZERO and not link_offsets.has(offset):
		link_offsets.append(offset)
		if world != null:
			world.power.mark_dirty()
			world.buildings.notify_changed(self)


func unlink(other: PowerPole) -> void:
	var offset := other.origin - origin
	if link_offsets.has(offset):
		link_offsets.erase(offset)
		if world != null:
			world.power.mark_dirty()
			world.buildings.notify_changed(self)


## Опоры, до которых есть провода (существующие и в радиусе).
func get_linked_poles() -> Array[PowerPole]:
	var result: Array[PowerPole] = []
	if world == null:
		return result
	var reach := get_pole_def().wire_range * GameConst.TILE_SIZE
	for offset in link_offsets:
		var other := world.buildings.get_at(origin + offset) as PowerPole
		if other != null and other != self and other.origin == origin + offset \
				and other.get_world_center().distance_to(get_world_center()) <= reach + 0.5:
			result.append(other)
	return result


func get_config_kind() -> ConfigKind:
	return ConfigKind.NONE


func get_config() -> Variant:
	if link_offsets.is_empty():
		return null
	var copy: Array = []
	for offset in link_offsets:
		copy.append(offset)
	return copy


func set_config(value: Variant) -> void:
	link_offsets.clear()
	if value is Array:
		for v in value:
			if v is Vector2i and v != Vector2i.ZERO and not link_offsets.has(v):
				link_offsets.append(v)
	if world != null:
		world.power.mark_dirty()


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(tr("INFO_POLE_LINKS") % [get_linked_poles().size(), get_pole_def().max_links])
	var net := power_net
	if net != null:
		lines.append(tr("INFO_POWER_NETWORK") % [roundi(net.demand_kw), roundi(net.capacity_kw)])
	return lines


# --- Окно ---

## Окно сети: нагрузка, заряд аккумуляторов, график спроса, выработки и заряда за последние минуты,
## состав сети по типам построек.
func get_window_sections() -> Array[WindowSection]:
	var net := power_net
	if net == null:
		return [WindowSection.bar(tr("WINDOW_NETWORK_LOAD"), 0.0, tr("WINDOW_NOT_CONNECTED"), WindowSection.COLOR_LOW)]
	var supply := net.capacity_kw + maxf(net.storage_kw, 0.0)
	var col := WindowSection.COLOR_POWER if net.satisfaction >= 0.999 else WindowSection.COLOR_LOW
	var sections: Array[WindowSection] = [WindowSection.bar(tr("WINDOW_NETWORK_LOAD"), net.demand_kw / maxf(net.capacity_kw, 0.001),
		tr("WINDOW_KW_OF") % [roundi(net.demand_kw), roundi(net.capacity_kw)], col)]
	if net.storage_capacity_kj > 0.0:
		sections.append(WindowSection.bar(tr("WINDOW_STORED"), net.stored_kj / net.storage_capacity_kj,
			tr("WINDOW_MJ_OF") % [net.stored_kj / 1000.0, net.storage_capacity_kj / 1000.0], WindowSection.COLOR_POWER))
	var history := net.history
	if history != null and history.demand.size() >= 2:
		var top := maxf(net.capacity_kw, supply)
		for v in history.demand:
			top = maxf(top, v)
		for v in history.supply:
			top = maxf(top, v)
		for v in history.capacity:
			top = maxf(top, v)
		top = maxf(top, 1.0)
		var charge := PackedFloat32Array()
		for v in history.charge:
			charge.append(v * top)
		var series: Array[PackedFloat32Array] = [history.demand, history.supply, history.capacity]
		var colors := PackedColorArray([Color(0.98, 0.29, 0.2), Color(0.72, 0.73, 0.15), Color(0.98, 0.74, 0.18)])
		var names := PackedStringArray([tr("WINDOW_GRAPH_DEMAND"), tr("WINDOW_GRAPH_SUPPLY"), tr("WINDOW_GRAPH_CAPACITY")])
		if net.storage_capacity_kj > 0.0:
			series.append(charge)
			colors.append(Color(0.51, 0.65, 0.6))
			names.append(tr("WINDOW_GRAPH_CHARGE"))
		sections.append(WindowSection.graph(tr("WINDOW_GRAPH_TOP") % roundi(top), series, colors, names, top))
	var lines := PackedStringArray()
	if net.linked:
		lines.append(tr("WINDOW_NETWORK_LINKED"))
	var sources: Array[Building] = []
	sources.append_array(net.generators)
	sources.append_array(net.storages)
	lines.append(tr("WINDOW_NETWORK_GENERATORS") % _count_by_type(sources))
	lines.append(tr("WINDOW_NETWORK_CONSUMERS") % _count_by_type(net.consumers))
	sections.append(WindowSection.text_lines(lines))
	return sections


## «Термогенератор ×2, Аккумулятор ×1» или «—».
func _count_by_type(list: Array[Building]) -> String:
	var counts := {}
	var order: Array[BuildingDef] = []
	for b in list:
		if not counts.has(b.def):
			counts[b.def] = 0
			order.append(b.def)
		counts[b.def] = int(counts[b.def]) + 1
	var parts := PackedStringArray()
	for d in order:
		parts.append("%s ×%d" % [tr(d.name_key), int(counts[d])])
	return ", ".join(parts) if not parts.is_empty() else "—"
