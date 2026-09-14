class_name ProjectileSystem
extends RefCounted
## Снаряды мира — плоские массивы. Турели и дрон их выпускают, враги получают урон.
##
## Пуля летит прямо и попадает в первого врага на отрезке пути за тик (без «пролёта» сквозь тонких).
## Снаряд артиллерии летит в точку и взрывается там, задевая всех в радиусе; по пути никого не бьёт.
## Урон наносится через EnemySystem.hurt — погибшие убираются в конце тика (Simulation.step).

enum Kind { BULLET, SHELL }

const GROW := 128
## Запас к радиусу врага при попадании пулей, пикселей.
const HIT_PADDING := 2.0
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

var fired: int = 0
var hits: int = 0
## Вспышки попаданий и взрывов для отрисовки (не сохраняются).
var blasts := PackedFloat32Array()
var blast_colors := PackedInt32Array()
var blast_cursor: int = 0
var last_blast_tick: int = -1000

var _world: GameWorld
var _capacity: int = 0
var _candidates := PackedInt32Array()


func _init(world: GameWorld) -> void:
	_world = world
	blasts.resize(BLAST_CAPACITY * BLAST_STRIDE)
	blasts.fill(-1.0)
	blast_colors.resize(BLAST_CAPACITY)


func dispose() -> void:
	_world = null


func spawn_bullet(from: Vector2, velocity: Vector2, p_damage: float, p_life: int, p_color: Color) -> void:
	var i := _add(Kind.BULLET, from, velocity, p_damage, 0.0, p_life, p_color)
	flight[i] = p_life


## Снаряд прилетит в точку to за ticks тиков и взорвётся с радиусом splash_px.
func spawn_shell(from: Vector2, to: Vector2, ticks: int, p_damage: float, splash_px: float, p_color: Color) -> void:
	var t := maxi(ticks, 1)
	var i := _add(Kind.SHELL, from, (to - from) / t, p_damage, splash_px, t, p_color)
	flight[i] = t


func clear() -> void:
	count = 0


func update(tick: int) -> void:
	if count == 0:
		return
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
				enemies.hurt(hit, damage[i])
				hits += 1
				_push_blast(enemies.pos_x[hit], enemies.pos_y[hit], 0.0, tick, color[i])
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
	_push_blast(pos_x[i], pos_y[i], splash[i], tick, color[i])
	if enemies.count == 0:
		return
	_candidates.clear()
	enemies.query_circle(pos_x[i], pos_y[i], splash[i], _candidates)
	for j in _candidates:
		enemies.hurt(j, damage[i])
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
	fired += 1
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
	count -= 1


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


# --- Сохранение ---

func save_data() -> Dictionary:
	return {"count": count, "fired": fired, "hits": hits,
		"kind": kind.slice(0, count), "pos_x": pos_x.slice(0, count), "pos_y": pos_y.slice(0, count),
		"prev_x": prev_x.slice(0, count), "prev_y": prev_y.slice(0, count),
		"vel_x": vel_x.slice(0, count), "vel_y": vel_y.slice(0, count),
		"damage": damage.slice(0, count), "splash": splash.slice(0, count),
		"life": life.slice(0, count), "flight": flight.slice(0, count), "color": color.slice(0, count)}


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
	fired = saved_fired
