extends Node
## Отладочный прогон со скриншотами для визуальной проверки сборки.
## Добавляется главным меню или игровой сценой только при флаге командной строки:
##   godot --path D:/Mind -- --autoshot --autoshot-dir=C:/путь/к/папке
## Мышь не двигает; изменённые настройки в конце восстанавливает.

var _dir: String = "user://autoshot"


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


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_dir.path_join(file_name))
	print("autoshot: ", file_name)


## Проверка инструментов через настоящие события ввода (как от мыши и клавиатуры).
func _run_interaction(game: Game) -> void:
	var bm := game.world.buildings
	var tools := game.tools
	var core := game.world.get_core()
	var base := core.origin
	var conveyor := Registry.get_building(&"conveyor")
	var results := PackedStringArray()
	game.camera.focus_on(core.get_world_center(), 1.0)
	await _frames(5)

	# Протягивание L-линии лент: 6 тайлов вправо и 3 вниз = 10 лент.
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
	results.append(_expect(bm.get_count() - before == 10, "протягивание L-линии ставит 10 лент (поставлено %d)" % (bm.get_count() - before)))
	var corner := bm.get_at(Vector2i(b.x, a.y))
	results.append(_expect(corner != null and corner.rotation == GameConst.Dir.DOWN, "угол линии повёрнут вниз"))

	# R поворачивает.
	var rotation_before := tools.rotation
	await _key(KEY_R)
	results.append(_expect(tools.rotation == (rotation_before + 1) % 4, "R поворачивает здание"))

	# ПКМ-клик отменяет инструмент.
	await _mouse_button(game, a, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button(game, a, MOUSE_BUTTON_RIGHT, false)
	results.append(_expect(tools.mode == ToolController.Mode.NONE, "ПКМ-клик отменяет инструмент"))

	# Пипетка копирует здание под курсором.
	await _mouse_move(game, corner.origin)
	await _key(KEY_Q)
	results.append(_expect(tools.mode == ToolController.Mode.PLACE and tools.place_def == conveyor and tools.rotation == GameConst.Dir.DOWN, "пипетка копирует ленту и поворот"))

	# Одиночная установка бура 2x2.
	var drill := Registry.get_building(&"mechanical_drill")
	tools.select_building(drill)
	var drill_tile := base + Vector2i(-14, 12)
	before = bm.get_count()
	await _mouse_move(game, drill_tile)
	await _mouse_button(game, drill_tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, drill_tile, MOUSE_BUTTON_LEFT, false)
	results.append(_expect(bm.get_count() - before == 1, "клик ставит бур"))

	# Esc сбрасывает инструмент, повторный Esc открывает меню паузы.
	await _key(KEY_ESCAPE)
	results.append(_expect(tools.mode == ToolController.Mode.NONE, "Esc сбрасывает инструмент"))
	await _key(KEY_ESCAPE)
	results.append(_expect(game.pause_menu.is_open(), "Esc без инструмента открывает паузу"))
	await _key(KEY_ESCAPE)
	results.append(_expect(not game.pause_menu.is_open() and tools.input_enabled, "Esc закрывает паузу"))

	# Shift+ЛКМ рамкой сносит линию и бур, ядро не трогает.
	before = bm.get_count()
	var r0 := base + Vector2i(-16, 4)
	var r1 := base + Vector2i(4, 14)
	await _key_hold(KEY_SHIFT, true)
	await _mouse_move(game, r0)
	await _mouse_button(game, r0, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, r1)
	await _frames(3)
	await _shot("i02_delete_rect.png")
	await _mouse_button(game, r1, MOUSE_BUTTON_LEFT, false)
	await _key_hold(KEY_SHIFT, false)
	results.append(_expect(before - bm.get_count() == 11, "рамка сносит 11 построек (снесено %d)" % (before - bm.get_count())))
	results.append(_expect(game.world.get_core() != null, "ядро уцелело"))

	# X — режим сноса, клик по пустому месту ничего не ломает.
	await _key(KEY_X)
	results.append(_expect(tools.mode == ToolController.Mode.DELETE, "X включает режим сноса"))
	await _key(KEY_X)
	results.append(_expect(tools.mode == ToolController.Mode.NONE, "повторный X выключает режим сноса"))

	var failed := 0
	for line in results:
		if line.begins_with("FAIL"):
			failed += 1
		print("autotest ", line)
	print("autotest: провалов %d из %d" % [failed, results.size()])
	game.camera.focus_on(core.get_world_center(), 1.0)
	await _frames(5)


func _expect(condition: bool, text: String) -> String:
	return ("OK   " if condition else "FAIL ") + text


func _tile_to_screen(game: Game, tile: Vector2i) -> Vector2:
	var world := Vector2(tile * GameConst.TILE_SIZE) + Vector2(16, 16)
	return (world - game.camera.position) * game.camera.zoom + get_viewport().get_visible_rect().size * 0.5


func _mouse_move(game: Game, tile: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _tile_to_screen(game, tile)
	event.global_position = event.position
	Input.parse_input_event(event)
	await _frames(2)


func _mouse_button(game: Game, tile: Vector2i, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _tile_to_screen(game, tile)
	event.global_position = event.position
	event.shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	Input.parse_input_event(event)
	await _frames(2)


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


func _run_game(game: Game) -> void:
	var original_language: Variant = Settings.get_value(&"game/language")
	await _frames(30)
	# Замер без скриншотов: сохранение PNG искажает время кадра.
	var start := Time.get_ticks_usec()
	var worst := 0
	var last := start
	for i in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
	print("autoshot perf: средний кадр %.2f мс, худший %.2f мс" % [(last - start) / 120000.0, worst / 1000.0])
	await _shot("g01_start.png")
	await _run_interaction(game)

	# Несколько зданий вокруг ядра.
	var bm := game.world.buildings
	var core := game.world.get_core()
	var base := core.origin
	var conveyor := Registry.get_building(&"conveyor")
	for i in 8:
		bm.place(conveyor, base + Vector2i(3 + i, 1), 0)
	for i in 4:
		bm.place(conveyor, base + Vector2i(10, 2 + i), 1)
	bm.place(Registry.get_building(&"mechanical_drill"), base + Vector2i(-11, -8), 0)
	bm.place(Registry.get_building(&"pneumatic_drill"), base + Vector2i(-9, -8), 0)
	bm.place(Registry.get_building(&"silicon_smelter"), base + Vector2i(4, -5), 0)
	bm.place(Registry.get_building(&"alloy_mixer"), base + Vector2i(7, -6), 0)
	bm.place(Registry.get_building(&"router"), base + Vector2i(11, 1), 0)
	bm.place(Registry.get_building(&"junction"), base + Vector2i(-2, 4), 0)
	bm.place(Registry.get_building(&"sorter"), base + Vector2i(-3, 4), 0)
	bm.place(Registry.get_building(&"overflow_gate"), base + Vector2i(-4, 4), 0)
	bm.place(Registry.get_building(&"bridge_conveyor"), base + Vector2i(-5, 4), 0)
	bm.place(Registry.get_building(&"container"), base + Vector2i(-6, -3), 0)
	bm.place(Registry.get_building(&"vault"), base + Vector2i(-6, 6), 0)
	bm.place(Registry.get_building(&"kiln"), base + Vector2i(1, 7), 0)

	# Призраки размещения: валидные и невалидные.
	game.tools.set_process(false)
	var ghosts: Array[PlacementPreview.Ghost] = []
	for step in LinePlanner.l_path(base + Vector2i(3, 4), base + Vector2i(8, 8), true, 0):
		var origin := Vector2i(step.x, step.y)
		ghosts.append(PlacementPreview.Ghost.new(conveyor, origin, step.z, bm.check_place(conveyor, origin, step.z)))
	var smelter := Registry.get_building(&"graphite_press")
	ghosts.append(PlacementPreview.Ghost.new(smelter, base + Vector2i(-1, 0), 0, bm.check_place(smelter, base + Vector2i(-1, 0), 0)))
	game.preview.set_ghosts(ghosts)
	game.camera.focus_on(core.get_world_center() + Vector2(40, 0), 1.25)
	await _frames(10)
	await _shot("g02_buildings.png")
	game.preview.clear()

	game.ore_overlay.visible = true
	game.hud.set_ore_legend_visible(true)
	game.camera.focus_on(core.get_world_center(), 0.6)
	await _frames(10)
	await _shot("g03_ore_overlay.png")
	game.ore_overlay.visible = false
	game.hud.set_ore_legend_visible(false)

	game.hud.toggle_debug()
	game.grid_overlay.set_chunk_lines_visible(true)
	game.camera.focus_on(core.get_world_center(), 0.5)
	await _frames(15)
	await _shot("g04_debug.png")

	game.camera.focus_on(game.world.grid.get_pixel_size() * 0.5, 0.2)
	await _frames(15)
	await _shot("g05_lod.png")
	game.hud.toggle_debug()

	game.camera.focus_on(core.get_world_center(), 1.0)
	game.open_pause_menu()
	await _frames(10)
	await _shot("g06_pause.png")
	game.pause_menu.call("_open_settings")
	await _frames(10)
	await _shot("g07_settings_graphics.png")
	var settings: SettingsMenu = game.pause_menu.get("_settings")
	var tabs: TabContainer = settings.get("_tabs")
	tabs.current_tab = 2
	await _frames(10)
	await _shot("g08_settings_controls.png")
	Settings.set_value(&"game/language", "en" if original_language == "ru" else "ru")
	tabs = settings.get("_tabs")
	await _frames(10)
	tabs = settings.get("_tabs")
	tabs.current_tab = 1
	await _frames(10)
	await _shot("g09_settings_other_language.png")

	Settings.set_value(&"game/language", original_language)
	Settings.save_now()
	get_tree().quit()
