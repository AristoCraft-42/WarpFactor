class_name AttackIndicator
extends Control
## Тревога при атаке на постройки планеты: уведомление (не чаще раза в ALERT_COOLDOWN секунд)
## и красная стрелка у края экрана в сторону атаки, пока место атаки за пределами видимой области.
## Атаку на сам шлюз объявляет панель угрозы.
##
## Кроме того — маленькие стрелки в стороны врагов, которых не видно на экране: направления
## разложены по SECTORS секторам, у каждой стрелки подпись с числом врагов в её стороне.

const ALERT_COOLDOWN := 20.0
## Сколько тиков после атаки видна стрелка.
const SHOW_TICKS := 90
const MARGIN := 48.0
## На сколько секторов делится круг для стрелок к врагам.
const SECTORS := 16
## Врагов дальше этого расстояния (в тайлах) стрелки не показывают.
const ENEMY_RANGE_TILES := 120.0

var _game: Game
var _seen_tick: int = -1000000
var _cooldown: float = 0.0
var _tracked: GameWorld
var _time: float = 0.0


func setup(game: Game) -> void:
	_game = game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	var planet := _game.run.planet if _game.run != null else null
	if planet == null or planet.simulation == null:
		return
	if planet != _tracked:
		_tracked = planet
		_seen_tick = planet.last_attack_tick
	if planet.last_attack_tick > _seen_tick:
		_seen_tick = planet.last_attack_tick
		if not planet.last_attack_gateway and _cooldown <= 0.0:
			_cooldown = ALERT_COOLDOWN
			Events.toast(tr("TOAST_BUILDINGS_ATTACKED"), Events.ToastKind.WARNING)
	queue_redraw()


func _draw() -> void:
	var planet := _tracked
	if planet == null or planet.simulation == null or _game.world != planet:
		return
	_draw_enemy_arrows(planet)
	if planet.simulation.tick - planet.last_attack_tick > SHOW_TICKS:
		return
	var camera := _game.camera
	var viewport_size := get_viewport_rect().size
	var screen := (planet.last_attack_position - camera.position) * camera.zoom + viewport_size * 0.5
	var inner := Rect2(Vector2.ZERO, viewport_size).grow(-MARGIN)
	# Окно меньше полей (headless, свёрнутое окно) — рисовать не по чему.
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	if inner.has_point(screen):
		return
	var center := viewport_size * 0.5
	var dir := (screen - center).normalized()
	# Точка на рамке inner по направлению к месту атаки.
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, (inner.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (inner.size.y * 0.5) / absf(dir.y))
	var tip := center + dir * t
	var side := Vector2(-dir.y, dir.x)
	var pulse := 0.7 + 0.3 * sin(_time * 10.0)
	var arrow := PackedVector2Array([tip + dir * 14.0, tip - dir * 10.0 + side * 13.0, tip - dir * 4.0, tip - dir * 10.0 - side * 13.0])
	draw_colored_polygon(arrow, Color(0.11, 0.13, 0.13, 0.8))
	draw_colored_polygon(PackedVector2Array([tip + dir * 10.0, tip - dir * 7.0 + side * 9.0, tip - dir * 2.0, tip - dir * 7.0 - side * 9.0]),
		Color(UiTheme.RED, pulse))


## Маленькие стрелки к врагам за пределами экрана: по одной на сектор, с числом врагов.
## Направление считается от середины экрана (а не от дрона — камера может смотреть в сторону)
## и усредняется по врагам сектора, иначе стрелка показывала в сторону границы сектора,
## где никого нет, и выглядела «криво».
func _draw_enemy_arrows(planet: GameWorld) -> void:
	var enemies := planet.enemies
	if enemies == null or enemies.count == 0:
		return
	var camera := _game.camera
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var inner := Rect2(Vector2.ZERO, viewport_size).grow(-MARGIN)
	# Окно меньше полей (headless, свёрнутое окно) — рисовать не по чему.
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var origin := camera.position
	var max_distance := ENEMY_RANGE_TILES * GameConst.TILE_SIZE
	var counts := PackedInt32Array()
	counts.resize(SECTORS)
	counts.fill(0)
	var nearest := PackedFloat32Array()
	nearest.resize(SECTORS)
	nearest.fill(max_distance)
	var sum_x := PackedFloat32Array()
	var sum_y := PackedFloat32Array()
	sum_x.resize(SECTORS)
	sum_y.resize(SECTORS)
	sum_x.fill(0.0)
	sum_y.fill(0.0)
	for i in enemies.count:
		var world_pos := Vector2(enemies.pos_x[i], enemies.pos_y[i])
		var screen := (world_pos - camera.position) * camera.zoom + center
		if inner.has_point(screen):
			continue
		var offset := world_pos - origin
		var distance := offset.length()
		if distance > max_distance or distance < 1.0:
			continue
		var sector := posmod(roundi(offset.angle() / TAU * SECTORS), SECTORS)
		counts[sector] += 1
		nearest[sector] = minf(nearest[sector], distance)
		var dir := offset / distance
		sum_x[sector] += dir.x
		sum_y[sector] += dir.y
	var font := ThemeDB.fallback_font
	for sector in SECTORS:
		if counts[sector] == 0:
			continue
		var dir := Vector2(sum_x[sector], sum_y[sector]).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT.rotated(TAU * sector / SECTORS)
		var t := INF
		if absf(dir.x) > 0.001:
			t = minf(t, (inner.size.x * 0.5) / absf(dir.x))
		if absf(dir.y) > 0.001:
			t = minf(t, (inner.size.y * 0.5) / absf(dir.y))
		var tip := center + dir * t
		var side := Vector2(-dir.y, dir.x)
		# Чем ближе враги, тем ярче и крупнее стрелка.
		var closeness := clampf(1.0 - nearest[sector] / max_distance, 0.0, 1.0)
		var alpha := 0.35 + 0.5 * closeness
		var length := 7.0 + 4.0 * closeness
		draw_colored_polygon(PackedVector2Array([tip + dir * length, tip - dir * 5.0 + side * 5.0, tip - dir * 5.0 - side * 5.0]),
			Color(UiTheme.RED, alpha))
		if counts[sector] > 1 and font != null:
			var label := str(counts[sector])
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			# Подпись уводится внутрь экрана вдоль той же стрелки, поэтому не налезает на рамку.
			var at := tip - dir * 18.0 - Vector2(width * 0.5, -4.0)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, alpha))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTheme.RED, minf(alpha + 0.2, 1.0)))
