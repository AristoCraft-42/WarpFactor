class_name Conveyor
extends Building
## Лента. Сам объект нужен для размещения, соседства, подсказок и (позже) сохранения;
## данные и движение предметов живут в ConveyorSystem. В список бодрствующих зданий лента не входит.


func _system() -> ConveyorSystem:
	return world.simulation.conveyors


func on_placed() -> void:
	_system().add(self)


func on_removed() -> void:
	_system().remove(self)


func on_rotated(_old_rotation: int) -> void:
	_system().set_direction(self)


func on_proximity_changed() -> void:
	_system().relink(self)
	_system().wake_building(id)


func wake() -> void:
	if world != null:
		_system().wake_building(id)


func accept_item(source: Building, _item: int) -> bool:
	return _system().accept_from(self, source)


func handle_item(source: Building, item: int) -> void:
	_system().insert_from(self, source, item)


func collect_contents(out: PackedInt32Array) -> void:
	_system().collect(self, out)


func save_state() -> Dictionary:
	return _system().export_items(self)


func load_state(state: Dictionary) -> void:
	_system().import_items(self, state)


func get_info_lines() -> PackedStringArray:
	var sys := _system()
	var c := sys.index_of(id)
	if c < 0:
		return PackedStringArray()
	var lines := PackedStringArray()
	lines.append(tr("INFO_CONVEYOR_ITEMS") % [sys.counts[c], ConveyorSystem.CAP])
	if def is ConveyorDef:
		lines.append(tr("STAT_THROUGHPUT") % (def as ConveyorDef).get_items_per_second())
	return lines
