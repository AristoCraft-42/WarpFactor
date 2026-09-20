extends Node
## Тестовый прогон (запускается как сцена, чтобы работали автозагрузки):
## 1) компиляция всех скриптов и шейдеров; 2) логические тесты модели.
## Запуск: godot --headless --path D:/Mind res://tests/test_runner.tscn

const SKIP_DIRS := ["res://.godot", "res://addons"]
const SKIP_FILES := ["res://tools/build_test_levels.gd"]
const Worlds := preload("res://tests/support/test_worlds.gd")

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	_compile_all()
	_test_registry()
	_test_line_planner()
	_test_input_codes()
	_test_level_io_roundtrip()
	_test_levels_load()
	_test_building_manager()
	_test_settings_entries()
	_test_conveyor_flow()
	_test_conveyor_blocking_and_sleep()
	_test_conveyor_rules()
	_test_drill_to_storage()
	_test_build_from_inventory()
	_test_inventory()
	_test_hand_crafting()
	_test_drone_mining()
	_test_player_transfer()
	_test_storage_blocking()
	_test_rotation()
	_test_determinism()
	_test_junction()
	_test_router()
	_test_sorters()
	_test_router_priorities()
	_test_bridge()
	_test_unloader()
	_test_pass_through_chains()
	_test_wake_through_pass_through()
	_test_config_copy_and_contents()
	_test_recipes_data()
	_test_furnace()
	_test_output_blocked()
	_test_assembler_power()
	_test_crafter_contents()
	_test_config_wakes_blocked_belts()
	_test_logistics_throughput()
	_test_unloader_from_buildings()
	_test_inversion_config()
	_test_run_gateway()
	_test_router_returns_items()
	_test_router_junction_chain()
	_test_unloader_balancing()
	_test_gateway_rotation()
	_test_star_map()
	_test_planet_generator()
	_test_building_state_roundtrip()
	_test_teleport()
	_test_save_roundtrip_and_determinism()
	_test_save_remap()
	_test_save_files()
	_test_enemy_data()
	_test_building_damage()
	_test_flow_field()
	_test_enemy_attack()
	_test_threat_schedule()
	_test_spawn_points()
	_test_drone_death_and_crate()
	_test_breach_teleport()
	_test_enemy_save_determinism()
	_test_defense_data()
	_test_turret_ammo()
	_test_turret_kills()
	_test_artillery()
	_test_drone_gun_and_repair()
	_test_walls_route()
	_test_power_network()
	_test_fluids()
	_test_research()
	_test_ammo_effects()
	_test_research_tree()
	_test_water_placement()
	_test_belt_drag_obstacles()
	_test_drill_front_output()
	_test_underground_pipes()
	_test_pole_drag_and_camera()
	_test_building_windows()
	_test_research_effects_and_floors()
	_test_gateway_ports()
	_test_accumulator()
	_test_power_and_fluids_between_floors()
	_test_lift()
	_test_coal_drill()
	_test_drone_upgrades()
	_test_research_queue()
	_test_pipe_dragging()
	_test_creative_blocks()
	_test_gateway_growth()
	_test_quick_transfer()
	_test_pipe_layer()
	_test_creative_research()
	_test_players()
	_test_commands()
	_test_command_order()
	_test_command_determinism()
	_test_net_join()
	_test_net_play()
	_test_net_desync_repair()
	_test_net_leave()
	_test_steam_transport()
	_test_steam_big_packet()
	_test_steam_session()
	_test_clock_waiting()
	_test_clock_scale()
	_test_net_join_pending_tick()
	_test_net_catch_up()
	_test_net_lost_client()
	_test_snapshot_determinism()
	_test_net_lost_tick()
	_test_net_lost_player_add()
	_test_net_input_delay()
	_test_power_window()
	print("=== Проверок: %d, провалов: %d ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Компиляция ---

func _compile_all() -> void:
	var files := PackedStringArray()
	_collect("res://", files)
	for path in files:
		if path in SKIP_FILES:
			continue
		var res := ResourceLoader.load(path)
		_check(res != null, "не загружается " + path)
		if res is GDScript:
			_check((res as GDScript).can_instantiate() or (res as GDScript).get_instance_base_type() != &"", "не компилируется " + path)
	print("Скриптов и шейдеров: %d" % files.size())


func _collect(dir: String, out: PackedStringArray) -> void:
	for skip in SKIP_DIRS:
		if dir.begins_with(skip):
			return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		if file.ends_with(".gd") or file.ends_with(".gdshader"):
			out.append(dir.path_join(file))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)


# --- Реестр ---

func _test_registry() -> void:
	Registry.ensure_loaded()
	_check(Registry.ores.size() == 5, "ожидалось 5 месторождений, есть %d" % Registry.ores.size())
	_check(Registry.floors.size() >= 4, "мало типов пола")
	_check(Registry.buildings.size() == 30, "ожидалось 30 зданий (24 обычных, 4 творческих, шлюз и пара), есть %d" % Registry.buildings.size())
	_check(Registry.fluids.size() == 2 and Registry.get_fluid(&"water") != null and Registry.get_fluid(&"steam") != null, "жидкости: вода и пар")
	_check(Registry.recipes.size() == 13 and Registry.researches.size() == 42,
		"13 рецептов и 42 исследования (%d / %d)" % [Registry.recipes.size(), Registry.researches.size()])
	_check(Registry.base_def != null and Registry.base_def.size == 46 and Registry.base_def.start_size == 16 and Registry.base_def.size_step == 6,
		"параметры подземного этажа загружены (16 → 46 шагами по 6)")
	_check(Registry.planet_types.size() == 2 and Registry.run_def != null and Registry.run_def.first_planet_type != null, "типы планет и параметры забега загружены")
	_check(Registry.items.size() == 17 + 28, "ожидалось 17 предметов и 28 предметов-построек, есть %d" % Registry.items.size())
	for id in [&"overflow_gate", &"underflow_gate", &"inverted_sorter", &"artillery", &"titanium_conveyor", &"vault"]:
		_check(Registry.get_building(id) == null, "постройки %s в ранней игре нет" % id)
	for def in Registry.buildings:
		if def is LogisticDef:
			_check((def as LogisticDef).throughput_of != null, "у %s задана пропускная способность" % def.id)
	_check(Registry.levels.size() >= 2, "ожидалось не меньше 2 уровней")
	_check(Registry.validate().is_empty(), "ошибки валидации: %s" % ", ".join(Registry.validate()))
	_check(Registry.stack_sizes.size() == Registry.items.size(), "таблица размеров стака")
	_check(Registry.drone_def != null and Registry.drone_def.inventory_slots > 0, "параметры дрона загружены")
	for i in Registry.items.size():
		_check(Registry.items[i].index == i, "индекс предмета не совпадает")
	for def in Registry.buildings:
		if def.player_buildable and not def.creative_only:
			_check(def.item != null and def.item.building == def, "у здания %s есть предмет-постройка" % def.id)
			_check(def.item != null and Registry.get_hand_recipe(def.item.index) != null, "у здания %s есть рецепт крафта" % def.id)
	for category in 4:
		_check(not Registry.buildings_in_category(category as BuildingDef.Category).is_empty(), "пустая категория %d" % category)
	for id in [&"gear", &"copper_cable", &"science_kit", &"resistor", &"casing_mg", &"cartridge_coal"]:
		_check(Registry.get_hand_recipe(_item(id)) != null, "компонент %s крафтится руками" % id)
	for id in [&"iron_ingot", &"brick", &"copper_ingot"]:
		_check(Registry.get_hand_recipe(_item(id)) == null, "%s — только переплавкой в печи" % id)
	_check(Registry.get_item(&"coal").is_fuel() and Registry.get_item(&"science_kit").science_tier == 1, "уголь — топливо, научный набор — первого уровня")
	_check(Registry.get_ore(&"water").fluid != null and Registry.get_ore(&"water").item == null, "вода — месторождение жидкости")
	# Все плейсхолдеры строятся без ошибок.
	ArtRegistry.ensure_built()
	_check(ArtRegistry.terrain_tileset != null, "не построен TileSet")
	for def in Registry.buildings:
		var tex := ArtRegistry.get_building_texture(def)
		_check(tex != null and tex.get_width() == def.size * GameConst.TILE_SIZE, "текстура здания %s" % def.id)
	for item in Registry.items:
		_check(ArtRegistry.get_item_icon(item) != null, "иконка предмета %s" % item.id)
	_check(ArtRegistry.item_atlas.get_width() == Registry.items.size() * GameConst.TILE_SIZE, "атлас предметов включает постройки")


# --- Геометрия протягивания ---

func _test_line_planner() -> void:
	var path := LinePlanner.l_path(Vector2i(0, 0), Vector2i(3, 2), true, 0)
	_check(path.size() == 6, "L-путь: ожидалось 6 тайлов, получено %d" % path.size())
	_check(path[0] == Vector3i(0, 0, GameConst.Dir.RIGHT), "L-путь: первый шаг вправо")
	_check(path[3] == Vector3i(3, 0, GameConst.Dir.DOWN), "L-путь: угол поворачивает вниз")
	_check(path[5] == Vector3i(3, 2, GameConst.Dir.DOWN), "L-путь: последний сохраняет направление")
	var single := LinePlanner.l_path(Vector2i(5, 5), Vector2i(5, 5), true, GameConst.Dir.UP)
	_check(single.size() == 1 and single[0].z == GameConst.Dir.UP, "L-путь из одного тайла берёт текущий поворот")
	var row := LinePlanner.straight_line(Vector2i(0, 0), Vector2i(7, 1), 2)
	_check(row.size() == 4 and row[3] == Vector2i(6, 0), "прямой ряд с шагом 2")
	_check(GameConst.origin_for_size(Vector2(48, 48), 1) == Vector2i(1, 1), "origin 1x1")
	_check(GameConst.origin_for_size(Vector2(48, 48), 3) == Vector2i(0, 0), "origin 3x3 центрируется")
	_check(GameConst.origin_for_size(Vector2(40, 40), 2) == Vector2i(0, 0), "origin 2x2 к ближайшему узлу")
	_check(GameConst.origin_for_size(Vector2(56, 56), 2) == Vector2i(1, 1), "origin 2x2 к ближайшему узлу (2)")


# --- Коды привязок ---

func _test_input_codes() -> void:
	for code in ["key:W", "key:Shift", "key:Ctrl+S", "key:F3", "mouse:1", "mouse:5"]:
		var event := InputActions.decode(code)
		_check(event != null, "decode " + code)
		if event != null:
			_check(InputActions.encode(event) == code, "roundtrip %s -> %s" % [code, InputActions.encode(event)])
	_check(InputActions.decode("key:") == null, "пустой код клавиши")
	_check(InputMap.has_action(&"build_primary"), "действия зарегистрированы")


# --- Формат карт ---

func _test_level_io_roundtrip() -> void:
	var map := LevelMap.new(40, 30, Registry.get_floor(&"stone").index)
	map.set_floor(3, 4, Registry.get_floor(&"rock").index)
	map.set_ore(10, 12, Registry.get_ore(&"malachite").index + 1)
	map.add_placement(Registry.get_building(&"container"), Vector2i(18, 13))
	map.add_placement(Registry.get_building(&"conveyor"), Vector2i(2, 2), 3)
	var path := "user://test_roundtrip.fwmap"
	_check(LevelIO.save_map(map, path) == OK, "сохранение карты")
	var loaded := LevelIO.load_map(path)
	_check(loaded != null, "загрузка карты")
	if loaded == null:
		return
	_check(loaded.width == 40 and loaded.height == 30, "размер карты")
	_check(loaded.floors == map.floors, "слой пола совпадает")
	_check(loaded.ores == map.ores, "слой руды совпадает")
	_check(loaded.placements.size() == 2, "здания карты")
	_check(loaded.placements[1].rotation == 3 and loaded.placements[1].origin == Vector2i(2, 2), "поворот и позиция здания")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(LevelIO.load_map("res://icon.svg") == null, "чужой файл отклоняется")


func _test_levels_load() -> void:
	for level in Registry.levels:
		var map := LevelIO.load_map(level.map_path)
		_check(map != null, "уровень %s загружается" % level.id)
		if map == null:
			continue
		var world := GameWorld.create(level, map, false)
		var tile := world.drone.get_tile()
		_check(world.grid.in_bounds_v(tile) and world.grid.is_buildable(tile.x, tile.y), "дрон уровня %s появляется на строимом месте" % level.id)
		for stack in level.starting_items:
			_check(world.drone.inventory.count(stack.item.index) == stack.amount,
				"уровень %s: стартовый инвентарь содержит %s" % [level.id, stack.item.id])
		world.dispose()
		var run := Run.create(level, map, false)
		_check(run.get_gateway(run.planet) != null and run.is_over_gateway(), "уровень %s: шлюз на месте посадки, дрон над ним" % level.id)
		_check(Rect2i(0, 0, map.width, map.height).encloses(run.planet.pad_rect), "уровень %s: площадка внутри карты" % level.id)
		run.dispose()


# --- Размещение и снос ---

func _test_building_manager() -> void:
	var map := LevelMap.new(64, 64, Registry.get_floor(&"stone").index)
	for y in 64:
		map.set_floor(20, y, Registry.get_floor(&"rock").index)
	var copper := Registry.get_ore(&"hematite").index + 1
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6), Vector2i(18, 5)]:
		map.set_ore(p.x, p.y, copper)
	var fixed := BuildingDef.new()
	fixed.id = &"test_fixed"
	fixed.size = 3
	fixed.removable = false
	map.add_placement(fixed, Vector2i(40, 40))
	var world := GameWorld.create(null, map, false)
	var bm := world.buildings
	var conveyor := Registry.get_building(&"conveyor")
	var drill := Registry.get_building(&"drill")
	var vault := Registry.get_building(&"container")

	_check(bm.get_count() == 1, "неудаляемое здание поставлено картой")
	_check(bm.check_place(drill, Vector2i(5, 5), 0) == BuildingManager.Check.OK, "бур на свободном месте")
	var d := bm.place(drill, Vector2i(5, 5), 0)
	_check(d != null and bm.get_at(Vector2i(6, 6)) == d, "бур занимает 2x2")
	_check(bm.check_place(drill, Vector2i(6, 6), 0) == BuildingManager.Check.OCCUPIED, "пересечение запрещено")
	_check(bm.check_place(drill, Vector2i(19, 5), 0) == BuildingManager.Check.BAD_TERRAIN, "скала запрещена")
	_check(bm.check_place(vault, Vector2i(64, 10), 0) == BuildingManager.Check.OUT_OF_BOUNDS, "выход за карту")
	_check(bm.check_place(drill, Vector2i(5, 5), 0) == BuildingManager.Check.SAME, "то же здание на том же месте")
	_check(bm.check_place(drill, Vector2i(10, 20), 0) == BuildingManager.Check.NO_ORE, "бур без руды запрещён")
	_check(bm.check_place(drill, Vector2i(17, 4), 0) == BuildingManager.Check.OK, "буру достаточно одного тайла руды")

	var c := bm.place(conveyor, Vector2i(10, 10), 0)
	_check(bm.check_place(conveyor, Vector2i(10, 10), 2) == BuildingManager.Check.REPLACE, "поворот ленты — замена")
	var c2 := bm.place(conveyor, Vector2i(10, 10), 2)
	_check(c2 != null and c2.rotation == 2 and c.id == 0, "замена ставит новую ленту и убирает старую")
	_check(bm.place(conveyor, Vector2i(10, 10), 2) == null, "повторная установка того же — ничего")
	var upgrade := Registry.get_building(&"junction")
	_check(bm.check_place(upgrade, Vector2i(10, 10), 2) == BuildingManager.Check.REPLACE, "другое здание того же размера — замена")

	var fixed_building := bm.get_at(Vector2i(40, 40))
	_check(not bm.remove(fixed_building), "неудаляемое здание не сносится")
	var in_rect := bm.collect_in_rect(Rect2i(0, 0, 64, 64))
	_check(in_rect.size() == 3, "в рамке 3 здания (бур, лента, неудаляемое), найдено %d" % in_rect.size())
	var partial := bm.collect_in_rect(Rect2i(6, 6, 1, 1))
	_check(partial.size() == 1 and partial[0] == d, "рамка ловит здание за любой его тайл")
	var edge := bm.collect_in_rect(Rect2i(42, 42, 1, 1))
	_check(edge.size() == 1 and edge[0] == fixed_building, "рамка в правом нижнем тайле здания 3x3")

	# Здание на границе чанков (32) и повторное использование id.
	var cross := bm.place(Registry.get_building(&"furnace"), Vector2i(31, 31), 0)
	_check(cross != null, "здание 2×2 на стыке чанков")
	_check(bm.collect_in_rect(Rect2i(32, 32, 1, 1)).has(cross), "поиск в соседнем чанке")
	var old_id := cross.id
	_check(bm.remove(cross), "снос здания со стыка")
	_check(bm.get_at(Vector2i(32, 32)) == null, "тайлы освобождены")
	var reused := bm.place(conveyor, Vector2i(50, 5), 1)
	_check(reused.id == old_id, "id переиспользуется")
	world.dispose()


func _test_settings_entries() -> void:
	var keys := {}
	for e in Settings.entries:
		_check(not keys.has(e.key), "повтор настройки " + e.key)
		keys[e.key] = true
		_check(SettingEntry.same_value(e.sanitize(e.default_value), e.default_value), "значение по умолчанию допустимо: " + e.key)
	var vsync := Settings.get_entry(&"graphics/vsync")
	_check(vsync.sanitize("мусор") == vsync.default_value, "неверное значение заменяется")
	_check(SettingEntry.same_value(Settings.get_entry(&"game/ui_scale").sanitize(10.0), 2.0), "диапазон ограничивается")


# --- Симуляция лент ---

## Источник → 10 лент → приёмник: пропускная способность и отсутствие потерь.
func _test_conveyor_flow() -> void:
	var world := Worlds.empty_world(40, 16)
	var source := world.buildings.place(Worlds.source_def(), Vector2i(2, 5), 0, true)
	Worlds.conveyor_line(world, Vector2i(3, 5), 10, GameConst.Dir.RIGHT)
	var sink := world.buildings.place(Worlds.sink_def(), Vector2i(13, 5), 0, true)
	Worlds.run_ticks(world, 600)
	var delivered_before: int = sink.received
	Worlds.run_ticks(world, 300)
	var rate: float = (sink.received - delivered_before) / 10.0
	var expected := (Registry.get_building(&"conveyor") as ConveyorDef).get_items_per_second()
	_check(absf(rate - expected) <= expected * 0.12, "пропускная способность ленты %.2f предм./с (ожидалось ~%.2f)" % [rate, expected])
	var on_belts := world.simulation.conveyors.get_item_count()
	_check(source.produced == sink.received + on_belts, "предметы не теряются: создано %d, доставлено %d, на лентах %d" % [source.produced, sink.received, on_belts])
	# Интервал между предметами не меньше ITEM_SPACE.
	var sys := world.simulation.conveyors
	var ok_spacing := true
	for c in sys.count:
		for s in range(1, sys.counts[c]):
			if sys.prog[c * ConveyorSystem.CAP + s - 1] - sys.prog[c * ConveyorSystem.CAP + s] < ConveyorSystem.SPACE:
				ok_spacing = false
	_check(ok_spacing, "между предметами соблюдается зазор")
	world.dispose()


## Без получателя лента забивается и засыпает; появление приёмника всё будит.
func _test_conveyor_blocking_and_sleep() -> void:
	var world := Worlds.empty_world(40, 16)
	world.buildings.place(Worlds.source_def(), Vector2i(2, 5), 0, true)
	Worlds.conveyor_line(world, Vector2i(3, 5), 10, GameConst.Dir.RIGHT)
	Worlds.run_ticks(world, 900)
	var sys := world.simulation.conveyors
	var capacity := 10 * ConveyorSystem.UNITS / ConveyorSystem.SPACE + 1
	_check(sys.get_item_count() == capacity, "забитая линия из 10 тайлов вмещает %d предметов (%d)" % [capacity, sys.get_item_count()])
	Worlds.run_ticks(world, 5)
	_check(sys.get_awake_count() == 0, "забитые ленты спят (бодрствуют: %d)" % sys.get_awake_count())
	_check(world.simulation.get_awake_building_count() == 0, "источник спит, когда отдать некуда")
	var sink := world.buildings.place(Worlds.sink_def(), Vector2i(13, 5), 0, true)
	Worlds.run_ticks(world, 300)
	_check(sink.received > 30, "после появления приёмника поток возобновился (%d)" % sink.received)
	world.dispose()


func _test_conveyor_rules() -> void:
	var world := Worlds.empty_world(40, 20)
	var sys := world.simulation.conveyors
	var conveyor := Registry.get_building(&"conveyor")
	# Встречные ленты не передают друг другу.
	world.buildings.place(Worlds.source_def(), Vector2i(2, 2), 0, true)
	world.buildings.place(conveyor, Vector2i(3, 2), GameConst.Dir.RIGHT, true)
	var facing := world.buildings.place(conveyor, Vector2i(4, 2), GameConst.Dir.LEFT, true)
	Worlds.run_ticks(world, 200)
	_check(sys.counts[sys.index_of(facing.id)] == 0, "встречная лента ничего не получает")

	# Вставка сбоку: вертикальная лента вливается в середину горизонтальной линии.
	world.buildings.place(Worlds.source_def(), Vector2i(2, 10), 0, true)
	Worlds.conveyor_line(world, Vector2i(3, 10), 8, GameConst.Dir.RIGHT)
	var sink := world.buildings.place(Worlds.sink_def(), Vector2i(11, 10), 0, true)
	world.buildings.place(Worlds.source_def(), Vector2i(6, 6), 0, true)
	Worlds.conveyor_line(world, Vector2i(6, 7), 3, GameConst.Dir.DOWN)
	Worlds.run_ticks(world, 900)
	var side_line := sys.index_of(world.buildings.get_at(Vector2i(6, 9)).id)
	_check(sink.received > 100, "в линию с боковым притоком доставлено %d" % sink.received)
	_check(sys.next_side[side_line] == 1, "боковая лента подключена сбоку")
	# Лента, упирающаяся в пустоту, держит предметы на краю.
	var dead_end := world.buildings.place(conveyor, Vector2i(20, 15), GameConst.Dir.RIGHT, true)
	world.buildings.place(Worlds.source_def(), Vector2i(19, 15), 0, true)
	Worlds.run_ticks(world, 200)
	_check(sys.counts[sys.index_of(dead_end.id)] == ConveyorSystem.CAP, "тупиковая лента заполнена")
	# Снос ленты посреди линии и замыкание на месте.
	world.buildings.remove(world.buildings.get_at(Vector2i(8, 10)), true)
	Worlds.run_ticks(world, 60)
	world.buildings.place(conveyor, Vector2i(8, 10), GameConst.Dir.RIGHT, true)
	var before: int = sink.received
	Worlds.run_ticks(world, 300)
	_check(sink.received > before, "после восстановления разрыва поток идёт снова")
	world.dispose()


## Бур на гематите от электричества → лента → склад.
func _test_drill_to_storage() -> void:
	var map := LevelMap.new(48, 20, Registry.get_floor(&"stone").index)
	var ore := Registry.get_ore(&"hematite").index + 1
	for y in range(8, 10):
		for x in range(4, 6):
			map.set_ore(x, y, ore)
	map.add_placement(Registry.get_building(&"container"), Vector2i(30, 9))
	var world := GameWorld.create(null, map, true)
	var drill: Drill = world.buildings.place(Registry.get_building(&"drill"), Vector2i(4, 8), 0, true)
	_check(drill.ore != null and drill.ore_tiles == 4, "бур нашёл 4 тайла гематита")
	var expected_ticks := roundi((6.0 + 1.5 * 1) / 4 * GameConst.TICK_RATE)
	_check(drill.ticks_per_item == expected_ticks, "время на предмет %d тиков (ожидалось %d)" % [drill.ticks_per_item, expected_ticks])
	Worlds.run_ticks(world, 120)
	_check(drill.buffer == 0 and drill.get_status() == Building.Status.NO_POWER and world.power.unconnected.has(drill), "без опоры бур не работает")
	Worlds.power_area(world, Vector2i(4, 5), 5, Vector2i(7, 6))
	Worlds.conveyor_line(world, Vector2i(6, 9), 24, GameConst.Dir.RIGHT)
	var item := Registry.get_item(&"hematite").index
	Worlds.run_ticks(world, 60 * GameConst.TICK_RATE)
	var container := world.buildings.get_at(Vector2i(30, 9)) as StorageBuilding
	var stored := container.inventory.count(item)
	var in_transit := world.simulation.conveyors.get_item_count() + drill.buffer
	var produced := 60 * GameConst.TICK_RATE / drill.ticks_per_item
	_check(stored > 0, "гематит доехал до склада (%d)" % stored)
	_check(absi(stored + in_transit - produced) <= 1, "добыто %d ≈ в складе %d + в пути %d" % [produced, stored, in_transit])
	_check(drill.power_net != null and is_equal_approx(drill.get_power_satisfaction(), 1.0), "бур в сети с полным питанием")
	world.dispose()


func _test_build_from_inventory() -> void:
	# Дрон появляется в центре карты (16, 8), радиус — 10 тайлов.
	var world := Worlds.empty_world(32, 16, false)
	var inventory := world.drone.inventory
	var conveyor := Registry.get_building(&"conveyor")
	var belt_item := conveyor.item.index
	_check(world.check_build(conveyor, Vector2i(14, 8), 0) == BuildingManager.Check.NO_ITEM, "без постройки в инвентаре лента недоступна")
	_check(world.build(conveyor, Vector2i(14, 8), 0) == null, "без постройки лента не строится")
	inventory.add(belt_item, 10)
	var budget := inventory.make_budget()
	var planned := 0
	for x in range(7, 27):
		if world.check_build(conveyor, Vector2i(x, 10), 0, budget) == BuildingManager.Check.OK:
			planned += 1
	_check(planned == 10, "бюджет протягивания хватает ровно на 10 лент (%d)" % planned)
	_check(world.check_build(conveyor, Vector2i(0, 0), 0) == BuildingManager.Check.OUT_OF_RANGE, "угол карты вне радиуса дрона")
	var built := world.build(conveyor, Vector2i(14, 8), 0)
	_check(built != null and inventory.count(belt_item) == 9, "стройка взяла ленту из инвентаря")

	# Замена поворотом при пустом запасе: старая лента возвращается и тут же ставится снова.
	inventory.remove(belt_item, 9)
	var rotated := world.build(conveyor, Vector2i(14, 8), 2)
	_check(rotated != null and rotated.rotation == 2 and inventory.count(belt_item) == 0, "замена не требует запаса и не дублирует постройку")

	# Снос возвращает постройку и содержимое.
	world.buildings.place(Worlds.source_def(), Vector2i(15, 8), 0, true)
	Worlds.run_ticks(world, 120)
	var on_belt := world.simulation.conveyors.counts[world.simulation.conveyors.index_of(rotated.id)]
	_check(on_belt > 0, "на ленте есть предметы (%d)" % on_belt)
	_check(world.demolish(rotated), "снос ленты")
	_check(inventory.count(belt_item) == 1, "лента вернулась в инвентарь")
	_check(inventory.count(0) == on_belt, "содержимое ленты в инвентаре (%d)" % inventory.count(0))

	# Далеко — нельзя снести; инвентарь полон — тоже.
	var far := world.buildings.place(conveyor, Vector2i(0, 0), 0, true)
	_check(not world.demolish(far) and world.last_error == GameWorld.ActionError.OUT_OF_RANGE, "далёкое здание не сносится")
	var near := world.build(conveyor, Vector2i(18, 8), 0)
	inventory.clear()
	var stone := Registry.get_item(&"stone").index
	inventory.add(stone, inventory.size() * Registry.stack_sizes[stone])
	_check(not world.demolish(near) and world.last_error == GameWorld.ActionError.INVENTORY_FULL, "при полном инвентаре снос запрещён")
	inventory.clear()
	_check(world.demolish(near) and inventory.count(belt_item) == 1, "после освобождения места снос проходит")

	# Творческий режим: радиус не ограничен, постройки не расходуются.
	var creative := Worlds.empty_world(32, 16, true)
	_check(creative.build(conveyor, Vector2i(0, 0), 0) != null, "в творческом режиме стройка бесплатна и без радиуса")
	_check(creative.drone.inventory.is_empty(), "творческий режим не трогает инвентарь")
	world.dispose()
	creative.dispose()


func _test_inventory() -> void:
	var copper := _item(&"hematite")
	var drill := Registry.get_building(&"drill").item.index
	var ore_stack := Registry.stack_sizes[copper]
	var drill_stack := Registry.stack_sizes[drill]
	var inv := Inventory.new(3)
	_check(inv.space_for(copper) == ore_stack * 3, "пустой инвентарь: 3 ячейки по стаку гематита")
	_check(inv.add(copper, ore_stack + ore_stack / 2) == ore_stack + ore_stack / 2 and inv.used_slots() == 2, "полторы стопки гематита занимают 2 ячейки")
	_check(inv.space_for(copper) == ore_stack + ore_stack - ore_stack / 2 and inv.space_for(drill) == drill_stack, "место считается по стакам")
	_check(inv.add(drill, drill_stack + 20) == drill_stack, "бурам хватило только одной ячейки")
	_check(inv.add(copper, ore_stack) == ore_stack - ore_stack / 2 and inv.count(copper) == ore_stack * 2, "гематит дополнил начатую стопку")
	_check(inv.remove(copper, ore_stack + 10) == ore_stack + 10 and inv.count(copper) == ore_stack - 10 and inv.used_slots() == 2, "опустевшая ячейка освободилась")
	var taken := inv.take_from_slot(2, 10)
	_check(taken == Vector2i(drill, 10) and inv.count(drill) == drill_stack - 10, "взять из конкретной ячейки")
	var budget := inv.make_budget()
	_check(budget.take(copper, ore_stack - 10) and not budget.take(copper, 1) and inv.count(copper) == ore_stack - 10, "бюджет не меняет инвентарь")

	var sorted := Inventory.new(4, true)
	sorted.add(drill, 10)
	sorted.add(copper, 30)
	sorted.add(copper, 5)
	_check(sorted.slot_items[0] == copper and sorted.slot_counts[0] == 35 and sorted.slot_items[1] == drill, "автосортировка по порядку предметов")

	# Кэш свободного места совпадает с полным пересчётом после случайных операций.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fuzz := Inventory.new(6)
	var mismatches := 0
	for i in 600:
		var item := rng.randi_range(0, Registry.items.size() - 1)
		if rng.randf() < 0.6:
			fuzz.add(item, rng.randi_range(1, 120))
		else:
			fuzz.remove(item, rng.randi_range(1, 120))
		var probe := rng.randi_range(0, Registry.items.size() - 1)
		var brute := 0
		for slot in fuzz.size():
			if fuzz.slot_items[slot] == Inventory.EMPTY:
				brute += Registry.stack_sizes[probe]
			elif fuzz.slot_items[slot] == probe:
				brute += Registry.stack_sizes[probe] - fuzz.slot_counts[slot]
		if brute != fuzz.space_for(probe):
			mismatches += 1
	_check(mismatches == 0, "кэш места совпадает с пересчётом (расхождений %d)" % mismatches)


func _test_hand_crafting() -> void:
	var world := Worlds.empty_world(32, 16, false)
	var inv := world.drone.inventory
	var queue := world.drone.crafting
	var iron := _item(&"iron_ingot")
	var gear := _item(&"gear")
	var belt := Registry.get_building(&"conveyor").item.index
	var gear_recipe := Registry.get_hand_recipe(gear)
	var belt_recipe := Registry.get_hand_recipe(belt)
	_check(gear_recipe.recipe != null and belt_recipe.building != null, "шестерня — из рецепта компонента, лента — из стоимости постройки")
	_check(queue.enqueue(gear_recipe, 1) == 0, "без железа шестерню не скрафтить")
	inv.add(iron, 5)
	_check(queue.max_craftable(gear_recipe) == 2, "железа хватает на 2 шестерни")
	_check(queue.enqueue(gear_recipe, 2) == 2 and inv.count(iron) == 1, "сырьё списано при постановке в очередь")
	Worlds.run_ticks(world, gear_recipe.ticks * 2 + 1)
	_check(inv.count(gear) == 2 and queue.is_empty(), "две шестерни скрафчены (%d)" % inv.count(gear))

	inv.add(iron, 4)
	queue.enqueue(gear_recipe, 2)
	queue.cancel(1)
	_check(inv.count(iron) == 3 and queue.units.size() == 1, "отмена возвращает сырьё")
	Worlds.run_ticks(world, 1)
	queue.cancel(0)
	_check(inv.count(iron) == 5 and queue.is_empty(), "отмена начатого крафта тоже возвращает сырьё")

	# Промежуточные детали: перекрёсток = 2 ленты + 2 железа; лента = железо + шестерня; шестерня = 2 железа.
	var junction := Registry.get_building(&"junction").item.index
	var junction_recipe := Registry.get_hand_recipe(junction)
	inv.clear()
	inv.add(iron, 5)
	_check(queue.max_craftable(junction_recipe) == 1, "с докрафтом железа хватает на перекрёсток")
	_check(queue.enqueue(junction_recipe, 1) == 1 and inv.count(iron) == 0, "железо на промежуточные детали списано")
	Worlds.run_ticks(world, gear_recipe.ticks + belt_recipe.ticks + junction_recipe.ticks + 5)
	_check(inv.count(junction) == 1 and inv.count(belt) == 0 and inv.count(gear) == 0, "перекрёсток готов, промежуточные израсходованы")
	inv.add(belt, 2)
	inv.add(iron, 2)
	_check(queue.enqueue(junction_recipe, 1) == 1 and inv.count(belt) == 0, "готовые ленты из инвентаря используются без докрафта")

	# Полный инвентарь: результат ждёт места.
	queue.cancel(0)
	inv.clear()
	inv.add(iron, 2)
	queue.enqueue(gear_recipe, 1)
	var stone := _item(&"stone")
	inv.add(stone, inv.size() * Registry.stack_sizes[stone])
	Worlds.run_ticks(world, gear_recipe.ticks + 5)
	_check(queue.blocked and queue.units.size() == 1, "крафт ждёт места в инвентаре")
	inv.remove(stone, Registry.stack_sizes[stone])
	Worlds.run_ticks(world, 2)
	_check(not queue.blocked and queue.is_empty() and inv.count(gear) == 1, "после освобождения места шестерня выдана")
	world.dispose()


func _test_drone_mining() -> void:
	var map := LevelMap.new(32, 16, Registry.get_floor(&"stone").index)
	map.set_ore(18, 8, Registry.get_ore(&"hematite").index + 1)
	map.set_ore(19, 8, Registry.get_ore(&"malachite").index + 1)
	var world := GameWorld.create(null, map, false)
	var drone := world.drone
	var inv := drone.inventory
	var copper := _item(&"hematite")
	var ticks := drone.def.mine_ticks(Registry.get_ore(&"hematite"))
	drone.set_mine_target(Vector2i(18, 8))
	Worlds.run_ticks(world, ticks * 3)
	_check(inv.count(copper) == 3, "дрон добыл 3 гематита за 3 цикла (%d)" % inv.count(copper))
	_check(drone.get_mineable_ore(Vector2i(19, 8)) == null, "малахит слишком твёрдый для дрона — только буром")
	drone.set_mine_target(Vector2i(19, 8))
	Worlds.run_ticks(world, ticks)
	_check(drone.mine_blocked and inv.count(_item(&"malachite")) == 0, "добыча малахита дроном не идёт")

	var center := drone.position
	drone.position = Vector2(48, 48)
	drone.set_mine_target(Vector2i(18, 8))
	Worlds.run_ticks(world, ticks * 2)
	_check(drone.mine_blocked and inv.count(copper) == 3, "вне радиуса добыча стоит")
	drone.position = center
	world.buildings.place(Registry.get_building(&"conveyor"), Vector2i(18, 8), 0, true)
	Worlds.run_ticks(world, ticks * 2)
	_check(drone.mine_blocked and inv.count(copper) == 3, "здание на руде мешает добыче")

	# Полёт: 8 тайлов в секунду, у края карты дрон останавливается.
	drone.stop_mining()
	drone.move_input = Vector2.RIGHT
	Worlds.run_ticks(world, GameConst.TICK_RATE)
	_check(absf(drone.position.x - center.x - drone.def.speed * GameConst.TILE_SIZE) < 1.0, "за секунду дрон пролетел %.0f px" % (drone.position.x - center.x))
	Worlds.run_ticks(world, GameConst.TICK_RATE * 10)
	_check(is_equal_approx(drone.position.x, world.grid.get_pixel_size().x), "дрон не вылетает за карту")
	world.dispose()


func _test_player_transfer() -> void:
	var world := Worlds.empty_world(32, 16, false)
	var inv := world.drone.inventory
	var hematite := _item(&"hematite")
	var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(17, 8), 0, true) as StorageBuilding
	inv.add(hematite, 150)
	_check(world.player_put(storage, hematite, 120) == 120, "положили 120 гематита в склад")
	_check(inv.count(hematite) == 30 and storage.inventory.count(hematite) == 120, "гематит перешёл в склад")
	_check(world.player_take(storage, hematite, 50) == 50 and inv.count(hematite) == 80, "забрали 50 гематита")
	var center := world.drone.position
	world.drone.position = Vector2.ZERO
	_check(world.player_take(storage, hematite, 10) == 0, "издалека не забрать")
	world.drone.position = center

	var furnace := world.buildings.place(Registry.get_building(&"furnace"), Vector2i(13, 6), 0, true) as Crafter
	var coal := _item(&"coal")
	inv.add(coal, 3)
	_check(world.player_put(furnace, coal, 3) == 3 and furnace.total_fuel() == 3, "уголь положен в печь как топливо")
	var put := world.player_put(furnace, hematite, 30)
	_check(put > 0 and put <= furnace.get_input_capacity(hematite), "гематит положен в печь до вместимости (%d)" % put)
	inv.add(_item(&"gear"), 5)
	_check(world.player_put(furnace, _item(&"gear"), 5) == 0, "печь не принимает шестерни")
	Worlds.run_ticks(world, 300)
	var iron := _item(&"iron_ingot")
	_check(furnace.outputs[iron] > 0, "печь сделала железо (%d)" % furnace.outputs[iron])
	var taken := world.player_take(furnace, iron, 100)
	_check(taken > 0 and inv.count(iron) == taken, "железо забрано руками (%d)" % taken)
	world.dispose()


## Полный склад останавливает ленту; когда игрок забирает предметы, лента просыпается.
func _test_storage_blocking() -> void:
	var world := Worlds.empty_world(32, 16, true)
	var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(10, 4), 0, true) as StorageBuilding
	var stone := _item(&"stone")
	storage.inventory.add(stone, storage.inventory.size() * Registry.stack_sizes[stone])
	world.buildings.place(Worlds.source_def(), Vector2i(4, 4), 0, true)
	Worlds.conveyor_line(world, Vector2i(5, 4), 5, GameConst.Dir.RIGHT)
	Worlds.run_ticks(world, 600)
	_check(storage.inventory.count(0) == 0 and world.simulation.conveyors.get_item_count() > 0, "полный склад не принимает предметы")
	_check(world.player_take(storage, stone, 100) == 100, "игрок освобождает ячейку")
	Worlds.run_ticks(world, 120)
	_check(storage.inventory.count(0) > 0, "лента проснулась и загружает склад (%d)" % storage.inventory.count(0))
	world.dispose()


func _test_rotation() -> void:
	var world := Worlds.empty_world(32, 16)
	world.buildings.place(Worlds.source_def(), Vector2i(4, 5), 0, true)
	var belt := world.buildings.place(Registry.get_building(&"conveyor"), Vector2i(5, 5), GameConst.Dir.UP, true)
	var sink := world.buildings.place(Worlds.sink_def(), Vector2i(6, 5), 0, true)
	Worlds.run_ticks(world, 120)
	_check(sink.received == 0, "лента вверх в приёмник справа не отдаёт")
	_check(world.rotate_building(belt, 1), "поворот ленты")
	_check(belt.rotation == GameConst.Dir.RIGHT, "лента смотрит вправо")
	Worlds.run_ticks(world, 120)
	_check(sink.received > 0, "после поворота предметы идут в приёмник (%d)" % sink.received)
	var router := world.buildings.place(Registry.get_building(&"router"), Vector2i(10, 10), 0, true)
	_check(world.rotate_building(router, 1) and router.rotation == 1, "любое здание можно повернуть")
	world.dispose()


func _test_determinism() -> void:
	var results: Array[int] = []
	for run in 2:
		var world := Worlds.empty_world(40, 16)
		world.buildings.place(Worlds.source_def(), Vector2i(2, 5), 0, true)
		Worlds.conveyor_line(world, Vector2i(3, 5), 6, GameConst.Dir.RIGHT)
		Worlds.conveyor_line(world, Vector2i(9, 5), 4, GameConst.Dir.DOWN)
		var sink := world.buildings.place(Worlds.sink_def(), Vector2i(9, 9), 0, true)
		Worlds.run_ticks(world, 777)
		results.append(sink.received)
		world.dispose()
	_check(results[0] == results[1] and results[0] > 0, "симуляция детерминирована (%s)" % str(results))


# --- Логистика (этап 3) ---

func _place(world: GameWorld, id: StringName, tile: Vector2i, rotation: int = 0) -> Building:
	return world.buildings.place(Registry.get_building(id), tile, rotation, true)


func _source(world: GameWorld, tile: Vector2i, items: Array) -> Building:
	var s := world.buildings.place(Worlds.source_def(), tile, 0, true)
	s.set("items", PackedInt32Array(items))
	return s


func _sink(world: GameWorld, tile: Vector2i) -> Building:
	return world.buildings.place(Worlds.sink_def(), tile, 0, true)


## Перекрёсток: два потока пересекаются и не смешиваются.
func _test_junction() -> void:
	var world := Worlds.empty_world(24, 24)
	var copper := Registry.get_item(&"hematite").index
	var lead := Registry.get_item(&"brick").index
	_source(world, Vector2i(2, 10), [copper])
	Worlds.conveyor_line(world, Vector2i(3, 10), 4, GameConst.Dir.RIGHT)
	_place(world, &"junction", Vector2i(7, 10))
	Worlds.conveyor_line(world, Vector2i(8, 10), 3, GameConst.Dir.RIGHT)
	var east := _sink(world, Vector2i(11, 10))
	_source(world, Vector2i(7, 5), [lead])
	Worlds.conveyor_line(world, Vector2i(7, 6), 4, GameConst.Dir.DOWN)
	Worlds.conveyor_line(world, Vector2i(7, 11), 3, GameConst.Dir.DOWN)
	var south := _sink(world, Vector2i(7, 14))
	Worlds.run_ticks(world, 900)
	_check(east.received > 50 and east.count_of(lead) == 0, "перекрёсток: восток получил только гематит (%d)" % east.received)
	_check(south.received > 50 and south.count_of(copper) == 0, "перекрёсток: юг получил только кирпичи (%d)" % south.received)
	world.dispose()


## Делитель раздаёт поток на три выхода примерно поровну.
func _test_router() -> void:
	var world := Worlds.empty_world(24, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 3, GameConst.Dir.RIGHT)
	var router := _place(world, &"router", Vector2i(6, 10))
	Worlds.conveyor_line(world, Vector2i(7, 10), 3, GameConst.Dir.RIGHT)
	Worlds.conveyor_line(world, Vector2i(6, 9), 3, GameConst.Dir.UP)
	Worlds.conveyor_line(world, Vector2i(6, 11), 3, GameConst.Dir.DOWN)
	var sinks := [_sink(world, Vector2i(10, 10)), _sink(world, Vector2i(6, 6)), _sink(world, Vector2i(6, 14))]
	Worlds.run_ticks(world, 1200)
	var total := 0
	var min_count := 1 << 30
	for s in sinks:
		total += s.received
		min_count = mini(min_count, s.received)
	_check(total > 80, "делитель пропускает поток (%d)" % total)
	_check(min_count * 3 >= total * 0.6, "делитель распределяет по всем выходам (%s)" % str(sinks.map(func(s): return s.received)))
	_check(router.get("item") == -1 or router.get("item") >= 0, "делитель в корректном состоянии")
	world.dispose()


## Сортировщик и инвертированный сортировщик.
func _test_sorters() -> void:
	for inverted in [false, true]:
		var world := Worlds.empty_world(24, 24)
		var copper := Registry.get_item(&"hematite").index
		var lead := Registry.get_item(&"brick").index
		_source(world, Vector2i(2, 10), [copper, lead])
		Worlds.conveyor_line(world, Vector2i(3, 10), 3, GameConst.Dir.RIGHT)
		var sorter := _place(world, &"sorter", Vector2i(6, 10))
		world.configure(sorter, copper)
		world.configure(sorter, inverted)
		Worlds.conveyor_line(world, Vector2i(7, 10), 2, GameConst.Dir.RIGHT)
		var forward := _sink(world, Vector2i(9, 10))
		Worlds.conveyor_line(world, Vector2i(6, 9), 2, GameConst.Dir.UP)
		var up := _sink(world, Vector2i(6, 7))
		Worlds.conveyor_line(world, Vector2i(6, 11), 2, GameConst.Dir.DOWN)
		var down := _sink(world, Vector2i(6, 13))
		Worlds.run_ticks(world, 900)
		var matched := lead if inverted else copper
		var other := copper if inverted else lead
		var name := "сортировщик с инверсией" if inverted else "сортировщик"
		_check(forward.received > 30 and forward.count_of(other) == 0, "%s: вперёд только выбранное (%d)" % [name, forward.received])
		_check(up.count_of(matched) == 0 and down.count_of(matched) == 0 and up.received > 5 and down.received > 5,
			"%s: в стороны остальное, поровну (%d / %d)" % [name, up.received, down.received])
		_check(sorter.get_display_item() == copper and sorter.is_inverted() == inverted, "%s: фильтр и инверсия сохранены" % name)
		world.dispose()


## Приоритеты маршрутизатора: выход — сначала в приоритетную сторону; вход — лента с приоритетной стороны первой.
func _test_router_priorities() -> void:
	var world := Worlds.empty_world(24, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 3, GameConst.Dir.RIGHT)
	var router := _place(world, &"router", Vector2i(6, 10)) as Router
	Worlds.conveyor_line(world, Vector2i(7, 10), 2, GameConst.Dir.RIGHT)
	var east := _sink(world, Vector2i(9, 10))
	Worlds.conveyor_line(world, Vector2i(6, 9), 2, GameConst.Dir.UP)
	var north := _sink(world, Vector2i(6, 7))
	world.configure(router, {"in": Router.NO_SIDE, "out": GameConst.Dir.UP})
	Worlds.run_ticks(world, 600)
	_check(north.received > 30 and east.received == 0, "приоритетный выход получает всё, пока принимает (%d / %d)" % [north.received, east.received])
	world.buildings.remove(north, true)
	Worlds.run_ticks(world, 600)
	_check(east.received > 20, "занятый приоритетный выход — поток уходит в другие стороны (%d)" % east.received)
	_check(world.rotate_building(router, 1) and router.world_side(router.priority_out) == GameConst.Dir.RIGHT, "поворот здания поворачивает приоритеты")
	world.dispose()

	# Приоритетный вход: запад и юг в один маршрутизатор с одним выходом, запад приоритетный.
	world = Worlds.empty_world(24, 24)
	var hematite := _item(&"hematite")
	var brick := _item(&"brick")
	var west_src := _source(world, Vector2i(2, 10), [hematite])
	Worlds.conveyor_line(world, Vector2i(3, 10), 3, GameConst.Dir.RIGHT)
	_source(world, Vector2i(6, 14), [brick])
	Worlds.conveyor_line(world, Vector2i(6, 13), 3, GameConst.Dir.UP)
	var merge := _place(world, &"router", Vector2i(6, 10)) as Router
	Worlds.conveyor_line(world, Vector2i(7, 10), 2, GameConst.Dir.RIGHT)
	var out := _sink(world, Vector2i(9, 10))
	world.configure(merge, {"in": GameConst.Dir.LEFT, "out": GameConst.Dir.RIGHT})
	Worlds.run_ticks(world, 900)
	_check(out.count_of(hematite) > 30 and out.count_of(brick) == 0, "пока приоритетный вход подаёт, остальные ждут (%d / %d)" % [out.count_of(hematite), out.count_of(brick)])
	world.buildings.remove(west_src, true)
	Worlds.run_ticks(world, 900)
	_check(out.count_of(brick) > 20, "приоритетный вход опустел — идут остальные (%d)" % out.count_of(brick))
	world.dispose()


## Мост переносит предметы над препятствием; связь проверяется по дальности и оси.
func _test_bridge() -> void:
	var world := Worlds.empty_world(32, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 2, GameConst.Dir.RIGHT)
	var a: BridgeConveyor = _place(world, &"bridge_conveyor", Vector2i(5, 10))
	# Препятствие из лент поперёк пути.
	Worlds.conveyor_line(world, Vector2i(6, 6), 9, GameConst.Dir.DOWN)
	Worlds.conveyor_line(world, Vector2i(7, 6), 9, GameConst.Dir.DOWN)
	Worlds.conveyor_line(world, Vector2i(8, 6), 9, GameConst.Dir.DOWN)
	var b: BridgeConveyor = _place(world, &"bridge_conveyor", Vector2i(9, 10))
	var sink := _sink(world, Vector2i(10, 10))
	var far: BridgeConveyor = _place(world, &"bridge_conveyor", Vector2i(15, 10))
	var diagonal: BridgeConveyor = _place(world, &"bridge_conveyor", Vector2i(7, 18))
	_check(a.can_link_to(b), "мост связывается в пределах 4 тайлов")
	_check(not b.can_link_to(far), "мост не связывается дальше дальности")
	_check(not a.can_link_to(diagonal), "мост не связывается по диагонали")
	world.configure(a, b.origin - a.origin)
	_check(a.get_link_target() == b, "связь моста установлена")
	Worlds.run_ticks(world, 900)
	_check(sink.received > 50, "мост доставил предметы над препятствием (%d)" % sink.received)
	# Встречная связь заменяет прежнюю, петли нет.
	world.configure(b, a.origin - b.origin)
	_check(a.get_link_target() == null and b.get_link_target() == a, "встречная связь снимает прежнюю")
	# Снос конечного моста разрывает связь.
	world.configure(a, b.origin - a.origin)
	world.buildings.remove(b, true)
	_check(a.get_link_target() == null, "снос моста разрывает связь")
	world.dispose()


## Разгрузчик берёт из ядра по фильтру; изъятое вычитается из доставки.
func _test_unloader() -> void:
	var map := LevelMap.new(32, 24, Registry.get_floor(&"stone").index)
	map.add_placement(Registry.get_building(&"container"), Vector2i(11, 11))
	var world := GameWorld.create(null, map, true)
	var copper := Registry.get_item(&"hematite").index
	var lead := Registry.get_item(&"brick").index
	var storage := world.buildings.get_at(Vector2i(11, 11)) as StorageBuilding
	storage.inventory.add(copper, 50)
	var unloader := _place(world, &"unloader", Vector2i(12, 11))
	Worlds.conveyor_line(world, Vector2i(13, 11), 3, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(16, 11))
	world.configure(unloader, lead)
	Worlds.run_ticks(world, 200)
	_check(sink.received == 0, "разгрузчик с фильтром «кирпич» не берёт гематит")
	world.configure(unloader, copper)
	Worlds.run_ticks(world, 600)
	_check(sink.received > 20, "разгрузчик выгружает гематит (%d)" % sink.received)
	var in_storage := storage.inventory.count(copper)
	var on_belts := world.simulation.conveyors.get_item_count()
	_check(in_storage + on_belts + sink.received == 50, "предметы из склада не теряются")
	# Петля «склад → разгрузчик → лента → склад»: предметы крутятся, но не множатся и не пропадают.
	world.buildings.remove(sink, true)
	Worlds.conveyor_line(world, Vector2i(16, 11), 1, GameConst.Dir.UP)
	Worlds.conveyor_line(world, Vector2i(16, 10), 5, GameConst.Dir.LEFT)
	var total_before := storage.inventory.count(copper) + world.simulation.conveyors.get_item_count()
	Worlds.run_ticks(world, 900)
	var total_after := storage.inventory.count(copper) + world.simulation.conveyors.get_item_count()
	_check(total_after == total_before, "петля через склад сохраняет количество (%d → %d)" % [total_before, total_after])
	world.dispose()


## Цепочка мгновенных зданий работает, а петля из сортировщиков не зацикливает передачу.
func _test_pass_through_chains() -> void:
	var world := Worlds.empty_world(32, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 2, GameConst.Dir.RIGHT)
	world.configure(_place(world, &"sorter", Vector2i(5, 10)), 0)
	world.configure(_place(world, &"sorter", Vector2i(6, 10)), 0)
	world.configure(_place(world, &"sorter", Vector2i(7, 10)), true)
	var sink := _sink(world, Vector2i(8, 10))
	Worlds.run_ticks(world, 300)
	_check(sink.received > 30, "цепочка сортировщиков пропускает поток (%d)" % sink.received)
	# Кольцо сортировщиков без выхода: accept_item не уходит в бесконечную рекурсию.
	for p in [Vector2i(20, 5), Vector2i(21, 5), Vector2i(21, 6), Vector2i(20, 6)]:
		_place(world, &"sorter", p)
	var probe := world.buildings.place(Worlds.source_def(), Vector2i(19, 5), 0, true)
	Worlds.run_ticks(world, 30)
	_check(true, "кольцо сортировщиков не зависает")
	_check(probe.get("produced") == 0, "в кольцо сортировщиков без выхода ничего не уходит")
	world.dispose()


## Заблокированная мгновенным зданием лента просыпается, когда место освобождается дальше.
func _test_wake_through_pass_through() -> void:
	var world := Worlds.empty_world(32, 16)
	_source(world, Vector2i(2, 5), [0])
	Worlds.conveyor_line(world, Vector2i(3, 5), 3, GameConst.Dir.RIGHT)
	_place(world, &"sorter", Vector2i(6, 5))
	world.configure(world.buildings.get_at(Vector2i(6, 5)), 0)
	Worlds.conveyor_line(world, Vector2i(7, 5), 3, GameConst.Dir.RIGHT)
	Worlds.run_ticks(world, 900)
	_check(world.simulation.conveyors.get_awake_count() == 0, "линия за сортировщиком забилась и уснула")
	var sink := _sink(world, Vector2i(10, 5))
	Worlds.run_ticks(world, 300)
	_check(sink.received > 20, "после появления выхода поток через сортировщик возобновился (%d)" % sink.received)
	world.dispose()


## Пипетка переносит настройку, снос возвращает содержимое буферов в ядро.
func _test_config_copy_and_contents() -> void:
	var world := Worlds.empty_world(24, 16, true)
	var lead := Registry.get_item(&"brick").index
	var sorter := world.build(Registry.get_building(&"sorter"), Vector2i(4, 4), 0, lead)
	_check(sorter != null and sorter.get_display_item() == lead, "настройка применяется при строительстве")
	var bridge := world.build(Registry.get_building(&"bridge_conveyor"), Vector2i(4, 8), 0, Vector2i(3, 0))
	_check(bridge.get_config() == Vector2i(3, 0), "настройка моста копируется как смещение")
	var router := world.build(Registry.get_building(&"router"), Vector2i(10, 10), 0)
	router.handle_item(null, lead)
	var before := world.drone.inventory.count(lead)
	_check(world.demolish(router), "снос делителя")
	_check(world.drone.inventory.count(lead) == before + 1, "предмет из делителя ушёл в инвентарь")
	world.dispose()


# --- Производство (этап 4) ---

func _item(id: StringName) -> int:
	return Registry.get_item(id).index


## Печь: рецепт по пришедшему сырью, уголь — топливо; без топлива стоит.
func _test_furnace() -> void:
	var world := Worlds.empty_world(24, 16)
	var hematite := _item(&"hematite")
	var coal := _item(&"coal")
	var iron := _item(&"iron_ingot")
	_source(world, Vector2i(2, 4), [hematite])
	Worlds.conveyor_line(world, Vector2i(3, 4), 3, GameConst.Dir.RIGHT)
	var furnace := _place(world, &"furnace", Vector2i(6, 4)) as Crafter
	Worlds.conveyor_line(world, Vector2i(8, 4), 2, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(10, 4))
	Worlds.run_ticks(world, 300)
	_check(furnace.get_recipe() != null and furnace.get_recipe().id == &"smelt_iron", "печь выбрала переплавку железа по гематиту")
	_check(sink.received == 0 and furnace.get_status() == Building.Status.NO_FUEL, "без угля печь стоит")
	for i in 5:
		furnace.handle_item(null, coal)
	Worlds.run_ticks(world, 30 * GameConst.TICK_RATE)
	var ingots: int = sink.count_of(iron)
	_check(ingots >= 8 and ingots <= 10, "печь выдала железо за 30 с: %d (≈9)" % ingots)
	_check(furnace.get_status() == Building.Status.WORKING, "печь работает")
	_check(5 - furnace.total_fuel() == 1, "за 9 слитков сгорел один уголь (%d)" % (5 - furnace.total_fuel()))
	_check(sink.count_of(hematite) == 0 and not furnace.accept_item(null, _item(&"stone")), "гематит не проходит сквозь печь, камень при нём не принимается")
	world.dispose()

	# Пустая печь берёт рецепт по новому сырью.
	world = Worlds.empty_world(24, 16)
	var brick_furnace := _place(world, &"furnace", Vector2i(6, 4)) as Crafter
	_check(brick_furnace.accept_item(null, _item(&"stone")) and brick_furnace.accept_item(null, hematite), "пустая печь принимает любое сырьё переплавки")
	for i in 4:
		brick_furnace.handle_item(null, _item(&"stone"))
	brick_furnace.handle_item(null, coal)
	Worlds.run_ticks(world, 8 * GameConst.TICK_RATE)
	_check(brick_furnace.get_recipe().id == &"smelt_brick" and brick_furnace.outputs[_item(&"brick")] == 2, "камень → кирпичи (%d)" % brick_furnace.outputs[_item(&"brick")])
	_check(not brick_furnace.accept_item(null, _item(&"malachite")) or brick_furnace.inputs[_item(&"stone")] == 0, "с камнем во входе малахит ждёт")
	world.dispose()




## Печь без выхода: буфер заполняется, статус «выход забит», входные ленты и печь засыпают.
func _test_output_blocked() -> void:
	var world := Worlds.empty_world(24, 16)
	var iron := _item(&"iron_ingot")
	_source(world, Vector2i(2, 4), [_item(&"hematite"), _item(&"coal")])
	Worlds.conveyor_line(world, Vector2i(3, 4), 3, GameConst.Dir.RIGHT)
	var furnace := _place(world, &"furnace", Vector2i(6, 4)) as Crafter
	Worlds.run_ticks(world, 70 * GameConst.TICK_RATE)
	_check(furnace.outputs[iron] == furnace.get_output_capacity(), "выходной буфер печи заполнен (%d)" % furnace.outputs[iron])
	_check(furnace.get_status() == Building.Status.OUTPUT_BLOCKED, "статус «выход забит»")
	Worlds.run_ticks(world, 120)
	_check(world.simulation.conveyors.get_awake_count() == 0 and world.simulation.get_awake_building_count() == 0,
		"забитая печь и ленты спят")
	var sink := _sink(world, Vector2i(8, 4))
	Worlds.run_ticks(world, 300)
	_check(sink.count_of(iron) > 9, "после появления выхода печь снова работает (%d)" % sink.count_of(iron))
	world.dispose()






## Сборщик: рецепт — настройка; без питания стоит; при нехватке мощности работает медленнее.
func _test_assembler_power() -> void:
	var world := Worlds.empty_world(32, 20)
	var iron := _item(&"iron_ingot")
	var gear := _item(&"gear")
	var assembler := _place(world, &"assembler", Vector2i(6, 6)) as Crafter
	_check(assembler.get_recipe() == null and not assembler.accept_item(null, iron), "без рецепта сборщик ничего не принимает")
	world.configure(assembler, &"gear")
	_check(assembler.get_recipe().id == &"gear" and assembler.get_config() == &"gear", "рецепт сборщика — настройка")
	_check(assembler.accept_item(null, iron) and not assembler.accept_item(null, _item(&"hematite")), "сборщик принимает только сырьё рецепта")
	for i in 20:
		assembler.handle_item(null, iron)
	Worlds.run_ticks(world, 60)
	_check(assembler.outputs[gear] == 0 and assembler.get_status() == Building.Status.NO_POWER, "без опоры сборщик не работает")
	var pole := _place(world, &"small_power_pole", Vector2i(9, 7)) as PowerPole
	var generator := _place(world, &"thermal_generator", Vector2i(10, 8)) as Generator
	for i in 3:
		generator.handle_item(null, _item(&"coal"))
	Worlds.run_ticks(world, 5 * GameConst.TICK_RATE)
	_check(assembler.outputs[gear] >= 8, "с питанием сборщик делает шестерни (%d)" % assembler.outputs[gear])
	var net := assembler.power_net
	_check(net != null and net.generators.has(generator) and net.poles.has(pole) and is_equal_approx(net.satisfaction, 1.0),
		"сеть: опора, генератор, сборщик — питания хватает")
	# Перегрузка: три сборщика (225 кВт) на термогенератор (150 кВт) — удовлетворённость 2/3.
	for origin in [Vector2i(7, 8), Vector2i(8, 4)]:
		var extra := _place(world, &"assembler", origin) as Crafter
		world.configure(extra, &"gear")
		for i in 40:
			extra.handle_item(null, iron)
	for i in 40:
		assembler.handle_item(null, iron)
	assembler.outputs[gear] = 0
	Worlds.run_ticks(world, 60)
	# Состав сети пересчитан — объект сети новый.
	net = assembler.power_net
	_check(net.consumers.size() == 3 and absf(net.satisfaction - 2.0 / 3.0) < 0.01, "при нехватке мощности удовлетворённость 2/3 (%.3f)" % net.satisfaction)
	var before := assembler.outputs[gear]
	Worlds.run_ticks(world, 3 * GameConst.TICK_RATE)
	var made := assembler.outputs[gear] - before
	_check(made >= 3 and made <= 5, "сборщик замедлился: %d шестерни за 3 с вместо 6" % made)
	world.buildings.remove(pole, true)
	Worlds.run_ticks(world, 2)
	_check(assembler.power_net == null and world.power.unconnected.has(assembler), "без опоры сборщики отключены")
	world.dispose()


## Снос печи посреди цикла: сырьё, топливо, продукция и начатый цикл уходят в инвентарь.
func _test_crafter_contents() -> void:
	var world := Worlds.empty_world(32, 24, true)
	var hematite := _item(&"hematite")
	var iron := _item(&"iron_ingot")
	var coal := _item(&"coal")
	var furnace := world.build(Registry.get_building(&"furnace"), Vector2i(10, 10), 0) as Crafter
	for i in 6:
		furnace.handle_item(null, hematite)
	for i in 2:
		furnace.handle_item(null, coal)
	Worlds.run_ticks(world, 240)
	_check(furnace.outputs[iron] > 0 and furnace.crafting, "печь делает железо (%d)" % furnace.outputs[iron])
	var totals := PackedInt32Array()
	totals.resize(Registry.items.size())
	totals.fill(0)
	furnace.collect_contents(totals)
	_check(totals[hematite] + totals[iron] == 6 and totals[coal] == 1, "в содержимом: 6 сырья и продукции, 1 уголь (%d + %d, %d)" % [totals[hematite], totals[iron], totals[coal]])
	var inv := world.drone.inventory
	_check(world.demolish(furnace), "снос печи")
	_check(inv.count(hematite) == totals[hematite] and inv.count(iron) == totals[iron] and inv.count(coal) == totals[coal],
		"сырьё, топливо, продукт и начатый цикл ушли в инвентарь")
	world.dispose()


## Данные заводов: рецепты с входами и выходами, топливо печи, питание сборщика.
func _test_recipes_data() -> void:
	var crafters := 0
	for def in Registry.buildings:
		if def is CrafterDef:
			crafters += 1
			for recipe in (def as CrafterDef).recipes:
				_check(recipe != null and not recipe.consumes.is_empty() and not recipe.output_items().is_empty(), "рецепт %s завода %s" % [recipe.id, def.id])
			_check(not def.get_stat_lines().is_empty(), "характеристики завода %s для меню" % def.id)
	_check(crafters == 2, "заводов 2: печь и сборщик (%d)" % crafters)
	var furnace := Registry.get_building(&"furnace") as CrafterDef
	_check(furnace.recipe_mode == CrafterDef.RecipeMode.AUTO and furnace.fuel_use > 0.0 and furnace.power_use == 0.0 and furnace.recipes.size() == 3,
		"печь: три переплавки на топливе, рецепт по сырью")
	var assembler := Registry.get_building(&"assembler") as CrafterDef
	_check(assembler.recipe_mode == CrafterDef.RecipeMode.SELECT and assembler.power_use > 0.0 and assembler.recipes.size() == 10,
		"сборщик: 10 рецептов на выбор, от электричества")
	for id in [&"drill", &"science_workshop"]:
		_check(Registry.get_building(id).power_use > 0.0, "%s потребляет электричество" % id)
	for id in [&"machine_gun", &"unloader", &"pump"]:
		_check(Registry.get_building(id).power_use == 0.0, "%s работает без электричества" % id)


## Регрессия: смена настройки будит ленты, уснувшие перед зданием (сортировщик без фильтра, мост без связи).
func _test_config_wakes_blocked_belts() -> void:
	var world := Worlds.empty_world(32, 16)
	var copper := _item(&"hematite")
	_source(world, Vector2i(2, 4), [copper])
	Worlds.conveyor_line(world, Vector2i(3, 4), 3, GameConst.Dir.RIGHT)
	var sorter := _place(world, &"sorter", Vector2i(6, 4))
	Worlds.conveyor_line(world, Vector2i(7, 4), 2, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(9, 4))
	Worlds.run_ticks(world, 900)
	_check(sink.received == 0, "сортировщик без фильтра и без боковых выходов ничего не пропускает")
	world.configure(sorter, copper)
	Worlds.run_ticks(world, 300)
	_check(sink.received > 20, "после выбора фильтра уснувшая лента проснулась (%d)" % sink.received)

	_source(world, Vector2i(2, 10), [copper])
	Worlds.conveyor_line(world, Vector2i(3, 10), 2, GameConst.Dir.RIGHT)
	var a := _place(world, &"bridge_conveyor", Vector2i(5, 10))
	var b := _place(world, &"bridge_conveyor", Vector2i(8, 10))
	var bridge_sink := _sink(world, Vector2i(9, 10))
	Worlds.run_ticks(world, 900)
	_check(bridge_sink.received == 0, "мост без связи не принимает")
	world.configure(a, b.origin - a.origin)
	Worlds.run_ticks(world, 300)
	_check(bridge_sink.received > 20, "после связи мостов уснувшая лента проснулась (%d)" % bridge_sink.received)
	world.dispose()


## Пропускная способность логистики: как у обычной ленты (титановые версии вернутся в мидгейме).
## Подающие и отводящие ленты вдвое быстрее — узким местом остаётся проверяемый блок.
func _test_logistics_throughput() -> void:
	var hematite := _item(&"hematite")
	var belt_rate: float = (Registry.get_building(&"conveyor") as ConveyorDef).get_items_per_second()
	var fast_belt := Registry.get_building(&"conveyor").duplicate() as ConveyorDef
	fast_belt.tiles_per_second *= 2.0
	for id in [&"junction", &"router", &"sorter", &"bridge_conveyor", &"unloader"]:
		var def := Registry.get_building(id) as LogisticDef
		_check(is_equal_approx(def.get_items_per_second(), belt_rate), "%s: заявлено %.1f предм./с" % [id, def.get_items_per_second()])
		var world := Worlds.empty_world(32, 12)
		var y := 5
		if def.logic_script == preload("res://buildings/transport/unloader.gd"):
			var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(7, y), 0, true) as StorageBuilding
			storage.inventory.add(hematite, 800)
		else:
			_source(world, Vector2i(3, y), [hematite])
			Worlds.conveyor_line(world, Vector2i(4, y), 4, GameConst.Dir.RIGHT, &"", fast_belt)
		var block := world.buildings.place(def, Vector2i(8, y), 0, true)
		var out_start := 9
		if block is BridgeConveyor:
			var end := world.buildings.place(def, Vector2i(11, y), 0, true)
			world.configure(block, end.origin - block.origin)
			out_start = 12
		elif block is Sorter:
			world.configure(block, hematite)
		Worlds.conveyor_line(world, Vector2i(out_start, y), 4, GameConst.Dir.RIGHT, &"", fast_belt)
		var sink := _sink(world, Vector2i(out_start + 4, y))
		Worlds.run_ticks(world, 300)
		var before: int = sink.received
		Worlds.run_ticks(world, 600)
		var rate: float = (sink.received - before) / 20.0
		_check(absf(rate - belt_rate) <= 0.35, "%s: реальная пропускная способность %.2f предм./с (ожидалось %.1f)" % [id, rate, belt_rate])
		world.dispose()


## Разгрузчик достаёт продукцию и сырьё заводов, добычу буров; топливо печи не трогает.
func _test_unloader_from_buildings() -> void:
	var hematite := _item(&"hematite")
	var coal := _item(&"coal")
	var iron := _item(&"iron_ingot")
	var world := Worlds.empty_world(32, 24)
	var furnace := world.buildings.place(Registry.get_building(&"furnace"), Vector2i(6, 5), 0, true) as Crafter
	for i in 5:
		furnace.handle_item(null, coal)
	_source(world, Vector2i(5, 5), [hematite])
	var unloader := _place(world, &"unloader", Vector2i(8, 5))
	Worlds.conveyor_line(world, Vector2i(9, 5), 3, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(12, 5))
	Worlds.run_ticks(world, 900)
	_check(sink.count_of(hematite) > 5, "разгрузчик забирает сырьё из печи (%d)" % sink.count_of(hematite))
	_check(sink.count_of(coal) == 0, "топливо печи разгрузчик не забирает")
	world.configure(unloader, iron)
	Worlds.run_ticks(world, 90)
	var before: int = sink.count_of(hematite)
	Worlds.run_ticks(world, 900)
	_check(sink.count_of(hematite) == before, "с фильтром «железо» гематит не забирается")
	_check(sink.count_of(iron) > 0, "с фильтром уходит продукция (%d)" % sink.count_of(iron))

	# Бур → разгрузчик → лента.
	var map := LevelMap.new(24, 12, Registry.get_floor(&"stone").index)
	for y in range(4, 6):
		for x in range(4, 6):
			map.set_ore(x, y, Registry.get_ore(&"hematite").index + 1)
	var mine := GameWorld.create(null, map, true)
	mine.buildings.place(Registry.get_building(&"drill"), Vector2i(4, 4), 0, true)
	mine.buildings.place(Registry.get_building(&"unloader"), Vector2i(6, 4), 0, true)
	Worlds.conveyor_line(mine, Vector2i(7, 4), 3, GameConst.Dir.RIGHT)
	var drill_sink := mine.buildings.place(Worlds.sink_def(), Vector2i(10, 4), 0, true)
	Worlds.power_area(mine, Vector2i(2, 5), 5, Vector2i(3, 7))
	Worlds.run_ticks(mine, 900)
	_check(drill_sink.received > 5, "разгрузчик забирает добычу бура (%d)" % drill_sink.received)

	# Склад → разгрузчик → печь: сырьё уходит в печь и назад в склад не возвращается.
	var chain := Worlds.empty_world(32, 24)
	var storage := chain.buildings.place(Registry.get_building(&"container"), Vector2i(5, 4), 0, true) as StorageBuilding
	storage.inventory.add(hematite, 100)
	chain.buildings.place(Registry.get_building(&"unloader"), Vector2i(6, 4), 0, true)
	var fed := chain.buildings.place(Registry.get_building(&"furnace"), Vector2i(7, 4), 0, true) as Crafter
	for i in 3:
		fed.handle_item(null, coal)
	Worlds.run_ticks(chain, 900)
	var produced := fed.outputs[iron]
	_check(produced > 0, "печь получила гематит из склада через разгрузчик и работает")
	_check(storage.inventory.count(hematite) + fed.inputs[hematite] + produced + (1 if fed.crafting else 0) == 100,
		"гематит не гоняется по кругу между складом и печью")
	_check(storage.inventory.count(iron) == 0, "в склад разгрузчик не кладёт")
	world.dispose()
	mine.dispose()
	chain.dispose()


## Инверсия — настройка: переносится пипеткой и копированием, переключается отдельно от фильтра.
func _test_inversion_config() -> void:
	var world := Worlds.empty_world(24, 16, true)
	var lead := _item(&"brick")
	var sorter := world.build(Registry.get_building(&"sorter"), Vector2i(4, 4), 0, {"item": lead, "inverted": true})
	_check(sorter.get_display_item() == lead and sorter.is_inverted(), "настройка сортировщика словарём при стройке")
	world.configure(sorter, null)
	_check(sorter.get_display_item() == -1 and sorter.is_inverted(), "снятие фильтра не сбрасывает инверсию")
	world.configure(sorter, false)
	_check(not sorter.is_inverted() and sorter.get_config() == null, "без фильтра и инверсии настройки нет")
	var router := world.build(Registry.get_building(&"router"), Vector2i(8, 4), 0, {"in": 2, "out": 0}) as Router
	_check(router.priority_in == 2 and router.priority_out == 0, "приоритеты маршрутизатора — настройка при стройке")
	var copy := world.build(Registry.get_building(&"router"), Vector2i(10, 4), 1, router.get_config()) as Router
	_check(copy.world_side(copy.priority_out) == GameConst.Dir.DOWN, "копия с поворотом поворачивает приоритеты")
	world.configure(router, null)
	_check(not router.has_priorities() and router.get_config() == null, "приоритеты снимаются")
	world.dispose()


## Забег: два мира тикают вместе, шлюз переносит предметы в обе стороны, дрон проходит через шлюз.
func _test_run_gateway() -> void:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	_unlock_all(run)
	var copper := _item(&"hematite")
	var lead := _item(&"brick")
	var gate := run.get_gateway(run.planet)
	var pair := run.get_gateway(run.base)
	_check(run.base.is_base and not run.planet.is_base and run.base.grid.width == Registry.base_def.size, "база отдельным миром нужного размера")
	_check(gate != null and pair != null and gate.link == run.link and pair.link == run.link, "шлюз и пара связаны")
	if gate == null or pair == null:
		run.dispose()
		return
	_check(run.drone.world == run.planet and run.can_use_gateway(), "дрон появляется над шлюзом на планете")
	var center := gate.origin + Vector2i.ONE * (gate.get_size() / 2)
	var pad_side := run.get_pad_size()
	_check(run.planet.pad_rect == Rect2i(center - Vector2i.ONE * (pad_side / 2), Vector2i(pad_side, pad_side)), "площадка вокруг шлюза (после всех расширений)")

	# Планета → база: в западный порт шлюза, из западного порта пары.
	var in_port := gate.get_input_tile()
	_source(run.planet, in_port + Vector2i(-2, 0), [copper])
	Worlds.conveyor_line(run.planet, in_port + Vector2i(-1, 0), 2, GameConst.Dir.RIGHT)
	var out_port := pair.get_output_tile()
	Worlds.conveyor_line(run.base, out_port, 2, GameConst.Dir.LEFT)
	var base_sink := _sink(run.base, out_port + Vector2i(-2, 0))
	for i in 900:
		run.step()
	_check(run.planet.simulation.tick == 900 and run.base.simulation.tick == 900, "оба мира тикают вместе")
	var port_rate: float = (Registry.get_building(&"conveyor") as ConveyorDef).get_items_per_second()
	_check(base_sink.count_of(copper) > port_rate * 30 * 0.7, "гематит с планеты пришёл в базу (%d)" % base_sink.count_of(copper))

	# Не через порт — не принимается.
	var north := run.planet.buildings.place(Registry.get_building(&"conveyor"), gate.origin + Vector2i(1, -1), GameConst.Dir.DOWN, true)
	_check(not gate.accept_item(north, copper), "шлюз не принимает предметы не через порт")

	# База → планета: в восточный порт пары, из восточного порта шлюза.
	var back_in := pair.get_input_tile()
	_source(run.base, back_in + Vector2i(2, 0), [lead])
	Worlds.conveyor_line(run.base, back_in + Vector2i(1, 0), 2, GameConst.Dir.LEFT)
	var back_out := gate.get_output_tile()
	Worlds.conveyor_line(run.planet, back_out, 2, GameConst.Dir.RIGHT)
	var planet_sink := _sink(run.planet, back_out + Vector2i(2, 0))
	for i in 600:
		run.step()
	_check(planet_sink.count_of(lead) > 50, "кирпичи из базы вышли на планету (%d)" % planet_sink.count_of(lead))

	# Нет выхода в базе — очередь «в базу» заполняется, поток встаёт; появился выход — идёт дальше.
	run.base.buildings.remove(base_sink, true)
	for i in 600:
		run.step()
	_check(run.link.size_of(true) == run.link.capacity * gate.port_count(), "без выхода очередь шлюза заполнена: по %d на порт (%d)" % [run.link.capacity, run.link.size_of(true)])
	base_sink = _sink(run.base, out_port + Vector2i(-2, 0))
	for i in 300:
		run.step()
	_check(base_sink.received > 20, "после появления выхода поток через шлюз возобновился (%d)" % base_sink.received)

	# Дрон проходит через шлюз; действовать можно только в мире, где он.
	var conveyor := Registry.get_building(&"conveyor")
	run.drone.inventory.add(conveyor.item.index, 5)
	_check(run.use_gateway() and run.drone.world == run.base, "F над шлюзом переносит дрона в базу")
	_check(pair.get_world_rect().has_point(run.drone.position), "дрон над парой шлюза")
	_check(run.planet.check_build(conveyor, gate.origin + Vector2i(0, -4), 0) == BuildingManager.Check.OUT_OF_RANGE, "на планете без дрона строить нельзя")
	_check(run.base.check_build(conveyor, pair.origin + Vector2i(0, -3), 0) == BuildingManager.Check.OK, "в базе строить можно")
	var y0 := run.drone.position.y
	run.drone.move_input = Vector2.DOWN
	for i in 15:
		run.step()
	run.drone.move_input = Vector2.ZERO
	_check(absf(run.drone.position.y - y0 - run.drone.get_speed() * GameConst.TILE_SIZE * 0.5) < 1.0, "дрон обновляется один раз за тик в своём мире")
	_check(not run.can_use_gateway(), "вдали от пары пройти нельзя")
	run.drone.position = pair.get_world_center()
	_check(run.use_gateway() and run.drone.world == run.planet, "дрон возвращается на планету")
	run.dispose()


## Маршрутизатор как в Mindustry: возвращает предмет источнику, если тот принимает.
func _test_router_returns_items() -> void:
	var world := Worlds.empty_world(24, 12)
	var src := _source(world, Vector2i(3, 5), [_item(&"hematite")])
	src.set("limit", 20)
	Worlds.conveyor_line(world, Vector2i(4, 5), 1, GameConst.Dir.RIGHT)
	_place(world, &"router", Vector2i(5, 5))
	var dead_end := _place(world, &"router", Vector2i(5, 4))
	Worlds.conveyor_line(world, Vector2i(5, 6), 2, GameConst.Dir.DOWN)
	var sink := _sink(world, Vector2i(5, 8))
	Worlds.run_ticks(world, 900)
	_check(sink.received == 20, "все предметы дошли: тупиковый маршрутизатор вернул свой (%d из 20)" % sink.received)
	_check(dead_end.get("item") == -1, "тупиковый маршрутизатор пуст")
	world.dispose()


## Чередование маршрутизатор+перекрёсток не душит поток (предмет не разворачивается на каждом хопе).
func _test_router_junction_chain() -> void:
	var belt_rate: float = (Registry.get_building(&"conveyor") as ConveyorDef).get_items_per_second()
	var pairs := 15
	var world := Worlds.empty_world(48, 12)
	var y := 5
	_source(world, Vector2i(2, y), [_item(&"hematite")])
	Worlds.conveyor_line(world, Vector2i(3, y), 1, GameConst.Dir.RIGHT)
	var x := 4
	for i in pairs:
		_place(world, &"router", Vector2i(x, y))
		x += 1
		_place(world, &"junction", Vector2i(x, y))
		x += 1
	Worlds.conveyor_line(world, Vector2i(x, y), 2, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(x + 2, y))
	Worlds.run_ticks(world, 400)
	var before: int = sink.received
	Worlds.run_ticks(world, 600)
	var rate: float = (sink.received - before) / 20.0
	_check(absf(rate - belt_rate) <= 0.5, "цепочка маршрутизатор+перекрёсток ×%d: %.2f предм./с (ожидалось %.1f)" % [pairs, rate, belt_rate])
	world.dispose()


## Разгрузчик балансирует две печи и не кладёт в склад.
func _test_unloader_balancing() -> void:
	var hematite := _item(&"hematite")
	var world := Worlds.empty_world(32, 24)
	var a := world.buildings.place(Registry.get_building(&"furnace"), Vector2i(4, 4), 0, true) as Crafter
	world.buildings.place(Registry.get_building(&"unloader"), Vector2i(6, 4), 0, true)
	var b := world.buildings.place(Registry.get_building(&"furnace"), Vector2i(7, 4), 0, true) as Crafter
	for i in 8:
		a.handle_item(null, hematite)
	Worlds.run_ticks(world, 90)
	var total := a.inputs[hematite] + b.inputs[hematite] + (1 if a.crafting else 0) + (1 if b.crafting else 0)
	_check(b.inputs[hematite] > 0 or b.crafting, "разгрузчик перекладывает гематит в менее заполненную печь")
	_check(absi(a.inputs[hematite] - b.inputs[hematite]) <= 2, "печи уравновешены (%d / %d)" % [a.inputs[hematite], b.inputs[hematite]])
	_check(total == 8, "гематит не теряется при балансировке (%d)" % total)
	world.dispose()


## Поворот шлюза меняет стороны портов.
func _test_gateway_rotation() -> void:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, true)
	var gate := run.get_gateway(run.planet)
	var west := gate.get_input_tile()
	run.drone.world = run.planet
	_check(run.planet.rotate_building(gate, 1), "шлюз поворачивается")
	_check(gate.get_input_side() == GameConst.Dir.UP and gate.get_output_side() == GameConst.Dir.DOWN, "после поворота вход сверху, выход снизу")
	var belt_old := run.planet.buildings.place(Registry.get_building(&"conveyor"), west, GameConst.Dir.RIGHT, true)
	var belt_new := run.planet.buildings.place(Registry.get_building(&"conveyor"), gate.get_input_tile(), GameConst.Dir.DOWN, true)
	_check(not gate.accept_item(belt_old, 0) and gate.accept_item(belt_new, 0), "шлюз принимает только через новый порт")
	var pair := run.get_gateway(run.base)
	_check(pair.get_output_side() == GameConst.Dir.LEFT, "пара в базе поворачивается независимо")
	run.dispose()


## Звёздная карта: детерминирована, связи ведут вперёд, у каждого шага есть вход.
func _test_star_map() -> void:
	var a := StarMap.new(12345, Registry.run_def, Registry.planet_types)
	var b := StarMap.new(12345, Registry.run_def, Registry.planet_types)
	_check(a.nodes.size() == b.nodes.size() and a.get_current().code == b.get_current().code, "карта детерминирована от сида")
	_check(a.get_current().type == Registry.run_def.first_planet_type, "первая планета — обычная")
	var all_ores := true
	for seed_value in 40:
		var start := StarMap.new(seed_value, Registry.run_def, Registry.planet_types).get_current()
		all_ores = all_ores and start.ores.size() == start.type.ore_ids.size()
	_check(all_ores, "на стартовой планете есть все руды её типа (40 сидов)")
	_check(a.get_step_count() == Registry.run_def.visible_depth + 1, "карта построена на %d шагов вперёд" % Registry.run_def.visible_depth)
	var next := a.get_next()
	_check(not next.is_empty(), "из стартовой планеты есть куда лететь")
	var ok := true
	var has_input := {}
	for node in a.nodes:
		for target_id in node.links:
			if a.get_node(target_id).depth != node.depth + 1:
				ok = false
			has_input[target_id] = true
	for node in a.nodes:
		if node.depth > 0 and not has_input.has(node.id):
			ok = false
	_check(ok, "связи только на шаг вперёд, у каждой планеты есть вход")
	var unsafe_per_step := true
	for depth in range(1, a.get_step_count()):
		var any_unsafe := false
		for node in a.nodes:
			if node.depth == depth and not node.type.safe:
				any_unsafe = true
		unsafe_per_step = unsafe_per_step and any_unsafe
	_check(unsafe_per_step, "в каждом шаге есть планета с ресурсами")
	a.move_to(next[0].id)
	_check(a.get_step_count() == next[0].depth + Registry.run_def.visible_depth + 1, "после перелёта карта достраивается вперёд")
	_check(not a.can_travel_to(0), "назад лететь нельзя")
	var wasteland_seen := false
	for run_seed in 40:
		var m := StarMap.new(run_seed, Registry.run_def, Registry.planet_types)
		for node in m.nodes:
			if node.type.safe:
				wasteland_seen = true
				_check(node.ores.is_empty(), "в пустоши нет руд")
	_check(wasteland_seen, "пустоши встречаются на звёздной карте")


## Генератор: детерминирован, место посадки — платформа, у обычной планеты руда рядом.
func _test_planet_generator() -> void:
	var star_map := StarMap.new(777, Registry.run_def, Registry.planet_types)
	var node := star_map.get_current()
	var map_a := PlanetGenerator.generate(node, Registry.run_def.pad_start_size)
	var map_b := PlanetGenerator.generate(node, Registry.run_def.pad_start_size)
	_check(map_a.floors == map_b.floors and map_a.ores == map_b.ores, "генерация детерминирована")
	_check(map_a.width == node.size.x and map_a.height == node.size.y, "размер карты как у узла")
	var center := Vector2i(map_a.width / 2, map_a.height / 2)
	var platform := Registry.get_floor(&"metal_plates").index
	var pad_ok := true
	var half := Registry.run_def.pad_start_size / 2
	for y in range(center.y - half, center.y + half):
		for x in range(center.x - half, center.x + half):
			pad_ok = pad_ok and map_a.get_floor(x, y) == platform and map_a.get_ore(x, y) == 0
	_check(pad_ok, "площадка — платформа без руды")
	var near_ore := 0
	for y in range(maxi(center.y - 36, 0), mini(center.y + 36, map_a.height)):
		for x in range(maxi(center.x - 36, 0), mini(center.x + 36, map_a.width)):
			if map_a.get_ore(x, y) != 0:
				near_ore += 1
	_check(near_ore > 40, "у обычной планеты руда недалеко от посадки (%d тайлов)" % near_ore)
	_check(node.size.x >= 336 and node.size.x <= 480 and node.size.y >= 252 and node.size.y <= 360,
		"обычная планета втрое больше прежней по стороне (%d×%d)" % [node.size.x, node.size.y])
	var started := Time.get_ticks_msec()
	PlanetGenerator.generate(node, Registry.run_def.pad_start_size)
	print("Генерация планеты %d×%d: %d мс" % [node.size.x, node.size.y, Time.get_ticks_msec() - started])
	var world := GameWorld.create(null, map_a, false)
	var drill := Registry.get_building(&"drill")
	_check(world.buildings.check_place(Registry.get_building(&"container"), center + Vector2i(3, 3), 0) == BuildingManager.Check.OK, "на площадке можно строить")
	world.dispose()
	for id in star_map.nodes.size():
		var n := star_map.get_node(id)
		if n.type.safe:
			var waste := PlanetGenerator.generate(n, Registry.run_def.pad_start_size)
			var ores := 0
			for v in waste.ores:
				ores += 1 if v != 0 else 0
			_check(ores == 0, "в пустоше ни одного тайла руды")
			break


## Состояние зданий переносится в новое здание того же типа.
func _test_building_state_roundtrip() -> void:
	var world := Worlds.empty_world(32, 24)
	var copper := _item(&"hematite")
	var coal := _item(&"coal")
	var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(2, 2), 0, true) as StorageBuilding
	storage.inventory.add(copper, 150)
	storage.inventory.add(coal, 7)
	var press := world.buildings.place(Registry.get_building(&"furnace"), Vector2i(6, 2), 0, true) as Crafter
	for i in 5:
		press.handle_item(null, copper)
	press.handle_item(null, coal)
	_source(world, Vector2i(2, 8), [copper])
	Worlds.conveyor_line(world, Vector2i(3, 8), 2, GameConst.Dir.RIGHT)
	var belt := world.buildings.get_at(Vector2i(4, 8))
	Worlds.run_ticks(world, 200)
	var other := Worlds.empty_world(32, 24)
	other.simulation.tick = world.simulation.tick
	for original in [storage, press, belt]:
		var copy := other.buildings.place(original.def, original.origin, original.rotation, true)
		copy.load_state(original.save_state())
		var a := PackedInt32Array()
		a.resize(Registry.items.size())
		a.fill(0)
		var b := a.duplicate()
		original.collect_contents(a)
		copy.collect_contents(b)
		_check(a == b and TeleportSummary.total(a) > 0, "%s: содержимое перенесено (%d)" % [original.def.id, TeleportSummary.total(b)])
	world.dispose()
	other.dispose()


## Телепорт: площадка переезжает с содержимым, остальное теряется, база и очередь шлюза сохраняются.
func _test_teleport() -> void:
	var run := Run.create_new(4242, false)
	var copper := _item(&"hematite")
	var gate := run.get_gateway(run.planet)
	var pad := run.planet.pad_rect
	_check(pad.size == Vector2i.ONE * Registry.run_def.pad_start_size and run.drone.world == run.planet, "новый забег: дрон на площадке 20×20 планеты")
	_check(TeleportSummary.total(run.drone.inventory.totals) > 0, "стартовый инвентарь выдан")
	# На площадке: склад с гематитом и лента с предметами. Вне площадки — склад, который потеряется.
	var on_pad := run.planet.buildings.place(Registry.get_building(&"container"), pad.position + Vector2i(1, 1), 0, true) as StorageBuilding
	on_pad.inventory.add(copper, 90)
	var belt := run.planet.buildings.place(Registry.get_building(&"conveyor"), pad.position + Vector2i(4, 1), GameConst.Dir.UP, true)
	run.planet.simulation.conveyors.import_items(belt, {"items": PackedInt32Array([copper, copper]), "prog": PackedInt32Array([900, 300])})
	var sorter := run.planet.buildings.place(Registry.get_building(&"sorter"), pad.position + Vector2i(6, 1), 0, true)
	run.planet.configure(sorter, {"item": copper, "inverted": true})
	var outside := run.planet.buildings.place(Registry.get_building(&"container"), pad.position + Vector2i(-6, 0), 0, true) as StorageBuilding
	outside.inventory.add(copper, 33)
	run.planet.rotate_building(gate, 2)
	run.link.push(true, copper)
	var in_base := run.base.buildings.place(Registry.get_building(&"container"), Vector2i(2, 2), 0, true) as StorageBuilding
	in_base.inventory.add(copper, 11)
	var old_planet := run.planet
	var old_code := run.star_map.get_current().code

	var next := run.star_map.get_next()
	_check(run.start_teleport(next[0].id) and run.is_charging(), "зарядка телепорта началась")
	_check(not run.start_teleport(next[0].id), "повторно не запускается")
	run.cancel_teleport()
	_check(not run.is_charging(), "зарядку можно отменить")
	var changed := [0]
	run.planet_changed.connect(func() -> void: changed[0] += 1)
	run.start_teleport(next[0].id)
	var ticks := run.run_def.get_charge_ticks()
	for i in ticks - 1:
		run.step()
	_check(run.planet == old_planet and changed[0] == 0, "до конца зарядки планета прежняя")
	run.step()
	_check(run.planet != old_planet and changed[0] == 1, "по окончании зарядки планета заменена")
	_check(run.star_map.get_current().id == next[0].id and run.star_map.get_current().code != old_code, "текущая планета на звёздной карте сменилась")
	_check(run.planet.simulation.tick == run.base.simulation.tick, "тики новой планеты синхронны с базой")

	var new_pad := run.planet.pad_rect
	var moved := run.planet.buildings.get_at(new_pad.position + Vector2i(1, 1)) as StorageBuilding
	_check(moved != null and moved.inventory.count(copper) == 90, "склад переехал с содержимым")
	var moved_belt := run.planet.buildings.get_at(new_pad.position + Vector2i(4, 1))
	var belt_items := PackedInt32Array()
	belt_items.resize(Registry.items.size())
	belt_items.fill(0)
	if moved_belt != null:
		moved_belt.collect_contents(belt_items)
	_check(moved_belt != null and moved_belt.rotation == GameConst.Dir.UP and belt_items[copper] == 2, "лента переехала с поворотом и предметами")
	var moved_sorter := run.planet.buildings.get_at(new_pad.position + Vector2i(6, 1))
	_check(moved_sorter != null and moved_sorter.get_display_item() == copper and moved_sorter.is_inverted(), "настройка сортировщика переехала")
	var new_gate := run.get_gateway(run.planet)
	_check(new_gate != null and new_gate.world == run.planet and new_gate.rotation == 2 and new_gate.link == run.link, "шлюз на новой планете с тем же поворотом и связью")
	_check(run.link.size_of(true) == 1, "очередь шлюза сохранилась")
	_check(in_base.world == run.base and in_base.inventory.count(copper) == 11, "база не изменилась")
	_check(run.drone.world == run.planet and new_pad.has_point(run.drone.get_tile()), "дрон на площадке новой планеты")
	var summary := run.last_summary
	_check(summary != null and summary.buildings_moved == 3 and summary.buildings_lost == 1, "итог: переехало 3, потеряно 1 (%d / %d)" % [summary.buildings_moved, summary.buildings_lost])
	_check(summary.items_lost[copper] == 33, "итог: потеряно 33 гематита из склада вне площадки")
	_check(old_planet.buildings == null, "старая планета освобождена")
	for i in 60:
		run.step()
	_check(true, "после телепорта симуляция идёт")
	run.dispose()


func _build_save_run() -> Run:
	var map := LevelMap.new(64, 48, Registry.get_floor(&"stone").index)
	for y in range(10, 14):
		for x in range(10, 14):
			map.set_ore(x, y, Registry.get_ore(&"hematite").index + 1)
	map.set_ore(40, 30, Registry.get_ore(&"water").index + 1)
	var run := Run.create(null, map, false)
	for id in [&"underground", &"gateway_items"]:
		run.research.done[id] = true
	run.apply_research_effects()
	var p := run.planet
	var bm := p.buildings
	var hematite := _item(&"hematite")
	var coal := _item(&"coal")
	var drill := Registry.get_building(&"drill")
	for o in [Vector2i(10, 10), Vector2i(12, 10), Vector2i(10, 12), Vector2i(12, 12)]:
		bm.place(drill, o, 0, true)
	# Буры от термогенератора через две опоры.
	var thermal := bm.place(Registry.get_building(&"thermal_generator"), Vector2i(14, 14), 0, true) as Generator
	for i in 10:
		thermal.handle_item(null, coal)
	for tile in [Vector2i(14, 12), Vector2i(9, 12)]:
		p.power.auto_link(bm.place(Registry.get_building(&"small_power_pole"), tile, 0, true) as PowerPole)
	Worlds.conveyor_line(p, Vector2i(14, 11), 4, GameConst.Dir.RIGHT)
	var router := bm.place(Registry.get_building(&"router"), Vector2i(18, 11), 0, true)
	p.configure(router, {"in": Router.NO_SIDE, "out": GameConst.Dir.RIGHT})
	Worlds.conveyor_line(p, Vector2i(19, 11), 3, GameConst.Dir.RIGHT)
	var sorter := bm.place(Registry.get_building(&"sorter"), Vector2i(22, 11), 0, true)
	p.configure(sorter, hematite)
	Worlds.conveyor_line(p, Vector2i(23, 11), 2, GameConst.Dir.RIGHT)
	bm.place(Registry.get_building(&"container"), Vector2i(25, 11), 0, true)
	Worlds.conveyor_line(p, Vector2i(18, 10), 2, GameConst.Dir.UP)
	bm.place(Registry.get_building(&"container"), Vector2i(18, 7), 0, true)
	# Гематит и уголь → печь → мост → перекрёсток → склад; поперёк перекрёстка — кирпичи.
	var source := bm.place(Registry.get_building(&"container"), Vector2i(4, 20), 0, true) as StorageBuilding
	source.inventory.add(hematite, 200)
	source.inventory.add(coal, 40)
	bm.place(Registry.get_building(&"unloader"), Vector2i(6, 20), 0, true)
	bm.place(Registry.get_building(&"furnace"), Vector2i(7, 20), 0, true)
	bm.place(Registry.get_building(&"unloader"), Vector2i(9, 20), 0, true)
	Worlds.conveyor_line(p, Vector2i(10, 20), 2, GameConst.Dir.RIGHT)
	var bridge_a := bm.place(Registry.get_building(&"bridge_conveyor"), Vector2i(12, 20), 0, true)
	var bridge_b := bm.place(Registry.get_building(&"bridge_conveyor"), Vector2i(15, 20), 0, true)
	p.configure(bridge_a, bridge_b.origin - bridge_a.origin)
	Worlds.conveyor_line(p, Vector2i(16, 20), 1, GameConst.Dir.RIGHT)
	bm.place(Registry.get_building(&"junction"), Vector2i(17, 20), 0, true)
	Worlds.conveyor_line(p, Vector2i(18, 20), 1, GameConst.Dir.RIGHT)
	bm.place(Registry.get_building(&"container"), Vector2i(19, 20), 0, true)
	(bm.place(Registry.get_building(&"container"), Vector2i(17, 15), 0, true) as StorageBuilding).inventory.add(_item(&"brick"), 200)
	bm.place(Registry.get_building(&"unloader"), Vector2i(17, 17), 0, true)
	Worlds.conveyor_line(p, Vector2i(17, 18), 2, GameConst.Dir.DOWN)
	Worlds.conveyor_line(p, Vector2i(17, 21), 1, GameConst.Dir.DOWN)
	bm.place(Registry.get_building(&"container"), Vector2i(17, 22), 0, true)
	# Вода → бойлер → паровой генератор → сборщик шестерней.
	bm.place(Registry.get_building(&"pump"), Vector2i(40, 30), 0, true)
	for x in range(41, 44):
		bm.place(Registry.get_building(&"pipe"), Vector2i(x, 30), 0, true)
	var boiler := bm.place(Registry.get_building(&"boiler"), Vector2i(44, 30), 0, true) as Boiler
	for i in 10:
		boiler.handle_item(null, coal)
	bm.place(Registry.get_building(&"steam_generator"), Vector2i(46, 30), 0, true)
	for tile in [Vector2i(46, 32), Vector2i(45, 35)]:
		p.power.auto_link(bm.place(Registry.get_building(&"small_power_pole"), tile, 0, true) as PowerPole)
	(bm.place(Registry.get_building(&"container"), Vector2i(40, 36), 0, true) as StorageBuilding).inventory.add(_item(&"iron_ingot"), 100)
	bm.place(Registry.get_building(&"unloader"), Vector2i(42, 36), 0, true)
	var assembler := bm.place(Registry.get_building(&"assembler"), Vector2i(43, 36), 0, true)
	p.configure(assembler, &"gear")
	var gate := run.get_gateway(p)
	world_to_gateway(run, gate, hematite)
	# Исследования посреди ручной сдачи.
	run.research.set_active(&"mining")
	run.research.progress[&"mining"] = 3
	run.research.manual_queue = 2
	# Дрон: инвентарь и очередь крафта.
	run.drone.inventory.add(_item(&"iron_ingot"), 50)
	run.drone.crafting.enqueue(Registry.get_hand_recipe(Registry.get_building(&"conveyor").item.index), 5)
	return run


func world_to_gateway(run: Run, gate: GatewayBuilding, copper: int) -> void:
	var p := run.planet
	var port := gate.get_input_tile()
	(p.buildings.place(Registry.get_building(&"container"), port + Vector2i(-3, 0), 0, true) as StorageBuilding).inventory.add(copper, 300)
	p.buildings.place(Registry.get_building(&"unloader"), port + Vector2i(-2, 0), 0, true)
	Worlds.conveyor_line(p, port + Vector2i(-1, 0), 2, GameConst.Dir.RIGHT)
	var pair := run.get_gateway(run.base)
	var out := pair.get_output_tile()
	Worlds.conveyor_line(run.base, out, 2, GameConst.Dir.LEFT)
	run.base.buildings.place(Registry.get_building(&"container"), out + Vector2i(-2, 0), 0, true)


## Путь к первому отличию двух значений (для сообщения теста).
func _first_diff(a: Variant, b: Variant, path: String = "") -> String:
	if typeof(a) != typeof(b):
		return path + " (тип)"
	if a is Dictionary:
		for key in (a as Dictionary):
			if not (b as Dictionary).has(key):
				return "%s/%s (нет ключа)" % [path, key]
			var d := _first_diff(a[key], b[key], "%s/%s" % [path, key])
			if not d.is_empty():
				return d
		return ""
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return path + " (размер)"
		for i in (a as Array).size():
			var d := _first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if not d.is_empty():
				return d
		return ""
	return "" if a == b else path


func _test_save_roundtrip_and_determinism() -> void:
	var run := _build_save_run()
	for i in 450:
		run.step()
	var saved := SaveIO.run_to_dict(run)
	var bytes := var_to_bytes(saved)
	var loaded := SaveIO.run_from_dict(bytes_to_var(bytes))
	var reloaded := SaveIO.run_to_dict(loaded)
	var diff := _first_diff(saved, reloaded)
	_check(diff.is_empty() and var_to_bytes(reloaded) == bytes, "сохранение → загрузка → то же состояние (отличие: %s)" % diff)
	_check(loaded.drone.world == loaded.planet and loaded.link.planet_gateway != null and loaded.link.planet_gateway.link == loaded.link, "дрон, шлюз и связь восстановлены")
	for i in 600:
		run.step()
		loaded.step()
	var a := SaveIO.run_to_dict(run)
	var b := SaveIO.run_to_dict(loaded)
	diff = _first_diff(a, b)
	_check(diff.is_empty() and var_to_bytes(a) == var_to_bytes(b), "после загрузки игра идёт так же, как без неё (отличие: %s)" % diff)
	var delivered := 0
	for building in run.base.buildings.get_all():
		if building is StorageBuilding:
			delivered += (building as StorageBuilding).inventory.count(_item(&"hematite"))
	_check(delivered > 0, "в сценарии гематит дошёл через шлюз (%d)" % delivered)
	_check(run.planet.fluids.networks.size() > 0 and run.planet.power.networks.size() >= 2, "в сценарии работают сети труб и электричества")
	run.dispose()
	loaded.dispose()


## Индексы предметов в сохранении переносятся по таблице id, если порядок предметов изменился.
func _test_save_remap() -> void:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	var copper := _item(&"hematite")
	var lead := _item(&"brick")
	var storage := run.planet.buildings.place(Registry.get_building(&"container"), Vector2i(4, 4), 0, true) as StorageBuilding
	storage.inventory.add(copper, 50)
	storage.inventory.add(lead, 20)
	var belt := run.planet.buildings.place(Registry.get_building(&"conveyor"), Vector2i(10, 4), 0, true)
	run.planet.simulation.conveyors.import_items(belt, {"items": PackedInt32Array([copper, lead]), "prog": PackedInt32Array([800, 200])})
	run.drone.inventory.clear()
	run.drone.inventory.add(copper, 7)
	var data := SaveIO.run_to_dict(run)
	# Изображаем сохранение из версии, где гематит и кирпич стояли в другом порядке.
	var table: PackedStringArray = data["tables"]["items"]
	table[copper] = "brick"
	table[lead] = "hematite"
	data["tables"]["items"] = table
	for entry in (data["planet"]["buildings"] as Array):
		var state: Dictionary = entry["state"]
		for key in ["slot_items", "items"]:
			if state.has(key):
				var arr: PackedInt32Array = state[key]
				for i in arr.size():
					if arr[i] == copper:
						arr[i] = lead
					elif arr[i] == lead:
						arr[i] = copper
				state[key] = arr
	var drone_slots: Dictionary = (data["players"][0] as Dictionary)["drone"]["inventory"]
	var drone_items: PackedInt32Array = drone_slots["slot_items"]
	for i in drone_items.size():
		if drone_items[i] == copper:
			drone_items[i] = lead
	drone_slots["slot_items"] = drone_items
	var loaded := SaveIO.run_from_dict(data)
	var moved := loaded.planet.buildings.get_at(Vector2i(4, 4)) as StorageBuilding
	_check(moved != null and moved.inventory.count(copper) == 50 and moved.inventory.count(lead) == 20, "склад: гематит и кирпичи на своих местах после переноса индексов")
	var contents := PackedInt32Array()
	contents.resize(Registry.items.size())
	contents.fill(0)
	loaded.planet.buildings.get_at(Vector2i(10, 4)).collect_contents(contents)
	_check(contents[copper] == 1 and contents[lead] == 1, "лента: предметы перенесены по id")
	_check(loaded.drone.inventory.count(copper) == 7, "инвентарь дрона перенесён по id")
	_check(not SaveContext.is_remapping(), "контекст переноса закрыт после загрузки")
	run.dispose()
	loaded.dispose()


func _test_save_files() -> void:
	var run := _build_save_run()
	for i in 60:
		run.step()
	var name := "__test_save__"
	_check(SaveIO.save_run(run, name) == OK, "сохранение в файл")
	var path := SaveIO.slot_path(name)
	var header := SaveIO.read_header(path)
	_check(header.get("name") == name and float(header.get("playtime", 0.0)) > 0.0 and header.get("path") == path, "заголовок читается без распаковки")
	var found := false
	for h in SaveIO.list_saves():
		found = found or h.get("path") == path
	_check(found, "сохранение в списке")
	var loaded := SaveIO.load_run(path)
	_check(loaded != null and var_to_bytes(SaveIO.run_to_dict(loaded)) == var_to_bytes(SaveIO.run_to_dict(run)), "загрузка из файла даёт то же состояние")
	_check(SaveIO.load_run("res://icon.svg") == null, "чужой файл не загружается")
	SaveIO.delete_save(path)
	_check(not FileAccess.file_exists(path), "сохранение удаляется")
	run.dispose()
	if loaded != null:
		loaded.dispose()


# --- Этап 9: угроза и враги ---

func _test_enemy_data() -> void:
	_check(Registry.enemies.size() == 3, "три типа врагов, есть %d" % Registry.enemies.size())
	for id in [&"crawler", &"soldier", &"brute"]:
		_check(Registry.get_enemy(id) != null, "враг %s загружен" % id)
	var normal: PlanetTypeDef = null
	var wasteland: PlanetTypeDef = null
	for t in Registry.planet_types:
		if t.id == &"normal":
			normal = t
		elif t.id == &"wasteland":
			wasteland = t
	_check(normal != null and normal.threat != null and not normal.safe, "у обычной планеты есть кривая угрозы")
	_check(wasteland != null and wasteland.safe, "пустошь безопасна")
	_check(ArtRegistry.enemy_atlas != null and ArtRegistry.enemy_atlas.get_width() == ArtRegistry.ENEMY_CELL * 3, "атлас врагов собран")
	var conveyor := Registry.get_building(&"conveyor")
	var container := Registry.get_building(&"container")
	var gate := Registry.get_building(&"central_gateway")
	_check(not conveyor.solid and conveyor.get_path_cost() == 1 and conveyor.get_max_health() > 0.0, "лента проходима для врагов и имеет прочность")
	_check(container.solid and container.get_path_cost() > 8, "склад твёрдый, проход сквозь него дорог")
	_check(gate.get_max_health() >= 1000.0, "у шлюза большая прочность")
	var threat := normal.threat
	_check(threat.get_gap_ticks(1) > threat.get_gap_ticks(3) and threat.get_gap_ticks(40) == 0, "затишья сокращаются и исчезают")
	_check(threat.get_spawn_ticks(1) < threat.get_spawn_ticks(5), "время появления растёт с волной")
	_check(threat.get_budget(2, 0.0) > threat.get_budget(1, 0.0) and threat.get_budget(1, 5.0) > threat.get_budget(1, 0.0),
		"бюджет растёт с волной и временем")


func _test_building_damage() -> void:
	var world := Worlds.empty_world(16, 8, false)
	var copper := _item(&"hematite")
	var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(4, 2), 0, true) as StorageBuilding
	storage.inventory.add(copper, 40)
	_check(storage.health == storage.get_max_health() and not storage.is_damaged(), "новое здание с полной прочностью")
	var destroyed := [0]
	world.building_destroyed.connect(func(_def: BuildingDef, _rect: Rect2i) -> void: destroyed[0] += 1)
	var before := world.drone.inventory.count(copper)
	world.damage_building(storage, 100.0)
	_check(storage.health == storage.get_max_health() - 100.0 and world.damaged.has(storage.id), "урон уменьшает прочность, здание повреждено")
	world.damage_building(storage, 1000.0)
	_check(world.buildings.get_at(Vector2i(4, 2)) == null and destroyed[0] == 1 and world.destroyed_count == 1, "при нуле здание разрушено")
	_check(world.drone.inventory.count(copper) == before and world.damaged.is_empty(), "разрушение без возврата: содержимое потеряно")
	var belt := world.buildings.place(Registry.get_building(&"conveyor"), Vector2i(8, 2), 0, true)
	world.damage_building(belt, 10.0)
	world.drone.position = Vector2(8.5, 2.5) * GameConst.TILE_SIZE
	_check(world.damaged.has(belt.id) and world.demolish(belt) and world.damaged.is_empty(), "снесённое игроком повреждённое здание уходит из списка повреждённых")
	var belt2 := world.buildings.place(Registry.get_building(&"conveyor"), Vector2i(9, 2), 0, true)
	world.damage_building(belt2, 5.0)
	var saved := SaveIO.world_to_dict(world)
	var entry: Dictionary = (saved["buildings"] as Array)[0]
	_check(entry.has("hp") and float(entry["hp"]) == belt2.health, "прочность повреждённого здания пишется в сохранение")
	world.dispose()


## Мир с тестовой картой: скальная стена с проходом, шлюз справа.
func _flow_world(width: int, height: int, wall_x: int, gap_y: int) -> GameWorld:
	var map := LevelMap.new(width, height, Registry.get_floor(&"stone").index)
	var rock := Registry.get_floor(&"rock").index
	for y in height:
		if y != gap_y:
			map.set_floor(wall_x, y, rock)
	var world := GameWorld.create(null, map, false)
	world.place_gateway(Registry.get_building(&"central_gateway") as GatewayDef, Vector2i(width - 5, height / 2 - 1))
	return world


func _follow_path(flow: FlowField, start: Vector2i, limit: int = 500) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var tile := start.y * flow.width + start.x
	for i in limit:
		var next := flow.best_neighbor(tile)
		if next < 0:
			break
		tile = next
		path.append(Vector2i(tile % flow.width, tile / flow.width))
	return path


func _test_flow_field() -> void:
	var world := _flow_world(24, 14, 10, 12)
	var flow := world.ensure_flow()
	var gate := world.gateway
	_check(flow.get_dist(gate.origin) == 0 and flow.get_dist(Vector2i(2, 6)) < FlowField.INF, "до шлюза есть путь")
	_check(flow.get_dist(Vector2i(10, 3)) == FlowField.INF and flow.blocked[3 * 24 + 10] == FlowField.ROCK, "скала непроходима")
	var path := _follow_path(flow, Vector2i(2, 6))
	_check(path.has(Vector2i(10, 12)) and gate.get_rect().has_point(path[path.size() - 1]), "путь идёт через проход в стене к шлюзу")
	var before := flow.get_dist(Vector2i(2, 6))
	var version := flow.version
	var blocker := world.buildings.place(Registry.get_building(&"stone_wall"), Vector2i(10, 12), 0, true)
	_check(flow.is_dirty() and flow.blocked[12 * 24 + 10] == FlowField.SOLID, "твёрдая постройка помечает поле грязным")
	Worlds.run_ticks(world, 2)
	_check(flow.version > version and flow.get_dist(Vector2i(2, 6)) == before + blocker.def.get_path_cost() - 1,
		"постройка в проходе проходима с ценой")
	var belt := world.buildings.place(Registry.get_building(&"conveyor"), Vector2i(12, 6), 0, true)
	_check(not flow.is_dirty() and flow.blocked[6 * 24 + 12] == FlowField.OPEN, "лента не перегораживает путь")
	world.buildings.remove(belt, true)
	world.buildings.remove(blocker, true)
	Worlds.run_ticks(world, 2)
	_check(flow.get_dist(Vector2i(2, 6)) == before, "после сноса цена пути прежняя")
	world.dispose()

	# Большая карта считается порциями: пока идёт пересчёт, враги пользуются старым полем.
	var big := _flow_world(220, 160, 100, 20)
	var big_flow := big.ensure_flow()
	var old_dist := big_flow.get_dist(Vector2i(5, 80))
	big.buildings.place(Registry.get_building(&"container"), Vector2i(100, 20), 0, true)
	big_flow.update()
	_check(big_flow.is_computing() and big_flow.get_dist(Vector2i(5, 80)) == old_dist, "пересчёт идёт порциями, старое поле действует")
	var ticks := 1
	while big_flow.is_computing() and ticks < 100:
		big_flow.update()
		ticks += 1
	_check(not big_flow.is_computing() and ticks >= 5 and big_flow.get_dist(Vector2i(5, 80)) > old_dist,
		"пересчёт закончился за %d тиков, новое поле учитывает постройку" % ticks)
	big.dispose()


## Угольный бур 1×1: жжёт топливо вместо тока, на угле сам берёт себе сколько нужно,
## малахит не берёт и работает вчетверо медленнее электробура.
func _test_coal_drill() -> void:
	var def := Registry.get_building(&"coal_drill") as DrillDef
	var electric := Registry.get_building(&"drill") as DrillDef
	var hematite := Registry.get_ore(&"hematite")
	_check(def.size == 1 and def.power_use == 0.0 and def.fuel_use > 0.0, "угольный бур 1×1 без электричества")
	_check(def.tier == 1 and Registry.get_ore(&"malachite").hardness > def.tier, "малахит угольному буру не по зубам")
	var slow := def.seconds_per_item(hematite, 1)
	var fast := electric.seconds_per_item(hematite, 4)
	_check(absf(slow / fast - 4.0) < 0.01, "вчетверо медленнее электробура на четырёх тайлах (%.2f с против %.2f с)" % [slow, fast])

	# Гематит: топливо нужно подвозить, добыча уходит на выход.
	var map := LevelMap.new(32, 16, Registry.get_floor(&"stone").index)
	map.set_ore(4, 4, Registry.get_ore(&"hematite").index + 1)
	map.set_ore(10, 4, Registry.get_ore(&"coal").index + 1)
	var world := GameWorld.create(null, map, true)
	var iron_drill := world.buildings.place(def, Vector2i(4, 4), GameConst.Dir.RIGHT, true) as Drill
	Worlds.run_ticks(world, 120)
	_check(iron_drill.buffer == 0 and iron_drill.get_status() == Building.Status.NO_FUEL, "без топлива угольный бур стоит")
	var coal := _item(&"coal")
	_check(iron_drill.accept_item(null, coal), "бур принимает уголь")
	iron_drill.handle_item(null, coal)
	Worlds.run_ticks(world, roundi(slow * GameConst.TICK_RATE) + 2)
	_check(iron_drill.buffer > 0 and iron_drill.total_fuel() == 0, "на угле бур добыл гематит (%d)" % iron_drill.buffer)
	_check(not iron_drill.accept_item(null, _item(&"iron_ingot")), "не топливо бур не принимает")

	# Уголь: бур сам набирает топливо до вместимости, дальше отдаёт наружу.
	var coal_drill := world.buildings.place(def, Vector2i(10, 4), GameConst.Dir.RIGHT, true) as Drill
	var sink := _sink(world, Vector2i(11, 4))
	coal_drill.handle_item(null, coal)
	Worlds.run_ticks(world, roundi(slow * (def.fuel_capacity + 4) * GameConst.TICK_RATE))
	_check(coal_drill.total_fuel() == def.fuel_capacity, "бур набрал себе топлива до вместимости (%d)" % coal_drill.total_fuel())
	_check(sink.received > 0, "остальной уголь ушёл на выход (%d)" % sink.received)

	# Топливо и горение переживают сохранение.
	var state := coal_drill.save_state()
	var copy := world.buildings.place(def, Vector2i(10, 8), GameConst.Dir.RIGHT, true) as Drill
	copy.load_state(state)
	_check(copy.total_fuel() == coal_drill.total_fuel() and is_equal_approx(copy.fuel_energy, coal_drill.fuel_energy),
		"топливо бура сохраняется")
	world.dispose()


## Ветка дрона: каждая ступень исследования меняет характеристику; загрузка дрона не лечит.
func _test_drone_upgrades() -> void:
	var run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var drone := run.drone
	var d := drone.def
	var hematite := Registry.get_ore(&"hematite")
	_check(drone.get_speed() == d.speed and drone.get_max_health() == d.health, "без исследований характеристики дрона базовые")
	var base_ticks := drone.get_mine_ticks(hematite)
	run.research.done[&"drone_speed_1"] = true
	run.research.done[&"drone_speed_2"] = true
	run.research.done[&"drone_mining_1"] = true
	run.research.done[&"drone_gun_1"] = true
	run.research.done[&"drone_repair_1"] = true
	run.research.done[&"drone_health_1"] = true
	run.apply_research_effects()
	_check(is_equal_approx(drone.get_speed(), d.speed + 2.0 * d.speed_step), "две ступени скорости: %.1f тайла/с" % drone.get_speed())
	_check(drone.get_mine_ticks(hematite) < base_ticks, "добыча быстрее: %d тиков вместо %d" % [drone.get_mine_ticks(hematite), base_ticks])
	_check(is_equal_approx(drone.get_gun_damage(), d.gun_damage + d.gun_damage_step), "урон автопушки вырос")
	_check(is_equal_approx(drone.get_repair_per_second(), d.repair_per_second + d.repair_step), "ремонт быстрее")
	_check(is_equal_approx(drone.get_max_health(), d.health + d.health_step) and is_equal_approx(drone.health, drone.get_max_health()),
		"прочность выросла, дрон подлечен на прирост")
	# Раненый дрон после загрузки не лечится сам.
	drone.health = 20.0
	var loaded := SaveIO.run_from_dict(bytes_to_var(var_to_bytes(SaveIO.run_to_dict(run))))
	_check(is_equal_approx(loaded.drone.health, 20.0) and is_equal_approx(loaded.drone.get_max_health(), drone.get_max_health()),
		"после загрузки здоровье прежнее, улучшения на месте")
	loaded.dispose()
	var creative := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), true)
	_check(creative.drone.get_speed() == d.speed + ResearchState.max_effect(&"drone_speed") * d.speed_step,
		"в творческом режиме открыты все ступени")
	creative.dispose()
	run.dispose()


## Очередь исследований: до QUEUE_MAX штук, недоступные ждут, завершённые выбрасываются.
func _test_research_queue() -> void:
	var state := ResearchState.new()
	state.done[&"electricity"] = true
	_check(state.set_active(&"mining"), "текущее — «Электробур»")
	# Промышленность пока недоступна (нужен Электробур), но в очередь встаёт.
	_check(state.queue_add(&"industry") and state.queue_add(&"defense"), "в очередь встают и недоступные исследования")
	_check(state.queue_position(&"industry") == 1 and state.queue_position(&"defense") == 2, "порядок очереди сохраняется")
	var extra := [&"fluid_handling", &"underground", &"drone_speed_1", &"logistics", &"gateway_items"]
	var added := 0
	for id in extra:
		if state.queue_add(id):
			added += 1
	_check(state.queue.size() == ResearchState.QUEUE_MAX and added == ResearchState.QUEUE_MAX - 2,
		"в очередь помещается %d исследований" % ResearchState.QUEUE_MAX)
	state.queue_remove(&"industry")
	_check(state.queue_position(&"industry") == 0 and state.queue.size() == ResearchState.QUEUE_MAX - 1, "из очереди можно убрать")
	_check(state.queue_add(&"industry") and state.queue.back() == &"industry", "освободившееся место снова занимается")
	# Завершаем «Электробур»: из очереди берётся первое доступное.
	var taken: Array[StringName] = []
	state.next_taken.connect(func(r: ResearchDef) -> void: taken.append(r.id))
	var mining := Registry.get_research(&"mining")
	for i in mining.cost_amount:
		state.add_kit(mining.cost_item.index)
	_check(state.is_done(&"mining") and taken.size() == 1 and state.active == taken[0], "после завершения выбрано следующее из очереди")
	_check(not state.queue.has(state.active), "взятое из очереди убрано из неё")
	# Выбор руками убирает исследование из очереди.
	var queued: StringName = state.queue[0]
	state.set_active(queued)
	_check(state.queue_position(queued) == 0, "выбранное руками уходит из очереди")


## Протягивание труб: препятствия перекрываются парой подземных, а ряд подземных ставится
## с наибольшим шагом (как опоры ЛЭП).
func _test_pipe_dragging() -> void:
	var world := Worlds.empty_world(40, 12)
	var pipe_def := Registry.get_building(&"pipe")
	var under_def := Registry.get_building(&"underground_pipe") as FluidBuildingDef
	var y := 5
	# Стена из трёх построек поперёк трассы.
	for x in range(6, 9):
		world.buildings.place(Registry.get_building(&"stone_wall"), Vector2i(x, y), 0, true)
	var path := LinePlanner.l_path(Vector2i(3, y), Vector2i(14, y), true, GameConst.Dir.RIGHT)
	var budget := world.drone.inventory.make_budget()
	var ghosts := LinePlanner.plan_pipe(world, pipe_def, path, budget)
	var under_ghosts: Array[PlacementPreview.Ghost] = []
	for g in ghosts:
		if g.def == under_def:
			under_ghosts.append(g)
	_check(under_ghosts.size() == 2, "через стену встают две подземные трубы (%d)" % under_ghosts.size())
	if under_ghosts.size() == 2:
		_check(under_ghosts[0].origin == Vector2i(5, y) and under_ghosts[1].origin == Vector2i(9, y),
			"вход перед стеной и выход сразу за ней (%s → %s)" % [under_ghosts[0].origin, under_ghosts[1].origin])
		_check(under_ghosts[0].rotation == GameConst.Dir.RIGHT and under_ghosts[1].rotation == GameConst.Dir.LEFT,
			"выход развёрнут навстречу входу")
	for g in ghosts:
		_check(g.origin.x < 6 or g.origin.x > 8, "на тайлы стены труба не ставится (%s)" % g.origin)

	# Ряд подземных труб: пара на всю дальность, следующая пара сразу за ней.
	var line := LinePlanner.plan_underground(world, under_def, Vector2i(2, 9), Vector2i(2 + under_def.underground_range + 3, 9),
		GameConst.Dir.RIGHT, budget)
	_check(line.size() == 4, "ряд подземных труб: две пары (%d труб)" % line.size())
	if line.size() == 4:
		_check(line[1].origin.x - line[0].origin.x == under_def.underground_range, "пара на наибольшем расстоянии")
		_check(line[2].origin.x - line[1].origin.x == 1, "следующая пара начинается вплотную к прошлой")
		_check(line[0].rotation == GameConst.Dir.RIGHT and line[1].rotation == GameConst.Dir.LEFT
			and line[2].rotation == GameConst.Dir.RIGHT, "повороты чередуются")
	world.dispose()


## Творческие блоки: источник предметов, энергии и жидкости, поглотитель; вне творческого режима не ставятся.
func _test_creative_blocks() -> void:
	var world := Worlds.empty_world(32, 16, true)
	var item_def := Registry.get_building(&"creative_item_source") as CreativeBlockDef
	var power_def := Registry.get_building(&"creative_power_source") as CreativeBlockDef
	var fluid_def := Registry.get_building(&"creative_fluid_source") as CreativeBlockDef
	var void_def := Registry.get_building(&"creative_void") as CreativeBlockDef
	_check(item_def.creative_only and power_def.creative_only and fluid_def.creative_only and void_def.creative_only,
		"творческие блоки помечены creative_only")
	var normal := Worlds.empty_world(16, 12, false)
	_check(normal.check_build(item_def, Vector2i(4, 4), 0) == BuildingManager.Check.LOCKED, "вне творческого режима блок не ставится")
	_check(world.check_build(item_def, Vector2i(4, 4), 0) == BuildingManager.Check.OK, "в творческом режиме ставится")
	normal.dispose()

	# Источник предметов: выдаёт выбранное с выбранной скоростью.
	var source := world.buildings.place(item_def, Vector2i(4, 4), 0, true) as CreativeBlock
	var stone := _item(&"stone")
	world.configure(source, Vector2i(stone, 2))
	var sink := _sink(world, Vector2i(5, 4))
	Worlds.run_ticks(world, 10 * GameConst.TICK_RATE)
	var rate := float(sink.received) / 10.0
	_check(absf(rate - item_def.get_rate(2)) <= 0.6, "источник выдаёт %.1f предм./с (ожидалось %.0f)" % [rate, item_def.get_rate(2)])

	# Поглотитель принимает всё.
	var sink_block := world.buildings.place(void_def, Vector2i(10, 4), 0, true) as CreativeBlock
	_check(sink_block.accept_item(null, stone) and sink_block.accept_item(null, _item(&"coal")), "поглотитель принимает любые предметы")

	# Источник энергии кормит потребителя без топлива.
	var assembler := world.buildings.place(Registry.get_building(&"assembler"), Vector2i(4, 9), 0, true) as Crafter
	world.configure(assembler, &"gear")
	for i in 20:
		assembler.handle_item(null, _item(&"iron_ingot"))
	var power := world.buildings.place(power_def, Vector2i(8, 9), 0, true) as CreativeBlock
	world.buildings.place(Registry.get_building(&"small_power_pole"), Vector2i(7, 10), 0, true)
	Worlds.run_ticks(world, 60)
	_check(power.power_net != null and assembler.power_net == power.power_net, "источник энергии и сборщик в одной сети")
	_check(is_equal_approx(assembler.get_power_satisfaction(), 1.0), "сборщик питается от творческого источника")

	# Источник жидкости наливает в трубу, поглотитель её выкачивает.
	var water := Registry.get_fluid(&"water").index
	var fluid_source := world.buildings.place(fluid_def, Vector2i(14, 4), 0, true) as CreativeBlock
	world.configure(fluid_source, Vector2i(water, 2))
	Worlds.conveyor_line(world, Vector2i(15, 4), 1, GameConst.Dir.RIGHT, &"pipe")
	Worlds.run_ticks(world, 60)
	var net := world.fluids.get_port_network(fluid_source, 0)
	_check(net != null and net.fluid == water and net.amount > 0.0, "источник налил воду в трубу (%.0f)" % (net.amount if net != null else 0.0))
	world.dispose()


## Шлюз начинает забег 2×2 и вырастает до 4×4 после всех «Портов шлюза»; центр не съезжает.
func _test_gateway_growth() -> void:
	var run := Run.create(null, LevelMap.new(64, 48, Registry.get_floor(&"stone").index), false)
	var gate := run.get_gateway(run.planet)
	var pair := run.get_gateway(run.base)
	var def := gate.get_gateway_def()
	_check(def.start_size == 2 and def.grown_size == 4, "в данных два размера шлюза")
	_check(gate.get_size() == 2 and pair.get_size() == 2, "в начале забега шлюз 2×2")
	var center := gate.origin + Vector2i.ONE
	var pad := run.planet.pad_rect
	_check(pad.position + pad.size / 2 == center, "площадка симметрична вокруг центра шлюза")
	_check(run.planet.buildings.get_at(gate.origin) == gate and run.planet.buildings.get_at(gate.origin + Vector2i.ONE) == gate
		and run.planet.buildings.get_at(gate.origin + Vector2i(2, 0)) == null, "шлюз занимает ровно 2×2")
	var steps := ResearchState.max_effect(&"gateway_ports")
	for research in Registry.researches:
		if research.effects.has(&"gateway_ports"):
			run.research.done[research.id] = true
	run.research._effects_signature = -1
	run.apply_research_effects()
	_check(steps > 0 and gate.get_size() == 4 and pair.get_size() == 4, "после всех «Портов шлюза» шлюз 4×4")
	_check(gate.origin + Vector2i(2, 2) == center, "центр шлюза остался на месте")
	_check(run.planet.buildings.get_at(gate.origin + Vector2i(3, 3)) == gate, "новые тайлы заняты шлюзом")
	_check(gate.port_count() == 3, "открыто три порта")
	var tiles := gate.get_input_tiles()
	var rect := gate.get_rect()
	for tile in tiles:
		_check(not rect.has_point(tile) and rect.grow(1).has_point(tile), "порт %s примыкает к шлюзу" % tile)
	# Размер переживает сохранение.
	var loaded := SaveIO.run_from_dict(bytes_to_var(var_to_bytes(SaveIO.run_to_dict(run))))
	var loaded_gate := loaded.get_gateway(loaded.planet)
	_check(loaded_gate.get_size() == 4 and loaded_gate.origin == gate.origin, "размер шлюза сохраняется")
	loaded.dispose()
	run.dispose()


## Shift-обмен: забрать продукцию завода и загрузить в него всё подходящее.
func _test_quick_transfer() -> void:
	var world := Worlds.empty_world(24, 16, false)
	var inv := world.drone.inventory
	var furnace := world.buildings.place(Registry.get_building(&"furnace"), Vector2i(6, 6), 0, true) as Crafter
	var hematite := _item(&"hematite")
	var coal := _item(&"coal")
	inv.add(hematite, 40)
	inv.add(coal, 10)
	inv.add(_item(&"gear"), 5)
	var put := world.player_fill(furnace)
	_check(put > 0 and furnace.total_fuel() > 0 and furnace.inputs[hematite] > 0, "Shift+ПКМ кладёт и сырьё, и топливо (%d)" % put)
	_check(inv.count(_item(&"gear")) == 5, "негодные предметы остаются у дрона")
	Worlds.run_ticks(world, 20 * GameConst.TICK_RATE)
	var iron := _item(&"iron_ingot")
	_check(furnace.outputs[iron] > 0, "печь наплавила железа")
	var before_inputs := furnace.inputs[hematite]
	var taken := world.player_take_output(furnace)
	_check(taken > 0 and inv.count(iron) == taken, "Shift+ЛКМ забирает продукцию (%d)" % taken)
	_check(furnace.outputs[iron] == 0 and furnace.inputs[hematite] == before_inputs and furnace.total_fuel() > 0,
		"сырьё и топливо остаются в печи")
	world.dispose()


## Слой труб перерисовывает чанк только при перестройке сети или заметном изменении заполнения.
func _test_pipe_layer() -> void:
	var world := Worlds.empty_world(32, 16, true)
	var layer := PipeLayer.new()
	add_child(layer)
	layer.setup(world)
	for x in range(4, 12):
		world.buildings.place(Registry.get_building(&"pipe"), Vector2i(x, 5), 0, true)
	world.fluids.update()
	layer._process(0.0)
	_check(layer.get_view_count() >= 1 and layer.redraw_count > 0, "трубы разложены по чанкам (%d)" % layer.get_view_count())
	var after_first := layer.redraw_count
	layer._process(0.0)
	layer._process(0.0)
	_check(layer.redraw_count == after_first, "без изменений чанки не перерисовываются")
	var net := world.fluids.get_pipe_network(world.buildings.get_at(Vector2i(4, 5)))
	net.insert(Registry.get_fluid(&"water").index, net.capacity)
	layer._process(0.0)
	_check(layer.redraw_count > after_first, "заполнение сети вызывает перерисовку")
	var filled := layer.redraw_count
	world.buildings.place(Registry.get_building(&"pipe"), Vector2i(12, 5), 0, true)
	world.fluids.update()
	layer._process(0.0)
	_check(layer.redraw_count > filled, "новая труба вызывает перерисовку")
	layer.queue_free()
	world.dispose()


## Творческий режим: полигон виден только там, «Исследовать заново» и «Открыть всё».
func _test_creative_research() -> void:
	var sandbox := Registry.get_research(&"sandbox")
	_check(sandbox != null and sandbox.creative_only and sandbox.cost_amount > 1000, "полигон — бесконечное творческое исследование")
	var normal := Run.create(null, LevelMap.new(32, 24, Registry.get_floor(&"stone").index), false)
	_check(not normal.research.sandbox and not normal.research.is_available(sandbox), "в обычном забеге полигона нет")
	normal.dispose()
	var run := Run.create(null, LevelMap.new(32, 24, Registry.get_floor(&"stone").index), true)
	var state := run.research
	_check(state.sandbox and state.is_available(sandbox), "в творческом забеге полигон доступен")
	_check(state.count_effect(&"pad_size") == ResearchState.max_effect(&"pad_size"), "в творческом режиме эффекты открыты")
	state.reset_progress()
	run.apply_research_effects()
	_check(not state.creative and state.count_effect(&"pad_size") == 0 and state.done.is_empty(),
		"«Исследовать заново» возвращает дерево в начало")
	_check(run.get_pad_size() == run.run_def.pad_start_size, "площадка вернулась к стартовому размеру")
	_check(state.is_available(Registry.get_research(&"electricity")) and not state.is_available(Registry.get_research(&"mining")),
		"после сброса доступна только «Электрика»")
	state.unlock_everything()
	run.apply_research_effects()
	_check(state.is_done(&"mining") and not state.is_done(&"sandbox") and state.creative, "«Открыть всё» закрывает дерево, кроме полигона")
	_check(state.count_effect(&"pad_size") == ResearchState.max_effect(&"pad_size"), "эффекты снова открыты")
	# Полигон принимает наборы и не заканчивается.
	state.set_active(&"sandbox")
	for i in 5:
		state.add_kit(sandbox.cost_item.index)
	_check(state.get_progress(sandbox) == 5 and not state.is_done(&"sandbox"), "полигон копит наборы и не завершается")
	run.dispose()


## Забег на двоих: у каждого свой дрон и инвентарь, исследования и улучшения — общие,
## игроки могут быть на разных этажах.
func _test_players() -> void:
	var run := _floors_run(_all_research_ids())
	_check(run.players.size() == 1 and run.local_player == run.players[0].id, "в новом забеге один игрок")
	var first := run.get_player(run.local_player)
	var second := run.add_player("Второй")
	_check(run.players.size() == 2 and second.id != first.id and second.drone != first.drone,
		"второй игрок со своим дроном")
	_check(second.drone.world == run.planet and run.planet.drones.size() == 2, "оба дрона на планете")
	_check(run.planet.drones[0].player_id < run.planet.drones[1].player_id, "дроны в мире отсортированы по id игрока")
	# Инвентари раздельные.
	var stone := _item(&"stone")
	first.drone.inventory.add(stone, 10)
	_check(first.drone.inventory.count(stone) == 10 and second.drone.inventory.count(stone) == 0, "инвентари у игроков свои")
	# Улучшения дрона общие: их даёт исследование.
	for research in Registry.researches:
		if research.effects.has(&"drone_speed"):
			run.research.done[research.id] = true
	run.research._effects_signature = -1
	run.apply_research_effects()
	_check(second.drone.get_speed() > second.drone.def.speed and is_equal_approx(first.drone.get_speed(), second.drone.get_speed()),
		"улучшения дрона общие для всех игроков")
	# Игроки на разных этажах.
	second.drone.position = run.get_gateway(run.planet).get_world_center()
	_check(run.use_gateway(second.drone) and second.drone.world == run.base, "второй игрок ушёл на подземный этаж")
	_check(run.planet.drones.size() == 1 and run.base.drones.size() == 1, "каждый мир знает своих дронов")
	_check(run.drone == first.drone and run.planet.drone == first.drone, "локальный игрок не сменился")
	run.set_local_player(second.id)
	_check(run.drone == second.drone and run.base.view_drone == second.drone, "смена локального игрока переводит взгляд")
	run.set_local_player(first.id)
	# Сохранение: оба игрока, их этажи и вещи.
	var loaded := SaveIO.run_from_dict(bytes_to_var(var_to_bytes(SaveIO.run_to_dict(run))))
	_check(loaded.players.size() == 2 and loaded.local_player == first.id, "игроки сохраняются")
	_check(loaded.get_player(first.id).drone.inventory.count(stone) == 10
		and loaded.get_player(second.id).drone.inventory.count(stone) == 0, "инвентари сохраняются по игрокам")
	_check(loaded.get_player(second.id).drone.world == loaded.base and loaded.base.drones.size() == 1,
		"игрок остался на своём этаже")
	loaded.dispose()
	# Выход игрока: его вещи падают грузом, забег продолжается.
	var before_crates := run.base.crates.size()
	run.remove_player(second.id)
	_check(run.players.size() == 1 and run.base.drones.is_empty(), "вышедший игрок убран из мира")
	_check(run.base.crates.size() >= before_crates, "вещи вышедшего не исчезли молча")
	run.dispose()


## Команды: действия игрока меняют мир только через очередь и только в тике.
func _test_commands() -> void:
	var run := _floors_run(_all_research_ids())
	var player := run.get_local_player()
	var drone := player.drone
	drone.position = Vector2(run.planet.grid.width, run.planet.grid.height) * GameConst.TILE_SIZE * 0.5
	var conveyor := Registry.get_building(&"conveyor")
	drone.inventory.add(conveyor.item.index, 10)
	var tile := drone.get_tile() + Vector2i(2, 0)
	run.submit(Command.Kind.BUILD, {"places": [{"def": "conveyor", "origin": tile, "rotation": 0, "config": null}]})
	_check(run.planet.buildings.get_at(tile) == null, "команда не меняет мир до тика")
	run.step()
	var built := run.planet.buildings.get_at(tile)
	_check(built != null and built.def == conveyor, "лента построена в тике")
	_check(drone.inventory.count(conveyor.item.index) == 9, "постройка списана у того, кто её ставил")
	# Движение и добыча — тоже команды.
	run.submit(Command.Kind.MOVE, {"dir": Vector2.RIGHT})
	run.step()
	_check(drone.move_input == Vector2.RIGHT, "команда движения дошла до дрона")
	# Снос возвращает постройку владельцу команды.
	run.submit(Command.Kind.REMOVE, {"ids": PackedInt32Array([built.id])})
	run.step()
	_check(run.planet.buildings.get_at(tile) == null and drone.inventory.count(conveyor.item.index) == 10, "снос командой вернул ленту")
	# Команда чужого игрока действует от его дрона и его инвентаря.
	var second := run.add_player("Второй")
	second.drone.position = drone.position + Vector2(GameConst.TILE_SIZE * 2, 0)
	second.drone.inventory.add(conveyor.item.index, 5)
	var tile2 := second.drone.get_tile() + Vector2i(1, 0)
	run.submit_for(second.id, Command.Kind.BUILD, {"places": [{"def": "conveyor", "origin": tile2, "rotation": 0, "config": null}]})
	run.step()
	_check(run.planet.buildings.get_at(tile2) != null, "второй игрок построил свою ленту")
	_check(second.drone.inventory.count(conveyor.item.index) == 4 and drone.inventory.count(conveyor.item.index) == 10,
		"списалось из инвентаря второго игрока")
	run.dispose()


## Порядок применения в тике не зависит от того, в каком порядке команды пришли.
func _test_command_order() -> void:
	var queue := CommandQueue.new()
	var a := Command.make(Command.Kind.MOVE, 2)
	a.seq = 0
	var b := Command.make(Command.Kind.MOVE, 1)
	b.seq = 5
	var c := Command.make(Command.Kind.MOVE, 1)
	c.seq = 2
	queue.submit(a, 10)
	queue.submit(b, 10)
	queue.submit(c, 10)
	var taken := queue.take(10)
	_check(taken.size() == 3 and taken[0] == c and taken[1] == b and taken[2] == a,
		"в тике команды идут по игроку, потом по номеру")
	_check(queue.take(10).is_empty(), "команды тика забираются один раз")
	queue.delay = 3
	queue.submit(Command.make(Command.Kind.MOVE, 1), 10)
	_check(queue.take(10).is_empty() and queue.take(13).size() == 1, "задержка сдвигает команду на нужный тик")


## Два забега с одинаковыми командами считаются одинаково (основа сетевой игры).
func _test_command_determinism() -> void:
	var first := _command_run()
	var second := _command_run()
	var conveyor := "conveyor"
	for run in [first, second]:
		var p1: Player = run.players[0]
		var p2: Player = run.players[1]
		var base_tile: Vector2i = p1.drone.get_tile()
		# В одном забеге команды подаются в одном порядке, в другом — в обратном:
		# сортировка в тике должна дать одинаковый результат.
		var order := [p1, p2] if run == first else [p2, p1]
		for step in 6:
			for p in order:
				var who: Player = p
				var tile: Vector2i = base_tile + Vector2i(2 + step, 2 if who == p1 else 4)
				run.submit_for(who.id, Command.Kind.BUILD,
					{"places": [{"def": conveyor, "origin": tile, "rotation": 0, "config": null}]})
				run.submit_for(who.id, Command.Kind.MOVE, {"dir": Vector2(0.5 if who == p1 else -0.5, 0.25)})
			for i in 5:
				run.step()
	for i in 60:
		first.step()
		second.step()
	var dump_a := var_to_bytes(SaveIO.run_to_dict(first))
	var dump_b := var_to_bytes(SaveIO.run_to_dict(second))
	_check(dump_a == dump_b, "одинаковые команды — байт в байт одинаковые забеги (%d и %d байт)" % [dump_a.size(), dump_b.size()])
	_check(first.planet.buildings.get_count() == second.planet.buildings.get_count() and first.planet.buildings.get_count() > 6,
		"оба забега построили одинаково (%d построек)" % first.planet.buildings.get_count())
	first.dispose()
	second.dispose()


## Забег на двоих с одинаковым сидом и запасом лент у обоих.
func _command_run() -> Run:
	var run := Run.create(null, LevelMap.new(64, 48, Registry.get_floor(&"stone").index), false)
	var second := run.add_player("Второй")
	var conveyor := Registry.get_building(&"conveyor")
	for p in run.players:
		p.drone.inventory.add(conveyor.item.index, 40)
		p.drone.position = run.get_gateway(run.planet).get_world_center()
	second.drone.position += Vector2(0, GameConst.TILE_SIZE * 2)
	return run


## Вход в сетевую игру: клиент получает снимок мира и своего игрока.
func _test_net_join() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	_check(host.host_run(host_run, 0, host_transport), "хост открыл игру")
	_check(host_run.command_router.is_valid(), "команды забега уходят в сеть")
	# Покрутим мир, чтобы снимок был не с нулевого тика.
	for i in 40:
		host.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
	var client := _join_client(host, host_transport, 2, "Напарник")
	_check(client.run != null, "клиенту пришёл снимок мира")
	if client.run == null:
		host.close()
		return
	_check(client.run.get_tick() == host_run.get_tick(), "тик клиента совпал с хостом (%d и %d)"
		% [client.run.get_tick(), host_run.get_tick()])
	_check(client.run.state_hash() == host_run.state_hash(), "состояние клиента совпало с хостом")
	_net_run(host, host_run, client, 20)
	_check(host_run.players.size() == 2 and client.run.players.size() == 2, "игрок добавлен у обоих (%d и %d)"
		% [host_run.players.size(), client.run.players.size()])
	_check(client.run.local_player != 1 and client.run.get_player(client.run.local_player) != null,
		"клиент играет за своего игрока")
	host.close()
	client.close()
	host_run.dispose()


## Игра по сети: команды обоих участников применяются в одном тике и мир остаётся одинаковым.
func _test_net_play() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	_net_run(host, host_run, client, 20)
	var conveyor := Registry.get_building(&"conveyor")
	var host_player: Player = host_run.players[0]
	var mate_id := client.run.local_player
	for run in [host_run, client.run]:
		for p in run.players:
			p.drone.inventory.add(conveyor.item.index, 20)
			p.drone.position = run.get_gateway(run.planet).get_world_center() + Vector2(0, GameConst.TILE_SIZE * (p.id - 1))
	var host_tile := host_player.drone.get_tile() + Vector2i(3, 0)
	var mate_tile := host_player.drone.get_tile() + Vector2i(3, 2)
	# Оба отдают команды «одновременно» — каждый со своей стороны.
	host_run.submit(Command.Kind.BUILD, {"places": [{"def": "conveyor", "origin": host_tile, "rotation": 0, "config": null}]})
	client.run.submit(Command.Kind.BUILD, {"places": [{"def": "conveyor", "origin": mate_tile, "rotation": 0, "config": null}]})
	client.run.submit(Command.Kind.MOVE, {"dir": Vector2.RIGHT})
	_net_run(host, host_run, client, 40)
	_check(host_run.planet.buildings.get_at(host_tile) != null and host_run.planet.buildings.get_at(mate_tile) != null,
		"у хоста построены обе ленты")
	_check(client.run.planet.buildings.get_at(host_tile) != null and client.run.planet.buildings.get_at(mate_tile) != null,
		"у клиента построены обе ленты")
	_check(host_run.get_player(mate_id).drone.move_input == Vector2.RIGHT, "команда движения клиента дошла до хоста")
	_check(host_run.state_hash() == client.run.state_hash(), "состояния совпадают после совместной игры")
	_check(client.run.get_tick() <= host_run.get_tick(), "клиент не обгоняет хоста")
	host.close()
	client.close()
	host_run.dispose()


## Расхождение: хост замечает разную контрольную сумму и чинит клиента снимком.
func _test_net_desync_repair() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	var notices := PackedStringArray()
	host.notice.connect(func(text: String) -> void: notices.append(text))
	var repaired := [false]
	client.run_replaced.connect(func(_fresh: Run) -> void: repaired[0] = true)
	_net_run(host, host_run, client, 20)
	# Ломаем мир клиента мимо команд — так выглядит любое расхождение.
	client.run.players[0].drone.position += Vector2(64, 0)
	_check(client.run.state_hash() != host_run.state_hash(), "состояния разъехались")
	_net_run(host, host_run, client, NetProtocol.CHECKSUM_EVERY * 2 + 20)
	_check(repaired[0], "клиент получил снимок для починки")
	_check(client.run.state_hash() == host_run.state_hash(), "после починки состояния снова совпадают")
	_check(notices.size() > 0, "хост сообщил о расхождении")
	_check(host.last_desync.begins_with("игроки"), "хост назвал разошедшуюся часть: %s" % host.last_desync)
	# После починки клиент должен остаться собой: в снимке стоит локальный игрок хоста,
	# и без set_local_player интерфейс клиента показывал бы чужой инвентарь и чужой радиус.
	var mine := client.run.get_player(client.run.local_player)
	_check(mine != null and mine.id != 1, "после починки клиент играет за себя (%d)" % client.run.local_player)
	if mine != null:
		_check(client.run.drone == mine.drone, "забег отдаёт дрона клиента")
		_check(mine.drone.world != null and mine.drone.world.drone == mine.drone,
			"мир показывает дрона клиента, а не хоста")
	host.close()
	client.close()
	host_run.dispose()


## Выход игрока: дрон остаётся стоять, вещи при нём; вернувшийся занимает своё тело.
func _test_net_leave() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	_net_run(host, host_run, client, 20)
	var mate_id := client.run.local_player
	var stone := _item(&"stone")
	host_run.get_player(mate_id).drone.inventory.add(stone, 7)
	client.run.submit(Command.Kind.MOVE, {"dir": Vector2.RIGHT})
	_net_run(host, host_run, client, 20)
	host_transport.drop(2)
	client.close()
	for i in 20:
		host.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
	var left := host_run.get_player(mate_id)
	_check(left != null and left.drone.world != null, "дрон вышедшего остался в мире")
	_check(left.drone.move_input == Vector2.ZERO, "дрон вышедшего остановлен")
	_check(left.drone.inventory.count(stone) == 7, "вещи вышедшего при нём")
	# Возвращаемся под тем же именем — занимаем своё тело.
	var again := _join_client(host, host_transport, 3, "Напарник")
	_check(again.run != null and again.run.local_player == mate_id, "вернувшийся занял своё тело (%d)"
		% (again.run.local_player if again.run != null else -1))
	_check(host_run.players.size() == 2, "новый игрок не заводится (%d)" % host_run.players.size())
	if again.run != null:
		_check(again.run.get_player(mate_id).drone.inventory.count(stone) == 7, "вещи на месте после возвращения")
	host.close()
	again.close()
	host_run.dispose()


## Подключить клиента к хосту и дождаться снимка.
func _join_client(host: NetSession, host_transport: LoopbackTransport, id: int, name: String) -> NetSession:
	var client_transport := LoopbackTransport.connect_client(host_transport, id)
	var client := NetSession.new()
	client.join_run("", 0, name, client_transport)
	for i in 10:
		host.poll()
		client.poll()
		if client.run != null:
			break
	return client


## Прокрутить сетевую игру: обе стороны опрашивают транспорт и шагают, когда можно.
func _net_run(host: NetSession, host_run: Run, client: NetSession, ticks: int) -> void:
	for i in ticks:
		host.poll()
		client.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
		client.poll()
		if client.can_step():
			client.run.step()
			client.after_step()
	# Дать клиенту догнать хоста.
	for i in 30:
		host.poll()
		client.poll()
		if client.run != null and client.can_step() and client.run.get_tick() < host_run.get_tick():
			client.run.step()
			client.after_step()


## Транспорт Steam: рукопожатие, свои номера участников, доставка и разрыв.
func _test_steam_transport() -> void:
	var fake := FakeSteam.new()
	SteamService.override_api(fake, true)
	var host_id := 76561190000000001
	var mate_id := 76561190000000002

	fake.active = host_id
	var host := SteamTransport.new()
	_check(host.host(0), "хост поднялся на Steam")
	_check(host.host_steam_id() == host_id, "хост знает свой SteamID")

	fake.active = mate_id
	var client := SteamTransport.new()
	_check(client.join(str(host_id), 0), "клиент начал подключение по SteamID")
	_check(client.is_connecting(), "пока номер не выдан — подключение не завершено")

	var host_peers := PackedInt32Array()
	host.peer_connected.connect(func(id: int) -> void: host_peers.append(id))
	var client_peers := PackedInt32Array()
	client.peer_connected.connect(func(id: int) -> void: client_peers.append(id))

	# Хост читает служебный пакет и выдаёт номер.
	fake.active = host_id
	host.poll()
	_check(host_peers.size() == 1 and host_peers[0] == 2, "хост выдал номер участника (%s)" % str(host_peers))
	fake.active = mate_id
	client.poll()
	_check(client_peers.size() == 1 and client_peers[0] == NetTransport.HOST_ID, "клиент считает хоста участником 1")
	_check(client.get_local_id() == 2 and not client.is_connecting(), "клиент узнал свой номер (%d)" % client.get_local_id())

	# Обычные пакеты ходят в обе стороны.
	var got_on_host := []
	host.packet_received.connect(func(from: int, data: PackedByteArray) -> void: got_on_host.append([from, data]))
	var got_on_client := []
	client.packet_received.connect(func(from: int, data: PackedByteArray) -> void: got_on_client.append([from, data]))
	fake.active = mate_id
	client.send(NetTransport.HOST_ID, "привет".to_utf8_buffer())
	fake.active = host_id
	host.poll()
	_check(got_on_host.size() == 1 and int(got_on_host[0][0]) == 2
		and (got_on_host[0][1] as PackedByteArray).get_string_from_utf8() == "привет", "пакет клиента дошёл до хоста")
	host.broadcast("всем".to_utf8_buffer())
	fake.active = mate_id
	client.poll()
	_check(got_on_client.size() == 1 and int(got_on_client[0][0]) == NetTransport.HOST_ID, "рассылка хоста дошла до клиента")

	# Запрос сессии принимается, разрыв доходит как отключение.
	fake.active = host_id
	fake.request_session(mate_id)
	_check(fake.accepted.has(mate_id), "хост разрешает сессию своему участнику")
	var gone := PackedInt32Array()
	host.peer_disconnected.connect(func(id: int) -> void: gone.append(id))
	fake.fail_session(mate_id)
	_check(gone.size() == 1 and gone[0] == 2, "обрыв сессии виден как выход участника")
	host.close()
	client.close()
	SteamService.override_api(null, false)


## Сетевая сессия поверх Steam-транспорта: вход в игру и совместная постройка.
func _test_steam_session() -> void:
	var fake := FakeSteam.new()
	SteamService.override_api(fake, true)
	var host_id := 76561190000000011
	var mate_id := 76561190000000012
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)

	fake.active = host_id
	var host := NetSession.new()
	_check(host.host_run(host_run, 0, SteamTransport.new()), "забег открыт через Steam")
	fake.active = mate_id
	var client := NetSession.new()
	_check(client.join_run(str(host_id), 0, "Напарник", SteamTransport.new()), "клиент подключается через Steam")

	# Пакеты ходят по очереди: перед каждым poll переключаем «кто сейчас».
	for i in 40:
		fake.active = host_id
		host.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
		fake.active = mate_id
		client.poll()
		if client.run != null and client.can_step():
			client.run.step()
			client.after_step()
	_check(client.run != null, "клиент получил мир через Steam")
	if client.run != null:
		_check(client.run.players.size() == 2 and host_run.players.size() == 2,
			"игроки сошлись (%d и %d)" % [client.run.players.size(), host_run.players.size()])
		_check(client.run.state_hash() != 0 and client.run.get_tick() > 0, "клиент считает свой забег")
	host.close()
	client.close()
	host_run.dispose()
	SteamService.override_api(null, false)


## Часы симуляции в сетевой игре: пока ждём команды хоста, накопленное время не пропадает,
## а потом тики отыгрываются. Без этого клиент отставал бы всё сильнее.
func _test_clock_waiting() -> void:
	var clock := SimClock.new()
	add_child(clock)
	var steps := [0]
	var allowed := [false]
	clock.setup(func() -> void: steps[0] += 1, func() -> bool: return allowed[0])
	# Полсекунды «в ожидании»: ни одного тика.
	for i in 30:
		clock._process(1.0 / 60.0)
	_check(steps[0] == 0, "пока хост не прислал команды, тики не считаются (%d)" % steps[0])
	# Разрешаем — накопленное время должно отыграться, а не пропасть.
	allowed[0] = true
	clock._process(1.0 / 60.0)
	_check(steps[0] > 1, "после разрешения клиент догоняет пачкой тиков (%d)" % steps[0])
	_check(steps[0] <= SimClock.MAX_TICKS_PER_FRAME, "но не больше MAX_TICKS_PER_FRAME за кадр (%d)" % steps[0])
	# Долгое ожидание не копит время бесконечно: после него не больше одной пачки.
	allowed[0] = false
	for i in 300:
		clock._process(1.0 / 60.0)
	allowed[0] = true
	var before: int = steps[0]
	for i in 3:
		clock._process(1.0 / 60.0)
	_check(steps[0] - before <= SimClock.MAX_TICKS_PER_FRAME + 3,
		"после долгого ожидания игра не рвётся вперёд (%d тиков)" % (steps[0] - before))
	clock.queue_free()

## Часы умеют идти быстрее и медленнее: на этом клиент сетевой игры догоняет хоста.
func _test_clock_scale() -> void:
	var clock := SimClock.new()
	add_child(clock)
	clock.set_process(false)
	var steps := [0]
	var scale := [1.0]
	clock.setup(func() -> void: steps[0] += 1, Callable(), func() -> float: return scale[0])
	for i in 60:
		clock._process(1.0 / 60.0)
	_check(steps[0] == GameConst.TICK_RATE, "при обычном ходе за секунду ровно тик-рейт (%d)" % steps[0])
	steps[0] = 0
	scale[0] = 2.0
	for i in 60:
		clock._process(1.0 / 60.0)
	_check(steps[0] == GameConst.TICK_RATE * 2, "с двойным темпом тиков вдвое больше (%d)" % steps[0])
	clock.queue_free()


## Один тик хоста в тестах.
func _host_step(host: NetSession, host_run: Run) -> void:
	host.poll()
	if host.can_step():
		host_run.step()
		host.after_step()


## Один «кадр» сетевой игры: хост считает тики по настоящему времени, клиент — своими часами.
## client_runs = false — у клиента кадров нет вовсе (окно свёрнуто, долгая загрузка).
func _net_frame(host: NetSession, host_run: Run, clock: SimClock, host_time: Array, dt: float,
		client_runs: bool) -> void:
	host_time[0] += dt
	while host_time[0] >= GameConst.TICK_DT:
		host_time[0] -= GameConst.TICK_DT
		_host_step(host, host_run)
	if client_runs:
		clock._process(dt)


## Часы клиента, живущие как в игре: шаг, разрешение и подстройка темпа берутся из сессии.
func _client_clock(client: NetSession) -> SimClock:
	var clock := SimClock.new()
	add_child(clock)
	clock.set_process(false)
	clock.setup(
		func() -> void:
			client.run.step()
			client.after_step(),
		func() -> bool:
			client.poll()
			return client.can_step(),
		client.time_scale)
	return clock


## Вход в игру: команда, запланированная ровно на тик снимка, не должна потеряться.
## Очередь команд в сохранение не входит, поэтому хост обязан прислать список этого тика отдельно —
## иначе новичок посчитает его пустым и разойдётся с хостом на ровном месте.
func _test_net_join_pending_tick() -> void:
	var conveyor := Registry.get_building(&"conveyor")
	var found_pending := false
	for offset in 4:
		var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
		var host_transport := LoopbackTransport.make_host()
		var host := NetSession.new()
		host.host_run(host_run, 0, host_transport)
		for i in 10:
			_host_step(host, host_run)
		var player: Player = host_run.players[0]
		player.drone.inventory.add(conveyor.item.index, 10)
		player.drone.position = host_run.get_gateway(host_run.planet).get_world_center()
		var tile := player.drone.get_tile() + Vector2i(4, 0)
		host_run.submit(Command.Kind.BUILD,
			{"places": [{"def": "conveyor", "origin": tile, "rotation": 0, "config": null}]})
		# Сдвигаем момент входа так, чтобы хотя бы раз он совпал с тиком, куда легла команда.
		for i in offset:
			_host_step(host, host_run)
		var planned: Dictionary = host.get("_planned")
		if not (planned.get(host_run.get_tick(), []) as Array).is_empty():
			found_pending = true
		var client := _join_client(host, host_transport, 2, "Напарник")
		if client.run != null:
			_net_run(host, host_run, client, 30)
			_check(client.run.planet.buildings.get_at(tile) != null,
				"вход на сдвиге %d: лента из очереди дошла до новичка" % offset)
			_check(client.run.state_hash() == host_run.state_hash(),
				"вход на сдвиге %d: состояния совпали" % offset)
			client.close()
		host.close()
		host_run.dispose()
	_check(found_pending, "проверен и тот вход, где команда лежит ровно на тике снимка")


## Клиент, у которого пропали кадры (свернули окно), должен догнать хоста, а не отстать навсегда.
## Раньше часы списывали время даже на пропущенных тиках, и отставание копилось до полной
## невозможности играть: дрон дёргался на месте, потому что команды применялись минутами позже.
func _test_net_catch_up() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	var clock := _client_clock(client)
	var host_time := [0.0]
	var dt := 1.0 / 60.0
	for i in 120:
		_net_frame(host, host_run, clock, host_time, dt, true)
	var gap := host_run.get_tick() - client.run.get_tick()
	_check(absi(gap) <= NetProtocol.CLIENT_BUFFER + 2,
		"в обычной игре клиент держится рядом с хостом (разрыв %d тиков)" % gap)
	_check(client.buffer_target() <= NetProtocol.CLIENT_BUFFER + 0.5,
		"на ровной связи запас не растёт (%.1f тика)" % client.buffer_target())
	_check(absf(clock.get_time_scale() - 1.0) < 0.2,
		"и время у него идёт почти ровно (темп %.2f)" % clock.get_time_scale())

	# Две секунды без единого кадра у клиента.
	for i in 120:
		_net_frame(host, host_run, clock, host_time, dt, false)
	client.poll()
	var behind := client.ready_ticks()
	_check(behind > 50, "после провала клиент отстал на %d тиков" % behind)
	_check(client.time_scale() > 1.5, "время клиента ускорилось, чтобы догнать (%.2f)" % client.time_scale())

	# Две секунды обычной игры — этого должно хватить, чтобы догнать.
	for i in 120:
		_net_frame(host, host_run, clock, host_time, dt, true)
	gap = host_run.get_tick() - client.run.get_tick()
	_check(absi(gap) <= NetProtocol.CLIENT_BUFFER + 2, "клиент догнал хоста (разрыв %d тиков)" % gap)
	_check(client.run.state_hash() == host_run.state_hash() or gap > 0, "мир клиента не сломался догоном")
	clock.queue_free()
	client.close()
	host.close()
	host_run.dispose()


## Если клиент отстал безнадёжно (минута без кадров), догонять ускорением бессмысленно:
## он просит снимок и продолжает с настоящего момента.
func _test_net_lost_client() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	var resynced := [false]
	client.run_replaced.connect(func(_fresh: Run) -> void: resynced[0] = true)
	var clock := _client_clock(client)
	var host_time := [0.0]
	var dt := 1.0 / 60.0
	for i in 60:
		_net_frame(host, host_run, clock, host_time, dt, true)
	# Клиента нет на связи столько, что отставание переваливает за RESYNC_BEHIND.
	# Кадр — 1/60 с, хост за него успевает полтика, поэтому кадров надо вдвое больше, чем тиков.
	for i in int(NetProtocol.RESYNC_BEHIND * 2.4):
		_net_frame(host, host_run, clock, host_time, dt, false)
	for i in 120:
		_net_frame(host, host_run, clock, host_time, dt, true)
	_check(resynced[0], "хост прислал снимок безнадёжно отставшему клиенту")
	var gap := host_run.get_tick() - client.run.get_tick()
	_check(absi(gap) <= NetProtocol.CLIENT_BUFFER + 2,
		"после снимка клиент снова рядом с хостом (разрыв %d тиков)" % gap)
	_check(client.run.state_hash() == host_run.state_hash() or gap > 0, "мир клиента цел после снимка")
	clock.queue_free()
	client.close()
	host.close()
	host_run.dispose()

## Снимок мира обязан быть детерминированным: забег и его копия из снимка, шагая рядом
## без команд, должны идти тик в тик одинаково.
##
## Это основа входа в сетевую игру и починки после расхождения: если копия хоть в чём-то
## отличается, клиент разойдётся сразу после получения снимка — и будет расходиться снова
## после каждой починки. Планета берётся настоящая, с волнами и врагами: самое сложное место.
func _test_snapshot_determinism() -> void:
	var run := Run.create_new(2024, true)
	run.set_creative_threat(true)
	# Дадим врагам появиться и разойтись по карте.
	for wave in 3:
		run.call_creative_wave()
		for i in 120:
			run.step()
	_check(run.planet.enemies.count > 0, "перед снимком на планете есть враги (%d)" % run.planet.enemies.count)
	_check(run.planet.flow != null, "перед снимком есть поле потоков")

	var copy := SaveIO.run_from_dict(SaveIO.run_to_dict(run))
	if copy == null:
		_check(false, "снимок читается обратно")
		run.dispose()
		return
	_check(copy.state_parts() == run.state_parts(), "сразу после снимка состояния совпадают")

	var broke_at := -1
	var broke_part := -1
	for i in 600:
		run.step()
		copy.step()
		var mine := run.state_parts()
		var theirs := copy.state_parts()
		if mine != theirs:
			broke_at = run.get_tick()
			for k in mini(mine.size(), theirs.size()):
				if mine[k] != theirs[k]:
					broke_part = k
					break
			break
	_check(broke_at < 0, "копия из снимка идёт вровень 600 тиков%s" % ("" if broke_at < 0
		else " — разошлось на тике %d: %s" % [broke_at, String(Run.STATE_PART_NAMES[broke_part])]))
	run.dispose()
	copy.dispose()

## Потерянный пакет с командами тика. Настоящие транспорты (особенно Steam P2P) теряют
## и переставляют пакеты, а раньше клиент молча перепрыгивал пропущенный тик: считал его пустым
## и расходился с хостом навсегда, ничем это не показывая.
func _test_net_lost_tick() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	_net_run(host, host_run, client, 20)
	var dropped := [0]
	host_transport.drop_filter = func(data: PackedByteArray) -> bool:
		if dropped[0] > 0:
			return false
		var message := NetProtocol.unpack(data)
		if NetProtocol.kind_of(message) != NetProtocol.Kind.TICK:
			return false
		dropped[0] = int(message.get("t", 0))
		return true
	_net_run(host, host_run, client, 10)
	_check(dropped[0] > 0, "пакет с командами тика потерян (тик %d)" % dropped[0])
	_check(client.run.get_tick() <= dropped[0], "клиент не перепрыгнул потерянный тик (%d при потере %d)"
		% [client.run.get_tick(), dropped[0]])
	var repaired := [false]
	client.run_replaced.connect(func(_fresh: Run) -> void: repaired[0] = true)
	_net_run(host, host_run, client, NetProtocol.GAP_TIMEOUT_POLLS + 200)
	_check(repaired[0], "клиент заметил дырку и получил свежий мир")
	_check(client.run.get_tick() > dropped[0], "после починки клиент пошёл дальше (тик %d)"
		% client.run.get_tick())
	_check(client.run.state_hash() == host_run.state_hash() or client.run.get_tick() != host_run.get_tick(),
		"мир клиента не сломан")
	host.close()
	client.close()
	host_run.dispose()


## Потерялся пакет, в котором ехало добавление игрока. Без починки клиент навсегда остаётся
## играть за дрона хоста: видит чужой инвентарь, а его команды хост отвергает — играть нельзя,
## хотя мир при этом живёт и обновляется.
func _test_net_lost_player_add() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	host_transport.drop_filter = func(data: PackedByteArray) -> bool:
		var message := NetProtocol.unpack(data)
		if NetProtocol.kind_of(message) != NetProtocol.Kind.TICK:
			return false
		for entry in (message.get("c", []) as Array):
			if int((entry as Dictionary).get("k", -1)) == int(Command.Kind.PLAYER_ADD):
				return true
		return false
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	_net_run(host, host_run, client, NetProtocol.SELF_TIMEOUT_POLLS + 300)
	_check(client.run.local_player != 1, "клиент не остался играть за дрона хоста (игрок %d)"
		% client.run.local_player)
	var mine := client.run.get_player(client.run.local_player)
	_check(mine != null and mine.drone != null, "у клиента есть свой дрон")
	if mine != null:
		_check(mine.drone.world != null and mine.drone.world.drone == mine.drone,
			"интерфейс клиента смотрит на его собственного дрона")
		# И его команды снова доходят до хоста.
		client.run.submit(Command.Kind.MOVE, {"dir": Vector2.RIGHT})
		_net_run(host, host_run, client, 40)
		var at_host := host_run.get_player(mine.id)
		_check(at_host != null and at_host.drone.move_input == Vector2.RIGHT,
			"команды клиента снова доходят до хоста")
	host.close()
	client.close()
	host_run.dispose()

## Большое сообщение через Steam. У старого P2P жёсткий предел в мегабайт на пакет, а снимок мира
## растёт вместе с фабрикой: без нарезки он в какой-то момент просто перестаёт доходить,
## и починка мира ломается молча — снаружи это выглядит как «клиент застрял».
func _test_steam_big_packet() -> void:
	var fake := FakeSteam.new()
	SteamService.override_api(fake, true)
	var host_id := 76561190000000001
	var mate_id := 76561190000000002

	fake.active = host_id
	var host := SteamTransport.new()
	host.host(0)
	fake.active = mate_id
	var client := SteamTransport.new()
	client.join(str(host_id), 0)
	fake.active = host_id
	host.poll()
	fake.active = mate_id
	client.poll()

	var got: Array[PackedByteArray] = [PackedByteArray()]
	client.packet_received.connect(func(_peer: int, data: PackedByteArray) -> void: got[0] = data)
	# Узор, а не нули: так видно и потерю куска, и перепутанный порядок.
	var pattern := PackedByteArray()
	pattern.resize(1000)
	for i in 1000:
		pattern[i] = (i * 7 + 3) % 251
	var big := PackedByteArray()
	while big.size() < SteamTransport.MAX_PACKET * 2 + 777:
		big.append_array(pattern)

	fake.active = host_id
	host.broadcast(big)
	fake.active = mate_id
	client.poll()
	_check(got[0].size() == big.size(), "большое сообщение собралось целиком (%d из %d байт)"
		% [got[0].size(), big.size()])
	_check(got[0] == big, "большое сообщение не побилось при нарезке")
	_check(fake.too_big == 0, "ни один пакет не упёрся в предел Steam (%d)" % fake.too_big)

	# Маленькие при этом ходят как раньше, без лишней обёртки.
	got[0] = PackedByteArray()
	fake.active = host_id
	host.broadcast(pattern)
	fake.active = mate_id
	client.poll()
	_check(got[0] == pattern, "обычные пакеты ходят как раньше")
	host.close()
	client.close()
	SteamService.override_api(null, false)

## Упреждение отрисовки обязано знать настоящую задержку ввода, а не константу из протокола.
##
## Команда попадает не в тик «сейчас + input_delay», а в первый ещё не разосланный тик —
## это на единицу больше; у клиента к этому добавляется дорога по сети и его собственное
## отставание. Если упреждение короче настоящей задержки, дрон на экране трогается, упирается
## в край упреждения и ждёт — это и есть рывок в начале движения.
func _test_net_input_delay() -> void:
	var host_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var host_transport := LoopbackTransport.make_host()
	var host := NetSession.new()
	host.host_run(host_run, 0, host_transport)
	var client := _join_client(host, host_transport, 2, "Напарник")
	if client.run == null:
		host.close()
		host_run.dispose()
		return
	_net_run(host, host_run, client, 30)

	# Хост: сколько тиков на самом деле проходит от команды до её применения.
	var host_player: Player = host_run.players[0]
	var sent := host_run.get_tick()
	host_run.submit(Command.Kind.MOVE, {"dir": Vector2.RIGHT})
	var applied := -1
	for i in 30:
		host.poll()
		client.poll()
		if host.can_step():
			var before := host_run.get_tick()
			host_run.step()
			host.after_step()
			if applied < 0 and host_player.drone.move_input == Vector2.RIGHT:
				applied = before
		if client.can_step():
			client.run.step()
			client.after_step()
	_check(applied > 0, "команда хоста применилась")
	_check(applied - sent > NetProtocol.INPUT_DELAY,
		"настоящая задержка больше константы протокола (%d против %d)" % [applied - sent, NetProtocol.INPUT_DELAY])
	_check(host.predicted_delay() == applied - sent,
		"хост предсказывает свою задержку точно (%d при настоящей %d)" % [host.predicted_delay(), applied - sent])
	print("tests ..   задержка ввода: хост %d тиков" % (applied - sent))

	# Клиент: то же самое, но через сеть — у него задержка своя и больше.
	var mate_id := client.run.local_player
	var mate := client.run.get_player(mate_id)
	if mate == null:
		host.close()
		client.close()
		host_run.dispose()
		return
	var sent_client := client.run.get_tick()
	client.run.submit(Command.Kind.MOVE, {"dir": Vector2.LEFT})
	var applied_client := -1
	for i in 40:
		host.poll()
		client.poll()
		if host.can_step():
			host_run.step()
			host.after_step()
		client.poll()
		if client.can_step():
			var before := client.run.get_tick()
			client.run.step()
			client.after_step()
			if applied_client < 0 and mate.drone.move_input == Vector2.LEFT:
				applied_client = before
	_check(applied_client > 0, "команда клиента применилась у него же")
	_check(absi(client.predicted_delay() - (applied_client - sent_client)) <= 1,
		"клиент предсказывает свою задержку точно (%d при настоящей %d)"
		% [client.predicted_delay(), applied_client - sent_client])
	print("tests ..   задержка ввода: клиент %d тиков" % (applied_client - sent_client))
	host.close()
	client.close()
	host_run.dispose()

## Все исследования забега завершены (этаж, шлюз и площадка — в полном размере).
func _unlock_all(run: Run) -> void:
	for research in Registry.researches:
		run.research.done[research.id] = true
	run.apply_research_effects()


func _enemy_run() -> Run:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	run.planet.threat.delay_next_wave(1000000)
	return run


func _test_enemy_attack() -> void:
	var run := _enemy_run()
	var planet := run.planet
	var gate := planet.gateway
	run.drone.position = Vector2(4, 4) * GameConst.TILE_SIZE
	_check(planet.flow != null and planet.threat != null and planet.spawn_points.size() >= 2, "у опасной планеты есть поле потоков, угроза и точки появления")
	var crawler := Registry.get_enemy(&"crawler")
	var start := gate.get_world_center() + Vector2(-12, 0) * GameConst.TILE_SIZE
	# Лента поперёк пути: враг проходит поверх.
	Worlds.conveyor_line(planet, GameConst.world_to_tile(start) + Vector2i(4, -3), 7, GameConst.Dir.DOWN)
	planet.spawn_enemy(crawler, start)
	for i in 240:
		run.step()
	var enemies := planet.enemies
	var pos := enemies.get_position(0)
	var rect := gate.get_world_rect()
	var gap := pos.distance_to(pos.clamp(rect.position, rect.end))
	_check(enemies.count == 1 and gap < crawler.radius + 8.0, "ползун дошёл до шлюза (зазор %.1f px)" % gap)
	_check(gate.health < gate.get_max_health() and planet.damaged.has(gate.id), "ползун бьёт шлюз")
	_check(planet.buildings.get_at(GameConst.world_to_tile(start) + Vector2i(4, 0)) != null, "ленту на пути враг прошёл, не сломав целиком")
	_check(enemies.damage(0, 1000.0) and enemies.count == 0 and enemies.killed == 1, "враг погибает от урона")
	run.dispose()

	# Шлюз окружён складами: пути нет — громилы ломают склад.
	run = _enemy_run()
	planet = run.planet
	gate = planet.gateway
	run.drone.position = Vector2(2, 2) * GameConst.TILE_SIZE
	var container := Registry.get_building(&"container")
	var ring := Rect2i(gate.origin - Vector2i(2, 2), Vector2i(7, 7))
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if not gate.get_rect().has_point(Vector2i(x, y)):
				planet.buildings.place(container, Vector2i(x, y), 0, true)
	Worlds.run_ticks(planet, 1)
	var brute := Registry.get_enemy(&"brute")
	for k in 3:
		planet.spawn_enemy(brute, gate.get_world_center() + Vector2(-10, -2 + 2 * k) * GameConst.TILE_SIZE)
	var hit := false
	for i in 1500:
		run.step()
		if planet.destroyed_count > 0 and gate.is_damaged():
			hit = true
			break
	_check(hit, "громилы ломают перегородивший путь склад и добираются до шлюза (разрушено %d)" % planet.destroyed_count)
	run.dispose()


func _test_threat_schedule() -> void:
	var def := ThreatDef.new()
	def.first_wave_seconds = 2.0
	def.first_gap_seconds = 4.0
	def.gap_multiplier = 0.5
	def.continuous_below_seconds = 1.0
	def.spawn_seconds = 1.0
	def.spawn_seconds_per_wave = 0.0
	def.budget_base = 3.0
	def.budget_per_wave = 1.0
	def.budget_per_minute = 0.0
	def.warning_seconds = 1.0
	def.enemy_ids = [&"crawler", &"brute"]
	def.enemy_from_wave = PackedInt32Array([1, 3])
	def.enemy_weights = PackedFloat32Array([1, 1])
	def.spawn_point_count = 2
	var run := _enemy_run()
	var planet := run.planet
	planet.threat = ThreatDirector.new(planet, def, planet.simulation.tick, 99)
	# Шлюз не должен пасть за время теста (иначе аварийный телепорт сменит планету).
	planet.gateway.health = 1.0e9
	var threat := planet.threat
	_check(threat.get_ticks_to_next_wave(planet.simulation.tick) == 60 and threat.wave == 0, "первая волна через заданное время")
	var warned := false
	for i in 60:
		warned = warned or threat.is_warning(planet.simulation.tick)
		run.step()
	_check(warned and threat.wave == 1 and threat.is_spawning(planet.simulation.tick), "предупреждение, затем волна 1")
	for i in 31:
		run.step()
	_check(planet.enemies.count == 3 and planet.enemies.spawned == 3, "волна 1 — бюджет 3 → 3 ползуна (%d)" % planet.enemies.count)
	var crawler := Registry.get_enemy(&"crawler").index
	var only_crawlers := true
	for i in planet.enemies.count:
		only_crawlers = only_crawlers and planet.enemies.types[i] == crawler
	_check(only_crawlers, "до волны 3 громил нет")
	var continuous_at := -1
	for i in 900:
		run.step()
		if threat.is_continuous() and continuous_at < 0:
			continuous_at = threat.wave
	_check(continuous_at > 1 and threat.wave > continuous_at, "затишья исчезают — волны идут встык (с волны %d, сейчас %d)" % [continuous_at, threat.wave])
	_check(planet.enemies.spawned > 20, "врагов становится больше (%d)" % planet.enemies.spawned)
	run.dispose()

	# Предел живых врагов откладывает появление.
	run = _enemy_run()
	planet = run.planet
	def.max_alive = 2
	planet.threat = ThreatDirector.new(planet, def, planet.simulation.tick, 99)
	for i in 120:
		run.step()
	_check(planet.enemies.count == 2 and planet.threat.get_pending_spawns() > 0, "сверх предела враги ждут в очереди")
	run.dispose()

	# Одинаковый сид — одинаковые волны.
	var a := _enemy_run()
	var b := _enemy_run()
	def.max_alive = 1500
	a.planet.threat = ThreatDirector.new(a.planet, def, 0, 7)
	b.planet.threat = ThreatDirector.new(b.planet, def, 0, 7)
	for i in 400:
		a.step()
		b.step()
	_check(a.planet.enemies.types.slice(0, a.planet.enemies.count) == b.planet.enemies.types.slice(0, b.planet.enemies.count)
		and a.planet.enemies.count > 0, "состав волн детерминирован")
	a.dispose()
	b.dispose()


func _test_spawn_points() -> void:
	var star_map := StarMap.new(31337, Registry.run_def, Registry.planet_types)
	var checked := 0
	for node in star_map.nodes:
		if node.type.safe or checked >= 3:
			continue
		checked += 1
		var map := PlanetGenerator.generate(node, Registry.run_def.pad_start_size)
		_check(map.spawn_points.size() == node.type.threat.spawn_point_count, "у планеты %s все точки появления (%d)" % [node.code, map.spawn_points.size()])
		var reach := PackedByteArray()
		reach.resize(map.width * map.height)
		reach.fill(0)
		SpawnPoints._flood(map.width, map.height, map.floors, reach, Vector2i(map.width / 2, map.height / 2))
		for p in map.spawn_points:
			var edge := mini(mini(p.x, p.y), mini(map.width - 1 - p.x, map.height - 1 - p.y))
			_check(edge <= SpawnPoints.INSET + SpawnPoints.SEARCH_RADIUS and reach[p.y * map.width + p.x] == 1,
				"точка %s у края и с проходом к центру" % p)
	# Посадка в скальном кольце: генератор прорубает коридоры.
	var map := LevelMap.new(60, 40, Registry.get_floor(&"stone").index)
	var rock := Registry.get_floor(&"rock").index
	for y in 40:
		for x in 60:
			var d := Vector2(x - 30, y - 20).length()
			if d > 9.0 and d < 13.0:
				map.set_floor(x, y, rock)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var found := SpawnPoints.find(60, 40, map.floors, Vector2i(30, 20), 3, rng, Registry.get_floor(&"stone").index)
	var ring_reach := PackedByteArray()
	ring_reach.resize(60 * 40)
	ring_reach.fill(0)
	SpawnPoints._flood(60, 40, map.floors, ring_reach, Vector2i(30, 20))
	var all_reachable := not found.is_empty()
	for p in found:
		all_reachable = all_reachable and ring_reach[p.y * 60 + p.x] == 1
	_check(found.size() == 3 and all_reachable, "сквозь скальное кольцо прорублены коридоры (%d точек)" % found.size())
	var no_carve := LevelMap.new(60, 40, Registry.get_floor(&"stone").index)
	for y in 40:
		for x in 60:
			var d := Vector2(x - 30, y - 20).length()
			if d > 9.0 and d < 13.0:
				no_carve.set_floor(x, y, rock)
	_check(SpawnPoints.find(60, 40, no_carve.floors, Vector2i(30, 20), 3, rng).is_empty(), "без прорубания замкнутая посадка не получает точек")
	# Безопасная планета — без угрозы.
	for node in star_map.nodes:
		if node.type.safe:
			var world := GameWorld.create(null, LevelMap.new(40, 30, Registry.get_floor(&"stone").index), false)
			var run := Run.new()
			run._setup_threat(world, node, 0)
			_check(world.threat == null and world.flow == null, "у пустоши нет угрозы")
			world.dispose()
			break


func _test_drone_death_and_crate() -> void:
	var run := _enemy_run()
	var planet := run.planet
	var drone := run.drone
	var copper := _item(&"hematite")
	drone.inventory.add(copper, 70)
	drone.inventory.add(_item(&"iron_ingot"), 20)
	var totals := PackedInt32Array()
	totals.resize(Registry.items.size())
	totals.fill(0)
	drone.inventory.collect_into(totals)
	var expected := TeleportSummary.total(totals)
	var recipe := Registry.get_hand_recipe(Registry.get_building(&"conveyor").item.index)
	_check(drone.crafting.enqueue(recipe, 5) == 5, "ленты поставлены в очередь крафта")
	var death_pos := planet.gateway.get_world_center() + Vector2(8, 0) * GameConst.TILE_SIZE
	drone.position = death_pos
	var tick := planet.simulation.tick
	planet.damage_drone(drone, drone.def.health * 0.5, tick)
	_check(not drone.dead and drone.health == drone.def.health * 0.5, "урон дрону уменьшает прочность")
	planet.damage_drone(drone, drone.def.health, tick)
	_check(drone.dead and drone.inventory.is_empty() and drone.crafting.is_empty(), "сбитый дрон теряет инвентарь и очередь")
	_check(planet.crates.size() == 1 and planet.crates[0].total() == expected, "груз содержит инвентарь и сырьё отменённого крафта (%d из %d)" % [planet.crates[0].total(), expected])
	_check(not run.can_use_gateway() and planet.check_build(Registry.get_building(&"conveyor"), GameConst.world_to_tile(death_pos), 0) == BuildingManager.Check.OUT_OF_RANGE,
		"сбитый дрон не ходит через шлюз и не строит")
	for i in drone.def.get_respawn_ticks():
		run.step()
	_check(not drone.dead and drone.position == planet.gateway.get_world_center() and drone.health == drone.def.health, "дрон появляется у шлюза с полной прочностью")
	planet.damage_drone(planet.drone, 1000.0, planet.simulation.tick)
	_check(not drone.dead, "после появления дрон неуязвим")
	drone.position = death_pos + Vector2(12, 0)
	run.step()
	_check(planet.crates.is_empty() and drone.inventory.count(copper) > 0, "дрон подбирает груз, подлетев к нему")
	var saved := SaveIO.world_to_dict(planet)
	_check((saved["crates"] as Array).is_empty(), "подобранный груз не сохраняется")
	run.dispose()

	var creative_run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), true)
	creative_run.planet.damage_drone(creative_run.drone, 10000.0, 0)
	_check(not creative_run.drone.dead, "в творческом режиме дрона не сбить")
	creative_run.dispose()


func _test_breach_teleport() -> void:
	var run := Run.create_new(4242, false)
	var planet := run.planet
	var pad := planet.pad_rect
	var copper := _item(&"hematite")
	var container := Registry.get_building(&"container")
	var damaged := planet.buildings.place(container, pad.position + Vector2i(1, 1), 0, true) as StorageBuilding
	damaged.inventory.add(copper, 20)
	planet.damage_building(damaged, 100.0)
	var doomed := planet.buildings.place(container, pad.position + Vector2i(4, 1), 0, true)
	planet.damage_building(doomed, 10000.0)
	# Груз на площадке — в стороне от дрона над шлюзом, чтобы тот его не подобрал.
	planet.crates.append(DroneCrate.from_counts(Vector2(pad.position + pad.size / 2 + Vector2i(4, 4)) * GameConst.TILE_SIZE, _counts(copper, 15)))
	planet.crates.append(DroneCrate.from_counts(Vector2(pad.position + Vector2i(-8, 0)) * GameConst.TILE_SIZE, _counts(copper, 9)))
	var old_node := run.star_map.get_current()
	var neighbors := old_node.links.duplicate()
	run.start_teleport(neighbors[0])
	planet.damage_building(planet.gateway, 100000.0)
	_check(planet.breached and planet.gateway != null and planet.gateway.health == 0.0, "шлюз не исчезает, мир прорван")
	var changed := [0]
	run.planet_changed.connect(func() -> void: changed[0] += 1)
	run.step()
	var summary := run.last_summary
	_check(changed[0] == 1 and run.planet != planet and neighbors.has(run.star_map.current_id), "прорыв — сразу телепорт на соседнюю планету")
	_check(summary.emergency and not run.is_charging(), "итог отмечен как аварийный, зарядка сброшена")
	_check(summary.buildings_destroyed == 1 and summary.buildings_moved == 1, "разрушенное потеряно, уцелевшее переехало")
	var moved := run.planet.buildings.get_at(run.planet.pad_rect.position + Vector2i(1, 1)) as StorageBuilding
	_check(moved != null and moved.health == moved.get_max_health() - 100.0 and run.planet.damaged.has(moved.id) and moved.inventory.count(copper) == 20,
		"повреждённый склад переехал с прочностью и содержимым")
	_check(run.planet.gateway.health == run.planet.gateway.get_max_health() and not run.planet.breached, "шлюз на новой планете цел")
	_check(run.planet.crates.size() == 1 and run.planet.crates[0].total() == 15 and summary.items_lost[copper] >= 9, "груз на площадке переехал, вне площадки — потерян")
	var node := run.star_map.get_current()
	_check((run.planet.threat != null) == (not node.type.safe), "угроза новой планеты по её типу")
	run.dispose()


func _counts(item: int, amount: int) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(Registry.items.size())
	counts.fill(0)
	counts[item] = amount
	return counts


func _test_enemy_save_determinism() -> void:
	var map := LevelMap.new(64, 48, Registry.get_floor(&"stone").index)
	var rock := Registry.get_floor(&"rock").index
	for y in range(6, 40):
		map.set_floor(20, y, rock)
	var run := Run.create(null, map, false)
	var planet := run.planet
	var gate := planet.gateway
	var container := Registry.get_building(&"container")
	planet.buildings.place(container, gate.origin + Vector2i(-4, -1), 0, true)
	planet.buildings.place(container, gate.origin + Vector2i(-4, 1), 0, true)
	Worlds.conveyor_line(planet, gate.origin + Vector2i(-8, -3), 9, GameConst.Dir.DOWN)
	var k := 0
	for def in Registry.enemies:
		for j in 8:
			planet.spawn_enemy(def, Vector2(3 + (k % 5), 4 + k % 40) * GameConst.TILE_SIZE + Vector2(k % 7, k % 3))
			k += 1
	run.drone.position = gate.get_world_center() + Vector2(-6, 6) * GameConst.TILE_SIZE
	# Оборона: пулемёт и артиллерия с патронами — в сохранение попадут снаряды в полёте.
	var gun := planet.buildings.place(Registry.get_building(&"machine_gun"), gate.origin + Vector2i(-2, 4), 0, true) as Turret
	var art := planet.buildings.place(Registry.get_building(&"machine_gun"), gate.origin + Vector2i(4, 4), 0, true) as Turret
	for i in 5:
		gun.handle_item(null, _item(&"cartridge_stone"))
		gun.handle_item(null, _item(&"cartridge_brick"))
	for i in 10:
		art.handle_item(null, _item(&"cartridge_coal"))
	planet.damage_building(planet.buildings.get_at(gate.origin + Vector2i(-4, -1)), 120.0)
	planet.threat.call_next_wave(planet.simulation.tick)
	for n in 4:
		planet.spawn_enemy(Registry.get_enemy(&"soldier"), gate.get_world_center() + Vector2(-9 - n, 5) * GameConst.TILE_SIZE)
	for i in 150:
		run.step()
	var guard := 0
	while planet.projectiles.count == 0 and guard < 300:
		run.step()
		guard += 1
	planet.buildings.place(container, gate.origin + Vector2i(-10, 3), 0, true)
	run.step()
	_check(planet.flow.is_computing(), "сохраняем посреди пересчёта поля потоков")
	_check(planet.threat.get_pending_spawns() > 0 or planet.threat.wave > 0, "у угрозы есть состояние")
	_check(planet.projectiles.count > 0, "в момент сохранения летят снаряды (%d)" % planet.projectiles.count)
	var saved := SaveIO.run_to_dict(run)
	var bytes := var_to_bytes(saved)
	var loaded := SaveIO.run_from_dict(bytes_to_var(bytes))
	var reloaded := SaveIO.run_to_dict(loaded)
	var diff := _first_diff(saved, reloaded)
	_check(diff.is_empty() and var_to_bytes(reloaded) == bytes, "враги, угроза и поле потоков сохраняются точно (отличие: %s)" % diff)
	for i in 400:
		run.step()
		loaded.step()
	var a := SaveIO.run_to_dict(run)
	var b := SaveIO.run_to_dict(loaded)
	diff = _first_diff(a, b)
	_check(diff.is_empty() and var_to_bytes(a) == var_to_bytes(b), "бой после загрузки идёт так же, как без неё (отличие: %s)" % diff)
	_check(run.planet.gateway == null or run.planet.gateway.is_damaged() or run.planet.destroyed_count > 0 or run.last_summary != null,
		"в сценарии враги успели навредить")
	run.dispose()
	loaded.dispose()


# --- Этап 10: оборона ---

func _test_defense_data() -> void:
	var gun := Registry.get_building(&"machine_gun") as TurretDef
	_check(gun != null and gun.category == BuildingDef.Category.DEFENSE and gun.power_use == 0.0, "пулемётная турель в разделе «Оборона», без электричества")
	for id in [&"cartridge_stone", &"cartridge_iron", &"cartridge_coal", &"cartridge_copper", &"cartridge_brick"]:
		_check(gun.find_ammo(_item(id)) >= 0, "пулемёт принимает %s" % id)
	_check(gun.find_ammo(_item(&"iron_ingot")) < 0 and gun.find_ammo(_item(&"casing_mg")) < 0, "наполнитель и гильза по отдельности — не патроны")
	var stone := gun.ammo[gun.find_ammo(_item(&"cartridge_stone"))]
	var iron := gun.ammo[gun.find_ammo(_item(&"cartridge_iron"))]
	var coal := gun.ammo[gun.find_ammo(_item(&"cartridge_coal"))]
	var copper := gun.ammo[gun.find_ammo(_item(&"cartridge_copper"))]
	var brick := gun.ammo[gun.find_ammo(_item(&"cartridge_brick"))]
	_check(iron.damage > stone.damage and coal.burn_dps > 0.0 and copper.reload_multiplier < 1.0 and brick.splash_radius > 0.0,
		"эффекты наполнителей: урон, горение, скорострельность, осколки")
	var cartridge := Registry.get_recipe(&"cartridge_coal")
	_check(cartridge.hand_craftable and cartridge.get_main_output().amount == 4 and cartridge.accepts_item(_item(&"casing_mg")) and cartridge.accepts_item(_item(&"coal")),
		"патрон: гильза + наполнитель → 4 патрона, можно руками")
	var wall := Registry.get_building(&"stone_wall")
	_check(wall.solid and not wall.rotatable and wall.line_placement, "каменная стена твёрдая, не поворачивается, ставится линией")
	_check(wall.get_path_cost() > Registry.get_building(&"drill").get_path_cost(), "проход сквозь стену дороже, чем сквозь бур")
	_check(Registry.drone_def.gun_damage > 0.0 and Registry.drone_def.repair_per_second > 0.0, "у дрона есть автопушка и ремонт")


func _test_turret_ammo() -> void:
	var world := Worlds.empty_world(16, 8, false)
	var copper := _item(&"cartridge_stone")
	var graphite := _item(&"cartridge_iron")
	var gun := world.buildings.place(Registry.get_building(&"machine_gun"), Vector2i(8, 3), 0, true) as Turret
	var d := gun.get_turret_def()
	_check(world.turrets.has(gun.id) and gun.get_status() == Building.Status.NO_AMMO, "турель без патронов, учтена в мире")
	_check(not gun.accept_item(null, _item(&"brick")) and gun.accept_item(null, copper), "кирпич — не патрон, каменный патрон — патрон")
	# Лента подаёт каменные патроны, пока запас не заполнится.
	var source := _source(world, Vector2i(5, 3), [copper])
	Worlds.conveyor_line(world, Vector2i(6, 3), 2, GameConst.Dir.RIGHT)
	Worlds.run_ticks(world, 400)
	_check(gun.total_shots == d.max_ammo and not gun.accept_item(null, copper), "лента заполняет запас патронов (%d/%d)" % [gun.total_shots, d.max_ammo])
	world.buildings.remove(source, true)
	# Руками: железные патроны ложатся поверх каменных и стреляют первыми.
	var gun2 := world.buildings.place(Registry.get_building(&"machine_gun"), Vector2i(12, 3), 0, true) as Turret
	world.drone.position = Vector2(12.5, 3.5) * GameConst.TILE_SIZE
	world.drone.inventory.add(copper, 10)
	world.drone.inventory.add(graphite, 10)
	_check(world.player_put(gun2, copper, 5) == 5 and world.player_put(gun2, graphite, 3) == 3, "патроны кладутся руками")
	_check(gun2.get_current_ammo().item.index == graphite and gun2.total_shots == 32, "последний вид патронов стреляет первым")
	var stacks := gun2.get_player_stacks()
	_check(stacks.size() == 2 and stacks[0] == Vector2i(graphite, 3) and gun2.take_player_items(copper, 5) == 0, "окно турели показывает патроны, забрать нельзя")
	var state := gun2.save_state()
	var copy := world.buildings.place(Registry.get_building(&"machine_gun"), Vector2i(14, 5), 0, true) as Turret
	copy.load_state(state)
	_check(copy.total_shots == 32 and copy.get_current_ammo().item.index == graphite, "запас патронов переносится в состояние")
	var before := world.drone.inventory.count(copper)
	_check(world.demolish(gun2) and world.drone.inventory.count(copper) == before + 5 and not world.turrets.has(gun2.id),
		"при сносе целые патроны возвращаются")
	world.dispose()


## Турель с патронами у шлюза; дрон уводится далеко, чтобы стреляли только турели.
func _defense_run() -> Run:
	var run := _enemy_run()
	run.drone.position = Vector2(2, 2) * GameConst.TILE_SIZE
	run.planet.gateway.health = 1.0e9
	return run


func _test_turret_kills() -> void:
	var run := _defense_run()
	var planet := run.planet
	var gate := planet.gateway
	var gun := planet.buildings.place(Registry.get_building(&"machine_gun"), gate.origin + Vector2i(-2, 1), 0, true) as Turret
	for i in 10:
		gun.handle_item(null, _item(&"cartridge_iron"))
	var start := gate.get_world_center() + Vector2(-14, 0) * GameConst.TILE_SIZE
	for k in 3:
		planet.spawn_enemy(Registry.get_enemy(&"crawler"), start + Vector2(0, (k - 1) * 20))
	var killed_at := -1
	for i in 600:
		run.step()
		if planet.enemies.count == 0:
			killed_at = i
			break
	_check(killed_at >= 0 and planet.enemies.killed == 3, "пулемёт уничтожил трёх ползунов (за %d тиков)" % killed_at)
	_check(planet.projectiles.fired > 0 and gun.total_shots < 40, "турель стреляла и тратила патроны (выстрелов %d)" % planet.projectiles.fired)
	_check(planet.projectiles.hits >= 1 and planet.projectiles.hits <= planet.projectiles.fired, "попадания считаются (%d из %d)" % [planet.projectiles.hits, planet.projectiles.fired])
	for i in 60:
		run.step()
	_check(planet.projectiles.count == 0 and gun.get_status() == Building.Status.IDLE, "без врагов снаряды исчезают, турель ждёт")
	run.dispose()


## Артиллерия (в ранней игре её нет, механика остаётся): мёртвая зона и взрыв по площади.
func _test_artillery() -> void:
	var run := _defense_run()
	var planet := run.planet
	var gate := planet.gateway
	var art := planet.buildings.place(Worlds.artillery_def(), gate.origin + Vector2i(-3, 4), 0, true) as Turret
	for i in 16:
		art.handle_item(null, _item(&"cartridge_iron"))
	# Враг вплотную — в мёртвой зоне.
	var center := art.get_world_center()
	planet.spawn_enemy(Registry.get_enemy(&"brute"), center + Vector2(2, 0) * GameConst.TILE_SIZE)
	planet.enemies.next_attack[0] = 1000000
	for i in 20:
		run.step()
	_check(planet.projectiles.fired == 0, "артиллерия не стреляет вплотную")
	planet.enemies.clear()
	# Плотная группа вдалеке: взрыв задевает нескольких.
	var group := center + Vector2(-11, 0) * GameConst.TILE_SIZE
	for k in 5:
		planet.spawn_enemy(Registry.get_enemy(&"soldier"), group + Vector2(k % 3 * 10 - 10, k * 6 - 12))
	for k in planet.enemies.count:
		planet.enemies.next_attack[k] = 1000000
	for i in 200:
		run.step()
		if planet.projectiles.fired >= 3:
			break
	for i in 90:
		run.step()
	var damaged := 0
	for k in planet.enemies.count:
		if planet.enemies.health[k] < Registry.get_enemy(&"soldier").health:
			damaged += 1
	_check(planet.projectiles.fired >= 3 and planet.projectiles.hits > planet.projectiles.fired,
		"снаряды артиллерии задевают по нескольку врагов (выстрелов %d, попаданий %d)" % [planet.projectiles.fired, planet.projectiles.hits])
	_check(damaged + planet.enemies.killed >= 3, "ранено или убито не меньше трёх (%d + %d)" % [damaged, planet.enemies.killed])
	run.dispose()


func _test_drone_gun_and_repair() -> void:
	var run := _enemy_run()
	var planet := run.planet
	var drone := run.drone
	planet.gateway.health = 1.0e9
	# Дрон у шлюза: ползун придёт к шлюзу и останется в радиусе автопушки.
	drone.position = planet.gateway.get_world_center() + Vector2(0, 3) * GameConst.TILE_SIZE
	planet.spawn_enemy(Registry.get_enemy(&"crawler"), planet.gateway.get_world_center() + Vector2(-12, 0) * GameConst.TILE_SIZE)
	for i in 600:
		run.step()
		if planet.enemies.count == 0:
			break
	_check(planet.enemies.count == 0 and planet.enemies.killed == 1 and not drone.dead, "автопушка дрона уничтожила ползуна")
	# Ремонт: повреждённый склад в радиусе чинится бесплатно, дальний — нет.
	var near := planet.buildings.place(Registry.get_building(&"container"), GameConst.world_to_tile(drone.position) + Vector2i(2, 2), 0, true)
	var far := planet.buildings.place(Registry.get_building(&"container"), GameConst.world_to_tile(drone.position) + Vector2i(18, 0), 0, true)
	planet.damage_building(near, 120.0)
	planet.damage_building(far, 60.0)
	var totals := TeleportSummary.total(drone.inventory.totals)
	for i in 20:
		run.step()
	_check(drone.is_repairing() and near.health > near.get_max_health() - 120.0, "дрон чинит постройку в радиусе")
	for i in 200:
		run.step()
	_check(not near.is_damaged() and not planet.damaged.has(near.id) and not drone.is_repairing(), "постройка починена полностью")
	_check(far.is_damaged() and TeleportSummary.total(drone.inventory.totals) == totals, "дальняя не чинится, ремонт бесплатный")
	var saved := drone.save_data()
	_check(saved.has("repair_target") and saved.has("gun_ready"), "состояние пушки и ремонта сохраняется")
	run.dispose()


func _test_walls_route() -> void:
	# Коридор со стеной поперёк: с проходом враги обходят, без прохода — стена на пути.
	var world := _flow_world(30, 16, 8, 14)
	var flow := world.ensure_flow()
	var wall := Registry.get_building(&"stone_wall")
	for y in range(2, 12):
		world.buildings.place(wall, Vector2i(18, y), 0, true)
	flow.compute_now()
	var path := _follow_path(flow, Vector2i(2, 7))
	var through_wall := false
	for p in path:
		through_wall = through_wall or world.buildings.get_at(p) != null and world.buildings.get_at(p).def == wall
	_check(not through_wall and world.gateway.get_rect().has_point(path[path.size() - 1]), "стену с проходом враги обходят")
	for y in [0, 1, 12, 13, 14, 15]:
		world.buildings.place(wall, Vector2i(18, y), 0, true)
	flow.compute_now()
	path = _follow_path(flow, Vector2i(2, 7))
	through_wall = false
	for p in path:
		through_wall = through_wall or world.buildings.get_at(p) != null and world.buildings.get_at(p).def == wall
	_check(through_wall, "сплошную стену путь проходит насквозь — её будут ломать")
	world.dispose()


# --- Этап Д: энергия, жидкости, исследования, патроны ---

## Электросеть: провода между опорами, зона питания, мощность и спрос, расход топлива, снос опоры.
func _test_power_network() -> void:
	var world := Worlds.empty_world(40, 20, false)
	var pole_def := Registry.get_building(&"small_power_pole")
	world.drone.inventory.add(pole_def.item.index, 5)
	var a := world.build(pole_def, Vector2i(14, 8), 0) as PowerPole
	var b := world.build(pole_def, Vector2i(20, 8), 0) as PowerPole
	var far := world.build(pole_def, Vector2i(29, 8), 0) as PowerPole
	_check(a != null and b != null and far != null, "опоры поставлены")
	_check(a.is_linked(b) and b.is_linked(a), "опора, поставленная рядом, соединилась проводом")
	_check(not b.is_linked(far), "опора дальше радиуса провода не соединяется")
	var generator := world.buildings.place(Registry.get_building(&"thermal_generator"), Vector2i(12, 6), 0, true) as Generator
	var assembler := world.buildings.place(Registry.get_building(&"assembler"), Vector2i(20, 9), 0, true) as Crafter
	world.configure(assembler, &"gear")
	for i in 30:
		assembler.handle_item(null, _item(&"iron_ingot"))
	Worlds.run_ticks(world, 30)
	_check(assembler.power_net != null and assembler.power_net == generator.power_net, "генератор и сборщик — одна сеть через провод")
	_check(assembler.get_status() == Building.Status.NO_POWER and assembler.outputs[_item(&"gear")] == 0, "без топлива в сети нет энергии")
	generator.handle_item(null, _item(&"coal"))
	Worlds.run_ticks(world, 3 * GameConst.TICK_RATE)
	_check(assembler.outputs[_item(&"gear")] >= 5, "с топливом сборщик работает (%d)" % assembler.outputs[_item(&"gear")])
	var net := assembler.power_net
	_check(is_equal_approx(net.satisfaction, 1.0) and absf(net.demand_kw - 75.0) < 0.01 and absf(net.capacity_kw - 150.0) < 0.01,
		"спрос 75 кВт, мощность 150 кВт (%.1f / %.1f)" % [net.demand_kw, net.capacity_kw])
	var energy_before := generator.fuel_energy + generator.total_fuel() * 4000.0
	Worlds.run_ticks(world, GameConst.TICK_RATE)
	var spent := energy_before - (generator.fuel_energy + generator.total_fuel() * 4000.0)
	_check(absf(spent - 150.0) < 6.0, "топливо по нагрузке: 75 кВт при КПД 50%% — %.1f кДж за секунду (≈150)" % spent)
	world.buildings.remove(b, true)
	Worlds.run_ticks(world, 2)
	_check(assembler.power_net == null and world.power.unconnected.has(assembler), "без опоры сборщик отключён")
	_check(a.get_linked_poles().is_empty() and a.get_config() == null, "провода к снесённой опоре убраны")
	world.dispose()


## Трубы: насос на воде → трубы → бойлер → паровые генераторы цепочкой → электричество; разрез трубы.
func _test_fluids() -> void:
	var map := LevelMap.new(40, 20, Registry.get_floor(&"stone").index)
	map.set_ore(4, 8, Registry.get_ore(&"water").index + 1)
	var world := GameWorld.create(null, map, true)
	var bm := world.buildings
	_check(bm.check_place(Registry.get_building(&"pump"), Vector2i(6, 8), 0) == BuildingManager.Check.NO_ORE, "насос без воды не ставится")
	_check(world.drone.get_mineable_ore(Vector2i(4, 8)) == null, "воду дрон не добывает")
	var pump := bm.place(Registry.get_building(&"pump"), Vector2i(4, 8), 0, true) as Pump
	for x in range(5, 10):
		bm.place(Registry.get_building(&"pipe"), Vector2i(x, 8), 0, true)
	var boiler := bm.place(Registry.get_building(&"boiler"), Vector2i(10, 8), 0, true) as Boiler
	var gen := bm.place(Registry.get_building(&"steam_generator"), Vector2i(12, 8), 0, true) as Generator
	var gen2 := bm.place(Registry.get_building(&"steam_generator"), Vector2i(14, 8), 0, true) as Generator
	for i in 5:
		boiler.handle_item(null, _item(&"coal"))
	Worlds.run_ticks(world, 60)
	var water := Registry.get_fluid(&"water").index
	var steam := Registry.get_fluid(&"steam").index
	var water_net := world.fluids.get_port_network(boiler, boiler.get_water_side())
	_check(pump.fluid != null and water_net != null and water_net == world.fluids.get_pipe_network(bm.get_at(Vector2i(7, 8))),
		"насос, трубы и вход бойлера — одна сеть")
	_check(water_net.fluid == water and water_net.amount > 0.0, "в трубах вода (%.0f)" % water_net.amount)
	var steam_net := world.fluids.get_port_network(gen2, gen2.get_steam_side(1))
	_check(steam_net != null and steam_net == world.fluids.get_port_network(boiler, boiler.get_steam_side()) and steam_net == world.fluids.get_port_network(gen, gen.get_steam_side(0)),
		"пар проходит от бойлера сквозь генераторы в цепочке без труб")
	_check(steam_net.fluid == steam and boiler.last_steam_rate > 0.0, "бойлер делает пар")
	bm.place(Registry.get_building(&"small_power_pole"), Vector2i(13, 11), 0, true)
	var assembler := bm.place(Registry.get_building(&"assembler"), Vector2i(11, 11), 0, true) as Crafter
	world.configure(assembler, &"gear")
	for i in 20:
		assembler.handle_item(null, _item(&"iron_ingot"))
	Worlds.run_ticks(world, 90)
	_check(assembler.power_net != null and assembler.power_net.generators.size() == 2 and is_equal_approx(assembler.power_net.satisfaction, 1.0),
		"два паровых генератора питают сборщик")
	_check(assembler.outputs[_item(&"gear")] > 0, "сборщик работает от пара (%d)" % assembler.outputs[_item(&"gear")])
	# Разрез трубы делит сеть; отрезанная часть уходит в бойлер, насос наполняет свою.
	bm.remove(bm.get_at(Vector2i(7, 8)), true)
	Worlds.run_ticks(world, 1)
	var left := world.fluids.get_pipe_network(bm.get_at(Vector2i(6, 8)))
	var right := world.fluids.get_pipe_network(bm.get_at(Vector2i(8, 8)))
	_check(left != null and right != null and left != right, "разрез трубы делит сеть на две")
	for i in 20:
		assembler.handle_item(null, _item(&"iron_ingot"))
	assembler.outputs[_item(&"gear")] = 0
	var right_before := right.amount
	Worlds.run_ticks(world, 5 * GameConst.TICK_RATE)
	_check(is_equal_approx(left.amount, left.capacity) and right.amount < right_before,
		"насос держит свою часть полной, отрезанная часть только убывает (%.0f / %.1f → %.1f)" % [left.amount, right_before, right.amount])
	world.dispose()


## Исследования: закрытые постройки и рецепты, ручная сдача, завершение, научный цех, сохранение, творческий режим.
func _test_research() -> void:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	var state := run.research
	var drone := run.drone
	var drill_def := Registry.get_building(&"drill")
	var drill_item := drill_def.item.index
	var kit := _item(&"science_kit")
	_check(not state.is_building_unlocked(drill_def) and state.is_building_unlocked(Registry.get_building(&"furnace"))
		and state.is_building_unlocked(Registry.get_building(&"coal_drill")), "электробур закрыт, печь и угольный бур доступны сразу")
	drone.inventory.add(_item(&"iron_ingot"), 50)
	_check(drone.crafting.enqueue(Registry.get_hand_recipe(drill_item), 1) == 0, "закрытую постройку не скрафтить")
	_check(not drone.crafting.is_available(Registry.get_hand_recipe(_item(&"cartridge_coal"))), "патроны закрыты «Обороной»")
	_check(not state.set_active(&"defense") and not state.set_active(&"mining"), "«Оборона» и «Электробур» недоступны без «Электрики»")
	_check(state.set_active(&"electricity") and state.get_active().id == &"electricity", "выбрано исследование «Электрика»")
	drone.inventory.add(kit, 12)
	_check(state.deposit_manual(drone.inventory) == 10 and drone.inventory.count(kit) == 2, "сдано ровно столько наборов, сколько нужно")
	var ticks := roundi(ResearchState.MANUAL_SECONDS * GameConst.TICK_RATE)
	for i in ticks * 3:
		run.step()
	_check(state.get_progress(Registry.get_research(&"electricity")) == 3 and state.manual_queue == 7, "ручная сдача: 3 набора за %d с" % (3 * roundi(ResearchState.MANUAL_SECONDS)))
	# Очередь: следующее исследование берётся само, когда текущее завершается.
	_check(state.queue_add(&"mining") and state.queue_add(&"defense") and state.queue == [&"mining", &"defense"], "два исследования в очереди")
	_check(not state.queue_add(&"mining"), "повторно в очередь не ставится")
	var loaded := SaveIO.run_from_dict(bytes_to_var(var_to_bytes(SaveIO.run_to_dict(run))))
	_check(loaded.research.get_progress(Registry.get_research(&"electricity")) == 3 and loaded.research.manual_queue == 7
		and loaded.research.active == &"electricity" and loaded.research.queue == [&"mining", &"defense"],
		"исследования и очередь сохраняются")
	loaded.dispose()
	var finished := [false]
	state.completed.connect(func(r: ResearchDef) -> void: finished[0] = r.id == &"electricity")
	for i in ticks * 7 + 1:
		run.step()
	_check(finished[0] and state.is_done(&"electricity"), "исследование завершено")
	_check(state.active == &"mining" and state.queue == [&"defense"], "из очереди выбрано следующее исследование")
	_check(state.is_building_unlocked(Registry.get_building(&"thermal_generator")), "термогенератор открыт «Электрикой»")
	# Научный цех от электричества быстрее ручной сдачи.
	_check(state.get_active().id == &"mining", "выбран «Электробур»")
	var workshop := run.planet.buildings.place(Registry.get_building(&"science_workshop"), Vector2i(6, 6), 0, true) as ScienceWorkshop
	Worlds.power_area(run.planet, Vector2i(6, 4), 5, Vector2i(9, 5))
	for i in 10:
		workshop.handle_item(null, kit)
	for i in 20 * GameConst.TICK_RATE:
		run.step()
	var progress := state.get_progress(Registry.get_research(&"mining"))
	_check(progress >= 9 and progress <= 10, "научный цех: %d наборов за 20 с (≈2 с на набор)" % progress)
	for i in 10:
		workshop.handle_item(null, kit)
	for i in 20 * GameConst.TICK_RATE:
		run.step()
	_check(state.is_done(&"mining") and state.active == &"defense", "«Электробур» готов, из очереди взята «Оборона»")
	_check(state.is_building_unlocked(drill_def) and drone.crafting.enqueue(Registry.get_hand_recipe(drill_item), 1) == 1, "электробур открыт и крафтится")
	var creative := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), true)
	_check(creative.research.is_building_unlocked(drill_def) and creative.drone.crafting.is_available(Registry.get_hand_recipe(_item(&"cartridge_coal"))),
		"в творческом режиме всё открыто")
	creative.dispose()
	run.dispose()


## Эффекты наполнителей: горение, осколочный взрыв при попадании, поджог, скорострельность.
func _test_ammo_effects() -> void:
	var run := _defense_run()
	var planet := run.planet
	var enemies := planet.enemies
	var gate := planet.gateway
	var center := gate.get_world_center() + Vector2(-12, 8) * GameConst.TILE_SIZE
	var i := planet.spawn_enemy(Registry.get_enemy(&"brute"), center)
	enemies.next_attack[i] = 100000000
	enemies.ignite(i, 10.0, planet.simulation.tick + 60)
	var hp := enemies.health[i]
	for k in 30:
		run.step()
	_check(absf(hp - enemies.health[0] - 10.0) < 0.7 and enemies.is_burning(0, planet.simulation.tick), "горение: 10 урона в секунду (%.1f)" % (hp - enemies.health[0]))
	for k in 45:
		run.step()
	_check(not enemies.is_burning(0, planet.simulation.tick), "горение заканчивается")
	enemies.clear()

	var d := Registry.get_building(&"machine_gun") as TurretDef
	var gun := planet.buildings.place(d, gate.origin + Vector2i(-6, 8), 0, true) as Turret
	var gun_center := gun.get_world_center()
	for k in 3:
		var j := planet.spawn_enemy(Registry.get_enemy(&"brute"), gun_center + Vector2(-5 * GameConst.TILE_SIZE, (k - 1) * 12.0))
		enemies.next_attack[j] = 100000000
	for k in 10:
		gun.handle_item(null, _item(&"cartridge_brick"))
	for k in 60:
		run.step()
		if planet.projectiles.hits > 0:
			break
	for k in 10:
		run.step()
	var damaged := 0
	for j in enemies.count:
		if enemies.health[j] < Registry.get_enemy(&"brute").health:
			damaged += 1
	_check(damaged >= 2, "осколочный патрон задевает соседей (ранено %d)" % damaged)
	for k in 5:
		gun.handle_item(null, _item(&"cartridge_coal"))
	var burning := false
	for k in 120:
		run.step()
		for j in enemies.count:
			burning = burning or enemies.is_burning(j, planet.simulation.tick)
		if burning:
			break
	_check(burning, "зажигательный патрон поджигает")
	var copper := d.ammo[d.find_ammo(_item(&"cartridge_copper"))]
	var stone := d.ammo[d.find_ammo(_item(&"cartridge_stone"))]
	_check(d.get_reload_ticks(copper) < d.get_reload_ticks(stone), "лёгкий патрон стреляет чаще (%d < %d тиков)" % [d.get_reload_ticks(copper), d.get_reload_ticks(stone)])
	run.dispose()


# --- Правки после этапа Д ---

## Дерево исследований: ветки, столбцы по глубине, доступность по цепочке.
func _test_research_tree() -> void:
	var cells := ResearchTreeView.layout(Registry.researches)
	_check(cells[&"electricity"].x == 0 and cells[&"mining"].x == 1 and cells[&"industry"].x == 2
		and cells[&"science_automation"].x == 3 and cells[&"logistics"].x == 2 and cells[&"defense"].x == 1,
		"дерево: Электрика → Электробур → Промышленность → Автоматизация науки, Электробур → Логистика")
	_check(cells[&"fluid_handling"].x == 1 and cells[&"steam_power"].x == 2 and cells[&"accumulators"].x == 3,
		"ветка жидкостей: Электрика → Трубы и насосы → Паровая энергия → Аккумуляторы")
	_check(cells[&"drone_speed_1"].x == 0 and cells[&"drone_mining_1"].x == 1 and cells[&"drone_mining_3"].x == 3,
		"ветка дрона отдельным корнем: Скорость I → остальные цепочки")
	var state := ResearchState.new()
	state.done[&"electricity"] = true
	_check(state.is_available(Registry.get_research(&"mining")) and state.is_available(Registry.get_research(&"defense"))
		and state.is_available(Registry.get_research(&"fluid_handling")) and not state.is_available(Registry.get_research(&"industry")),
		"после Электрики доступны Электробур, Оборона и Трубы, Промышленность — нет")
	state.done[&"mining"] = true
	_check(state.is_available(Registry.get_research(&"industry")) and state.is_available(Registry.get_research(&"logistics"))
		and not state.is_available(Registry.get_research(&"science_automation")),
		"Промышленность и Логистика — после Электробура, Автоматизация науки — после Промышленности")


## На воде можно ставить только трубы и насосы.
func _test_water_placement() -> void:
	var map := LevelMap.new(16, 12, Registry.get_floor(&"stone").index)
	var water := Registry.get_ore(&"water").index + 1
	for x in range(4, 8):
		map.set_ore(x, 5, water)
	var world := GameWorld.create(null, map, true)
	var bm := world.buildings
	_check(bm.check_place(Registry.get_building(&"conveyor"), Vector2i(5, 5), 0) == BuildingManager.Check.ON_FLUID, "лента на воду не ставится")
	_check(bm.check_place(Registry.get_building(&"furnace"), Vector2i(4, 4), 0) == BuildingManager.Check.ON_FLUID, "печь, задевшая воду, не ставится")
	_check(bm.check_place(Registry.get_building(&"stone_wall"), Vector2i(6, 5), 0) == BuildingManager.Check.ON_FLUID, "стена на воду не ставится")
	_check(bm.check_place(Registry.get_building(&"pipe"), Vector2i(5, 5), 0) == BuildingManager.Check.OK, "труба на воду ставится")
	_check(bm.check_place(Registry.get_building(&"underground_pipe"), Vector2i(6, 5), 0) == BuildingManager.Check.OK, "подземная труба на воду ставится")
	_check(bm.check_place(Registry.get_building(&"pump"), Vector2i(4, 5), 0) == BuildingManager.Check.OK, "насос на воду ставится")
	_check(bm.check_place(Registry.get_building(&"conveyor"), Vector2i(5, 6), 0) == BuildingManager.Check.OK, "рядом с водой строить можно")
	world.dispose()


## Протягивание ленты: мост через препятствие, перекрёсток через чужую ленту; без них ничего не ломается.
func _test_belt_drag_obstacles() -> void:
	var map := LevelMap.new(32, 16, Registry.get_floor(&"stone").index)
	var world := GameWorld.create(null, map, false)
	var bm := world.buildings
	var inv := world.drone.inventory
	world.drone.position = Vector2(12, 8) * GameConst.TILE_SIZE
	var belt := Registry.get_building(&"conveyor")
	var bridge := Registry.get_building(&"bridge_conveyor")
	var junction := Registry.get_building(&"junction")
	# Препятствия на линии y = 8: две стены (x = 8, 9) и поперечная лента (x = 14, вниз).
	bm.place(Registry.get_building(&"stone_wall"), Vector2i(8, 8), 0, true)
	bm.place(Registry.get_building(&"stone_wall"), Vector2i(9, 8), 0, true)
	var crossing := bm.place(belt, Vector2i(14, 8), GameConst.Dir.DOWN, true)
	var path := LinePlanner.l_path(Vector2i(4, 8), Vector2i(18, 8), true, 0)
	inv.add(belt.item.index, 30)

	# Без мостов и перекрёстков: стены красные, поперечная лента не трогается.
	var plain := LinePlanner.plan_belt(world, belt, path, inv.make_budget())
	var wall_blocked := false
	var touches_crossing := false
	for g in plain:
		if g.origin == Vector2i(8, 8) and g.def == belt and not BuildingManager.is_valid_check(g.check):
			wall_blocked = true
		if g.origin == Vector2i(14, 8):
			touches_crossing = true
	_check(wall_blocked and not touches_crossing, "без мостов препятствие остаётся препятствием, без перекрёстка чужая лента не трогается")

	inv.add(bridge.item.index, 2)
	inv.add(junction.item.index, 1)
	var ghosts := LinePlanner.plan_belt(world, belt, path, inv.make_budget())
	var by_tile := {}
	for g in ghosts:
		by_tile[g.origin] = g
	var entry: PlacementPreview.Ghost = by_tile.get(Vector2i(7, 8))
	var exit: PlacementPreview.Ghost = by_tile.get(Vector2i(10, 8))
	_check(entry != null and entry.def == bridge and entry.config == Vector2i(3, 0) and exit != null and exit.def == bridge,
		"мост перед стенами и сразу за ними, вход связан с выходом")
	_check(not by_tile.has(Vector2i(8, 8)) and not by_tile.has(Vector2i(9, 8)), "под мостом ленты не планируются")
	var cross: PlacementPreview.Ghost = by_tile.get(Vector2i(14, 8))
	_check(cross != null and cross.def == junction and cross.check == BuildingManager.Check.REPLACE, "поперечная лента заменяется перекрёстком")
	var all_valid := true
	for g in ghosts:
		all_valid = all_valid and BuildingManager.is_valid_check(g.check)
	_check(all_valid, "вся трасса строится")

	# Строим как инструмент и гоним предметы с обоих направлений.
	for g in ghosts:
		world.build(g.def, g.origin, g.rotation, g.config if g.def != belt else null)
	var source := bm.place(Worlds.source_def(), Vector2i(3, 8), 0, true)
	source.set("items", PackedInt32Array([_item(&"hematite")]))
	var sink := bm.place(Worlds.sink_def(), Vector2i(19, 8), 0, true)
	var down_source := bm.place(Worlds.source_def(), Vector2i(14, 6), 0, true)
	down_source.set("items", PackedInt32Array([_item(&"brick")]))
	bm.place(belt, Vector2i(14, 7), GameConst.Dir.DOWN, true)
	bm.place(belt, Vector2i(14, 9), GameConst.Dir.DOWN, true)
	var down_sink := bm.place(Worlds.sink_def(), Vector2i(14, 10), 0, true)
	Worlds.run_ticks(world, 20 * GameConst.TICK_RATE)
	_check(sink.count_of(_item(&"hematite")) > 30 and sink.count_of(_item(&"brick")) == 0, "гематит прошёл по мосту и через перекрёсток (%d)" % sink.count_of(_item(&"hematite")))
	_check(down_sink.count_of(_item(&"brick")) > 30 and down_sink.count_of(_item(&"hematite")) == 0, "поперечный поток не смешался (%d)" % down_sink.count_of(_item(&"brick")))
	_check(crossing.world == null and bm.get_at(Vector2i(8, 8)).def.id == &"stone_wall", "стены на месте, поперечная лента стала перекрёстком")

	# Препятствие длиннее дальности моста — мост не ставится.
	var long_world := Worlds.empty_world(32, 8, true)
	for x in range(6, 11):
		long_world.buildings.place(Registry.get_building(&"stone_wall"), Vector2i(x, 3), 0, true)
	var long_plan := LinePlanner.plan_belt(long_world, belt, LinePlanner.l_path(Vector2i(2, 3), Vector2i(14, 3), true, 0), null)
	var has_bridge := false
	for g in long_plan:
		has_bridge = has_bridge or g.def == bridge
	_check(not has_bridge, "пять стен подряд мост не перекрывает (дальность 4)")
	long_world.dispose()
	world.dispose()


## Бур отдаёт только с лицевой стороны; разгрузчик забирает с любой.
func _test_drill_front_output() -> void:
	var map := LevelMap.new(24, 16, Registry.get_floor(&"stone").index)
	var ore := Registry.get_ore(&"hematite").index + 1
	for y in range(6, 8):
		for x in range(6, 8):
			map.set_ore(x, y, ore)
	var world := GameWorld.create(null, map, true)
	var bm := world.buildings
	var drill := bm.place(Registry.get_building(&"drill"), Vector2i(6, 6), GameConst.Dir.RIGHT, true) as Drill
	Worlds.power_area(world, Vector2i(3, 2), 5, Vector2i(4, 3))
	var right := bm.place(Worlds.sink_def(), Vector2i(8, 6), 0, true)
	var down := bm.place(Worlds.sink_def(), Vector2i(6, 8), 0, true)
	Worlds.run_ticks(world, 20 * GameConst.TICK_RATE)
	_check(right.received > 5 and down.received == 0, "бур отдаёт только вперёд (%d / %d)" % [right.received, down.received])
	_check(world.rotate_building(drill, 1) and drill.rotation == GameConst.Dir.DOWN, "бур поворачивается")
	var before: int = right.received
	Worlds.run_ticks(world, 20 * GameConst.TICK_RATE)
	_check(down.received > 5 and right.received == before, "после поворота — только вниз (%d)" % down.received)
	bm.remove(down, true)
	var unloader := bm.place(Registry.get_building(&"unloader"), Vector2i(5, 6), 0, true)
	bm.place(Registry.get_building(&"conveyor"), Vector2i(4, 6), GameConst.Dir.LEFT, true)
	var side_sink := bm.place(Worlds.sink_def(), Vector2i(3, 6), 0, true)
	Worlds.run_ticks(world, 20 * GameConst.TICK_RATE)
	_check(unloader != null and side_sink.received > 5, "разгрузчик сбоку забирает добычу бура (%d)" % side_sink.received)
	world.dispose()


## Подземные трубы: пара через препятствие, разворот выхода, закрытые стороны, дальность.
func _test_underground_pipes() -> void:
	var map := LevelMap.new(40, 16, Registry.get_floor(&"stone").index)
	map.set_ore(2, 6, Registry.get_ore(&"water").index + 1)
	var world := GameWorld.create(null, map, true)
	var bm := world.buildings
	var under := Registry.get_building(&"underground_pipe") as FluidBuildingDef
	var pipe := Registry.get_building(&"pipe")
	bm.place(Registry.get_building(&"pump"), Vector2i(2, 6), 0, true)
	bm.place(pipe, Vector2i(3, 6), 0, true)
	var entrance := bm.place(under, Vector2i(4, 6), GameConst.Dir.RIGHT, true) as UndergroundPipe
	for x in range(5, 11):
		bm.place(Registry.get_building(&"stone_wall"), Vector2i(x, 6), 0, true)
	_check(under.placement_rotation(world, Vector2i(11, 6), GameConst.Dir.RIGHT) == GameConst.Dir.LEFT, "выход сам разворачивается ко входу")
	var exit := bm.place(under, Vector2i(11, 6), under.placement_rotation(world, Vector2i(11, 6), GameConst.Dir.RIGHT), true) as UndergroundPipe
	bm.place(pipe, Vector2i(12, 6), 0, true)
	var side_pipe := bm.place(pipe, Vector2i(11, 5), 0, true)
	_check(entrance.get_linked_partner() == exit and exit.get_linked_partner() == entrance, "вход и выход — пара")
	Worlds.run_ticks(world, 60)
	var far_pipe := bm.get_at(Vector2i(12, 6))
	var net := world.fluids.get_pipe_network(far_pipe)
	_check(net != null and net == world.fluids.get_pipe_network(bm.get_at(Vector2i(3, 6))) and net.amount > 0.0,
		"вода прошла под стенами (%.0f)" % (net.amount if net != null else -1.0))
	_check(world.fluids.get_pipe_network(side_pipe) != net and not world.fluids.pipe_connects(exit, GameConst.Dir.UP),
		"сбоку подземная труба закрыта")
	_check(under.placement_rotation(world, Vector2i(20, 6), GameConst.Dir.RIGHT) == GameConst.Dir.RIGHT, "за занятой парой новая труба не разворачивается")
	# Дальше дальности пара не образуется.
	var lone := bm.place(under, Vector2i(24, 9), GameConst.Dir.RIGHT, true) as UndergroundPipe
	var too_far := bm.place(under, Vector2i(24 + under.underground_range + 1, 9), GameConst.Dir.LEFT, true) as UndergroundPipe
	_check(lone.get_linked_partner() == null and too_far.get_linked_partner() == null, "дальше %d тайлов пары нет" % under.underground_range)
	bm.remove(exit, true)
	Worlds.run_ticks(world, 2)
	_check(entrance.get_linked_partner() == null and world.fluids.get_pipe_network(far_pipe) != world.fluids.get_pipe_network(bm.get_at(Vector2i(3, 6))),
		"снос выхода разрывает подземный участок")
	world.dispose()


## Опоры протягиваются с шагом дальности провода; камера не выходит за карту.
func _test_pole_drag_and_camera() -> void:
	var pole_def := Registry.get_building(&"small_power_pole") as PowerPoleDef
	_check(pole_def.get_line_step() == 7, "шаг протягивания опор — 7 тайлов (провод 7.5)")
	var row := LinePlanner.straight_line(Vector2i(2, 5), Vector2i(20, 6), pole_def.get_line_step())
	_check(row == [Vector2i(2, 5), Vector2i(9, 5), Vector2i(16, 5)], "ряд опор через 7 тайлов")
	var world := Worlds.empty_world(32, 12, false)
	world.drone.position = Vector2(9, 5) * GameConst.TILE_SIZE
	world.drone.inventory.add(pole_def.item.index, 3)
	var poles: Array[PowerPole] = []
	for origin in row:
		poles.append(world.build(pole_def, origin, 0) as PowerPole)
	_check(poles[0] != null and poles[2] != null and poles[0].is_linked(poles[1]) and poles[1].is_linked(poles[2]), "протянутые опоры соединены цепочкой")
	world.dispose()
	_check(is_equal_approx(CameraController.clamp_axis(10.0, 400.0, 3000.0), 400.0)
		and is_equal_approx(CameraController.clamp_axis(2900.0, 400.0, 3000.0), 2600.0)
		and is_equal_approx(CameraController.clamp_axis(1500.0, 400.0, 3000.0), 1500.0),
		"камера упирается в края карты")
	_check(is_equal_approx(CameraController.clamp_axis(50.0, 800.0, 768.0), 384.0), "карта меньше экрана — камера в центре карты")


## Окна зданий: отдельные ячейки сырья, топлива и продукта, полоски прогресса, питания и жидкостей.
func _test_building_windows() -> void:
	var world := Worlds.empty_world(32, 20, true)
	var bm := world.buildings
	var furnace := bm.place(Registry.get_building(&"furnace"), Vector2i(4, 4), 0, true) as Crafter
	for i in 4:
		furnace.handle_item(null, _item(&"hematite"))
	furnace.handle_item(null, _item(&"coal"))
	Worlds.run_ticks(world, 30)
	var sections := furnace.get_window_sections()
	var kinds := PackedStringArray()
	for sec in sections:
		kinds.append("S" if sec.kind == WindowSection.Kind.SLOTS else "B")
	_check("".join(kinds) == "SSSBB", "печь: сырьё, топливо, продукт, прогресс, горение (%s)" % "".join(kinds))
	_check(sections[0].stacks[0] == Vector2i(_item(&"hematite"), 3) and sections[1].hints[0] == _item(&"coal")
		and sections[2].hints[0] == _item(&"iron_ingot") and sections[3].fraction > 0.0 and sections[4].fraction > 0.0,
		"в ячейках гематит, подсказки угля и слитка, прогресс идёт, уголь горит")
	_check(furnace.has_player_window(), "у печи есть окно")

	var assembler := bm.place(Registry.get_building(&"assembler"), Vector2i(8, 4), 0, true) as Crafter
	world.configure(assembler, &"science_kit")
	var asm := assembler.get_window_sections()
	_check(asm.size() == 4 and asm[0].stacks.size() == 2 and asm[0].hints[1] == _item(&"gear")
		and asm[3].kind == WindowSection.Kind.BAR and asm[3].fraction == 0.0,
		"сборщик: два входа рецепта, продукт, прогресс, питание (нет опоры)")

	var boiler := bm.place(Registry.get_building(&"boiler"), Vector2i(12, 4), 0, true) as Boiler
	var boiler_kinds := PackedStringArray()
	for sec in boiler.get_window_sections():
		boiler_kinds.append("S" if sec.kind == WindowSection.Kind.SLOTS else "B")
	_check("".join(boiler_kinds) == "SBBBB", "бойлер: топливо, горение, вода, пар, выход пара")

	var gun := bm.place(Registry.get_building(&"machine_gun"), Vector2i(16, 4), 0, true) as Turret
	for i in 3:
		gun.handle_item(null, _item(&"cartridge_iron"))
	var gun_sections := gun.get_window_sections()
	_check(not gun_sections[0].can_take and gun_sections[1].fraction > 0.0, "турель: патроны не забираются, запас выстрелов виден")

	var pole := bm.place(Registry.get_building(&"small_power_pole"), Vector2i(20, 4), 0, true)
	var pipe := bm.place(Registry.get_building(&"pipe"), Vector2i(20, 8), 0, true)
	_check(pole.has_player_window() and pipe.has_player_window() and pole.get_window_sections().size() == 1 and pipe.get_window_sections().size() == 1,
		"у опоры и трубы окно с полоской сети")
	_check(not bm.place(Registry.get_building(&"router"), Vector2i(24, 4), 0, true).get_window_sections().size() > 0, "у маршрутизатора разделов окна нет")
	world.dispose()


# --- Этап 11: энергия, этажи, шлюз ---

## Забег на пустой карте 48×32 с водой над шлюзом; research — завершённые исследования.
## Все исследования забега (для тестов, где нужен полностью открытый забег).
func _all_research_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for r in Registry.researches:
		if not r.creative_only:
			ids.append(r.id)
	return ids


func _floors_run(research: Array[StringName]) -> Run:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	map.set_ore(24, 10, Registry.get_ore(&"water").index + 1)
	var run := Run.create(null, map, false)
	for id in research:
		run.research.done[id] = true
	run.apply_research_effects()
	return run


## Эффекты исследований: размеры площадки и подземного этажа, закрытый проход.
func _test_research_effects_and_floors() -> void:
	var run := _floors_run([])
	var state := run.research
	_check(ResearchState.max_effect(&"pad_size") == 5 and ResearchState.max_effect(&"underground_size") == 5 and ResearchState.max_effect(&"gateway_ports") == 2,
		"пять расширений площадки и этажа, два шага портов")
	_check(run.get_pad_size() == 20 and run.planet.pad_rect.size == Vector2i(20, 20), "площадка в начале 20×20")
	_check(run.base.play_rect.size == Vector2i(16, 16) and run.base.grid.width == 46, "открытая часть этажа 16×16 на карте 46×46")
	var void_floor := Registry.get_floor(&"void").index
	_check(run.base.grid.get_floor(0, 0) == void_floor and not run.base.grid.is_buildable(0, 0)
		and run.base.grid.get_floor(run.base.play_rect.position.x, run.base.play_rect.position.y) != void_floor,
		"за краем открытой части — пустота, на ней не строят")
	_check(run.is_over_gateway() and not run.can_use_gateway() and not run.use_gateway(), "без «Подземного этажа» через шлюз не пройти")
	# Площадка растёт: свободные тайлы — платформа, под постройкой пол не меняется.
	var old_pad := run.planet.pad_rect
	var outside := old_pad.position + Vector2i(-2, 5)
	run.planet.buildings.place(Registry.get_building(&"stone_wall"), outside, 0, true)
	var free_tile := old_pad.position + Vector2i(-1, 5)
	state.done[&"pad_1"] = true
	run.apply_research_effects()
	var platform := Registry.get_floor(&"metal_plates").index
	_check(run.planet.pad_rect.size == Vector2i(24, 24) and run.planet.pad_rect.encloses(old_pad), "«Расширение площадки I»: 24×24 вокруг прежней")
	_check(run.planet.grid.get_floor(free_tile.x, free_tile.y) == platform and run.planet.grid.get_floor(outside.x, outside.y) != platform,
		"новая часть площадки — платформа, под стеной пол прежний")
	state.done[&"underground"] = true
	state.done[&"underground_1"] = true
	state.done[&"underground_2"] = true
	run.apply_research_effects()
	_check(run.base.play_rect.size == Vector2i(28, 28) and run.base.grid.is_buildable(run.base.play_rect.position.x, run.base.play_rect.position.y),
		"два расширения этажа: 28×28, новая часть — пол")
	_check(run.use_gateway() and run.drone.world == run.base, "после «Подземного этажа» дрон проходит через шлюз")
	run.drone.move_input = Vector2(-1, 0)
	for i in 30 * 10:
		run.step()
	_check(run.drone.position.x >= run.base.get_play_rect_px().position.x - 0.01, "дрон не вылетает за открытую часть этажа")
	run.dispose()

	var creative := Run.create(null, LevelMap.new(64, 64, Registry.get_floor(&"stone").index), true)
	_check(creative.get_pad_size() == 40 and creative.base.play_rect.size == Vector2i(46, 46) and creative.can_use_gateway(),
		"в творческом режиме площадка 40, этаж 46 и проход открыты сразу")
	creative.dispose()


## Шлюз: передача предметов закрыта исследованием, «Порты шлюза» добавляют вход и выход.
func _test_gateway_ports() -> void:
	var run := _floors_run([&"underground"])
	var gate := run.get_gateway(run.planet)
	var pair := run.get_gateway(run.base)
	var hematite := _item(&"hematite")
	var inputs := gate.get_gateway_def().get_port_tiles(gate.origin, gate.get_size(), gate.get_input_side(), 2)
	var outputs := pair.get_gateway_def().get_port_tiles(pair.origin, pair.get_size(), pair.get_output_side(), 2)
	var sources: Array[Building] = []
	var sinks: Array[Building] = []
	for k in 2:
		var src := run.planet.buildings.place(Worlds.source_def(), inputs[k], 0, true)
		src.set("items", PackedInt32Array([hematite]))
		sources.append(src)
		sinks.append(run.base.buildings.place(Worlds.sink_def(), outputs[k], 0, true))
	for i in 150:
		run.step()
	_check(run.link.size_of(true) == 0 and sinks[0].received == 0, "без «Передачи предметов» шлюз ничего не принимает")
	run.research.done[&"gateway_items"] = true
	run.apply_research_effects()
	for i in 150:
		run.step()
	var before: int = sinks[0].received + sinks[1].received
	for i in 600:
		run.step()
	var one_port: float = (sinks[0].received + sinks[1].received - before) / 20.0
	_check(absf(one_port - 6.0) < 0.5 and sinks[1].received == 0, "один порт: %.1f предм./с только через средний" % one_port)
	run.research.done[&"gateway_ports_1"] = true
	run.apply_research_effects()
	_check(gate.port_count() == 2 and gate.get_input_tiles() == inputs, "«Порты шлюза I»: второй вход и выход")
	for i in 150:
		run.step()
	before = sinks[0].received + sinks[1].received
	for i in 600:
		run.step()
	var two_ports: float = (sinks[0].received + sinks[1].received - before) / 20.0
	_check(absf(two_ports - 12.0) < 1.0 and sinks[1].received > 0, "два порта: %.1f предм./с" % two_ports)
	run.dispose()


## Аккумулятор: заряжается излишком, покрывает нехватку, запас сохраняется.
func _test_accumulator() -> void:
	var world := Worlds.empty_world(32, 20)
	var bm := world.buildings
	var acc_def := Registry.get_building(&"accumulator") as AccumulatorDef
	_check(acc_def != null and is_equal_approx(acc_def.capacity_kj, 5000.0) and is_equal_approx(acc_def.max_rate, 300.0), "аккумулятор: 5 МДж, 300 кВт")
	var pole := bm.place(Registry.get_building(&"small_power_pole"), Vector2i(10, 8), 0, true)
	var acc := bm.place(acc_def, Vector2i(11, 9), 0, true) as Accumulator
	var generator := bm.place(Registry.get_building(&"thermal_generator"), Vector2i(8, 9), 0, true) as Generator
	var assembler := bm.place(Registry.get_building(&"assembler"), Vector2i(11, 6), 0, true) as Crafter
	world.configure(assembler, &"gear")
	for i in 3:
		generator.handle_item(null, _item(&"coal"))
	for i in 40:
		assembler.handle_item(null, _item(&"iron_ingot"))
	Worlds.run_ticks(world, 2 * GameConst.TICK_RATE)
	_check(pole.power_net != null and pole.power_net.storages.has(acc), "аккумулятор в сети опоры")
	_check(absf(acc.stored_kj - 150.0) < 6.0, "излишек 150 − 75 кВт заряжает: %.0f кДж за 2 с (≈150)" % acc.stored_kj)
	# Без генератора аккумулятор питает сборщик.
	bm.remove(generator, true)
	acc.stored_kj = 1000.0
	assembler.outputs[_item(&"gear")] = 0
	for i in 40:
		assembler.handle_item(null, _item(&"iron_ingot"))
	Worlds.run_ticks(world, 3 * GameConst.TICK_RATE)
	var net := assembler.power_net
	_check(net != null and is_equal_approx(net.satisfaction, 1.0) and assembler.outputs[_item(&"gear")] >= 5, "без генератора сборщик работает от аккумулятора")
	_check(absf(acc.stored_kj - (1000.0 - 75.0 * 3.0)) < 10.0, "разряд по спросу: %.0f кДж (≈775)" % acc.stored_kj)
	acc.stored_kj = 10.0
	Worlds.run_ticks(world, 30)
	_check(acc.stored_kj == 0.0 and assembler.power_net.satisfaction < 1.0, "пустой аккумулятор не спасает")
	var copy := bm.place(acc_def, Vector2i(20, 12), 0, true) as Accumulator
	acc.stored_kj = 1234.0
	copy.load_state(acc.save_state())
	_check(is_equal_approx(copy.stored_kj, 1234.0), "запас аккумулятора сохраняется")
	world.dispose()


## Ток и жидкости между этажами: открываются исследованиями, шлюз соединяет сети.
func _test_power_and_fluids_between_floors() -> void:
	var run := _floors_run([&"underground"])
	var planet := run.planet
	var base := run.base
	var gate := run.get_gateway(planet)
	var pair := run.get_gateway(base)
	planet.buildings.place(Registry.get_building(&"small_power_pole"), gate.origin + Vector2i(-1, -1), 0, true)
	var generator := planet.buildings.place(Registry.get_building(&"thermal_generator"), gate.origin + Vector2i(-4, -3), 0, true) as Generator
	for i in 5:
		generator.handle_item(null, _item(&"coal"))
	base.buildings.place(Registry.get_building(&"small_power_pole"), pair.origin + Vector2i(-1, -1), 0, true)
	var assembler := base.buildings.place(Registry.get_building(&"assembler"), pair.origin + Vector2i(-4, -3), 0, true) as Crafter
	base.configure(assembler, &"gear")
	for i in 30:
		assembler.handle_item(null, _item(&"iron_ingot"))
	for i in 60:
		run.step()
	_check(assembler.get_status() == Building.Status.NO_POWER and assembler.outputs[_item(&"gear")] == 0, "без «Передачи энергии» этаж без тока")
	run.research.done[&"gateway_power"] = true
	run.apply_research_effects()
	for i in 3 * GameConst.TICK_RATE:
		run.step()
	var net := assembler.power_net
	_check(gate.power_net != null and pair.power_net != null and net.linked and is_equal_approx(net.satisfaction, 1.0), "шлюз соединяет сети площадки и этажа")
	_check(assembler.outputs[_item(&"gear")] >= 5 and generator.last_output_kw > 70.0, "сборщик этажа работает от генератора планеты (%d)" % assembler.outputs[_item(&"gear")])

	# Жидкости: насос над шлюзом — трубы в порт шлюза — вода выходит из порта пары.
	var pump_tile := Vector2i(24, 10)
	planet.buildings.place(Registry.get_building(&"pump"), pump_tile, 0, true)
	var up_side := gate.get_fluid_side(1)
	var gate_port := gate.get_rect().get_center()
	var pipe_line := Vector2i(24, gate.origin.y - 1) if up_side == GameConst.Dir.UP else Vector2i(24, gate.origin.y + 3)
	for y in range(pump_tile.y + 1, pipe_line.y + 1):
		planet.buildings.place(Registry.get_building(&"pipe"), Vector2i(24, y), 0, true)
	var pair_side := pair.get_fluid_side(1)
	var base_pipe := pair.origin + Vector2i(1, -1) if pair_side == GameConst.Dir.UP else pair.origin + Vector2i(1, 3)
	var tank := base.buildings.place(Registry.get_building(&"pipe"), base_pipe, 0, true)
	for i in 5 * GameConst.TICK_RATE:
		run.step()
	_check(base.fluids.get_pipe_network(tank) == null or base.fluids.get_pipe_network(tank).amount == 0.0, "без «Передачи жидкостей» вода на этаж не идёт")
	run.research.done[&"gateway_fluids"] = true
	run.apply_research_effects()
	for i in 5 * GameConst.TICK_RATE:
		run.step()
	var tank_net := base.fluids.get_pipe_network(tank)
	_check(gate_port != Vector2i.ZERO and tank_net != null and tank_net.fluid == Registry.get_fluid(&"water").index and tank_net.amount > 50.0,
		"вода перетекла через шлюз на этаж (%.0f)" % (tank_net.amount if tank_net != null else -1.0))
	run.dispose()


## Лифт: место, пара на другом этаже, предметы в обе стороны, дрон, снос пары, переезд, сохранение.
func _test_lift() -> void:
	var run := _floors_run([&"underground", &"underground_1", &"lift"])
	var planet := run.planet
	var base := run.base
	var lift_def := Registry.get_building(&"lift") as LiftDef
	var hematite := _item(&"hematite")
	var inside := run.planet.pad_rect.position + Vector2i(4, 3)
	_check(run._check_lift(planet, lift_def, run.planet.pad_rect.position + Vector2i(-3, 3)) == BuildingManager.Check.LIFT_AREA, "вне площадки лифт не ставится")
	var blocker := base.buildings.place(Registry.get_building(&"container"), run.pair_origin(planet, inside), 0, true)
	_check(run._check_lift(planet, lift_def, inside) == BuildingManager.Check.LIFT_PAIR, "место пары занято — нельзя")
	base.buildings.remove(blocker, true)
	_check(run._check_lift(planet, lift_def, inside) == BuildingManager.Check.OK, "место для лифта и его пары свободно")
	var top := planet.buildings.place(lift_def, inside, 0, true) as Lift
	var bottom := base.buildings.get_at(run.pair_origin(planet, inside)) as Lift
	_check(top != null and bottom != null and top.pair == bottom and bottom.pair == top, "пара лифта появилась на этаже в том же месте")
	var source := planet.buildings.place(Worlds.source_def(), inside + Vector2i(-1, 0), 0, true)
	source.set("items", PackedInt32Array([hematite]))
	var down_sink := base.buildings.place(Worlds.sink_def(), bottom.origin + Vector2i(2, 0), 0, true)
	for i in 10 * GameConst.TICK_RATE:
		run.step()
	_check(down_sink.received >= 55 and down_sink.received <= 62, "вниз едет со скоростью ленты: %d за 10 с" % down_sink.received)
	planet.buildings.remove(source, true)
	var up_source := base.buildings.place(Worlds.source_def(), bottom.origin + Vector2i(-1, 0), 0, true)
	up_source.set("items", PackedInt32Array([_item(&"brick")]))
	var up_sink := planet.buildings.place(Worlds.sink_def(), top.origin + Vector2i(2, 1), 0, true)
	base.configure(bottom, Lift.Direction.UP)
	_check(top.direction == Lift.Direction.UP and bottom.is_source() and not top.is_source(), "направление — общая настройка пары")
	for i in 5 * GameConst.TICK_RATE:
		run.step()
	var up_before: int = up_sink.count_of(_item(&"brick"))
	for i in 5 * GameConst.TICK_RATE:
		run.step()
	var up_rate: int = up_sink.count_of(_item(&"brick")) - up_before
	_check(up_rate >= 27 and up_rate <= 31, "вверх тоже едет со скоростью ленты: %d за 5 с" % up_rate)
	# Дрон через лифт.
	run.drone.world = planet
	run.drone.position = top.get_world_center()
	_check(run.can_use_gateway() and run.use_gateway() and run.drone.world == base and bottom.get_world_rect().has_point(run.drone.position),
		"дрон переходит через лифт на этаж")
	run.drone.world = planet
	run.drone.position = run.get_gateway(planet).get_world_center()
	# Сохранение: пара и направление восстанавливаются.
	var loaded := SaveIO.run_from_dict(bytes_to_var(var_to_bytes(SaveIO.run_to_dict(run))))
	var loaded_top := loaded.planet.buildings.get_at(inside) as Lift
	_check(loaded_top != null and loaded_top.pair != null and loaded_top.pair.world == loaded.base and loaded_top.direction == Lift.Direction.UP,
		"после загрузки лифт снова в паре, направление прежнее")
	loaded.dispose()
	# Переезд: лифт на площадке переезжает и снова находит пару на этаже.
	base.buildings.remove(up_source, true)
	var offset := top.origin - planet.pad_rect.position
	var next := run.star_map.get_next()
	run.start_teleport(next[0].id)
	for i in Registry.run_def.get_charge_ticks() + 1:
		run.step()
	var moved := run.planet.buildings.get_at(run.planet.pad_rect.position + offset) as Lift
	_check(run.planet != planet and moved != null and moved.pair == bottom and bottom.pair == moved, "после телепорта лифт площадки снова в паре")
	# Снос одного лифта сносит пару.
	base.buildings.remove(bottom, true)
	_check(moved.world == null and bottom.world == null, "снос лифта на этаже сносит и лифт на площадке")
	run.dispose()


## Окно опоры: нагрузка, заряд, график за последние минуты, состав сети.
func _test_power_window() -> void:
	var world := Worlds.empty_world(32, 20)
	var bm := world.buildings
	var pole := bm.place(Registry.get_building(&"small_power_pole"), Vector2i(10, 8), 0, true) as PowerPole
	bm.place(Registry.get_building(&"accumulator"), Vector2i(11, 9), 0, true)
	var generator := bm.place(Registry.get_building(&"thermal_generator"), Vector2i(8, 9), 0, true) as Generator
	generator.handle_item(null, _item(&"coal"))
	var assembler := bm.place(Registry.get_building(&"assembler"), Vector2i(11, 6), 0, true) as Crafter
	world.configure(assembler, &"gear")
	for i in 40:
		assembler.handle_item(null, _item(&"iron_ingot"))
	Worlds.run_ticks(world, PowerGraph.HISTORY_TICKS * 5)
	var sections := pole.get_window_sections()
	var kinds := PackedStringArray()
	for sec in sections:
		kinds.append(str(sec.kind))
	_check(sections.size() == 4 and sections[2].kind == WindowSection.Kind.GRAPH and sections[3].kind == WindowSection.Kind.TEXT,
		"окно опоры: нагрузка, заряд, график, состав (%s)" % ",".join(kinds))
	_check(sections[2].series.size() == 4 and sections[2].series[0].size() == 5 and sections[2].series[0][4] > 70.0,
		"график: спрос, выработка, возможная выработка, заряд; 5 точек, спрос ≈75 кВт")
	_check(sections[2].series[2].size() == 5 and sections[2].series[2][4] >= sections[2].series[1][4],
		"ряд возможной выработки не ниже фактической")
	_check(sections[3].lines[0].contains("×1") and sections[3].lines[1].contains("×1"), "состав сети: источники и потребители")
	world.dispose()
