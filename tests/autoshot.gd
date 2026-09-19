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
	menu.call("_show_new_run")
	await _frames(10)
	await _shot("m02_levels.png")
	menu.call("_show_settings")
	await _frames(10)
	await _shot("m03_settings.png")
	menu.call("_show_saves")
	await _frames(10)
	await _shot("m04_saves.png")
	get_tree().quit()


# --- Игра ---

func _run_game(game: Game) -> void:
	var original_language: Variant = Settings.get_value(&"game/language")
	# Площадка шлюза занимает ±7 тайлов от места посадки — сцены строим южнее неё.
	var base := game.world.drone.get_tile() + Vector2i(0, 11)
	await _frames(30)
	await _measure_frames("старт")
	await _shot("g01_start.png")

	_hold_threat(game)
	await _run_research(game)
	await _run_gateway(game)
	await _run_lift(game)
	await _run_drone(game, base)
	await _run_interaction(game, base)
	await _run_build_helpers(game, base)
	await _run_coal_drill(game, base)
	await _run_production_chain(game, base)
	await _run_factory(game, base)
	await _run_power(game, base)
	await _run_logistics(game, base)
	await _run_enemies(game, base)
	await _run_defense(game)

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

	await _run_teleport(game)
	_hold_threat(game)
	await _run_pad_expansion(game)
	await _run_saves(game)
	await _run_breach(game)

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


## Исследования: закрытый бур в меню, окно исследований (J), выбор кликом, ручная сдача наборов.
## Остальные сценарии идут со всеми завершёнными исследованиями.
func _run_research(game: Game) -> void:
	var run := game.run
	var state := run.research
	var drill_def := Registry.get_building(&"drill")
	var kit := Registry.get_item(&"science_kit").index
	var menu := _find_child_of_type(game.hud, "BuildMenu") as BuildMenu
	var production_tab: Button = (menu.get("_category_buttons") as Array)[BuildingDef.Category.PRODUCTION]
	await _click_control(production_tab)
	await _frames(40)
	var drill_button: Button = (menu.get("_building_buttons") as Dictionary)[&"drill"]
	_expect(not state.is_building_unlocked(drill_def) and drill_button.modulate.r < 0.9, "бур закрыт исследованием — кнопка затемнена")
	var units := run.drone.crafting.units.size()
	var center := drill_button.get_global_rect().get_center()
	await _mouse_move_screen(center)
	await _frames(40)
	await _shot("r00_locked_menu.png")
	await _mouse_button_screen(center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(center, MOUSE_BUTTON_RIGHT, false)
	_expect(run.drone.crafting.units.size() == units, "закрытую постройку не скрафтить")
	await _mouse_move_screen(Vector2(40, 300))

	await _key(KEY_J)
	var window := game.hud.research_window
	await _frames(5)
	_expect(window.visible, "J открывает окно исследований")
	var cards: Dictionary = window.get("_cards")
	var electricity_button: Button = (cards[&"electricity"] as Dictionary)["button"]
	var mining_button: Button = (cards[&"mining"] as Dictionary)["button"]
	await _click_control(mining_button)
	_expect(state.active == &"", "недоступное исследование не выбирается")
	await _click_control(electricity_button)
	_expect(state.active == &"electricity", "клик по карточке выбирает «Электрику»")
	# ПКМ ставит следующие исследования в очередь.
	var mining_center := mining_button.get_global_rect().get_center()
	await _mouse_button_screen(mining_center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(mining_center, MOUSE_BUTTON_RIGHT, false)
	await _frames(5)
	_expect(state.queue == [&"mining"], "ПКМ по карточке ставит «Электробур» в очередь")
	var defense_center: Vector2 = ((cards[&"defense"] as Dictionary)["button"] as Button).get_global_rect().get_center()
	await _mouse_button_screen(defense_center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(defense_center, MOUSE_BUTTON_RIGHT, false)
	await _frames(5)
	_expect(state.queue == [&"mining", &"defense"], "в очереди два исследования")
	await _mouse_button_screen(defense_center, MOUSE_BUTTON_RIGHT, true)
	await _mouse_button_screen(defense_center, MOUSE_BUTTON_RIGHT, false)
	await _frames(5)
	_expect(state.queue == [&"mining"], "повторный ПКМ убирает из очереди")
	run.drone.inventory.add(kit, 12)
	# Окно обновляется по таймеру (0.25 с), а кадры короче — обновляем сразу, чтобы не ловить гонку.
	window.refresh()
	await _frames(5)
	var deposit: Button = window.get("_deposit_button")
	await _click_control(deposit)
	_expect(state.manual_queue == 10 and run.drone.inventory.count(kit) == 2,
		"кнопка сдаёт нужные наборы в ручную очередь (сдано %d, наборов у дрона %d, выбрано «%s», кнопка %s)"
			% [state.manual_queue, run.drone.inventory.count(kit), state.active, "выключена" if deposit.disabled else "включена"])
	game.clock.set_speed_index(2)
	await _wait_ticks(run.planet, roundi(ResearchState.MANUAL_SECONDS * GameConst.TICK_RATE) * 2 + 5)
	game.clock.set_speed_index(0)
	await _frames(20)
	_expect(state.get_progress(Registry.get_research(&"electricity")) == 2, "ручная очередь: 2 набора за %d с" % roundi(ResearchState.MANUAL_SECONDS * 2))
	await _shot("r01_research_window.png")
	# Колесо над деревом приближает его.
	var tree_center := window.get_global_rect().get_center()
	await _mouse_move_screen(tree_center)
	var zoom_before: float = window.get_tree_zoom()
	await _wheel_screen(tree_center, true)
	await _frames(5)
	_expect(window.get_tree_zoom() > zoom_before, "колесо приближает дерево исследований (%.2f)" % window.get_tree_zoom())
	await _shot("r01b_research_zoom.png")
	await _wheel_screen(tree_center, false)
	await _frames(5)
	_expect(is_equal_approx(window.get_tree_zoom(), zoom_before), "колесо назад возвращает масштаб")
	await _key(KEY_ESCAPE)
	_expect(not window.visible and not game.pause_menu.is_open(), "Esc закрывает окно исследований")

	# Шлюз под дроном: без «Подземного этажа» — подсказка об исследовании, F не переносит.
	run.drone.position = run.get_gateway(run.planet).get_world_center()
	await _frames(5)
	var gateway_label: Label = game.hud.get("_gateway_label")
	_expect(gateway_label.visible and gateway_label.text.contains(tr(Registry.get_research(&"underground").name_key)),
		"над шлюзом подсказка: нужен «Подземный этаж»")
	await _key(KEY_F)
	_expect(game.world == run.planet, "без исследования F не переносит на этаж")

	# Дальше — всё открыто, кроме расширений площадки (их смотрим после телепорта).
	for research in Registry.researches:
		if not research.effects.has(&"pad_size"):
			state.done[research.id] = true
	state.progress.clear()
	state.manual_queue = 0
	state.active = &""
	state.changed.emit()
	run.apply_research_effects()
	# Меню обновляет кнопки раз в 0.2 с.
	await _frames(40)
	_expect(drill_button.modulate.r > 0.9 and state.is_building_unlocked(drill_def), "после исследования электробур открыт в меню")
	# «Порты шлюза II» открыты — шлюз вырос до 4×4, центр остался на месте.
	var grown := run.get_gateway(run.planet)
	_expect(grown.get_size() == 4 and run.planet.buildings.get_at(grown.origin + Vector2i(3, 3)) == grown,
		"после «Портов шлюза II» шлюз занимает 4×4")
	_expect(run.planet.pad_rect.position + run.planet.pad_rect.size / 2 == grown.origin + Vector2i(2, 2),
		"площадка осталась симметричной вокруг центра шлюза")
	_expect(run.drone.get_speed() > run.drone.def.speed and run.drone.get_max_health() > run.drone.def.health,
		"ветка дрона поднимает скорость (%.1f) и прочность (%.0f)" % [run.drone.get_speed(), run.drone.get_max_health()])
	run.drone.inventory.remove(kit, 2)


## Угольный бур: ставится в один тайл на угле, сам берёт себе топливо и отдаёт остальное на ленту.
func _run_coal_drill(game: Game, base: Vector2i) -> void:
	var world := game.world
	var def := Registry.get_building(&"coal_drill") as DrillDef
	var tile := _find_any_ore_tile(world, &"coal", base, 26)
	_expect(tile.x >= 0, "рядом есть угольная порода")
	if tile.x < 0:
		return
	await _drone_to(game, tile + Vector2i(0, 3))
	world.drone.inventory.add(def.item.index, 1)
	game.tools.select_building(def)
	await _mouse_move(game, tile)
	await _mouse_button(game, tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, tile, MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	var drill := world.buildings.get_at(tile) as Drill
	_expect(drill != null and drill.def.size == 1, "угольный бур занял один тайл")
	if drill == null:
		return
	_expect(drill.get_status() == Building.Status.NO_FUEL, "пока нет топлива — бур стоит")
	drill.handle_item(null, Registry.get_item(&"coal").index)
	game.clock.set_speed_index(2)
	await _wait_ticks(world, roundi(def.seconds_per_item(drill.ore, 1) * GameConst.TICK_RATE) * 3)
	game.clock.set_speed_index(0)
	await _frames(10)
	_expect(drill.total_fuel() > 0, "бур оставил себе добытый уголь на топливо (%d)" % drill.total_fuel())
	await _mouse_move(game, tile)
	await _frames(20)
	await _shot("p12_coal_drill.png")
	await _mouse_move(game, tile + Vector2i(0, 4))
	world.buildings.remove(drill, true)


## Колесо мыши на экранной точке.
func _wheel_screen(pos: Vector2, up: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = event.button_index
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


func _iron_index() -> int:
	return Registry.get_item(&"iron_ingot").index


## Отложить волны текущей планеты, чтобы враги не мешали остальным сценариям.
func _hold_threat(game: Game) -> void:
	if game.run.planet.threat != null:
		game.run.planet.threat.delay_next_wave(10000000)


## Угроза и враги: панель угрозы, толпа врагов, полоски прочности, гибель дрона и груз, вызов волны (F3 + N).
func _run_enemies(game: Game, base: Vector2i) -> void:
	var run := game.run
	var planet := run.planet
	var gate := planet.gateway
	_expect(planet.threat != null and planet.flow != null, "на опасной планете есть угроза и поле потоков")
	_expect(not planet.spawn_points.is_empty(), "у готовой карты найдены точки появления (%d)" % planet.spawn_points.size())
	await _frames(12)
	var panel := game.hud.threat_panel
	var wave_label: Label = panel.get("_wave_label")
	_expect(panel.visible and not wave_label.text.is_empty(), "панель угрозы показывает отсчёт: %s" % wave_label.text)

	# Толпа врагов западнее площадки: идут к шлюзу.
	var t := float(GameConst.TILE_SIZE)
	var origin := gate.get_world_center() + Vector2(-18, 9) * t
	var k := 0
	for def in Registry.enemies:
		for j in (12 if def.id == &"crawler" else (6 if def.id == &"soldier" else 2)):
			var p := origin + Vector2((k % 6) * 1.2, (k / 6) * 1.2) * t
			if planet.flow.get_dist(GameConst.world_to_tile(p)) < FlowField.INF:
				planet.spawn_enemy(def, p)
			k += 1
	_expect(planet.enemies.count > 10, "враги появились (%d)" % planet.enemies.count)
	var damaged_target: Building = null
	for b in planet.buildings.get_all():
		if b != gate and b.def.solid and planet.pad_rect.encloses(b.get_rect()):
			damaged_target = b
			break
	if damaged_target != null:
		planet.damage_building(damaged_target, damaged_target.get_max_health() * 0.5)
	planet.damage_building(gate, gate.get_max_health() * 0.2)
	await _drone_to(game, GameConst.world_to_tile(gate.get_world_center()) + Vector2i(-4, 4))
	game.camera.focus_on(origin.lerp(gate.get_world_center(), 0.5), 0.8)
	await _wait_ticks(planet, 90)
	_expect(game.planet_view.enemy_renderer.drawn_count > 0, "враги рисуются (%d в кадре)" % game.planet_view.enemy_renderer.drawn_count)
	var gate_row: HBoxContainer = panel.get("_gate_row")
	_expect(gate_row.visible, "повреждённый шлюз виден в панели угрозы")
	await _shot("e01_enemies.png")
	await _measure_frames("враги")

	# Дрона сбивают: груз на месте гибели, отсчёт до появления, затем подбор.
	var drone := run.drone
	var death_tile := GameConst.world_to_tile(gate.get_world_center()) + Vector2i(-9, 0)
	await _drone_to(game, death_tile)
	drone.inventory.add(Registry.get_item(&"hematite").index, 25)
	planet.damage_drone(100000.0, planet.simulation.tick)
	await _frames(6)
	var respawn_label: Label = game.hud.get("_respawn_label")
	_expect(drone.dead and respawn_label.visible and planet.crates.size() == 1, "дрон сбит: груз выпал, показан отсчёт")
	await _shot("e02_drone_down.png")
	await _wait_ticks(planet, drone.def.get_respawn_ticks() + 2)
	_expect(not drone.dead and drone.position == gate.get_world_center(), "дрон появился у шлюза")
	await _drone_to(game, death_tile)
	await _wait_ticks(planet, 2)
	_expect(planet.crates.is_empty() and drone.inventory.count(Registry.get_item(&"hematite").index) >= 25, "груз подобран")

	# Отладка: F3 и N вызывают волну.
	var wave := planet.threat.wave
	await _key(KEY_F3)
	await _key(KEY_N)
	await _wait_ticks(planet, 3)
	_expect(planet.threat.wave == wave + 1, "F3 + N вызывают следующую волну")
	await _key(KEY_F3)
	await _frames(5)
	await _shot("e03_wave.png")

	# Убираем врагов и чиним шлюз, чтобы не мешать телепорту.
	planet.enemies.clear()
	planet.threat.clear_pending()
	planet.threat.delay_next_wave(10000000)
	gate.health = gate.get_max_health()
	planet.damaged.erase(gate.id)
	await _frames(5)


## Свободный от зданий и строимый прямоугольник size рядом с center (поиск по кольцам).
func _find_clear_rect(world: GameWorld, size: Vector2i, center: Vector2i, radius: int) -> Vector2i:
	for r in range(0, radius):
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != r:
					continue
				var ok := true
				for yy in range(y, y + size.y):
					for xx in range(x, x + size.x):
						ok = ok and world.grid.in_bounds(xx, yy) and world.grid.is_buildable(xx, yy) and world.buildings.get_at(Vector2i(xx, yy)) == null
				if ok:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Оборона: турель из меню, патроны через окно турели, стены линией, радиусы (T), бой, ремонт дроном.
func _run_defense(game: Game) -> void:
	var run := game.run
	var planet := run.planet
	var tools := game.tools
	var gate := planet.gateway
	var inv := run.drone.inventory
	var gun_def := Registry.get_building(&"machine_gun")
	var wall_def := Registry.get_building(&"stone_wall")
	var copper := Registry.get_item(&"cartridge_iron").index
	inv.add(gun_def.item.index, 2)
	inv.add(wall_def.item.index, 12)
	inv.add(copper, 40)
	var spot := _find_clear_rect(planet, Vector2i(3, 8), GameConst.world_to_tile(gate.get_world_center()) + Vector2i(0, -10), 12)
	_expect(spot.x >= 0, "есть место под сцену обороны")
	if spot.x < 0:
		return
	await _drone_to(game, spot + Vector2i(1, 4))

	# Турель: вкладка «Оборона» → пулемёт → клик по карте.
	var menu := _find_child_of_type(game.hud, "BuildMenu") as BuildMenu
	var defense_tab: Button = (menu.get("_category_buttons") as Array)[BuildingDef.Category.DEFENSE]
	await _click_control(defense_tab)
	var gun_button: Button = (menu.get("_building_buttons") as Dictionary)[&"machine_gun"]
	await _click_control(gun_button)
	_expect(tools.mode == ToolController.Mode.PLACE and tools.place_def == gun_def, "вкладка «Оборона»: пулемёт в руке")
	var gun_tile := spot + Vector2i(1, 4)
	await _mouse_move(game, gun_tile)
	await _mouse_button(game, gun_tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, gun_tile, MOUSE_BUTTON_LEFT, false)
	var gun := planet.buildings.get_at(gun_tile) as Turret
	_expect(gun != null, "пулемёт поставлен")
	await _key(KEY_ESCAPE)
	if gun == null:
		return

	# Патроны: окно турели и клик по железным патронам в инвентаре.
	await _mouse_move(game, gun_tile)
	await _mouse_button(game, gun_tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, gun_tile, MOUSE_BUTTON_LEFT, false)
	var window := game.hud.inventory_window
	await _frames(5)
	_expect(window.visible and window.mode == InventoryWindow.Mode.BUILDING, "клик по турели открывает её окно")
	var slots: Array = window.get("_inventory_slots")
	var copper_slot := -1
	for i in inv.size():
		if inv.slot_items[i] == copper:
			copper_slot = i
			break
	if copper_slot >= 0:
		await _click_control(slots[copper_slot])
	await _frames(5)
	_expect(gun.total_shots > 0, "патроны из инвентаря легли в турель (%d выстрелов)" % gun.total_shots)
	await _shot("d00_turret_window.png")
	await _key(KEY_ESCAPE)
	await _frames(3)

	# Стены линией протягиванием.
	tools.select_building(wall_def)
	var a := spot + Vector2i(0, 0)
	var b := spot + Vector2i(0, 7)
	var before := planet.buildings.get_count()
	await _mouse_move(game, a)
	await _mouse_button(game, a, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, a + Vector2i(0, 1))
	await _mouse_move(game, b)
	await _frames(3)
	await _mouse_button(game, b, MOUSE_BUTTON_LEFT, false)
	_expect(planet.buildings.get_count() - before == 8, "стены ставятся линией (%d)" % (planet.buildings.get_count() - before))
	await _key(KEY_ESCAPE)

	# Радиусы турелей по T, враги идут мимо — пулемёт стреляет.
	await _key(KEY_T)
	_expect(game.planet_view.turret_view.show_ranges, "T показывает радиусы турелей")
	var enemy_origin := gun.get_world_center() + Vector2(-9, 2) * GameConst.TILE_SIZE
	for k in 4:
		var p := enemy_origin + Vector2(0, (k - 2) * 24)
		if planet.flow.get_dist(GameConst.world_to_tile(p)) < FlowField.INF:
			planet.spawn_enemy(Registry.get_enemy(&"crawler"), p)
	var spawned := planet.enemies.count
	var killed_before := planet.enemies.killed
	# Дрон отлетает, чтобы стреляла турель, а не автопушка.
	await _drone_to(game, spot + Vector2i(12, -4))
	game.camera.focus_on(gun.get_world_center() + Vector2(-3, 0) * GameConst.TILE_SIZE, 0.9)
	await _wait_ticks(planet, 45)
	await _shot("d01_defense.png")
	var guard := 0
	while planet.enemies.killed - killed_before < spawned and guard < 900:
		await get_tree().process_frame
		guard += 1
	# Часть ползунов может пройти к шлюзу вне радиуса турели — достаточно половины.
	_expect(spawned > 0 and (planet.enemies.killed - killed_before) * 2 >= spawned and gun.last_shot_tick > 0,
		"пулемёт уничтожил врагов (%d из %d)" % [planet.enemies.killed - killed_before, spawned])
	planet.enemies.clear()
	planet.projectiles.clear()
	await _key(KEY_T)
	_expect(not game.planet_view.turret_view.show_ranges, "T скрывает радиусы")

	# Ремонт: дрон рядом с повреждённой стеной чинит её бесплатно.
	var wall := planet.buildings.get_at(a + Vector2i(0, 3))
	planet.damage_building(wall, wall.get_max_health() * 0.8)
	await _drone_to(game, a + Vector2i(3, 3))
	game.camera.recenter()
	await _wait_ticks(planet, 12)
	_expect(run.drone.is_repairing(), "дрон чинит стену")
	await _shot("d02_repair.png")
	await _wait_ticks(planet, 240)
	_expect(not wall.is_damaged(), "стена починена")

## Прорыв: шлюз разрушен — аварийный телепорт на соседнюю планету и итог.
func _run_breach(game: Game) -> void:
	var run := game.run
	var planet := run.planet
	var gate := planet.gateway
	var ids := run.star_map.get_current().links.duplicate()
	var crawler := Registry.get_enemy(&"crawler")
	var flow := planet.ensure_flow()
	planet.spawn_enemy(crawler, gate.get_world_center() + Vector2(-3, 0) * GameConst.TILE_SIZE)
	# Дрон подальше: автопушка и ремонт не должны спасти шлюз.
	await _drone_to(game, gate.origin + Vector2i(1, 22))
	game.camera.focus_on(gate.get_world_center(), 1.0)
	gate.health = 1.0
	var guard := 0
	while run.planet == planet and guard < 600:
		await get_tree().process_frame
		guard += 1
	_expect(run.planet != planet and ids.has(run.star_map.current_id), "враг добил шлюз — аварийный телепорт на соседнюю планету")
	await _frames(20)
	var summary := run.last_summary
	_expect(game.hud.summary_window.visible and summary != null and summary.emergency, "показан итог аварийного телепорта")
	await _shot("e04_emergency_summary.png")
	var ok_button: Button = game.hud.summary_window.get("_ok_button")
	await _click_control(ok_button)
	_hold_threat(game)
	_expect(flow != null and run.planet.gateway.health == run.planet.gateway.get_max_health(), "шлюз на новой планете цел")


## База и планета: переход через шлюз по F, стройка в базе, предметы через шлюз в обе стороны.
func _run_gateway(game: Game) -> void:
	var run := game.run
	var gate := run.get_gateway(run.planet)
	var pair := run.get_gateway(run.base)
	var copper := Registry.get_item(&"hematite").index
	var lead := Registry.get_item(&"brick").index
	var conveyor := Registry.get_building(&"conveyor")

	# Планета: склад с гематитом → разгрузчик → лента в западный порт шлюза.
	var in_port := gate.get_input_tile()
	var planet_storage := run.planet.buildings.place(Registry.get_building(&"container"), in_port + Vector2i(-3, 0), 0, true) as StorageBuilding
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
	# Этаж по ширине меньше экрана — камера по X стоит в его центре и не показывает пустоту за краем.
	var bounds := run.base.get_play_rect_px()
	_expect(absf(game.camera.position.x - bounds.get_center().x) < 2.0 and bounds.has_point(game.camera.position),
		"камера на этаже — в пределах открытой части")

	# Много труб на экране: раньше кадр перерисовывал их все заново, теперь чанки кэшируются.
	# Ставим только на свободные тайлы этажа, ничего не сносим.
	var pipe_def := Registry.get_building(&"pipe")
	# Берём кусок этажа 24×24 — этого хватает, чтобы нагрузить отрисовку, и сцена не затягивается.
	var open_rect := run.base.play_rect.grow(-2)
	var field := Rect2i(open_rect.get_center() - Vector2i(12, 12), Vector2i(24, 24)).intersection(open_rect)
	var placed := 0
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			var tile := Vector2i(x, y)
			if run.base.buildings.check_place(pipe_def, tile, 0) != BuildingManager.Check.OK:
				continue
			if run.base.buildings.place(pipe_def, tile, 0) != null:
				placed += 1
	run.base.fluids.update()
	var zoom_before := game.camera.user_zoom
	game.camera.focus_on(Vector2(field.get_center() * GameConst.TILE_SIZE), 0.5)
	await _frames(20)
	await _measure_frames("%d труб на экране" % placed)
	_expect(placed > 100, "этаж заставлен трубами (%d)" % placed)
	await _shot("w01b_pipe_field.png")
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			var pipe := run.base.buildings.get_at(Vector2i(x, y))
			if pipe is Pipe:
				run.base.buildings.remove(pipe)
	run.base.fluids.update()
	# Масштаб возвращаем: иначе дальше камера смотрит слишком широко и упирается в край карты.
	game.camera.focus_on(run.drone.position, zoom_before)
	game.camera.recenter()
	await _frames(20)

	# Стройка в базе настоящим вводом.
	var base_tile := pair.origin + Vector2i(1, -3)
	game.tools.select_building(conveyor)
	await _mouse_move(game, base_tile)
	await _mouse_button(game, base_tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, base_tile, MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	_expect(run.base.buildings.get_at(base_tile) != null and run.planet.buildings.get_at(base_tile) == null, "клик строит в базе, а не на планете")

	# База: из западного порта пары — в склад; склад с кирпичами → разгрузчик → восточный порт пары.
	var out_port := pair.get_output_tile()
	Worlds_line(run.base, out_port, 2, GameConst.Dir.LEFT)
	var base_in := run.base.buildings.place(Registry.get_building(&"container"), out_port + Vector2i(-2, 0), 0, true) as StorageBuilding
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
	_expect(base_in.inventory.count(copper) > 0, "гематит с планеты пришёл в базу через шлюз (%d)" % base_in.inventory.count(copper))

	# Обратно на планету: кирпичи из базы вышли из восточного порта шлюза.
	await _drone_to(game, pair.origin + Vector2i.ONE)
	await _key(KEY_F)
	await _frames(5)
	_expect(game.world == run.planet and not game.is_in_base(), "F над парой — обратно на планету")
	await _frames(10)
	await _shot("w03_planet_gateway.png")
	_expect(planet_out.inventory.count(lead) > 0, "кирпичи из базы вышли на планету (%d)" % planet_out.inventory.count(lead))
	_expect(run.base.simulation.tick == run.planet.simulation.tick, "база тикает, пока дрон на планете")


## Сохранения: F5 — быстрое сохранение, меню паузы — сохранение в слот (загрузка проверяется тестами).
func _run_saves(game: Game) -> void:
	var quick := SaveIO.slot_path(Game.QUICKSAVE_FILE)
	SaveIO.delete_save(quick)
	await _key(KEY_F5)
	await _frames(5)
	_expect(FileAccess.file_exists(quick), "F5 делает быстрое сохранение")
	var header := SaveIO.read_header(quick)
	_expect(String(header.get("title", "")) == game.run.get_world_title(game.run.planet), "в заголовке — текущая планета")

	game.open_pause_menu()
	await _frames(5)
	var saves_screen: SavesScreen = game.pause_menu.get("_saves")
	game.pause_menu.call("_open_saves", SavesScreen.Mode.SAVE)
	await _frames(10)
	_expect(saves_screen.visible and saves_screen.mode == SavesScreen.Mode.SAVE, "меню паузы открывает экран сохранения")
	var name_edit: LineEdit = saves_screen.get("_name_edit")
	name_edit.text = "autoshot slot"
	var save_button: Button = saves_screen.get("_save_button")
	var path := SaveIO.slot_path("autoshot slot")
	SaveIO.delete_save(path)
	await _click_control(save_button)
	await _frames(5)
	_expect(FileAccess.file_exists(path), "кнопка «Сохранить» пишет слот")
	await _shot("s01_save_screen.png")
	var loaded := SaveIO.load_run(path)
	_expect(loaded != null and loaded.star_map.get_current().id == game.run.star_map.get_current().id, "слот загружается в тот же забег")
	if loaded != null:
		loaded.dispose()
	SaveIO.delete_save(path)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	_expect(not game.pause_menu.is_open(), "меню паузы закрыто")


## Телепорт: клик по шлюзу, звёздная карта, зарядка, итог; площадка переезжает, остальное теряется.
func _run_teleport(game: Game) -> void:
	var run := game.run
	var gate := run.get_gateway(run.planet)
	var old_planet := run.planet
	var pad := run.planet.pad_rect
	var lead := Registry.get_item(&"brick").index
	# Склад у выхода шлюза (из сценария шлюза) стоит на площадке — должен переехать с кирпичами.
	var pad_storage := run.planet.buildings.get_at(gate.get_output_tile() + Vector2i(2, 0)) as StorageBuilding
	var pad_lead := pad_storage.inventory.count(lead) if pad_storage != null else 0
	var storage_offset := pad_storage.origin - pad.position if pad_storage != null else Vector2i.ZERO
	var buildings_outside := 0
	for b in run.planet.buildings.get_all():
		if b != gate and not pad.encloses(b.get_rect()):
			buildings_outside += 1

	await _drone_to(game, gate.origin + Vector2i.ONE)
	game.camera.focus_on(run.drone.position, 1.0)
	await _frames(3)
	var gate_tile := gate.origin + Vector2i.ONE
	await _mouse_move(game, gate_tile)
	await _mouse_button(game, gate_tile, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, gate_tile, MOUSE_BUTTON_LEFT, false)
	var window := game.hud.teleport_window
	_expect(window.visible and game.tools.selected == gate, "клик по шлюзу открывает окно телепорта")
	var next := run.star_map.get_next()
	_expect(not next.is_empty(), "со стартовой планеты есть куда лететь")
	if next.is_empty():
		return
	window.select_node(next[next.size() - 1].id)
	await _frames(10)
	await _shot("t01_star_map.png")
	var start_button: Button = window.get("_start_button")
	await _click_control(start_button)
	_expect(run.is_charging() and run.charge_target == next[next.size() - 1].id, "кнопка запускает зарядку телепорта")
	await _frames(5)
	await _shot("t02_charging.png")
	await _key(KEY_ESCAPE)
	_expect(not window.visible and run.is_charging(), "окно закрывается, зарядка продолжается")

	game.clock.set_speed_index(2)
	var guard := 0
	while run.planet == old_planet and guard < 8000:
		await get_tree().process_frame
		guard += 1
	game.clock.set_speed_index(0)
	_expect(run.planet != old_planet and game.world == run.planet, "после зарядки дрон на новой планете")
	await _frames(20)
	_expect(game.hud.summary_window.visible, "показан итог планеты")
	await _shot("t03_summary.png")
	var summary := run.last_summary
	_expect(summary != null and summary.buildings_lost == buildings_outside, "итог: потеряны постройки вне площадки (%d из %d)" % [summary.buildings_lost if summary != null else -1, buildings_outside])
	var moved := run.planet.buildings.get_at(run.planet.pad_rect.position + storage_offset) as StorageBuilding
	_expect(pad_storage == null or (moved != null and moved.inventory.count(lead) == pad_lead), "склад площадки переехал с кирпичами (%d)" % pad_lead)
	var ok_button: Button = game.hud.summary_window.get("_ok_button")
	if ok_button != null:
		await _click_control(ok_button)
	_expect(not game.hud.summary_window.visible, "итог закрывается")
	var title: Label = game.hud.get("_title_label")
	_expect(title.text == run.get_world_title(run.planet), "заголовок — новая планета: %s" % title.text)
	await _frames(20)
	await _shot("t04_new_planet.png")
	game.camera.focus_on(run.drone.position, 0.35)
	await _frames(20)
	await _shot("t05_new_planet_overview.png")
	game.camera.recenter()


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
	await _frames(60)
	_expect(game.camera.position.distance_to(drone.get_draw_position(game.clock.alpha)) < 2.0,
		"камера следует за дроном (%.1f px)" % game.camera.position.distance_to(drone.get_draw_position(game.clock.alpha)))
	await _shot("d00_drone.png")

	# Добыча: ЛКМ по руде с зажатием.
	var ore_tile := _find_ore_tile(world, &"hematite", base, 30)
	_expect(ore_tile != Vector2i(-1, -1), "рядом есть гематит")
	if ore_tile == Vector2i(-1, -1):
		return
	await _drone_to(game, ore_tile + Vector2i(-3, 1))
	var copper := Registry.get_item(&"hematite").index
	var copper_before := inv.count(copper)
	await _mouse_move(game, ore_tile)
	await _mouse_button(game, ore_tile, MOUSE_BUTTON_LEFT, true)
	_expect(drone.is_mining() and drone.mine_tile == ore_tile, "ЛКМ по руде включает добычу")
	game.clock.set_speed_index(2)
	await _wait_ticks(world, drone.def.mine_ticks(Registry.get_ore(&"hematite")) * 2 + 4)
	game.clock.set_speed_index(0)
	await _frames(3)
	await _shot("d01_mining.png")
	await _mouse_button(game, ore_tile, MOUSE_BUTTON_LEFT, false)
	_expect(inv.count(copper) >= copper_before + 2, "дрон добыл гематит (+%d)" % (inv.count(copper) - copper_before))
	_expect(drone.last_mined_item == copper and drone.last_mined_count == inv.count(copper)
		and drone.last_mined_tile == ore_tile and world.simulation.tick - drone.last_mined_tick < DroneView.MINED_TICKS,
		"над тайлом видна надпись «%s ×%d»" % [tr(Registry.items[copper].name_key), drone.last_mined_count])
	await _shot("d05b_mined_label.png")
	_expect(drone.get_mineable_ore(_find_any_ore_tile(world, &"malachite", base, 60)) == null, "малахит дрону не по силам")
	_expect(not drone.is_mining(), "отпускание кнопки останавливает добычу")

	# Окно инвентаря (E): вкладка компонентов, затем крафт ленты кликом по рецепту (шестерня докрафчивается).
	inv.add(Registry.get_item(&"iron_ingot").index, 80)
	await _drone_to(game, base)
	await _key(KEY_E)
	var window := game.hud.inventory_window
	_expect(window.visible and window.mode == InventoryWindow.Mode.CRAFT, "E открывает инвентарь и крафт")
	await _frames(5)
	var component_slots: Dictionary = window.get("_recipe_slots")
	_expect(component_slots.has(Registry.get_item(&"gear").index) and component_slots.has(Registry.get_item(&"science_kit").index),
		"первая вкладка крафта — компоненты (шестерня, научный набор)")
	await _shot("d02_inventory.png")
	var craft_tabs: Array = window.get("_category_buttons")
	await _click_control(craft_tabs[BuildingDef.Category.TRANSPORT + 1] as Control)
	await _frames(3)
	var belt := Registry.get_building(&"conveyor").item.index
	var belt_recipe := Registry.get_hand_recipe(belt)
	var belts_before := inv.count(belt)
	var recipe_slots: Dictionary = window.get("_recipe_slots")
	var belt_slot := recipe_slots.get(belt) as ItemSlot
	_expect(belt_slot != null, "во вкладке «Транспорт» есть рецепт ленты")
	if belt_slot == null:
		return
	await _click_control(belt_slot)
	await _wait_craft(world)
	_expect(inv.count(belt) == belts_before + belt_recipe.amount, "клик по рецепту крафтит ленты (+%d)" % (inv.count(belt) - belts_before))
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
	game.clock.set_speed_index(2)
	await _wait_craft(world)
	game.clock.set_speed_index(0)
	_expect(drone.crafting.is_empty() and inv.count(belt) == belts_before + belt_recipe.amount * 7,
		"очередь докрафтила ленты (+%d)" % (inv.count(belt) - belts_before))


## Инструменты через настоящие события ввода.
func _run_interaction(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var inv := world.drone.inventory
	var conveyor := Registry.get_building(&"conveyor")
	inv.add(Registry.get_building(&"drill").item.index, 4)
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
	var extraction_tab: Button = (menu.get("_category_buttons") as Array)[BuildingDef.Category.PRODUCTION]
	await _click_control(extraction_tab)
	_expect(int(menu.get("_category")) == BuildingDef.Category.PRODUCTION, "с лентой в руке вкладка «Производство» открывается")
	_expect(tools.mode == ToolController.Mode.PLACE and tools.place_def == conveyor, "здание остаётся в руке при смене вкладки")
	await _frames(3)
	await _shot("i02_tab_switch.png")
	var drill_button: Button = (menu.get("_building_buttons") as Dictionary)[&"drill"]
	var rect_before := drill_button.get_global_rect()
	await _mouse_move_screen(rect_before.get_center())
	await _frames(3)
	_expect(drill_button.get_global_rect() == rect_before, "наведение на кнопку не сдвигает панель")
	await _click_control(drill_button)
	_expect(tools.place_def == Registry.get_building(&"drill"), "клик по буру в другой вкладке выбирает бур")

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
	var drill := Registry.get_building(&"drill")
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
		if x.def.removable:
			bm.remove(x, true)


## Цепочка «бур → лента → контейнер»: буры от термогенератора через опоры, предметы едут и складываются.
func _run_production_chain(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var drill := Registry.get_building(&"drill")
	var conveyor := Registry.get_building(&"conveyor")
	var copper := Registry.get_item(&"hematite").index

	# Контейнер северо-западнее места посадки, буры на ближайшем гематите, лента от буров к контейнеру.
	var container := bm.place(Registry.get_building(&"container"), base + Vector2i(-3, -3), 0, true) as StorageBuilding
	var spot := _find_drill_spot(world, drill, base, 20)
	var drills: Array[Building] = []
	for dx in [0, 2, 4]:
		for row in [[0, GameConst.Dir.DOWN], [3, GameConst.Dir.UP]]:
			var placed := bm.place(drill, spot + Vector2i(dx, row[0]), row[1])
			if placed != null:
				drills.append(placed)
	var target := container.origin + Vector2i(0, -1)
	var line_start := spot + Vector2i(0, 2)
	for step in LinePlanner.l_path(line_start, Vector2i(target.x, line_start.y), true, 0):
		bm.place(conveyor, Vector2i(step.x, step.y), step.z)
	var turn := Vector2i(target.x, line_start.y)
	var vertical_dir := GameConst.Dir.DOWN if target.y > turn.y else GameConst.Dir.UP
	for step in LinePlanner.l_path(turn, target, false, vertical_dir):
		bm.place(conveyor, Vector2i(step.x, step.y), vertical_dir if Vector2i(step.x, step.y) != target else GameConst.Dir.DOWN)
	_expect(not drills.is_empty(), "поставлено буров на гематите: %d" % drills.size())
	if drills.is_empty():
		return
	await _wait_ticks(world, 30)
	_expect(drills[0].get_status() == Building.Status.NO_POWER and world.power.unconnected.has(drills[0]), "бур без опоры — «нет питания»")
	game.camera.focus_on(Vector2(spot * GameConst.TILE_SIZE) + Vector2(160, 48), 1.3)
	await _frames(10)
	await _shot("g02a_no_power.png")
	_power_up(world, drills)
	await _wait_ticks(world, 2)
	var powered := 0
	for d in drills:
		if d.power_net != null:
			powered += 1
	_expect(powered == drills.size(), "опоры и термогенераторы подключили все буры (%d из %d)" % [powered, drills.size()])

	game.clock.set_speed_index(2)
	await _wait_ticks(world, 40 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	await _frames(20)
	await _shot("g02_items_on_belts.png")
	var stored := container.inventory.count(copper)
	_expect(stored > 0, "гематит дошёл до контейнера (%d)" % stored)
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
	_expect(inv.count(copper) > copper_before and container.inventory.count(copper) < in_container, "ЛКМ по ячейке контейнера забирает гематит")
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


## Производство: склад → печь (гематит и уголь) → сборщик шестерней от электричества → лента → склад;
## статусы в подсказках, выбор рецепта сборщика в панели настройки.
func _run_factory(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var hematite := Registry.get_item(&"hematite").index
	var coal := Registry.get_item(&"coal").index
	var gear := Registry.get_item(&"gear").index
	var container_def := Registry.get_building(&"container")
	var unloader_def := Registry.get_building(&"unloader")
	var spot := _find_clear_rect(world, Vector2i(14, 6), base + Vector2i(-6, -12), 20)
	_expect(spot.x >= 0, "есть место под сцену производства")
	if spot.x < 0:
		return
	var source := bm.place(container_def, spot + Vector2i(1, 1), 0, true) as StorageBuilding
	source.inventory.add(hematite, 200)
	source.inventory.add(coal, 30)
	bm.place(unloader_def, spot + Vector2i(2, 1), 0, true)
	var furnace := bm.place(Registry.get_building(&"furnace"), spot + Vector2i(3, 1), 0, true) as Crafter
	bm.place(unloader_def, spot + Vector2i(5, 1), 0, true)
	var assembler := bm.place(Registry.get_building(&"assembler"), spot + Vector2i(6, 1), 0, true) as Crafter
	var out_unloader := bm.place(unloader_def, spot + Vector2i(8, 1), 0, true)
	world.configure(out_unloader, gear)
	# Разгрузчик в склад не кладёт — продукция едет по ленте.
	Worlds_line(world, spot + Vector2i(9, 1), 2, GameConst.Dir.RIGHT)
	var output := bm.place(container_def, spot + Vector2i(11, 1), 0, true) as StorageBuilding
	_expect(furnace != null and assembler != null and output != null, "печь, сборщик и склады поставлены")
	if furnace == null or assembler == null or output == null:
		return
	await _drone_to(game, spot + Vector2i(5, 4))
	game.camera.focus_on(Vector2((spot + Vector2i(6, 2)) * GameConst.TILE_SIZE), 1.4)
	await _wait_ticks(world, 10)
	_expect(assembler.get_status() == Building.Status.NO_RECIPE, "сборщик без рецепта в статусе «нет рецепта»")
	await _mouse_move(game, assembler.origin)
	await _frames(40)
	await _shot("g11_tooltip_assembler.png")

	# Рецепт сборщика — кликом в панели настройки.
	await _mouse_button(game, assembler.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, assembler.origin, MOUSE_BUTTON_LEFT, false)
	var panel := _find_child_of_type(game.hud, "ConfigPanel") as ConfigPanel
	await _frames(3)
	_expect(tools.selected == assembler and panel != null and panel.visible, "клик по сборщику открывает выбор рецепта")
	var grid: Node = _find_child_of_class(panel, "GridContainer") if panel != null else null
	var gear_index := (assembler.def as CrafterDef).find_recipe_index(&"gear")
	if grid != null and gear_index >= 0 and grid.get_child_count() > gear_index:
		await _click_control(grid.get_child(gear_index) as Control)
	_expect(assembler.get_recipe() != null and assembler.get_recipe().id == &"gear", "клик по шестерне выбирает рецепт")
	await _frames(3)
	await _shot("g11b_recipe_picker.png")
	await _key(KEY_ESCAPE)

	# Печь работает на угле; сборщик получил железо, но без опоры стоит.
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 15 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	_expect(furnace.get_status() == Building.Status.WORKING or furnace.outputs[Registry.get_item(&"iron_ingot").index] > 0, "печь плавит гематит на угле")
	_expect(assembler.get_status() == Building.Status.NO_POWER, "сборщик без опоры — «нет питания»")
	_power_up(world, [assembler])
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 40 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	_expect(output.inventory.count(gear) > 0, "шестерни из сборщика дошли до склада (%d)" % output.inventory.count(gear))
	await _mouse_move(game, furnace.origin)
	await _frames(40)
	await _shot("g12_tooltip_furnace.png")
	await _mouse_button(game, furnace.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, furnace.origin, MOUSE_BUTTON_LEFT, false)
	await _frames(15)
	var furnace_window := game.hud.inventory_window
	var furnace_views: Array = furnace_window.get("_section_views")
	_expect(furnace_window.visible and furnace_views.size() == 5 and (furnace_views[0] as Dictionary).has("slots")
		and (furnace_views[3] as Dictionary).has("bar"), "окно печи: сырьё, топливо, продукт, прогресс, горение")
	await _shot("g13_furnace_window.png")
	await _key(KEY_ESCAPE)
	# Shift+ПКМ загружает всё подходящее, Shift+ЛКМ забирает только продукцию.
	# Печь для показа ставим отдельно: у печи из цепочки продукцию сразу забирает разгрузчик.
	var demo_at := spot + Vector2i(3, 4)
	if bm.check_place(Registry.get_building(&"furnace"), demo_at, 0) == BuildingManager.Check.OK:
		var demo := bm.place(Registry.get_building(&"furnace"), demo_at, 0, true) as Crafter
		var inv := world.drone.inventory
		inv.add(hematite, 20)
		inv.add(coal, 5)
		await _drone_to(game, demo_at + Vector2i(1, 3))
		await _mouse_move(game, demo_at)
		await _key_hold(KEY_SHIFT, true)
		await _mouse_button(game, demo_at, MOUSE_BUTTON_RIGHT, true)
		await _mouse_button(game, demo_at, MOUSE_BUTTON_RIGHT, false)
		await _frames(5)
		_expect(demo.inputs[hematite] > 0 and demo.total_fuel() > 0, "Shift+ПКМ загружает сырьё и топливо")
		game.clock.set_speed_index(2)
		await _wait_ticks(world, 12 * GameConst.TICK_RATE)
		game.clock.set_speed_index(0)
		inv.remove(hematite, inv.count(hematite))
		inv.remove(coal, inv.count(coal))
		var iron := _iron_index()
		var before_iron := inv.count(iron)
		var ready: int = demo.outputs[iron]
		await _mouse_button(game, demo_at, MOUSE_BUTTON_LEFT, true)
		await _mouse_button(game, demo_at, MOUSE_BUTTON_LEFT, false)
		await _key_hold(KEY_SHIFT, false)
		await _frames(5)
		_expect(ready > 0 and inv.count(iron) == before_iron + ready and demo.outputs[iron] == 0,
			"Shift+ЛКМ забирает продукцию (%d)" % ready)
		_expect(demo.inputs[hematite] > 0 and demo.total_fuel() > 0, "сырьё и топливо остаются в печи")
		await _shot("g13b_quick_transfer.png")
		bm.remove(demo, true)
	await _mouse_move(game, spot + Vector2i(20, 20))
	await _frames(3)
	await _drone_to(game, base)


## Энергия и жидкости: насос на воде → трубы → бойлер → паровой генератор → опоры → сборщик;
## зоны питания видны с опорой в руке.
func _run_power(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var pump_def := Registry.get_building(&"pump")
	var layout := _find_steam_spot(world, base, 50)
	_expect(layout.x >= 0, "у воды есть место под паровую станцию")
	if layout.x < 0:
		return
	_expect(bm.check_place(pump_def, layout + Vector2i(-1, 0), 0) == BuildingManager.Check.NO_ORE, "насос без воды не ставится")
	var pump := bm.place(pump_def, layout, 0, true)
	for x in [1, 5]:
		bm.place(Registry.get_building(&"pipe"), layout + Vector2i(-x, 0), 0, true)
	bm.place(Registry.get_building(&"stone_wall"), layout + Vector2i(-3, 0), 0, true)
	var boiler := bm.place(Registry.get_building(&"boiler"), layout + Vector2i(-7, 0), 2, true) as Boiler
	var generator := bm.place(Registry.get_building(&"steam_generator"), layout + Vector2i(-9, 0), 0, true) as Generator
	var coal := Registry.get_item(&"coal").index
	while boiler.accept_item(null, coal):
		boiler.handle_item(null, coal)
	# Потребитель: сборщик шестерней со складом железа.
	var storage := bm.place(Registry.get_building(&"container"), layout + Vector2i(-11, 4), 0, true) as StorageBuilding
	storage.inventory.add(Registry.get_item(&"iron_ingot").index, 300)
	bm.place(Registry.get_building(&"unloader"), layout + Vector2i(-10, 4), 0, true)
	var assembler := bm.place(Registry.get_building(&"assembler"), layout + Vector2i(-9, 4), 0, true) as Crafter
	world.configure(assembler, &"gear")
	_wire(world, generator, assembler)
	await _drone_to(game, layout + Vector2i(-5, 3))
	game.camera.focus_on(Vector2((layout + Vector2i(-5, 2)) * GameConst.TILE_SIZE), 1.4)

	# Подземная труба под стеной: вход и выход ставятся одним поворотом, выход разворачивается сам.
	var under_def := Registry.get_building(&"underground_pipe")
	world.drone.inventory.add(under_def.item.index, 2)
	tools.select_building(under_def)
	tools.rotation = GameConst.Dir.LEFT
	for x in [2, 4]:
		var tile := layout + Vector2i(-x, 0)
		await _mouse_move(game, tile)
		await _mouse_button(game, tile, MOUSE_BUTTON_LEFT, true)
		await _mouse_button(game, tile, MOUSE_BUTTON_LEFT, false)
	var entrance := bm.get_at(layout + Vector2i(-2, 0)) as UndergroundPipe
	var exit := bm.get_at(layout + Vector2i(-4, 0)) as UndergroundPipe
	_expect(entrance != null and exit != null and entrance.rotation == GameConst.Dir.LEFT and exit.rotation == GameConst.Dir.RIGHT,
		"подземные трубы поставлены кликами, выход развернулся ко входу")
	_expect(entrance != null and entrance.get_linked_partner() == exit, "вход и выход соединены под стеной")
	await _frames(3)
	_expect(game.planet_view.network_view.show_underground, "с трубой в руке виден подземный участок")
	await _shot("p00_underground_pipe.png")
	# На воду лента не ставится.
	tools.select_building(Registry.get_building(&"conveyor"))
	var water_tile := _find_free_water(world, layout, 12)
	if water_tile.x >= 0:
		await _mouse_move(game, water_tile)
		await _frames(3)
		_expect(tools.plan_problem == BuildingManager.Check.ON_FLUID, "лента на воду не ставится — подсказка о воде")
		await _shot("p00b_water_problem.png")
	await _key(KEY_ESCAPE)
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 10 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	var water_net := world.fluids.get_pipe_network(bm.get_at(layout + Vector2i(-5, 0)))
	_expect(pump != null and water_net != null and water_net.fluid == Registry.get_fluid(&"water").index and water_net.amount > 0.0,
		"насос качает воду в трубы")
	_expect(boiler.last_steam_rate > 0.0 and generator.last_output_kw > 0.0, "бойлер делает пар, паровой генератор выдаёт ток (%.0f кВт)" % generator.last_output_kw)
	_expect(assembler.power_net != null and assembler.power_net.generators.has(generator), "сборщик в сети парового генератора")
	_expect(assembler.outputs[Registry.get_item(&"gear").index] > 0 or assembler.get_status() == Building.Status.WORKING, "сборщик работает от пара")
	await _frames(5)
	await _shot("p01_steam_power.png")
	# Опора в руке — зоны питания всех опор.
	tools.select_building(Registry.get_building(&"small_power_pole"))
	await _mouse_move(game, layout + Vector2i(-4, 3))
	await _frames(5)
	_expect(game.planet_view.network_view.show_power_areas, "с опорой в руке видны зоны питания")
	await _shot("p02_power_areas.png")
	await _key(KEY_ESCAPE)
	await _frames(3)
	_expect(not game.planet_view.network_view.show_power_areas, "без опоры в руке зоны скрыты")
	# Аккумулятор рядом со сборщиком, оверлей сетей (P) и окно опоры с графиком.
	var accumulator := bm.place(Registry.get_building(&"accumulator"), assembler.origin + Vector2i(3, 0), 0, true) as Accumulator
	_wire(world, generator, accumulator)
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 12 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	_expect(accumulator != null and accumulator.power_net != null and accumulator.stored_kj > 0.0, "аккумулятор заряжается излишком пара (%.0f кДж)" % (accumulator.stored_kj if accumulator != null else -1.0))
	await _key(KEY_P)
	await _frames(5)
	_expect(game.planet_view.network_view.power_overlay, "P включает оверлей электросетей")
	await _shot("p05_power_overlay.png")
	await _key(KEY_P)
	var net_pole: PowerPole = null
	for id in world.power.poles:
		if world.power.poles[id].power_net == accumulator.power_net:
			net_pole = world.power.poles[id]
			break
	if net_pole != null:
		await _mouse_move(game, net_pole.origin)
		await _mouse_button(game, net_pole.origin, MOUSE_BUTTON_LEFT, true)
		await _mouse_button(game, net_pole.origin, MOUSE_BUTTON_LEFT, false)
		await _frames(15)
		var pole_views: Array = game.hud.inventory_window.get("_section_views")
		var has_chart := false
		for v in pole_views:
			has_chart = has_chart or (v as Dictionary).has("chart")
		_expect(game.hud.inventory_window.visible and has_chart, "окно опоры: график сети")
		# Ряды графика включаются кнопками под ним.
		for v in pole_views:
			var dict := v as Dictionary
			if not dict.has("chart"):
				continue
			var chart: PowerChart = dict["chart"]
			var legend: Array = dict["legend"]
			_expect(chart.series.size() == 4 and legend.size() == 4, "на графике четыре ряда: спрос, выработка, возможная, заряд")
			if legend.size() == 4:
				await _click_control(legend[1] as Button)
				await _frames(5)
				_expect(chart.hidden_series.has(1), "кнопка выключает ряд выработки")
				await _shot("p06b_network_series.png")
				await _click_control(legend[1] as Button)
				await _frames(5)
				_expect(not chart.hidden_series.has(1), "повторный клик возвращает ряд")
		await _shot("p06_network_window.png")
		await _key(KEY_ESCAPE)
	await _mouse_move(game, boiler.origin)
	await _frames(40)
	await _shot("p03_tooltip_boiler.png")
	await _mouse_button(game, boiler.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, boiler.origin, MOUSE_BUTTON_LEFT, false)
	await _frames(15)
	var window := game.hud.inventory_window
	var views: Array = window.get("_section_views")
	_expect(window.visible and views.size() == 5, "окно бойлера: топливо и четыре полоски (%d)" % views.size())
	await _shot("p04_boiler_window.png")
	await _key(KEY_ESCAPE)
	await _run_pipe_dragging(game, layout)
	await _mouse_move(game, layout + Vector2i(20, 20))
	await _drone_to(game, base)


## Трубы протягиванием: стена перекрывается подземной парой сама; ряд подземных встаёт с наибольшим шагом.
## Рядом — водный бак: он входит в ту же сеть труб и вмещает много.
func _run_pipe_dragging(game: Game, layout: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var inv := world.drone.inventory
	var pipe_def := Registry.get_building(&"pipe")
	var under_def := Registry.get_building(&"underground_pipe") as FluidBuildingDef
	var row := layout + Vector2i(-2, 6)
	if not _rect_clear(world, Rect2i(row + Vector2i(0, -1), Vector2i(16, 5))):
		return
	await _drone_to(game, row + Vector2i(6, 3))
	bm.place(Registry.get_building(&"stone_wall"), row + Vector2i(-4, 0), 0, true)
	bm.place(Registry.get_building(&"stone_wall"), row + Vector2i(-5, 0), 0, true)
	inv.add(pipe_def.item.index, 20)
	inv.add(under_def.item.index, 10)
	tools.select_building(pipe_def)
	await _mouse_move(game, row)
	await _mouse_button(game, row, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, row + Vector2i(-8, 0))
	await _frames(3)
	await _mouse_button(game, row + Vector2i(-8, 0), MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	var entry := bm.get_at(row + Vector2i(-3, 0)) as UndergroundPipe
	var exit := bm.get_at(row + Vector2i(-6, 0)) as UndergroundPipe
	_expect(entry != null and exit != null and entry.get_linked_partner() == exit,
		"протягивание трубы через стену само ставит подземную пару")
	await _shot("p07_pipe_drag.png")

	# Ряд подземных труб: клик с протягиванием ставит пары на наибольшем расстоянии.
	var under_row := row + Vector2i(0, 2)
	tools.select_building(under_def)
	await _mouse_move(game, under_row)
	await _mouse_button(game, under_row, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, under_row + Vector2i(-under_def.underground_range, 0))
	await _frames(3)
	await _mouse_button(game, under_row + Vector2i(-under_def.underground_range, 0), MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	var far := bm.get_at(under_row + Vector2i(-under_def.underground_range, 0)) as UndergroundPipe
	var near := bm.get_at(under_row) as UndergroundPipe
	_expect(near != null and far != null and near.get_linked_partner() == far,
		"ряд подземных труб: пара на всю дальность")
	var middle_empty := true
	for i in range(1, under_def.underground_range):
		middle_empty = middle_empty and bm.get_at(under_row + Vector2i(-i, 0)) == null
	_expect(middle_empty, "между парой пусто — трубы не тратятся зря")
	await _shot("p08_underground_drag.png")

	# Водный бак 2×2 в ту же сеть.
	var tank_def := Registry.get_building(&"water_tank")
	var tank_at := row + Vector2i(2, 1)
	if bm.check_place(tank_def, tank_at, 0) == BuildingManager.Check.OK:
		inv.add(tank_def.item.index, 1)
		tools.select_building(tank_def)
		await _mouse_move(game, tank_at)
		await _mouse_button(game, tank_at, MOUSE_BUTTON_LEFT, true)
		await _mouse_button(game, tank_at, MOUSE_BUTTON_LEFT, false)
		await _key(KEY_ESCAPE)
		var tank := bm.get_at(tank_at)
		_expect(tank != null and tank.get_size() == 2, "водный бак 2×2 поставлен")
		if tank != null:
			bm.place(pipe_def, tank_at + Vector2i(-1, 0), 0, true)
			world.fluids.update()
			var tank_net := world.fluids.get_pipe_network(tank)
			var row_net := world.fluids.get_pipe_network(bm.get_at(row))
			_expect(tank_net != null and tank_net == row_net and tank_net.capacity > 1000.0,
				"бак в одной сети с трубами и сильно поднял её ёмкость (%.0f)" % (tank_net.capacity if tank_net != null else 0.0))



## Логистика: витрина зданий, настройка кликами, мосты, оверлей загрузки лент.
func _run_logistics(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var copper := Registry.get_item(&"hematite").index
	var lead := Registry.get_item(&"brick").index
	await _drone_to(game, base)

	# Витрина: разгрузчик у склада → сортировщик → маршрутизатор → мост над препятствием, перекрёсток.
	var storage := bm.place(Registry.get_building(&"container"), base + Vector2i(2, 1), 0, true) as StorageBuilding
	storage.inventory.add(copper, 600)
	var right := base + Vector2i(3, 1)
	var unloader := bm.place(Registry.get_building(&"unloader"), right, 0, true)
	world.configure(unloader, copper)
	Worlds_line(world, right + Vector2i(1, 0), 3, GameConst.Dir.RIGHT)
	var sorter := bm.place(Registry.get_building(&"sorter"), right + Vector2i(4, 0), 0, true)
	world.configure(sorter, copper)
	Worlds_line(world, right + Vector2i(5, 0), 2, GameConst.Dir.RIGHT)
	var router := bm.place(Registry.get_building(&"router"), right + Vector2i(7, 0), 0, true) as Router
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
	Worlds_line(world, right + Vector2i(7, -1), 3, GameConst.Dir.UP)

	game.camera.focus_on(Vector2((right + Vector2i(8, 1)) * GameConst.TILE_SIZE), 1.1)
	game.clock.set_speed_index(2)
	await _wait_ticks(world, 15 * GameConst.TICK_RATE)
	game.clock.set_speed_index(0)
	await _frames(10)
	await _shot("g09_logistics.png")
	_expect(sorter.get_display_item() == copper, "сортировщик показывает фильтр")
	_expect(bridge_a.get_link_target() == bridge_b, "мост витрины связан")
	_expect(storage.inventory.count(copper) < 600, "разгрузчик достаёт гематит из склада")

	# Приоритетный выход маршрутизатора кликом в панели: весь поток уходит вниз, пока лента принимает.
	await _mouse_move(game, router.origin)
	await _mouse_button(game, router.origin, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, router.origin, MOUSE_BUTTON_LEFT, false)
	var router_panel := _find_child_of_type(game.hud, "ConfigPanel") as ConfigPanel
	await _frames(3)
	_expect(tools.selected == router and router_panel != null and router_panel.visible, "клик по маршрутизатору открывает приоритеты")
	var down_buttons := _find_buttons_with_text(router_panel, "↓")
	_expect(down_buttons.size() == 2, "в панели строки приоритетного входа и выхода")
	if down_buttons.size() == 2:
		await _click_control(down_buttons[1])
	_expect(router.priority_out == GameConst.Dir.DOWN and router.priority_in == Router.NO_SIDE, "клик по «↓» в строке выхода делает нижнюю сторону приоритетной")
	await _frames(3)
	await _shot("i06_router_priority.png")
	await _key(KEY_ESCAPE)
	await _mouse_move(game, router.origin)
	await _key(KEY_Q)
	var router_copy: Variant = tools.place_config
	_expect(tools.place_def == router.def and router_copy is Dictionary and int((router_copy as Dictionary).get("out", -1)) == GameConst.Dir.DOWN,
		"пипетка копирует приоритеты маршрутизатора")
	await _key(KEY_ESCAPE)
	world.configure(router, null)

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


## Кнопки с текстом text внутри node (в порядке обхода).
func _find_buttons_with_text(node: Node, text: String) -> Array[Button]:
	var result: Array[Button] = []
	if node == null:
		return result
	for child in node.get_children():
		if child is Button and (child as Button).text == text:
			result.append(child as Button)
		result.append_array(_find_buttons_with_text(child, text))
	return result


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
			if found.x > 0 and Registry.ores[found.x - 1].id == &"hematite" and found.y > best_tiles:
				best = origin
				best_tiles = found.y
	return best


## Любой тайл месторождения ore_id рядом с center (без проверки, может ли дрон его добывать).
func _find_any_ore_tile(world: GameWorld, ore_id: StringName, center: Vector2i, radius: int) -> Vector2i:
	for r in radius:
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if not world.grid.in_bounds(x, y):
					continue
				var ore := world.grid.get_ore_def(x, y)
				if ore != null and ore.id == ore_id:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Тайл воды под насос, западнее которого свободно под 5 труб, бойлер и паровой генератор (и место под сборщик ниже).
func _find_steam_spot(world: GameWorld, center: Vector2i, radius: int) -> Vector2i:
	var bm := world.buildings
	var pump := Registry.get_building(&"pump")
	for r in radius:
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != r:
					continue
				var tile := Vector2i(x, y)
				if not world.grid.in_bounds_v(tile) or bm.check_place(pump, tile, 0) != BuildingManager.Check.OK:
					continue
				if _rect_clear(world, Rect2i(tile + Vector2i(-12, 0), Vector2i(12, 7))):
					return tile
	return Vector2i(-1, -1)


func _rect_clear(world: GameWorld, rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not world.grid.in_bounds(x, y) or not world.grid.is_buildable(x, y) or world.buildings.get_at(Vector2i(x, y)) != null:
				return false
			var ore := world.grid.get_ore_def(x, y)
			if ore != null and ore.fluid != null:
				return false
	return true


## Свободный тайл воды рядом с center.
func _find_free_water(world: GameWorld, center: Vector2i, radius: int) -> Vector2i:
	for r in radius:
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if not world.grid.in_bounds(x, y) or world.buildings.get_at(Vector2i(x, y)) != null:
					continue
				var ore := world.grid.get_ore_def(x, y)
				if ore != null and ore.fluid != null:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Лифт: кликом на площадке шлюза, пара появляется на подземном этаже, дрон проходит по F.
func _run_lift(game: Game) -> void:
	var run := game.run
	var planet := run.planet
	var tools := game.tools
	var lift_def := Registry.get_building(&"lift")
	var gate := run.get_gateway(planet)
	await _drone_to(game, gate.origin + Vector2i(1, 5))
	var spot := Vector2i(-1, -1)
	for dy in range(4, 9):
		for dx in range(-6, 6):
			var candidate := gate.origin + Vector2i(dx, dy)
			if planet.check_build(lift_def, candidate, 0) == BuildingManager.Check.NO_ITEM:
				spot = candidate
				break
		if spot.x >= 0:
			break
	_expect(spot.x >= 0, "на площадке есть место для лифта")
	if spot.x < 0:
		return
	run.drone.inventory.add(lift_def.item.index, 1)
	tools.select_building(lift_def)
	await _mouse_move(game, spot)
	await _mouse_button(game, spot, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(game, spot, MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	var lift := planet.buildings.get_at(spot) as Lift
	_expect(lift != null and lift.pair != null and lift.pair.world == run.base, "лифт поставлен кликом, пара — на подземном этаже")
	if lift == null or lift.pair == null:
		return
	await _drone_to(game, spot)
	await _frames(3)
	await _shot("f01_lift_pad.png")
	await _key(KEY_F)
	await _frames(5)
	_expect(game.world == run.base and lift.pair.get_world_rect().has_point(run.drone.position), "F над лифтом — дрон на подземном этаже у пары")
	await _shot("f02_lift_underground.png")
	await _key(KEY_F)
	await _frames(5)
	_expect(game.world == run.planet, "F над парой — обратно на площадку")


## После телепорта: «Расширение площадки I» — площадка 24×24, рамка и платформа перерисованы.
func _run_pad_expansion(game: Game) -> void:
	var run := game.run
	var before := run.planet.pad_rect
	run.research.done[&"pad_1"] = true
	run.apply_research_effects()
	await _frames(10)
	_expect(run.planet.pad_rect.size == before.size + Vector2i(4, 4) and run.planet.pad_rect.encloses(before), "расширение площадки: %s → %s" % [before.size, run.planet.pad_rect.size])
	await _drone_to(game, GameConst.world_to_tile(run.get_gateway(run.planet).get_world_center()))
	game.camera.focus_on(run.drone.position, 0.6)
	await _frames(10)
	await _shot("t06_pad_expanded.png")
	game.camera.recenter()


## Протягивание: лента через стены (мост) и поперёк другой ленты (перекрёсток), опоры через 7 тайлов.
func _run_build_helpers(game: Game, base: Vector2i) -> void:
	var world := game.world
	var bm := world.buildings
	var tools := game.tools
	var inv := world.drone.inventory
	var spot := _find_clear_rect(world, Vector2i(17, 7), base + Vector2i(-8, -14), 24)
	_expect(spot.x >= 0, "есть место под протягивание через препятствия")
	if spot.x < 0:
		return
	var conveyor := Registry.get_building(&"conveyor")
	var y := spot.y + 2
	bm.place(Registry.get_building(&"stone_wall"), Vector2i(spot.x + 5, y), 0, true)
	bm.place(Registry.get_building(&"stone_wall"), Vector2i(spot.x + 6, y), 0, true)
	for dy in [-1, 0, 1]:
		bm.place(conveyor, Vector2i(spot.x + 10, y + dy), GameConst.Dir.DOWN, true)
	inv.add(conveyor.item.index, 20)
	inv.add(Registry.get_building(&"bridge_conveyor").item.index, 2)
	inv.add(Registry.get_building(&"junction").item.index, 1)
	await _drone_to(game, Vector2i(spot.x + 8, y + 2))
	game.camera.focus_on(Vector2(Vector2i(spot.x + 8, y + 1) * GameConst.TILE_SIZE), 1.2)
	await _frames(3)
	tools.select_building(conveyor)
	var a := Vector2i(spot.x + 1, y)
	var b := Vector2i(spot.x + 14, y)
	await _mouse_move(game, a)
	await _mouse_button(game, a, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, a + Vector2i(1, 0))
	await _mouse_move(game, b)
	await _frames(3)
	await _shot("i07_belt_obstacles_preview.png")
	await _mouse_button(game, b, MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	var entry := bm.get_at(Vector2i(spot.x + 4, y)) as BridgeConveyor
	var exit := bm.get_at(Vector2i(spot.x + 7, y)) as BridgeConveyor
	_expect(entry != null and exit != null and entry.get_link_target() == exit, "лента перепрыгнула стены мостом")
	_expect(bm.get_at(Vector2i(spot.x + 5, y)).def.id == &"stone_wall" and bm.get_at(Vector2i(spot.x + 10, y)) is Junction,
		"стены целы, поперечная лента стала перекрёстком")
	await _frames(5)
	await _shot("i07b_belt_obstacles.png")

	# Опоры протягиванием: через 7 тайлов, провода прямые.
	var pole_def := Registry.get_building(&"small_power_pole")
	inv.add(pole_def.item.index, 3)
	tools.select_building(pole_def)
	var p0 := Vector2i(spot.x + 1, spot.y + 5)
	var p1 := Vector2i(spot.x + 15, spot.y + 5)
	await _mouse_move(game, p0)
	await _mouse_button(game, p0, MOUSE_BUTTON_LEFT, true)
	await _mouse_move(game, p0 + Vector2i(1, 0))
	await _mouse_move(game, p1)
	await _frames(3)
	await _mouse_button(game, p1, MOUSE_BUTTON_LEFT, false)
	await _key(KEY_ESCAPE)
	var poles: Array[PowerPole] = []
	for dx in [1, 8, 15]:
		poles.append(bm.get_at(Vector2i(spot.x + dx, spot.y + 5)) as PowerPole)
	_expect(poles[0] != null and poles[1] != null and poles[2] != null and bm.get_at(Vector2i(spot.x + 2, spot.y + 5)) == null,
		"протягивание ставит опоры через 7 тайлов")
	_expect(poles[1] != null and poles[0].is_linked(poles[1]) and poles[1].is_linked(poles[2]), "протянутые опоры связаны проводами")
	await _frames(5)
	await _shot("i08_pole_drag.png")
	await _drone_to(game, base)


## Питание для построек сценария: термогенераторы с углём (по мощности) и опоры от них к каждому потребителю.
func _power_up(world: GameWorld, consumers: Array) -> void:
	var bm := world.buildings
	var gen_def := Registry.get_building(&"thermal_generator") as GeneratorDef
	var coal := Registry.get_item(&"coal").index
	var first := consumers[0] as Building
	var demand := 0.0
	for c: Building in consumers:
		demand += c.def.power_use
	var generators: Array[Building] = []
	var near := first.origin + Vector2i(-3, -3)
	for i in ceili(demand / gen_def.max_output):
		var spot := _find_clear_rect(world, Vector2i(2, 2), near, 12)
		if spot.x < 0:
			break
		var gen := bm.place(gen_def, spot, 0, true)
		while gen.accept_item(null, coal):
			gen.handle_item(null, coal)
		generators.append(gen)
		near = spot
	if generators.is_empty():
		return
	var all: Array = []
	all.append_array(generators)
	all.append_array(consumers)
	for b: Building in all:
		if b != generators[0] and not _is_covered(world, b):
			_wire(world, generators[0], b)


func _is_covered(world: GameWorld, b: Building) -> bool:
	for id in world.power.poles:
		if world.power.poles[id].get_supply_rect().intersects(b.get_rect()):
			return true
	return false


## Опоры цепочкой от постройки a к постройке b: первая — в зоне a, последняя — в зоне b, соседние в радиусе провода.
func _wire(world: GameWorld, a: Building, b: Building) -> void:
	var bm := world.buildings
	var pole_def := Registry.get_building(&"small_power_pole")
	var from := a.get_rect().get_center()
	var to := b.get_rect().get_center()
	var steps := maxi(1, ceili(Vector2(to - from).length() / 5.0))
	var prev := Vector2i(-1, -1)
	for i in steps + 1:
		var target := Vector2i(Vector2(from).lerp(Vector2(to), float(i) / steps).round())
		var must := a.get_rect().grow(2) if i == 0 else (b.get_rect().grow(2) if i == steps else Rect2i())
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for y in range(target.y - 3, target.y + 4):
			for x in range(target.x - 3, target.x + 4):
				var tile := Vector2i(x, y)
				if must.size != Vector2i.ZERO and not must.has_point(tile):
					continue
				if prev.x >= 0 and Vector2(tile - prev).length() > 7.0:
					continue
				if bm.check_place(pole_def, tile, 0) != BuildingManager.Check.OK:
					continue
				var distance := Vector2(tile - target).length()
				if distance < best_distance:
					best = tile
					best_distance = distance
		if best.x < 0:
			continue
		var pole := bm.place(pole_def, best, 0, true) as PowerPole
		world.power.auto_link(pole)
		prev = best


## Ждать, пока очередь крафта дрона опустеет.
func _wait_craft(world: GameWorld) -> void:
	var guard := 0
	while not world.drone.crafting.is_empty() and guard < 4000:
		await get_tree().process_frame
		guard += 1


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
