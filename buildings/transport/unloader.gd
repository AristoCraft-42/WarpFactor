class_name Unloader
extends Building
## Разгрузчик: достаёт предметы из соседних зданий, которые умеют их отдавать (can_unload):
## складов, готовой продукции заводов, буфера буров. Кладёт их соседям, которые принимают:
## лентам, заводам, складам. Из склада в склад не перекладывает (иначе предметы гонялись бы
## по кругу), назад в здание-источник — тоже.
## Настройка — фильтр по предмету; без фильтра — любые предметы по очереди.
## Скорость — пропускная способность ленты своего уровня.

var filter: int = -1
var blocked: bool = false
var _next_tick: int = 0
var _item_cursor: int = 0


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
	var sources: Array[Building] = []
	for other in proximity:
		if other.can_unload():
			sources.append(other)
	blocked = false
	if sources.is_empty() or proximity.size() < 2:
		return false
	var any_item := false
	var count := Registry.items.size()
	for k in count:
		var item := filter if filter >= 0 else (_item_cursor + k) % count
		if _has_in_sources(sources, item):
			any_item = true
			if _move(sources, item):
				if filter < 0:
					_item_cursor = (item + 1) % count
				_next_tick = tick + (def as LogisticDef).get_ticks_per_item()
				sleep_until(_next_tick)
				return false
		if filter >= 0:
			break
	if not any_item:
		# Нечего доставать: ждём, пока в источниках что-то появится.
		for source in sources:
			wait_for(source)
		return false
	blocked = true
	for other in proximity:
		wait_for(other)
	return false


func get_status() -> Status:
	return Status.OUTPUT_BLOCKED if blocked else Status.NONE


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if filter < 0:
		lines.append(tr("INFO_FILTER_ANY"))
	else:
		lines.append(tr("INFO_FILTER") % tr(Registry.items[filter].name_key))
	lines.append(tr("INFO_RATE") % (def as LogisticDef).get_items_per_second())
	return lines


func _has_in_sources(sources: Array[Building], item: int) -> bool:
	for source in sources:
		if source.has_item(item):
			return true
	return false


## Переложить один предмет item из какого-нибудь источника в какого-нибудь получателя (по кругу).
func _move(sources: Array[Building], item: int) -> bool:
	var n := proximity.size()
	for k in n:
		var target := proximity[(_dump_index + k) % n]
		var target_is_storage := target.get_inventory() != null
		var source: Building = null
		for candidate in sources:
			if candidate != target and candidate.has_item(item) and not (target_is_storage and candidate.get_inventory() != null):
				source = candidate
				break
		if source == null or not target.accept_item(self, item):
			continue
		if source.unload_item(item):
			_dump_index = (_dump_index + k + 1) % n
			target.handle_item(self, item)
			return true
	return false
