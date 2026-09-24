class_name PadOverlay
extends Node2D
## Граница площадки центрального шлюза и рамки развёрнутых платформ добычи: пунктир и лёгкая заливка.
## Всё, что стоит на площадке, переезжает вместе с базой; остальное на планете теряется при телепорте.
## Платформа добычи — такой же переносимый кусок: её содержимое уезжает обратно в комнату.
## Перерисовывается, когда площадка расширяется исследованием (GameWorld.bounds_changed),
## и каждый раз, когда платформа разворачивается или сворачивается.

const COLOR := Color(0.51, 0.65, 0.6)
const PLATFORM_COLOR := Color(0.62, 0.72, 0.42)
const DASH := 12.0

var _rect: Rect2 = Rect2()
var _world: GameWorld
## Рамки развёрнутых платформ, пиксели мира.
var _platforms: Array[Rect2] = []
var _signature: String = ""


func setup(world: GameWorld) -> void:
	z_index = 2
	_world = world
	var t := float(GameConst.TILE_SIZE)
	_rect = Rect2(Vector2(world.pad_rect.position) * t, Vector2(world.pad_rect.size) * t)
	_refresh_platforms()
	visible = _rect.size != Vector2.ZERO or not _platforms.is_empty()
	queue_redraw()


func _process(_delta: float) -> void:
	# Платформы разворачиваются редко, поэтому следим за дешёвой подписью, а не перерисовываем всё.
	_refresh_platforms()


## Где сейчас стоят платформы этого мира. true — состав изменился.
func _refresh_platforms() -> void:
	var run := _world.run if _world != null else null
	if run == null:
		return
	var rects: Array[Rect2] = []
	var signature := ""
	var t := float(GameConst.TILE_SIZE)
	if _world == run.planet:
		for console in run.platform_consoles():
			if not console.is_deployed():
				continue
			var tiles := run.platform_target_rect(console.deployed_at)
			rects.append(Rect2(Vector2(tiles.position) * t, Vector2(tiles.size) * t))
			signature += "%d:%s;" % [console.room, console.deployed_at]
	elif _world == run.base:
		# В комнате рамка показывает, что именно уедет на планету (и куда вернётся).
		for room in run.get_mining_rooms():
			var tiles := Registry.base_def.platform_rect(room)
			rects.append(Rect2(Vector2(tiles.position) * t, Vector2(tiles.size) * t))
			signature += "room%d;" % room
	if signature == _signature:
		return
	_signature = signature
	_platforms = rects
	visible = _rect.size != Vector2.ZERO or not _platforms.is_empty()
	queue_redraw()


func _draw() -> void:
	if _rect.size != Vector2.ZERO:
		_frame(_rect, COLOR)
	for rect in _platforms:
		_frame(rect, PLATFORM_COLOR)


func _frame(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(color, 0.06), true)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		_dashed(corners[i], corners[(i + 1) % 4], color)
	# Уголки плотнее — рамку видно издалека.
	for i in 4:
		var c: Vector2 = corners[i]
		var to_next: Vector2 = (corners[(i + 1) % 4] - c).normalized() * 28.0
		var to_prev: Vector2 = (corners[(i + 3) % 4] - c).normalized() * 28.0
		draw_line(c, c + to_next, Color(color, 0.95), 4.0)
		draw_line(c, c + to_prev, Color(color, 0.95), 4.0)


func _dashed(from: Vector2, to: Vector2, color: Color = COLOR) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var pos := 0.0
	while pos < length:
		var end := minf(pos + DASH, length)
		draw_line(from + dir * pos, from + dir * end, Color(color, 0.7), 2.0)
		pos += DASH * 2.0
