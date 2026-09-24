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
var mining_view: WorldView
var boiler_view: WorldView
var active_view: WorldView
var preview: PlacementPreview
var drone_view: DroneView
var camera: CameraController
var tools: ToolController
var drone_controller: DroneController
## Журнал сети: когда последний раз писали сводку игры (мс).
var _last_log_msec: int = 0
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

	# Клиент вошёл в сетевую игру ещё из меню: забег уже пришёл снимком.
	if Session.net.role == NetSession.Role.CLIENT and Session.net.run != null:
		run = Session.net.run
		_start()
		return
	# Дальше — только своя игра (новая, загрузка, уровень). Клиентская сессия, если она ещё
	# висит, к ней отношения не имеет: оставить её — и все команды новой игры уйдут чужому хосту.
	if Session.net.role == NetSession.Role.CLIENT:
		Session.net.close()
		if Session.lobbies != null:
			Session.lobbies.leave()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--load="):
			Session.load_path = arg.substr("--load=".length())
		elif arg == "--creative":
			# Творческий забег прямо из командной строки: нужен автопрогону и ручной отладке.
			Session.creative = true
		elif arg == "--cheats" or arg == "--autoshot":
			# Автопрогон нажимает отладочные клавиши (F3, ускорение времени) — ему нужны читы.
			Session.cheats = true
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
		run = Run.create_new(run_seed, Session.creative, Session.cheats)
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

	run = Run.create(level, map, Session.creative, Session.cheats)
	_start()


func _start() -> void:
	world = run.drone.world
	_build_scene()
	_connect_run_signals()
	_last_autosave_tick = run.base.simulation.tick

	# Отладочные прогоны (tests/), только по флагам командной строки.
	var args := OS.get_cmdline_user_args()
	if args.has("--autoshot"):
		var shot_script: Script = load("res://tests/autoshot.gd")
		if shot_script != null:
			add_child(shot_script.new())
	if args.has("--players-check"):
		var players_script: Script = load("res://tests/players_check.gd")
		if players_script != null:
			add_child(players_script.new())
	for arg in args:
		if arg.begins_with("--stress="):
			var stress_script: Script = load("res://tests/stress_render.gd")
			if stress_script != null:
				add_child(stress_script.new())


## Подписки на сам забег. Забег заменяется целиком (вход в сеть, починка снимком),
## поэтому подписки живут отдельно от построения сцены и ставятся заново на новый забег.
func _connect_run_signals() -> void:
	run.drone_changed_world.connect(_on_drone_changed_world)
	run.planet_changed.connect(_on_planet_changed)
	run.teleport_starting.connect(_on_teleport_starting)


func _on_teleport_starting() -> void:
	save_named(TELEPORT_AUTOSAVE_FILE, tr("SAVE_NAME_BEFORE_TELEPORT"), false)

	camera.focus_on(run.drone.position, 1.0)
	_on_view_changed()
	terrain.flush()


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


## Один из этажей базы открыт на экране (подземный, добычи или котельная).
func is_in_base() -> bool:
	return world == run.base or world == run.mining or world == run.boiler


func _build_scene() -> void:
	clock = SimClock.new()
	clock.name = "SimClock"
	add_child(clock)
	clock.setup(_net_step, _net_can_step, _net_time_scale)
	clock.state_changed.connect(_on_clock_changed)
	# Сессия и настройки живут дольше сцены, поэтому подписываемся один раз:
	# при пересборке (починка снимком) эти же сигналы иначе подключились бы повторно.
	_connect_once(Session.net.run_replaced, _on_run_replaced)
	_connect_once(Session.net.time_state, _on_net_time)
	_connect_once(Session.net.notice, _on_net_notice)
	_connect_once(Settings.changed, _on_setting_changed)
	if Session.net.is_networked():
		Session.net.set_run(run)
	Session.predict.setup(run)

	camera = CameraController.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	camera.setup(world.get_play_rect_px())
	camera.follow_source = func() -> Vector2:
		var at := run.drone.get_draw_position(clock.alpha)
		return at + drone_view.local_offset() if drone_view != null else at
	camera.view_changed.connect(_on_view_changed)

	planet_view = WorldView.new()
	planet_view.name = "PlanetView"
	add_child(planet_view)
	planet_view.setup(run.planet, camera, clock)
	base_view = WorldView.new()
	base_view.name = "BaseView"
	add_child(base_view)
	base_view.setup(run.base, camera, clock)
	mining_view = WorldView.new()
	mining_view.name = "MiningView"
	add_child(mining_view)
	mining_view.setup(run.mining, camera, clock)
	boiler_view = WorldView.new()
	boiler_view.name = "BoilerView"
	add_child(boiler_view)
	boiler_view.setup(run.boiler, camera, clock)
	run.base.bounds_changed.connect(_on_bounds_changed.bind(run.base))
	run.mining.bounds_changed.connect(_on_bounds_changed.bind(run.mining))
	run.boiler.bounds_changed.connect(_on_bounds_changed.bind(run.boiler))
	run.planet.bounds_changed.connect(_on_bounds_changed.bind(run.planet))
	active_view = _view_of(world)
	for view in [planet_view, base_view, mining_view, boiler_view]:
		view.set_active(view == active_view)

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
	# Раньше часов (у них -100): иначе нажатие, сделанное в этом кадре, попадёт в симуляцию
	# только со следующего — лишний тик задержки на ровном месте.
	drone_controller.process_priority = -200
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
	# Окно пульта платформы забирает WASD себе, поэтому управление переключается вместе с выбором.
	tools.selection_changed.connect(_update_input_enabled)


## Подписка, которая переживает пересборку сцены.
func _connect_once(sig: Signal, handler: Callable) -> void:
	if not sig.is_connected(handler):
		sig.connect(handler)


func _on_net_notice(text: String) -> void:
	Events.toast(text, Events.ToastKind.INFO)


## Выделения и чертежи напарников на этом этаже — в превью, каждому свой цвет.
func _show_remote_marks() -> void:
	var marks: Array = []
	var shared := Session.net.marks_in(run.floor_of(world))
	for id in shared:
		var player := run.get_player(id)
		if player == null:
			continue
		var entry: Dictionary = shared[id]
		marks.append({"rect": entry.get("sel", Rect2i()), "plan": entry.get("plan", Rect2i()),
			"color": player.color, "name": player.name})
	preview.set_remote_marks(marks)


## Можно ли считать очередной тик: в сетевой игре клиент ждёт список команд от хоста.
## Заодно забираем пришедшие пакеты — так ожидание короче ровно на один кадр.
func _net_can_step() -> bool:
	if not Session.net.is_networked():
		return true
	_rebuilt_now = false
	Session.net.poll()
	if _rebuilt_now:
		# Пока опрашивали сеть, пришёл снимок и сцена собрана заново — эти часы уже не у дел.
		return false
	return Session.net.can_step()


## Темп времени: хост идёт ровно 1.0, клиент подстраивается под него, чтобы держать
## небольшой запас подтверждённых тиков (иначе сеть видна как рывки, а просадки кадров
## превращаются в невосполнимое отставание).
func _net_time_scale() -> float:
	return Session.net.time_scale()


func _net_step() -> void:
	run.step()
	Session.net.after_step()
	if drone_view != null:
		drone_view.after_tick()


## Время общее: свою паузу и скорость отправляем всем, чужие принимаем молча.
var _applying_net_time: bool = false
## Сцену пересобрали прямо сейчас (внутри опроса сети).
var _rebuilt_now: bool = false


func _on_clock_changed() -> void:
	if _applying_net_time or not Session.net.is_networked():
		return
	Session.net.send_time(clock.paused, clock.speed_index)


func _on_net_time(paused: bool, speed_index: int) -> void:
	_applying_net_time = true
	clock.speed_index = clampi(speed_index, 0, SimClock.SPEEDS.size() - 1)
	clock.paused = paused
	clock.state_changed.emit()
	_applying_net_time = false


## Клиенту пришёл снимок мира: старый забег выбрасываем и собираем сцену заново.
func _on_run_replaced(fresh: Run) -> void:
	if fresh == run:
		return
	var old := run
	run = fresh
	world = run.drone.world
	# Сцену могут пересобрать прямо посреди цикла тиков (снимок приходит из poll внутри часов),
	# поэтому текущему кадру шагать больше нечем.
	_rebuilt_now = true
	_rebuild_for_new_run()
	if old != null:
		old.dispose()


## Пересборка сцены под новый забег.
##
## Сносятся ВСЕ дети, включая часы: _build_scene() заводит часы сам, и оставленные старые
## стали бы вторым двигателем симуляции — мир шагал бы дважды, интерполяция считалась бы
## по чужому alpha, и каждая следующая починка добавляла бы ещё одни часы. Выбор скорости
## и паузу переносим руками, они к узлу не привязаны.
func _rebuild_for_new_run() -> void:
	var speed_index := clock.speed_index if clock != null else 0
	var paused := clock.paused if clock != null else false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_scene()
	clock.speed_index = speed_index
	clock.paused = paused
	_connect_run_signals()
	Session.net.set_run(run)
	camera.focus_on(run.drone.position, 1.0)
	_on_view_changed()
	terrain.flush()


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
		# Ускорение времени — чит: в обычном выживании его нет.
		if run.cheats_allowed():
			clock.set_speed_index(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_3"):
		if run.cheats_allowed():
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
	elif event.is_action_pressed("chat"):
		# Enter открывает строку чата, а пока она открыта — управление дроном выключено.
		if hud.chat_panel.is_typing():
			hud.chat_panel.close_input()
		else:
			hud.chat_panel.open_input()
		_update_input_enabled()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		if not run.cheats_allowed():
			get_viewport().set_input_as_handled()
			return
		_debug_enabled = hud.toggle_debug()
		grid_overlay.set_chunk_lines_visible(_debug_enabled)
		_update_grid_visibility()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if Session.net.is_networked():
		Session.net.poll()
	if tools == null:
		return
	if Session.net.is_networked():
		Session.net.send_cursor(camera.get_mouse_world(), run.floor_of(world),
			tools.shared_selection(), tools.shared_plan())
		_show_remote_marks()
	if Session.net.is_networked() and Time.get_ticks_msec() - _last_log_msec > 5000:
		_last_log_msec = Time.get_ticks_msec()
		_log_state()
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


## Сводка того, что видит игрок: почему дрон может не слушаться, если сеть в порядке.
func _log_state() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	NetLog.write("игра", "управление %s (пауза-меню %s, модальное окно %s), инструмент %s%s, часы: пауза %s, стоп %s, скорость %d, фокус ввода: %s, мир на экране: %s" % [
		"вкл" if drone_controller.input_enabled else "ВЫКЛ", pause_menu.is_open(), hud.is_modal_open(),
		ToolController.Mode.keys()[tools.mode], (" " + String(tools.place_def.id)) if tools.place_def != null and tools.mode == ToolController.Mode.PLACE else "",
		clock.paused, clock.blocked, clock.speed_index,
		("%s (%s)" % [focus.name, focus.get_class()]) if focus != null else "нет",
		"база" if world == run.base else "планета"])


func _update_input_enabled() -> void:
	var enabled := not pause_menu.is_open() and not hud.is_modal_open()
	if Session.net.is_networked() and drone_controller != null and enabled != drone_controller.input_enabled:
		NetLog.write("игра", "управление %s (пауза-меню %s, модальное окно %s)" % [
			"включено" if enabled else "ВЫКЛЮЧЕНО", pause_menu.is_open(), hud.is_modal_open()])
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
	for view in [planet_view, base_view, mining_view, boiler_view]:
		view.set_active(view == active_view)
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
	if target == run.base:
		return base_view
	if target == run.mining:
		return mining_view
	if target == run.boiler:
		return boiler_view
	return planet_view


func _on_view_changed() -> void:
	terrain.update_view(camera.get_world_view_rect(), camera.user_zoom)
	_update_grid_visibility()


func _update_grid_visibility() -> void:
	var wanted := Settings.get_bool(&"game/show_grid") or _debug_enabled
	grid_overlay.visible = wanted and camera.user_zoom >= GameConst.GRID_MIN_ZOOM


func _on_setting_changed(key: StringName) -> void:
	if key == &"game/show_grid":
		_update_grid_visibility()
