class_name DroneView
extends Node2D
## Отрисовка дрона игрока: корпус по интерполированной позиции, луч добычи с прогрессом,
## круг радиуса строительства, пока в руке постройка или план вставки.
## Плейсхолдер рисуется примитивами; спрайт из DroneDef.sprite подменяет его без правки логики.

const BODY_RADIUS := 13.0
const RANGE_COLOR := Color(0.98, 0.74, 0.18, 0.35)
const BEAM_COLOR := Color(0.99, 0.5, 0.1, 0.9)
const TURN_SPEED := 14.0

var _drone: Drone
var _clock: SimClock
var _tools: ToolController
var _angle: float = 0.0
var _time: float = 0.0


func setup(drone: Drone, clock: SimClock, tools: ToolController) -> void:
	_drone = drone
	_clock = clock
	_tools = tools
	_angle = drone.facing
	z_index = 5


func _process(delta: float) -> void:
	if _drone == null:
		return
	_time += delta
	_angle = lerp_angle(_angle, _drone.facing, 1.0 - exp(-delta * TURN_SPEED))
	queue_redraw()


func _draw() -> void:
	if _drone == null:
		return
	var pos := _drone.get_draw_position(_clock.alpha)
	if _tools != null and _tools.mode != ToolController.Mode.NONE and not _drone.world.creative:
		_draw_range(pos)
	if _drone.is_mining():
		_draw_beam(pos)
	_draw_body(pos)


func _draw_range(pos: Vector2) -> void:
	var radius := _drone.get_reach_px()
	var segments := 64
	for i in segments:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / segments + _time * 0.15
		var a1 := TAU * (i + 1) / segments + _time * 0.15
		draw_arc(pos, radius, a0, a1, 4, RANGE_COLOR, 2.0)


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


func _draw_body(pos: Vector2) -> void:
	var def := _drone.def
	draw_set_transform(pos, _angle, Vector2.ONE)
	if def.sprite != null:
		var size := def.sprite.get_size()
		draw_texture(def.sprite, -size * 0.5)
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
			shadow.append(p + Vector2(3, 3).rotated(-_angle))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
		draw_colored_polygon(hull, def.color.darkened(0.15))
		var outline := hull.duplicate()
		outline.append(hull[0])
		draw_polyline(outline, def.color.lightened(0.35), 2.0)
		draw_circle(Vector2(r * 0.15, 0), 3.5, Color(0.2, 0.9, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
