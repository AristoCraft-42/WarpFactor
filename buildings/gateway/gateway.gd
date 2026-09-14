class_name GatewayBuilding
extends Building
## Центральный шлюз на планете и его пара в базе — зеркальные порты между мирами (GatewayLink).
## На планете вход (inbound_side) принимает предметы в очередь «в базу», выход (outbound_side)
## отдаёт очередь «наружу». В базе на тех же сторонах наоборот: inbound_side отдаёт «в базу»,
## outbound_side принимает «наружу». Отдача ограничена пропускной способностью ленты порта.
## Предмет принимается только от здания, стоящего на тайле входного порта.
## Через шлюз проходит дрон (Run.use_gateway).

var link: GatewayLink
var _next_out: int = 0


func get_gateway_def() -> GatewayDef:
	return def as GatewayDef


func is_in_base() -> bool:
	return get_gateway_def().in_base


## Сторона, через которую предметы входят в это здание.
func get_input_side() -> int:
	var d := get_gateway_def()
	return d.outbound_side if d.in_base else d.inbound_side


## Сторона, через которую предметы выходят из этого здания.
func get_output_side() -> int:
	var d := get_gateway_def()
	return d.inbound_side if d.in_base else d.outbound_side


func get_input_tile() -> Vector2i:
	return get_gateway_def().get_port_tile(origin, get_input_side())


func get_output_tile() -> Vector2i:
	return get_gateway_def().get_port_tile(origin, get_output_side())


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


func accept_item(source: Building, _item: int) -> bool:
	if link == null or source == null or not source.occupies(get_input_tile()):
		return false
	return link.has_space(not is_in_base())


func handle_item(_source: Building, item: int) -> void:
	link.push(not is_in_base(), item)
	var other := link.other(self)
	if other != null and other.world != null:
		other.wake()


func update_tick(tick: int) -> bool:
	if link == null:
		return false
	var to_base := is_in_base()
	if link.size_of(to_base) == 0:
		# Проснёмся, когда другая сторона положит предмет в очередь.
		return false
	if tick < _next_out:
		sleep_until(_next_out)
		return false
	var target := world.buildings.get_at(get_output_tile())
	if target == null:
		# Выхода нет — ждём, пока рядом что-нибудь построят (on_proximity_changed).
		return false
	var item := link.peek(to_base)
	if not target.accept_item(self, item):
		wait_for(target)
		return false
	link.pop(to_base)
	target.handle_item(self, item)
	_next_out = tick + get_gateway_def().get_ticks_per_item()
	# В очереди освободилось место — ленты у входа другой стороны могут отдавать дальше.
	var other := link.other(self)
	if other != null and other.world != null:
		other.notify_space()
	if link.size_of(to_base) > 0:
		sleep_until(_next_out)
	return false


func get_info_lines() -> PackedStringArray:
	if link == null:
		return PackedStringArray()
	return PackedStringArray([
		tr("INFO_GATEWAY_TO_BASE") % [link.size_of(true), link.capacity],
		tr("INFO_GATEWAY_TO_PLANET") % [link.size_of(false), link.capacity],
	])
