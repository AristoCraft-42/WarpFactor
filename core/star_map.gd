class_name StarMap
extends RefCounted
## Звёздная карта забега: граф планет по шагам (как в FTL / Slay the Spire).
## Шаг 0 — стартовая планета; в каждом следующем шаге 2–3 планеты, связи ведут только вперёд.
## Карта детерминирована от сида забега и достраивается на visible_depth шагов вперёд от текущей
## планеты. Позже исследования ограничат, что игроку видно заранее.


class StarNode:
	var id: int = 0
	## Номер шага (0 — старт).
	var depth: int = 0
	## Позиция в шаге (0..count-1) — для раскладки на экране.
	var slot: int = 0
	var slots_in_step: int = 1
	var planet_seed: int = 0
	var type: PlanetTypeDef
	## Размер карты в тайлах.
	var size: Vector2i = Vector2i.ZERO
	## Индексы руд (OreDef.index), которые есть на планете.
	var ores: PackedInt32Array = PackedInt32Array()
	## id узлов следующего шага.
	var links: PackedInt32Array = PackedInt32Array()
	## Код планеты для названия (например, «KX-417»).
	var code: String = ""
	var visited: bool = false


var nodes: Array[StarNode] = []
var current_id: int = 0
var run_seed: int = 0

## Сколько шагов карты открыли исследования сверх базовой дальности (ставит забег).
var bonus_depth: int = 0
## Что открыла разведка (ставит забег): 0 — ничего, 1 — тип планеты и выбор цели, 2 — ещё и ресурсы.
var scan_level: int = 0

var _run_def: RunDef
var _types: Array[PlanetTypeDef] = []
var _steps: Array[PackedInt32Array] = []


func _init(p_run_seed: int, run_def: RunDef, types: Array[PlanetTypeDef]) -> void:
	run_seed = p_run_seed
	_run_def = run_def
	_types = types
	var first_type := run_def.first_planet_type if run_def.first_planet_type != null else (types[0] if not types.is_empty() else null)
	var start := _make_node(0, 0, 1, first_type)
	start.visited = true
	_steps.append(PackedInt32Array([start.id]))
	ensure_depth(get_visible_depth())


## На сколько шагов вперёд видна карта: из данных забега плюс исследования «Дальний обзор».
func get_visible_depth() -> int:
	# Без разведки видно только следующий шаг: куда несёт, то и есть.
	return (_run_def.visible_depth + bonus_depth) if scan_level > 0 else 1


## Можно ли выбирать, куда лететь. До разведки выбора нет — цель одна.
func can_choose() -> bool:
	return scan_level > 0


## Цель по умолчанию, когда выбора ещё нет (первый сосед по порядку — одинаково у всех игроков).
func get_default_next() -> int:
	var next := get_next()
	return next[0].id if not next.is_empty() else -1


func get_current() -> StarNode:
	return nodes[current_id]


func get_node(id: int) -> StarNode:
	return nodes[id] if id >= 0 and id < nodes.size() else null


## Узлы, в которые можно телепортироваться из текущего.
func get_next() -> Array[StarNode]:
	var result: Array[StarNode] = []
	for id in get_current().links:
		result.append(nodes[id])
	return result


func can_travel_to(id: int) -> bool:
	# Без разведки лететь можно только к цели по умолчанию: выбирать ещё нечем.
	if not can_choose() and id != get_default_next():
		return false
	return get_current().links.has(id)


## Узлы, видимые игроку: от текущего шага на visible_depth вперёд.
func get_visible_nodes() -> Array[StarNode]:
	var result: Array[StarNode] = []
	var max_depth := get_current().depth + get_visible_depth()
	for node in nodes:
		if node.depth <= max_depth:
			result.append(node)
	return result


func get_step_count() -> int:
	return _steps.size()


## Перейти на планету id (после телепорта) и достроить карту вперёд.
func move_to(id: int) -> void:
	current_id = id
	nodes[id].visited = true
	ensure_depth(nodes[id].depth + get_visible_depth())


func save_data() -> Dictionary:
	var visited := PackedInt32Array()
	for node in nodes:
		if node.visited:
			visited.append(node.id)
	return {"current": current_id, "visited": visited, "steps": _steps.size()}


## Восстановить: карта детерминирована от сида, поэтому хватает числа шагов, пройденных узлов и текущего.
func load_data(data: Dictionary) -> void:
	ensure_depth(int(data.get("steps", _steps.size())) - 1)
	for node in nodes:
		node.visited = false
	for id in (data.get("visited", PackedInt32Array()) as PackedInt32Array):
		if id >= 0 and id < nodes.size():
			nodes[id].visited = true
	current_id = clampi(int(data.get("current", 0)), 0, nodes.size() - 1)
	nodes[current_id].visited = true
	ensure_depth(nodes[current_id].depth + get_visible_depth())


## Достроить шаги до depth включительно.
func ensure_depth(depth: int) -> void:
	while _steps.size() <= depth:
		_add_step()


func _add_step() -> void:
	var depth := _steps.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, depth, "step"])
	var count := rng.randi_range(_run_def.min_nodes_per_step, _run_def.max_nodes_per_step)
	var ids := PackedInt32Array()
	var safe_count := 0
	for slot in count:
		var type := _pick_type(rng)
		# Не делаем весь шаг пустошами: хотя бы одна планета с ресурсами.
		if type.safe:
			safe_count += 1
			if safe_count == count:
				type = _first_unsafe_type()
		ids.append(_make_node(depth, slot, count, type).id)
	_steps.append(ids)
	_link(_steps[depth - 1], ids, rng)


## Связи из предыдущего шага: каждый узел ведёт в ближайший по высоте и иногда в соседний;
## у каждого узла нового шага есть хотя бы один вход.
func _link(prev: PackedInt32Array, next: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var incoming := PackedInt32Array()
	incoming.resize(next.size())
	incoming.fill(0)
	for i in prev.size():
		var node := nodes[prev[i]]
		var j := 0
		if prev.size() > 1:
			j = roundi(float(i) * (next.size() - 1) / (prev.size() - 1))
		else:
			j = rng.randi_range(0, next.size() - 1)
		_add_link(node, next[j], incoming, j)
		var neighbor := j + (1 if rng.randf() < 0.5 else -1)
		if neighbor >= 0 and neighbor < next.size() and rng.randf() < 0.55:
			_add_link(node, next[neighbor], incoming, neighbor)
		if prev.size() == 1:
			# Единственный узел шага ведёт во все планеты следующего шага.
			for k in next.size():
				_add_link(node, next[k], incoming, k)
	for j in next.size():
		if incoming[j] == 0:
			var i := roundi(float(j) * (prev.size() - 1) / maxi(next.size() - 1, 1))
			_add_link(nodes[prev[clampi(i, 0, prev.size() - 1)]], next[j], incoming, j)


func _add_link(node: StarNode, target: int, incoming: PackedInt32Array, j: int) -> void:
	if node.links.has(target):
		return
	node.links.append(target)
	incoming[j] += 1


func _make_node(depth: int, slot: int, slots: int, type: PlanetTypeDef) -> StarNode:
	var node := StarNode.new()
	node.id = nodes.size()
	node.depth = depth
	node.slot = slot
	node.slots_in_step = slots
	node.planet_seed = hash([run_seed, depth, slot, "planet"]) & 0x7fffffff
	node.type = type
	var rng := RandomNumberGenerator.new()
	rng.seed = node.planet_seed
	node.size = Vector2i(rng.randi_range(type.min_size.x, type.max_size.x), rng.randi_range(type.min_size.y, type.max_size.y))
	for i in type.ore_ids.size():
		var ore := Registry.get_ore(type.ore_ids[i])
		var chance := type.ore_chances[i] if i < type.ore_chances.size() else 1.0
		# На стартовой планете есть все руды её типа: ранней игре нужны и малахит, и вода.
		var roll := rng.randf()
		if ore != null and (depth == 0 or roll < chance):
			node.ores.append(ore.index)
	const LETTERS := "ABCDEFGHKLMNPRSTVXZ"
	node.code = "%s%s-%03d" % [LETTERS[rng.randi_range(0, LETTERS.length() - 1)], LETTERS[rng.randi_range(0, LETTERS.length() - 1)], rng.randi_range(1, 999)]
	nodes.append(node)
	return node


func _pick_type(rng: RandomNumberGenerator) -> PlanetTypeDef:
	var total := 0.0
	for t in _types:
		total += t.weight
	var roll := rng.randf() * total
	for t in _types:
		roll -= t.weight
		if roll <= 0.0:
			return t
	return _types[_types.size() - 1]


func _first_unsafe_type() -> PlanetTypeDef:
	for t in _types:
		if not t.safe:
			return t
	return _types[0]
