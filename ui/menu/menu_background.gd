class_name MenuBackground
extends SubViewportContainer
## Фон главного меню: настоящая работающая фабрика (MenuWorld), над которой медленно летает
## камера — пролёт, как в заставке Factorio. Мир живёт своей жизнью: ленты едут, печи плавят,
## генераторы жгут уголь.
##
## Мир крутится в отдельном SubViewport со своей камерой: обычная Camera2D двигала бы вместе
## с миром и сам интерфейс меню, ведь кнопки живут в том же окне.
## Отключается настройкой graphics/menu_background — тогда меню рисует статичную карту.

## Масштаб камеры: от дальнего к ближнему и обратно.
const ZOOM_NEAR := 2.1
const ZOOM_FAR := 1.55
## Насколько завод смещён вправо от центра экрана (доля видимой ширины): слева его закрывают кнопки.
const SIDE_BIAS := 0.12
## Скорости пролёта, оборотов в секунду: полный проход по оси — полторы-две минуты.
## Числа несоразмерны, поэтому путь не повторяется по кругу.
const SPEED_X := 0.012
const SPEED_Y := 0.0083
const SPEED_ZOOM := 0.0071
## Сколько тиков фабрика проживает до показа: к появлению меню ленты уже полны.
const WARMUP_TICKS := 2400

var scene: MenuWorld
var camera: CameraController
var clock: SimClock

var _view: WorldView
var _viewport: SubViewport
var _time: float = 0.0


func setup(p_seed: int) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.name = "MenuViewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Свой ввод фону не нужен: по миру никто не кликает, а меню не должно терять события.
	_viewport.gui_disable_input = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)

	scene = MenuWorld.new(p_seed)
	for i in WARMUP_TICKS:
		scene.step()

	clock = SimClock.new()
	clock.name = "MenuClock"
	clock.setup(scene.step)
	_viewport.add_child(clock)

	camera = CameraController.new()
	camera.name = "MenuCamera"
	camera.input_enabled = false
	camera.follow_source = _flyover_point
	_viewport.add_child(camera)
	camera.setup(scene.world.get_play_rect_px())
	camera.set_zoom_level(ZOOM_FAR)
	camera.make_current()

	_view = WorldView.new()
	_view.name = "MenuWorldView"
	_viewport.add_child(_view)
	_view.setup(scene.world, camera, clock)
	# Сетка на фоне ни к чему: она делит картинку на клетки и спорит с текстом меню.
	_view.grid_overlay.visible = false


func _process(delta: float) -> void:
	_time += delta
	if camera != null:
		camera.set_zoom_level(lerpf(ZOOM_FAR, ZOOM_NEAR, 0.5 + 0.5 * sin(_time * SPEED_ZOOM * TAU)))


func _exit_tree() -> void:
	if scene != null:
		scene.dispose()
		scene = null


## Куда смотрит камера: медленный овал над заводом. Радиусы — всё, что остаётся от завода
## за вычетом видимой области, поэтому пустой край почти не попадает в кадр.
func _flyover_point() -> Vector2:
	var rect: Rect2 = scene.factory_rect
	var view := Vector2.ZERO
	if camera != null and camera.is_inside_tree():
		view = camera.get_world_view_rect().size
	# Минимум пары десятков пикселей: даже когда завод уже целиком в кадре, картинка должна дышать.
	var radius := ((rect.size - view) * 0.5).maxf(28.0)
	var center := rect.get_center() - Vector2(view.x * SIDE_BIAS, 0.0)
	return center + Vector2(sin(_time * SPEED_X * TAU) * radius.x,
		sin(_time * SPEED_Y * TAU + 1.3) * radius.y)
