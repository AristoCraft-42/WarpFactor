class_name DroneView
extends Node2D
## Отрисовка дронов игроков в показанном сейчас мире: корпус по интерполированной позиции,
## луч добычи с прогрессом, круг радиуса строительства (только у своего дрона, пока в руке постройка),
## полоска прочности при уроне. Сбитый дрон не рисуется; после появления мигает, пока неуязвим.
## Зелёный луч — ремонт постройки, вспышка у корпуса — выстрел автопушки.
## Чужие дроны рисуются цветом своего игрока и подписаны именем.
## Плейсхолдер рисуется примитивами; спрайт из DroneDef.sprite подменяет его без правки логики.

const BODY_RADIUS := 13.0
const RANGE_COLOR := Color(0.98, 0.74, 0.18, 0.35)
## Сколько тиков висит надпись о добыче.
const MINED_TICKS := 45
const BEAM_COLOR := Color(0.99, 0.5, 0.1, 0.9)
const TURN_SPEED := 14.0

var _run: Run
var _world: GameWorld
var _clock: SimClock
var _tools: ToolController
## Сглаженный угол корпуса по id игрока.
var _angles: Dictionary[int, float] = {}
var _time: float = 0.0
## Дрон, который рисуется прямо сейчас (у отрисовки много мелких шагов, чтобы не таскать его всюду).
var _drone: Drone


func setup(run: Run, world: GameWorld, clock: SimClock, tools: ToolController) -> void:
	_run = run
	_world = world
	_clock = clock
	_tools = tools
	z_index = 5


func set_world(world: GameWorld) -> void:
	_world = world


func _process(delta: float) -> void:
	if _run == null:
		return
	_time += delta
	for player in _run.players:
		var drone := player.drone
		if drone == null:
			continue
		var angle: float = _angles.get(player.id, drone.facing)
		_angles[player.id] = lerp_angle(angle, drone.facing, 1.0 - exp(-delta * TURN_SPEED))
	queue_redraw()


func _draw() -> void:
	if _run == null or _world == null:
		return
	for player in _run.players:
		if player.drone != null and player.drone.world == _world:
			_draw_drone(player)


func _draw_drone(player: Player) -> void:
	_drone = player.drone
	var local := player.id == _run.local_player
	if _drone.dead or _drone.world == null:
		return
	var pos := _drone.get_draw_position(_clock.alpha)
	var tick := _drone.world.simulation.tick
	if tick < _drone.invulnerable_until and fmod(_time, 0.24) < 0.12:
		return
	if _drone.health < _drone.get_max_health():
		var fraction := clampf(_drone.health / _drone.get_max_health(), 0.0, 1.0)
		var bar := Rect2(pos + Vector2(-16, BODY_RADIUS + 8), Vector2(32, 4))
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), CombatOverlay.bar_color(fraction), true)
	if local and _tools != null and _tools.mode != ToolController.Mode.NONE and not _drone.world.creative:
		_draw_range(pos)
	if _drone.is_mining():
		_draw_beam(pos)
	if local:
		_draw_mined_label()
	if _drone.is_repairing():
		_draw_repair(pos)
	_draw_body(pos, player)
	if not local:
		_draw_name(pos, player)
	var since := tick - _drone.last_gun_tick
	if since < 3:
		var muzzle := pos + Vector2.from_angle(_drone.gun_angle) * (BODY_RADIUS + 4.0)
		draw_line(pos, muzzle, Color(_drone.def.gun_color.lightened(0.2), 0.9), 2.5)
		draw_circle(muzzle, 3.5 - since, Color(_drone.def.gun_color.lightened(0.5), 0.9))


## Имя чужого игрока над дроном.
func _draw_name(pos: Vector2, player: Player) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var width := font.get_string_size(player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var at := pos + Vector2(-width * 0.5, -BODY_RADIUS - 8.0)
	draw_string_outline(font, at, player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.85))
	draw_string(font, at, player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, player.color)


func _draw_range(pos: Vector2) -> void:
	var radius := _drone.get_reach_px()
	var segments := 64
	for i in segments:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / segments + _time * 0.15
		var a1 := TAU * (i + 1) / segments + _time * 0.15
		draw_arc(pos, radius, a0, a1, 4, RANGE_COLOR, 2.0)


func _draw_repair(pos: Vector2) -> void:
	var building := _drone.world.buildings.get_by_id(_drone.repair_target)
	if building == null:
		return
	var rect := building.get_world_rect()
	var target := rect.get_center() + Vector2(sin(_time * 7.0), cos(_time * 5.0)) * rect.size * 0.25
	var flicker := 0.7 + 0.3 * sin(_time * 25.0)
	draw_line(pos, target, Color(0.56, 0.75, 0.49, 0.75 * flicker), 3.0)
	draw_line(pos, target, Color(0.85, 1.0, 0.8, 0.8 * flicker), 1.2)
	draw_circle(target, 4.0 * flicker, Color(0.72, 0.9, 0.6, 0.9))
	draw_rect(rect.grow(1.0), Color(0.56, 0.75, 0.49, 0.6), false, 2.0)


## Надпись «Камень ×11» над последним добытым тайлом: всплывает и гаснет за MINED_TICKS тиков.
func _draw_mined_label() -> void:
	if _drone.last_mined_item < 0 or _drone.world == null:
		return
	var age := _drone.world.simulation.tick - _drone.last_mined_tick
	if age < 0 or age >= MINED_TICKS:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var fade := 1.0 - float(age) / MINED_TICKS
	var t := float(GameConst.TILE_SIZE)
	var pos := Vector2(_drone.last_mined_tile) * t + Vector2(t * 0.5, -10.0 - 14.0 * (1.0 - fade))
	var text := "%s ×%d" % [tr(Registry.items[_drone.last_mined_item].name_key), _drone.last_mined_count]
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var at := pos - Vector2(width * 0.5, 0.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85 * fade))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.98, 0.94, 0.78, fade))


func _draw_beam(pos: Vector2) -> void:
	var t := float(GameConst.TILE_SIZE)
	var target := Vector2(_drone.mine_tile) * t + Vector2(t, t) * 0.5
	var tile_rect := Rect2(Vector2(_drone.mine_tile) * t, Vector2(t, t))
	if _drone.mine_blocked:
		draw_line(pos, target, Color(UiTheme.GRAY, 0.5), 1.5)
		draw_rect(tile_rect.grow(-2.0), Color(UiTheme.RED, 0.8), false, 2.0)
		return
	var flicker := 0.75 + 0.25 * sin(_time * 30.0)
	draw_line(pos, target, Color(BEAM_COLOR, BEAM_COLOR.a * flicker), 2.5)
	draw_circle(target, 3.0 + 1.5 * flicker, Color(1.0, 0.85, 0.4, 0.9))
	draw_rect(tile_rect.grow(-2.0), Color(BEAM_COLOR, 0.7), false, 2.0)
	# Полоска прогресса добычи над тайлом.
	var fraction := _drone.get_mine_fraction()
	var bar := Rect2(tile_rect.position + Vector2(3, -6), Vector2(t - 6, 3))
	draw_rect(bar, Color(0, 0, 0, 0.6), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), UiTheme.YELLOW, true)


func _draw_body(pos: Vector2, player: Player) -> void:
	var def := _drone.def
	var angle: float = _angles.get(player.id, _drone.facing)
	draw_set_transform(pos, angle, Vector2.ONE)
	if def.sprite != null:
		var size := def.sprite.get_size()
		draw_texture(def.sprite, -size * 0.5, player.color)
	else:
		var r := BODY_RADIUS
		var moving := _drone.move_input != Vector2.ZERO
		if moving:
			var glow := 0.6 + 0.4 * sin(_time * 40.0)
			draw_circle(Vector2(-r * 0.95, 0), 4.0 * glow + 2.0, Color(0.55, 0.75, 1.0, 0.7))
		# Тень под корпусом.
		var hull := PackedVector2Array([
			Vector2(r * 1.15, 0), Vector2(-r * 0.7, r * 0.85), Vector2(-r * 0.35, 0), Vector2(-r * 0.7, -r * 0.85)])
		var shadow := PackedVector2Array()
		for p in hull:
			shadow.append(p + Vector2(3, 3).rotated(-angle))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
		draw_colored_polygon(hull, player.color.darkened(0.15))
		var outline := hull.duplicate()
		outline.append(hull[0])
		draw_polyline(outline, player.color.lightened(0.35), 2.0)
		draw_circle(Vector2(r * 0.15, 0), 3.5, Color(0.2, 0.9, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
