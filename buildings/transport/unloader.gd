class_name Unloader
extends Building
## Разгрузчик: перекладывает предметы между соседями, балансируя их заполненность (как в Mindustry).
## Источник — сосед, который отдаёт предмет (can_unload): склад, завод (и сырьё, и продукция), бур.
## Получатель — сосед, который принимает предмет, кроме складов: в склад разгрузчик не кладёт.
## Берёт у самого заполненного этим предметом источника (склады и буры — в первую очередь)
## и отдаёт наименее заполненному получателю; между двумя заводами перекладывает, только пока
## их заполненность различается — поэтому предметы не гоняются по кругу.
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


func save_state() -> Dictionary:
	return {"next_tick": _next_tick, "cursor": _item_cursor}


func load_state(state: Dictionary) -> void:
	_next_tick = int(state.get("next_tick", 0))
	_item_cursor = maxi(SaveContext.item(int(state.get("cursor", 0))), 0)
	wake()


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


## Переложить один предмет item: от самого заполненного источника к наименее заполненному получателю.
func _move(sources: Array[Building], item: int) -> bool:
	var n := proximity.size()
	# Получатель: принимает предмет, не склад; при равной заполненности — по кругу.
	var target: Building = null
	var target_load := INF
	var target_k := 0
	for k in n:
		var other := proximity[(_dump_index + k) % n]
		if other.get_inventory() != null or not other.accept_item(self, item):
			continue
		var load := other.get_load_factor(item)
		if load < target_load:
			target = other
			target_load = load
			target_k = k
	if target == null:
		return false
	# Источник: сначала те, кто сам не принимает предмет (склады, буры), затем самые заполненные.
	var source: Building = null
	var source_can_load := true
	var source_load := -1.0
	for candidate in sources:
		if candidate == target or not candidate.has_item(item):
			continue
		var can_load := candidate.get_inventory() == null and candidate.accept_item(self, item)
		var load := candidate.get_load_factor(item)
		var better := source == null or (source_can_load and not can_load) or (can_load == source_can_load and load > source_load)
		if better:
			source = candidate
			source_can_load = can_load
			source_load = load
	if source == null:
		return false
	# Между двумя получателями одного уровня заполненности не перекладываем.
	if source_can_load and source_load <= target_load:
		return false
	if not source.unload_item(item):
		return false
	_dump_index = (_dump_index + target_k + 1) % n
	target.handle_item(self, item)
	return true
