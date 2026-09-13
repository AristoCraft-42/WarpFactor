class_name Router
extends Building
## Делитель: держит один предмет и после задержки отдаёт его по кругу любому соседу, кроме источника.

var item: int = -1
var _from_id: int = 0
var _ready_tick: int = 0


func accept_item(_source: Building, _item: int) -> bool:
	return item < 0


func handle_item(source: Building, new_item: int) -> void:
	item = new_item
	_from_id = source.id if source != null else 0
	_ready_tick = world.simulation.tick + (def as LogisticDef).transfer_ticks
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


func collect_contents(out: PackedInt32Array) -> void:
	if item >= 0:
		out[item] += 1


func get_info_lines() -> PackedStringArray:
	if item < 0:
		return PackedStringArray([tr("INFO_EMPTY")])
	return PackedStringArray([tr("INFO_HOLDING") % tr(Registry.items[item].name_key)])
