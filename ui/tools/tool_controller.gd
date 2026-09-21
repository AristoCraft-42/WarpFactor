class_name ToolController
extends Node
## Инструменты игрока.
## - ЛКМ: строительство (одиночное и протягиванием), вставка скопированного; пустой рукой —
##   выбор здания (настройка, окно склада/завода) или добыча руды дроном, пока кнопка зажата.
## - Shift+ЛКМ по зданию пустой рукой — забрать накопленную продукцию, Shift+ПКМ — загрузить в него
##   всё подходящее сырьё из инвентаря.
## - ПКМ с зажатием: выделение области; X — снести выделенное (без выделения — здание под курсором),
##   C — скопировать выделенное в руку.
##   Клик ПКМ отменяет инструмент или выделение, а по зданию без инструмента выделяет его.
## - R: поворот здания в руке, скопированного плана или стоящего здания под курсором. Q — пипетка.
## Все изменения мира идут через GameWorld: радиус дрона, постройки из инвентаря, возврат при сносе.
## Превью обновляется только при смене тайла под курсором, состояния, инвентаря или позиции дрона.

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
enum Drag { NONE, PLACE, SELECT, MINE }

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
var _inventory_revision: int = -1
## Тайл дрона на момент последнего расчёта превью (радиус зависит от позиции).
var _drone_key: Vector2i = Vector2i(-999999, -999999)


func setup(world: GameWorld, camera: CameraController, preview: PlacementPreview) -> void:
	_camera = camera
	_preview = preview
	set_world(world)


## Смена активного мира (дрон прошёл через шлюз): инструмент, выделение и выбор сбрасываются.
func set_world(world: GameWorld) -> void:
	if world == _world:
		return
	if _world != null:
		_cancel_drag()
		clear_tool()
		select(null)
		clear_area()
		if _world.buildings != null:
			_world.buildings.building_added.disconnect(_on_world_changed)
			_world.buildings.building_removed.disconnect(_on_world_changed)
			_world.buildings.building_rotated.disconnect(_on_world_changed)
			_world.buildings.building_changed.disconnect(_on_world_changed)
			_world.buildings.building_removed.disconnect(_on_building_removed)
	_world = world
	_world.buildings.building_added.connect(_on_world_changed)
	_world.buildings.building_removed.connect(_on_world_changed)
	_world.buildings.building_rotated.connect(_on_world_changed)
	_world.buildings.building_changed.connect(_on_world_changed)
	_world.buildings.building_removed.connect(_on_building_removed)
	hover_building = null
	hover_in_bounds = false
	hover_tile = Vector2i(-1, -1)
	_last_key = Vector2i(-999999, -999999)
	if _preview != null:
		_preview.clear()
		_preview.set_hover(null)
		_preview.set_selection(null)
	_dirty = true
	hover_changed.emit()


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


## Сносит здания и сообщает, если что-то не удалось (далеко, инвентарь полон) или потерялось.
func remove_buildings(targets: Array[Building]) -> void:
	var ids := PackedInt32Array()
	for b in targets:
		if b != null and b.id != 0:
			ids.append(b.id)
	if ids.is_empty():
		return
	_world.submit(Command.Kind.REMOVE, {"ids": ids})
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
	if event.is_action_pressed("build_primary") and _quick_transfer(true):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_area") and _quick_transfer(false):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_primary"):
		match mode:
			Mode.PLACE:
				_begin_place_drag()
			Mode.PASTE:
				_paste()
			_:
				clear_area()
				if hover_building == null and _world.drone.get_mineable_ore(hover_tile) != null:
					_begin_mine_drag()
				else:
					_click_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("build_primary"):
		if _drag == Drag.PLACE or _drag == Drag.MINE:
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
		elif _drag == Drag.NONE and hover_building != null and not _over_ui:
			var single: Array[Building] = [hover_building]
			remove_buildings(single)
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
	if (_drag == Drag.PLACE or _drag == Drag.MINE) and not Input.is_action_pressed("build_primary"):
		_finish_drag()
	elif _drag == Drag.SELECT and not Input.is_action_pressed("select_area"):
		_finish_drag()

	var over_ui := get_viewport().gui_get_hovered_control() != null and _drag == Drag.NONE
	if over_ui != _over_ui:
		_over_ui = over_ui
		_dirty = true
	# Инвентарь и позиция дрона влияют на доступность построек в превью.
	var drone := _world.drone
	if mode != Mode.NONE:
		if drone.inventory.revision != _inventory_revision:
			_inventory_revision = drone.inventory.revision
			_dirty = true
		var drone_key := Vector2i((drone.position / (GameConst.TILE_SIZE * 0.5)).floor())
		if drone_key != _drone_key:
			_drone_key = drone_key
			_dirty = true
	# Дрон улетел от выбранного здания — окно и настройка закрываются.
	if selected != null and not _world.can_interact(selected):
		select(null)

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
		Drag.MINE:
			if _world.drone.get_mineable_ore(tile) != null:
				_world.submit(Command.Kind.MINE, {"tile": tile})
			_set_ghosts([])
			return
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


func _begin_mine_drag() -> void:
	_drag = Drag.MINE
	select(null)
	_world.submit(Command.Kind.MINE, {"tile": hover_tile})
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
		Drag.MINE:
			_world.submit(Command.Kind.MINE, {"tile": Drone.NO_TILE})
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
	if _drag == Drag.MINE and _world != null and _world.drone != null:
		_world.submit(Command.Kind.MINE, {"tile": Drone.NO_TILE})
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


## Одно действие игрока (клик или протягивание) — одна команда со списком мест.
## Сама постройка, связывание мостов и подсказки происходят при выполнении команды.
func _build_ghosts() -> void:
	var last_rotation := rotation
	var places := []
	for g in _ghosts:
		if g.check == BuildingManager.Check.OK or g.check == BuildingManager.Check.REPLACE:
			# Свою настройку несут вставляемый план и постройки, подставленные при протягивании (мосты).
			var config: Variant = g.config if (mode == Mode.PASTE or g.def != place_def) else place_config
			places.append({"def": String(g.def.id), "origin": g.origin, "rotation": g.rotation, "config": config})
		elif g.check == BuildingManager.Check.NO_ITEM or g.check == BuildingManager.Check.OUT_OF_RANGE:
			places.append({"def": String(g.def.id), "origin": g.origin, "rotation": g.rotation, "config": null})
		last_rotation = g.rotation
	var link := mode == Mode.PLACE and place_def is LogisticDef and (place_def as LogisticDef).link_range > 0
	if not places.is_empty():
		_world.submit(Command.Kind.BUILD, {"places": places, "link_bridges": link, "config": place_config})
		# В сетевой игре здание встанет, только когда команда вернётся от хоста: до тех пор
		# на его месте висит отметка, чтобы было видно, что клик принят.
		if Session.net.is_networked() and _preview != null:
			var sent: Array[PlacementPreview.Ghost] = []
			for g in _ghosts:
				if g.check == BuildingManager.Check.OK or g.check == BuildingManager.Check.REPLACE:
					sent.append(g)
			_preview.add_pending(sent, _world)
	if link and place_def != null and place_def.line_placement and _ghosts.size() > 1:
		rotation = last_rotation


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
			if hover_building == null:
				return
			if not _world.can_interact(hover_building):
				Events.toast(tr("TOAST_OUT_OF_RANGE"), Events.ToastKind.WARNING)
			elif _world.can_interact(hover_building) and hover_building.def.rotatable:
				_world.submit(Command.Kind.ROTATE, {"id": hover_building.id, "delta": 1})
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
		elif entry.config is Array:
			var rotated: Array = []
			for v in entry.config:
				rotated.append(Vector2i(-v.y, v.x) if v is Vector2i else v)
			entry.config = rotated
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


## Клик ЛКМ пустой рукой: выбрать здание с настройкой или окном (склад, завод, бур); для выбранного
## моста клик по другому мосту в пределах дальности связывает их (повторный клик — разрывает связь).
## Быстрый обмен с зданием под курсором по Shift: забрать продукцию (ЛКМ) или загрузить сырьё (ПКМ).
## Возвращает true, если обмен состоялся и клик больше никому не нужен.
func _quick_transfer(take: bool) -> bool:
	if not Input.is_key_pressed(KEY_SHIFT) or mode != Mode.NONE or _over_ui:
		return false
	var building := hover_building
	if building == null or not building.has_player_window():
		return false
	if not _world.can_interact(building):
		Events.toast(tr("TOAST_OUT_OF_RANGE"), Events.ToastKind.WARNING)
		return true
	_world.submit(Command.Kind.TAKE_OUTPUT if take else Command.Kind.FILL, {"id": building.id})
	return true


func _click_select() -> void:
	var clicked := hover_building
	if clicked != null and clicked.has_player_window() and not _world.can_interact(clicked):
		Events.toast(tr("TOAST_OUT_OF_RANGE"), Events.ToastKind.WARNING)
		return
	if selected is BridgeConveyor and clicked is BridgeConveyor and clicked != selected:
		var bridge := selected as BridgeConveyor
		if bridge.can_link_to(clicked):
			var offset := clicked.origin - bridge.origin
			_world.submit(Command.Kind.CONFIGURE, {"id": bridge.id, "value": null if bridge.link == offset else offset})
			select(clicked)
			return
	if clicked != null and clicked.has_player_window() and clicked != selected:
		select(clicked)
	else:
		select(null)


# --- Превью ---

func _update_ghosts(mouse_world: Vector2, tile: Vector2i) -> void:
	var def := place_def
	var budget := _world.drone.inventory.make_budget()
	var ghosts: Array[PlacementPreview.Ghost] = []
	if _drag == Drag.PLACE and def.line_placement:
		var delta := tile - _drag_start
		if not _axis_locked and delta != Vector2i.ZERO:
			_x_first = absi(delta.x) >= absi(delta.y)
			_axis_locked = true
		var fluid_def := def as FluidBuildingDef
		if fluid_def != null and fluid_def.role == FluidBuildingDef.Role.UNDERGROUND:
			# Подземные трубы протягиваются парами на наибольшем расстоянии — как опоры ЛЭП.
			_set_ghosts(LinePlanner.plan_underground(_world, fluid_def, _drag_start, tile, rotation, budget))
			return
		var path := LinePlanner.l_path(_drag_start, tile, _x_first, rotation)
		if def is ConveyorDef and path.size() > 1:
			ghosts = LinePlanner.plan_belt(_world, def, path, budget)
		elif fluid_def != null and fluid_def.role == FluidBuildingDef.Role.PIPE and path.size() > 1:
			ghosts = LinePlanner.plan_pipe(_world, def, path, budget)
		else:
			for step in path:
				var origin := Vector2i(step.x, step.y)
				var rot := step.z if def.rotatable else 0
				ghosts.append(PlacementPreview.Ghost.new(def, origin, rot, _world.check_build(def, origin, rot, budget)))
	elif _drag == Drag.PLACE:
		var end_origin := GameConst.origin_for_size(mouse_world, def.size)
		for origin in LinePlanner.straight_line(_drag_start, end_origin, def.get_line_step()):
			var rot := def.placement_rotation(_world, origin, rotation)
			ghosts.append(PlacementPreview.Ghost.new(def, origin, rot, _world.check_build(def, origin, rot, budget)))
	else:
		var origin := GameConst.origin_for_size(mouse_world, def.size)
		var rot := def.placement_rotation(_world, origin, rotation)
		ghosts.append(PlacementPreview.Ghost.new(def, origin, rot, _world.check_build(def, origin, rot, budget)))
	_set_ghosts(ghosts)


func _update_paste_ghosts(tile: Vector2i) -> void:
	var budget := _world.drone.inventory.make_budget()
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
func _on_world_changed(_building: Building) -> void:
	_dirty = true


func _on_building_removed(building: Building) -> void:
	if building == selected:
		select(null)
	if has_area():
		_refresh_area_buildings()
