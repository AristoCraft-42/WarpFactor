class_name PowerGraph
extends RefCounted
## Электросети мира. Опоры ЛЭП соединяются проводами (связи — смещения до других опор) и питают
## постройки, попавшие в их зону (квадрат вокруг опоры). Опоры, связанные проводами, и всё в их зонах —
## одна сеть. Постройка в зонах нескольких сетей принадлежит сети опоры с меньшим id.
##
## Каждый тик (до зданий), по сети или группе сетей, соединённых шлюзом и лифтами между этажами:
##   спрос — сумма запросов потребителей (Building.power_request, кВт, выставляют сами здания);
##   выработка — сколько генераторы могут дать за тик (топливо, пар);
##   нехватку покрывают аккумуляторы (не больше запаса и их мощности), излишек их заряжает;
##   удовлетворённость = (выработка на спрос + разряд) / спрос — потребители работают медленнее при нехватке;
##   генераторы расходуют топливо пропорционально тому, что у них взяли.
## Мир в забеге: prepare() и общий баланс групп делает Run (сети этажей могут быть связаны), update() — пусто.
## Отдельный мир (тесты, бенчмарки): update() сам готовит и считает каждую сеть.
## Состав сетей пересчитывается при изменении зданий (лениво, в начале следующего тика) — он полностью
## определяется постройками, поэтому в сохранение не пишется. История для графика — по ключу сети
## (наименьший id опоры), переживает пересборку; тоже не сохраняется.

## История: одна точка на HISTORY_TICKS тиков, хранится HISTORY_SIZE точек.
const HISTORY_TICKS := 30
const HISTORY_SIZE := 120

class PowerNetwork:
	var poles: Array[PowerPole] = []
	var consumers: Array[Building] = []
	var generators: Array[Building] = []
	var storages: Array[Building] = []
	## Постройки-связи между этажами (шлюз, лифты), стоящие в зоне опор этой сети.
	var links: Array[Building] = []
	## Постоянное имя сети: наименьший id опоры.
	var key: int = 0
	## Удовлетворённость спроса 0..1 на текущий тик.
	var satisfaction: float = 0.0
	## Спрос, возможная выработка и поток аккумуляторов (+ разряд, − заряд) на прошлом тике, кВт
	## (для связанных сетей — по всей группе).
	var demand_kw: float = 0.0
	var capacity_kw: float = 0.0
	var storage_kw: float = 0.0
	## Запас и ёмкость аккумуляторов группы, кДж.
	var stored_kj: float = 0.0
	var storage_capacity_kj: float = 0.0
	## Сеть связана с сетью другого этажа.
	var linked: bool = false
	var history: PowerHistory

	# Подготовка тика.
	var demand_kj: float = 0.0
	var caps := PackedFloat64Array()
	var give := PackedFloat64Array()
	var take := PackedFloat64Array()


## Точки графика сети: спрос, выработка, заряд аккумуляторов (доля) — средние за HISTORY_TICKS тиков.
class PowerHistory:
	var demand := PackedFloat32Array()
	var supply := PackedFloat32Array()
	## Сколько сеть могла бы выдать (генераторы на полную) — верхняя граница выработки.
	var capacity := PackedFloat32Array()
	var charge := PackedFloat32Array()
	var _sum_demand: float = 0.0
	var _sum_supply: float = 0.0
	var _sum_capacity: float = 0.0
	var _ticks: int = 0

	func add(demand_kw: float, supply_kw: float, capacity_kw: float, charge_share: float) -> void:
		_sum_demand += demand_kw
		_sum_supply += supply_kw
		_sum_capacity += capacity_kw
		_ticks += 1
		if _ticks < HISTORY_TICKS:
			return
		demand = _push(demand, _sum_demand / _ticks)
		supply = _push(supply, _sum_supply / _ticks)
		capacity = _push(capacity, _sum_capacity / _ticks)
		charge = _push(charge, charge_share)
		_sum_demand = 0.0
		_sum_supply = 0.0
		_sum_capacity = 0.0
		_ticks = 0

	static func _push(values: PackedFloat32Array, value: float) -> PackedFloat32Array:
		values.append(value)
		if values.size() > HISTORY_SIZE:
			values.remove_at(0)
		return values


var networks: Array[PowerNetwork] = []
## Опоры мира по id.
var poles: Dictionary[int, PowerPole] = {}
## Потребители вне зон опор (для значка «нет подключения»).
var unconnected: Array[Building] = []
## Балансом управляет забег (сети этажей могут быть связаны).
var managed: bool = false

var _world: GameWorld
var _dirty: bool = true
var _history: Dictionary[int, PowerHistory] = {}


func _init(world: GameWorld) -> void:
	_world = world
	world.buildings.building_added.connect(_on_changed)
	world.buildings.building_removed.connect(_on_removed)


func dispose() -> void:
	_world = null
	networks.clear()
	poles.clear()
	unconnected.clear()
	_history.clear()


func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## Тик отдельного мира: подготовка и баланс каждой сети. В забеге баланс считает Run.
func update() -> void:
	if managed:
		return
	prepare()
	for net in networks:
		balance([net])


## Пересобрать сети при изменениях и собрать спрос, возможную выработку и возможности аккумуляторов.
func prepare() -> void:
	if _dirty:
		rebuild()
	var dt := GameConst.TICK_DT
	for net in networks:
		var demand := 0.0
		for c in net.consumers:
			demand += c.power_request * dt
		net.demand_kj = demand
		net.caps.resize(net.generators.size())
		for i in net.generators.size():
			net.caps[i] = net.generators[i].get_power_capacity_kj(dt)
		net.give.resize(net.storages.size())
		net.take.resize(net.storages.size())
		for i in net.storages.size():
			var storage := net.storages[i] as Accumulator
			net.give[i] = storage.get_discharge_limit_kj(dt)
			net.take[i] = storage.get_charge_limit_kj(dt)


## Баланс группы сетей (одна сеть или сети этажей, связанные шлюзом и лифтами): общая удовлетворённость,
## расход генераторов пропорционально их возможностям, разряд и заряд аккумуляторов пропорционально их пределам.
static func balance(group: Array[PowerNetwork]) -> void:
	var dt := GameConst.TICK_DT
	var demand := 0.0
	var caps := 0.0
	var give := 0.0
	var take := 0.0
	var stored := 0.0
	var storage_capacity := 0.0
	var has_consumers := false
	for net in group:
		demand += net.demand_kj
		has_consumers = has_consumers or not net.consumers.is_empty()
		for c in net.caps:
			caps += c
		for g in net.give:
			give += g
		for t in net.take:
			take += t
		for s in net.storages:
			stored += (s as Accumulator).stored_kj
			storage_capacity += (s as Accumulator).get_accumulator_def().capacity_kj
	var from_generators := minf(caps, demand)
	var discharge := minf(demand - from_generators, give)
	var charge := minf(caps - from_generators, take)
	var satisfaction := 1.0
	if demand > 0.0:
		satisfaction = minf(1.0, (from_generators + discharge) / demand)
	elif caps <= 0.0 and give <= 0.0 and has_consumers:
		satisfaction = 0.0
	var draw_share := (from_generators + charge) / caps if caps > 0.0 else 0.0
	var give_share := discharge / give if give > 0.0 else 0.0
	var take_share := charge / take if take > 0.0 else 0.0
	for net in group:
		for i in net.generators.size():
			if net.caps[i] > 0.0:
				net.generators[i].draw_power_kj(net.caps[i] * draw_share)
		for i in net.storages.size():
			var storage := net.storages[i] as Accumulator
			storage.apply_flow_kj(net.take[i] * take_share - net.give[i] * give_share, dt)
	stored += charge - discharge
	for net in group:
		net.satisfaction = satisfaction
		net.demand_kw = demand / dt
		net.capacity_kw = caps / dt
		net.storage_kw = (discharge - charge) / dt
		net.stored_kj = stored
		net.storage_capacity_kj = storage_capacity
		net.linked = group.size() > 1
		if net.history != null:
			net.history.add(net.demand_kw, (from_generators + discharge) / dt, net.capacity_kw,
				stored / storage_capacity if storage_capacity > 0.0 else 0.0)


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
			net.key = id
			by_root[root] = net
			networks.append(net)
		net.poles.append(poles[id])
		poles[id].power_net = net
	var kept: Dictionary[int, PowerHistory] = {}
	for net in networks:
		net.history = _history.get(net.key, PowerHistory.new())
		kept[net.key] = net.history
		for pole in net.poles:
			for b in _world.buildings.collect_in_rect(pole.get_supply_rect()):
				if b.power_net != null:
					continue
				if b.def.power_use > 0.0:
					b.power_net = net
					net.consumers.append(b)
				elif b.is_power_storage():
					b.power_net = net
					net.storages.append(b)
				elif b.is_power_generator():
					b.power_net = net
					net.generators.append(b)
				elif b.is_power_link():
					b.power_net = net
					net.links.append(b)
	_history = kept
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
