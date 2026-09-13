class_name ToolController
extends Node
## Инструменты игрока.
## - ЛКМ: строительство (одиночное и протягиванием), вставка скопированного, выбор здания для настройки.
## - ПКМ с зажатием: выделение области; X — снести выделенное, C — скопировать в руку.
##   Клик ПКМ отменяет инструмент или выделение, а по зданию без инструмента выделяет его.
## - R: поворот здания в руке, скопированного плана или стоящего здания под курсором. Q — пипетка.
## Все изменения мира идут через GameWorld (стоимость, возврат, содержимое в ядро).
## Превью обновляется только при смене тайла под курсором, состояния или запасов ядра.

signal mode_changed
signal hover_changed
## Изменился план размещения (для подсказки о причине невалидности).
signal plan_changed
signal pause_menu_requested
## Снос большого числа зданий — интерфейс спрашивает подтверждение и вызывает remove_buildings.
signal delete_confirmation_requested(targets: Array[Building])
## Выбрано здание для настройки (или выбор снят).
signal selection_changed
## Изменилось выделение области.
signal area_changed

enum Mode { NONE, PLACE, PASTE }
enum Drag { NONE, PLACE, SELECT }

## Сдвиг мыши (пикселей), после которого нажатие ПКМ считается выделением, а не кликом.
const SELECT_DRAG_THRESHOLD := 6.0


## Здание скопированного плана: смещение левого верхнего тайла от угла плана.
class PlanEntry:
	var def: BuildingDef
	var offset: Vector2i
	var rotation: int
	var config: Variant

	func _init(p_def: BuildingDef, p_offset: Vector2i, p_rotation: int, p_config: Variant) -> void:
		def = p_def
		offset = p_offset
		rotation = p_rotation
		config = p_config


var mode: Mode = Mode.NONE
var place_def: BuildingDef
var rotation: int = 0
## Настройка, скопированная пипеткой; применяется к новым зданиям того же типа.
var place_config: Variant = null
## Здание, выбранное для настройки (фильтр, связь моста).
var selected: Building
## Выделенная область (size = 0 — нет выделения) и попавшие в неё здания.
var area_rect: Rect2i = Rect2i()
var area_buildings: Array[Building] = []
## Скопированный план для вставки.
var plan: Array[PlanEntry] = []
var plan_size: Vector2i = Vector2i.ZERO

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
var _drag_start_screen: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _x_first: bool = true
var _axis_locked: bool = false
var _ghosts: Array[PlacementPreview.Ghost] = []
## Ключ позиции курсора с шагом в полтайла: меняется и при смене тайла, и при смене «угла» для 2x2.
var _last_key: Vector2i = Vector2i(-999999, -999999)
var _dirty: bool = true
var _over_ui: bool = false
var _storage_revision: int = -1
## Последний построенный мост — новый мост в линию с ним связывается автоматически.
var _last_bridge: BridgeConveyor


func setup(world: GameWorld, camera: CameraController, preview: PlacementPreview) -> void:
	_world = world
	_camera = camera
	_preview = preview
	_world.buildings.building_added.connect(_on_world_changed)
	_world.buildings.building_removed.connect(_on_world_changed)
	_world.buildings.building_rotated.connect(_on_world_changed)
	_world.buildings.building_changed.connect(_on_world_changed)
	_world.buildings.building_removed.connect(_on_building_removed)


# --- Режимы ---

func select_building(def: BuildingDef, config: Variant = null) -> void:
	_cancel_drag()
	select(null)
	clear_area()
	place_def = def
	place_config = config
	mode = Mode.PLACE
	_dirty = true
	mode_changed.emit()


func clear_tool() -> void:
	_cancel_drag()
	place_def = null
	place_config = null
	plan = []
	mode = Mode.NONE
	_dirty = true
	mode_changed.emit()


## Выбрать здание для настройки (null — снять выбор).
func select(building: Building) -> void:
	if building == selected:
		return
	selected = building
	_dirty = true
	selection_changed.emit()


func set_area(rect: Rect2i) -> void:
	area_rect = rect
	_refresh_area_buildings()
	_dirty = true
	area_changed.emit()


func clear_area() -> void:
	if area_rect.size == Vector2i.ZERO and area_buildings.is_empty():
		return
	area_rect = Rect2i()
	area_buildings = []
	_dirty = true
	area_changed.emit()


func has_area() -> bool:
	return area_rect.size != Vector2i.ZERO


func is_dragging() -> bool:
	return _drag != Drag.NONE


func remove_buildings(targets: Array[Building]) -> void:
	for b in targets:
		_world.demolish(b)
	_dirty = true


## Снести выделенное (с подтверждением при большом количестве).
func delete_area() -> void:
	var targets: Array[Building] = []
	for b in area_buildings:
		if b.world != null and b.def.removable:
			targets.append(b)
	clear_area()
	if targets.is_empty():
		return
	if targets.size() >= GameConst.MASS_DELETE_THRESHOLD and Settings.get_bool(&"game/confirm_mass_delete"):
		delete_confirmation_requested.emit(targets)
	else:
		remove_buildings(targets)


## Скопировать выделенное в руку: план со смещениями, поворотами и настройками.
func copy_area() -> void:
	var sources: Array[Building] = []
	for b in area_buildings:
		if b.world != null and b.def.player_buildable:
			sources.append(b)
	clear_area()
	if sources.is_empty():
		return
	var bounds := sources[0].get_rect()
	for b in sources:
		bounds = bounds.merge(b.get_rect())
	var entries: Array[PlanEntry] = []
	for b in sources:
		entries.append(PlanEntry.new(b.def, b.origin - bounds.position, b.rotation, b.get_config()))
	_cancel_drag()
	select(null)
	place_def = null
	place_config = null
	plan = entries
	plan_size = bounds.size
	mode = Mode.PASTE
	_dirty = true
	mode_changed.emit()
	Events.toast(tr("TOAST_COPIED") % entries.size())


# --- Ввод ---

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("build_primary"):
		match mode:
			Mode.PLACE:
				_begin_place_drag()
			Mode.PASTE:
				_paste()
			_:
				clear_area()
				_click_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("build_primary"):
		if _drag == Drag.PLACE:
			_finish_drag()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_area"):
		_begin_select_drag(event)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("select_area"):
		if _drag == Drag.SELECT:
			_finish_drag()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate"):
		_rotate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pipette"):
		_pipette()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("delete_selection"):
		if has_area():
			delete_area()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("copy_selection"):
		if has_area():
			copy_area()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		if _drag != Drag.NONE:
			_cancel_drag()
		elif has_area():
			clear_area()
		elif selected != null:
			select(null)
		elif mode != Mode.NONE:
			clear_tool()
		else:
			pause_menu_requested.emit()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Сдвиг мыши при зажатой ПКМ отслеживаем и над панелями интерфейса.
	if _drag == Drag.SELECT and event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).position.distance_to(_drag_start_screen) > SELECT_DRAG_THRESHOLD:
			_drag_moved = true


func _process(_delta: float) -> void:
	if _world == null:
		return
	# Отпускание кнопки над панелью интерфейса не доходит до _unhandled_input.
	if _drag == Drag.PLACE and not Input.is_action_pressed("build_primary"):
		_finish_drag()
	elif _drag == Drag.SELECT and not Input.is_action_pressed("select_area"):
		_finish_drag()

	var over_ui := get_viewport().gui_get_hovered_control() != null and _drag == Drag.NONE
	if over_ui != _over_ui:
		_over_ui = over_ui
		_dirty = true
	# Запасы ядра влияют на доступность построек в превью.
	if mode != Mode.NONE and _world.core_storage.revision != _storage_revision:
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
	# Над интерфейсом «здание под курсором» не меняется: иначе инфо-панель прыгает под мышью.
	if not (_over_ui and _drag == Drag.NONE):
		hover_tile = tile
		hover_building = hovered
		hover_in_bounds = in_bounds
		hover_changed.emit()

	_preview.set_selection(selected)
	if not input_enabled or (_over_ui and _drag == Drag.NONE):
		_set_ghosts([])
		_preview.set_area(area_rect, area_buildings)
		_preview.set_hover(null)
		return

	match _drag:
		Drag.SELECT:
			if not _drag_moved and tile != _drag_start:
				_drag_moved = true
			if _drag_moved:
				var rect := Rect2i(_drag_start, Vector2i.ONE).merge(Rect2i(tile, Vector2i.ONE))
				_preview.set_area(rect, _collect(rect))
			_set_ghosts([])
			return
		Drag.PLACE:
			_update_ghosts(mouse_world, tile)
			return

	_preview.set_area(area_rect, area_buildings)
	match mode:
		Mode.PLACE:
			_update_ghosts(mouse_world, tile)
		Mode.PASTE:
			_update_paste_ghosts(tile)
		_:
			_set_ghosts([])
			_preview.set_hover(hovered)


# --- Перетаскивание ---

func _begin_place_drag() -> void:
	var mouse_world := _camera.get_mouse_world()
	_drag = Drag.PLACE
	_axis_locked = false
	if place_def.line_placement:
		_drag_start = GameConst.world_to_tile(mouse_world)
	else:
		_drag_start = GameConst.origin_for_size(mouse_world, place_def.size)
	_dirty = true


func _begin_select_drag(event: InputEvent) -> void:
	_cancel_drag()
	_drag = Drag.SELECT
	_drag_start = GameConst.world_to_tile(_camera.get_mouse_world())
	_drag_start_screen = (event as InputEventMouse).position if event is InputEventMouse else _camera.get_mouse_screen()
	_drag_moved = false
	_dirty = true


func _finish_drag() -> void:
	var kind := _drag
	_drag = Drag.NONE
	_dirty = true
	match kind:
		Drag.PLACE:
			_build_ghosts()
		Drag.SELECT:
			var tile := GameConst.world_to_tile(_camera.get_mouse_world())
			if _drag_moved or tile != _drag_start:
				if mode != Mode.NONE:
					clear_tool()
				select(null)
				set_area(Rect2i(_drag_start, Vector2i.ONE).merge(Rect2i(tile, Vector2i.ONE)))
			else:
				_right_click()
	_set_ghosts([])
	_preview.clear()


func _cancel_drag() -> void:
	if _drag == Drag.NONE:
		return
	_drag = Drag.NONE
	_ghosts = []
	_dirty = true
	if _preview != null:
		_preview.clear()


## Клик ПКМ: отменить инструмент, снять выделение или выбор; иначе выделить здание под курсором.
func _right_click() -> void:
	if mode != Mode.NONE:
		clear_tool()
	elif has_area():
		clear_area()
	elif selected != null:
		select(null)
	elif hover_building != null:
		set_area(hover_building.get_rect())


func _build_ghosts() -> void:
	var last_rotation := rotation
	var short_of_resources := false
	var built: Array[Building] = []
	for g in _ghosts:
		if g.check == BuildingManager.Check.OK or g.check == BuildingManager.Check.REPLACE:
			var config: Variant = g.config if mode == Mode.PASTE else place_config
			var b := _world.build(g.def, g.origin, g.rotation, config)
			if b == null:
				short_of_resources = true
			else:
				built.append(b)
		elif g.check == BuildingManager.Check.NOT_AFFORDABLE:
			short_of_resources = true
		last_rotation = g.rotation
	if mode == Mode.PLACE:
		_link_new_bridges(built)
		if place_def != null and place_def.line_placement and _ghosts.size() > 1:
			rotation = last_rotation
	if short_of_resources:
		Events.toast(tr("TOAST_NOT_ENOUGH_RESOURCES"), Events.ToastKind.WARNING)


func _paste() -> void:
	_update_paste_ghosts(GameConst.world_to_tile(_camera.get_mouse_world()))
	_build_ghosts()
	_dirty = true


# --- Поворот, пипетка, выбор ---

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
		Mode.PASTE:
			_rotate_plan()
		Mode.NONE:
			# Пустой рукой R поворачивает здание под курсором.
			if hover_building != null and _world.rotate_building(hover_building, 1):
				_dirty = true


## Поворот скопированного плана на 90° по часовой стрелке вместе со связями мостов.
func _rotate_plan() -> void:
	for entry in plan:
		var size := entry.def.size
		entry.offset = Vector2i(plan_size.y - entry.offset.y - size, entry.offset.x)
		entry.rotation = (entry.rotation + 1) % 4
		if entry.config is Vector2i:
			var v: Vector2i = entry.config
			entry.config = Vector2i(-v.y, v.x)
	plan_size = Vector2i(plan_size.y, plan_size.x)
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
	select_building(b.def, b.get_config())


## Клик ЛКМ пустой рукой: выбрать настраиваемое здание; для выбранного моста клик по другому мосту
## в пределах дальности связывает их (повторный клик по связанному — разрывает связь).
func _click_select() -> void:
	var clicked := hover_building
	if selected is BridgeConveyor and clicked is BridgeConveyor and clicked != selected:
		var bridge := selected as BridgeConveyor
		if bridge.can_link_to(clicked):
			var offset := clicked.origin - bridge.origin
			_world.configure(bridge, null if bridge.link == offset else offset)
			select(clicked)
			return
	if clicked != null and clicked.get_config_kind() != Building.ConfigKind.NONE and clicked != selected:
		select(clicked)
	else:
		select(null)


# --- Превью ---

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
		for origin in LinePlanner.straight_line(_drag_start, end_origin, def.get_line_step()):
			ghosts.append(PlacementPreview.Ghost.new(def, origin, rotation, _world.check_build(def, origin, rotation, budget)))
	else:
		var origin := GameConst.origin_for_size(mouse_world, def.size)
		ghosts.append(PlacementPreview.Ghost.new(def, origin, rotation, _world.check_build(def, origin, rotation, budget)))
	_set_ghosts(ghosts)


func _update_paste_ghosts(tile: Vector2i) -> void:
	var budget := _world.core_storage.make_budget()
	var corner := tile - plan_size / 2
	var ghosts: Array[PlacementPreview.Ghost] = []
	for entry in plan:
		var origin := corner + entry.offset
		var ghost := PlacementPreview.Ghost.new(entry.def, origin, entry.rotation,
			_world.check_build(entry.def, origin, entry.rotation, budget))
		ghost.config = entry.config
		ghosts.append(ghost)
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


func _collect(rect: Rect2i) -> Array[Building]:
	return _world.buildings.collect_in_rect(rect)


func _refresh_area_buildings() -> void:
	area_buildings = _collect(area_rect) if has_area() else []


# --- Мосты ---

## Связывает только что построенные мосты цепочкой, а первый — с предыдущим построенным мостом.
func _link_new_bridges(built: Array[Building]) -> void:
	var bridges: Array[BridgeConveyor] = []
	for b in built:
		if b is BridgeConveyor:
			bridges.append(b)
	if bridges.is_empty():
		return
	if place_config == null:
		var last := _last_bridge
		if last != null and last.world != null and last.link == Vector2i.ZERO and last.can_link_to(bridges[0]):
			_world.configure(last, bridges[0].origin - last.origin)
		for i in bridges.size() - 1:
			if bridges[i].can_link_to(bridges[i + 1]):
				_world.configure(bridges[i], bridges[i + 1].origin - bridges[i].origin)
	_last_bridge = bridges[bridges.size() - 1]


func _on_world_changed(_building: Building) -> void:
	_dirty = true


func _on_building_removed(building: Building) -> void:
	if building == selected:
		select(null)
	if building == _last_bridge:
		_last_bridge = null
	if has_area():
		_refresh_area_buildings()
