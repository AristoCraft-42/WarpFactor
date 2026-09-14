class_name Game
extends Node2D
## Корень игровой сцены: загружает уровень, создаёт забег (планета + база) и все представления,
## связывает камеру (следует за дроном), инструменты, управление дроном и интерфейс.
## У каждого мира свой WorldView; активен вид мира, где находится дрон. Переход — через шлюз (F).
## Собственной игровой логики не содержит.

var run: Run
## Активный мир — тот, где сейчас дрон.
var world: GameWorld
var clock: SimClock
var planet_view: WorldView
var base_view: WorldView
var active_view: WorldView
var preview: PlacementPreview
var drone_view: DroneView
var camera: CameraController
var tools: ToolController
var drone_controller: DroneController
var hud: Hud
var pause_menu: PauseMenu

## Представления активного мира (для интерфейса, отладки и тестов).
var terrain: TerrainView:
	get:
		return active_view.terrain
var grid_overlay: GridOverlay:
	get:
		return active_view.grid_overlay
var building_layer: BuildingLayer:
	get:
		return active_view.building_layer
var item_renderer: ItemRenderer:
	get:
		return active_view.item_renderer
var ore_overlay: OreOverlay:
	get:
		return active_view.ore_overlay
var belt_overlay: BeltLoadOverlay:
	get:
		return active_view.belt_overlay

var _debug_enabled: bool = false
var _ores_shown: bool = false
var _belts_shown: bool = false


func _ready() -> void:
	Registry.ensure_loaded()
	ArtRegistry.ensure_built()

	var level := Session.level
	if level == null:
		# Сцена запущена напрямую (F6 в редакторе или из командной строки):
		# уровень можно указать аргументом --level=<id>, иначе берётся первый.
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--level="):
				level = Registry.get_level(StringName(arg.substr("--level=".length())))
		if level == null and not Registry.levels.is_empty():
			level = Registry.levels[0]
	if level == null:
		push_error("Game: нет ни одного уровня")
		Session.exit_to_menu.call_deferred()
		return
	var map := LevelIO.load_map(level.map_path)
	if map == null:
		Events.toast(tr("TOAST_LEVEL_LOAD_FAILED") % tr(level.title_key), Events.ToastKind.WARNING)
		Session.exit_to_menu.call_deferred()
		return

	run = Run.create(level, map, Session.creative)
	world = run.drone.world
	_build_scene()
	run.drone_changed_world.connect(_on_drone_changed_world)

	camera.focus_on(run.drone.position, 1.0)
	_on_view_changed()
	terrain.flush()

	# Отладочные прогоны (tests/), только по флагам командной строки.
	var args := OS.get_cmdline_user_args()
	if args.has("--autoshot"):
		var shot_script: Script = load("res://tests/autoshot.gd")
		if shot_script != null:
			add_child(shot_script.new())
	for arg in args:
		if arg.begins_with("--stress="):
			var stress_script: Script = load("res://tests/stress_render.gd")
			if stress_script != null:
				add_child(stress_script.new())


func _exit_tree() -> void:
	if run != null:
		run.dispose()
		run = null
		world = null


func open_pause_menu() -> void:
	if pause_menu.is_open():
		return
	tools.clear_tool()
	pause_menu.open()
	_update_input_enabled()


## Мир базы открыт на экране.
func is_in_base() -> bool:
	return world == run.base


func _build_scene() -> void:
	clock = SimClock.new()
	clock.name = "SimClock"
	add_child(clock)
	clock.setup(run.step)

	camera = CameraController.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	camera.setup(world.grid.get_pixel_size())
	camera.follow_source = func() -> Vector2: return run.drone.get_draw_position(clock.alpha)
	camera.view_changed.connect(_on_view_changed)

	planet_view = WorldView.new()
	planet_view.name = "PlanetView"
	add_child(planet_view)
	planet_view.setup(run.planet, camera, clock)
	base_view = WorldView.new()
	base_view.name = "BaseView"
	add_child(base_view)
	base_view.setup(run.base, camera, clock)
	active_view = _view_of(world)
	planet_view.set_active(active_view == planet_view)
	base_view.set_active(active_view == base_view)

	preview = PlacementPreview.new()
	preview.name = "Preview"
	add_child(preview)

	drone_view = DroneView.new()
	drone_view.name = "Drone"
	add_child(drone_view)

	tools = ToolController.new()
	tools.name = "Tools"
	add_child(tools)
	tools.setup(world, camera, preview)
	tools.pause_menu_requested.connect(open_pause_menu)
	drone_view.setup(run.drone, clock, tools)

	drone_controller = DroneController.new()
	drone_controller.name = "DroneController"
	add_child(drone_controller)
	drone_controller.setup(run.drone)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.closed.connect(_update_input_enabled)

	Settings.changed.connect(_on_setting_changed)


func _unhandled_input(event: InputEvent) -> void:
	if tools == null or not tools.input_enabled:
		return
	if event.is_action_pressed("use_gateway"):
		run.use_gateway()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlay_ores"):
		_ores_shown = not _ores_shown
		ore_overlay.visible = _ores_shown
		hud.set_ore_legend_visible(_ores_shown)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlay_belts"):
		_belts_shown = not _belts_shown
		belt_overlay.visible = _belts_shown
		hud.set_belt_legend_visible(_belts_shown)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_grid"):
		Settings.set_value(&"game/show_grid", not Settings.get_bool(&"game/show_grid"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		clock.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_1"):
		clock.set_speed_index(0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_2"):
		clock.set_speed_index(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_3"):
		clock.set_speed_index(2)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		_debug_enabled = hud.toggle_debug()
		grid_overlay.set_chunk_lines_visible(_debug_enabled)
		_update_grid_visibility()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if tools == null:
		return
	# Модальный диалог подтверждения тоже блокирует ввод в мир.
	var enabled := not pause_menu.is_open() and not hud.is_modal_open()
	if enabled != tools.input_enabled:
		_update_input_enabled()


func _update_input_enabled() -> void:
	var enabled := not pause_menu.is_open() and not hud.is_modal_open()
	tools.input_enabled = enabled
	camera.input_enabled = enabled
	drone_controller.input_enabled = enabled
	# Пока открыто меню паузы, время мира стоит (выбор скорости игрока не меняется).
	clock.blocked = pause_menu.is_open()


## Дрон прошёл через шлюз: активным становится вид мира, где он оказался.
func _on_drone_changed_world() -> void:
	world = run.drone.world
	active_view.set_active(false)
	active_view = _view_of(world)
	active_view.set_active(true)
	ore_overlay.visible = _ores_shown
	belt_overlay.visible = _belts_shown
	grid_overlay.set_chunk_lines_visible(_debug_enabled)
	tools.set_world(world)
	camera.set_map_size(world.grid.get_pixel_size())
	hud.on_world_changed()
	_on_view_changed()
	terrain.flush()


func _view_of(target: GameWorld) -> WorldView:
	return base_view if target == run.base else planet_view


func _on_view_changed() -> void:
	terrain.update_view(camera.get_world_view_rect(), camera.user_zoom)
	_update_grid_visibility()


func _update_grid_visibility() -> void:
	var wanted := Settings.get_bool(&"game/show_grid") or _debug_enabled
	grid_overlay.visible = wanted and camera.user_zoom >= GameConst.GRID_MIN_ZOOM


func _on_setting_changed(key: StringName) -> void:
	if key == &"game/show_grid":
		_update_grid_visibility()
