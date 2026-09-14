extends Node
## Отладочный прогон со скриншотами и проверкой инструментов настоящими событиями ввода.
## Добавляется главным меню или игровой сценой только при флаге командной строки:
##   godot --path D:/Mind res://core/game.tscn -- --autoshot --autoshot-dir=C:/путь/к/папке
## Мышь не двигает; изменённые настройки в конце восстанавливает.
## Сцены разворачиваются южнее площадки центрального шлюза (место посадки); перед действиями дрон
## переносится к нужному месту, чтобы всё было в его радиусе.

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
	# Площадка шлюза занимает ±7 тайлов от места посадки — сцены строим южнее неё.
	var base := game.world.drone.get_tile() + Vector2i(0, 11)
	await _frames(30)
	await _measure_frames("старт")
	await _shot("g01_start.png")

	await _run_gateway(game)
	await _run_drone(game, base)
	await _run_interaction(game, base)
	await _run_production_chain(game, base)
	await _run_factory(game, base)
	await _run_logistics(game, base)

	await _drone_to(game, base)
	game.ore_overlay.visible = true
	game.hud.set_ore_legend_visible(true)
	game.camera.focus_on(game.world.drone.position, 0.6)
	await _frames(10)
	await _shot("g04_ore_overlay.png")
	game.ore_overlay.visible = false
	game.hud.set_ore_legend_visible(false)

	game.hud.toggle_debug()
	game.grid_overlay.set_chunk_lines_visible(true)
	game.camera.focus_on(game.world.drone.position, 0.8)
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


## База и планета: переход через шлюз по F, стройка в базе, предметы через шлюз в обе стороны.
func _run_gateway(game: Game) -> void:
	var run := game.run
	var gate := run.get_gateway(run.planet)
	var pair := run.get_gateway(run.base)
	var copper := Registry.get_item(&"copper").index
	var lead := Registry.get_item(&"lead").index
	var conveyor := Registry.get_building(&"conveyor")

	# Планета: склад с медью → разгрузчик → лента в западный порт шлюза.
	var in_port := gate.get_input_tile()
	var planet_storage := run.planet.buildings.place(Registry.get_building(&"container"), in_port + Vector2i(-4, 0), 0, true) as StorageBuilding
	planet_storage.inventory.add(copper, 300)
	run.planet.buildings.place(Registry.get_building(&"unloader"), in_port + Vector2i(-2, 0), 0, true)
	Worlds_line(run.planet, in_port + Vector2i(-1, 0), 2, GameConst.Dir.RIGHT)
	var planet_out := run.planet.buildings.place(Registry.get_building(&"container"), gate.get_output_tile() + Vector2i(2, 0), 0, true) as StorageBuilding
	Worlds_line(run.planet, gate.get_output_tile(), 2, GameConst.Dir.RIGHT)

	await _drone_to(game, gate.origin + Vector2i.ONE)
	game.camera.focus_on(run.drone.position, 1.0)
	await _frames(5)
	var hud_gateway: Label = game.hud.get("_gateway_label")
	_expect(run.can_use_gateway() and hud_gateway.visible, "над шлюзом видна подсказка перехода")
	await _shot("w01_gateway_prompt.png")
	await _key(KEY_F)
	await _frames(5)
	_expect(game.world == run.base and run.drone.world == run.base and game.is_in_base(), "F над шлюзом — дрон и вид в базе")
	_expect(game.camera.position.distance_to(run.drone.position) < 2.0, "камера перенеслась к дрону в базе")

	# Стройка в базе настоящим вводом.
	var base_tile := pair.origin + Vector2i(1, -3)
	game.tools.select_building(conveyor)
	await _mouse_move(game, base_tile)
	await _mouse_button(game, base_tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, base_tile, MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	_expect(run.base.buildings.get_at(base_tile) != null and run.planet.buildings.get_at(base_tile) == null, "клик строит в базе, а не на планете")

	# База: из западного порта пары — в склад; склад со свинцом → разгрузчик → восточный порт пары.
	var out_port := pair.get_output_tile()
	Worlds_line(run.base, out_port, 2, GameConst.Dir.LEFT)
	var base_in := run.base.buildings.place(Registry.get_building(&"container"), out_port + Vector2i(-3, 0), 0, true) as StorageBuilding
	var back_in := pair.get_input_tile()
	Worlds_line(run.base, back_in, 1, GameConst.Dir.LEFT)
	run.base.buildings.place(Registry.get_building(&"unloader"), back_in + Vector2i(1, 0), 0, true)
	var base_out := run.base.buildings.place(Registry.get_building(&"container"), back_in + Vector2i(2, 0), 0, true) as StorageBuilding
	base_out.inventory.add(lead, 300)
	game.clock.set_speed_index(2)
	await _wait_ticks(run.base, 15 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	await _frames(10)
	await _shot("w02_base.png")
	_expect(base_in.inventory.count(copper) > 0, "медь с планеты пришла в базу через шлюз (%d)" % base_in.inventory.count(copper))

	# Обратно на планету: свинец из базы вышел из восточного порта шлюза.
	await _drone_to(game, pair.origin + Vector2i.ONE)
	await _key(KEY_F)
	await _frames(5)
	_expect(game.world == run.planet and not game.is_in_base(), "F над парой — обратно на планету")
	await _frames(10)
	await _shot("w03_planet_gateway.png")
	_expect(planet_out.inventory.count(lead) > 0, "свинец из базы вышел на планету (%d)" % planet_out.inventory.count(lead))
	_expect(run.base.simulation.tick == run.planet.simulation.tick, "база тикает, пока дрон на планете")


## Дрон: полёт, камера, добыча руды, окно инвентаря и ручной крафт.
func _run_drone(game: Game, base: Vector2i) -> void:
	var world := game.world
	var drone := world.drone
	var inv := drone.inventory

	# Полёт на D и слежение камеры.
	var start := drone.position
	await _key_hold(KEY_D, true)
	await _frames(20)
	await _key_hold(KEY_D, false)
	_expect(drone.position.x > start.x + 16.0, "D двигает дрона вправо (%.0f px)" % (drone.position.x - start.x))
	await _frames(20)
	_expect(game.camera.position.distance_to(drone.get_draw_position(game.clock.alpha)) < 2.0, "камера следует за дроном")
	await _shot("d00_drone.png")

	# Добыча: ЛКМ по руде с зажатием.
	var ore_tile := _find_ore_tile(world, &"copper", base, 30)
	_expect(ore_tile != Vector2i(-1, -1), "рядом есть медная руда")
	if ore_tile == Vector2i(-1, -1):
		return
	await _drone_to(game, ore_tile + Vector2i(-3, 1))
	var copper := Registry.get_item(&"copper").index
	var copper_before := inv.count(copper)
	await _mouse_move(game, ore_tile)
	await _mouse_button(game, ore_tile, MOUSE_BUTTON_LEFT, true)
	_expect(drone.is_mining() and drone.mine_tile == ore_tile, "ЛКМ по руде включает добычу")
	game.clock.set_speed_index(2)
	await _wait_ticks(world, drone.def.mine_ticks(Registry.get_ore(&"copper")) * 2 + 4)
	game.clock.set_speed_index(0)
	await _frames(3)
	await _shot("d01_mining.png")
	await _mouse_button(game, ore_tile, MOUSE_BUTTON_LEFT, false)
	_expect(inv.count(copper) >= copper_before + 2, "дрон добыл медь (+%d)" % (inv.count(copper) - copper_before))
	_expect(not drone.is_mining(), "отпускание кнопки останавливает добычу")

	# Окно инвентаря (E) и крафт кликом по рецепту.
	await _drone_to(game, base)
	await _key(KEY_E)
	var window := game.hud.inventory_window
	_expect(window.visible and window.mode == InventoryWindow.Mode.CRAFT, "E открывает инвентарь и крафт")
	await _frames(5)
	await _shot("d02_inventory.png")
	var belt := Registry.get_building(&"conveyor").item.index
	var belt_recipe := Registry.get_hand_recipe(belt)
	var belts_before := inv.count(belt)
	var recipe_slots: Dictionary = window.get("_recipe_slots")
	var belt_slot := recipe_slots.get(belt) as ItemSlot
	_expect(belt_slot != null, "в крафте есть рецепт ленты")
	if belt_slot == null:
		return
	await _click_control(belt_slot)
	await _wait_ticks(world, belt_recipe.ticks + 3)
	_expect(inv.count(belt) == belts_before + 1, "клик по рецепту крафтит ленту (+%d)" % (inv.count(belt) - belts_before))
	var center := belt_slot.get_global_rect().get_center()
	await _mouse_button_screen(center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(center, MOUSE_BUTTON_RIGHT, false)
	_expect(drone.crafting.units.size() >= 4, "ПКМ по рецепту ставит 5 крафтов (в очереди %d)" % drone.crafting.units.size())
	await _frames(3)
	await _shot("d03_craft_queue.png")
	# Отмена работает как крафт: ещё 5 в очередь, ПКМ по группе в очереди — минус 5.
	await _mouse_button_screen(center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(center, MOUSE_BUTTON_RIGHT, false)
	var queued := drone.crafting.units.size()
	await _frames(3)
	var queue_panel := _find_child_of_type(game.hud, "CraftQueuePanel")
	var queue_row: HBoxContainer = queue_panel.get("_row") if queue_panel != null else null
	if queue_row != null and queue_row.get_child_count() > 0:
		var group_center := (queue_row.get_child(0) as Control).get_global_rect().get_center()
		await _mouse_move_screen(group_center)
		await _mouse_button_screen(group_center, MOUSE_BUTTON_RIGHT, true)
		await _mouse_button_screen(group_center, MOUSE_BUTTON_RIGHT, false)
	_expect(drone.crafting.units.size() <= queued - 4, "ПКМ по группе в очереди отменяет 5 (%d → %d)" % [queued, drone.crafting.units.size()])
	await _key(KEY_ESCAPE)
	_expect(not window.visible, "Esc закрывает инвентарь")
	# ПКМ по кнопке постройки в меню строительства — крафт одной.
	var menu := _find_child_of_type(game.hud, "BuildMenu") as BuildMenu
	var belt_button: Button = (menu.get("_building_buttons") as Dictionary)[&"conveyor"]
	var button_center := belt_button.get_global_rect().get_center()
	var units_before := drone.crafting.units.size()
	await _mouse_move_screen(button_center)
	await _mouse_button_screen(button_center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(button_center, MOUSE_BUTTON_RIGHT, false)
	_expect(drone.crafting.units.size() >= units_before, "ПКМ по кнопке постройки ставит крафт")
	await _wait_ticks(world, belt_recipe.ticks * 8 + 4)
	_expect(drone.crafting.is_empty() and inv.count(belt) == belts_before + 7, "очередь докрафтила ленты (+%d)" % (inv.count(belt) - belts_before))


## Инструменты через настоящие события ввода.
func _run_interaction(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var inv := world.drone.inventory
	var conveyor := Registry.get_building(&"conveyor")
	await _drone_to(game, base)

	# Протягивание L-линии лент: 7 тайлов вправо и 3 вниз = 10 лент из инвентаря.
	var belts_before := inv.count(conveyor.item.index)
	var before := bm.get_count()
	tools.select_building(conveyor)
	var a := base + Vector2i(-6, 3)
	var b := base + Vector2i(0, 6)
	await _mouse_move(game, a)
	await _mouse_button(game, a, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, a + Vector2i(1, 0))
	await _mouse_move(game, b)
	await _frames(3)
	await _shot("i01_drag_line.png")
	await _mouse_button(game, b, MOUSE_BUTTON_LEFT, false)
	_expect(bm.get_count() - before == 10, "протягивание L-линии ставит 10 лент (поставлено %d)" % (bm.get_count() - before))
	_expect(belts_before - inv.count(conveyor.item.index) == 10, "линия взяла 10 лент из инвентаря")
	var corner := bm.get_at(Vector2i(b.x, a.y))
	_expect(corner != null and corner.rotation == GameConst.Dir.DOWN, "угол линии повёрнут вниз")

	# Вне радиуса дрона превью показывает причину.
	var far := base + Vector2i(14, -2)
	await _mouse_move(game, far)
	_expect(tools.plan_problem == BuildingManager.Check.OUT_OF_RANGE, "превью за радиусом дрона показывает причину")
	await _shot("i01b_out_of_range.png")

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
	var no_ore := _find_empty_spot(world, drill, base, 9)
	await _mouse_move(game, no_ore)
	_expect(tools.plan_problem == BuildingManager.Check.NO_ORE, "превью бура без руды показывает причину")
	var ore_spot := _find_drill_spot(world, drill, base, 20)
	_expect(ore_spot != Vector2i(-1, -1), "рядом с местом посадки есть место для бура на руде")
	await _drone_to(game, ore_spot + Vector2i(1, 3))
	before = bm.get_count()
	var drills_before := inv.count(drill.item.index)
	await _mouse_move(game, ore_spot)
	await _mouse_button(game, ore_spot, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, ore_spot, MOUSE_BUTTON_LEFT, false)
	_expect(bm.get_count() - before == 1 and drills_before - inv.count(drill.item.index) == 1, "клик ставит бур на руду из инвентаря")
	await _drone_to(game, base)

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
	var rect := Rect2i(a, Vector2i.ONE).merge(Rect2i(b, Vector2i.ONE))
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

	before = bm.get_count()
	await _key(KEY_C)
	_expect(tools.mode == ToolController.Mode.PASTE and tools.plan.size() == expected, "C копирует выделенное в руку (%d)" % tools.plan.size())
	var paste_at := base + Vector2i(-4, -5)
	await _mouse_move(game, paste_at)
	await _key(KEY_R)
	await _frames(3)
	await _shot("i03b_paste_preview.png")
	await _mouse_button(game, paste_at, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, paste_at, MOUSE_BUTTON_LEFT, false)
	var pasted := bm.get_count() - before
	_expect(pasted == expected, "ЛКМ вставляет копию из инвентаря (поставлено %d из %d)" % [pasted, expected])
	await _mouse_button(game, paste_at, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button(game, paste_at, MOUSE_BUTTON_RIGHT, false)
	_expect(tools.mode == ToolController.Mode.NONE, "клик ПКМ выходит из вставки")

	# Выделение и снос на X: постройки возвращаются в инвентарь.
	await _mouse_move(game, rect.position)
	await _mouse_button(game, rect.position, MOUSE_BUTTON_RIGHT, true)
	await _mouse_move(game, rect.position + Vector2i(1, 1))
	await _mouse_move(game, rect.end - Vector2i.ONE)
	await _mouse_button(game, rect.end - Vector2i.ONE, MOUSE_BUTTON_RIGHT, false)
	before = bm.get_count()
	var belts_before_delete := inv.count(conveyor.item.index)
	await _key(KEY_X)
	_expect(before - bm.get_count() == expected and expected >= 10, "X сносит выделенные постройки (%d из %d)" % [before - bm.get_count(), expected])
	_expect(inv.count(conveyor.item.index) - belts_before_delete == expected, "снесённые ленты вернулись в инвентарь")
	_expect(not tools.has_area(), "выделение снято")

	# Клик ПКМ по зданию без инструмента выделяет его, X сносит.
	var lone := bm.place(conveyor, base + Vector2i(3, 3), 0)
	await _mouse_move(game, lone.origin)
	await _mouse_button(game, lone.origin, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button(game, lone.origin, MOUSE_BUTTON_RIGHT, false)
	_expect(tools.has_area() and tools.area_buildings.size() == 1, "клик ПКМ по зданию выделяет его")
	await _key(KEY_X)
	_expect(lone.world == null, "X сносит одиночное выделенное здание")

	# Без выделения X сносит здание под курсором (и в руке с инструментом тоже).
	var hovered := bm.place(conveyor, base + Vector2i(3, 5), 0)
	await _mouse_move(game, hovered.origin)
	_expect(not tools.has_area() and tools.hover_building == hovered, "курсор над лентой, выделения нет")
	await _key(KEY_X)
	_expect(hovered.world == null, "X без выделения сносит здание под курсором")
	var hovered_in_hand := bm.place(conveyor, base + Vector2i(3, 7), 0)
	tools.select_building(conveyor)
	await _mouse_move(game, hovered_in_hand.origin)
	await _key(KEY_X)
	_expect(hovered_in_hand.world == null, "X сносит здание под курсором и с постройкой в руке")
	await _key(KEY_ESCAPE)

	# Удаляем вставленную копию, чтобы не мешала следующим проверкам.
	var cleanup := Rect2i(paste_at - Vector2i(8, 8), Vector2i(16, 16))
	for x in bm.collect_in_rect(cleanup):
		bm.remove(x, true)


## Цепочка «бур → лента → контейнер»: предметы едут и складываются.
func _run_production_chain(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var drill := Registry.get_building(&"mechanical_drill")
	var conveyor := Registry.get_building(&"conveyor")
	var copper := Registry.get_item(&"copper").index

	# Контейнер северо-западнее места посадки, буры на ближайшей меди, лента от буров к контейнеру.
	var container := bm.place(Registry.get_building(&"container"), base + Vector2i(-3, -3), 0, true) as StorageBuilding
	var spot := _find_drill_spot(world, drill, base, 20)
	var placed_drills := 0
	for dx in [0, 2, 4]:
		for dy in [0, -2]:
			if bm.place(drill, spot + Vector2i(dx, dy), 0) != null:
				placed_drills += 1
	var target := container.origin + Vector2i(0, -1)
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
	var stored := container.inventory.count(copper)
	_expect(stored > 0, "медь дошла до контейнера (%d)" % stored)
	await _measure_frames("работающая цепочка")

	# Окно контейнера: клик открывает содержимое, ЛКМ по ячейке забирает стопку в инвентарь.
	await _drone_to(game, container.origin + Vector2i(2, 2))
	await _mouse_move(game, container.origin)
	await _mouse_button(game, container.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, container.origin, MOUSE_BUTTON_LEFT, false)
	var window := game.hud.inventory_window
	_expect(game.tools.selected == container and window.visible and window.mode == InventoryWindow.Mode.BUILDING, "клик по контейнеру открывает его окно")
	await _frames(12)
	await _shot("g02c_container_window.png")
	var slots: Array = window.get("_building_slots")
	var inv := world.drone.inventory
	var copper_before := inv.count(copper)
	var in_container := container.inventory.count(copper)
	if not slots.is_empty():
		await _click_control(slots[0] as Control)
	_expect(inv.count(copper) > copper_before and container.inventory.count(copper) < in_container, "ЛКМ по ячейке контейнера забирает медь")
	await _key(KEY_ESCAPE)
	_expect(not window.visible and game.tools.selected == null, "Esc закрывает окно контейнера")

	# Все типы предметов на лентах (проверка ориентации иконок в MultiMesh), включая постройки.
	var row_origin := base + Vector2i(-8, 8)
	var sys := world.simulation.conveyors
	var per_row := 16
	for i in Registry.items.size():
		var tile := row_origin + Vector2i(i % per_row, i / per_row)
		var belt := bm.place(conveyor, tile, GameConst.Dir.RIGHT, true)
		if belt != null:
			sys.call("_insert", sys.index_of(belt.id), Registry.items[i].index, ConveyorSystem.UNITS / 2, 0.0, 0)
	game.clock.toggle_pause()
	game.camera.focus_on(Vector2(row_origin * GameConst.TILE_SIZE) + Vector2(per_row * 16, 32), 2.5)
	await _frames(15)
	await _shot("g02b_item_types.png")
	game.clock.toggle_pause()
	for i in Registry.items.size():
		var tile := row_origin + Vector2i(i % per_row, i / per_row)
		if bm.get_at(tile) != null:
			bm.remove(bm.get_at(tile), true)
	game.camera.focus_on(Vector2(spot * GameConst.TILE_SIZE) + Vector2(160, 48), 1.3)

	# Поворот ленты посреди работающей линии: поток прерывается, обратный поворот его восстанавливает.
	var middle := bm.get_at(line_start + Vector2i(3, 0))
	bm.rotate(middle, middle.rotation + 1)
	await _frames(30)
	await _shot("g03_rotated_belt.png")
	bm.rotate(middle, middle.rotation + 3)
	var stored_after_fix := container.inventory.count(copper)
	await _wait_ticks(world, 20 * GameConst.TICK_RATE)
	_expect(container.inventory.count(copper) > stored_after_fix, "после обратного поворота поток восстановился")
	await _drone_to(game, base)


## Производство: камень → дробилка → сепаратор → контейнер; подсказки со статусами.
func _run_factory(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var drill := Registry.get_building(&"mechanical_drill")
	var spot := _find_ore_spot(world, drill, base, 30, &"stone")
	_expect(spot != Vector2i(-1, -1), "есть место для бура на камне")
	if spot == Vector2i(-1, -1):
		return
	bm.place(drill, spot, 0, true)
	bm.place(drill, spot + Vector2i(0, 2), 0, true)
	var pulverizer := bm.place(Registry.get_building(&"pulverizer"), spot + Vector2i(2, 1), 0, true)
	var separator := bm.place(Registry.get_building(&"separator"), spot + Vector2i(3, 1), 0, true) as Crafter
	for x in range(5, 8):
		bm.place(Registry.get_building(&"conveyor"), spot + Vector2i(x, 1), GameConst.Dir.RIGHT, true)
	var output := bm.place(Registry.get_building(&"container"), spot + Vector2i(8, 1), 0, true) as StorageBuilding
	_expect(pulverizer != null and separator != null and output != null, "дробилка, сепаратор и контейнер поставлены")
	if pulverizer == null or separator == null or output == null:
		return
	var kiln := bm.place(Registry.get_building(&"kiln"), spot + Vector2i(0, -4), 0, true) as Crafter

	var ores := [&"copper", &"lead", &"coal", &"titanium"]
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 60 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	var collected := 0
	for item in ores:
		collected += output.inventory.count(Registry.get_item(item).index)
	_expect(collected > 0, "руды из сепаратора дошли до контейнера (%d)" % collected)
	_expect(kiln != null and kiln.get_status() == Building.Status.NO_INPUT, "печь без сырья в статусе «нет сырья»")

	await _drone_to(game, spot + Vector2i(3, 4))
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
	await _drone_to(game, base)


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
func _run_logistics(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var copper := Registry.get_item(&"copper").index
	var lead := Registry.get_item(&"lead").index
	await _drone_to(game, base)

	# Витрина: разгрузчик у склада → сортировщик → делитель → мост над препятствием, перекрёсток.
	var storage := bm.place(Registry.get_building(&"vault"), base + Vector2i(0, -1), 0, true) as StorageBuilding
	storage.inventory.add(copper, 2000)
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
	var inverted_gate := bm.place(Registry.get_building(&"overflow_gate"), right + Vector2i(1, 6), 0, true)
	world.configure(inverted_gate, true)
	await _frames(10)
	await _shot("g09_logistics.png")
	_expect(sorter.get_display_item() == copper, "сортировщик показывает фильтр")
	_expect(bridge_a.get_link_target() == bridge_b, "мост витрины связан")
	_expect(storage.inventory.count(copper) < 2000, "разгрузчик достаёт медь из хранилища")

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
	_expect(panel != null and panel.visible and not game.hud.inventory_window.visible, "открылась панель настройки (без окна инвентаря)")
	await _shot("i04_config_panel.png")
	var grid := _find_child_of_class(panel, "GridContainer")
	if grid != null and grid.get_child_count() > lead + 1:
		await _click_control(grid.get_child(lead + 1) as Control)
	_expect(sorter.get_display_item() == lead, "клик по свинцу в панели меняет фильтр")
	var toggle := _find_child_of_class(panel, "CheckButton") as CheckButton
	_expect(toggle != null, "у сортировщика есть переключатель инверсии")
	if toggle != null:
		await _click_control(toggle)
		await _frames(3)
		_expect(sorter.is_inverted(), "клик по переключателю включает инверсию")
		await _shot("i04b_sorter_inverted.png")
		toggle = _find_child_of_class(panel, "CheckButton") as CheckButton
		await _click_control(toggle)
		await _frames(3)
		_expect(not sorter.is_inverted() and sorter.get_display_item() == lead, "повторный клик выключает инверсию, фильтр остаётся")
	await _key(KEY_ESCAPE)
	_expect(tools.selected == null and not panel.visible, "Esc снимает выбор и закрывает панель")

	# Пипетка копирует фильтр.
	await _mouse_move(game, sorter.origin)
	await _key(KEY_Q)
	var copied: Variant = tools.place_config
	_expect(tools.place_def == sorter.def and copied is Dictionary and (copied as Dictionary).get("item") == lead, "пипетка копирует фильтр сортировщика")
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
	world.drone.inventory.add(bridge_def.item.index, 10)
	tools.select_building(bridge_def)
	var start := base + Vector2i(-2, 8)
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


## Переносит дрона в центр тайла и возвращает к нему камеру.
func _drone_to(game: Game, tile: Vector2i) -> void:
	var drone := game.world.drone
	drone.position = Vector2(tile * GameConst.TILE_SIZE) + Vector2.ONE * GameConst.TILE_SIZE * 0.5
	drone.prev_position = drone.position
	game.camera.recenter()
	await _frames(3)


## Ближайший к center свободный тайл руды ore_id, который дрон может добывать.
func _find_ore_tile(world: GameWorld, ore_id: StringName, center: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(center.y - radius, center.y + radius):
		for x in range(center.x - radius, center.x + radius):
			var tile := Vector2i(x, y)
			var ore := world.drone.get_mineable_ore(tile)
			if ore == null or ore.id != ore_id:
				continue
			var distance := Vector2(tile - center).length()
			if distance < best_distance:
				best = tile
				best_distance = distance
	return best


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
