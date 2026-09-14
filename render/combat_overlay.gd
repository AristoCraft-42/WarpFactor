class_name CombatOverlay
extends Node2D
## Бой поверх мира: полоски прочности повреждённых зданий и раненых врагов, вспышки атак
## (выстрел — трассер, ближний бой — искры), обломки разрушенных построек и выпавший груз дрона.
## Перерисовывается каждый кадр, только пока есть что показывать.

const BAR_HEIGHT := 4.0
## Сколько тиков видна вспышка атаки.
const EVENT_TICKS := 4
## Сколько секунд видны обломки.
const DEBRIS_SECONDS := 0.7
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
	var has_content := not _world.damaged.is_empty() or _world.enemies.count > 0 or not _debris.is_empty() \
		or not _world.crates.is_empty()
	if has_content or _had_content:
		queue_redraw()
	_had_content = has_content


func _draw() -> void:
	if _world == null or _world.buildings == null:
		return
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 2)
	_draw_crates(view)
	_draw_debris()
	_draw_events(view)
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
