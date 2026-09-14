class_name SpawnMarkers
extends Node2D
## Точки появления врагов на опасной планете: красная зона у края карты. Перед волной и во время
## появления зона пульсирует, чтобы было видно, откуда пойдут враги.

const RADIUS := 2.2
const COLOR := Color(0.98, 0.29, 0.2)

var _world: GameWorld
var _time: float = 0.0


func setup(world: GameWorld) -> void:
	_world = world
	z_index = 1
	visible = not world.spawn_points.is_empty()


func _process(delta: float) -> void:
	if _world == null or _world.spawn_points.is_empty():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _world == null or _world.simulation == null:
		return
	var threat := _world.threat
	var tick := _world.simulation.tick
	var alert := threat != null and (threat.is_warning(tick) or threat.is_spawning(tick))
	var t := float(GameConst.TILE_SIZE)
	var pulse := 0.5 + 0.5 * sin(_time * (6.0 if alert else 2.0))
	for p in _world.spawn_points:
		var c := Vector2(p) * t + Vector2.ONE * t * 0.5
		var r := RADIUS * t
		draw_circle(c, r, Color(COLOR, (0.10 + 0.12 * pulse) if alert else 0.06))
		var segments := 24
		for i in segments:
			if i % 2 == 1:
				continue
			var a0 := TAU * i / segments + _time * 0.3
			draw_arc(c, r, a0, a0 + TAU / segments, 4, Color(COLOR, 0.9 if alert else 0.45), 3.0 if alert else 2.0)
		# Знак опасности: треугольник с восклицательным знаком.
		var tri := PackedVector2Array([c + Vector2(0, -13), c + Vector2(12, 9), c + Vector2(-12, 9)])
		draw_colored_polygon(tri, Color(COLOR, 0.55 + 0.35 * pulse if alert else 0.4))
		draw_line(c + Vector2(0, -5), c + Vector2(0, 2), Color(0.11, 0.13, 0.13), 3.0)
		draw_circle(c + Vector2(0, 6), 1.8, Color(0.11, 0.13, 0.13))
