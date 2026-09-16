class_name PowerGraph
extends RefCounted
## Электросети мира. Опоры ЛЭП соединяются проводами (связи — смещения до других опор) и питают
## постройки, попавшие в их зону (квадрат вокруг опоры). Опоры, связанные проводами, и всё в их зонах —
## одна сеть. Постройка в зонах нескольких сетей принадлежит сети опоры с меньшим id.
##
## Каждый тик (до зданий):
##   спрос сети — сумма запросов потребителей (Building.power_request, кВт, выставляют сами здания);
##   предложение — сумма того, что генераторы могут дать за тик (топливо, пар);
##   удовлетворённость = предложение / спрос (не больше 1) — потребители работают медленнее при нехватке;
##   генераторы расходуют топливо пропорционально нагрузке.
## Состав сетей пересчитывается при изменении зданий (лениво, в начале следующего тика) — он полностью
## определяется постройками, поэтому в сохранение не пишется.

class PowerNetwork:
	var poles: Array[PowerPole] = []
	var consumers: Array[Building] = []
	var generators: Array[Building] = []
	## Удовлетворённость спроса 0..1 на текущий тик.
	var satisfaction: float = 0.0
	## Спрос и доступная мощность на прошлом тике, кВт (для интерфейса).
	var demand_kw: float = 0.0
	var capacity_kw: float = 0.0


var networks: Array[PowerNetwork] = []
## Опоры мира по id.
var poles: Dictionary[int, PowerPole] = {}
## Потребители вне зон опор (для значка «нет подключения»).
var unconnected: Array[Building] = []

var _world: GameWorld
var _dirty: bool = true
var _caps := PackedFloat64Array()


func _init(world: GameWorld) -> void:
	_world = world
	world.buildings.building_added.connect(_on_changed)
	world.buildings.building_removed.connect(_on_removed)


func dispose() -> void:
	_world = null
	networks.clear()
	poles.clear()
	unconnected.clear()


func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


func update() -> void:
	if _dirty:
		rebuild()
	var dt := GameConst.TICK_DT
	for net in networks:
		var demand := 0.0
		for c in net.consumers:
			demand += c.power_request * dt
		_caps.resize(net.generators.size())
		var capacity := 0.0
		for i in net.generators.size():
			var cap := net.generators[i].get_power_capacity_kj(dt)
			_caps[i] = cap
			capacity += cap
		net.demand_kw = demand / dt
		net.capacity_kw = capacity / dt
		if demand <= 0.0:
			net.satisfaction = 1.0 if capacity > 0.0 or net.consumers.is_empty() else 0.0
			continue
		net.satisfaction = minf(1.0, capacity / demand)
		var load := minf(1.0, demand / capacity) if capacity > 0.0 else 0.0
		for i in net.generators.size():
			if _caps[i] > 0.0:
				net.generators[i].draw_power_kj(_caps[i] * load)


## Пересчитать состав сетей по опорам, проводам и зонам.
func rebuild() -> void:
	_dirty = false
	networks.clear()
	unconnected.clear()
	for b in _world.buildings.get_all():
		b.power_net = null
	var ids := poles.keys()
	ids.sort()
	# Компоненты по проводам (связь в любую сторону).
	var parent: Dictionary[int, int] = {}
	for id in ids:
		parent[id] = id
	for id in ids:
		var pole := poles[id]
		for other in pole.get_linked_poles():
			_union(parent, id, other.id)
	var by_root: Dictionary[int, PowerNetwork] = {}
	for id in ids:
		var root := _find(parent, id)
		var net: PowerNetwork = by_root.get(root)
		if net == null:
			net = PowerNetwork.new()
			by_root[root] = net
			networks.append(net)
		net.poles.append(poles[id])
		poles[id].power_net = net
	for net in networks:
		for pole in net.poles:
			for b in _world.buildings.collect_in_rect(pole.get_supply_rect()):
				if b.power_net != null:
					continue
				if b.def.power_use > 0.0:
					b.power_net = net
					net.consumers.append(b)
				elif b.is_power_generator():
					b.power_net = net
					net.generators.append(b)
	for b in _world.buildings.get_all():
		if b.power_net == null and b.def.power_use > 0.0:
			unconnected.append(b)
	# Потребители, которые спали, пока сеть менялась, должны пересчитать скорость.
	for net in networks:
		for c in net.consumers:
			c.wake()


func _find(parent: Dictionary[int, int], id: int) -> int:
	var root := id
	while parent[root] != root:
		root = parent[root]
	var node := id
	while parent[node] != root:
		var next := parent[node]
		parent[node] = root
		node = next
	return root


func _union(parent: Dictionary[int, int], a: int, b: int) -> void:
	if not parent.has(a) or not parent.has(b):
		return
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)


# --- Опоры ---

func register_pole(pole: PowerPole) -> void:
	poles[pole.id] = pole
	_dirty = true


func unregister_pole(pole: PowerPole) -> void:
	poles.erase(pole.id)
	# Связи других опор на снесённую убираются, чтобы новая опора на том же месте не соединилась сама.
	for other in pole.get_linked_poles():
		other.unlink(pole)
	_dirty = true


## Новая опора соединяется проводами с ближайшими опорами в радиусе (пока у обеих есть свободные связи).
func auto_link(pole: PowerPole) -> void:
	var d := pole.get_pole_def()
	var center := pole.get_world_center()
	var reach := d.wire_range * GameConst.TILE_SIZE
	var candidates: Array[PowerPole] = []
	var ids := poles.keys()
	ids.sort()
	for id in ids:
		var other := poles[id]
		if other == pole or pole.is_linked(other):
			continue
		var other_reach := minf(reach, other.get_pole_def().wire_range * GameConst.TILE_SIZE)
		if other.get_world_center().distance_to(center) <= other_reach:
			candidates.append(other)
	candidates.sort_custom(func(a: PowerPole, b: PowerPole) -> bool:
		var da := a.get_world_center().distance_squared_to(center)
		var db := b.get_world_center().distance_squared_to(center)
		return da < db if da != db else a.id < b.id)
	for other in candidates:
		if pole.link_count() >= d.max_links:
			break
		if other.link_count() >= other.get_pole_def().max_links:
			continue
		pole.link(other)
		other.link(pole)
	_dirty = true


func _on_changed(_building: Building) -> void:
	_dirty = true


func _on_removed(building: Building) -> void:
	building.power_net = null
	_dirty = true
