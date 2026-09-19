class_name Router
extends Building
## Маршрутизатор (как в Mindustry): принимает предметы со всех сторон и отдаёт по кругу во все стороны.
## Источнику предмет возвращается только если остальные выходы не принимают — иначе цепочка
## маршрутизатор+перекрёсток разворачивает поток (перекрёсток шлёт на противоположную сторону).
## Мгновенным зданиям (сортировщик) назад не отдаёт никогда: предмет метался бы без задержки.
## Предмет выходит через get_ticks_per_item() − 1 тиков после входа: источник, разбуженный в тике
## отдачи, приносит следующий ровно через get_ticks_per_item() — это и есть пропускная способность.
##
## Настройка — приоритетные стороны (относительно поворота, поэтому R поворачивает их вместе со зданием):
## - приоритетный выход: предмет сначала предлагается этой стороне, остальным — только если она занята;
## - приоритетный вход: пока по ленте с этой стороны к маршрутизатору едут предметы, другие входы ждут.

const NO_SIDE := -1

var item: int = -1
## Приоритетные стороны относительно поворота (NO_SIDE — нет).
var priority_in: int = NO_SIDE
var priority_out: int = NO_SIDE
## Откуда пришёл текущий предмет (0 — неизвестно). Ему отдаём в последнюю очередь.
var _from_id: int = 0
var _ready_tick: int = 0


## Сторона в мире (0..3) для относительной стороны; NO_SIDE остаётся NO_SIDE.
func world_side(relative: int) -> int:
	return NO_SIDE if relative == NO_SIDE else posmod(relative + rotation, 4)


func accept_item(source: Building, _item: int) -> bool:
	if item >= 0:
		return false
	if priority_in != NO_SIDE and source != null and side_of(source) != world_side(priority_in):
		# Приоритетный вход: уступаем ленте с приоритетной стороны, пока на ней есть предметы для нас.
		var favored := world.buildings.get_at(origin + GameConst.dir_vector(world_side(priority_in)))
		if favored is Conveyor and world.simulation.conveyors.has_items_heading_to(favored.id, id):
			return false
	return true


func handle_item(source: Building, new_item: int) -> void:
	item = new_item
	_from_id = source.id if source != null else 0
	_ready_tick = world.simulation.tick + maxi((def as LogisticDef).get_ticks_per_item() - 1, 1)
	wake()


func on_proximity_changed() -> void:
	wake()


func on_rotated(_old_rotation: int) -> void:
	wake()


func update_tick(tick: int) -> bool:
	if item < 0:
		return false
	if tick < _ready_tick:
		sleep_until(_ready_tick)
		return false
	# Приоритетный выход — первым.
	if priority_out != NO_SIDE:
		var favored := world.buildings.get_at(origin + GameConst.dir_vector(world_side(priority_out)))
		if favored != null and favored.id != _from_id and favored.accept_item(self, item):
			_give(favored)
			return false
	var n := proximity.size()
	for k in n:
		var target := proximity[(_dump_index + k) % n]
		if target.id == _from_id:
			continue
		if target.accept_item(self, item):
			_dump_index = (_dump_index + k + 1) % n
			_give(target)
			return false
	# Другие выходы заняты — вернуть источнику (тупик). Перекрёстку это нельзя делать первым:
	# он отправит предмет на противоположную сторону и поток развернётся.
	var src := _source_building()
	if src != null and not (src is PassThroughBuilding) and src.accept_item(self, item):
		_give(src)
		return false
	for target in proximity:
		if target.id == _from_id and target is PassThroughBuilding:
			continue
		wait_for(target)
	return false


func _give(target: Building) -> void:
	var passed := item
	item = -1
	target.handle_item(self, passed)
	notify_space()


func _source_building() -> Building:
	return world.buildings.get_by_id(_from_id) if _from_id != 0 else null


func save_state() -> Dictionary:
	return {"item": item, "ready_tick": _ready_tick, "from": _from_id}


func load_state(state: Dictionary) -> void:
	item = SaveContext.item(int(state.get("item", -1)))
	_ready_tick = int(state.get("ready_tick", 0))
	_from_id = int(state.get("from", 0))
	wake()


func collect_contents(out: PackedInt32Array) -> void:
	if item >= 0:
		out[item] += 1


# --- Настройка ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.ROUTER


## null — без приоритетов, иначе {"in": сторона, "out": сторона} (стороны относительно поворота).
func get_config() -> Variant:
	if priority_in == NO_SIDE and priority_out == NO_SIDE:
		return null
	return {"in": priority_in, "out": priority_out}


func set_config(value: Variant) -> void:
	priority_in = NO_SIDE
	priority_out = NO_SIDE
	if value is Dictionary:
		priority_in = _side(int((value as Dictionary).get("in", NO_SIDE)))
		priority_out = _side(int((value as Dictionary).get("out", NO_SIDE)))
	if world != null:
		wake()


static func _side(value: int) -> int:
	return value if value >= 0 and value <= 3 else NO_SIDE


func has_priorities() -> bool:
	return priority_in != NO_SIDE or priority_out != NO_SIDE


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if item < 0:
		lines.append(tr("INFO_EMPTY"))
	else:
		lines.append(tr("INFO_HOLDING") % tr(Registry.items[item].name_key))
	if priority_in != NO_SIDE:
		lines.append(tr("INFO_ROUTER_PRIORITY_IN"))
	if priority_out != NO_SIDE:
		lines.append(tr("INFO_ROUTER_PRIORITY_OUT"))
	return lines
