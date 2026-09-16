class_name TurretView
extends Node2D
## Стволы турелей (поворачиваются, поэтому рисуются каждый кадр поверх основания из атласа зданий),
## вспышка выстрела и радиусы стрельбы. Радиусы всех турелей — по переключателю (оверлей радиусов).

const RANGE_COLOR := Color(0.98, 0.29, 0.2)
const MIN_RANGE_COLOR := Color(0.51, 0.65, 0.6)

## Показать радиусы всех турелей мира.
var show_ranges: bool = false:
	set(value):
		show_ranges = value
		queue_redraw()

var _world: GameWorld
var _camera: CameraController
var _had_content: bool = false


func setup(world: GameWorld, camera: CameraController) -> void:
	_world = world
	_camera = camera
	z_index = 3


func _process(_delta: float) -> void:
	if _world == null:
		return
	# Перерисовка и в кадре, когда турелей не стало: иначе на экране остаётся последний рисунок стволов.
	var has_content := not _world.turrets.is_empty() or show_ranges
	if has_content or _had_content:
		queue_redraw()
	_had_content = has_content


func _draw() -> void:
	if _world == null or _world.simulation == null:
		return
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 3)
	var tick := _world.simulation.tick
	for id in _world.turrets:
		var turret := _world.turrets[id]
		var d := turret.get_turret_def()
		var center := turret.get_world_center()
		if show_ranges and view.grow(d.get_range_px()).has_point(center):
			draw_range(self, d, center, 0.5)
		if not view.has_point(center):
			continue
		_draw_head(turret, d, center, tick)


## Круг дальности (и мёртвой зоны артиллерии).
static func draw_range(canvas: CanvasItem, d: TurretDef, center: Vector2, strength: float = 1.0) -> void:
	var r := d.get_range_px()
	canvas.draw_circle(center, r, Color(RANGE_COLOR, 0.05 * strength), true)
	canvas.draw_arc(center, r, 0.0, TAU, 96, Color(RANGE_COLOR, 0.8 * strength), 2.0)
	if d.min_range > 0.0:
		canvas.draw_arc(center, d.get_min_range_px(), 0.0, TAU, 48, Color(MIN_RANGE_COLOR, 0.7 * strength), 2.0)


func _draw_head(turret: Turret, d: TurretDef, center: Vector2, tick: int) -> void:
	var dir := Vector2.from_angle(turret.angle)
	var side := Vector2(-dir.y, dir.x)
	var body := d.color
	var recoil := 0.0
	var since := tick - turret.last_shot_tick
	if since < 4:
		recoil = (4 - since) * (1.2 if d.artillery else 0.6)
	var base := center - dir * recoil
	if d.artillery:
		draw_line(base, base + dir * (d.barrel_length + 1.0), Color(0.11, 0.13, 0.13), 10.0)
		draw_line(base, base + dir * d.barrel_length, body.lightened(0.35), 6.0)
		draw_circle(base, 11.0, Color(0.11, 0.13, 0.13))
		draw_circle(base, 9.0, body.lightened(0.2))
		draw_circle(base - dir * 2.0, 4.0, body.darkened(0.3))
	else:
		for k in [-1.0, 1.0]:
			var offset: Vector2 = side * 3.5 * k
			draw_line(base + offset, base + offset + dir * (d.barrel_length + 1.5), Color(0.11, 0.13, 0.13), 5.0)
			draw_line(base + offset, base + offset + dir * d.barrel_length, body.lightened(0.45), 2.5)
		draw_circle(base, 9.0, Color(0.11, 0.13, 0.13))
		draw_circle(base, 7.0, body.lightened(0.25))
		draw_circle(base, 2.5, body.darkened(0.4))
	if turret.get_status() == Building.Status.NO_AMMO:
		draw_circle(center + Vector2(9, -9) * d.size, 3.5, Color(0.98, 0.29, 0.2, 0.9))
	if since < 3:
		var muzzle := center + dir * (d.barrel_length + 3.0)
		var ammo := turret.get_current_ammo()
		var flash := ammo.color if ammo != null else Color(1.0, 0.8, 0.3)
		draw_circle(muzzle, (6.0 if d.artillery else 3.5) * (3 - since) / 3.0 + 1.0, Color(flash.lightened(0.4), 0.9))
