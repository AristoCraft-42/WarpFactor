class_name BuildingLayer
extends Node2D
## Слой зданий: по одной ноде BuildingChunkView на чанк.
## Чанк перерисовывается только когда в нём что-то изменилось (dirty-флаг),
## остальное время Godot использует закэшированные команды отрисовки — кадр ничего не стоит.

var _world: GameWorld
var _views: Dictionary[int, BuildingChunkView] = {}
var _dirty: Dictionary[int, bool] = {}


func setup(world: GameWorld) -> void:
	_world = world
	world.buildings.building_added.connect(_on_building_changed)
	world.buildings.building_removed.connect(_on_building_changed)
	world.buildings.building_rotated.connect(_on_building_changed)
	for b in world.buildings.get_all():
		_on_building_changed(b)


func get_view_count() -> int:
	return _views.size()


func _on_building_changed(building: Building) -> void:
	_dirty[_world.grid.chunk_index(GameConst.tile_to_chunk(building.origin))] = true


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	for chunk_idx in _dirty:
		var view: BuildingChunkView = _views.get(chunk_idx)
		if view == null:
			view = BuildingChunkView.new()
			view.name = "Chunk%d" % chunk_idx
			view.chunk_index = chunk_idx
			view.world = _world
			add_child(view)
			_views[chunk_idx] = view
		view.queue_redraw()
	_dirty.clear()


## Рисует здание (или «призрак» при размещении) на произвольном CanvasItem.
static func draw_building(canvas: CanvasItem, def: BuildingDef, origin: Vector2i, rotation: int, modulate: Color = Color.WHITE) -> void:
	var texture := ArtRegistry.get_building_texture(def)
	var size_px := def.get_pixel_size()
	var top_left := Vector2(origin * GameConst.TILE_SIZE)
	if def.rotatable and posmod(rotation, 4) != 0:
		canvas.draw_set_transform(top_left + size_px * 0.5, GameConst.dir_angle(rotation))
		canvas.draw_texture_rect(texture, Rect2(-size_px * 0.5, size_px), false, modulate)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(texture, Rect2(top_left, size_px), false, modulate)
