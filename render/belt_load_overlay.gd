class_name BeltLoadOverlay
extends Node2D
## Оверлей «загрузка лент»: пустые ленты — серые, движущиеся — от зелёного к жёлтому по заполненности,
## стоящие с предметами (заблокированные) — красные. Перерисовывается несколько раз в секунду,
## только для видимых чанков.

const REFRESH_INTERVAL := 0.2
const COLOR_EMPTY := Color(0.55, 0.55, 0.55, 0.22)
const COLOR_LOW := Color(0.72, 0.73, 0.15, 0.5)
const COLOR_HIGH := Color(0.98, 0.74, 0.18, 0.6)
const COLOR_BLOCKED := Color(0.98, 0.29, 0.2, 0.65)

var _world: GameWorld
var _camera: CameraController
var _timer: float = 0.0


func setup(world: GameWorld, camera: CameraController) -> void:
	_world = world
	_camera = camera
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_INTERVAL
		queue_redraw()


func _draw() -> void:
	if _world == null:
		return
	var grid := _world.grid
	var manager := _world.buildings
	var sys := _world.simulation.conveyors
	var chunk_range := grid.chunk_range_for_world_rect(_camera.get_world_view_rect())
	var t := float(GameConst.TILE_SIZE)
	for cy in range(chunk_range.position.y, chunk_range.end.y):
		for cx in range(chunk_range.position.x, chunk_range.end.x):
			for bid in manager.get_chunk_ids(cy * grid.chunks_x() + cx):
				var c := sys.index_of(bid)
				if c < 0:
					continue
				var n := sys.counts[c]
				var col := COLOR_EMPTY
				if n > 0:
					if sys.awake_flags[c] == 0:
						col = COLOR_BLOCKED
					else:
						col = COLOR_LOW.lerp(COLOR_HIGH, float(n - 1) / (ConveyorSystem.CAP - 1))
				draw_rect(Rect2(sys.tiles_x[c] * t + 2.0, sys.tiles_y[c] * t + 2.0, t - 4.0, t - 4.0), col)
