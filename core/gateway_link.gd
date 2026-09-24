class_name GatewayLink
extends RefCounted
## Связь центрального шлюза планеты с его парой в базе: очереди предметов между мирами.
## «В базу» заполняет вход шлюза на планете и опустошает выход пары; «наружу» — наоборот.
##
## У каждого порта своя очередь: что вошло в k-й вход, выйдет из k-го выхода на другом этаже
## и ничего не перепутается. Порты считаются от середины стороны наружу, поэтому k-й вход и k-й
## выход лежат на одной линии — поток идёт насквозь.

var planet_gateway: GatewayBuilding
var base_gateway: GatewayBuilding
## Вместимость очереди на один открытый порт (очередь вмещает capacity × портов).
var capacity: int = 10
## Сколько предметов каждого типа ушло в базу и на планету за время на текущей планете.
var sent_to_base := PackedInt32Array()
var sent_to_planet := PackedInt32Array()

## Очереди по портам: [порт][предметы].
var _to_base: Array[PackedInt32Array] = []
var _to_planet: Array[PackedInt32Array] = []


func _init() -> void:
	reset_counters()
	_resize(GatewayDef.MAX_PORTS)


func _resize(ports: int) -> void:
	while _to_base.size() < ports:
		_to_base.append(PackedInt32Array())
		_to_planet.append(PackedInt32Array())


func reset_counters() -> void:
	sent_to_base.resize(Registry.items.size())
	sent_to_base.fill(0)
	sent_to_planet.resize(Registry.items.size())
	sent_to_planet.fill(0)


func has_space(to_base: bool, port: int) -> bool:
	return size_of(to_base, port) < capacity


func size_of(to_base: bool, port: int) -> int:
	var queues := _to_base if to_base else _to_planet
	return queues[port].size() if port >= 0 and port < queues.size() else 0


## Сколько предметов ждёт во всех портах (для окна шлюза и итогов).
func total_of(to_base: bool) -> int:
	var sum := 0
	for queue in (_to_base if to_base else _to_planet):
		sum += queue.size()
	return sum


func push(to_base: bool, port: int, item: int) -> void:
	_resize(port + 1)
	if to_base:
		_to_base[port].append(item)
		sent_to_base[item] += 1
	else:
		_to_planet[port].append(item)
		sent_to_planet[item] += 1


func peek(to_base: bool, port: int) -> int:
	return (_to_base if to_base else _to_planet)[port][0]


func pop(to_base: bool, port: int) -> void:
	var queues := _to_base if to_base else _to_planet
	queues[port].remove_at(0)


func save_data() -> Dictionary:
	return {"to_base": _to_base.duplicate(true), "to_planet": _to_planet.duplicate(true), "capacity": capacity,
		"sent_to_base": sent_to_base.duplicate(), "sent_to_planet": sent_to_planet.duplicate(),
		"planet_gateway": planet_gateway.id if planet_gateway != null else 0,
		"base_gateway": base_gateway.id if base_gateway != null else 0}


func load_data(data: Dictionary) -> void:
	_to_base = _load_queues(data.get("to_base", []))
	_to_planet = _load_queues(data.get("to_planet", []))
	_resize(GatewayDef.MAX_PORTS)
	capacity = int(data.get("capacity", capacity))
	sent_to_base = SaveContext.counts(data.get("sent_to_base", PackedInt32Array()))
	sent_to_planet = SaveContext.counts(data.get("sent_to_planet", PackedInt32Array()))


## Очереди портов из сохранения. В старых сохранениях очередь была одна на сторону —
## всё, что в ней лежало, отдаём первому порту.
func _load_queues(value: Variant) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	if value is PackedInt32Array:
		result.append(SaveContext.items(value))
		return result
	for queue in (value as Array):
		result.append(SaveContext.items(queue))
	return result


## Здание на другом конце связи.
func other(gateway: GatewayBuilding) -> GatewayBuilding:
	return base_gateway if gateway == planet_gateway else planet_gateway


## Предметы в пути (для итогов и сноса мира).
func collect(out: PackedInt32Array) -> void:
	for queue in _to_base:
		for item in queue:
			out[item] += 1
	for queue in _to_planet:
		for item in queue:
			out[item] += 1


func dispose() -> void:
	if planet_gateway != null:
		planet_gateway.link = null
	if base_gateway != null:
		base_gateway.link = null
	planet_gateway = null
	base_gateway = null
