extends Node
## Отладочный прогон со скриншотами и проверкой инструментов настоящими событиями ввода.
## Добавляется главным меню или игровой сценой только при флаге командной строки:
##   godot --path D:/Mind res://core/game.tscn -- --autoshot --autoshot-dir=C:/путь/к/папке
## Мышь не двигает; изменённые настройки в конце восстанавливает.

var _dir: String = "user://autoshot"
var _results := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autoshot-dir="):
			_dir = arg.substr("--autoshot-dir=".length())
	DirAccess.make_dir_recursive_absolute(_dir)
	var parent := get_parent()
	if parent is Game:
		_run_game(parent as Game)
	elif parent is MainMenu:
		_run_menu(parent as MainMenu)


# --- Главное меню ---

func _run_menu(menu: MainMenu) -> void:
	await _frames(40)
	await _shot("m01_menu.png")
	menu.call("_show_level_select")
	await _frames(10)
	await _shot("m02_levels.png")
	menu.call("_show_settings")
	await _frames(10)
	await _shot("m03_settings.png")
	get_tree().quit()


# --- Игра ---

func _run_game(game: Game) -> void:
	var original_language: Variant = Settings.get_value(&"game/language")
	await _frames(30)
	await _measure_frames("старт")
	await _shot("g01_start.png")

	await _run_interaction(game)
	await _run_production_chain(game)

	game.ore_overlay.visible = true
	game.hud.set_ore_legend_visible(true)
	game.camera.focus_on(game.world.get_core().get_world_center(), 0.6)
	await _frames(10)
	await _shot("g04_ore_overlay.png")
	game.ore_overlay.visible = false
	game.hud.set_ore_legend_visible(false)

	game.hud.toggle_debug()
	game.grid_overlay.set_chunk_lines_visible(true)
	game.camera.focus_on(game.world.get_core().get_world_center(), 0.8)
	await _frames(20)
	await _shot("g05_debug.png")
	game.hud.toggle_debug()
	game.grid_overlay.set_chunk_lines_visible(false)

	game.open_pause_menu()
	await _frames(10)
	await _shot("g06_pause.png")
	game.pause_menu.call("_open_settings")
	var settings: SettingsMenu = game.pause_menu.get("_settings")
	var tabs: TabContainer = settings.get("_tabs")
	tabs.current_tab = 2
	await _frames(10)
	await _shot("g07_settings_controls.png")
	Settings.set_value(&"game/language", "en" if original_language == "ru" else "ru")
	await _frames(10)
	(settings.get("_tabs") as TabContainer).current_tab = 1
	await _frames(10)
	await _shot("g08_settings_other_language.png")
	Settings.set_value(&"game/language", original_language)
	Settings.save_now()

	var failed := 0
	for line in _results:
		if line.begins_with("FAIL"):
			failed += 1
		print("autotest ", line)
	print("autotest: провалов %d из %d" % [failed, _results.size()])
	get_tree().quit()


## Инструменты через настоящие события ввода.
func _run_interaction(game: Game) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var core := world.get_core()
	var base := core.origin
	var conveyor := Registry.get_building(&"conveyor")
	game.camera.focus_on(core.get_world_center(), 1.0)
	await _frames(5)

	# Протягивание L-линии лент: 7 тайлов вправо и 3 вниз = 10 лент.
	var copper_before := world.core_storage.get_count(Registry.get_item(&"copper").index)
	var before := bm.get_count()
	tools.select_building(conveyor)
	var a := base + Vector2i(-12, 6)
	var b := base + Vector2i(-6, 9)
	await _mouse_move(game, a)
	await _mouse_button(game, a, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, a + Vector2i(1, 0))
	await _mouse_move(game, b)
	await _frames(3)
	await _shot("i01_drag_line.png")
	await _mouse_button(game, b, MOUSE_BUTTON_LEFT, false)
	_expect(bm.get_count() - before == 10, "протягивание L-линии ставит 10 лент (поставлено %d)" % (bm.get_count() - before))
	_expect(copper_before - world.core_storage.get_count(Registry.get_item(&"copper").index) == 10, "линия списала 10 меди")
	var corner := bm.get_at(Vector2i(b.x, a.y))
	_expect(corner != null and corner.rotation == GameConst.Dir.DOWN, "угол линии повёрнут вниз")

	# Переключение раздела меню, когда здание уже в руке (настоящий клик по вкладке).
	var menu := _find_child_of_type(game.hud, "BuildMenu") as BuildMenu
	var extraction_tab: Button = (menu.get("_category_buttons") as Array)[BuildingDef.Category.EXTRACTION]
	await _click_control(extraction_tab)
	_expect(int(menu.get("_category")) == BuildingDef.Category.EXTRACTION, "с лентой в руке вкладка «Добыча» открывается")
	_expect(tools.mode == ToolController.Mode.PLACE and tools.place_def == conveyor, "здание остаётся в руке при смене вкладки")
	await _frames(3)
	await _shot("i02_tab_switch.png")
	var drill_button: Button = (menu.get("_building_buttons") as Dictionary)[&"mechanical_drill"]
	var rect_before := drill_button.get_global_rect()
	await _mouse_move_screen(rect_before.get_center())
	await _frames(3)
	_expect(drill_button.get_global_rect() == rect_before, "наведение на кнопку не сдвигает панель")
	await _click_control(drill_button)
	_expect(tools.place_def == Registry.get_building(&"mechanical_drill"), "клик по буру в другой вкладке выбирает бур")

	# R поворачивает здание в руке.
	var rotation_before := tools.rotation
	await _key(KEY_R)
	_expect(tools.rotation == (rotation_before + 1) % 4, "R поворачивает здание в руке")

	# ПКМ-клик отменяет инструмент.
	await _mouse_button(game, a, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button(game, a, MOUSE_BUTTON_RIGHT, false)
	_expect(tools.mode == ToolController.Mode.NONE, "ПКМ-клик отменяет инструмент")

	# R пустой рукой поворачивает стоящее здание под курсором.
	var straight := bm.get_at(a)
	await _mouse_move(game, a)
	var old_rotation := straight.rotation
	await _key(KEY_R)
	_expect(straight.rotation == (old_rotation + 1) % 4, "R пустой рукой поворачивает ленту под курсором")
	await _key(KEY_R)
	await _key(KEY_R)
	await _key(KEY_R)
	_expect(straight.rotation == old_rotation, "четыре поворота возвращают исходное направление")

	# Пипетка копирует здание под курсором.
	await _mouse_move(game, corner.origin)
	await _key(KEY_Q)
	_expect(tools.mode == ToolController.Mode.PLACE and tools.place_def == conveyor and tools.rotation == GameConst.Dir.DOWN, "пипетка копирует ленту и поворот")

	# Бур ставится только на руду.
	var drill := Registry.get_building(&"mechanical_drill")
	tools.select_building(drill)
	var no_ore := _find_empty_spot(world, drill, base, 16)
	await _mouse_move(game, no_ore)
	_expect(tools.plan_problem == BuildingManager.Check.NO_ORE, "превью бура без руды показывает причину")
	var ore_spot := _find_drill_spot(world, drill, base, 14)
	_expect(ore_spot != Vector2i(-1, -1), "рядом с ядром есть место для бура на руде")
	before = bm.get_count()
	await _mouse_move(game, ore_spot)
	await _mouse_button(game, ore_spot, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, ore_spot, MOUSE_BUTTON_LEFT, false)
	_expect(bm.get_count() - before == 1, "клик ставит бур на руду")

	# Esc сбрасывает инструмент, повторный Esc открывает меню паузы, пауза останавливает время.
	await _key(KEY_ESCAPE)
	_expect(tools.mode == ToolController.Mode.NONE, "Esc сбрасывает инструмент")
	await _key(KEY_ESCAPE)
	_expect(game.pause_menu.is_open() and not game.clock.is_running(), "Esc открывает паузу и останавливает время")
	var tick_in_menu := world.simulation.tick
	await _frames(20)
	_expect(world.simulation.tick == tick_in_menu, "в меню паузы тики не идут")
	await _key(KEY_ESCAPE)
	_expect(not game.pause_menu.is_open() and tools.input_enabled, "Esc закрывает паузу")

	# Пробел — пауза, 3 — скорость x4.
	await _key(KEY_SPACE)
	_expect(game.clock.paused, "пробел ставит паузу")
	await _key(KEY_3)
	_expect(not game.clock.paused and game.clock.get_speed() == 4, "клавиша 3 включает x4")
	await _key(KEY_1)

	# Shift+ЛКМ рамкой сносит линию и бур, ядро не трогает, стоимость возвращается.
	var rect := Rect2i(a, Vector2i.ONE).merge(Rect2i(b, Vector2i.ONE)).merge(Rect2i(ore_spot - Vector2i.ONE, Vector2i(3, 3)))
	var expected := 0
	for x in bm.collect_in_rect(rect):
		if x.def.removable:
			expected += 1
	before = bm.get_count()
	await _key_hold(KEY_SHIFT, true)
	await _mouse_move(game, rect.position)
	await _mouse_button(game, rect.position, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, rect.end - Vector2i.ONE)
	await _frames(3)
	await _shot("i03_delete_rect.png")
	await _mouse_button(game, rect.end - Vector2i.ONE, MOUSE_BUTTON_LEFT, false)
	await _key_hold(KEY_SHIFT, false)
	_expect(before - bm.get_count() == expected and expected >= 11, "рамка сносит %d построек (снесено %d)" % [expected, before - bm.get_count()])
	_expect(world.get_core() != null, "ядро уцелело")

	await _key(KEY_X)
	_expect(tools.mode == ToolController.Mode.DELETE, "X включает режим сноса")
	await _key(KEY_X)
	_expect(tools.mode == ToolController.Mode.NONE, "повторный X выключает режим сноса")


## Цепочка «бур → лента → ядро»: предметы едут и засчитываются.
func _run_production_chain(game: Game) -> void:
	var world := game.world
	var bm := world.buildings
	var core := world.get_core()
	var drill := Registry.get_building(&"mechanical_drill")
	var conveyor := Registry.get_building(&"conveyor")
	var copper := Registry.get_item(&"copper").index
	var start_delivered := world.core_storage.delivered[copper]

	# Несколько буров на ближайшей медной залежи, лента вдоль них и дальше к ядру.
	var spot := _find_drill_spot(world, drill, core.origin, 20)
	var placed_drills := 0
	for dx in [0, 2, 4]:
		for dy in [0, -2]:
			if bm.place(drill, spot + Vector2i(dx, dy), 0) != null:
				placed_drills += 1
	var target := core.origin + Vector2i(1, -1)
	var line_start := spot + Vector2i(0, 2)
	for step in LinePlanner.l_path(line_start, Vector2i(target.x, line_start.y), true, 0):
		bm.place(conveyor, Vector2i(step.x, step.y), step.z)
	var turn := Vector2i(target.x, line_start.y)
	var vertical_dir := GameConst.Dir.DOWN if target.y > turn.y else GameConst.Dir.UP
	for step in LinePlanner.l_path(turn, target, false, vertical_dir):
		bm.place(conveyor, Vector2i(step.x, step.y), vertical_dir if Vector2i(step.x, step.y) != target else GameConst.Dir.DOWN)
	_expect(placed_drills > 0, "поставлено буров на меди: %d" % placed_drills)

	game.clock.set_speed_index(2)
	game.camera.focus_on(Vector2(spot * GameConst.TILE_SIZE) + Vector2(160, 48), 1.3)
	await _wait_ticks(world, 40 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	await _frames(20)
	await _shot("g02_items_on_belts.png")
	_expect(world.core_storage.delivered[copper] > start_delivered, "медь дошла до ядра (+%d)" % (world.core_storage.delivered[copper] - start_delivered))
	await _measure_frames("работающая цепочка")

	# Все типы предметов на отдельной ленте (проверка ориентации иконок в MultiMesh).
	var row_origin := core.origin + Vector2i(-6, 6)
	var sys := world.simulation.conveyors
	for i in Registry.items.size():
		var belt := bm.place(conveyor, row_origin + Vector2i(i, 0), GameConst.Dir.RIGHT, true)
		sys.call("_insert", sys.index_of(belt.id), Registry.items[i].index, ConveyorSystem.UNITS / 2, 0.0, 0)
	game.clock.toggle_pause()
	game.camera.focus_on(Vector2(row_origin * GameConst.TILE_SIZE) + Vector2(Registry.items.size() * 16, 16), 3.0)
	await _frames(15)
	await _shot("g02b_item_types.png")
	game.clock.toggle_pause()
	for i in Registry.items.size():
		world.buildings.remove(bm.get_at(row_origin + Vector2i(i, 0)), true)
	game.camera.focus_on(Vector2(spot * GameConst.TILE_SIZE) + Vector2(160, 48), 1.3)

	# Поворот ленты посреди работающей линии: поток прерывается, обратный поворот его восстанавливает.
	var middle := bm.get_at(line_start + Vector2i(3, 0))
	world.rotate_building(middle, 1)
	await _frames(30)
	await _shot("g03_rotated_belt.png")
	world.rotate_building(middle, 3)
	var delivered_after_fix := world.core_storage.delivered[copper]
	await _wait_ticks(world, 20 * GameConst.TICK_RATE)
	_expect(world.core_storage.delivered[copper] > delivered_after_fix, "после обратного поворота поток восстановился")


# --- Утилиты ---

func _expect(condition: bool, text: String) -> void:
	_results.append(("OK   " if condition else "FAIL ") + text)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _wait_ticks(world: GameWorld, ticks: int) -> void:
	var target := world.simulation.tick + ticks
	var guard := 0
	while world.simulation.tick < target and guard < 20000:
		await get_tree().process_frame
		guard += 1


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_dir.path_join(file_name))
	print("autoshot: ", file_name)


func _measure_frames(label: String) -> void:
	var start := Time.get_ticks_usec()
	var worst := 0
	var last := start
	for i in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	print("autoshot perf (%s): средний кадр %.2f мс, худший %.2f мс" % [label, (last - start) / 120000.0, worst / 1000.0])


func _find_drill_spot(world: GameWorld, drill: BuildingDef, center: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_tiles := 0
	for y in range(center.y - radius, center.y + radius):
		for x in range(center.x - radius, center.x + radius):
			var origin := Vector2i(x, y)
			if world.buildings.check_place(drill, origin, 0) != BuildingManager.Check.OK:
				continue
			var found := (drill as DrillDef).find_ore(world.grid, origin)
			if Registry.ores[found.x - 1].id == &"copper" and found.y > best_tiles:
				best = origin
				best_tiles = found.y
	return best


## Свободное место без руды под буром.
func _find_empty_spot(world: GameWorld, drill: BuildingDef, center: Vector2i, radius: int) -> Vector2i:
	for y in range(center.y + 4, center.y + radius):
		for x in range(center.x - radius, center.x + radius):
			var origin := Vector2i(x, y)
			if world.buildings.check_place(drill, origin, 0) == BuildingManager.Check.NO_ORE:
				return origin
	return center


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_script() != null and (child.get_script() as Script).get_global_name() == type_name:
			return child
		var nested := _find_child_of_type(child, type_name)
		if nested != null:
			return nested
	return null


func _tile_to_screen(game: Game, tile: Vector2i) -> Vector2:
	var world_pos := Vector2(tile * GameConst.TILE_SIZE) + Vector2(16, 16)
	return (world_pos - game.camera.position) * game.camera.zoom + get_viewport().get_visible_rect().size * 0.5


func _mouse_move(game: Game, tile: Vector2i) -> void:
	await _mouse_move_screen(_tile_to_screen(game, tile))


func _mouse_move_screen(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	Input.parse_input_event(event)
	await _frames(2)


func _mouse_button(game: Game, tile: Vector2i, button: MouseButton, pressed: bool) -> void:
	await _mouse_button_screen(_tile_to_screen(game, tile), button, pressed)


func _mouse_button_screen(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	event.shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	Input.parse_input_event(event)
	await _frames(2)


func _click_control(control: Control) -> void:
	var pos := control.get_global_rect().get_center()
	await _mouse_move_screen(pos)
	await _mouse_button_screen(pos, MOUSE_BUTTON_LEFT, true)
	await _mouse_button_screen(pos, MOUSE_BUTTON_LEFT, false)


func _key(code: Key) -> void:
	await _key_hold(code, true)
	await _key_hold(code, false)


func _key_hold(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = code == KEY_SHIFT and pressed
	Input.parse_input_event(event)
	await _frames(2)
