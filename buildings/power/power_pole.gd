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
