class_name Unloader
extends Building
## Разгрузчик: берёт предметы из соседнего хранилища (ядро, позже контейнеры) и отдаёт соседям,
## которые хранилищами не являются. Настройка — фильтр по предмету (без фильтра — любые по очереди).

var filter: int = -1

var _next_tick: int = 0
var _item_cursor: int = 0
var blocked: bool = false


func get_config_kind() -> ConfigKind:
	return ConfigKind.ITEM


func get_config() -> Variant:
	return filter if filter >= 0 else null


func set_config(value: Variant) -> void:
	filter = int(value) if (value is int and int(value) >= 0 and int(value) < Registry.items.size()) else -1
	wake()


func get_display_item() -> int:
	return filter


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


func update_tick(tick: int) -> bool:
	if tick < _next_tick:
		sleep_until(_next_tick)
		return false
	var storages: Array[Building] = []
	var targets: Array[Building] = []
	for other in proximity:
		if other.can_unload():
			storages.append(other)
		else:
			targets.append(other)
	blocked = false
	if storages.is_empty() or targets.is_empty():
		return false

	var item := _choose_item(storages)
	if item < 0:
		for storage in storages:
			wait_for(storage)
		return false

	var n := targets.size()
	for k in n:
		var target := targets[(_dump_index + k) % n]
		if target.accept_item(self, item):
			for storage in storages:
				if storage.has_item(item) and storage.unload_item(item):
					_dump_index = (_dump_index + k + 1) % n
					target.handle_item(self, item)
					_next_tick = tick + maxi((def as LogisticDef).transfer_ticks, 1)
					sleep_until(_next_tick)
					return false
			break
	blocked = true
	for target in targets:
		wait_for(target)
	return false


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if filter < 0:
		lines.append(tr("INFO_FILTER_ANY"))
	else:
		lines.append(tr("INFO_FILTER") % tr(Registry.items[filter].name_key))
	lines.append(tr("INFO_RATE") % (float(GameConst.TICK_RATE) / maxi((def as LogisticDef).transfer_ticks, 1)))
	if blocked:
		lines.append(tr("INFO_OUTPUT_BLOCKED"))
	return lines


## Предмет для выгрузки: фильтр или следующий по кругу из имеющихся в хранилищах.
func _choose_item(storages: Array[Building]) -> int:
	if filter >= 0:
		for storage in storages:
			if storage.has_item(filter):
				return filter
		return -1
	var count := Registry.items.size()
	for k in count:
		var item := (_item_cursor + k) % count
		for storage in storages:
			if storage.has_item(item):
				_item_cursor = (item + 1) % count
				return item
	return -1
