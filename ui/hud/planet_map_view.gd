class_name PlanetMapView
extends Control
## Планета «со спутника» для пульта платформы: пиксель на тайл, руды прямо в картинке,
## поверх — площадка базы, уже развёрнутые платформы, точки появления врагов и рамка наводки.
## Картинка собирается один раз на планету (MapPreview) и перестраивается, когда планета меняется.

signal tile_picked(tile: Vector2i)

const PAD_COLOR := Color(0.36, 0.67, 0.85, 0.9)
const PLATFORM_COLOR := Color(0.45, 0.78, 0.4, 0.9)
const SPAWN_COLOR := Color(0.9, 0.3, 0.25, 0.85)
const AIM_OK := Color(0.98, 0.86, 0.3)
const AIM_BAD := Color(0.95, 0.35, 0.28)

## Куда целится игрок (центр платформы, тайлы) и помещается ли она туда.
var aim: Vector2i = Vector2i.ZERO
var aim_ok: bool = true

var _run: Run
var _texture: ImageTexture
var _built_for: GameWorld
var _built_tick: int = -1


func setup(run: Run) -> void:
	_run = run
	custom_minimum_size = Vector2(560, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Пересобрать картинку планеты (новая планета или расчищенная площадка).
func refresh() -> void:
	if _run == null or _run.planet == null:
		return
	var grid := _run.planet.grid
	var image := MapPreview.build_terrain_image(grid.width, grid.height, grid.floors, grid.ores)
	_texture = ImageTexture.create_from_image(image)
	_built_for = _run.planet
	_built_tick = _run.planet.simulation.tick
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _run == null:
		return
	if _texture == null or _built_for != _run.planet:
		refresh()
	queue_redraw()


## Прямоугольник карты внутри контрола: планета вписана целиком, пропорции сохранены.
func map_rect() -> Rect2:
	if _run == null or _run.planet == null:
		return Rect2(Vector2.ZERO, size)
	var grid := _run.planet.grid
	var scale := minf(size.x / float(grid.width), size.y / float(grid.height))
	var box := Vector2(grid.width, grid.height) * scale
	return Rect2((size - box) * 0.5, box)


func tile_at(pos: Vector2) -> Vector2i:
	var rect := map_rect()
	if rect.size.x <= 0.0 or _run == null:
		return Vector2i.ZERO
	var grid := _run.planet.grid
	var local := (pos - rect.position) / rect.size
	return Vector2i(clampi(floori(local.x * grid.width), 0, grid.width - 1),
		clampi(floori(local.y * grid.height), 0, grid.height - 1))


## Прямоугольник тайлов в координатах контрола.
func rect_of(tiles: Rect2i) -> Rect2:
	var rect := map_rect()
	if _run == null or _run.planet == null:
		return Rect2()
	var grid := _run.planet.grid
	var unit := rect.size / Vector2(grid.width, grid.height)
	return Rect2(rect.position + Vector2(tiles.position) * unit, Vector2(tiles.size) * unit)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		tile_picked.emit(tile_at(click.position))
		accept_event()


func _draw() -> void:
	var rect := map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.BG_HARD, 0.95))
	if _texture == null or _run == null:
		return
	draw_texture_rect(_texture, rect, false)
	if _run.planet.pad_rect.size != Vector2i.ZERO:
		draw_rect(rect_of(_run.planet.pad_rect), PAD_COLOR, false, 2.0)
	for tile in _run.planet.spawn_points:
		var spot := rect_of(Rect2i(tile, Vector2i.ONE)).grow(2.0)
		draw_rect(spot, SPAWN_COLOR, true)
	for console in _run.platform_consoles():
		if console.is_deployed():
			draw_rect(rect_of(_run.platform_target_rect(console.deployed_at)), PLATFORM_COLOR, false, 2.0)
	var frame := rect_of(_run.platform_target_rect(aim))
	draw_rect(frame, AIM_OK if aim_ok else AIM_BAD, false, 2.0)
	# Крестик в середине рамки: видно, куда именно целится платформа.
	var middle := frame.get_center()
	var arm := maxf(frame.size.x * 0.25, 4.0)
	var color := AIM_OK if aim_ok else AIM_BAD
	draw_line(middle - Vector2(arm, 0), middle + Vector2(arm, 0), color, 1.0)
	draw_line(middle - Vector2(0, arm), middle + Vector2(0, arm), color, 1.0)
