class_name EnemySystem
extends RefCounted
## Враги мира: плоские массивы (SoA), один проход в тике, отрисовка — одним MultiMesh (EnemyRenderer).
##
## Тик врага:
##   1. движение к следующему тайлу поля потоков (FlowField) к центральному шлюзу; скала — скольжение
##      вдоль неё, твёрдая постройка впереди — враг встаёт и она становится его целью;
##   2. выбор цели раз в RETARGET_TICKS (со сдвигом по индексу): перегородившая путь постройка,
##      затем дрон в радиусе, затем ближайшая постройка в радиусе (шлюз — тоже постройка);
##   3. атака, если цель в радиусе и прошла пауза.
## После прохода толпа раздвигается: пересекающиеся враги расталкиваются (не больше SEPARATION_CHECKS
## соседей на врага). Удаление — перестановкой последнего на место удалённого; у врага есть постоянный uid.
##
## Списки врагов по тайлам служат и для поиска целей турелями и снарядами (find_nearest, query_circle).
## Снаряды не удаляют врагов сразу (hurt), а помечают прочностью ≤ 0; remove_dead убирает их в конце тика,
## чтобы индексы в списках не сбивались посреди прохода.

const TARGET_NONE := 0
const TARGET_DRONE := -1

## Чем занята стая. Выбирается при рождении волны и может смениться по ходу.
enum Mood {
	GATE,  ## идём к шлюзу — основной поток
	HUNT,  ## охотимся на дрона игрока
	RAID,  ## грызём всё, что попадётся по дороге
}

## Пока стая дальше этого от цели, быстрые ждут медленных; ближе — каждый бежит как может.
const CHARGE_TILES := 14.0
## Медленнее этой доли своей скорости ждущий не идёт: даже с самым медлительным в стае
## остальные не должны вставать намертво.
const WAIT_FLOOR := 0.3
## А вот тот, кто ушёл вдвое дальше поводка, останавливается почти совсем.
const WAIT_STOP := 0.05
## Поводок стаи: дальше этого от замыкающего вырвавшийся вперёд не уходит (тайлы).
const PACK_LEASH := 5.0
## Проходящий рядом игрок перебивает любые планы: ближе этого враг бросается на него (тайлы).
const AGGRO_TILES := 7.0
## Стрелок держится на этой доле своей дальности и не подходит ближе.
const KEEP_RANGE := 0.75
## Насколько враг виляет: размах (радианы) и частота (радиан за тик).
const WANDER_AMPLITUDE := 0.75
const WANDER_SPEED := 0.035
## Как часто пересчитывается поворот виляния (тиков).
const WANDER_EVERY := 8
## Разброс личной скорости: ±15 %.
const SPEED_SPREAD := 0.15
## Своя дорожка: к цели каждый идёт со своим поперечным смещением (тайлы в каждую сторону).
## Из-за него стая идёт полосой, а не колонной по одному следу.
const LANE_TILES := 2.6
## Рывки и передышки: раз в DASH_PERIOD тиков враг ускоряется на DASH_TICKS, а половина ещё
## и замирает на PAUSE_TICKS — со стороны это выглядит живым роем, а не строем машин.
const DASH_PERIOD := 210
const DASH_TICKS := 24
const DASH_SPEED := 1.4
const PAUSE_TICKS := 12
const PAUSE_SPEED := 0.12
## Охотник, который столько тиков не может сократить расстояние до дрона, бросает погоню.
const CHASE_PATIENCE := 150
## Дальше этого охотник дрона не видит и идёт к шлюзу (тайлы).
const HUNT_RANGE_TILES := 40.0
## Во сколько раз шире ищет цели стая налётчиков.
const RAID_REACH := 3.0
const RETARGET_TICKS := 10
const SEPARATION_CHECKS := 6
## Доля перекрытия, на которую враги расходятся за тик.
const SEPARATION_STRENGTH := 0.35
const GROW := 256
const EVENT_CAPACITY := 256
const EVENT_STRIDE := 6
const DEATH_CAPACITY := 128
const DEATH_STRIDE := 4
## Вид события атаки для отрисовки.
enum EventKind { MELEE, SHOT }

var count: int = 0
var uid := PackedInt32Array()
var types := PackedInt32Array()
var pos_x := PackedFloat32Array()
var pos_y := PackedFloat32Array()
var prev_x := PackedFloat32Array()
var prev_y := PackedFloat32Array()
var facing := PackedFloat32Array()
var health := PackedFloat32Array()
var next_attack := PackedInt32Array()
## id постройки, TARGET_DRONE или TARGET_NONE.
var target := PackedInt32Array()
## Стая (общий номер у рождённых вместе) и чем она занята.
var squad := PackedInt32Array()
var mood := PackedInt32Array()
## Погоня: лучшее расстояние до жертвы и сколько тиков оно не улучшалось.
var chase_best := PackedFloat32Array()
var chase_ticks := PackedInt32Array()
## Личные мелочи, посчитанные при рождении: множитель скорости, фаза виляния, текущий поворот
## виляния и место стаи в сводке этого тика. Считать их каждый тик заново дорого при тысяче врагов.
var _trait_speed := PackedFloat32Array()
var _trait_phase := PackedFloat32Array()
## Своя дорожка (пиксели поперёк пути) и склонность к передышкам — считаются при рождении:
## в тике на тысячу врагов лишние вычисления стоят дороже, чем лишний массив.
var _trait_lane := PackedFloat32Array()
var _trait_pause := PackedByteArray()
var _wander_turn := PackedFloat32Array()
## На какой момент посчитан поворот виляния: после загрузки он пересчитывается сам.
var _wander_tick := PackedInt32Array()
var _slot_of := PackedInt32Array()
## id постройки, перегородившей путь (0 — путь свободен).
var blocker := PackedInt32Array()
var next_tile := PackedInt32Array()
var path_version := PackedInt32Array()
## Горение: урон в секунду и тик окончания.
var burn_dps := PackedFloat32Array()
var burn_until := PackedInt32Array()

var next_uid: int = 1
var spawned: int = 0
var killed: int = 0

## События атак для отрисовки (не сохраняются): x0, y0, x1, y1, тик, вид — кольцевой буфер.
var events := PackedFloat32Array()
var event_cursor: int = 0
## Гибель врагов для отрисовки (не сохраняется): x, y, тик, тип — кольцевой буфер.
var deaths := PackedFloat32Array()
var death_cursor: int = 0
var last_death_tick: int = -1000
var last_update_usec: int = 0

var _world: GameWorld
var _capacity: int = 0
## Сводка по стаям на текущий тик: номер стаи → место в массивах ниже.
var _squad_slot: Dictionary[int, int] = {}
var _sq_count := PackedInt32Array()
var _sq_dist_sum := PackedFloat32Array()
var _sq_min_dist := PackedFloat32Array()
var _sq_max_dist := PackedFloat32Array()
var _sq_min_speed := PackedFloat32Array()
# Характеристики типов по индексу EnemyDef.
var _speed := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _reach := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _interval := PackedInt32Array()
var _ranged := PackedByteArray()
# Раздвигание толпы: списки врагов по тайлам.
## Крупная сетка для поиска: у турели дальность в восемь тайлов, и по тайловой сетке она
## перебирала бы сотни ячеек на каждый поиск цели. Клетка в QUERY_CELL тайлов — их десятки.
const QUERY_CELL := 4
## До какого радиуса (в тайлах) выгоднее тайловая сетка.
const FINE_QUERY_TILES := 2.5
var _query_head := PackedInt32Array()
var _query_next := PackedInt32Array()
var _query_w: int = 0
var _query_h: int = 0
var _query_valid: bool = false
## Буферы поиска, чтобы не создавать массив на каждый запрос (их два: поиск и круг не вложены).
var _near_scratch := PackedInt32Array()
var _circle_scratch := PackedInt32Array()

var _cell_head := PackedInt32Array()
var _cell_next := PackedInt32Array()
var _cells := PackedInt32Array()
## Списки по тайлам соответствуют текущим индексам врагов.
var _cells_valid: bool = false


func _init(world: GameWorld) -> void:
	_world = world
	events.resize(EVENT_CAPACITY * EVENT_STRIDE)
	events.fill(-1.0)
	deaths.resize(DEATH_CAPACITY * DEATH_STRIDE)
	deaths.fill(-1.0)
	var n := Registry.enemies.size()
	_speed.resize(n)
	_radius.resize(n)
	_reach.resize(n)
	_damage.resize(n)
	_interval.resize(n)
	_ranged.resize(n)
	for def in Registry.enemies:
		_speed[def.index] = def.get_speed_per_tick()
		_radius[def.index] = def.radius
		_reach[def.index] = def.get_range_px() + def.radius
		_damage[def.index] = def.damage
		_interval[def.index] = def.get_attack_ticks()
		_ranged[def.index] = 1 if def.attack_range >= 1.0 else 0


func dispose() -> void:
	_world = null


func get_position(i: int) -> Vector2:
	return Vector2(pos_x[i], pos_y[i])


func get_def(i: int) -> EnemyDef:
	return Registry.enemies[types[i]]


func get_radius(i: int) -> float:
	return _radius[types[i]]


## Индекс врага по uid (-1 — нет такого).
func find_uid(value: int) -> int:
	for i in count:
		if uid[i] == value:
			return i
	return -1


func spawn(def: EnemyDef, position: Vector2, tick: int, squad_id: int = 0, squad_mood: int = Mood.GATE) -> int:
	_ensure_capacity(count + 1)
	var i := count
	count += 1
	uid[i] = next_uid
	next_uid += 1
	types[i] = def.index
	pos_x[i] = position.x
	pos_y[i] = position.y
	prev_x[i] = position.x
	prev_y[i] = position.y
	facing[i] = 0.0
	health[i] = def.health
	next_attack[i] = tick + _interval[def.index]
	target[i] = TARGET_NONE
	squad[i] = squad_id
	mood[i] = squad_mood
	chase_best[i] = INF
	chase_ticks[i] = 0
	_set_traits(i)
	blocker[i] = 0
	next_tile[i] = -1
	path_version[i] = -1
	burn_dps[i] = 0.0
	burn_until[i] = 0
	spawned += 1
	_cells_valid = false
	_query_valid = false
	return i


## Урон врагу. true — враг погиб и удалён (индекс занял последний враг).
func damage(i: int, amount: float) -> bool:
	if i < 0 or i >= count:
		return false
	health[i] -= amount
	if health[i] > 0.0:
		return false
	_push_death(i)
	remove_at(i)
	killed += 1
	return true


## Поджечь: горение не складывается — остаётся более сильное, длительность продлевается.
func ignite(i: int, dps: float, until_tick: int) -> void:
	if i < 0 or i >= count or health[i] <= 0.0:
		return
	burn_dps[i] = maxf(burn_dps[i], dps)
	burn_until[i] = maxi(burn_until[i], until_tick)


func is_burning(i: int, tick: int) -> bool:
	return tick < burn_until[i]


## Урон без удаления (снаряды): погибший остаётся до remove_dead. true — враг погиб этим уроном.
func hurt(i: int, amount: float) -> bool:
	if i < 0 or i >= count or health[i] <= 0.0:
		return false
	health[i] -= amount
	return health[i] <= 0.0


## Убрать погибших (прочность ≤ 0). Возвращает, сколько убрано.
func remove_dead() -> int:
	var removed := 0
	for i in range(count - 1, -1, -1):
		if health[i] <= 0.0:
			_push_death(i)
			remove_at(i)
			removed += 1
	killed += removed
	return removed


func is_alive(i: int) -> bool:
	return i >= 0 and i < count and health[i] > 0.0


## Ближайший живой враг, чьё тело попадает в кольцо [min_range, max_range] от точки; -1 — нет.
func find_nearest(x: float, y: float, max_range: float, min_range: float = 0.0) -> int:
	if count == 0:
		return -1
	_near_scratch.clear()
	_collect_candidates(x, y, max_range, _near_scratch)
	var candidates := _near_scratch
	var best := -1
	var best_d := INF
	for i in candidates:
		var d := _body_distance(i, x, y)
		if d < best_d and d <= max_range and d >= min_range and health[i] > 0.0:
			best_d = d
			best = i
	return best


## Живые враги, чьё тело пересекает круг: индексы добавляются в out.
func query_circle(x: float, y: float, radius: float, out: PackedInt32Array) -> void:
	if count == 0:
		return
	_circle_scratch.clear()
	_collect_candidates(x, y, radius, _circle_scratch)
	for i in _circle_scratch:
		if health[i] > 0.0 and _body_distance(i, x, y) <= radius:
			out.append(i)


## Кандидаты рядом с точкой. Сетка выбирается по радиусу: для попадания пули (радиус меньше тайла)
## тайловая сетка даёт девять клеток и почти никого лишнего, а для поиска цели турелью (восемь
## тайлов) по ней пришлось бы перебрать сотни клеток — там выигрывает крупная.
func _collect_candidates(x: float, y: float, radius: float, out: PackedInt32Array) -> void:
	var t := float(GameConst.TILE_SIZE)
	var fine := radius <= t * FINE_QUERY_TILES
	var cell := t if fine else t * QUERY_CELL
	var span := ceili(radius / cell) + 1
	if count <= (span * 2 + 1) * (span * 2 + 1):
		out.resize(count)
		for i in count:
			out[i] = i
		return
	var w := _world.grid.width if fine else _query_w
	var h := _world.grid.height if fine else _query_h
	if fine:
		if not _cells_valid:
			rebuild_cells()
	elif not _query_valid:
		rebuild_query_cells()
	var heads := _cell_head if fine else _query_head
	var next := _cell_next if fine else _query_next
	var tx := int(x / cell)
	var ty := int(y / cell)
	for cy in range(maxi(ty - span, 0), mini(ty + span, h - 1) + 1):
		var row := cy * w
		for cx in range(maxi(tx - span, 0), mini(tx + span, w - 1) + 1):
			var j := heads[row + cx]
			while j >= 0:
				if j < count:
					out.append(j)
				j = next[j]


## Крупная сетка для поиска целей и попаданий: перестраивается раз в тик, как и тайловая.
func rebuild_query_cells() -> void:
	var grid := _world.grid
	var cell := GameConst.TILE_SIZE * QUERY_CELL
	_query_w = (grid.width + QUERY_CELL - 1) / QUERY_CELL
	_query_h = (grid.height + QUERY_CELL - 1) / QUERY_CELL
	if _query_head.size() != _query_w * _query_h:
		_query_head.resize(_query_w * _query_h)
	_query_head.fill(-1)
	if _query_next.size() < _capacity:
		_query_next.resize(_capacity)
	var inv := 1.0 / float(cell)
	for i in count:
		var c := clampi(int(pos_y[i] * inv), 0, _query_h - 1) * _query_w + clampi(int(pos_x[i] * inv), 0, _query_w - 1)
		_query_next[i] = _query_head[c]
		_query_head[c] = i
	_query_valid = true


## Расстояние от точки до края тела врага (0 — внутри).
func _body_distance(i: int, x: float, y: float) -> float:
	var dx := pos_x[i] - x
	var dy := pos_y[i] - y
	return maxf(sqrt(dx * dx + dy * dy) - _radius[types[i]], 0.0)


## Списки врагов по тайлам (раздвигание толпы, поиск целей).
func rebuild_cells() -> void:
	var grid := _world.grid
	var w := grid.width
	var h := grid.height
	var inv_t := 1.0 / GameConst.TILE_SIZE
	if _cell_head.size() != w * h:
		_cell_head.resize(w * h)
	_cell_head.fill(-1)
	if _cells.size() < _capacity:
		_cells.resize(_capacity)
	if _cell_next.size() < _capacity:
		_cell_next.resize(_capacity)
	for i in count:
		var c := clampi(int(pos_y[i] * inv_t), 0, h - 1) * w + clampi(int(pos_x[i] * inv_t), 0, w - 1)
		_cells[i] = c
		_cell_next[i] = _cell_head[c]
		_cell_head[c] = i
	_cells_valid = true


func _push_death(i: int) -> void:
	var o := death_cursor * DEATH_STRIDE
	deaths[o] = pos_x[i]
	deaths[o + 1] = pos_y[i]
	deaths[o + 2] = _world.simulation.tick if _world != null and _world.simulation != null else 0
	deaths[o + 3] = types[i]
	death_cursor = (death_cursor + 1) % DEATH_CAPACITY
	last_death_tick = int(deaths[o + 2])


func remove_at(i: int) -> void:
	var last := count - 1
	if i != last:
		uid[i] = uid[last]
		types[i] = types[last]
		pos_x[i] = pos_x[last]
		pos_y[i] = pos_y[last]
		prev_x[i] = prev_x[last]
		prev_y[i] = prev_y[last]
		facing[i] = facing[last]
		health[i] = health[last]
		next_attack[i] = next_attack[last]
		target[i] = target[last]
		squad[i] = squad[last]
		mood[i] = mood[last]
		chase_best[i] = chase_best[last]
		chase_ticks[i] = chase_ticks[last]
		_trait_speed[i] = _trait_speed[last]
		_trait_phase[i] = _trait_phase[last]
		_trait_lane[i] = _trait_lane[last]
		_trait_pause[i] = _trait_pause[last]
		_wander_turn[i] = _wander_turn[last]
		_wander_tick[i] = _wander_tick[last]
		blocker[i] = blocker[last]
		next_tile[i] = next_tile[last]
		path_version[i] = path_version[last]
		burn_dps[i] = burn_dps[last]
		burn_until[i] = burn_until[last]
	count -= 1
	_cells_valid = false
	_query_valid = false


func clear() -> void:
	count = 0
	_cells_valid = false
	_query_valid = false


# --- Тик ---

func update(tick: int) -> void:
	if count == 0:
		return
	var start := Time.get_ticks_usec()
	var world := _world
	var grid := world.grid
	var w := grid.width
	var h := grid.height
	var ids := grid.building_ids
	var manager := world.buildings
	var flow := world.flow
	var dist := flow.dist
	var blocked := flow.blocked
	var flow_version := flow.version
	var t := float(GameConst.TILE_SIZE)
	var inv_t := 1.0 / t
	var max_x := w * t - 0.5
	var max_y := h * t - 0.5
	var gate := world.gateway
	var has_gate := gate != null and gate.world != null
	var gate_center := gate.get_world_center() if has_gate else Vector2.ZERO
	# Живые дроны этого мира: враг целится в ближайшего из них.
	var live: Array[Drone] = []
	for d in world.drones:
		if d.world == world and d.is_targetable(tick):
			live.append(d)
	var drone_ok := not live.is_empty()
	# Стаи: пока стая далеко, быстрые придерживают шаг и ждут отставших.
	_collect_squads(dist, w, inv_t)

	for i in count:
		var type := types[i]
		var x := pos_x[i]
		var y := pos_y[i]
		prev_x[i] = x
		prev_y[i] = y
		if burn_until[i] > 0:
			if tick < burn_until[i]:
				health[i] -= burn_dps[i] * GameConst.TICK_DT
			else:
				burn_until[i] = 0
				burn_dps[i] = 0.0
		var radius := _radius[type]
		var tx := clampi(int(x * inv_t), 0, w - 1)
		var ty := clampi(int(y * inv_t), 0, h - 1)
		var tile := ty * w + tx

		# 1. Движение.
		var nt := next_tile[i]
		if nt < 0 or nt == tile or path_version[i] != flow_version:
			nt = flow.best_neighbor(tile) if dist[tile] < FlowField.INF else -1
			next_tile[i] = nt
			path_version[i] = flow_version
		var goal_x := gate_center.x
		var goal_y := gate_center.y
		var has_goal := has_gate
		if nt >= 0:
			goal_x = (nt % w + 0.5) * t
			goal_y = (nt / w + 0.5) * t
			has_goal = true
		# Охотник идёт прямо на дрона, пока тот в пределах видимости; если догнать не выходит,
		# он бросает погоню и уходит к шлюзу — стая не зацикливается на недосягаемой жертве.
		var hunting := false
		# Игрок прошёл рядом — враг переключается на него, чем бы ни занимался.
		if drone_ok and mood[i] != Mood.HUNT:
			var near := _nearest_drone(live, x, y)
			if near != null and Vector2(near.position.x - x, near.position.y - y).length() < AGGRO_TILES * t:
				mood[i] = Mood.HUNT
				chase_best[i] = INF
				chase_ticks[i] = 0
		if mood[i] == Mood.HUNT:
			var prey := _nearest_drone(live, x, y)
			if prey == null:
				mood[i] = Mood.GATE
			else:
				var pdx := prey.position.x - x
				var pdy := prey.position.y - y
				var pd := sqrt(pdx * pdx + pdy * pdy)
				if pd > HUNT_RANGE_TILES * t:
					mood[i] = Mood.GATE
				else:
					hunting = true
					goal_x = prey.position.x
					goal_y = prey.position.y
					has_goal = true
					if pd < chase_best[i] - t * 0.5:
						chase_best[i] = pd
						chase_ticks[i] = 0
					else:
						chase_ticks[i] += 1
						if chase_ticks[i] > CHASE_PATIENCE:
							mood[i] = Mood.GATE
							chase_ticks[i] = 0
							chase_best[i] = INF
		var block := 0
		# Внутри твёрдой постройки (её поставили поверх врага) — бьём её, но выйти можно.
		if blocked[tile] == FlowField.SOLID:
			block = ids[tile]
		# Стрелок держит дистанцию: подойдя на выстрел, он останавливается, а если жертва подошла
		# вплотную — пятится. Лезть в ближний бой ему незачем.
		if _ranged[type] == 1 and target[i] != TARGET_NONE and has_goal:
			var aim := _target_point(target[i], live, manager, x, y)
			if aim.z > 0.0:
				var adx := aim.x - x
				var ady := aim.y - y
				var ad := sqrt(adx * adx + ady * ady)
				var reach_now := _reach[type]
				if ad <= reach_now and ad > 0.01:
					if ad < reach_now * KEEP_RANGE:
						goal_x = x - adx / ad * t
						goal_y = y - ady / ad * t
					else:
						has_goal = false
						facing[i] = atan2(ady, adx)

		# Своя дорожка: цель сдвигается поперёк пути, у каждого по-своему. Охотник бежит прямо
		# на жертву — ему вилять незачем.
		if has_goal and not hunting:
			var lane := _trait_lane[i]
			var ldx := goal_x - x
			var ldy := goal_y - y
			var llen := sqrt(ldx * ldx + ldy * ldy)
			if llen > t * 0.5:
				goal_x += -ldy / llen * lane
				goal_y += ldx / llen * lane
		if has_goal:
			var vx := goal_x - x
			var vy := goal_y - y
			var length := sqrt(vx * vx + vy * vy)
			if length > 0.5:
				vx /= length
				vy /= length
				# Виляние: враг не идёт по идеальной прямой, и след стаи получается полосой.
				if length > t * 1.5:
					var turn := wander(i, tick)
					var cs := cos(turn)
					var sn := sin(turn)
					var rx := vx * cs - vy * sn
					vy = vx * sn + vy * cs
					vx = rx
				facing[i] = atan2(vy, vx)
				var step := _speed[type] * speed_scale(i) * pace_scale(i, tick)
				# Стая идёт вместе: тот, кто вырвался вперёд, придерживает шаг, пока остальные
				# не подтянутся. У самой цели все бегут в полную силу — тут скорость и решает.
				if not hunting:
					var slot := _slot_of[i]
					if slot >= 0 and _sq_count[slot] > 1 and _sq_min_dist[slot] > CHARGE_TILES:
						# Поводок у каждого свой (±40 %): иначе стая идёт ровной шеренгой.
						var leash := PACK_LEASH * (0.6 + 0.8 * trait01(uid[i], 3))
						var rear: float = _sq_max_dist[slot]
						var mine: float = float(dist[tile]) if dist[tile] < FlowField.INF else rear
						if mine < rear - leash * 2.0:
							# Ушёл слишком далеко — стоит и ждёт своих.
							step = minf(step, _speed[type] * WAIT_STOP)
						elif mine < rear - leash:
							# Оторвался от замыкающего — идёт со скоростью самого медленного в стае.
							step = minf(step, maxf(_sq_min_speed[slot], step * WAIT_FLOOR))
				# Шаг не длиннее остатка пути: быстрый враг не проскакивает цель и не дрожит у неё.
				step = minf(step, length)
				var nx := clampf(x + vx * step, 0.5, max_x)
				var ny := clampf(y + vy * step, 0.5, max_y)
				var lt := _tile_at(nx + vx * radius, ny + vy * radius, w, h, inv_t)
				if lt < 0 or lt == tile or blocked[lt] == FlowField.OPEN:
					x = nx
					y = ny
				else:
					var ahead_building := blocked[lt] == FlowField.SOLID
					var path_blocked := nt >= 0 and blocked[nt] != FlowField.OPEN
					# Целый шаг не влез — пробуем короче: иначе быстрый враг встаёт в полутайле
					# от стены и до неё не дотягивается.
					var fitted := false
					for fraction in [0.5]:
						var fx := clampf(x + vx * step * fraction, 0.5, max_x)
						var fy := clampf(y + vy * step * fraction, 0.5, max_y)
						var ft := _tile_at(fx + vx * radius, fy + vy * radius, w, h, inv_t)
						if ft < 0 or ft == tile or blocked[ft] == FlowField.OPEN:
							x = fx
							y = fy
							fitted = true
							break
					if fitted:
						pass
					elif ahead_building and (path_blocked or nt < 0):
						block = ids[lt]
					else:
						# Скольжение вдоль препятствия по одной из осей.
						var sx := clampf(x + vx * step, 0.5, max_x)
						var lx := _tile_at(sx + signf(vx) * radius, y, w, h, inv_t)
						if absf(vx) > 0.05 and (lx < 0 or lx == tile or blocked[lx] == FlowField.OPEN):
							x = sx
						else:
							var sy := clampf(y + vy * step, 0.5, max_y)
							var ly := _tile_at(x, sy + signf(vy) * radius, w, h, inv_t)
							if absf(vy) > 0.05 and (ly < 0 or ly == tile or blocked[ly] == FlowField.OPEN):
								y = sy
							elif ahead_building:
								block = ids[lt]
				pos_x[i] = x
				pos_y[i] = y
		blocker[i] = block

		# 2. Цель.
		var tg := target[i]
		# Ближайший к врагу дрон — и цель поиска, и жертва атаки.
		var drone := _nearest_drone(live, x, y)
		if block != 0:
			tg = block
		elif (i + tick) % RETARGET_TICKS == 0 or (tg > 0 and manager.get_by_id(tg) == null) or (tg == TARGET_DRONE and not drone_ok):
			# Налётчики смотрят шире и охотно грызут всё по дороге, остальные — только то,
			# до чего дотянулись.
			var look := RAID_REACH if mood[i] == Mood.RAID else 1.0
			tg = _find_target(x, y, type, drone_ok, drone, grid, manager, look)
		target[i] = tg

		# 3. Атака.
		if tg == TARGET_NONE or tick < next_attack[i]:
			continue
		var reach := _reach[type]
		if tg == TARGET_DRONE:
			var ddx := drone.position.x - x
			var ddy := drone.position.y - y
			var drone_reach := reach + drone.def.hit_radius
			if drone_ok and ddx * ddx + ddy * ddy <= drone_reach * drone_reach:
				next_attack[i] = tick + _interval[type]
				_push_event(x, y, drone.position.x, drone.position.y, tick, type)
				world.damage_drone(drone, _damage[type], tick)
				if not drone.is_targetable(tick):
					live.erase(drone)
					drone_ok = not live.is_empty()
			else:
				target[i] = TARGET_NONE
			continue
		var b := manager.get_by_id(tg)
		if b == null:
			target[i] = TARGET_NONE
			continue
		var rect := b.get_world_rect()
		var cx := clampf(x, rect.position.x, rect.end.x)
		var cy := clampf(y, rect.position.y, rect.end.y)
		if (cx - x) * (cx - x) + (cy - y) * (cy - y) <= reach * reach:
			next_attack[i] = tick + _interval[type]
			_push_event(x, y, cx, cy, tick, type)
			world.damage_building(b, _damage[type])
		elif block != tg:
			target[i] = TARGET_NONE

	_separate(w, h, inv_t, max_x, max_y, blocked)
	last_update_usec = Time.get_ticks_usec() - start


## Личные мелочи врага (скорость, фаза виляния) считаются от его номера, а не от случайных чисел:
## в совместной игре у всех должно выйти одно и то же.
static func trait01(value: int, salt: int) -> float:
	var h := (value * 2654435761 + salt * 40503) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10007.0


## Личные мелочи врага выводятся из его номера, поэтому после загрузки получаются те же самые:
## сохранять их не нужно, а пересчитывать каждый тик — дорого при тысяче врагов.
func _set_traits(i: int) -> void:
	_trait_speed[i] = 1.0 + (trait01(uid[i], 1) - 0.5) * 2.0 * SPEED_SPREAD
	_trait_phase[i] = trait01(uid[i], 2) * TAU
	_trait_lane[i] = (trait01(uid[i], 5) - 0.5) * 2.0 * LANE_TILES * GameConst.TILE_SIZE
	_trait_pause[i] = 1 if trait01(uid[i], 7) > 0.5 else 0
	_wander_turn[i] = 0.0
	_wander_tick[i] = -1


## Личная скорость врага: ±SPEED_SPREAD от типовой, чтобы стая не шла одинаковым шагом.
func speed_scale(i: int) -> float:
	return _trait_speed[i]


## Рывок или передышка: всё считается от номера врага и тика, без случайных чисел,
## поэтому у всех участников сетевой игры рой ведёт себя одинаково.
func pace_scale(i: int, tick: int) -> float:
	var phase := posmod(tick + uid[i] * 37, DASH_PERIOD)
	if phase < DASH_TICKS:
		return DASH_SPEED
	if phase < DASH_TICKS + PAUSE_TICKS and _trait_pause[i] == 1:
		return PAUSE_SPEED
	return 1.0


## Насколько враг отклоняется от прямого пути прямо сейчас (радианы): медленное виляние,
## у каждого своя фаза. Из-за него стая идёт полосой, а не цепочкой по одному следу.
## Пересчитывается раз в WANDER_EVERY тиков и вразнобой: синус тысяче врагов каждый тик дорог,
## а виляние и так медленное.
func wander(i: int, tick: int) -> float:
	# Момент округляется вниз с шагом WANDER_EVERY и вразнобой по врагам: значение зависит только
	# от номера врага и времени, поэтому после загрузки выходит ровно тем же.
	var moment := tick - (tick + uid[i]) % WANDER_EVERY
	if _wander_tick[i] != moment:
		_wander_tick[i] = moment
		_wander_turn[i] = WANDER_AMPLITUDE * sin(moment * WANDER_SPEED + _trait_phase[i])
	return _wander_turn[i]


## Пересчитать сводку по стаям: сколько их, насколько далеко они от цели и кто в стае самый медленный.
## dist — поле расстояний до шлюза в тайлах (FlowField), по нему видно, кто вырвался вперёд.
func _collect_squads(dist: PackedInt32Array, w: int, inv_t: float) -> void:
	_squad_slot.clear()
	_sq_count.clear()
	_sq_dist_sum.clear()
	_sq_min_dist.clear()
	_sq_max_dist.clear()
	_sq_min_speed.clear()
	# Враги лежат в порядке рождения, поэтому соседи почти всегда из одной стаи: словарь
	# спрашиваем только когда стая сменилась — при тысяче врагов это заметная экономия.
	var last_sid := -1
	var last_slot := -1
	for i in count:
		var sid := squad[i]
		var slot := last_slot if sid == last_sid else int(_squad_slot.get(sid, -1))
		if slot < 0:
			slot = _sq_count.size()
			_squad_slot[sid] = slot
			_sq_count.append(0)
			_sq_dist_sum.append(0.0)
			_sq_min_dist.append(INF)
			_sq_max_dist.append(0.0)
			_sq_min_speed.append(INF)
		var tile := int(pos_y[i] * inv_t) * w + int(pos_x[i] * inv_t)
		var d: float = float(dist[tile]) if tile >= 0 and tile < dist.size() else INF
		if d >= FlowField.INF:
			d = _sq_min_dist[slot] if _sq_count[slot] > 0 else 0.0
		_sq_count[slot] += 1
		_sq_dist_sum[slot] += d
		_sq_min_dist[slot] = minf(_sq_min_dist[slot], d)
		_sq_max_dist[slot] = maxf(_sq_max_dist[slot], d)
		_sq_min_speed[slot] = minf(_sq_min_speed[slot], _speed[types[i]] * _trait_speed[i])
		_slot_of[i] = slot
		last_sid = sid
		last_slot = slot


## Куда целится враг: (x, y, 1) — точка цели, z = 0 — цели уже нет.
func _target_point(tg: int, live: Array[Drone], manager: BuildingManager, x: float, y: float) -> Vector3:
	if tg == TARGET_DRONE:
		var drone := _nearest_drone(live, x, y)
		return Vector3(drone.position.x, drone.position.y, 1.0) if drone != null else Vector3.ZERO
	var b := manager.get_by_id(tg)
	if b == null:
		return Vector3.ZERO
	var rect := b.get_world_rect()
	return Vector3(clampf(x, rect.position.x, rect.end.x), clampf(y, rect.position.y, rect.end.y), 1.0)


func _tile_at(px: float, py: float, w: int, h: int, inv_t: float) -> int:
	if px < 0.0 or py < 0.0:
		return -1
	var tx := int(px * inv_t)
	var ty := int(py * inv_t)
	if tx >= w or ty >= h:
		return -1
	return ty * w + tx


## Ближайшая цель в радиусе атаки: дрон в приоритете, затем постройка.
## Ближайший к точке дрон из списка живых (null — список пуст).
static func _nearest_drone(live: Array[Drone], x: float, y: float) -> Drone:
	if live.is_empty():
		return null
	if live.size() == 1:
		return live[0]
	var best: Drone = live[0]
	var best_distance := INF
	for d in live:
		var dd := (d.position.x - x) * (d.position.x - x) + (d.position.y - y) * (d.position.y - y)
		if dd < best_distance:
			best_distance = dd
			best = d
	return best


func _find_target(x: float, y: float, type: int, drone_ok: bool, drone: Drone, grid: WorldGrid,
		manager: BuildingManager, look: float = 1.0) -> int:
	var reach := _reach[type] * look
	if drone_ok:
		var ddx := drone.position.x - x
		var ddy := drone.position.y - y
		var drone_reach := reach + drone.def.hit_radius
		if ddx * ddx + ddy * ddy <= drone_reach * drone_reach:
			return TARGET_DRONE
	var t := float(GameConst.TILE_SIZE)
	var span := ceili(reach / t)
	var w := grid.width
	var tx := int(x / t)
	var ty := int(y / t)
	var ids := grid.building_ids
	var best := TARGET_NONE
	var best_d := reach * reach
	var last := 0
	for yy in range(maxi(ty - span, 0), mini(ty + span, grid.height - 1) + 1):
		for xx in range(maxi(tx - span, 0), mini(tx + span, w - 1) + 1):
			var bid := ids[yy * w + xx]
			if bid == 0 or bid == last or bid == best:
				continue
			last = bid
			var b := manager.get_by_id(bid)
			if b == null:
				continue
			var rect := b.get_world_rect()
			var cx := clampf(x, rect.position.x, rect.end.x)
			var cy := clampf(y, rect.position.y, rect.end.y)
			var d := (cx - x) * (cx - x) + (cy - y) * (cy - y)
			if d <= best_d:
				best_d = d
				best = bid
	return best


func _push_event(x0: float, y0: float, x1: float, y1: float, tick: int, type: int) -> void:
	var o := event_cursor * EVENT_STRIDE
	events[o] = x0
	events[o + 1] = y0
	events[o + 2] = x1
	events[o + 3] = y1
	events[o + 4] = tick
	events[o + 5] = EventKind.SHOT if _ranged[type] == 1 else EventKind.MELEE
	event_cursor = (event_cursor + 1) % EVENT_CAPACITY


## Раздвигание толпы: враг отталкивается от пересекающихся соседей по своему и соседним тайлам.
func _separate(w: int, h: int, inv_t: float, max_x: float, max_y: float, blocked: PackedByteArray) -> void:
	rebuild_cells()
	for i in count:
		var c := _cells[i]
		var cx := c % w
		var cy := c / w
		var xi := pos_x[i]
		var yi := pos_y[i]
		var ri := _radius[types[i]]
		var push_x := 0.0
		var push_y := 0.0
		var checks := 0
		for oy in range(maxi(cy - 1, 0), mini(cy + 1, h - 1) + 1):
			if checks >= SEPARATION_CHECKS:
				break
			for ox in range(maxi(cx - 1, 0), mini(cx + 1, w - 1) + 1):
				var j := _cell_head[oy * w + ox]
				while j >= 0 and checks < SEPARATION_CHECKS:
					if j != i:
						checks += 1
						var dx := xi - pos_x[j]
						var dy := yi - pos_y[j]
						var min_d := ri + _radius[types[j]]
						var d2 := dx * dx + dy * dy
						if d2 < min_d * min_d:
							if d2 < 0.0001:
								# Совпали точно — расталкиваем в сторону, зависящую от порядка.
								dx = 1.0 if i > j else -1.0
								dy = 0.5 if (i + j) % 2 == 0 else -0.5
								d2 = dx * dx + dy * dy
							var d := sqrt(d2)
							var k := (min_d - d) * SEPARATION_STRENGTH / d
							push_x += dx * k
							push_y += dy * k
					j = _cell_next[j]
		if push_x == 0.0 and push_y == 0.0:
			continue
		var px := clampf(xi + push_x, 0.5, max_x)
		var py := clampf(yi + push_y, 0.5, max_y)
		var pt := int(py * inv_t) * w + int(px * inv_t)
		if pt == c or blocked[pt] == FlowField.OPEN:
			pos_x[i] = px
			pos_y[i] = py


func _ensure_capacity(wanted: int) -> void:
	if wanted <= _capacity:
		return
	_capacity = maxi(wanted, _capacity + GROW)
	uid.resize(_capacity)
	types.resize(_capacity)
	pos_x.resize(_capacity)
	pos_y.resize(_capacity)
	prev_x.resize(_capacity)
	prev_y.resize(_capacity)
	facing.resize(_capacity)
	health.resize(_capacity)
	next_attack.resize(_capacity)
	target.resize(_capacity)
	squad.resize(_capacity)
	mood.resize(_capacity)
	chase_best.resize(_capacity)
	chase_ticks.resize(_capacity)
	_trait_speed.resize(_capacity)
	_trait_phase.resize(_capacity)
	_trait_lane.resize(_capacity)
	_trait_pause.resize(_capacity)
	_wander_turn.resize(_capacity)
	_wander_tick.resize(_capacity)
	_slot_of.resize(_capacity)
	blocker.resize(_capacity)
	next_tile.resize(_capacity)
	path_version.resize(_capacity)
	burn_dps.resize(_capacity)
	burn_until.resize(_capacity)
	_cell_next.resize(_capacity)


# --- Сохранение ---

func save_data() -> Dictionary:
	return {
		"count": count, "next_uid": next_uid, "spawned": spawned, "killed": killed,
		"uid": uid.slice(0, count), "types": types.slice(0, count),
		"pos_x": pos_x.slice(0, count), "pos_y": pos_y.slice(0, count),
		"prev_x": prev_x.slice(0, count), "prev_y": prev_y.slice(0, count),
		"facing": facing.slice(0, count), "health": health.slice(0, count),
		"next_attack": next_attack.slice(0, count), "target": target.slice(0, count),
		"squad": squad.slice(0, count), "mood": mood.slice(0, count),
		"chase_best": chase_best.slice(0, count), "chase_ticks": chase_ticks.slice(0, count),
		"blocker": blocker.slice(0, count), "next_tile": next_tile.slice(0, count),
		"path_version": path_version.slice(0, count),
		"burn_dps": burn_dps.slice(0, count), "burn_until": burn_until.slice(0, count),
	}


## type_map — сохранённый индекс типа → текущий (-1 — тип исчез, враг пропускается).
func load_data(data: Dictionary, type_map: PackedInt32Array) -> void:
	count = 0
	next_uid = int(data.get("next_uid", 1))
	spawned = int(data.get("spawned", 0))
	killed = int(data.get("killed", 0))
	var saved: int = int(data.get("count", 0))
	var s_uid: PackedInt32Array = data.get("uid", PackedInt32Array())
	var s_types: PackedInt32Array = data.get("types", PackedInt32Array())
	var s_px: PackedFloat32Array = data.get("pos_x", PackedFloat32Array())
	var s_py: PackedFloat32Array = data.get("pos_y", PackedFloat32Array())
	var s_prx: PackedFloat32Array = data.get("prev_x", PackedFloat32Array())
	var s_pry: PackedFloat32Array = data.get("prev_y", PackedFloat32Array())
	var s_facing: PackedFloat32Array = data.get("facing", PackedFloat32Array())
	var s_health: PackedFloat32Array = data.get("health", PackedFloat32Array())
	var s_attack: PackedInt32Array = data.get("next_attack", PackedInt32Array())
	var s_target: PackedInt32Array = data.get("target", PackedInt32Array())
	var s_squad: PackedInt32Array = data.get("squad", PackedInt32Array())
	var s_mood: PackedInt32Array = data.get("mood", PackedInt32Array())
	var s_chase_best: PackedFloat32Array = data.get("chase_best", PackedFloat32Array())
	var s_chase_ticks: PackedInt32Array = data.get("chase_ticks", PackedInt32Array())
	var s_blocker: PackedInt32Array = data.get("blocker", PackedInt32Array())
	var s_next: PackedInt32Array = data.get("next_tile", PackedInt32Array())
	var s_version: PackedInt32Array = data.get("path_version", PackedInt32Array())
	var s_burn_dps: PackedFloat32Array = data.get("burn_dps", PackedFloat32Array())
	var s_burn_until: PackedInt32Array = data.get("burn_until", PackedInt32Array())
	for k in [s_uid.size(), s_types.size(), s_px.size(), s_py.size(), s_prx.size(), s_pry.size(), s_facing.size(),
			s_health.size(), s_attack.size(), s_target.size(), s_blocker.size(), s_next.size(), s_version.size()]:
		saved = mini(saved, k)
	_ensure_capacity(saved)
	for j in saved:
		var type := s_types[j]
		if type_map.size() > 0:
			type = type_map[type] if type >= 0 and type < type_map.size() else -1
		if type < 0 or type >= Registry.enemies.size():
			continue
		var i := count
		count += 1
		uid[i] = s_uid[j]
		types[i] = type
		pos_x[i] = s_px[j]
		pos_y[i] = s_py[j]
		prev_x[i] = s_prx[j]
		prev_y[i] = s_pry[j]
		facing[i] = s_facing[j]
		health[i] = s_health[j]
		next_attack[i] = s_attack[j]
		target[i] = s_target[j]
		squad[i] = int(s_squad[j]) if j < s_squad.size() else 0
		mood[i] = int(s_mood[j]) if j < s_mood.size() else Mood.GATE
		chase_best[i] = float(s_chase_best[j]) if j < s_chase_best.size() else INF
		chase_ticks[i] = int(s_chase_ticks[j]) if j < s_chase_ticks.size() else 0
		_set_traits(i)
		blocker[i] = s_blocker[j]
		next_tile[i] = s_next[j]
		path_version[i] = s_version[j]
		burn_dps[i] = s_burn_dps[j] if j < s_burn_dps.size() else 0.0
		burn_until[i] = s_burn_until[j] if j < s_burn_until.size() else 0
