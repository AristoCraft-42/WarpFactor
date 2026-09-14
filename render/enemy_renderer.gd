class_name EnemyRenderer
extends Node2D
## Отрисовка врагов одним MultiMeshInstance2D: позиция интерполируется между тиками, спрайт повёрнут
## по направлению движения, ячейка атласа — индекс типа. Рисуются только враги в видимой области.

const STRIDE := 12
const INITIAL_CAPACITY := 512
## Ниже этого масштаба враги рисуются крупнее, чтобы толпу было видно издалека.
const FAR_ZOOM := 0.35
const SHADER := preload("res://render/shaders/items.gdshader")

var drawn_count: int = 0

var _world: GameWorld
var _camera: CameraController
var _clock: SimClock
var _instance: MultiMeshInstance2D
var _multimesh: MultiMesh
var _buffer := PackedFloat32Array()
var _capacity: int = 0
var _sizes := PackedFloat32Array()


func setup(world: GameWorld, camera: CameraController, clock: SimClock) -> void:
	_world = world
	_camera = camera
	_clock = clock
	z_index = 3
	_sizes.resize(Registry.enemies.size())
	for def in Registry.enemies:
		_sizes[def.index] = def.draw_size
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
	_instance.texture = ArtRegistry.enemy_atlas
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("cells", float(maxi(Registry.enemies.size(), 1)))
	_instance.material = material
	add_child(_instance)
	_ensure_capacity(INITIAL_CAPACITY)


func _process(_delta: float) -> void:
	if _world == null or _world.enemies == null:
		return
	var sys := _world.enemies
	var count := sys.count
	if count > _capacity:
		_ensure_capacity(count * 2)
	var view := _camera.get_world_view_rect().grow(GameConst.TILE_SIZE * 2)
	var x0 := view.position.x
	var y0 := view.position.y
	var x1 := view.end.x
	var y1 := view.end.y
	var alpha := _clock.alpha
	var boost := 1.0 if _camera.user_zoom >= FAR_ZOOM else FAR_ZOOM / maxf(_camera.user_zoom, 0.05)
	var pos_x := sys.pos_x
	var pos_y := sys.pos_y
	var prev_x := sys.prev_x
	var prev_y := sys.prev_y
	var facing := sys.facing
	var types := sys.types
	var n := 0
	for i in count:
		var x := prev_x[i] + (pos_x[i] - prev_x[i]) * alpha
		var y := prev_y[i] + (pos_y[i] - prev_y[i]) * alpha
		if x < x0 or y < y0 or x > x1 or y > y1:
			continue
		var type := types[i]
		var s := _sizes[type] * boost
		var a := facing[i]
		var cs := cos(a) * s
		var sn := sin(a) * s
		var o := n * STRIDE
		# Базис X = (cos, sin)·s, Y = (sin, −cos)·s: поворот плюс отражение, как у предметов.
		_buffer[o] = cs
		_buffer[o + 1] = sn
		_buffer[o + 3] = x
		_buffer[o + 4] = sn
		_buffer[o + 5] = -cs
		_buffer[o + 7] = y
		_buffer[o + 8] = type
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
		for k in STRIDE:
			_buffer[o + k] = 0.0
	_multimesh.instance_count = _capacity
	_multimesh.visible_instance_count = 0
