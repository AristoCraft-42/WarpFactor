class_name ProjectileSystem
extends RefCounted
## Снаряды мира — плоские массивы. Турели и дрон их выпускают, враги получают урон.
##
## Пуля летит прямо и попадает в первого врага на отрезке пути за тик (без «пролёта» сквозь тонких);
## у пули может быть взрыв при попадании (осколочный патрон) и поджог (зажигательный).
## Снаряд артиллерии летит в точку и взрывается там, задевая всех в радиусе; по пути никого не бьёт.
## Урон наносится через EnemySystem.hurt — погибшие убираются в конце тика (Simulation.step).

enum Kind { BULLET, SHELL }

const GROW := 128
## Запас к радиусу врага при попадании пулей, пикселей.
const HIT_PADDING := 2.0
## Лучи (молния тесла-турели, ремонтный луч): кольцевой буфер отрезков для отрисовки.
## На симуляцию не влияют — это только картинка, но живут они в системе снарядов,
## чтобы отрисовке было где их взять.
const BEAM_CAPACITY := 64
const BEAM_STRIDE := 6

const BLAST_CAPACITY := 64
## x, y, радиус, тик; цвет — в blast_colors.
const BLAST_STRIDE := 4

var count: int = 0
var kind := PackedByteArray()
var pos_x := PackedFloat32Array()
var pos_y := PackedFloat32Array()
var prev_x := PackedFloat32Array()
var prev_y := PackedFloat32Array()
var vel_x := PackedFloat32Array()
var vel_y := PackedFloat32Array()
var damage := PackedFloat32Array()
var splash := PackedFloat32Array()
var life := PackedInt32Array()
## Полное время полёта (для дуги снаряда на рисунке).
var flight := PackedInt32Array()
var color := PackedInt32Array()
## Горение, накладываемое попаданием: урон в секунду и длительность в тиках.
var burn_dps := PackedFloat32Array()
var burn_ticks := PackedInt32Array()

var fired: int = 0
var hits: int = 0
## Вспышки попаданий и взрывов для отрисовки (не сохраняются).
## Лучи: x0, y0, x1, y1, тик, цвет (упакованный).
var beams := PackedFloat32Array()
var beam_cursor: int = 0
var last_beam_tick: int = -1000
var blasts := PackedFloat32Array()
var blast_colors := PackedInt32Array()
var blast_cursor: int = 0
var last_blast_tick: int = -1000

var _world: GameWorld
var _capacity: int = 0
var _candidates := PackedInt32Array()


func _init(world: GameWorld) -> void:
	_world = world
	beams.resize(BEAM_CAPACITY * BEAM_STRIDE)
	beams.fill(-1.0)
	blasts.resize(BLAST_CAPACITY * BLAST_STRIDE)
	blasts.fill(-1.0)
	blast_colors.resize(BLAST_CAPACITY)


func dispose() -> void:
	_world = null


func spawn_bullet(from: Vector2, velocity: Vector2, p_damage: float, p_life: int, p_color: Color) -> int:
	var i := _add(Kind.BULLET, from, velocity, p_damage, 0.0, p_life, p_color)
	flight[i] = p_life
	return i


## Взрыв при попадании (радиус, пикселей) и горение для снаряда i.
func set_effects(i: int, splash_px: float, p_burn_dps: float, p_burn_ticks: int) -> void:
	splash[i] = splash_px
	burn_dps[i] = p_burn_dps
	burn_ticks[i] = p_burn_ticks


## Снаряд прилетит в точку to за ticks тиков и взорвётся с радиусом splash_px.
func spawn_shell(from: Vector2, to: Vector2, ticks: int, p_damage: float, splash_px: float, p_color: Color) -> void:
	var t := maxi(ticks, 1)
	var i := _add(Kind.SHELL, from, (to - from) / t, p_damage, splash_px, t, p_color)
	flight[i] = t


func clear() -> void:
	count = 0


## Сколько заняло обновление снарядов в прошлом тике (мкс): для бенчмарков и отладки.
var last_update_usec: int = 0


func update(tick: int) -> void:
	last_update_usec = 0
	if count == 0:
		return
	var started := Time.get_ticks_usec()
	var enemies := _world.enemies
	var size := _world.grid.get_pixel_size()
	var i := 0
	while i < count:
		var x := pos_x[i]
		var y := pos_y[i]
		prev_x[i] = x
		prev_y[i] = y
		var nx := x + vel_x[i]
		var ny := y + vel_y[i]
		life[i] -= 1
		if kind[i] == Kind.BULLET:
			var hit := _first_hit(enemies, x, y, nx, ny) if enemies.count > 0 else -1
			if hit >= 0:
				var hx := enemies.pos_x[hit]
				var hy := enemies.pos_y[hit]
				if splash[i] > 0.0:
					_explode_at(enemies, i, hx, hy, tick)
				else:
					_apply_hit(enemies, i, hit, tick)
					_push_blast(hx, hy, 0.0, tick, color[i])
					_world.sounds.push(SoundLog.Kind.HIT, Vector2(hx, hy))
				_remove(i)
				continue
			pos_x[i] = nx
			pos_y[i] = ny
			if life[i] <= 0 or nx < 0.0 or ny < 0.0 or nx > size.x or ny > size.y:
				_remove(i)
				continue
		else:
			pos_x[i] = nx
			pos_y[i] = ny
			if life[i] <= 0:
				_explode(enemies, i, tick)
				_remove(i)
				continue
		i += 1
	last_update_usec = Time.get_ticks_usec() - started


## Первый живой враг, которого задевает отрезок (x0, y0) → (x1, y1); -1 — никого.
func _first_hit(enemies: EnemySystem, x0: float, y0: float, x1: float, y1: float) -> int:
	var mx := (x0 + x1) * 0.5
	var my := (y0 + y1) * 0.5
	var dx := x1 - x0
	var dy := y1 - y0
	var length2 := dx * dx + dy * dy
	_candidates.clear()
	enemies.query_circle(mx, my, sqrt(length2) * 0.5 + HIT_PADDING, _candidates)
	var best := -1
	var best_t := INF
	for j in _candidates:
		var ex := enemies.pos_x[j] - x0
		var ey := enemies.pos_y[j] - y0
		var t := clampf((ex * dx + ey * dy) / length2, 0.0, 1.0) if length2 > 0.0 else 0.0
		var cx := ex - dx * t
		var cy := ey - dy * t
		var r := enemies.get_radius(j) + HIT_PADDING
		if cx * cx + cy * cy <= r * r and t < best_t:
			best_t = t
			best = j
	return best


func _explode(enemies: EnemySystem, i: int, tick: int) -> void:
	_explode_at(enemies, i, pos_x[i], pos_y[i], tick)


func _explode_at(enemies: EnemySystem, i: int, x: float, y: float, tick: int) -> void:
	_push_blast(x, y, splash[i], tick, color[i])
	_world.sounds.push(SoundLog.Kind.EXPLOSION, Vector2(x, y))
	if enemies.count == 0:
		return
	_candidates.clear()
	enemies.query_circle(x, y, splash[i], _candidates)
	for j in _candidates:
		_apply_hit(enemies, i, j, tick)


func _apply_hit(enemies: EnemySystem, i: int, target: int, tick: int) -> void:
	enemies.hurt(target, damage[i])
	if burn_ticks[i] > 0 and burn_dps[i] > 0.0:
		enemies.ignite(target, burn_dps[i], tick + burn_ticks[i])
	hits += 1


func _add(p_kind: Kind, from: Vector2, velocity: Vector2, p_damage: float, splash_px: float, p_life: int, p_color: Color) -> int:
	if count + 1 > _capacity:
		_capacity = maxi(count + 1, _capacity + GROW)
		kind.resize(_capacity)
		pos_x.resize(_capacity)
		pos_y.resize(_capacity)
		prev_x.resize(_capacity)
		prev_y.resize(_capacity)
		vel_x.resize(_capacity)
		vel_y.resize(_capacity)
		damage.resize(_capacity)
		splash.resize(_capacity)
		life.resize(_capacity)
		flight.resize(_capacity)
		color.resize(_capacity)
		burn_dps.resize(_capacity)
		burn_ticks.resize(_capacity)
	var i := count
	count += 1
	kind[i] = p_kind
	pos_x[i] = from.x
	pos_y[i] = from.y
	prev_x[i] = from.x
	prev_y[i] = from.y
	vel_x[i] = velocity.x
	vel_y[i] = velocity.y
	damage[i] = p_damage
	splash[i] = splash_px
	life[i] = p_life
	color[i] = p_color.to_rgba32()
	burn_dps[i] = 0.0
	burn_ticks[i] = 0
	fired += 1
	if _world != null:
		_world.sounds.push(SoundLog.Kind.SHOT if p_kind == Kind.BULLET else SoundLog.Kind.SHELL, from)
	return i


func _remove(i: int) -> void:
	var last := count - 1
	if i != last:
		kind[i] = kind[last]
		pos_x[i] = pos_x[last]
		pos_y[i] = pos_y[last]
		prev_x[i] = prev_x[last]
		prev_y[i] = prev_y[last]
		vel_x[i] = vel_x[last]
		vel_y[i] = vel_y[last]
		damage[i] = damage[last]
		splash[i] = splash[last]
		life[i] = life[last]
		flight[i] = flight[last]
		color[i] = color[last]
		burn_dps[i] = burn_dps[last]
		burn_ticks[i] = burn_ticks[last]
	count -= 1


## Показать лужу жидкости (турель полива). Только для отрисовки.
func push_splash(at: Vector2, radius: float, tick: int, color: Color) -> void:
	_push_blast(at.x, at.y, radius, tick, pack_color(color))


## Показать луч от from к to (молния, ремонт). Только для отрисовки.
func push_beam(from: Vector2, to: Vector2, tick: int, color: Color) -> void:
	var o := beam_cursor * BEAM_STRIDE
	beams[o] = from.x
	beams[o + 1] = from.y
	beams[o + 2] = to.x
	beams[o + 3] = to.y
	beams[o + 4] = float(tick)
	beams[o + 5] = float(pack_color(color))
	beam_cursor = (beam_cursor + 1) % BEAM_CAPACITY
	last_beam_tick = tick


func _push_blast(x: float, y: float, radius: float, tick: int, rgba: int) -> void:
	var o := blast_cursor * BLAST_STRIDE
	blasts[o] = x
	blasts[o + 1] = y
	blasts[o + 2] = radius
	blasts[o + 3] = tick
	blast_colors[blast_cursor] = rgba
	blast_cursor = (blast_cursor + 1) % BLAST_CAPACITY
	last_blast_tick = tick


static func color_of(rgba: int) -> Color:
	return Color.hex(rgba & 0xFFFFFFFF)


static func pack_color(color: Color) -> int:
	return int(color.to_rgba32())


# --- Сохранение ---

func save_data() -> Dictionary:
	return {"count": count, "fired": fired, "hits": hits,
		"kind": kind.slice(0, count), "pos_x": pos_x.slice(0, count), "pos_y": pos_y.slice(0, count),
		"prev_x": prev_x.slice(0, count), "prev_y": prev_y.slice(0, count),
		"vel_x": vel_x.slice(0, count), "vel_y": vel_y.slice(0, count),
		"damage": damage.slice(0, count), "splash": splash.slice(0, count),
		"life": life.slice(0, count), "flight": flight.slice(0, count), "color": color.slice(0, count),
		"burn_dps": burn_dps.slice(0, count), "burn_ticks": burn_ticks.slice(0, count)}


func load_data(data: Dictionary) -> void:
	count = 0
	fired = int(data.get("fired", 0))
	hits = int(data.get("hits", 0))
	var n := int(data.get("count", 0))
	var s_kind: PackedByteArray = data.get("kind", PackedByteArray())
	var s_px: PackedFloat32Array = data.get("pos_x", PackedFloat32Array())
	var s_py: PackedFloat32Array = data.get("pos_y", PackedFloat32Array())
	var s_prx: PackedFloat32Array = data.get("prev_x", PackedFloat32Array())
	var s_pry: PackedFloat32Array = data.get("prev_y", PackedFloat32Array())
	var s_vx: PackedFloat32Array = data.get("vel_x", PackedFloat32Array())
	var s_vy: PackedFloat32Array = data.get("vel_y", PackedFloat32Array())
	var s_damage: PackedFloat32Array = data.get("damage", PackedFloat32Array())
	var s_splash: PackedFloat32Array = data.get("splash", PackedFloat32Array())
	var s_life: PackedInt32Array = data.get("life", PackedInt32Array())
	var s_flight: PackedInt32Array = data.get("flight", PackedInt32Array())
	var s_color: PackedInt32Array = data.get("color", PackedInt32Array())
	var s_burn_dps: PackedFloat32Array = data.get("burn_dps", PackedFloat32Array())
	var s_burn_ticks: PackedInt32Array = data.get("burn_ticks", PackedInt32Array())
	for k in [s_kind.size(), s_px.size(), s_py.size(), s_prx.size(), s_pry.size(), s_vx.size(), s_vy.size(),
			s_damage.size(), s_splash.size(), s_life.size(), s_flight.size(), s_color.size()]:
		n = mini(n, k)
	var saved_fired := fired
	for j in n:
		var i := _add(s_kind[j] as Kind, Vector2(s_px[j], s_py[j]), Vector2(s_vx[j], s_vy[j]), s_damage[j], s_splash[j], s_life[j], Color.WHITE)
		prev_x[i] = s_prx[j]
		prev_y[i] = s_pry[j]
		flight[i] = s_flight[j]
		color[i] = s_color[j]
		if j < s_burn_dps.size() and j < s_burn_ticks.size():
			burn_dps[i] = s_burn_dps[j]
			burn_ticks[i] = s_burn_ticks[j]
	fired = saved_fired
