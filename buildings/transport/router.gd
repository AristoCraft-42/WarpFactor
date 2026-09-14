class_name Router
extends Building
## Маршрутизатор (как в Mindustry): принимает предметы со всех сторон и отдаёт по кругу во все стороны,
## в том числе обратно источнику, если тот принимает (цепочки маршрутизаторов гоняют предметы туда-сюда).
## Исключение — мгновенные здания (сортировщик, клапан): им назад не отдаёт, иначе предмет метался бы
## между ними без задержки.
## Предмет выходит через get_ticks_per_item() − 1 тиков после входа: источник, разбуженный в тике
## отдачи, приносит следующий ровно через get_ticks_per_item() — это и есть пропускная способность.

var item: int = -1
## Источник-мгновенное здание, которому предмет назад не отдаётся (0 — такого нет).
var _from_id: int = 0
var _ready_tick: int = 0


func accept_item(_source: Building, _item: int) -> bool:
	return item < 0


func handle_item(source: Building, new_item: int) -> void:
	item = new_item
	_from_id = source.id if source is PassThroughBuilding else 0
	_ready_tick = world.simulation.tick + maxi((def as LogisticDef).get_ticks_per_item() - 1, 1)
	wake()


func on_proximity_changed() -> void:
	wake()


func update_tick(tick: int) -> bool:
	if item < 0:
		return false
	if tick < _ready_tick:
		sleep_until(_ready_tick)
		return false
	var n := proximity.size()
	for k in n:
		var target := proximity[(_dump_index + k) % n]
		if target.id == _from_id:
			continue
		if target.accept_item(self, item):
			var passed := item
			item = -1
			_dump_index = (_dump_index + k + 1) % n
			target.handle_item(self, passed)
			notify_space()
			return false
	for target in proximity:
		if target.id != _from_id:
			wait_for(target)
	return false


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


func get_info_lines() -> PackedStringArray:
	if item < 0:
		return PackedStringArray([tr("INFO_EMPTY")])
	return PackedStringArray([tr("INFO_HOLDING") % tr(Registry.items[item].name_key)])
