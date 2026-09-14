class_name GatewayLink
extends RefCounted
## Связь центрального шлюза планеты с его парой в базе: две очереди предметов между мирами.
## «В базу» заполняет вход шлюза на планете и опустошает выход пары; «наружу» — наоборот.

var planet_gateway: GatewayBuilding
var base_gateway: GatewayBuilding
var capacity: int = 10

var _to_base := PackedInt32Array()
var _to_planet := PackedInt32Array()


func has_space(to_base: bool) -> bool:
	return size_of(to_base) < capacity


func size_of(to_base: bool) -> int:
	return _to_base.size() if to_base else _to_planet.size()


func push(to_base: bool, item: int) -> void:
	if to_base:
		_to_base.append(item)
	else:
		_to_planet.append(item)


func peek(to_base: bool) -> int:
	return _to_base[0] if to_base else _to_planet[0]


func pop(to_base: bool) -> void:
	if to_base:
		_to_base.remove_at(0)
	else:
		_to_planet.remove_at(0)


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
