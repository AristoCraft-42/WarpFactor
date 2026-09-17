class_name GatewayLink
extends RefCounted
## Связь центрального шлюза планеты с его парой в базе: две очереди предметов между мирами.
## «В базу» заполняет вход шлюза на планете и опустошает выход пары; «наружу» — наоборот.

var planet_gateway: GatewayBuilding
var base_gateway: GatewayBuilding
## Вместимость очереди на один открытый порт (очередь вмещает capacity × портов).
var capacity: int = 10
## Сколько предметов каждого типа ушло в базу и на планету за время на текущей планете.
var sent_to_base := PackedInt32Array()
var sent_to_planet := PackedInt32Array()

var _to_base := PackedInt32Array()
var _to_planet := PackedInt32Array()


func _init() -> void:
	reset_counters()


func reset_counters() -> void:
	sent_to_base.resize(Registry.items.size())
	sent_to_base.fill(0)
	sent_to_planet.resize(Registry.items.size())
	sent_to_planet.fill(0)


func has_space(to_base: bool) -> bool:
	return size_of(to_base) < capacity


func size_of(to_base: bool) -> int:
	return _to_base.size() if to_base else _to_planet.size()


func push(to_base: bool, item: int) -> void:
	if to_base:
		_to_base.append(item)
		sent_to_base[item] += 1
	else:
		_to_planet.append(item)
		sent_to_planet[item] += 1


func peek(to_base: bool) -> int:
	return _to_base[0] if to_base else _to_planet[0]


func pop(to_base: bool) -> void:
	if to_base:
		_to_base.remove_at(0)
	else:
		_to_planet.remove_at(0)


func save_data() -> Dictionary:
	return {"to_base": _to_base.duplicate(), "to_planet": _to_planet.duplicate(), "capacity": capacity,
		"sent_to_base": sent_to_base.duplicate(), "sent_to_planet": sent_to_planet.duplicate(),
		"planet_gateway": planet_gateway.id if planet_gateway != null else 0,
		"base_gateway": base_gateway.id if base_gateway != null else 0}


func load_data(data: Dictionary) -> void:
	_to_base = SaveContext.items(data.get("to_base", PackedInt32Array()))
	_to_planet = SaveContext.items(data.get("to_planet", PackedInt32Array()))
	capacity = int(data.get("capacity", capacity))
	sent_to_base = SaveContext.counts(data.get("sent_to_base", PackedInt32Array()))
	sent_to_planet = SaveContext.counts(data.get("sent_to_planet", PackedInt32Array()))


## Здание на другом конце связи.
func other(gateway: GatewayBuilding) -> GatewayBuilding:
	return base_gateway if gateway == planet_gateway else planet_gateway


## Предметы в пути (для итогов и сноса мира).
func collect(out: PackedInt32Array) -> void:
	for item in _to_base:
		out[item] += 1
	for item in _to_planet:
		out[item] += 1


func dispose() -> void:
	if planet_gateway != null:
		planet_gateway.link = null
	if base_gateway != null:
		base_gateway.link = null
	planet_gateway = null
	base_gateway = null
