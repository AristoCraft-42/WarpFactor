class_name CameraController
extends Camera2D
## Камера: панорама перетаскиванием (СКМ), клавишами и краем экрана, зум колесом к курсору.
## Пользовательский масштаб user_zoom не зависит от масштаба интерфейса:
## content_scale_factor корневого окна компенсируется делением.

## Камера сдвинулась или изменила масштаб.
signal view_changed

const KEY_PAN_SPEED := 900.0
const EDGE_PAN_MARGIN := 6.0
const ZOOM_STEP := 1.15

var input_enabled: bool = true
var user_zoom: float = 1.0
## Точка, куда возвращает действие cam_home (ядро уровня).
var home_target: Vector2 = Vector2.ZERO

var _map_size_px: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0
var _zoom_anchor: Vector2 = Vector2.ZERO
var _panning: bool = false
var _last_position: Vector2 = Vector2.INF
var _last_zoom: float = -1.0
## Последняя позиция курсора из событий ввода (координаты viewport).
var _mouse_screen: Vector2 = Vector2.ZERO
var _has_mouse: bool = false


func setup(map_size_px: Vector2) -> void:
	_map_size_px = map_size_px
	Settings.changed.connect(_on_setting_changed)
	_apply_zoom_property()


func focus_on(world_pos: Vector2, zoom_value: float = -1.0) -> void:
	position = world_pos
	if zoom_value > 0.0:
		user_zoom = clampf(zoom_value, GameConst.ZOOM_MIN, GameConst.ZOOM_MAX)
		_target_zoom = user_zoom
		_apply_zoom_property()
	_clamp_position()


## Видимая область в мировых координатах.
func get_world_view_rect() -> Rect2:
	var size := get_viewport().get_visible_rect().size / zoom
	return Rect2(position - size * 0.5, size)


## Позиция экранной точки (в координатах viewport) в мире.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	return position + (screen_pos - viewport_size * 0.5) / zoom


## Позиция курсора в координатах viewport. Берётся из событий мыши, а не из системного курсора:
## так она корректна и во встроенном окне редактора, и при симулированном вводе.
func get_mouse_screen() -> Vector2:
	return _mouse_screen if _has_mouse else get_viewport().get_mouse_position()


func get_mouse_world() -> Vector2:
	return screen_to_world(get_mouse_screen())


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("zoom_in", true):
		_zoom_by(ZOOM_STEP, event)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_out", true):
		_zoom_by(1.0 / ZOOM_STEP, event)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cam_pan"):
		_panning = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cam_home"):
		get_viewport().set_input_as_handled()
		focus_on(home_target)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = (event as InputEventMouse).position
		_has_mouse = true
	# Перетаскивание обрабатываем в _input, чтобы оно не прерывалось над панелями интерфейса.
	if not _panning:
		return
	if event is InputEventMouseMotion:
		position -= (event as InputEventMouseMotion).relative / zoom
		_clamp_position()
	elif event.is_action_released("cam_pan"):
		_panning = false


func _process(delta: float) -> void:
	if _panning and not Input.is_action_pressed("cam_pan"):
		_panning = false

	if input_enabled:
		var dir := Vector2(
			Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"),
			Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up"))
		if dir == Vector2.ZERO and Settings.get_bool(&"game/edge_pan") and not _panning:
			dir = _edge_direction()
		if dir != Vector2.ZERO:
			position += dir.limit_length(1.0) * KEY_PAN_SPEED * Settings.get_float(&"game/pan_speed") * delta / user_zoom
			_clamp_position()

	if not is_equal_approx(user_zoom, _target_zoom):
		if Settings.get_bool(&"game/smooth_zoom"):
			var k := 1.0 - exp(-delta * 18.0)
			var next := lerpf(user_zoom, _target_zoom, k)
			if absf(next - _target_zoom) < 0.0005:
				next = _target_zoom
			_set_zoom_keep_anchor(next, _zoom_anchor)
		else:
			_set_zoom_keep_anchor(_target_zoom, _zoom_anchor)

	if position != _last_position or not is_equal_approx(zoom.x, _last_zoom):
		_last_position = position
		_last_zoom = zoom.x
		view_changed.emit()


func _zoom_by(factor: float, event: InputEvent) -> void:
	var speed := Settings.get_float(&"game/zoom_speed")
	var effective := pow(factor, speed)
	_target_zoom = clampf(_target_zoom * effective, GameConst.ZOOM_MIN, GameConst.ZOOM_MAX)
	if event is InputEventMouse:
		_zoom_anchor = (event as InputEventMouse).position
	else:
		_zoom_anchor = get_viewport().get_visible_rect().size * 0.5
	if not Settings.get_bool(&"game/smooth_zoom"):
		_set_zoom_keep_anchor(_target_zoom, _zoom_anchor)


func _set_zoom_keep_anchor(new_zoom: float, anchor: Vector2) -> void:
	var before := screen_to_world(anchor)
	user_zoom = new_zoom
	_apply_zoom_property()
	var after := screen_to_world(anchor)
	position += before - after
	_clamp_position()


func _apply_zoom_property() -> void:
	var ui_scale := maxf(get_tree().root.content_scale_factor, 0.01)
	zoom = Vector2.ONE * (user_zoom / ui_scale)


func _edge_direction() -> Vector2:
	var window := get_window()
	if window == null or not window.has_focus():
		return Vector2.ZERO
	var size := get_viewport().get_visible_rect().size
	var mouse := get_mouse_screen()
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > size.x or mouse.y > size.y:
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if mouse.x <= EDGE_PAN_MARGIN:
		dir.x = -1.0
	elif mouse.x >= size.x - EDGE_PAN_MARGIN:
		dir.x = 1.0
	if mouse.y <= EDGE_PAN_MARGIN:
		dir.y = -1.0
	elif mouse.y >= size.y - EDGE_PAN_MARGIN:
		dir.y = 1.0
	return dir


func _clamp_position() -> void:
	if _map_size_px == Vector2.ZERO:
		return
	position = position.clamp(Vector2.ZERO, _map_size_px)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_has_mouse = false


func _on_setting_changed(key: StringName) -> void:
	if key == &"game/ui_scale":
		_apply_zoom_property()
