class_name PadOverlay
extends Node2D
## Граница площадки центрального шлюза: пунктирная рамка и лёгкая заливка.
## Всё, что стоит на площадке, переезжает вместе с базой; остальное на планете теряется при телепорте.
## Перерисовывается, когда площадка расширяется исследованием (GameWorld.bounds_changed).

const COLOR := Color(0.51, 0.65, 0.6)
const DASH := 12.0

var _rect: Rect2 = Rect2()


func setup(world: GameWorld) -> void:
	z_index = 2
	visible = world.pad_rect.size != Vector2i.ZERO
	if not visible:
		return
	var t := float(GameConst.TILE_SIZE)
	_rect = Rect2(Vector2(world.pad_rect.position) * t, Vector2(world.pad_rect.size) * t)
	queue_redraw()


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return
	draw_rect(_rect, Color(COLOR, 0.06), true)
	var corners := [_rect.position, Vector2(_rect.end.x, _rect.position.y), _rect.end, Vector2(_rect.position.x, _rect.end.y)]
	for i in 4:
		_dashed(corners[i], corners[(i + 1) % 4])
	# Уголки плотнее — площадку видно издалека.
	for i in 4:
		var c: Vector2 = corners[i]
		var to_next: Vector2 = (corners[(i + 1) % 4] - c).normalized() * 28.0
		var to_prev: Vector2 = (corners[(i + 3) % 4] - c).normalized() * 28.0
		draw_line(c, c + to_next, Color(COLOR, 0.95), 4.0)
		draw_line(c, c + to_prev, Color(COLOR, 0.95), 4.0)


func _dashed(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var pos := 0.0
	while pos < length:
		var end := minf(pos + DASH, length)
		draw_line(from + dir * pos, from + dir * end, Color(COLOR, 0.7), 2.0)
		pos += DASH * 2.0
