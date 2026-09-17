class_name NetworkView
extends Node2D
## Сети мира поверх зданий: стыки труб и их содержимое, провода между опорами ЛЭП, зоны питания опор
## (пока в руке постройка, связанная с электричеством, или курсор над опорой) и значки питания
## у потребителей: красный — не подключён к опоре, жёлтый — энергии не хватает.

const WIRE_COLOR := Color(0.16, 0.14, 0.12)
const WIRE_LIGHT := Color(0.85, 0.65, 0.3)
const AREA_COLOR := Color(0.98, 0.74, 0.18)

## Показать зоны питания всех опор.
var show_power_areas: bool = false
## Показать подземные участки труб (в руке постройка для жидкостей).
var show_underground: bool = false
## Оверлей электросетей (P): зоны опор цветом своей сети, перегруженные сети мигают красным,
## связанные с другим этажом — со значком «⇅».
var power_overlay: bool = false

var _world: GameWorld
var _camera: CameraController
var _time: float = 0.0


func setup(world: GameWorld, camera: CameraController) -> void:
	_world = world
	_camera = camera
	z_index = 2


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if _world == null or _world.power == null or _world.fluids == null:
		return
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 8)
	_draw_pipes(view)
	if show_underground:
		_draw_underground(view)
	if power_overlay:
		_draw_network_overlay(view)
	elif show_power_areas:
		_draw_areas(view)
	_draw_wires(view)
	_draw_power_marks(view)


func _draw_pipes(view: Rect2) -> void:
	var fluids := _world.fluids
	var t := float(GameConst.TILE_SIZE)
	for id in fluids.pipes:
		var pipe := fluids.pipes[id]
		var rect := pipe.get_world_rect()
		if not view.intersects(rect):
			continue
		var center := rect.get_center()
		var body := pipe.def.color
		for side in 4:
			if not fluids.pipe_connects(pipe, side):
				continue
			var dir := Vector2(GameConst.dir_vector(side))
			var a := center + dir * 5.0
			var b := center + dir * (t * 0.5)
			draw_line(a, b, Color(0.11, 0.13, 0.13), 14.0)
			draw_line(a, b, body, 10.0)
			draw_line(a + Vector2(dir.y, -dir.x) * 3.0, b + Vector2(dir.y, -dir.x) * 3.0, body.lightened(0.25), 2.0)
		var net := fluids.get_pipe_network(pipe)
		if net != null and net.fluid >= 0 and net.capacity > 0.0:
			var fill := clampf(net.amount / net.capacity, 0.0, 1.0)
			var col := Registry.fluids[net.fluid].color
			draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(col, 0.35 + 0.65 * fill), true)


## Подземные пары — пунктир между входом и выходом, непарные подземные трубы — красная метка.
func _draw_underground(view: Rect2) -> void:
	var fluids := _world.fluids
	for id in fluids.pipes:
		var pipe := fluids.pipes[id] as UndergroundPipe
		if pipe == null:
			continue
		var partner := pipe.get_linked_partner()
		var a := pipe.get_world_center()
		if partner == null:
			if view.has_point(a):
				draw_circle(a, 5.0, Color(0.98, 0.29, 0.2, 0.9))
			continue
		if partner.id < pipe.id:
			continue
		var b := partner.get_world_center()
		if not view.has_point(a) and not view.has_point(b):
			continue
		draw_dashed_line(a, b, Color(0.11, 0.13, 0.13, 0.7), 6.0, 10.0)
		draw_dashed_line(a, b, Color(0.51, 0.65, 0.6, 0.95), 3.0, 10.0)


func _draw_wires(view: Rect2) -> void:
	for id in _world.power.poles:
		var pole := _world.power.poles[id]
		var a := pole.get_world_center() + Vector2(0, -6)
		for other in pole.get_linked_poles():
			if other.id < pole.id and other.is_linked(pole):
				continue
			var b := other.get_world_center() + Vector2(0, -6)
			if not view.has_point(a) and not view.has_point(b):
				continue
			draw_line(a, b, WIRE_COLOR, 3.0)
			draw_line(a, b, WIRE_LIGHT, 1.0)


func _draw_areas(view: Rect2) -> void:
	var t := float(GameConst.TILE_SIZE)
	for id in _world.power.poles:
		var rect := _world.power.poles[id].get_supply_rect()
		var r := Rect2(Vector2(rect.position) * t, Vector2(rect.size) * t)
		if not view.intersects(r):
			continue
		draw_rect(r, Color(AREA_COLOR, 0.07), true)
		draw_rect(r, Color(AREA_COLOR, 0.55), false, 2.0)


func _draw_network_overlay(view: Rect2) -> void:
	var t := float(GameConst.TILE_SIZE)
	var pulse := 0.55 + 0.45 * sin(_time * 5.0)
	var font := ThemeDB.fallback_font
	for net in _world.power.networks:
		var col := Color.from_hsv(fposmod(net.key * 0.618034, 1.0), 0.55, 0.95)
		var overloaded := net.demand_kw > 0.0 and net.satisfaction < 0.999
		for pole in net.poles:
			var rect := pole.get_supply_rect()
			var r := Rect2(Vector2(rect.position) * t, Vector2(rect.size) * t)
			if not view.intersects(r):
				continue
			draw_rect(r, Color(col, 0.16), true)
			if overloaded:
				draw_rect(r, Color(0.98, 0.29, 0.2, pulse), false, 3.0)
			else:
				draw_rect(r, Color(col, 0.7), false, 2.0)
		if net.poles.is_empty():
			continue
		var first := net.poles[0]
		var anchor := first.get_world_center() + Vector2(10, -14)
		if view.has_point(anchor) and font != null:
			var label := tr("WINDOW_KW_OF") % [roundi(net.demand_kw), roundi(net.capacity_kw)]
			if net.linked:
				label += "  ⇅"
			draw_string_outline(font, anchor, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, anchor, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.98, 0.29, 0.2) if overloaded else col)


func _draw_power_marks(view: Rect2) -> void:
	var pulse := 0.6 + 0.4 * sin(_time * 5.0)
	for b in _world.power.unconnected:
		if b.world != null and view.has_point(b.get_world_center()):
			_draw_bolt(b.get_world_center(), Color(0.98, 0.29, 0.2, pulse))
	for net in _world.power.networks:
		if net.satisfaction >= 0.999:
			continue
		for b in net.consumers:
			if b.power_request > 0.0 and view.has_point(b.get_world_center()):
				_draw_bolt(b.get_world_center(), Color(0.98, 0.74, 0.18, pulse))


func _draw_bolt(center: Vector2, col: Color) -> void:
	var c := center + Vector2(0, -2)
	draw_circle(c, 9.0, Color(0.11, 0.13, 0.13, 0.75))
	var bolt := PackedVector2Array([c + Vector2(1.5, -6.5), c + Vector2(-4, 1), c + Vector2(0, 1), c + Vector2(-1.5, 6.5),
		c + Vector2(4, -1), c + Vector2(0, -1)])
	draw_colored_polygon(bolt, col)
