class_name ItemRenderer
extends Node2D
## Отрисовка предметов на лентах одним MultiMeshInstance2D.
## Каждый кадр обходятся только ленты видимых чанков; позиция интерполируется между тиками
## (прогресс − сдвиг за тик × (1 − alpha)), поэтому движение плавное при любом FPS и скорости.
## Предмет повёрнут по движению: при движении вправо спрайт как нарисован (как у зданий),
## на ленте вниз — на четверть оборота по часовой и т. д. Вошедший сбоку (поворот ленты, выход
## здания) доворачивается со стороны, откуда пришёл, пока съезжает к середине ленты.
## Постоянные поля буфера (нули) заполнены заранее — на предмет пишутся 7 чисел.

const ITEM_PX := 15.0
## Ниже этого масштаба предметы не рисуются (LOD).
const MIN_ZOOM := 0.4
const STRIDE := 12
const INITIAL_CAPACITY := 2048
const SHADER := preload("res://render/shaders/items.gdshader")
const HALF_PI := PI * 0.5

var drawn_count: int = 0

var _world: GameWorld
var _camera: CameraController
var _clock: SimClock
var _instance: MultiMeshInstance2D
var _multimesh: MultiMesh
var _buffer := PackedFloat32Array()
var _capacity: int = 0


func setup(world: GameWorld, camera: CameraController, clock: SimClock) -> void:
	_world = world
	_camera = camera
	_clock = clock
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	var size := world.grid.get_pixel_size()
	_multimesh.custom_aabb = AABB(Vector3(-64, -64, -1), Vector3(size.x + 128, size.y + 128, 2))
	_instance = MultiMeshInstance2D.new()
	_instance.multimesh = _multimesh
	_instance.texture = ArtRegistry.item_atlas
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("cells", float(maxi(Registry.items.size(), 1)))
	_instance.material = material
	add_child(_instance)
	_ensure_capacity(INITIAL_CAPACITY)


func _process(_delta: float) -> void:
	if _world == null:
		return
	if _camera.user_zoom < MIN_ZOOM:
		if _instance.visible:
			_instance.visible = false
		drawn_count = 0
		return
	_instance.visible = true

	var grid := _world.grid
	var manager := _world.buildings
	var sys := _world.simulation.conveyors
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE)
	var chunk_range := grid.chunk_range_for_world_rect(view)

	var counts := sys.counts
	var prog := sys.prog
	var dprog := sys.dprog
	var lat := sys.lat
	var items := sys.items
	var dirs := sys.dirs
	var tiles_x := sys.tiles_x
	var tiles_y := sys.tiles_y
	var inv_alpha := 1.0 - _clock.alpha
	var units := float(ConveyorSystem.UNITS)
	var tile := float(GameConst.TILE_SIZE)
	var half := tile * 0.5
	var cap := ConveyorSystem.CAP

	var n := 0
	for cy in range(chunk_range.position.y, chunk_range.end.y):
		for cx in range(chunk_range.position.x, chunk_range.end.x):
			for bid in manager.get_chunk_ids(cy * grid.chunks_x() + cx):
				var c := sys.index_of(bid)
				if c < 0:
					continue
				var count := counts[c]
				if count == 0:
					continue
				if n + count > _capacity:
					_ensure_capacity((n + count) * 2)
				var d := dirs[c]
				var dx := 1.0 if d == 0 else (-1.0 if d == 2 else 0.0)
				var dy := 1.0 if d == 1 else (-1.0 if d == 3 else 0.0)
				var angle := d * HALF_PI
				var center_x := tiles_x[c] * tile + half
				var center_y := tiles_y[c] * tile + half
				var base := c * cap
				for s in count:
					var k := base + s
					var p := (prog[k] - dprog[k] * inv_alpha) / units - 0.5
					var side := lat[k]
					var l := side * half
					var o := n * STRIDE
					# Поворот: оси спрайта (cos, sin) и (−sin, cos); по Y масштаб отрицательный.
					var rc := dx
					var rs := dy
					if side != 0.0:
						# Вошёл сбоку: side = 1 — пришёл с боковой стороны «по часовой» от движения,
						# то есть ехал на четверть оборота раньше; доворачивается, пока съезжает к середине.
						var a := angle - side * HALF_PI
						rc = cos(a)
						rs = sin(a)
					_buffer[o] = rc * ITEM_PX
					_buffer[o + 1] = rs * ITEM_PX
					_buffer[o + 4] = rs * ITEM_PX
					_buffer[o + 5] = -rc * ITEM_PX
					# Ось движения (dx, dy), боковая ось (−dy, dx).
					_buffer[o + 3] = center_x + dx * p * tile - dy * l
					_buffer[o + 7] = center_y + dy * p * tile + dx * l
					_buffer[o + 8] = items[k]
					n += 1
	drawn_count = n
	_multimesh.buffer = _buffer
	_multimesh.visible_instance_count = n


func _ensure_capacity(wanted: int) -> void:
	if wanted <= _capacity:
		return
	var old := _capacity
	_capacity = maxi(wanted, INITIAL_CAPACITY)
	_buffer.resize(_capacity * STRIDE)
	for i in range(old, _capacity):
		var o := i * STRIDE
		_buffer[o] = ITEM_PX
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = 0.0
		_buffer[o + 4] = 0.0
		# Отрицательный масштаб по Y: QuadMesh в 2D иначе рисуется вверх ногами.
		_buffer[o + 5] = -ITEM_PX
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = 0.0
		_buffer[o + 8] = 0.0
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = 0.0
		_buffer[o + 11] = 0.0
	_multimesh.instance_count = _capacity
	_multimesh.visible_instance_count = 0
