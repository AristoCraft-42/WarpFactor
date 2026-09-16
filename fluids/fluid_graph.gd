class_name FluidGraph
extends RefCounted
## Сети труб мира. Узлы сети — трубы и порты машин (насос, бойлер, паровой генератор).
## Трубы соединяются с соседними трубами и с портами машин на прилегающей стороне (подземная труба — только
## с открытой стороны, а под землёй — со своей парой); порты двух машин,
## стоящих вплотную лицом друг к другу, соединяются без трубы. Порты одной машины с одинаковой группой —
## одна сеть (паровой генератор пропускает пар насквозь).
##
## У сети одна жидкость, общий объём и вместимость (трубы + небольшой запас портов). Машины кладут
## и берут жидкость в своём тике (insert / extract). Когда сеть пуста, жидкость сбрасывается.
## При изменении построек сети пересобираются (лениво, в начале тика): объём старой сети делится
## по узлам пропорционально вместимости и собирается в новые сети; если при слиянии встретились
## разные жидкости, остаётся та, которой больше.
## В сохранение пишется объём каждой сети по её наименьшему ключу узла — после загрузки сети
## собираются заново из построек, и объёмы совпадают точно.

## Вместимость порта машины (чтобы машины вплотную работали без труб).
const PORT_CAPACITY := 20.0

## Порт машины: сторона в мире, допустимая жидкость (null — любая), группа (порты одной группы — одна сеть).
class Port:
	var side: int = 0
	var fluid: FluidDef
	var group: int = 0

	func _init(p_side: int, p_fluid: FluidDef, p_group: int) -> void:
		side = p_side
		fluid = p_fluid
		group = p_group


class FluidNetwork:
	## Индекс FluidDef (-1 — пусто).
	var fluid: int = -1
	var amount: float = 0.0
	var capacity: float = 0.0
	## Наименьший ключ узла — постоянное имя сети для сохранения.
	var key: int = 0
	var nodes := PackedInt64Array()

	func get_free(p_fluid: int) -> float:
		if fluid >= 0 and fluid != p_fluid:
			return 0.0
		return maxf(capacity - amount, 0.0)

	## Положить до value единиц жидкости p_fluid. Возвращает, сколько легло.
	func insert(p_fluid: int, value: float) -> float:
		if value <= 0.0 or (fluid >= 0 and fluid != p_fluid):
			return 0.0
		var put := minf(value, maxf(capacity - amount, 0.0))
		if put > 0.0:
			fluid = p_fluid
			amount += put
		return put

	## Взять до value единиц жидкости p_fluid. Возвращает, сколько взято.
	func extract(p_fluid: int, value: float) -> float:
		if value <= 0.0 or fluid != p_fluid:
			return 0.0
		var taken := minf(value, amount)
		amount -= taken
		if amount <= 0.000001:
			amount = 0.0
			fluid = -1
		return taken


var networks: Array[FluidNetwork] = []
## Трубы мира по id (для отрисовки).
var pipes: Dictionary[int, Building] = {}

var _world: GameWorld
var _dirty: bool = true
## Ключ узла → сеть.
var _node_net: Dictionary[int, FluidNetwork] = {}


func _init(world: GameWorld) -> void:
	_world = world


func dispose() -> void:
	_world = null
	networks.clear()
	pipes.clear()
	_node_net.clear()


func mark_dirty() -> void:
	_dirty = true


func is_dirty() -> bool:
	return _dirty


func update() -> void:
	if _dirty:
		rebuild()


static func pipe_key(building_id: int) -> int:
	return building_id * 8


static func port_key(building_id: int, side: int) -> int:
	return building_id * 8 + side + 1


## Сеть порта машины на стороне side (null — порт ни к чему не подключён).
func get_port_network(building: Building, side: int) -> FluidNetwork:
	if _dirty:
		rebuild()
	return _node_net.get(port_key(building.id, side))


func get_pipe_network(pipe: Building) -> FluidNetwork:
	if _dirty:
		rebuild()
	return _node_net.get(pipe_key(pipe.id))


func register_pipe(pipe: Building) -> void:
	pipes[pipe.id] = pipe
	_dirty = true


func unregister_pipe(pipe: Building) -> void:
	pipes.erase(pipe.id)
	_dirty = true


## Соединяется ли труба с соседом по стороне side (для отрисовки стыков).
func pipe_connects(pipe: Building, side: int) -> bool:
	if not (pipe as Pipe).connects_side(side):
		return false
	var other := _world.buildings.get_at(pipe.origin + GameConst.dir_vector(side))
	if other == null:
		return false
	if other is Pipe:
		return (other as Pipe).connects_side((side + 2) % 4)
	for port in other.get_fluid_ports():
		if port.side == (side + 2) % 4:
			return true
	return false


# --- Пересборка ---

func rebuild() -> void:
	_dirty = false
	# Объём старых сетей — в доли узлов.
	var shares: Dictionary[int, float] = {}
	var share_fluid: Dictionary[int, int] = {}
	for net in networks:
		if net.amount <= 0.0 or net.capacity <= 0.0:
			continue
		for key in net.nodes:
			shares[key] = net.amount * _node_capacity(key) / net.capacity
			share_fluid[key] = net.fluid
	networks.clear()
	_node_net.clear()

	var parent: Dictionary[int, int] = {}
	var ids := pipes.keys()
	ids.sort()
	for id in ids:
		parent[pipe_key(id)] = pipe_key(id)
	var machines: Array[Building] = []
	for b in _world.buildings.get_all():
		if b is Pipe:
			continue
		var ports := b.get_fluid_ports()
		if ports.is_empty():
			continue
		machines.append(b)
		for port in ports:
			parent[port_key(b.id, port.side)] = port_key(b.id, port.side)
	# Трубы между собой и подземные пары.
	for id in ids:
		var pipe := pipes[id] as Pipe
		for side in [0, 1]:
			var other := _world.buildings.get_at(pipe.origin + GameConst.dir_vector(side))
			if other is Pipe and pipe.connects_side(side) and (other as Pipe).connects_side((side + 2) % 4):
				_union(parent, pipe_key(id), pipe_key(other.id))
		if pipe is UndergroundPipe:
			var partner := (pipe as UndergroundPipe).get_linked_partner()
			if partner != null:
				_union(parent, pipe_key(id), pipe_key(partner.id))
	# Порты машин: с трубами и портами соседей по стороне; порты одной группы.
	for b in machines:
		var ports := b.get_fluid_ports()
		for port in ports:
			var key := port_key(b.id, port.side)
			for group_port in ports:
				if group_port != port and group_port.group == port.group:
					_union(parent, key, port_key(b.id, group_port.side))
			for tile in _side_tiles(b, port.side):
				var other := _world.buildings.get_at(tile)
				if other == null or other == b:
					continue
				if other is Pipe:
					if (other as Pipe).connects_side((port.side + 2) % 4):
						_union(parent, key, pipe_key(other.id))
				else:
					for other_port in other.get_fluid_ports():
						if other_port.side == (port.side + 2) % 4 and _compatible(port, other_port):
							_union(parent, key, port_key(other.id, other_port.side))

	var keys := parent.keys()
	keys.sort()
	var by_root: Dictionary[int, FluidNetwork] = {}
	var best_share: Dictionary[FluidNetwork, Dictionary] = {}
	for key in keys:
		var root := _find(parent, key)
		var net: FluidNetwork = by_root.get(root)
		if net == null:
			net = FluidNetwork.new()
			net.key = key
			by_root[root] = net
			networks.append(net)
			best_share[net] = {}
		net.nodes.append(key)
		net.capacity += _node_capacity(key)
		_node_net[key] = net
		if shares.has(key):
			var per_fluid: Dictionary = best_share[net]
			per_fluid[share_fluid[key]] = float(per_fluid.get(share_fluid[key], 0.0)) + shares[key]
	for net in networks:
		var per_fluid: Dictionary = best_share[net]
		var fluids := per_fluid.keys()
		fluids.sort()
		for f in fluids:
			if float(per_fluid[f]) > net.amount:
				net.amount = minf(float(per_fluid[f]), net.capacity)
				net.fluid = f


func _node_capacity(key: int) -> float:
	if key % 8 == 0:
		var pipe: Building = pipes.get(key / 8)
		return pipe.get_fluid_capacity() if pipe != null else 0.0
	return PORT_CAPACITY


func _compatible(a: Port, b: Port) -> bool:
	return a.fluid == null or b.fluid == null or a.fluid == b.fluid


## Тайлы снаружи здания вдоль стороны side.
func _side_tiles(b: Building, side: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var rect := b.get_rect()
	match side:
		GameConst.Dir.RIGHT:
			for y in range(rect.position.y, rect.end.y):
				result.append(Vector2i(rect.end.x, y))
		GameConst.Dir.LEFT:
			for y in range(rect.position.y, rect.end.y):
				result.append(Vector2i(rect.position.x - 1, y))
		GameConst.Dir.DOWN:
			for x in range(rect.position.x, rect.end.x):
				result.append(Vector2i(x, rect.end.y))
		_:
			for x in range(rect.position.x, rect.end.x):
				result.append(Vector2i(x, rect.position.y - 1))
	return result


func _find(parent: Dictionary[int, int], key: int) -> int:
	var root := key
	while parent[root] != root:
		root = parent[root]
	var node := key
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


# --- Сохранение ---

func save_data() -> Dictionary:
	if _dirty:
		rebuild()
	var keys := PackedInt64Array()
	var fluids := PackedInt32Array()
	var amounts := PackedFloat64Array()
	for net in networks:
		if net.amount > 0.0:
			keys.append(net.key)
			fluids.append(net.fluid)
			amounts.append(net.amount)
	return {"keys": keys, "fluids": fluids, "amounts": amounts}


## fluid_map — сохранённый индекс жидкости → текущий (пусто — без переноса).
func load_data(data: Dictionary, fluid_map: PackedInt32Array) -> void:
	rebuild()
	for net in networks:
		net.amount = 0.0
		net.fluid = -1
	var by_key: Dictionary[int, FluidNetwork] = {}
	for net in networks:
		by_key[net.key] = net
	var keys: PackedInt64Array = data.get("keys", PackedInt64Array())
	var fluids: PackedInt32Array = data.get("fluids", PackedInt32Array())
	var amounts: PackedFloat64Array = data.get("amounts", PackedFloat64Array())
	for i in mini(keys.size(), mini(fluids.size(), amounts.size())):
		var net: FluidNetwork = by_key.get(keys[i])
		var f := fluids[i]
		if fluid_map.size() > 0:
			f = fluid_map[f] if f >= 0 and f < fluid_map.size() else -1
		if net == null or f < 0:
			continue
		net.fluid = f
		net.amount = minf(amounts[i], net.capacity)
