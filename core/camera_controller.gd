class_name CameraController
extends Camera2D
## Камера следует за дроном (follow_source). Перетаскивание СКМ временно смещает взгляд;
## когда дрон снова летит, смещение плавно возвращается к нулю, cam_home сбрасывает его сразу.
## Зум колесом к курсору. Пользовательский масштаб user_zoom не зависит от масштаба интерфейса:
## content_scale_factor корневого окна компенсируется делением.

## Камера сдвинулась или изменила масштаб.
signal view_changed

const ZOOM_STEP := 1.15
## Скорость возврата смещённого взгляда к дрону, пока он движется.
const RECENTER_SPEED := 2.5

var input_enabled: bool = true
var user_zoom: float = 1.0
## Источник точки слежения: Callable() -> Vector2. Пусто — камера смотрит от начала карты.
var follow_source: Callable
## Смещение взгляда от точки слежения (пиксели мира).
var look_offset: Vector2 = Vector2.ZERO

## Границы взгляда в пикселях мира (открытая часть карты); size 0 — без ограничений.
var _bounds_px: Rect2 = Rect2()
var _target_zoom: float = 1.0
var _zoom_anchor: Vector2 = Vector2.ZERO
var _panning: bool = false
var _anchor_point: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.INF
var _last_zoom: float = -1.0
## Последняя позиция курсора из событий ввода (координаты viewport).
var _mouse_screen: Vector2 = Vector2.ZERO
var _has_mouse: bool = false


func setup(bounds_px: Rect2) -> void:
	_bounds_px = bounds_px
	Settings.changed.connect(_on_setting_changed)
	_apply_zoom_property()


## Смена мира: новые границы карты, взгляд возвращается к дрону.
func set_map_size(bounds_px: Rect2) -> void:
	_bounds_px = bounds_px
	look_offset = Vector2.ZERO
	_anchor_point = _follow_point()
	_apply_position()


## Показать точку мира (смещением взгляда от дрона) и, при необходимости, задать масштаб.
func focus_on(world_pos: Vector2, zoom_value: float = -1.0) -> void:
	if zoom_value > 0.0:
		user_zoom = clampf(zoom_value, GameConst.ZOOM_MIN, GameConst.ZOOM_MAX)
		_target_zoom = user_zoom
		_apply_zoom_property()
	look_offset = world_pos - _follow_point()
	_apply_position()


## Вернуть взгляд на дрона.
func recenter() -> void:
	look_offset = Vector2.ZERO
	_apply_position()


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
		recenter()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = (event as InputEventMouse).position
		_has_mouse = true
	# Перетаскивание обрабатываем в _input, чтобы оно не прерывалось над панелями интерфейса.
	if not _panning:
		return
	if event is InputEventMouseMotion:
		look_offset -= (event as InputEventMouseMotion).relative / zoom
		_apply_position()
	elif event.is_action_released("cam_pan"):
		_panning = false


func _process(delta: float) -> void:
	if _panning and not Input.is_action_pressed("cam_pan"):
		_panning = false
	var follow := _follow_point()
	# Дрон полетел — смещённый взгляд плавно возвращается к нему.
	if follow.distance_squared_to(_anchor_point) > 0.01 and not _panning and look_offset != Vector2.ZERO:
		look_offset = look_offset.lerp(Vector2.ZERO, 1.0 - exp(-delta * RECENTER_SPEED))
		if look_offset.length_squared() < 1.0:
			look_offset = Vector2.ZERO
	_anchor_point = follow
	_apply_position()
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


func _follow_point() -> Vector2:
	if follow_source.is_valid():
		return follow_source.call()
	return Vector2.ZERO


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
	look_offset += before - after
	_apply_position()


func _apply_zoom_property() -> void:
	var ui_scale := maxf(get_tree().root.content_scale_factor, 0.01)
	zoom = Vector2.ONE * (user_zoom / ui_scale)


## Позиция = точка слежения + смещение. Видимая область не выходит за границы карты (смещение подрезается
## вместе с ней); если карта меньше экрана по оси — камера по этой оси стоит в центре карты.
func _apply_position() -> void:
	var follow := _follow_point()
	var wanted := follow + look_offset
	if _bounds_px.size != Vector2.ZERO:
		var half := get_viewport().get_visible_rect().size / zoom * 0.5
		var local := wanted - _bounds_px.position
		wanted = _bounds_px.position + Vector2(clamp_axis(local.x, half.x, _bounds_px.size.x), clamp_axis(local.y, half.y, _bounds_px.size.y))
	position = wanted
	look_offset = wanted - follow


## Центр взгляда по оси: половина видимой области half, длина карты extent.
static func clamp_axis(value: float, half: float, extent: float) -> float:
	if half * 2.0 >= extent:
		return extent * 0.5
	return clampf(value, half, extent - half)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_has_mouse = false


func _on_setting_changed(key: StringName) -> void:
	if key == &"game/ui_scale":
		_apply_zoom_property()
