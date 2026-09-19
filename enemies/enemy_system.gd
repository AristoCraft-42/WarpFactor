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
# Характеристики типов по индексу EnemyDef.
var _speed := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _reach := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _interval := PackedInt32Array()
var _ranged := PackedByteArray()
# Раздвигание толпы: списки врагов по тайлам.
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


func spawn(def: EnemyDef, position: Vector2, tick: int) -> int:
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
	blocker[i] = 0
	next_tile[i] = -1
	path_version[i] = -1
	burn_dps[i] = 0.0
	burn_until[i] = 0
	spawned += 1
	_cells_valid = false
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
	var candidates := _candidates(x, y, max_range)
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
	for i in _candidates(x, y, radius):
		if health[i] > 0.0 and _body_distance(i, x, y) <= radius:
			out.append(i)


## Кандидаты рядом с точкой: все враги, если их мало, иначе — из списков тайлов в квадрате радиуса.
func _candidates(x: float, y: float, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var t := float(GameConst.TILE_SIZE)
	var span := ceili(radius / t) + 1
	if count <= (span * 2 + 1) * (span * 2 + 1):
		result.resize(count)
		for i in count:
			result[i] = i
		return result
	if not _cells_valid:
		rebuild_cells()
	var grid := _world.grid
	var w := grid.width
	var h := grid.height
	var tx := int(x / t)
	var ty := int(y / t)
	for cy in range(maxi(ty - span, 0), mini(ty + span, h - 1) + 1):
		for cx in range(maxi(tx - span, 0), mini(tx + span, w - 1) + 1):
			var j := _cell_head[cy * w + cx]
			while j >= 0:
				if j < count:
					result.append(j)
				j = _cell_next[j]
	return result


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
		blocker[i] = blocker[last]
		next_tile[i] = next_tile[last]
		path_version[i] = path_version[last]
		burn_dps[i] = burn_dps[last]
		burn_until[i] = burn_until[last]
	count -= 1
	_cells_valid = false


func clear() -> void:
	count = 0
	_cells_valid = false


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
		var block := 0
		# Внутри твёрдой постройки (её поставили поверх врага) — бьём её, но выйти можно.
		if blocked[tile] == FlowField.SOLID:
			block = ids[tile]
		if has_goal:
			var vx := goal_x - x
			var vy := goal_y - y
			var length := sqrt(vx * vx + vy * vy)
			if length > 0.5:
				vx /= length
				vy /= length
				facing[i] = atan2(vy, vx)
				var step := _speed[type]
				var nx := clampf(x + vx * step, 0.5, max_x)
				var ny := clampf(y + vy * step, 0.5, max_y)
				var lt := _tile_at(nx + vx * radius, ny + vy * radius, w, h, inv_t)
				if lt < 0 or lt == tile or blocked[lt] == FlowField.OPEN:
					x = nx
					y = ny
				else:
					var ahead_building := blocked[lt] == FlowField.SOLID
					var path_blocked := nt >= 0 and blocked[nt] != FlowField.OPEN
					if ahead_building and (path_blocked or nt < 0):
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
			tg = _find_target(x, y, type, drone_ok, drone, grid, manager)
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


func _find_target(x: float, y: float, type: int, drone_ok: bool, drone: Drone, grid: WorldGrid, manager: BuildingManager) -> int:
	var reach := _reach[type]
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
		blocker[i] = s_blocker[j]
		next_tile[i] = s_next[j]
		path_version[i] = s_version[j]
		burn_dps[i] = s_burn_dps[j] if j < s_burn_dps.size() else 0.0
		burn_until[i] = s_burn_until[j] if j < s_burn_until.size() else 0
