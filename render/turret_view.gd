class_name TurretView
extends Node2D
## Стволы турелей (поворачиваются, поэтому рисуются поверх основания из атласа зданий),
## вспышка выстрела и радиусы стрельбы. Радиусы всех турелей — по переключателю (оверлей радиусов).
##
## Турели рисуются участками (CELL × CELL тайлов) — у каждого участка свой холст. Перерисовывается
## только участок, у которого что-то поменялось (повернулся ствол, выстрел, статус), и только
## пока он на экране: остальные хранят прошлую картинку. Полёт камеры ничего не перерисовывает —
## картинка лежит в мировых координатах.
##
## Сама перерисовка дешёвая: круглые части — одна белая текстура-круг, покрашенная в нужный цвет
## (такие прямоугольники склеиваются в один вызов отрисовки), стволы — одной командой линий.
## Многоугольники вместо этого разбивались на треугольники поштучно, и 400 турелей в бою
## стоили 40 мс на перерисовку.

const RANGE_COLOR := Color(0.98, 0.29, 0.2)
const MIN_RANGE_COLOR := Color(0.51, 0.65, 0.6)
## Ниже этого масштаба головы турелей не рисуются: на экране они меньше пикселя.
const MIN_ZOOM := 0.45
## Сторона участка, тайлов: меньше участок — меньше лишнего перерисовывается в бою.
const CELL := 8
## Сторона текстуры круга, пикселей.
const DISC_TEXTURE := 32

## Показать радиусы всех турелей мира.
var show_ranges: bool = false:
	set(value):
		show_ranges = value
		_ranges_dirty = true

## Для замеров: сколько длилась отрисовка и сколько раз рисовали (сбрасывает тот, кто меряет).
var last_draw_usec: int = 0
var redraws: int = 0

var _world: GameWorld
var _camera: CameraController
## Участки: ключ участка → холст.
var _cells: Dictionary[int, TurretCell] = {}
var _ranges: Node2D
var _ranges_dirty: bool = true
var _had_ranges: bool = false
var _heads_visible: bool = true
## Набор турелей поменялся — участки надо разложить заново.
var _cells_dirty: bool = true
## Текстура круга — своя у слоя, а не общая статическая: статическая переменная переживала
## видеосистему и при выходе из игры освобождалась уже без неё (падение на выходе).
var _disc: Texture2D


func setup(world: GameWorld, camera: CameraController) -> void:
	_world = world
	_camera = camera
	z_index = 3
	_ranges = Node2D.new()
	_ranges.name = "Ranges"
	_ranges.draw.connect(_draw_ranges)
	add_child(_ranges)
	camera.view_changed.connect(_on_view_changed)
	world.buildings.building_added.connect(_on_building_changed)
	world.buildings.building_removed.connect(_on_building_changed)


func _on_building_changed(building: Building) -> void:
	if building is Turret:
		_cells_dirty = true
		_ranges_dirty = true


## Белый круг с мягким краем: им рисуются все головы, дула и вспышки.
func disc_texture() -> Texture2D:
	if _disc != null:
		return _disc
	var img := Image.create_empty(DISC_TEXTURE, DISC_TEXTURE, false, Image.FORMAT_RGBA8)
	var half := DISC_TEXTURE * 0.5
	for y in DISC_TEXTURE:
		for x in DISC_TEXTURE:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(half - d, 0.0, 1.0)))
	_disc = ImageTexture.create_from_image(img)
	return _disc


func _on_view_changed() -> void:
	# Масштаб мог перейти порог, ниже которого головы не рисуются; радиусы рисуются по видимой
	# области, их обновляем только когда они включены.
	var heads := _camera.user_zoom >= MIN_ZOOM
	if heads != _heads_visible:
		_heads_visible = heads
		for key in _cells:
			_cells[key].signature = INF
	if show_ranges:
		_ranges_dirty = true


func _process(_delta: float) -> void:
	if _world == null or _world.simulation == null:
		return
	_sync_cells()
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 3)
	var tick := _world.simulation.tick
	for key in _cells:
		var cell := _cells[key]
		if not view.intersects(cell.rect):
			continue
		var signature := _signature_of(cell, tick)
		if not is_equal_approx(signature, cell.signature):
			cell.signature = signature
			cell.queue_redraw()
	var has_ranges := show_ranges and not _world.turrets.is_empty()
	if has_ranges != _had_ranges:
		_had_ranges = has_ranges
		_ranges_dirty = true
	if _ranges_dirty:
		_ranges_dirty = false
		_ranges.queue_redraw()


## Разложить турели по участкам: участок появляется с первой турелью и пропадает с последней.
## Раскладка пересчитывается только когда турель поставили или снесли.
func _sync_cells() -> void:
	if not _cells_dirty:
		return
	_cells_dirty = false
	for key in _cells:
		_cells[key].turrets.clear()
	for id in _world.turrets:
		var turret: Turret = _world.turrets[id]
		var tile := turret.origin
		var coords := Vector2i(floori(float(tile.x) / CELL), floori(float(tile.y) / CELL))
		var key := coords.y * 65536 + coords.x
		var cell: TurretCell = _cells.get(key)
		if cell == null:
			cell = TurretCell.new()
			cell.view = self
			cell.rect = Rect2(Vector2(coords * CELL * GameConst.TILE_SIZE), Vector2.ONE * CELL * GameConst.TILE_SIZE)
			_cells[key] = cell
			add_child(cell)
		cell.turrets.append(turret)
		cell.signature = INF
	for key in _cells.keys():
		var cell := _cells[key]
		if cell.turrets.is_empty():
			_cells.erase(key)
			cell.queue_free()


## Всё, от чего зависит картинка участка: углы стволов, статусы, вспышки выстрела.
func _signature_of(cell: TurretCell, tick: int) -> float:
	var sum := 0.0
	for turret in cell.turrets:
		sum += turret.angle + float(turret.get_status()) * 0.37
		# Вспышка живёт три тика — эти тики картинка меняется каждый кадр.
		if tick - turret.last_shot_tick < 4:
			sum += float(tick) * 0.11
	return sum


## Нарисовать турели участка на его холсте.
func draw_cell(cell: TurretCell) -> void:
	if _world == null or _world.simulation == null or not _heads_visible:
		return
	var started := Time.get_ticks_usec()
	redraws += 1
	var tick := _world.simulation.tick
	cell.lines.clear()
	cell.line_colors.clear()
	cell.disc_rects.clear()
	cell.disc_colors.clear()
	for turret in cell.turrets:
		if turret.world == _world:
			_collect_head(cell, turret, turret.get_turret_def(), turret.center(), tick)
	if not cell.lines.is_empty():
		cell.draw_multiline_colors(cell.lines, cell.line_colors, 2.5)
	var disc := disc_texture()
	for k in cell.disc_colors.size():
		var r := cell.disc_rects[k]
		cell.draw_texture_rect(disc, Rect2(r.x - r.z, r.y - r.z, r.z * 2.0, r.z * 2.0), false, cell.disc_colors[k])
	last_draw_usec += Time.get_ticks_usec() - started


func _draw_ranges() -> void:
	if not show_ranges or _world == null:
		return
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 3)
	for id in _world.turrets:
		var turret: Turret = _world.turrets[id]
		var d := turret.get_turret_def()
		var center := turret.center()
		if view.grow(d.get_range_px()).has_point(center):
			draw_range(_ranges, d, center, 0.5)


## Круг дальности (и мёртвой зоны артиллерии).
static func draw_range(canvas: CanvasItem, d: TurretDef, center: Vector2, strength: float = 1.0) -> void:
	var r := d.get_range_px()
	canvas.draw_circle(center, r, Color(RANGE_COLOR, 0.05 * strength), true)
	canvas.draw_arc(center, r, 0.0, TAU, 48, Color(RANGE_COLOR, 0.8 * strength), 2.0)
	if d.min_range > 0.0:
		canvas.draw_arc(center, d.get_min_range_px(), 0.0, TAU, 32, Color(MIN_RANGE_COLOR, 0.7 * strength), 2.0)


## Стволы турели — в буфер линий участка, круглые части — в буфер кругов, которые рисуются следом.
func _collect_head(cell: TurretCell, turret: Turret, d: TurretDef, center: Vector2, tick: int) -> void:
	var dir := Vector2.from_angle(turret.angle)
	var side := Vector2(-dir.y, dir.x)
	var body := d.color
	var recoil := 0.0
	var since := tick - turret.last_shot_tick
	if since < 4:
		recoil = (4 - since) * (1.2 if d.artillery else 0.6)
	var base := center - dir * recoil
	var dark := Color(0.11, 0.13, 0.13)
	if d.artillery:
		cell.add_line(base, base + dir * (d.barrel_length + 1.0), dark)
		cell.add_line(base, base + dir * d.barrel_length, body.lightened(0.35))
		cell.add_disc(base, 11.0, dark)
		cell.add_disc(base, 9.0, body.lightened(0.2))
		cell.add_disc(base - dir * 2.0, 4.0, body.darkened(0.3))
	elif d.kind != TurretDef.Kind.BULLET:
		# Молния, ремонт и полив: один излучатель вместо пары стволов.
		cell.add_line(base, base + dir * (d.barrel_length + 1.5), dark)
		cell.add_line(base, base + dir * d.barrel_length, body.lightened(0.5))
		cell.add_disc(base, 9.5, dark)
		cell.add_disc(base, 7.5, body.lightened(0.2))
		cell.add_disc(base + dir * d.barrel_length, 3.0, body.lightened(0.6))
	else:
		for k in [-1.0, 1.0]:
			var offset: Vector2 = side * 3.5 * k
			cell.add_line(base + offset, base + offset + dir * (d.barrel_length + 1.5), dark)
			cell.add_line(base + offset, base + offset + dir * d.barrel_length, body.lightened(0.45))
		cell.add_disc(base, 9.0, dark)
		cell.add_disc(base, 7.0, body.lightened(0.25))
		cell.add_disc(base, 2.5, body.darkened(0.4))
	if d.kind == TurretDef.Kind.BULLET and turret.get_status() == Building.Status.NO_AMMO:
		cell.add_disc(center + Vector2(9, -9) * d.size, 3.5, Color(0.98, 0.29, 0.2, 0.9))
	if since < 3:
		var muzzle := center + dir * (d.barrel_length + 3.0)
		var ammo := turret.get_current_ammo()
		var flash := ammo.color if ammo != null else Color(1.0, 0.8, 0.3)
		var size := (6.0 if d.artillery else 3.5) * (3 - since) / 3.0 + 1.0
		cell.add_disc(muzzle, size, Color(flash.lightened(0.4), 0.9))


## Холст одного участка: хранит свои турели и прошлую подпись картинки.
class TurretCell extends Node2D:
	var view: TurretView
	var rect: Rect2
	var turrets: Array[Turret] = []
	var signature: float = INF
	var lines := PackedVector2Array()
	var line_colors := PackedColorArray()
	## Круги: x, y — середина, z — радиус.
	var disc_rects := PackedVector3Array()
	var disc_colors := PackedColorArray()

	func add_line(from: Vector2, to: Vector2, color: Color) -> void:
		lines.append(from)
		lines.append(to)
		line_colors.append(color)

	func add_disc(at: Vector2, radius: float, color: Color) -> void:
		disc_rects.append(Vector3(at.x, at.y, radius))
		disc_colors.append(color)

	func _draw() -> void:
		if view != null:
			view.draw_cell(self)
