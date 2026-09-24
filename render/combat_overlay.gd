class_name CombatOverlay
extends Node2D
## Бой поверх мира: полоски прочности повреждённых зданий и раненых врагов, вспышки атак
## (выстрел — трассер, ближний бой — искры), обломки разрушенных построек и выпавший груз дрона,
## снаряды турелей и дрона (пуля — штрих, снаряд артиллерии — шар по дуге), попадания, взрывы и гибель врагов.
## Перерисовывается каждый кадр, только пока есть что показывать.

const BAR_HEIGHT := 4.0
## Сколько тиков видна вспышка атаки.
const EVENT_TICKS := 4
## Сколько секунд видны обломки.
## Сколько тиков живёт луч на экране.
const BEAM_TICKS := 6
const DEBRIS_SECONDS := 0.7
## Сколько тиков видны взрывы и гибель врагов.
const BLAST_TICKS := 10
const DEATH_TICKS := 12
const CRATE_COLOR := Color(0.98, 0.74, 0.18)

var _world: GameWorld
var _camera: CameraController
var _clock: SimClock
var _debris: Array[Dictionary] = []
var _time: float = 0.0
var _had_content: bool = false


func setup(world: GameWorld, camera: CameraController, clock: SimClock) -> void:
	_world = world
	_camera = camera
	_clock = clock
	z_index = 4
	world.building_destroyed.connect(_on_building_destroyed)


func _process(delta: float) -> void:
	if _world == null or _world.buildings == null:
		return
	_time += delta
	for i in range(_debris.size() - 1, -1, -1):
		_debris[i]["age"] = float(_debris[i]["age"]) + delta
		if float(_debris[i]["age"]) >= DEBRIS_SECONDS:
			_debris.remove_at(i)
	var tick := _world.simulation.tick
	var has_content := not _world.damaged.is_empty() or _world.enemies.count > 0 or not _debris.is_empty() \
		or not _world.crates.is_empty() or _world.projectiles.count > 0 \
		or tick - _world.projectiles.last_blast_tick <= BLAST_TICKS or tick - _world.enemies.last_death_tick <= DEATH_TICKS
	if tick - _world.projectiles.last_beam_tick <= BEAM_TICKS:
		has_content = true
	if has_content or _had_content:
		queue_redraw()
	_had_content = has_content


func _draw() -> void:
	if _world == null or _world.buildings == null:
		return
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 2)
	_draw_crates(view)
	_draw_debris()
	_draw_deaths(view)
	_draw_events(view)
	_draw_projectiles(view)
	_draw_blasts(view)
	_draw_beams(view)
	_draw_burning(view)
	if _camera.user_zoom >= 0.3:
		_draw_building_bars(view)
		_draw_enemy_bars(view)


func _draw_building_bars(view: Rect2) -> void:
	for id in _world.damaged:
		var b := _world.buildings.get_by_id(id)
		if b == null:
			continue
		var rect := b.get_world_rect()
		if not view.intersects(rect):
			continue
		var fraction := clampf(b.health / b.get_max_health(), 0.0, 1.0)
		var bar := Rect2(rect.position + Vector2(3, -BAR_HEIGHT - 3), Vector2(rect.size.x - 6, BAR_HEIGHT))
		_draw_bar(bar, fraction)


func _draw_enemy_bars(view: Rect2) -> void:
	var sys := _world.enemies
	var alpha := _clock.alpha
	for i in sys.count:
		var def := Registry.enemies[sys.types[i]]
		if sys.health[i] >= def.health:
			continue
		var x := lerpf(sys.prev_x[i], sys.pos_x[i], alpha)
		var y := lerpf(sys.prev_y[i], sys.pos_y[i], alpha)
		if not view.has_point(Vector2(x, y)):
			continue
		var width := def.draw_size * 0.9
		_draw_bar(Rect2(x - width * 0.5, y - def.draw_size * 0.5 - 6.0, width, 3.0), clampf(sys.health[i] / def.health, 0.0, 1.0))


static func bar_color(fraction: float) -> Color:
	if fraction > 0.6:
		return UiTheme.GREEN
	if fraction > 0.3:
		return UiTheme.YELLOW
	return UiTheme.RED


func _draw_bar(bar: Rect2, fraction: float) -> void:
	draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), bar_color(fraction), true)


func _draw_events(view: Rect2) -> void:
	var sys := _world.enemies
	var tick := _world.simulation.tick
	var events := sys.events
	for k in EnemySystem.EVENT_CAPACITY:
		var o := k * EnemySystem.EVENT_STRIDE
		var at := events[o + 4]
		if at < 0.0 or tick - int(at) >= EVENT_TICKS:
			continue
		var from := Vector2(events[o], events[o + 1])
		var to := Vector2(events[o + 2], events[o + 3])
		if not view.has_point(to) and not view.has_point(from):
			continue
		var fade := 1.0 - float(tick - int(at)) / EVENT_TICKS
		if int(events[o + 5]) == EnemySystem.EventKind.SHOT:
			draw_line(from, to, Color(1.0, 0.55, 0.2, 0.85 * fade), 2.0)
			draw_circle(to, 3.0 * fade + 1.0, Color(1.0, 0.85, 0.4, fade))
		else:
			var base := fmod(to.x * 0.37 + to.y * 0.11, TAU)
			for s in 4:
				var dir := Vector2.from_angle(base + s * PI * 0.5)
				draw_line(to + dir * 2.0, to + dir * (4.0 + 5.0 * (1.0 - fade)), Color(1.0, 0.4, 0.3, fade), 2.0)


func _draw_projectiles(view: Rect2) -> void:
	var sys := _world.projectiles
	var alpha := _clock.alpha
	for i in sys.count:
		var x := lerpf(sys.prev_x[i], sys.pos_x[i], alpha)
		var y := lerpf(sys.prev_y[i], sys.pos_y[i], alpha)
		if not view.has_point(Vector2(x, y)):
			continue
		var col := ProjectileSystem.color_of(sys.color[i])
		if sys.kind[i] == ProjectileSystem.Kind.BULLET:
			var tail := Vector2(sys.vel_x[i], sys.vel_y[i]) * 0.6
			draw_line(Vector2(x, y) - tail, Vector2(x, y), Color(col, 0.95), 2.5)
		else:
			# Снаряд летит по дуге: тень на земле и шар над ней.
			var total := maxf(sys.flight[i], 1.0)
			var progress := clampf(1.0 - (float(sys.life[i]) - alpha) / total, 0.0, 1.0)
			var height := sin(progress * PI) * minf(total * 1.2, 36.0)
			draw_circle(Vector2(x, y), 3.5, Color(0, 0, 0, 0.35))
			draw_circle(Vector2(x, y - height), 5.0, Color(0.11, 0.13, 0.13))
			draw_circle(Vector2(x, y - height), 3.5, col.lightened(0.2))


## Горящие враги: язычки пламени над телом.
func _draw_burning(view: Rect2) -> void:
	var sys := _world.enemies
	var tick := _world.simulation.tick
	var alpha := _clock.alpha
	for i in sys.count:
		if not sys.is_burning(i, tick):
			continue
		var p := Vector2(lerpf(sys.prev_x[i], sys.pos_x[i], alpha), lerpf(sys.prev_y[i], sys.pos_y[i], alpha))
		if not view.has_point(p):
			continue
		var r := sys.get_radius(i)
		for k in 3:
			var phase := _time * 9.0 + k * 2.1 + i
			var offset := Vector2(sin(phase) * r * 0.6, -r * 0.4 - absf(cos(phase * 0.7)) * r * 0.8)
			draw_circle(p + offset, 2.5 + sin(phase * 1.3), Color(1.0, 0.55 + 0.25 * sin(phase), 0.1, 0.85))


## Лучи турелей: молния бьёт цепью, ремонтный луч тянется к постройке.
func _draw_beams(view: Rect2) -> void:
	var sys := _world.projectiles
	var tick := _world.simulation.tick
	for k in ProjectileSystem.BEAM_CAPACITY:
		var o := k * ProjectileSystem.BEAM_STRIDE
		var at := sys.beams[o + 4]
		var age := tick - int(at)
		if at < 0.0 or age < 0 or age >= BEAM_TICKS:
			continue
		var from := Vector2(sys.beams[o], sys.beams[o + 1])
		var to := Vector2(sys.beams[o + 2], sys.beams[o + 3])
		if not view.intersects(Rect2(from, Vector2.ZERO).expand(to)):
			continue
		var fade := 1.0 - float(age) / BEAM_TICKS
		var color := ProjectileSystem.color_of(int(sys.beams[o + 5]))
		draw_line(from, to, Color(color, 0.85 * fade), 3.0 * fade + 1.0)
		draw_line(from, to, Color(color.lightened(0.5), 0.9 * fade), 1.0)


func _draw_blasts(view: Rect2) -> void:
	var sys := _world.projectiles
	var tick := _world.simulation.tick
	for k in ProjectileSystem.BLAST_CAPACITY:
		var o := k * ProjectileSystem.BLAST_STRIDE
		var at := sys.blasts[o + 3]
		if at < 0.0 or tick - int(at) > BLAST_TICKS:
			continue
		var p := Vector2(sys.blasts[o], sys.blasts[o + 1])
		if not view.has_point(p):
			continue
		var t := float(tick - int(at)) / BLAST_TICKS
		var col := ProjectileSystem.color_of(sys.blast_colors[k])
		var radius := sys.blasts[o + 2]
		if radius > 0.0:
			draw_circle(p, radius * (0.4 + 0.6 * t), Color(col, 0.35 * (1.0 - t)))
			draw_arc(p, radius * (0.5 + 0.5 * t), 0.0, TAU, 32, Color(col.lightened(0.3), 0.9 * (1.0 - t)), 3.0)
		else:
			draw_circle(p, 5.0 * (1.0 - t) + 1.0, Color(col.lightened(0.5), 0.9 * (1.0 - t)))


func _draw_deaths(view: Rect2) -> void:
	var sys := _world.enemies
	var tick := _world.simulation.tick
	for k in EnemySystem.DEATH_CAPACITY:
		var o := k * EnemySystem.DEATH_STRIDE
		var at := sys.deaths[o + 2]
		if at < 0.0 or tick - int(at) > DEATH_TICKS:
			continue
		var p := Vector2(sys.deaths[o], sys.deaths[o + 1])
		if not view.has_point(p):
			continue
		var t := float(tick - int(at)) / DEATH_TICKS
		var type := clampi(int(sys.deaths[o + 3]), 0, Registry.enemies.size() - 1)
		var def := Registry.enemies[type]
		var size := def.draw_size * 0.5
		draw_circle(p, size * (0.6 + 0.8 * t), Color(def.color.lightened(0.3), 0.55 * (1.0 - t)))
		for s in 5:
			var dir := Vector2.from_angle(s * TAU / 5.0 + p.x * 0.01)
			draw_rect(Rect2(p + dir * size * (0.3 + 1.4 * t) - Vector2(2, 2), Vector2(4, 4)), Color(def.color.darkened(0.3), 1.0 - t), true)


func _draw_debris() -> void:
	for d in _debris:
		var rect: Rect2 = d["rect"]
		var t := float(d["age"]) / DEBRIS_SECONDS
		var col := Color(0.99, 0.5, 0.1, 0.6 * (1.0 - t))
		draw_rect(rect.grow(t * 10.0), col, false, 3.0)
		var center := rect.get_center()
		var seed_value: int = d["seed"]
		for s in 6:
			var angle := float(PlaceholderArt.hash3(seed_value, s, 3) % 628) / 100.0
			var dist := (6.0 + float(PlaceholderArt.hash3(seed_value, s, 7) % 10)) * (0.4 + t * 1.6)
			var p := center + Vector2.from_angle(angle) * dist * (rect.size.x / GameConst.TILE_SIZE)
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.3, 0.28, 0.25, 1.0 - t), true)


func _draw_crates(view: Rect2) -> void:
	for crate in _world.crates:
		if not view.has_point(crate.position):
			continue
		var bob := sin(_time * 3.0 + crate.position.x * 0.01) * 2.0
		var c := crate.position + Vector2(0, bob)
		var r := Rect2(c - Vector2(9, 8), Vector2(18, 16))
		draw_circle(crate.position + Vector2(2, 10), 8.0, Color(0, 0, 0, 0.3))
		draw_rect(r.grow(2.0), Color(0.11, 0.13, 0.13), true)
		draw_rect(r, CRATE_COLOR.darkened(0.25), true)
		draw_line(r.position, r.end, CRATE_COLOR.darkened(0.55), 2.0)
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), CRATE_COLOR.darkened(0.55), 2.0)
		draw_rect(r, CRATE_COLOR, false, 2.0)
		# Маяк над грузом — видно издалека.
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_line(c + Vector2(0, -10), c + Vector2(0, -24), Color(CRATE_COLOR, 0.35 + 0.4 * pulse), 2.0)
		draw_circle(c + Vector2(0, -26), 3.0 + pulse, Color(CRATE_COLOR, 0.8))


func _on_building_destroyed(_def: BuildingDef, rect: Rect2i) -> void:
	var t := float(GameConst.TILE_SIZE)
	_debris.append({"rect": Rect2(Vector2(rect.position) * t, Vector2(rect.size) * t), "age": 0.0,
		"seed": rect.position.x * 73 + rect.position.y * 151})
