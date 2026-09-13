class_name TerrainView
extends Node2D
## Отрисовка пола и руды через два TileMapLayer.
## Чанки заполняются лениво — только попавшие в камеру, с бюджетом времени на кадр.
## Под тайлмапами всегда лежит обзорная текстура (1 тексель = 1 тайл): она закрывает ещё
## не заполненные чанки и заменяет тайлмапы при сильном отдалении (LOD).

## Сколько микросекунд за кадр можно тратить на заполнение чанков.
const FILL_BUDGET_USEC := 3000

var _grid: WorldGrid
var _floor_layer: TileMapLayer
var _ore_layer: TileMapLayer
var _overview: Sprite2D
var _overview_image: Image
var _overview_texture: ImageTexture
var _filled: PackedByteArray = PackedByteArray()
## Очередь чанков на заполнение; ближайшие к центру экрана — в конце.
var _queue: PackedInt32Array = PackedInt32Array()
var _visible_range: Rect2i = Rect2i()
var _lod_active: bool = false


func setup(grid: WorldGrid) -> void:
	ArtRegistry.ensure_built()
	_grid = grid

	_overview_image = MapPreview.build_terrain_image(grid.width, grid.height, grid.floors, grid.ores)
	_overview_texture = ImageTexture.create_from_image(_overview_image)
	_overview = Sprite2D.new()
	_overview.name = "Overview"
	_overview.centered = false
	_overview.texture = _overview_texture
	_overview.scale = Vector2(GameConst.TILE_SIZE, GameConst.TILE_SIZE)
	_overview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_overview)

	_floor_layer = _make_layer("FloorLayer")
	_ore_layer = _make_layer("OreLayer")

	_filled.resize(grid.chunks_x() * grid.chunks_y())
	_filled.fill(0)


## Вызывается при изменении камеры: world_rect — видимая область, zoom — пользовательский масштаб.
func update_view(world_rect: Rect2, zoom: float) -> void:
	var lod := zoom < GameConst.OVERVIEW_ZOOM
	if lod != _lod_active:
		_lod_active = lod
		_floor_layer.visible = not lod
		_ore_layer.visible = not lod
	if lod:
		_queue.clear()
		_visible_range = Rect2i()
		return

	var chunk_range := _grid.chunk_range_for_world_rect(world_rect.grow(GameConst.CHUNK_PIXELS * 0.5))
	if chunk_range == _visible_range:
		return
	_visible_range = chunk_range

	var center := Vector2(chunk_range.position) + Vector2(chunk_range.size) * 0.5
	var pending: Array[Vector2i] = []
	for cy in range(chunk_range.position.y, chunk_range.end.y):
		for cx in range(chunk_range.position.x, chunk_range.end.x):
			if _filled[_grid.chunk_index(Vector2i(cx, cy))] == 0:
				pending.append(Vector2i(cx, cy))
	# Дальние в начале, ближние в конце — забираем с конца.
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(center) > (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(center))
	_queue.clear()
	for c in pending:
		_queue.append(_grid.chunk_index(c))


## Немедленно заполнить все чанки из очереди (при старте, чтобы не мигало).
func flush() -> void:
	while not _queue.is_empty():
		_fill_next()


## Обновить один тайл (для будущего редактора уровней).
func refresh_tile(x: int, y: int) -> void:
	var i := _grid.index_of(x, y)
	var chunk_idx := _grid.chunk_index(GameConst.tile_to_chunk(Vector2i(x, y)))
	if _filled[chunk_idx] == 1:
		_set_tile(x, y, i)
	var c := ArtRegistry.floor_colors[_grid.floors[i]]
	if _grid.ores[i] != 0:
		c = ArtRegistry.ore_colors[_grid.ores[i] - 1]
	_overview_image.set_pixel(x, y, c)
	_overview_texture.update(_overview_image)


func get_filled_chunk_count() -> int:
	return _filled.count(1)


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var start := Time.get_ticks_usec()
	while not _queue.is_empty():
		_fill_next()
		if Time.get_ticks_usec() - start > FILL_BUDGET_USEC:
			break


func _fill_next() -> void:
	var last := _queue.size() - 1
	var chunk_idx := _queue[last]
	_queue.remove_at(last)
	if _filled[chunk_idx] == 1:
		return
	_filled[chunk_idx] = 1
	var chunk := Vector2i(chunk_idx % _grid.chunks_x(), chunk_idx / _grid.chunks_x())
	var rect := _grid.chunk_tile_rect(chunk)
	for y in range(rect.position.y, rect.end.y):
		var row := y * _grid.width
		for x in range(rect.position.x, rect.end.x):
			_set_tile(x, y, row + x)


func _set_tile(x: int, y: int, i: int) -> void:
	var coords := Vector2i(x, y)
	_floor_layer.set_cell(coords, ArtRegistry.TERRAIN_SOURCE_ID, ArtRegistry.floor_atlas_coords(_grid.floors[i], x, y))
	var ore := _grid.ores[i]
	if ore != 0:
		_ore_layer.set_cell(coords, ArtRegistry.TERRAIN_SOURCE_ID, ArtRegistry.ore_atlas_coords(ore, x, y))
	else:
		_ore_layer.erase_cell(coords)


func _make_layer(layer_name: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = ArtRegistry.terrain_tileset
	layer.rendering_quadrant_size = GameConst.CHUNK_SIZE
	layer.collision_enabled = false
	layer.navigation_enabled = false
	layer.occlusion_enabled = false
	add_child(layer)
	return layer
