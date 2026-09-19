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

## Имена файлов служебных сохранений.
const AUTOSAVE_FILE := "autosave"
const TELEPORT_AUTOSAVE_FILE := "autosave_teleport"
const QUICKSAVE_FILE := "quicksave"

var _debug_enabled: bool = false
var _last_autosave_tick: int = 0
var _ores_shown: bool = false
var _belts_shown: bool = false
var _ranges_shown: bool = false
var _power_shown: bool = false


func _ready() -> void:
	Registry.ensure_loaded()
	ArtRegistry.ensure_built()

	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--load="):
			Session.load_path = arg.substr("--load=".length())
	if not Session.load_path.is_empty():
		var path := Session.load_path
		Session.load_path = ""
		run = SaveIO.load_run(path)
		if run == null:
			Events.toast(tr("TOAST_LOAD_FAILED"), Events.ToastKind.WARNING)
			Session.exit_to_menu.call_deferred()
			return
		_start()
		Events.toast(tr("TOAST_LOADED") % String(SaveIO.read_header(path).get("name", "")), Events.ToastKind.SUCCESS)
		return
	var run_seed := Session.run_seed
	for arg in args:
		if arg.begins_with("--seed="):
			run_seed = arg.substr("--seed=".length()).to_int()
	if run_seed >= 0:
		run = Run.create_new(run_seed, Session.creative)
		_start()
		return

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
	_start()


func _start() -> void:
	world = run.drone.world
	_build_scene()
	run.drone_changed_world.connect(_on_drone_changed_world)
	run.planet_changed.connect(_on_planet_changed)
	run.teleport_starting.connect(func() -> void: save_named(TELEPORT_AUTOSAVE_FILE, tr("SAVE_NAME_BEFORE_TELEPORT"), false))
	_last_autosave_tick = run.base.simulation.tick

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


## Сохранить забег в служебный слот: file_id — имя файла, display_name — имя в списке.
func save_named(file_id: String, display_name: String, announce: bool) -> void:
	var error := SaveIO.save_run_as(run, file_id, display_name)
	_last_autosave_tick = run.base.simulation.tick
	if error != OK:
		Events.toast(tr("TOAST_SAVE_FAILED"), Events.ToastKind.WARNING)
	elif announce:
		Events.toast(tr("TOAST_SAVED") % display_name, Events.ToastKind.SUCCESS)


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
	camera.setup(world.get_play_rect_px())
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
	run.base.bounds_changed.connect(_on_bounds_changed.bind(run.base))
	run.planet.bounds_changed.connect(_on_bounds_changed.bind(run.planet))
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
	drone_view.setup(run, world, clock, tools)

	drone_controller = DroneController.new()
	drone_controller.name = "DroneController"
	add_child(drone_controller)
	drone_controller.setup(run.drone, world)
	run.players_changed.connect(_on_players_changed)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.run = run
	pause_menu.closed.connect(_update_input_enabled)

	Settings.changed.connect(_on_setting_changed)


func _unhandled_input(event: InputEvent) -> void:
	if tools == null or not tools.input_enabled:
		return
	if event.is_action_pressed("use_gateway"):
		if run.is_over_gateway() and not run.is_underground_open():
			Events.toast(tr("TOAST_LOCKED") % tr(Registry.get_research(&"underground").name_key), Events.ToastKind.WARNING)
		else:
			run.submit(Command.Kind.USE_PASSAGE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("research"):
		hud.research_window.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_save"):
		save_named(QUICKSAVE_FILE, tr("SAVE_NAME_QUICK"), true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		var path := SaveIO.slot_path(QUICKSAVE_FILE)
		if FileAccess.file_exists(path):
			Session.load_game(path)
		else:
			Events.toast(tr("TOAST_NO_QUICKSAVE"), Events.ToastKind.WARNING)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlay_ores"):
		_ores_shown = not _ores_shown
		ore_overlay.visible = _ores_shown
		hud.set_ore_legend_visible(_ores_shown)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlay_power"):
		_power_shown = not _power_shown
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlay_ranges"):
		_ranges_shown = not _ranges_shown
		planet_view.turret_view.show_ranges = _ranges_shown
		base_view.turret_view.show_ranges = _ranges_shown
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
	elif _debug_enabled and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_N and run.planet.threat != null:
		# Отладка (F3): вызвать следующую волну сейчас.
		run.planet.threat.call_next_wave(run.planet.simulation.tick)
		Events.toast(tr("TOAST_WAVE_CALLED"), Events.ToastKind.INFO)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("player_add"):
		if run.creative:
			run.submit(Command.Kind.PLAYER_ADD)
		else:
			Events.toast(tr("TOAST_PLAYER_CREATIVE_ONLY"), Events.ToastKind.WARNING)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("player_switch"):
		if run.players.size() > 1:
			switch_player()
		else:
			Events.toast(tr("TOAST_PLAYER_ALONE"), Events.ToastKind.INFO)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		_debug_enabled = hud.toggle_debug()
		grid_overlay.set_chunk_lines_visible(_debug_enabled)
		_update_grid_visibility()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if tools == null:
		return
	# Автосохранение по времени игры (тики базы), интервал — из настроек.
	var interval := Settings.get_int(&"game/autosave") * 60 * GameConst.TICK_RATE
	if interval > 0 and run.base.simulation.tick - _last_autosave_tick >= interval:
		save_named(AUTOSAVE_FILE, tr("SAVE_NAME_AUTO"), false)
	# Зоны питания видны, пока в руке постройка, связанная с электричеством, или курсор над опорой.
	var held: BuildingDef = tools.place_def if tools.mode == ToolController.Mode.PLACE else null
	var show_areas := (held != null and (held.power_use > 0.0 or held is PowerPoleDef or held is GeneratorDef)) \
		or tools.hover_building is PowerPole
	active_view.network_view.show_power_areas = show_areas
	active_view.network_view.power_overlay = _power_shown
	active_view.network_view.show_underground = held is FluidBuildingDef or tools.hover_building is UndergroundPipe
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
## Следующий игрок забега становится локальным (проверка совместной игры без сети).
func switch_player() -> void:
	if run.players.size() < 2:
		return
	var index := 0
	for i in run.players.size():
		if run.players[i].id == run.local_player:
			index = i
			break
	var next := run.players[(index + 1) % run.players.size()]
	run.set_local_player(next.id)
	Events.toast(tr("TOAST_PLAYER_SWITCHED") % next.name, Events.ToastKind.INFO)


## Состав игроков изменился: камера и управление смотрят на дрона локального игрока.
func _on_players_changed() -> void:
	if run.drone == null:
		return
	world = run.drone.world
	if active_view != _view_of(world):
		_on_drone_changed_world()
		return
	drone_view.set_world(world)
	drone_controller.setup(run.drone, world)
	tools.set_world(world)
	hud.on_world_changed()


func _on_drone_changed_world() -> void:
	world = run.drone.world
	active_view.set_active(false)
	active_view = _view_of(world)
	active_view.set_active(true)
	ore_overlay.visible = _ores_shown
	belt_overlay.visible = _belts_shown
	grid_overlay.set_chunk_lines_visible(_debug_enabled)
	tools.set_world(world)
	drone_view.set_world(world)
	drone_controller.setup(run.drone, world)
	camera.set_map_size(world.get_play_rect_px())
	hud.on_world_changed()
	_on_view_changed()
	terrain.flush()


## Телепорт: вид старой планеты заменяется видом новой, панели переключаются, показывается итог.
func _on_planet_changed() -> void:
	var old_view := planet_view
	planet_view = WorldView.new()
	planet_view.name = "PlanetView"
	add_child(planet_view)
	move_child(planet_view, old_view.get_index())
	planet_view.setup(run.planet, camera, clock)
	run.planet.bounds_changed.connect(_on_bounds_changed.bind(run.planet))
	planet_view.turret_view.show_ranges = _ranges_shown
	remove_child(old_view)
	old_view.queue_free()
	world = run.drone.world
	active_view = _view_of(world)
	planet_view.set_active(active_view == planet_view)
	base_view.set_active(active_view == base_view)
	ore_overlay.visible = _ores_shown
	belt_overlay.visible = _belts_shown
	grid_overlay.set_chunk_lines_visible(_debug_enabled)
	tools.set_world(world)
	drone_view.set_world(world)
	drone_controller.setup(run.drone, world)
	camera.set_map_size(world.get_play_rect_px())
	hud.on_planet_changed()
	_on_view_changed()
	terrain.flush()
	save_named(AUTOSAVE_FILE, tr("SAVE_NAME_AUTO"), false)


## Площадка или открытая часть этажа расширилась: камера получает новые границы, если этот мир на экране.
func _on_bounds_changed(changed: GameWorld) -> void:
	if changed == world:
		camera.set_map_size(world.get_play_rect_px())


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
