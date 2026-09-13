class_name ToolController
extends Node
## Инструменты игрока: строительство (одиночное и протягиванием), снос (клик и рамка),
## пипетка, поворот (здания в руке или стоящего под курсором), отмена.
## Все изменения мира идут через GameWorld (стоимость, возврат, содержимое в ядро).
## Превью обновляется только при смене тайла под курсором, состояния или запасов ядра.

signal mode_changed
signal hover_changed
## Изменился план размещения (для подсказки о причине невалидности).
signal plan_changed
signal pause_menu_requested
## Снос большого числа зданий — интерфейс спрашивает подтверждение и вызывает remove_buildings.
signal delete_confirmation_requested(targets: Array[Building])

enum Mode { NONE, PLACE, DELETE }
enum Drag { NONE, PLACE, DELETE }

var mode: Mode = Mode.NONE
var place_def: BuildingDef
var rotation: int = 0
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if not value:
			_cancel_drag()

var hover_tile: Vector2i = Vector2i(-1, -1)
var hover_building: Building
var hover_in_bounds: bool = false
## Первая причина, по которой план нельзя построить (Check.OK — всё в порядке).
var plan_problem: BuildingManager.Check = BuildingManager.Check.OK

var _world: GameWorld
var _camera: CameraController
var _preview: PlacementPreview

var _drag: Drag = Drag.NONE
var _drag_start: Vector2i = Vector2i.ZERO
var _x_first: bool = true
var _axis_locked: bool = false
var _ghosts: Array[PlacementPreview.Ghost] = []
var _delete_targets: Array[Building] = []
## Ключ позиции курсора с шагом в полтайла: меняется и при смене тайла, и при смене «угла» для 2x2.
var _last_key: Vector2i = Vector2i(-999999, -999999)
var _dirty: bool = true
var _over_ui: bool = false
var _storage_revision: int = -1


func setup(world: GameWorld, camera: CameraController, preview: PlacementPreview) -> void:
	_world = world
	_camera = camera
	_preview = preview
	_camera.pan_clicked.connect(_on_pan_clicked)
	_world.buildings.building_added.connect(_on_world_changed)
	_world.buildings.building_removed.connect(_on_world_changed)
	_world.buildings.building_rotated.connect(_on_world_changed)


func select_building(def: BuildingDef) -> void:
	_cancel_drag()
	place_def = def
	mode = Mode.PLACE
	_dirty = true
	mode_changed.emit()


func set_delete_mode() -> void:
	_cancel_drag()
	place_def = null
	mode = Mode.DELETE
	_dirty = true
	mode_changed.emit()


func clear_tool() -> void:
	_cancel_drag()
	place_def = null
	mode = Mode.NONE
	_dirty = true
	mode_changed.emit()


func is_dragging() -> bool:
	return _drag != Drag.NONE


func remove_buildings(targets: Array[Building]) -> void:
	for b in targets:
		_world.demolish(b)
	_dirty = true


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("build_primary"):
		if Input.is_action_pressed("area_modifier") or mode == Mode.DELETE:
			_begin_drag(Drag.DELETE)
		elif mode == Mode.PLACE:
			_begin_drag(Drag.PLACE)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("build_primary"):
		if _drag != Drag.NONE:
			_finish_drag()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate"):
		_rotate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pipette"):
		_pipette()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("delete_mode"):
		if mode == Mode.DELETE:
			clear_tool()
		else:
			set_delete_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		if _drag != Drag.NONE:
			_cancel_drag()
		elif mode != Mode.NONE:
			clear_tool()
		else:
			pause_menu_requested.emit()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _world == null:
		return
	# Отпускание кнопки над панелью интерфейса не доходит до _unhandled_input.
	if _drag != Drag.NONE and not Input.is_action_pressed("build_primary"):
		_finish_drag()

	var over_ui := get_viewport().gui_get_hovered_control() != null and _drag == Drag.NONE
	if over_ui != _over_ui:
		_over_ui = over_ui
		_dirty = true
	# Запасы ядра влияют на доступность построек в превью.
	if mode == Mode.PLACE and _world.core_storage.revision != _storage_revision:
		_storage_revision = _world.core_storage.revision
		_dirty = true

	var mouse_world := _camera.get_mouse_world()
	var half := float(GameConst.TILE_SIZE) * 0.5
	var key := Vector2i(floori(mouse_world.x / half), floori(mouse_world.y / half))
	if key == _last_key and not _dirty:
		return
	_last_key = key
	_dirty = false

	var tile := GameConst.world_to_tile(mouse_world)
	var in_bounds := _world.grid.in_bounds_v(tile)
	var hovered := _world.buildings.get_at(tile) if in_bounds else null
	if tile != hover_tile or hovered != hover_building or in_bounds != hover_in_bounds:
		hover_tile = tile
		hover_building = hovered
		hover_in_bounds = in_bounds
	hover_changed.emit()

	if not input_enabled or (_over_ui and _drag == Drag.NONE):
		_set_ghosts([])
		_preview.set_delete_selection(Rect2i(), [])
		_preview.set_hover(null)
		return

	match _drag:
		Drag.DELETE:
			_update_delete_selection(Rect2i(_drag_start, Vector2i.ONE).merge(Rect2i(tile, Vector2i.ONE)))
			return
		Drag.PLACE:
			_update_ghosts(mouse_world, tile)
			return

	match mode:
		Mode.PLACE:
			_update_ghosts(mouse_world, tile)
		Mode.DELETE:
			_update_delete_selection(Rect2i(tile, Vector2i.ONE))
		_:
			_set_ghosts([])
			_delete_targets = []
			_preview.set_delete_selection(Rect2i(), [])
			_preview.set_hover(hovered)


func _begin_drag(kind: Drag) -> void:
	var mouse_world := _camera.get_mouse_world()
	_drag = kind
	_axis_locked = false
	if kind == Drag.PLACE and not place_def.line_placement:
		_drag_start = GameConst.origin_for_size(mouse_world, place_def.size)
	else:
		_drag_start = GameConst.world_to_tile(mouse_world)
	_dirty = true


func _finish_drag() -> void:
	var kind := _drag
	_drag = Drag.NONE
	_dirty = true
	match kind:
		Drag.PLACE:
			var last_rotation := rotation
			var short_of_resources := false
			for g in _ghosts:
				if g.check == BuildingManager.Check.OK or g.check == BuildingManager.Check.REPLACE:
					if _world.build(g.def, g.origin, g.rotation) == null:
						short_of_resources = true
				elif g.check == BuildingManager.Check.NOT_AFFORDABLE:
					short_of_resources = true
				last_rotation = g.rotation
			if short_of_resources:
				Events.toast(tr("TOAST_NOT_ENOUGH_RESOURCES"), Events.ToastKind.WARNING)
			if place_def != null and place_def.line_placement and _ghosts.size() > 1:
				rotation = last_rotation
		Drag.DELETE:
			var targets := _delete_targets
			_delete_targets = []
			if targets.size() >= GameConst.MASS_DELETE_THRESHOLD and Settings.get_bool(&"game/confirm_mass_delete"):
				delete_confirmation_requested.emit(targets)
			else:
				remove_buildings(targets)
	_set_ghosts([])
	_preview.clear()


func _cancel_drag() -> void:
	if _drag == Drag.NONE:
		return
	_drag = Drag.NONE
	_ghosts = []
	_delete_targets = []
	_dirty = true
	if _preview != null:
		_preview.clear()


func _rotate() -> void:
	match mode:
		Mode.PLACE:
			if place_def == null:
				return
			if _drag == Drag.PLACE and place_def.line_placement:
				# Во время протягивания R меняет, по какой оси трасса идёт сначала.
				_x_first = not _x_first
				_axis_locked = true
			else:
				rotation = (rotation + 1) % 4
			_dirty = true
		Mode.NONE:
			# Пустой рукой R поворачивает здание под курсором.
			if hover_building != null and _world.rotate_building(hover_building, 1):
				_dirty = true


func _pipette() -> void:
	var b := hover_building
	if b == null:
		clear_tool()
		return
	if not b.def.player_buildable:
		Events.toast(tr("TOAST_PIPETTE_UNAVAILABLE") % tr(b.def.name_key), Events.ToastKind.WARNING)
		return
	rotation = b.rotation
	select_building(b.def)


func _update_ghosts(mouse_world: Vector2, tile: Vector2i) -> void:
	var def := place_def
	var budget := _world.core_storage.make_budget()
	var ghosts: Array[PlacementPreview.Ghost] = []
	if _drag == Drag.PLACE and def.line_placement:
		var delta := tile - _drag_start
		if not _axis_locked and delta != Vector2i.ZERO:
			_x_first = absi(delta.x) >= absi(delta.y)
			_axis_locked = true
		for step in LinePlanner.l_path(_drag_start, tile, _x_first, rotation):
			var origin := Vector2i(step.x, step.y)
			var rot := step.z if def.rotatable else 0
			ghosts.append(PlacementPreview.Ghost.new(def, origin, rot, _world.check_build(def, origin, rot, budget)))
	elif _drag == Drag.PLACE:
		var end_origin := GameConst.origin_for_size(mouse_world, def.size)
		for origin in LinePlanner.straight_line(_drag_start, end_origin, def.size):
			ghosts.append(PlacementPreview.Ghost.new(def, origin, rotation, _world.check_build(def, origin, rotation, budget)))
	else:
		var origin := GameConst.origin_for_size(mouse_world, def.size)
		ghosts.append(PlacementPreview.Ghost.new(def, origin, rotation, _world.check_build(def, origin, rotation, budget)))
	_preview.set_delete_selection(Rect2i(), [])
	_set_ghosts(ghosts)


func _set_ghosts(ghosts: Array[PlacementPreview.Ghost]) -> void:
	_ghosts = ghosts
	_preview.set_ghosts(ghosts)
	var problem := BuildingManager.Check.OK
	for g in ghosts:
		if not BuildingManager.is_valid_check(g.check):
			problem = g.check
			break
	if problem != plan_problem:
		plan_problem = problem
		plan_changed.emit()


func _update_delete_selection(rect: Rect2i) -> void:
	var targets: Array[Building] = []
	for b in _world.buildings.collect_in_rect(rect):
		if b.def.removable:
			targets.append(b)
	_delete_targets = targets
	_set_ghosts([])
	_preview.set_delete_selection(rect if _drag == Drag.DELETE else Rect2i(), targets)


func _on_pan_clicked() -> void:
	if not input_enabled:
		return
	if _drag != Drag.NONE:
		_cancel_drag()
	elif mode != Mode.NONE:
		clear_tool()


func _on_world_changed(_building: Building) -> void:
	_dirty = true
