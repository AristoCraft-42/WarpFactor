class_name AttackIndicator
extends Control
## Тревога при атаке на постройки планеты: уведомление (не чаще раза в ALERT_COOLDOWN секунд)
## и красная стрелка у края экрана в сторону атаки, пока место атаки за пределами видимой области.
## Атаку на сам шлюз объявляет панель угрозы.

const ALERT_COOLDOWN := 20.0
## Сколько тиков после атаки видна стрелка.
const SHOW_TICKS := 90
const MARGIN := 48.0

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
	if planet.simulation.tick - planet.last_attack_tick > SHOW_TICKS:
		return
	var camera := _game.camera
	var viewport_size := get_viewport_rect().size
	var screen := (planet.last_attack_position - camera.position) * camera.zoom + viewport_size * 0.5
	var inner := Rect2(Vector2.ZERO, viewport_size).grow(-MARGIN)
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
