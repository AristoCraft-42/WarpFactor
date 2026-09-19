class_name CreativeBlock
extends Building
## Творческий блок: источник предметов, энергии или жидкости и поглотитель.
## Настройка — Vector2i(что выдаём, номер ступени скорости): для предметов это индекс предмета,
## для жидкости — индекс жидкости, для энергии и поглотителя важна только ступень.
##
## Источник предметов копит дробный остаток и раздаёт соседям по кругу, как бур.
## Источник жидкости наливает в свою сеть, поглотитель — выкачивает из неё и принимает любые предметы.
## Источник энергии для PowerGraph — обычный генератор, поглотитель — обычный потребитель.

## Что выдаёт (индекс предмета или жидкости; -1 — не выбрано).
var pick: int = -1
## Номер ступени скорости.
var rate_index: int = 0
## Накопленный дробный остаток для выдачи предметов.
var _progress: float = 0.0
## Сколько отдано и принято за прошлую секунду (для окна).
var moved: int = 0
var _moved_tick: int = 0
var _moved_counter: int = 0


func get_creative_def() -> CreativeBlockDef:
	return def as CreativeBlockDef


func get_rate() -> float:
	return get_creative_def().get_rate(rate_index)


func on_placed() -> void:
	var d := get_creative_def()
	rate_index = d.default_rate
	if pick < 0:
		if d.kind == CreativeBlockDef.Kind.ITEM and not Registry.items.is_empty():
			pick = Registry.items[0].index
		elif d.kind == CreativeBlockDef.Kind.FLUID and not Registry.fluids.is_empty():
			pick = 0
	if d.kind == CreativeBlockDef.Kind.FLUID or d.kind == CreativeBlockDef.Kind.VOID:
		world.fluids.mark_dirty()
	wake()


func on_removed() -> void:
	var d := get_creative_def()
	if d.kind == CreativeBlockDef.Kind.FLUID or d.kind == CreativeBlockDef.Kind.VOID:
		world.fluids.mark_dirty()


func on_proximity_changed() -> void:
	wake()


func update_tick(tick: int) -> bool:
	var d := get_creative_def()
	if tick - _moved_tick >= GameConst.TICK_RATE:
		_moved_tick = tick
		moved = _moved_counter
		_moved_counter = 0
	match d.kind:
		CreativeBlockDef.Kind.ITEM:
			_produce_items()
		CreativeBlockDef.Kind.FLUID:
			_produce_fluid()
		CreativeBlockDef.Kind.VOID:
			power_request = get_rate()
			_drain_fluid()
		CreativeBlockDef.Kind.POWER:
			pass
	return true


## Выдать предметы соседям по кругу; то, что не взяли, не копится.
func _produce_items() -> void:
	if pick < 0:
		return
	_progress += get_rate() * GameConst.TICK_DT
	var n := proximity.size()
	while _progress >= 1.0:
		_progress -= 1.0
		var given := false
		for k in n:
			var index := (_dump_index + k) % n
			var target := proximity[index]
			if target.accept_item(self, pick):
				target.handle_item(self, pick)
				_dump_index = (index + 1) % n
				given = true
				_moved_counter += 1
				break
		if not given:
			_progress = 0.0
			return


func _produce_fluid() -> void:
	if pick < 0 or pick >= Registry.fluids.size():
		return
	var net := world.fluids.get_port_network(self, 0)
	if net == null:
		return
	_moved_counter += roundi(net.insert(pick, get_rate() * GameConst.TICK_DT))


func _drain_fluid() -> void:
	var net := world.fluids.get_port_network(self, 0)
	if net == null or net.fluid < 0:
		return
	_moved_counter += roundi(net.extract(net.fluid, get_rate() * GameConst.TICK_DT))


# --- Предметы ---

## Поглотитель принимает всё, остальные блоки предметы не принимают.
func accept_item(_source: Building, _item: int) -> bool:
	return get_creative_def().kind == CreativeBlockDef.Kind.VOID


func handle_item(_source: Building, _item: int) -> void:
	_moved_counter += 1
	notify_space()


# --- Энергия ---

func is_power_generator() -> bool:
	return get_creative_def().kind == CreativeBlockDef.Kind.POWER


func get_power_capacity_kj(dt: float) -> float:
	return get_rate() * dt


func draw_power_kj(kj: float) -> void:
	_moved_counter += roundi(kj)


# --- Жидкости ---

func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	var d := get_creative_def()
	if d.kind != CreativeBlockDef.Kind.FLUID and d.kind != CreativeBlockDef.Kind.VOID:
		return ports
	for side in 4:
		ports.append(FluidGraph.Port.new(side, null, 0))
	return ports


# --- Настройка ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.SOURCE


func get_config() -> Variant:
	return Vector2i(pick, rate_index)


func set_config(value: Variant) -> void:
	if not (value is Vector2i):
		return
	var v := value as Vector2i
	var d := get_creative_def()
	pick = v.x
	rate_index = clampi(v.y, 0, maxi(d.rates.size() - 1, 0))
	_progress = 0.0
	if d.kind == CreativeBlockDef.Kind.FLUID:
		world.fluids.mark_dirty()
	wake()
	notify_space()


## Из чего выбирать в панели настройки: предметы, жидкости или ничего.
func get_source_kind() -> CreativeBlockDef.Kind:
	return get_creative_def().kind


# --- Сохранение ---

func save_state() -> Dictionary:
	return {"pick": pick, "rate": rate_index, "progress": _progress}


func load_state(state: Dictionary) -> void:
	pick = int(state.get("pick", -1))
	rate_index = int(state.get("rate", get_creative_def().default_rate))
	_progress = float(state.get("progress", 0.0))
	wake()


# --- Подсказки и окно ---

func get_status() -> Status:
	return Status.WORKING


func has_player_window() -> bool:
	return true


func get_info_lines() -> PackedStringArray:
	var d := get_creative_def()
	var lines := PackedStringArray()
	match d.kind:
		CreativeBlockDef.Kind.ITEM:
			lines.append(tr("INFO_CREATIVE_ITEM") % [tr(Registry.items[pick].name_key) if pick >= 0 else "—", get_rate()])
		CreativeBlockDef.Kind.FLUID:
			lines.append(tr("INFO_CREATIVE_FLUID") % [tr(Registry.fluids[pick].name_key) if pick >= 0 else "—", get_rate()])
		CreativeBlockDef.Kind.POWER:
			lines.append(tr("INFO_CREATIVE_POWER") % get_rate())
		CreativeBlockDef.Kind.VOID:
			lines.append(tr("INFO_CREATIVE_VOID") % get_rate())
	lines.append(tr("INFO_CREATIVE_MOVED") % moved)
	return lines


func get_window_sections() -> Array[WindowSection]:
	var sections: Array[WindowSection] = []
	sections.append(WindowSection.text_lines(get_info_lines()))
	var net := world.fluids.get_port_network(self, 0) if not get_fluid_ports().is_empty() else null
	if net != null:
		sections.append(WindowSection.fluid(tr("WINDOW_FLUID"), net))
	return sections
