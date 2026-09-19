class_name PipeLayer
extends Node2D
## Стыки труб и заполнение сетей — по одной ноде на чанк, как у BuildingLayer.
## Раньше всё это рисовалось заново каждый кадр обходом всех труб мира: на этаже, полностью
## заставленном трубами, кадр стоил десятки тысяч команд отрисовки. Теперь чанк перерисовывается,
## только когда трубы перестроились или заметно изменилось заполнение сети.

## На сколько ступеней делится заполнение сети: перерисовываем при переходе через ступень.
const FILL_STEPS := 12

var _world: GameWorld
var _views: Dictionary[int, PipeChunkView] = {}
var _dirty: Dictionary[int, bool] = {}
## Ключ сети → её ступень заполнения.
var _net_fill: Dictionary[int, int] = {}
## Ключ сети → чанки, в которых лежат её трубы.
var _net_chunks: Dictionary[int, PackedInt32Array] = {}
var _version: int = -1
## Сколько раз пришлось перерисовать чанк (для тестов и отладки).
var redraw_count: int = 0


func setup(world: GameWorld) -> void:
	_world = world
	z_index = 2


func get_view_count() -> int:
	return _views.size()


func _process(_delta: float) -> void:
	if _world == null or _world.fluids == null:
		return
	var fluids := _world.fluids
	if fluids.version != _version:
		_version = fluids.version
		_rebuild_index(fluids)
	else:
		_check_fill(fluids)
	if _dirty.is_empty():
		return
	for chunk_idx in _dirty:
		var view: PipeChunkView = _views.get(chunk_idx)
		if view != null:
			view.queue_redraw()
			redraw_count += 1
	_dirty.clear()


## Сеть труб пересобрана: заново разложить трубы по чанкам и перерисовать всё, что задето.
func _rebuild_index(fluids: FluidGraph) -> void:
	var by_chunk: Dictionary[int, Array] = {}
	var net_chunks: Dictionary[int, PackedInt32Array] = {}
	for id in fluids.pipes:
		var pipe: Building = fluids.pipes[id]
		var chunk_idx := _world.grid.chunk_index(GameConst.tile_to_chunk(pipe.origin))
		var list: Array = by_chunk.get(chunk_idx, [])
		list.append(pipe)
		by_chunk[chunk_idx] = list
		var net := fluids.get_pipe_network(pipe)
		if net == null:
			continue
		var chunks: PackedInt32Array = net_chunks.get(net.key, PackedInt32Array())
		if not chunks.has(chunk_idx):
			chunks.append(chunk_idx)
			net_chunks[net.key] = chunks
	_net_chunks = net_chunks
	_net_fill.clear()
	for net in fluids.networks:
		_net_fill[net.key] = _fill_step(net)
	# Чанки без труб больше не нужны.
	for chunk_idx in _views.keys():
		if not by_chunk.has(chunk_idx):
			var view := _views[chunk_idx]
			_views.erase(chunk_idx)
			_dirty.erase(chunk_idx)
			view.queue_free()
	for chunk_idx in by_chunk:
		var view: PipeChunkView = _views.get(chunk_idx)
		if view == null:
			view = PipeChunkView.new()
			view.name = "Pipes%d" % chunk_idx
			view.world = _world
			add_child(view)
			_views[chunk_idx] = view
		view.pipes.assign(by_chunk[chunk_idx])
		_dirty[chunk_idx] = true


## Заполнение сети перешло через ступень — перерисовать её чанки.
func _check_fill(fluids: FluidGraph) -> void:
	for net in fluids.networks:
		var step := _fill_step(net)
		if int(_net_fill.get(net.key, -1)) == step:
			continue
		_net_fill[net.key] = step
		for chunk_idx in (_net_chunks.get(net.key, PackedInt32Array()) as PackedInt32Array):
			_dirty[chunk_idx] = true


static func _fill_step(net: FluidGraph.FluidNetwork) -> int:
	if net.fluid < 0 or net.capacity <= 0.0:
		return -1
	return (net.fluid + 1) * (FILL_STEPS + 1) + floori(clampf(net.amount / net.capacity, 0.0, 1.0) * FILL_STEPS)
