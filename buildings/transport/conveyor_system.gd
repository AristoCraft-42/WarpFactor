class_name ConveyorSystem
extends RefCounted
## Симуляция всех лент: модель «слот + прогресс» (как в Mindustry), данные — структура массивов (SoA).
##
## На ленте до CAP предметов, у каждого — тип и прогресс вдоль тайла в целых единицах
## (0..UNITS, UNITS — выходной край). Целые числа исключают накопление ошибок float:
## поток и засыпание лент детерминированы. Слоты упорядочены от переднего предмета (индекс 0)
## к заднему; новые предметы всегда встают в хвост. Между предметами не меньше SPACE.
## Лента обновляется в тике, только пока бодрствует: пустая засыпает до прихода предмета,
## заблокированная — до освобождения места у получателя.
##
## Индексы лент плотные и меняются при удалении (swap-remove), поэтому ссылки между лентами
## хранятся по id зданий и разрешаются через _index_of.

const CAP := 3
## Единиц прогресса на тайл.
const UNITS := 1200
## Минимальный зазор между предметами (0.4 тайла).
const SPACE := 480
## Зазор в долях тайла (для характеристик в интерфейсе).
const ITEM_SPACE := 0.4
## Позиция вставки сбоку и минимум заднего предмета для такой вставки.
const SIDE_INSERT := 600
const SIDE_ACCEPT_MIN := 840
## «Прогресс заднего предмета» пустой ленты.
const EMPTY_MIN := UNITS

var count: int = 0
## Данные на ленту
var bids: PackedInt32Array = PackedInt32Array()
var counts: PackedByteArray = PackedByteArray()
var mins: PackedInt32Array = PackedInt32Array()
var steps: PackedInt32Array = PackedInt32Array()
var dirs: PackedByteArray = PackedByteArray()
var tiles_x: PackedInt32Array = PackedInt32Array()
var tiles_y: PackedInt32Array = PackedInt32Array()
## Цель: id следующей ленты (0 — нет) и вход в неё (0 — сзади, 1 — сбоку), либо id другого здания.
var next_conv: PackedInt32Array = PackedInt32Array()
var next_side: PackedByteArray = PackedByteArray()
var next_bid: PackedInt32Array = PackedInt32Array()
var fresh_tick: PackedInt32Array = PackedInt32Array()
var awake_flags: PackedByteArray = PackedByteArray()
var has_waiters: PackedByteArray = PackedByteArray()
## Данные на слот (шаг CAP)
var items: PackedInt32Array = PackedInt32Array()
var prog: PackedInt32Array = PackedInt32Array()
## Сдвиг прогресса за последний тик — для визуальной интерполяции.
var dprog: PackedInt32Array = PackedInt32Array()
## Боковое смещение (−1..1) предмета, вставленного сбоку; плавно уходит в 0. Только для отрисовки.
var lat: PackedFloat32Array = PackedFloat32Array()

## Сколько лент обновилось на последнем тике.
var last_updated: int = 0

var _index_of: PackedInt32Array = PackedInt32Array()
var _awake: PackedInt32Array = PackedInt32Array()
var _sim: Simulation
var _manager: BuildingManager


func _init(sim: Simulation, manager: BuildingManager) -> void:
	_sim = sim
	_manager = manager


func dispose() -> void:
	_sim = null
	_manager = null


static func step_for(def: BuildingDef) -> int:
	if def is ConveyorDef:
		return maxi(1, roundi((def as ConveyorDef).tiles_per_second * UNITS / GameConst.TICK_RATE))
	return 96


func index_of(building_id: int) -> int:
	return _index_of[building_id] if building_id < _index_of.size() else -1


func get_awake_count() -> int:
	return _awake.size()


func get_item_count() -> int:
	var total := 0
	for c in count:
		total += counts[c]
	return total


# --- Регистрация ---

func add(conveyor: Conveyor) -> void:
	var c := count
	count += 1
	bids.append(conveyor.id)
	counts.append(0)
	mins.append(EMPTY_MIN)
	steps.append(step_for(conveyor.def))
	dirs.append(conveyor.rotation)
	tiles_x.append(conveyor.origin.x)
	tiles_y.append(conveyor.origin.y)
	next_conv.append(0)
	next_side.append(0)
	next_bid.append(0)
	fresh_tick.append(-1)
	awake_flags.append(0)
	has_waiters.append(0)
	items.resize(count * CAP)
	prog.resize(count * CAP)
	dprog.resize(count * CAP)
	lat.resize(count * CAP)
	for s in CAP:
		items[c * CAP + s] = 0
		prog[c * CAP + s] = 0
		dprog[c * CAP + s] = 0
		lat[c * CAP + s] = 0.0
	if conveyor.id >= _index_of.size():
		var old_size := _index_of.size()
		_index_of.resize(maxi(conveyor.id + 1, old_size * 2))
		for i in range(old_size, _index_of.size()):
			_index_of[i] = -1
	_index_of[conveyor.id] = c


func remove(conveyor: Conveyor) -> void:
	var c := index_of(conveyor.id)
	if c < 0:
		return
	var last := count - 1
	# Убираем удаляемую ленту из списка бодрствующих, последнюю переименовываем в c.
	var rebuilt := PackedInt32Array()
	for a in _awake:
		if a == c:
			continue
		rebuilt.append(c if a == last else a)
	_awake = rebuilt
	if c != last:
		_copy(last, c)
		_index_of[bids[c]] = c
	_index_of[conveyor.id] = -1
	count = last
	bids.resize(count)
	next_conv.resize(count)
	fresh_tick.resize(count)
	tiles_x.resize(count)
	tiles_y.resize(count)
	counts.resize(count)
	dirs.resize(count)
	next_side.resize(count)
	awake_flags.resize(count)
	has_waiters.resize(count)
	mins.resize(count)
	steps.resize(count)
	items.resize(count * CAP)
	prog.resize(count * CAP)
	dprog.resize(count * CAP)
	lat.resize(count * CAP)


func set_direction(conveyor: Conveyor) -> void:
	var c := index_of(conveyor.id)
	if c >= 0:
		dirs[c] = conveyor.rotation


## Пересчитать, куда лента отдаёт предметы.
func relink(conveyor: Conveyor) -> void:
	var c := index_of(conveyor.id)
	if c < 0:
		return
	next_conv[c] = 0
	next_side[c] = 0
	next_bid[c] = 0
	var d := dirs[c]
	var target := _manager.get_at(conveyor.origin + GameConst.dir_vector(d))
	if target == null:
		return
	var t := index_of(target.id)
	if t >= 0:
		var td := dirs[t]
		if posmod(td - d, 4) == 2:
			return # ленты смотрят друг на друга — передачи нет
		next_conv[c] = target.id
		next_side[c] = 0 if td == d else 1
	else:
		next_bid[c] = target.id


func wake_building(building_id: int) -> void:
	var c := index_of(building_id)
	if c >= 0:
		_wake(c)


func set_has_waiters(building_id: int, value: bool) -> void:
	var c := index_of(building_id)
	if c >= 0:
		has_waiters[c] = 1 if value else 0


# --- Приём от других зданий ---

func accept_from(conveyor: Conveyor, source: Building) -> bool:
	var c := index_of(conveyor.id)
	if c < 0 or counts[c] >= CAP:
		return false
	if source.id == next_conv[c] or source.id == next_bid[c]:
		return false
	var side := conveyor.side_of(source)
	if side < 0:
		return false
	var d := dirs[c]
	if side == d:
		return false
	if side == (d + 2) % 4:
		return mins[c] >= SPACE
	return mins[c] > SIDE_ACCEPT_MIN


func insert_from(conveyor: Conveyor, source: Building, item: int) -> void:
	var c := index_of(conveyor.id)
	if c < 0:
		return
	var d := dirs[c]
	var side := conveyor.side_of(source)
	if side == (d + 2) % 4:
		_insert(c, item, 0, 0.0, 0)
	else:
		_insert(c, item, SIDE_INSERT, 1.0 if side == (d + 1) % 4 else -1.0, 0)


## Предметы ленты от переднего к заднему: {"items", "prog"}.
func export_items(conveyor: Conveyor) -> Dictionary:
	var c := index_of(conveyor.id)
	# Упакованные массивы в словаре хранятся по значению: сначала заполняем локальные.
	var out_items := PackedInt32Array()
	var out_prog := PackedInt32Array()
	if c >= 0:
		for s in counts[c]:
			out_items.append(items[c * CAP + s])
			out_prog.append(prog[c * CAP + s])
	return {"items": out_items, "prog": out_prog}


## Восстановить предметы ленты из export_items (лента должна быть пустой).
func import_items(conveyor: Conveyor, state: Dictionary) -> void:
	var c := index_of(conveyor.id)
	if c < 0:
		return
	var src_items: PackedInt32Array = state.get("items", PackedInt32Array())
	var src_prog: PackedInt32Array = state.get("prog", PackedInt32Array())
	var n := mini(mini(src_items.size(), src_prog.size()), CAP)
	for s in n:
		var k := c * CAP + s
		items[k] = src_items[s]
		prog[k] = clampi(src_prog[s], 0, UNITS)
		dprog[k] = 0
		lat[k] = 0.0
	counts[c] = n
	mins[c] = prog[c * CAP + n - 1] if n > 0 else EMPTY_MIN
	if n > 0:
		_wake(c)


func collect(conveyor: Conveyor, out: PackedInt32Array) -> void:
	var c := index_of(conveyor.id)
	if c < 0:
		return
	for s in counts[c]:
		out[items[c * CAP + s]] += 1


# --- Тик ---

func update(tick: int) -> void:
	last_updated = _awake.size()
	if _awake.is_empty():
		return
	var current := _awake
	_awake = PackedInt32Array()
	for c in current:
		awake_flags[c] = 0

	# Локальные ссылки на массивы: в Godot 4.7 packed-массивы разделяются по ссылке, копий нет.
	var a_counts := counts
	var a_items := items
	var a_prog := prog
	var a_dprog := dprog
	var a_lat := lat
	var a_mins := mins
	var a_steps := steps
	var a_dirs := dirs
	var a_next_conv := next_conv
	var a_next_side := next_side
	var a_next_bid := next_bid
	var a_fresh := fresh_tick
	var a_waiters := has_waiters
	var a_awake_flags := awake_flags
	var next_awake := _awake
	var index_map := _index_of
	var index_map_size := index_map.size()

	for c in current:
		var n := a_counts[c]
		if n == 0:
			continue
		var base := c * CAP
		var step := a_steps[c]
		var is_fresh := a_fresh[c] == tick
		var nc := a_next_conv[c]
		var ni := -1
		var limit := UNITS
		if nc != 0:
			ni = index_map[nc] if nc < index_map_size else -1
			if ni >= 0 and a_next_side[c] == 0:
				var gap := SPACE - a_mins[ni]
				if gap > 0:
					limit = UNITS - gap

		var moved := is_fresh
		var overshoot := 0
		var front_moved := 0
		var lat_step := float(step) / UNITS * 2.0
		for i in n:
			if is_fresh and i == n - 1:
				# Предмет пришёл в этом тике и уже сдвинулся при передаче.
				continue
			var k := base + i
			var p := a_prog[k]
			var cap_p := limit if i == 0 else a_prog[k - 1] - SPACE
			var want := p + step
			var np := want if want < cap_p else cap_p
			if np < p:
				np = p
			var dp := np - p
			a_dprog[k] = dp
			if dp > 0:
				a_prog[k] = np
				moved = true
			if i == 0:
				front_moved = dp
				if want > UNITS and np == UNITS:
					overshoot = want - UNITS
			var l := a_lat[k]
			if l != 0.0:
				a_lat[k] = move_toward(l, 0.0, lat_step)

		# Передача переднего предмета.
		if a_prog[base] >= UNITS:
			var item := a_items[base]
			var passed := false
			if ni >= 0:
				if a_counts[ni] < CAP:
					if a_next_side[c] == 0:
						if a_mins[ni] >= SPACE:
							var pos := mini(overshoot, a_mins[ni] - SPACE)
							var tn := a_counts[ni]
							var tk := ni * CAP + tn
							a_items[tk] = item
							a_prog[tk] = pos
							a_dprog[tk] = front_moved + pos
							a_lat[tk] = 0.0
							a_counts[ni] = tn + 1
							a_mins[ni] = pos
							a_fresh[ni] = tick
							if a_awake_flags[ni] == 0:
								a_awake_flags[ni] = 1
								next_awake.append(ni)
							passed = true
					elif a_mins[ni] > SIDE_ACCEPT_MIN:
						var from_side := (a_dirs[c] + 2) % 4
						_insert(ni, item, SIDE_INSERT, 1.0 if from_side == (a_dirs[ni] + 1) % 4 else -1.0, 0)
						passed = true
			elif a_next_bid[c] != 0:
				var target := _manager.get_by_id(a_next_bid[c])
				if target != null:
					var source := _manager.get_by_id(bids[c])
					if target.accept_item(source, item):
						target.handle_item(source, item)
						passed = true
			if passed:
				for i in range(1, n):
					var k := base + i
					a_items[k - 1] = a_items[k]
					a_prog[k - 1] = a_prog[k]
					a_dprog[k - 1] = a_dprog[k]
					a_lat[k - 1] = a_lat[k]
				n -= 1
				a_counts[c] = n
				moved = true

		a_mins[c] = a_prog[base + n - 1] if n > 0 else EMPTY_MIN

		if moved:
			if a_waiters[c] == 1:
				a_waiters[c] = 0
				_sim.notify_space(bids[c])
			if n > 0 and a_awake_flags[c] == 0:
				a_awake_flags[c] = 1
				next_awake.append(c)
		elif n > 0:
			# Всё стоит: ждём, пока получатель освободит место.
			if ni >= 0:
				_sim.add_waiter(nc, bids[c])
			elif a_next_bid[c] != 0:
				_sim.add_waiter(a_next_bid[c], bids[c])


# --- Внутреннее ---

## Вставка в хвост ленты c. moved — сколько предмет «прошёл» за тик (для интерполяции).
func _insert(c: int, item: int, pos: int, lateral: float, moved: int) -> void:
	var n := counts[c]
	var k := c * CAP + n
	items[k] = item
	prog[k] = pos
	dprog[k] = moved
	lat[k] = lateral
	counts[c] = n + 1
	mins[c] = pos
	fresh_tick[c] = _sim.tick
	_wake(c)


func _wake(c: int) -> void:
	if awake_flags[c] == 0:
		awake_flags[c] = 1
		_awake.append(c)


func _copy(from: int, to: int) -> void:
	bids[to] = bids[from]
	counts[to] = counts[from]
	mins[to] = mins[from]
	steps[to] = steps[from]
	dirs[to] = dirs[from]
	tiles_x[to] = tiles_x[from]
	tiles_y[to] = tiles_y[from]
	next_conv[to] = next_conv[from]
	next_side[to] = next_side[from]
	next_bid[to] = next_bid[from]
	fresh_tick[to] = fresh_tick[from]
	awake_flags[to] = awake_flags[from]
	has_waiters[to] = has_waiters[from]
	for s in CAP:
		items[to * CAP + s] = items[from * CAP + s]
		prog[to * CAP + s] = prog[from * CAP + s]
		dprog[to * CAP + s] = dprog[from * CAP + s]
		lat[to * CAP + s] = lat[from * CAP + s]
