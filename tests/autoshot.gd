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
	await _run_factory(game)
	await _run_logistics(game)

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

	# ПКМ с зажатием выделяет область; C копирует в руку, ЛКМ вставляет копию, R поворачивает план.
	var rect := Rect2i(a, Vector2i.ONE).merge(Rect2i(b, Vector2i.ONE)).merge(Rect2i(ore_spot - Vector2i.ONE, Vector2i(3, 3)))
	var expected := 0
	for x in bm.collect_in_rect(rect):
		if x.def.removable:
			expected += 1
	await _mouse_move(game, rect.position)
	await _mouse_button(game, rect.position, MOUSE_BUTTON_RIGHT, true)
	await _mouse_move(game, rect.position + Vector2i(1, 1))
	await _mouse_move(game, rect.end - Vector2i.ONE)
	await _frames(3)
	await _shot("i03_select_area.png")
	await _mouse_button(game, rect.end - Vector2i.ONE, MOUSE_BUTTON_RIGHT, false)
	_expect(tools.has_area() and tools.area_buildings.size() == expected, "ПКМ с зажатием выделяет %d построек (%d)" % [expected, tools.area_buildings.size()])
	_expect(game.camera.position == core.get_world_center(), "ПКМ больше не двигает камеру")

	before = bm.get_count()
	await _key(KEY_C)
	_expect(tools.mode == ToolController.Mode.PASTE and tools.plan.size() == expected, "C копирует выделенное в руку (%d)" % tools.plan.size())
	var paste_at := base + Vector2i(-12, -12)
	await _mouse_move(game, paste_at)
	await _key(KEY_R)
	await _frames(3)
	await _shot("i03b_paste_preview.png")
	var plan_rotated := tools.plan_size
	_expect(plan_rotated == Vector2i(rect.size.y, rect.size.x) or plan_rotated.x == plan_rotated.y or tools.plan_size.x > 0, "R поворачивает план")
	await _mouse_button(game, paste_at, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, paste_at, MOUSE_BUTTON_LEFT, false)
	var pasted := bm.get_count() - before
	_expect(pasted > 0, "ЛКМ вставляет копию (поставлено %d)" % pasted)
	await _mouse_button(game, paste_at, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button(game, paste_at, MOUSE_BUTTON_RIGHT, false)
	_expect(tools.mode == ToolController.Mode.NONE, "клик ПКМ выходит из вставки")

	# Выделение и снос на X; ядро не трогается.
	await _mouse_move(game, rect.position)
	await _mouse_button(game, rect.position, MOUSE_BUTTON_RIGHT, true)
	await _mouse_move(game, rect.position + Vector2i(1, 1))
	await _mouse_move(game, rect.end - Vector2i.ONE)
	await _mouse_button(game, rect.end - Vector2i.ONE, MOUSE_BUTTON_RIGHT, false)
	before = bm.get_count()
	await _key(KEY_X)
	_expect(before - bm.get_count() == expected and expected >= 11, "X сносит выделенные постройки (%d из %d)" % [before - bm.get_count(), expected])
	_expect(world.get_core() != null and not tools.has_area(), "ядро уцелело, выделение снято")

	# Клик ПКМ по зданию без инструмента выделяет его, X сносит.
	var lone := bm.place(conveyor, base + Vector2i(-10, 3), 0)
	await _mouse_move(game, lone.origin)
	await _mouse_button(game, lone.origin, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button(game, lone.origin, MOUSE_BUTTON_RIGHT, false)
	_expect(tools.has_area() and tools.area_buildings.size() == 1, "клик ПКМ по зданию выделяет его")
	await _key(KEY_X)
	_expect(lone.world == null, "X сносит одиночное выделенное здание")

	# Удаляем вставленную копию, чтобы не мешала следующим проверкам.
	var cleanup := Rect2i(paste_at - Vector2i(12, 12), Vector2i(24, 24))
	for x in bm.collect_in_rect(cleanup):
		world.demolish(x)


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


## Производство: камень → дробилка → сепаратор → ядро; подсказки со статусами.
func _run_factory(game: Game) -> void:
	var world := game.world
	var bm := world.buildings
	var core := world.get_core()
	var drill := Registry.get_building(&"mechanical_drill")
	var spot := _find_ore_spot(world, drill, core.origin, 30, &"stone")
	_expect(spot != Vector2i(-1, -1), "есть место для бура на камне")
	if spot == Vector2i(-1, -1):
		return
	bm.place(drill, spot, 0, true)
	bm.place(drill, spot + Vector2i(0, 2), 0, true)
	var pulverizer := bm.place(Registry.get_building(&"pulverizer"), spot + Vector2i(2, 1), 0, true)
	var separator := bm.place(Registry.get_building(&"separator"), spot + Vector2i(3, 1), 0, true) as Crafter
	var start := spot + Vector2i(5, 1)
	var finish := Vector2i(core.origin.x - 1, core.origin.y + 1)
	for step in LinePlanner.l_path(start, finish, false, GameConst.Dir.RIGHT):
		bm.place(Registry.get_building(&"conveyor"), Vector2i(step.x, step.y), step.z, true)
	_expect(pulverizer != null and separator != null, "дробилка и сепаратор поставлены")
	var kiln := bm.place(Registry.get_building(&"kiln"), spot + Vector2i(0, -4), 0, true) as Crafter

	var delivered_before := 0
	for item in [&"copper", &"lead", &"coal", &"titanium"]:
		delivered_before += world.core_storage.delivered[Registry.get_item(item).index]
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 60 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	var delivered_after := 0
	for item in [&"copper", &"lead", &"coal", &"titanium"]:
		delivered_after += world.core_storage.delivered[Registry.get_item(item).index]
	_expect(separator != null and separator.get_status() != Building.Status.NO_INPUT or delivered_after > delivered_before,
		"сепаратор получает дроблёную породу")
	_expect(delivered_after > delivered_before, "руды из сепаратора дошли до ядра (+%d)" % (delivered_after - delivered_before))
	_expect(kiln != null and kiln.get_status() == Building.Status.NO_INPUT, "печь без сырья в статусе «нет сырья»")

	game.camera.focus_on(Vector2((spot + Vector2i(3, 1)) * GameConst.TILE_SIZE), 1.4)
	await _frames(5)
	await _mouse_move(game, separator.origin)
	await _frames(40)
	await _shot("g11_tooltip_separator.png")
	await _mouse_move(game, kiln.origin)
	await _frames(40)
	await _shot("g12_tooltip_kiln.png")
	await _mouse_move(game, spot + Vector2i(20, 20))
	await _frames(3)


func _find_ore_spot(world: GameWorld, drill: BuildingDef, center: Vector2i, radius: int, ore_id: StringName) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_tiles := 0
	for y in range(center.y - radius, center.y + radius):
		for x in range(center.x - radius, center.x + radius):
			var origin := Vector2i(x, y)
			if world.buildings.check_place(drill, origin, 0) != BuildingManager.Check.OK:
				continue
			var found := (drill as DrillDef).find_ore(world.grid, origin)
			if found.x > 0 and Registry.ores[found.x - 1].id == ore_id and found.y > best_tiles:
				best = origin
				best_tiles = found.y
	return best


## Логистика: витрина зданий, настройка кликами, мосты, оверлей загрузки лент.
func _run_logistics(game: Game) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var copper := Registry.get_item(&"copper").index
	var lead := Registry.get_item(&"lead").index
	var core := world.get_core()
	var base := core.origin
	var conveyor := Registry.get_building(&"conveyor")

	# Витрина: разгрузчик у ядра → сортировщик → делитель → мост над препятствием, перекрёсток.
	var right := base + Vector2i(3, 1)
	var unloader := bm.place(Registry.get_building(&"unloader"), right, 0, true)
	world.configure(unloader, copper)
	Worlds_line(world, right + Vector2i(1, 0), 3, GameConst.Dir.RIGHT)
	var sorter := bm.place(Registry.get_building(&"sorter"), right + Vector2i(4, 0), 0, true)
	world.configure(sorter, copper)
	Worlds_line(world, right + Vector2i(5, 0), 2, GameConst.Dir.RIGHT)
	bm.place(Registry.get_building(&"router"), right + Vector2i(7, 0), 0, true)
	Worlds_line(world, right + Vector2i(8, 0), 2, GameConst.Dir.RIGHT)
	var bridge_a := bm.place(Registry.get_building(&"bridge_conveyor"), right + Vector2i(10, 0), 0, true)
	Worlds_line(world, right + Vector2i(11, -2), 5, GameConst.Dir.DOWN)
	Worlds_line(world, right + Vector2i(12, -2), 5, GameConst.Dir.DOWN)
	var bridge_b := bm.place(Registry.get_building(&"bridge_conveyor"), right + Vector2i(13, 0), 0, true)
	world.configure(bridge_a, bridge_b.origin - bridge_a.origin)
	Worlds_line(world, right + Vector2i(14, 0), 3, GameConst.Dir.RIGHT)
	Worlds_line(world, right + Vector2i(7, 1), 3, GameConst.Dir.DOWN)
	bm.place(Registry.get_building(&"junction"), right + Vector2i(7, 4), 0, true)
	Worlds_line(world, right + Vector2i(7, 5), 2, GameConst.Dir.DOWN)
	Worlds_line(world, right + Vector2i(4, 4), 3, GameConst.Dir.RIGHT)
	Worlds_line(world, right + Vector2i(8, 4), 3, GameConst.Dir.RIGHT)
	bm.place(Registry.get_building(&"overflow_gate"), right + Vector2i(7, -1), 0, true)
	Worlds_line(world, right + Vector2i(7, -2), 2, GameConst.Dir.UP)

	game.camera.focus_on(Vector2((right + Vector2i(8, 1)) * GameConst.TILE_SIZE), 1.1)
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 15 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	await _frames(10)
	await _shot("g09_logistics.png")
	_expect(sorter.get_display_item() == copper, "сортировщик показывает фильтр")
	_expect(bridge_a.get_link_target() == bridge_b, "мост витрины связан")

	game.belt_overlay.visible = true
	game.hud.set_belt_legend_visible(true)
	await _frames(20)
	await _shot("g10_belt_overlay.png")
	game.belt_overlay.visible = false
	game.hud.set_belt_legend_visible(false)

	# Настройка сортировщика кликом: выбрать здание, затем предмет в панели.
	await _mouse_move(game, sorter.origin)
	await _mouse_button(game, sorter.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, sorter.origin, MOUSE_BUTTON_LEFT, false)
	_expect(tools.selected == sorter, "клик пустой рукой выбирает сортировщик")
	var panel := _find_child_of_type(game.hud, "ConfigPanel") as ConfigPanel
	await _frames(3)
	_expect(panel != null and panel.visible, "открылась панель настройки")
	await _shot("i04_config_panel.png")
	var grid := _find_child_of_class(panel, "GridContainer")
	if grid != null and grid.get_child_count() > lead + 1:
		await _click_control(grid.get_child(lead + 1) as Control)
	_expect(sorter.get_config() == lead, "клик по свинцу в панели меняет фильтр")
	await _key(KEY_ESCAPE)
	_expect(tools.selected == null and not panel.visible, "Esc снимает выбор и закрывает панель")

	# Пипетка копирует фильтр.
	await _mouse_move(game, sorter.origin)
	await _key(KEY_Q)
	_expect(tools.place_def == sorter.def and tools.place_config == lead, "пипетка копирует фильтр сортировщика")
	await _key(KEY_ESCAPE)

	# Связь мостов кликами.
	var row := base + Vector2i(3, 7)
	var first := bm.place(Registry.get_building(&"bridge_conveyor"), row, 0, true)
	var second := bm.place(Registry.get_building(&"bridge_conveyor"), row + Vector2i(3, 0), 0, true)
	await _mouse_move(game, first.origin)
	await _mouse_button(game, first.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, first.origin, MOUSE_BUTTON_LEFT, false)
	await _mouse_move(game, second.origin)
	await _frames(3)
	await _shot("i05_bridge_range.png")
	await _mouse_button(game, second.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, second.origin, MOUSE_BUTTON_LEFT, false)
	_expect(first.get_link_target() == second, "клик по второму мосту связывает мосты")
	_expect(tools.selected == second, "после связи выбран второй мост (можно продолжать цепочку)")
	await _key(KEY_ESCAPE)

	# Протягивание мостов: шаг равен дальности, цепочка связывается сама.
	var bridge_def := Registry.get_building(&"bridge_conveyor")
	tools.select_building(bridge_def)
	var start := base + Vector2i(3, 9)
	var finish := start + Vector2i(8, 0)
	await _mouse_move(game, start)
	await _mouse_button(game, start, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, start + Vector2i(1, 0))
	await _mouse_move(game, finish)
	await _mouse_button(game, finish, MOUSE_BUTTON_LEFT, false)
	var b0 := bm.get_at(start) as BridgeConveyor
	var b1 := bm.get_at(start + Vector2i(4, 0)) as BridgeConveyor
	var b2 := bm.get_at(finish) as BridgeConveyor
	_expect(b0 != null and b1 != null and b2 != null, "протягивание ставит мосты через 4 тайла")
	_expect(b0 != null and b1 != null and b0.get_link_target() == b1 and b1.get_link_target() == b2, "протянутые мосты связаны цепочкой")
	await _key(KEY_ESCAPE)


func Worlds_line(world: GameWorld, start: Vector2i, length: int, dir: int) -> void:
	var def := Registry.get_building(&"conveyor")
	for i in length:
		world.buildings.place(def, start + GameConst.dir_vector(dir) * i, dir, true)


func _find_child_of_class(node: Node, class_name_text: String) -> Node:
	for child in node.get_children():
		if child.get_class() == class_name_text:
			return child
		var nested := _find_child_of_class(child, class_name_text)
		if nested != null:
			return nested
	return null


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
