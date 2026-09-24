class_name TurretView
extends Node2D
## Стволы турелей (поворачиваются, поэтому рисуются поверх основания из атласа зданий),
## вспышка выстрела и радиусы стрельбы. Радиусы всех турелей — по переключателю (оверлей радиусов).
##
## Рисуется не каждый кадр, а только когда картинка меняется: повернулся ствол, кто-то выстрелил,
## сменился статус, поехала камера или включили радиусы. У базы из сотни турелей это разница
## между сотнями команд отрисовки в каждом кадре и ни одной, пока враги не пришли.
## Стволы всех турелей уходят одной командой (draw_multiline), головы — восьмиугольниками:
## draw_circle рисует десятки вершин на каждый круг, а на радиусе в семь пикселей разницы не видно.

const RANGE_COLOR := Color(0.98, 0.29, 0.2)
const MIN_RANGE_COLOR := Color(0.51, 0.65, 0.6)
## Ниже этого масштаба головы турелей не рисуются: на экране они меньше пикселя.
const MIN_ZOOM := 0.45
## Вершин в «круге» головы.
const HEAD_SIDES := 8

## Показать радиусы всех турелей мира.
var show_ranges: bool = false:
	set(value):
		show_ranges = value
		_dirty = true

var _world: GameWorld
var _camera: CameraController
var _had_content: bool = false
## Подпись картинки: по ней видно, изменилось ли что-то с прошлого кадра.
var _signature: float = INF
var _dirty: bool = true
## Буферы, чтобы не создавать массивы в каждом кадре.
var _lines := PackedVector2Array()
var _line_colors := PackedColorArray()


func setup(world: GameWorld, camera: CameraController) -> void:
	_world = world
	_camera = camera
	z_index = 3
	camera.view_changed.connect(_on_view_changed)


func _on_view_changed() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _world == null:
		return
	var has_content := not _world.turrets.is_empty() or show_ranges
	# Перерисовка и в кадре, когда турелей не стало: иначе на экране остаётся последний рисунок стволов.
	if not has_content and _had_content:
		_dirty = true
	_had_content = has_content
	if has_content:
		var signature := _current_signature()
		if not is_equal_approx(signature, _signature):
			_signature = signature
			_dirty = true
	if _dirty:
		_dirty = false
		queue_redraw()


## Всё, от чего зависит картинка: углы стволов, выстрелы и статусы.
func _current_signature() -> float:
	var sum := 0.0
	var tick := _world.simulation.tick if _world.simulation != null else 0
	for id in _world.turrets:
		var turret: Turret = _world.turrets[id]
		sum += turret.angle + float(turret.get_status()) * 0.37
		# Вспышка живёт три тика — эти тики картинка меняется каждый кадр.
		if tick - turret.last_shot_tick < 4:
			sum += float(tick) * 0.11
	return sum


func _draw() -> void:
	if _world == null or _world.simulation == null:
		return
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 3)
	var tick := _world.simulation.tick
	var heads := _camera.user_zoom >= MIN_ZOOM
	_lines.clear()
	_line_colors.clear()
	var bodies: Array[Dictionary] = []
	for id in _world.turrets:
		var turret: Turret = _world.turrets[id]
		var d := turret.get_turret_def()
		var center := turret.get_world_center()
		if show_ranges and view.grow(d.get_range_px()).has_point(center):
			draw_range(self, d, center, 0.5)
		if not heads or not view.has_point(center):
			continue
		_collect_head(turret, d, center, tick, bodies)
	if not _lines.is_empty():
		draw_multiline_colors(_lines, _line_colors, 2.5)
	for body in bodies:
		_draw_disc(body["at"], body["r"], body["color"])


## Круг дальности (и мёртвой зоны артиллерии).
static func draw_range(canvas: CanvasItem, d: TurretDef, center: Vector2, strength: float = 1.0) -> void:
	var r := d.get_range_px()
	canvas.draw_circle(center, r, Color(RANGE_COLOR, 0.05 * strength), true)
	canvas.draw_arc(center, r, 0.0, TAU, 48, Color(RANGE_COLOR, 0.8 * strength), 2.0)
	if d.min_range > 0.0:
		canvas.draw_arc(center, d.get_min_range_px(), 0.0, TAU, 32, Color(MIN_RANGE_COLOR, 0.7 * strength), 2.0)


## Стволы турели кладутся в общий буфер линий, круглые части — в список, который рисуется следом.
func _collect_head(turret: Turret, d: TurretDef, center: Vector2, tick: int, bodies: Array[Dictionary]) -> void:
	var dir := Vector2.from_angle(turret.angle)
	var side := Vector2(-dir.y, dir.x)
	var body := d.color
	var recoil := 0.0
	var since := tick - turret.last_shot_tick
	if since < 4:
		recoil = (4 - since) * (1.2 if d.artillery else 0.6)
	var base := center - dir * recoil
	if d.artillery:
		_add_line(base, base + dir * (d.barrel_length + 1.0), Color(0.11, 0.13, 0.13))
		_add_line(base, base + dir * d.barrel_length, body.lightened(0.35))
		bodies.append({"at": base, "r": 11.0, "color": Color(0.11, 0.13, 0.13)})
		bodies.append({"at": base, "r": 9.0, "color": body.lightened(0.2)})
		bodies.append({"at": base - dir * 2.0, "r": 4.0, "color": body.darkened(0.3)})
	else:
		for k in [-1.0, 1.0]:
			var offset: Vector2 = side * 3.5 * k
			_add_line(base + offset, base + offset + dir * (d.barrel_length + 1.5), Color(0.11, 0.13, 0.13))
			_add_line(base + offset, base + offset + dir * d.barrel_length, body.lightened(0.45))
		bodies.append({"at": base, "r": 9.0, "color": Color(0.11, 0.13, 0.13)})
		bodies.append({"at": base, "r": 7.0, "color": body.lightened(0.25)})
		bodies.append({"at": base, "r": 2.5, "color": body.darkened(0.4)})
	if turret.get_status() == Building.Status.NO_AMMO:
		bodies.append({"at": center + Vector2(9, -9) * d.size, "r": 3.5, "color": Color(0.98, 0.29, 0.2, 0.9)})
	if since < 3:
		var muzzle := center + dir * (d.barrel_length + 3.0)
		var ammo := turret.get_current_ammo()
		var flash := ammo.color if ammo != null else Color(1.0, 0.8, 0.3)
		var size := (6.0 if d.artillery else 3.5) * (3 - since) / 3.0 + 1.0
		bodies.append({"at": muzzle, "r": size, "color": Color(flash.lightened(0.4), 0.9)})


func _add_line(from: Vector2, to: Vector2, color: Color) -> void:
	_lines.append(from)
	_lines.append(to)
	_line_colors.append(color)


## Восьмиугольник вместо круга: у головы радиусом в несколько пикселей разницы не видно,
## а вершин втрое меньше.
func _draw_disc(at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	points.resize(HEAD_SIDES)
	for i in HEAD_SIDES:
		var angle := TAU * i / HEAD_SIDES
		points[i] = at + Vector2(cos(angle), sin(angle)) * radius
	draw_colored_polygon(points, color)
