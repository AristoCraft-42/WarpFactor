class_name FlowField
extends RefCounted
## Поле потоков наземных врагов: для каждого тайла — цена пути до центрального шлюза.
##
## Цена входа в тайл: скала непроходима, пустая земля — 1 (у скал — 2, чтобы враги не тёрлись о камни),
## проходимые постройки (ленты, логистика) — как земля, твёрдые — «с ценой» по прочности
## (BuildingDef.get_path_cost): враг обходит постройку, если обход дешевле, иначе ломает её.
##
## Поле считается алгоритмом Дейкстры с корзинами (цены — небольшие целые) не за один тик,
## а порциями по NODES_PER_TICK узлов: пока идёт пересчёт, враги пользуются прежним полем,
## по окончании поля меняются местами и растёт version. Постройка или снос твёрдого здания
## помечает поле грязным; пересчёт, начатый до изменения, доходит до конца и запускается снова.
## Всё состояние пересчёта сохраняется — после загрузки враги двигаются так же, как без неё.

const INF := 0x3fffffff
## Наибольшая цена тайла (и число корзин минус один).
const MAX_COST := 250
const NODES_PER_TICK := 3000
## Значения маски blocked.
const OPEN := 0
const ROCK := 1
const SOLID := 2

var width: int = 0
var height: int = 0
## Активное поле: цена пути до шлюза (INF — не дойти).
var dist := PackedInt32Array()
## Растёт при каждой замене поля — враги пересчитывают следующий шаг.
var version: int = 0
## Цена входа в тайл (0 — непроходимо).
var cost := PackedByteArray()
## OPEN / ROCK / SOLID — войти в тайл нельзя, если не OPEN.
var blocked := PackedByteArray()
## Сколько раз поле пересчитано и за сколько тиков последний раз (для отладки).
var computed_count: int = 0
var last_compute_ticks: int = 0

var _world: GameWorld
## Цена пустой земли по тайлу: 0 — скала, 1 — открыто, 2 — рядом скала.
var _ground := PackedByteArray()
var _dirty: bool = true
var _computing: bool = false
var _work := PackedInt32Array()
var _cur_dist: int = 0
var _pending: int = 0
var _ticks_spent: int = 0
## Корзины Дейкстры — односвязные списки в общем пуле записей.
var _head := PackedInt32Array()
var _entry_node := PackedInt32Array()
var _entry_next := PackedInt32Array()
var _free_entry: int = -1


func _init(world: GameWorld) -> void:
	_world = world
	var grid := world.grid
	width = grid.width
	height = grid.height
	var n := width * height
	dist.resize(n)
	dist.fill(INF)
	_work.resize(n)
	_work.fill(INF)
	cost.resize(n)
	blocked.resize(n)
	_ground.resize(n)
	_head.resize(MAX_COST + 1)
	_head.fill(-1)
	_build_ground()
	for b in world.buildings.get_all():
		_apply_building(b, true)
	world.buildings.building_added.connect(_on_building_added)
	world.buildings.building_removed.connect(_on_building_removed)


func dispose() -> void:
	if _world != null and _world.buildings != null:
		if _world.buildings.building_added.is_connected(_on_building_added):
			_world.buildings.building_added.disconnect(_on_building_added)
		if _world.buildings.building_removed.is_connected(_on_building_removed):
			_world.buildings.building_removed.disconnect(_on_building_removed)
	_world = null


func is_dirty() -> bool:
	return _dirty


func is_computing() -> bool:
	return _computing


func mark_dirty() -> void:
	_dirty = true


## Шаг пересчёта в тике симуляции.
func update() -> void:
	if not _computing:
		if not _dirty:
			return
		_begin()
	_ticks_spent += 1
	if _run(NODES_PER_TICK):
		_finish()


## Пересчитать сразу целиком (создание планеты, тесты).
func compute_now() -> void:
	if not _computing:
		_begin()
	_run(INF)
	_finish()


func get_dist(tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0 or tile.x >= width or tile.y >= height:
		return INF
	return dist[tile.y * width + tile.x]


func is_blocked_index(index: int) -> bool:
	return blocked[index] != OPEN


## Следующий тайл пути из tile (индекс) — сосед с наименьшей ценой; -1, если ближе к шлюзу не стать.
## По диагонали — только если оба боковых тайла и сам диагональный свободны (без срезания углов).
func best_neighbor(tile: int) -> int:
	var x := tile % width
	var y := tile / width
	var best := -1
	var best_d := dist[tile]
	# Сначала прямые соседи: при равной цене шаг по прямой.
	if x > 0 and dist[tile - 1] < best_d:
		best = tile - 1
		best_d = dist[best]
	if x < width - 1 and dist[tile + 1] < best_d:
		best = tile + 1
		best_d = dist[best]
	if y > 0 and dist[tile - width] < best_d:
		best = tile - width
		best_d = dist[best]
	if y < height - 1 and dist[tile + width] < best_d:
		best = tile + width
		best_d = dist[best]
	for oy in [-1, 1]:
		var ny: int = y + oy
		if ny < 0 or ny >= height:
			continue
		for ox in [-1, 1]:
			var nx: int = x + ox
			if nx < 0 or nx >= width:
				continue
			var m := ny * width + nx
			if dist[m] >= best_d or blocked[m] != OPEN:
				continue
			if blocked[y * width + nx] != OPEN or blocked[ny * width + x] != OPEN:
				continue
			best = m
			best_d = dist[m]
	return best


# --- Пересчёт ---

func _begin() -> void:
	_dirty = false
	_computing = true
	_ticks_spent = 0
	_work.fill(INF)
	_head.fill(-1)
	_entry_node.clear()
	_entry_next.clear()
	_free_entry = -1
	_pending = 0
	_cur_dist = 0
	var gate := _world.gateway if _world != null else null
	if gate == null or gate.world == null:
		return
	var rect := gate.get_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x >= 0 and y >= 0 and x < width and y < height:
				var i := y * width + x
				_work[i] = 0
				_push(i, 0)


## Обработать до budget записей. true — пересчёт закончен.
func _run(budget: int) -> bool:
	var nb := MAX_COST + 1
	var w := width
	var h := height
	while _pending > 0:
		var bi := _cur_dist % nb
		var e := _head[bi]
		if e < 0:
			_cur_dist += 1
			continue
		if budget <= 0:
			return false
		budget -= 1
		_head[bi] = _entry_next[e]
		var node := _entry_node[e]
		_entry_next[e] = _free_entry
		_free_entry = e
		_pending -= 1
		var d := _cur_dist
		if _work[node] != d:
			continue
		var x := node % w
		if x > 0:
			_relax(node - 1, d)
		if x < w - 1:
			_relax(node + 1, d)
		if node >= w:
			_relax(node - w, d)
		if node < (h - 1) * w:
			_relax(node + w, d)
	return true


func _relax(m: int, d: int) -> void:
	var c := cost[m]
	if c == 0:
		return
	var nd := d + c
	if nd < _work[m]:
		_work[m] = nd
		_push(m, nd)


func _push(node: int, d: int) -> void:
	var e := _free_entry
	if e >= 0:
		_free_entry = _entry_next[e]
	else:
		e = _entry_node.size()
		_entry_node.append(0)
		_entry_next.append(-1)
	var bi := d % (MAX_COST + 1)
	_entry_node[e] = node
	_entry_next[e] = _head[bi]
	_head[bi] = e
	_pending += 1


func _finish() -> void:
	_computing = false
	var old := dist
	dist = _work
	_work = old
	version += 1
	computed_count += 1
	last_compute_ticks = _ticks_spent


# --- Цены тайлов ---

func _build_ground() -> void:
	var grid := _world.grid
	var floors := grid.floors
	var buildable := Registry.floor_buildable
	for y in height:
		for x in width:
			var i := y * width + x
			if buildable[floors[i]] == 0:
				_ground[i] = 0
				continue
			var near_rock := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < width and ny < height and buildable[floors[ny * width + nx]] == 0:
						near_rock = true
			_ground[i] = 2 if near_rock else 1
	for i in width * height:
		cost[i] = _ground[i]
		blocked[i] = OPEN if _ground[i] > 0 else ROCK


func _apply_building(b: Building, placed: bool) -> void:
	var rect := b.get_rect()
	var solid := b.def.solid
	var extra := b.def.get_path_cost() - 1
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			var i := y * width + x
			var ground := _ground[i]
			if ground == 0:
				continue
			if placed and solid:
				cost[i] = mini(ground + extra, MAX_COST)
				blocked[i] = SOLID
			else:
				cost[i] = ground
				blocked[i] = OPEN


func _on_building_added(b: Building) -> void:
	_apply_building(b, true)
	if b.def.solid:
		_dirty = true


func _on_building_removed(b: Building) -> void:
	_apply_building(b, false)
	if b.def.solid:
		_dirty = true


# --- Сохранение ---

func save_data() -> Dictionary:
	return {"dist": dist.duplicate(), "version": version, "dirty": _dirty, "computing": _computing,
		"work": _work.duplicate() if _computing else PackedInt32Array(), "cur": _cur_dist, "pending": _pending,
		"head": _head.duplicate(), "entry_node": _entry_node.duplicate(), "entry_next": _entry_next.duplicate(),
		"free": _free_entry, "spent": _ticks_spent, "computed": computed_count, "last_ticks": last_compute_ticks}


## Восстановить после того, как здания мира уже стоят (цены тайлов строятся по ним заново).
func load_data(data: Dictionary) -> void:
	var n := width * height
	var saved_dist: PackedInt32Array = data.get("dist", PackedInt32Array())
	if saved_dist.size() != n:
		_dirty = true
		compute_now()
		return
	dist = saved_dist.duplicate()
	version = int(data.get("version", 0))
	_dirty = bool(data.get("dirty", false))
	_computing = bool(data.get("computing", false))
	_cur_dist = int(data.get("cur", 0))
	_pending = int(data.get("pending", 0))
	_head = (data.get("head", PackedInt32Array()) as PackedInt32Array).duplicate()
	_entry_node = (data.get("entry_node", PackedInt32Array()) as PackedInt32Array).duplicate()
	_entry_next = (data.get("entry_next", PackedInt32Array()) as PackedInt32Array).duplicate()
	_free_entry = int(data.get("free", -1))
	_ticks_spent = int(data.get("spent", 0))
	computed_count = int(data.get("computed", 0))
	last_compute_ticks = int(data.get("last_ticks", 0))
	var work: PackedInt32Array = data.get("work", PackedInt32Array())
	if _computing and (work.size() != n or _head.size() != MAX_COST + 1):
		# Повреждённое состояние пересчёта — начинаем его заново.
		_computing = false
		_dirty = true
		_head.resize(MAX_COST + 1)
		_head.fill(-1)
		return
	if _computing:
		_work = work.duplicate()
	else:
		_work.resize(n)
