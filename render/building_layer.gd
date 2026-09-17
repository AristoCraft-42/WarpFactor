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
	world.buildings.building_changed.connect(_on_building_changed)
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


## Детали поверх здания, зависящие от настройки: иконка фильтра, инверсия, связь моста, порты шлюза,
## приоритетные стороны маршрутизатора.
static func draw_building_extras(canvas: CanvasItem, building: Building) -> void:
	if building is Router:
		var router := building as Router
		if router.priority_in != Router.NO_SIDE:
			_draw_side_mark(canvas, building, router.world_side(router.priority_in), true)
		if router.priority_out != Router.NO_SIDE:
			_draw_side_mark(canvas, building, router.world_side(router.priority_out), false)
	if building is GatewayBuilding:
		var gate := building as GatewayBuilding
		if gate.items_enabled():
			for tile in gate.get_input_tiles():
				draw_port_arrow(canvas, tile, gate.get_input_side(), true)
			for tile in gate.get_output_tiles():
				draw_port_arrow(canvas, tile, gate.get_output_side(), false)
	if building is Drill:
		draw_side_arrow(canvas, building.get_world_center(), building.def.size, building.rotation, false)
	if building.is_inverted():
		# Инверсия: сиреневая рамка и уголок-отметка.
		var rect := building.get_world_rect().grow(-2.0)
		canvas.draw_rect(rect, Color(0.83, 0.53, 0.61, 0.95), false, 2.0)
		var corner := rect.position
		canvas.draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(10, 0), corner + Vector2(0, 10)]),
			Color(0.83, 0.53, 0.61, 0.95))
	var item := building.get_display_item()
	if item >= 0:
		var t := float(GameConst.TILE_SIZE)
		var icon_size := t * 0.5
		var center := building.get_world_center()
		canvas.draw_rect(Rect2(center - Vector2.ONE * (icon_size * 0.5 + 2.0), Vector2.ONE * (icon_size + 4.0)), Color(0, 0, 0, 0.55))
		canvas.draw_texture_rect_region(ArtRegistry.item_atlas, Rect2(center - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size),
			Rect2(item * t, 0, t, t))
	if building is BridgeConveyor:
		var target := (building as BridgeConveyor).get_link_target()
		if target != null:
			var from := building.get_world_center()
			var to := target.get_world_center()
			canvas.draw_line(from, to, Color(0.1, 0.1, 0.1, 0.6), 6.0)
			canvas.draw_line(from, to, Color(0.98, 0.74, 0.18, 0.85), 3.0)
			canvas.draw_circle(to, 4.0, Color(0.98, 0.74, 0.18, 0.95))


## Небольшая стрелка у стороны 1×1 здания: вход — внутрь (зелёная), выход — наружу (оранжевая).
static func _draw_side_mark(canvas: CanvasItem, building: Building, side: int, incoming: bool) -> void:
	var dir := Vector2(GameConst.dir_vector(side))
	var edge := building.get_world_center() + dir * (GameConst.TILE_SIZE * 0.5 - 6.0)
	var point := -dir if incoming else dir
	var side_vec := Vector2(-point.y, point.x)
	var col := Color(0.72, 0.73, 0.15) if incoming else Color(0.99, 0.5, 0.1)
	var tip := edge + point * 5.0
	var back := edge - point * 4.0
	canvas.draw_colored_polygon(PackedVector2Array([tip + point * 1.5, back - point * 1.5 + side_vec * 7.0, back - point * 1.5 - side_vec * 7.0]), Color(0, 0, 0, 0.65))
	canvas.draw_colored_polygon(PackedVector2Array([tip, back + side_vec * 5.0, back - side_vec * 5.0]), col)


## Стрелка на середине стороны здания (порт шлюза, выход бура): вход — внутрь (зелёная), выход — наружу (оранжевая).
static func draw_side_arrow(canvas: CanvasItem, center: Vector2, size_tiles: int, side: int, incoming: bool, alpha: float = 1.0) -> void:
	var t := float(GameConst.TILE_SIZE)
	var dir := Vector2(GameConst.dir_vector(side))
	# Стрелка на середине стороны здания: наполовину внутри, чтобы её не закрывала лента в порту.
	var edge := center + dir * (size_tiles * t * 0.5 - 4.0)
	var point := -dir if incoming else dir
	var side_vec := Vector2(-point.y, point.x)
	var col := Color(0.72, 0.73, 0.15) if incoming else Color(0.99, 0.5, 0.1)
	var tip := edge + point * 11.0
	var back := edge - point * 9.0
	var outline := PackedVector2Array([tip + point * 2.5, back - point * 1.5 + side_vec * 13.0, back - point * 1.5 - side_vec * 13.0])
	canvas.draw_colored_polygon(outline, Color(0, 0, 0, 0.6 * alpha))
	canvas.draw_colored_polygon(PackedVector2Array([tip, back + side_vec * 10.0, back - side_vec * 10.0]), Color(col, 0.9 * alpha))


## Стрелка порта у тайла port снаружи здания: вход — внутрь (зелёная), выход — наружу (оранжевая).
static func draw_port_arrow(canvas: CanvasItem, port: Vector2i, side: int, incoming: bool) -> void:
	var t := float(GameConst.TILE_SIZE)
	var dir := Vector2(GameConst.dir_vector(side))
	# Стрелка у края здания напротив порта: наполовину внутри, чтобы её не закрывала лента.
	var edge := (Vector2(port) + Vector2.ONE * 0.5) * t - dir * (t * 0.5 + 4.0)
	var point := -dir if incoming else dir
	var side_vec := Vector2(-point.y, point.x)
	var col := Color(0.72, 0.73, 0.15) if incoming else Color(0.99, 0.5, 0.1)
	var tip := edge + point * 9.0
	var back := edge - point * 7.0
	canvas.draw_colored_polygon(PackedVector2Array([tip + point * 2.0, back - point * 1.5 + side_vec * 10.0, back - point * 1.5 - side_vec * 10.0]), Color(0, 0, 0, 0.6))
	canvas.draw_colored_polygon(PackedVector2Array([tip, back + side_vec * 8.0, back - side_vec * 8.0]), Color(col, 0.9))


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
