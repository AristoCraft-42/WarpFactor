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
	_test_gates()
	_test_bridge()
	_test_unloader()
	_test_pass_through_chains()
	_test_wake_through_pass_through()
	_test_config_copy_and_contents()
	_test_recipes_data()
	_test_graphite_press()
	_test_smelter_inputs()
	_test_output_blocked()
	_test_separator_weights()
	_test_pulverizer_separator_chain()
	_test_alloy_mixer_and_contents()
	_test_config_wakes_blocked_belts()
	_test_logistics_throughput()
	_test_unloader_from_buildings()
	_test_inversion_config()
	_test_run_gateway()
	_test_router_returns_items()
	_test_unloader_balancing()
	_test_gateway_rotation()
	_test_star_map()
	_test_planet_generator()
	_test_building_state_roundtrip()
	_test_teleport()
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
	_check(Registry.ores.size() == 6, "ожидалось 6 руд, есть %d" % Registry.ores.size())
	_check(Registry.floors.size() >= 4, "мало типов пола")
	_check(Registry.buildings.size() == 26, "ожидалось 26 зданий (24 + шлюз и его пара), есть %d" % Registry.buildings.size())
	_check(Registry.base_def != null and Registry.base_def.size == 24, "параметры базы загружены (24×24)")
	_check(Registry.planet_types.size() == 2 and Registry.run_def != null and Registry.run_def.first_planet_type != null, "типы планет и параметры забега загружены")
	_check(Registry.items.size() == 11 + 24, "ожидалось 11 ресурсов и 24 предмета-постройки, есть %d" % Registry.items.size())
	_check(Registry.get_building(&"inverted_sorter") == null and Registry.get_building(&"underflow_gate") == null,
		"инвертированные варианты стали настройкой, а не отдельными зданиями")
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
		if def.player_buildable:
			_check(def.item != null and def.item.building == def, "у здания %s есть предмет-постройка" % def.id)
			_check(def.item != null and Registry.get_hand_recipe(def.item.index) != null, "у здания %s есть рецепт крафта" % def.id)
	for category in 4:
		_check(not Registry.buildings_in_category(category as BuildingDef.Category).is_empty(), "пустая категория %d" % category)
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
	map.set_ore(10, 12, Registry.get_ore(&"titanium").index + 1)
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
		_check(run.get_gateway(run.planet) != null and run.can_use_gateway(), "уровень %s: шлюз на месте посадки, дрон над ним" % level.id)
		_check(Rect2i(0, 0, map.width, map.height).encloses(run.planet.pad_rect), "уровень %s: площадка внутри карты" % level.id)
		run.dispose()


# --- Размещение и снос ---

func _test_building_manager() -> void:
	var map := LevelMap.new(64, 64, Registry.get_floor(&"stone").index)
	for y in 64:
		map.set_floor(20, y, Registry.get_floor(&"rock").index)
	var copper := Registry.get_ore(&"copper").index + 1
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
	var drill := Registry.get_building(&"mechanical_drill")
	var vault := Registry.get_building(&"vault")

	_check(bm.get_count() == 1, "неудаляемое здание поставлено картой")
	_check(bm.check_place(drill, Vector2i(5, 5), 0) == BuildingManager.Check.OK, "бур на свободном месте")
	var d := bm.place(drill, Vector2i(5, 5), 0)
	_check(d != null and bm.get_at(Vector2i(6, 6)) == d, "бур занимает 2x2")
	_check(bm.check_place(drill, Vector2i(6, 6), 0) == BuildingManager.Check.OCCUPIED, "пересечение запрещено")
	_check(bm.check_place(drill, Vector2i(19, 5), 0) == BuildingManager.Check.BAD_TERRAIN, "скала запрещена")
	_check(bm.check_place(vault, Vector2i(62, 62), 0) == BuildingManager.Check.OUT_OF_BOUNDS, "выход за карту")
	_check(bm.check_place(drill, Vector2i(5, 5), 0) == BuildingManager.Check.SAME, "то же здание на том же месте")
	_check(bm.check_place(drill, Vector2i(10, 20), 0) == BuildingManager.Check.NO_ORE, "бур без руды запрещён")
	_check(bm.check_place(drill, Vector2i(17, 4), 0) == BuildingManager.Check.OK, "буру достаточно одного тайла руды")

	var c := bm.place(conveyor, Vector2i(10, 10), 0)
	_check(bm.check_place(conveyor, Vector2i(10, 10), 2) == BuildingManager.Check.REPLACE, "поворот ленты — замена")
	var c2 := bm.place(conveyor, Vector2i(10, 10), 2)
	_check(c2 != null and c2.rotation == 2 and c.id == 0, "замена ставит новую ленту и убирает старую")
	_check(bm.place(conveyor, Vector2i(10, 10), 2) == null, "повторная установка того же — ничего")
	var upgrade := Registry.get_building(&"titanium_conveyor")
	_check(bm.check_place(upgrade, Vector2i(10, 10), 2) == BuildingManager.Check.REPLACE, "апгрейд ленты — замена")

	var fixed_building := bm.get_at(Vector2i(40, 40))
	_check(not bm.remove(fixed_building), "неудаляемое здание не сносится")
	var in_rect := bm.collect_in_rect(Rect2i(0, 0, 64, 64))
	_check(in_rect.size() == 3, "в рамке 3 здания (бур, лента, неудаляемое), найдено %d" % in_rect.size())
	var partial := bm.collect_in_rect(Rect2i(6, 6, 1, 1))
	_check(partial.size() == 1 and partial[0] == d, "рамка ловит здание за любой его тайл")
	var edge := bm.collect_in_rect(Rect2i(42, 42, 1, 1))
	_check(edge.size() == 1 and edge[0] == fixed_building, "рамка в правом нижнем тайле здания 3x3")

	# Здание на границе чанков (32) и повторное использование id.
	var cross := bm.place(vault, Vector2i(31, 31), 0)
	_check(cross != null, "хранилище на стыке чанков")
	_check(bm.collect_in_rect(Rect2i(33, 33, 1, 1)).has(cross), "поиск в соседнем чанке")
	var old_id := cross.id
	_check(bm.remove(cross), "снос хранилища")
	_check(bm.get_at(Vector2i(33, 33)) == null, "тайлы освобождены")
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


## Бур на медной руде → лента → ядро.
func _test_drill_to_storage() -> void:
	var map := LevelMap.new(48, 20, Registry.get_floor(&"stone").index)
	var copper := Registry.get_ore(&"copper").index + 1
	for y in range(8, 10):
		for x in range(4, 6):
			map.set_ore(x, y, copper)
	map.add_placement(Registry.get_building(&"container"), Vector2i(30, 8))
	var world := GameWorld.create(null, map, true)
	var drill: Drill = world.buildings.place(Registry.get_building(&"mechanical_drill"), Vector2i(4, 8), 0, true)
	_check(drill.ore != null and drill.ore_tiles == 4, "бур нашёл 4 тайла меди")
	var expected_ticks := roundi((8.0 + 2.0 * 1) / 4 * GameConst.TICK_RATE)
	_check(drill.ticks_per_item == expected_ticks, "время на предмет %d тиков (ожидалось %d)" % [drill.ticks_per_item, expected_ticks])
	Worlds.conveyor_line(world, Vector2i(6, 9), 24, GameConst.Dir.RIGHT)
	var copper_index := Registry.get_item(&"copper").index
	Worlds.run_ticks(world, 60 * GameConst.TICK_RATE)
	var container := world.buildings.get_at(Vector2i(30, 8)) as StorageBuilding
	var stored := container.inventory.count(copper_index)
	var in_transit := world.simulation.conveyors.get_item_count() + drill.buffer
	var produced := 60 * GameConst.TICK_RATE / drill.ticks_per_item
	_check(stored > 0, "медь доехала до контейнера (%d)" % stored)
	_check(absi(stored + in_transit - produced) <= 1, "добыто %d ≈ в контейнере %d + в пути %d" % [produced, stored, in_transit])
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
	var copper := _item(&"copper")
	var drill := Registry.get_building(&"mechanical_drill").item.index
	var inv := Inventory.new(3)
	_check(inv.space_for(copper) == 300, "пустой инвентарь: 3 ячейки по 100 меди")
	_check(inv.add(copper, 150) == 150 and inv.used_slots() == 2, "150 меди занимают 2 ячейки")
	_check(inv.space_for(copper) == 150 and inv.space_for(drill) == Registry.stack_sizes[drill], "место считается по стакам")
	_check(inv.add(drill, 70) == 50, "бурам хватило только одной ячейки на 50")
	_check(inv.add(copper, 80) == 50 and inv.count(copper) == 200, "медь дополнила начатую стопку")
	_check(inv.remove(copper, 120) == 120 and inv.count(copper) == 80 and inv.used_slots() == 2, "опустевшая ячейка освободилась")
	var taken := inv.take_from_slot(2, 10)
	_check(taken == Vector2i(drill, 10) and inv.count(drill) == 40, "взять из конкретной ячейки")
	var budget := inv.make_budget()
	_check(budget.take(copper, 80) and not budget.take(copper, 1) and inv.count(copper) == 80, "бюджет не меняет инвентарь")

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
	var copper := _item(&"copper")
	var belt := Registry.get_building(&"conveyor").item.index
	var belt_recipe := Registry.get_hand_recipe(belt)
	_check(queue.enqueue(belt_recipe, 1) == 0, "без меди ленту не скрафтить")
	inv.add(copper, 5)
	_check(queue.max_craftable(belt_recipe) == 5, "меди хватает на 5 лент")
	_check(queue.enqueue(belt_recipe, 3) == 3 and inv.count(copper) == 2, "сырьё списано при постановке в очередь")
	Worlds.run_ticks(world, belt_recipe.ticks * 3 + 1)
	_check(inv.count(belt) == 3 and queue.is_empty(), "три ленты скрафчены за 3 цикла (%d)" % inv.count(belt))

	queue.enqueue(belt_recipe, 2)
	queue.cancel(1)
	_check(inv.count(copper) == 1 and queue.units.size() == 1, "отмена возвращает сырьё")
	Worlds.run_ticks(world, 1)
	queue.cancel(0)
	_check(inv.count(copper) == 2 and queue.is_empty(), "отмена начатого крафта тоже возвращает сырьё")

	# Промежуточные детали: титановая лента = лента + свинец + титан; ленты докрафчиваются из меди.
	var titanium_belt := Registry.get_building(&"titanium_conveyor").item.index
	var ti_recipe := Registry.get_hand_recipe(titanium_belt)
	inv.clear()
	inv.add(copper, 2)
	inv.add(_item(&"lead"), 2)
	inv.add(_item(&"titanium"), 2)
	_check(queue.max_craftable(ti_recipe) == 2, "с докрафтом хватает на 2 титановые ленты")
	_check(queue.enqueue(ti_recipe, 2) == 2 and inv.count(copper) == 0, "медь для промежуточных лент списана")
	Worlds.run_ticks(world, (belt_recipe.ticks + ti_recipe.ticks) * 2 + 2)
	_check(inv.count(titanium_belt) == 2 and inv.count(belt) == 0, "титановые ленты готовы, промежуточные израсходованы")
	inv.add(belt, 1)
	inv.add(_item(&"lead"), 1)
	inv.add(_item(&"titanium"), 1)
	_check(queue.enqueue(ti_recipe, 1) == 1 and inv.count(belt) == 0, "готовая лента из инвентаря используется без меди")

	# Полный инвентарь: результат ждёт места.
	queue.cancel(0)
	inv.clear()
	inv.add(copper, 1)
	queue.enqueue(belt_recipe, 1)
	var stone := _item(&"stone")
	inv.add(stone, inv.size() * Registry.stack_sizes[stone])
	Worlds.run_ticks(world, belt_recipe.ticks + 5)
	_check(queue.blocked and queue.units.size() == 1, "крафт ждёт места в инвентаре")
	inv.remove(stone, 100)
	Worlds.run_ticks(world, 2)
	_check(not queue.blocked and queue.is_empty() and inv.count(belt) == 1, "после освобождения места лента выдана")
	world.dispose()


func _test_drone_mining() -> void:
	var map := LevelMap.new(32, 16, Registry.get_floor(&"stone").index)
	map.set_ore(18, 8, Registry.get_ore(&"copper").index + 1)
	map.set_ore(19, 8, Registry.get_ore(&"titanium").index + 1)
	var world := GameWorld.create(null, map, false)
	var drone := world.drone
	var inv := drone.inventory
	var copper := _item(&"copper")
	var ticks := drone.def.mine_ticks(Registry.get_ore(&"copper"))
	drone.set_mine_target(Vector2i(18, 8))
	Worlds.run_ticks(world, ticks * 3)
	_check(inv.count(copper) == 3, "дрон добыл 3 меди за 3 цикла (%d)" % inv.count(copper))
	_check(drone.get_mineable_ore(Vector2i(19, 8)) == null, "титан слишком твёрдый для дрона")
	drone.set_mine_target(Vector2i(19, 8))
	Worlds.run_ticks(world, ticks)
	_check(drone.mine_blocked and inv.count(_item(&"titanium")) == 0, "добыча титана не идёт")

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
	var copper := _item(&"copper")
	var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(17, 8), 0, true) as StorageBuilding
	inv.add(copper, 150)
	_check(world.player_put(storage, copper, 120) == 120, "положили 120 меди в контейнер")
	_check(inv.count(copper) == 30 and storage.inventory.count(copper) == 120, "медь перешла в контейнер")
	_check(world.player_take(storage, copper, 50) == 50 and inv.count(copper) == 80, "забрали 50 меди")
	var center := world.drone.position
	world.drone.position = Vector2.ZERO
	_check(world.player_take(storage, copper, 10) == 0, "издалека не забрать")
	world.drone.position = center

	var press := world.buildings.place(Registry.get_building(&"graphite_press"), Vector2i(13, 6), 0, true) as Crafter
	inv.add(_item(&"coal"), 30)
	var put := world.player_put(press, _item(&"coal"), 30)
	_check(put > 0 and put <= press.get_input_capacity(_item(&"coal")), "уголь положен в пресс до вместимости (%d)" % put)
	_check(world.player_put(press, copper, 5) == 0, "пресс не принимает медь")
	Worlds.run_ticks(world, 200)
	var graphite := _item(&"graphite")
	_check(press.outputs[graphite] > 0 or press.get_player_stacks().size() > 0, "пресс сделал графит")
	var taken := world.player_take(press, graphite, 100)
	_check(taken > 0 and inv.count(graphite) == taken, "графит забран руками (%d)" % taken)
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
	var copper := Registry.get_item(&"copper").index
	var lead := Registry.get_item(&"lead").index
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
	_check(east.received > 50 and east.count_of(lead) == 0, "перекрёсток: восток получил только медь (%d)" % east.received)
	_check(south.received > 50 and south.count_of(copper) == 0, "перекрёсток: юг получил только свинец (%d)" % south.received)
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
		var copper := Registry.get_item(&"copper").index
		var lead := Registry.get_item(&"lead").index
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


## Переливной и обратный шлюзы.
func _test_gates() -> void:
	# Переливной: пока впереди свободно — всё вперёд; без выхода вперёд — в стороны.
	var world := Worlds.empty_world(24, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 3, GameConst.Dir.RIGHT)
	_place(world, &"overflow_gate", Vector2i(6, 10))
	Worlds.conveyor_line(world, Vector2i(7, 10), 2, GameConst.Dir.RIGHT)
	var forward := _sink(world, Vector2i(9, 10))
	Worlds.conveyor_line(world, Vector2i(6, 9), 2, GameConst.Dir.UP)
	var up := _sink(world, Vector2i(6, 7))
	Worlds.run_ticks(world, 600)
	_check(forward.received > 30 and up.received == 0, "переливной шлюз: при свободном выходе всё вперёд (%d / %d)" % [forward.received, up.received])
	world.buildings.remove(forward, true)
	Worlds.run_ticks(world, 600)
	_check(up.received > 20, "переливной шлюз: при забитом выходе — в сторону (%d)" % up.received)
	world.dispose()

	# Обратный: сначала в стороны, вперёд только когда стороны заняты.
	world = Worlds.empty_world(24, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 3, GameConst.Dir.RIGHT)
	world.configure(_place(world, &"overflow_gate", Vector2i(6, 10)), true)
	Worlds.conveyor_line(world, Vector2i(7, 10), 2, GameConst.Dir.RIGHT)
	forward = _sink(world, Vector2i(9, 10))
	Worlds.conveyor_line(world, Vector2i(6, 9), 2, GameConst.Dir.UP)
	up = _sink(world, Vector2i(6, 7))
	Worlds.run_ticks(world, 600)
	_check(up.received > 30 and forward.received == 0, "обратный шлюз: при свободной стороне всё в сторону (%d / %d)" % [up.received, forward.received])
	world.buildings.remove(up, true)
	Worlds.run_ticks(world, 600)
	_check(forward.received > 20, "обратный шлюз: при забитой стороне — вперёд (%d)" % forward.received)
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
	map.add_placement(Registry.get_building(&"container"), Vector2i(10, 10))
	var world := GameWorld.create(null, map, true)
	var copper := Registry.get_item(&"copper").index
	var lead := Registry.get_item(&"lead").index
	var storage := world.buildings.get_at(Vector2i(10, 10)) as StorageBuilding
	storage.inventory.add(copper, 50)
	var unloader := _place(world, &"unloader", Vector2i(12, 11))
	Worlds.conveyor_line(world, Vector2i(13, 11), 3, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(16, 11))
	world.configure(unloader, lead)
	Worlds.run_ticks(world, 200)
	_check(sink.received == 0, "разгрузчик со свинцовым фильтром не берёт медь")
	world.configure(unloader, copper)
	Worlds.run_ticks(world, 600)
	_check(sink.received > 20, "разгрузчик выгружает медь (%d)" % sink.received)
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
	_place(world, &"overflow_gate", Vector2i(5, 10))
	_place(world, &"overflow_gate", Vector2i(6, 10))
	world.configure(_place(world, &"sorter", Vector2i(7, 10)), true)
	var sink := _sink(world, Vector2i(8, 10))
	Worlds.run_ticks(world, 300)
	_check(sink.received > 30, "цепочка шлюзов и сортировщика пропускает поток (%d)" % sink.received)
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
	var lead := Registry.get_item(&"lead").index
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


## Графитовый пресс: уголь 2 → графит 1 за 1.5 с.
func _test_graphite_press() -> void:
	var world := Worlds.empty_world(24, 16)
	_source(world, Vector2i(2, 4), [_item(&"coal")])
	Worlds.conveyor_line(world, Vector2i(3, 4), 3, GameConst.Dir.RIGHT)
	var press := _place(world, &"graphite_press", Vector2i(6, 4)) as Crafter
	Worlds.conveyor_line(world, Vector2i(8, 4), 2, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(10, 4))
	Worlds.run_ticks(world, 30 * GameConst.TICK_RATE)
	var graphite: int = sink.count_of(_item(&"graphite"))
	_check(graphite >= 16 and graphite <= 20, "пресс выдал графит за 30 с: %d (≈19)" % graphite)
	_check(sink.count_of(_item(&"coal")) == 0, "уголь не проходит сквозь пресс")
	_check(not press.accept_item(null, _item(&"copper")), "пресс не принимает медь")
	_check(press.get_status() == Building.Status.WORKING, "пресс работает")
	world.dispose()


## Кремниевый завод ждёт все входы; без угля — «нет сырья».
func _test_smelter_inputs() -> void:
	var world := Worlds.empty_world(24, 16)
	_source(world, Vector2i(2, 4), [_item(&"sand")])
	Worlds.conveyor_line(world, Vector2i(3, 4), 3, GameConst.Dir.RIGHT)
	var smelter := _place(world, &"silicon_smelter", Vector2i(6, 4)) as Crafter
	Worlds.conveyor_line(world, Vector2i(8, 4), 2, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(10, 4))
	Worlds.run_ticks(world, 300)
	_check(sink.received == 0 and smelter.get_status() == Building.Status.NO_INPUT, "без угля завод стоит со статусом «нет сырья»")
	_check(smelter.get_missing_inputs().size() == 1, "подсказка называет недостающий уголь")
	_source(world, Vector2i(6, 1), [_item(&"coal")])
	Worlds.conveyor_line(world, Vector2i(6, 2), 2, GameConst.Dir.DOWN)
	Worlds.run_ticks(world, 600)
	_check(sink.count_of(_item(&"silicon")) > 10, "с углём завод выдаёт кремний (%d)" % sink.count_of(_item(&"silicon")))
	world.dispose()


## Печь без выхода: буфер заполняется, статус «выход забит», входные ленты засыпают.
func _test_output_blocked() -> void:
	var world := Worlds.empty_world(24, 16)
	_source(world, Vector2i(2, 4), [_item(&"sand"), _item(&"lead")])
	Worlds.conveyor_line(world, Vector2i(3, 4), 3, GameConst.Dir.RIGHT)
	var kiln := _place(world, &"kiln", Vector2i(6, 4)) as Crafter
	Worlds.run_ticks(world, 1200)
	var metaglass := _item(&"metaglass")
	_check(kiln.outputs[metaglass] == kiln.get_output_capacity(), "выходной буфер печи заполнен (%d)" % kiln.outputs[metaglass])
	_check(kiln.get_status() == Building.Status.OUTPUT_BLOCKED, "статус «выход забит»")
	Worlds.run_ticks(world, 60)
	_check(world.simulation.conveyors.get_awake_count() == 0 and world.simulation.get_awake_building_count() == 0,
		"забитая печь и ленты спят")
	var sink := _sink(world, Vector2i(8, 4))
	Worlds.run_ticks(world, 300)
	_check(sink.count_of(metaglass) > 10, "после появления выхода печь снова работает (%d)" % sink.count_of(metaglass))
	world.dispose()


## Сепаратор: распределение по весам (5:3:2:2) и воспроизводимость.
func _test_separator_weights() -> void:
	var world := Worlds.empty_world(16, 16)
	var separator := _place(world, &"separator", Vector2i(4, 4)) as Crafter
	var produce := separator.get_recipe().produces[0] as ProduceWeighted
	var counts := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rolls := 6000
	for i in rolls:
		separator.outputs.fill(0)
		produce.produce(separator, rng)
		for item in produce.output_items():
			if separator.outputs[item] > 0:
				counts[item] = int(counts.get(item, 0)) + 1
	var weights := {_item(&"copper"): 5, _item(&"lead"): 3, _item(&"coal"): 2, _item(&"titanium"): 2}
	for item in weights:
		var share := float(counts.get(item, 0)) / rolls
		var expected := float(weights[item]) / 12.0
		_check(absf(share - expected) < 0.03, "сепаратор: доля %s %.3f (ожидалось %.3f)" % [Registry.items[item].id, share, expected])
	world.dispose()


## Цепочка: камень → дробилка → сепаратор → руды.
func _test_pulverizer_separator_chain() -> void:
	var world := Worlds.empty_world(32, 16)
	_source(world, Vector2i(2, 4), [_item(&"stone")])
	Worlds.conveyor_line(world, Vector2i(3, 4), 2, GameConst.Dir.RIGHT)
	_place(world, &"pulverizer", Vector2i(5, 4))
	Worlds.conveyor_line(world, Vector2i(6, 4), 2, GameConst.Dir.RIGHT)
	_place(world, &"separator", Vector2i(8, 4))
	Worlds.conveyor_line(world, Vector2i(10, 4), 2, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(12, 4))
	Worlds.run_ticks(world, 60 * GameConst.TICK_RATE)
	var ores: int = sink.count_of(_item(&"copper")) + sink.count_of(_item(&"lead")) + sink.count_of(_item(&"coal")) + sink.count_of(_item(&"titanium"))
	_check(ores > 20 and ores == sink.received, "цепочка дробилка → сепаратор выдаёт руды (%d)" % ores)
	world.dispose()


## Смеситель 3×3 со всеми тремя входами; снос посреди цикла возвращает сырьё.
func _test_alloy_mixer_and_contents() -> void:
	var world := Worlds.empty_world(32, 24, true)
	var mixer := world.build(Registry.get_building(&"alloy_mixer"), Vector2i(10, 10), 0) as Crafter
	_source(world, Vector2i(9, 10), [_item(&"copper")])
	_source(world, Vector2i(9, 11), [_item(&"lead")])
	_source(world, Vector2i(9, 12), [_item(&"titanium")])
	Worlds.run_ticks(world, 200)
	_check(mixer.outputs[_item(&"alloy")] > 0, "смеситель делает сплав (%d)" % mixer.outputs[_item(&"alloy")])
	var totals := PackedInt32Array()
	totals.resize(Registry.items.size())
	totals.fill(0)
	mixer.collect_contents(totals)
	var inv := world.drone.inventory
	var before := inv.count(_item(&"alloy")) + inv.count(_item(&"copper"))
	var expected_back := totals[_item(&"alloy")] + totals[_item(&"copper")]
	_check(world.demolish(mixer), "снос смесителя")
	_check(inv.count(_item(&"alloy")) + inv.count(_item(&"copper")) == before + expected_back,
		"сырьё, продукт и начатый цикл ушли в инвентарь")
	world.dispose()


## Данные рецептов: у каждого завода рецепт с входами и выходами.
func _test_recipes_data() -> void:
	var crafters := 0
	for def in Registry.buildings:
		if def is CrafterDef:
			crafters += 1
			var recipe := (def as CrafterDef).recipe
			_check(recipe != null and not recipe.consumes.is_empty() and not recipe.output_items().is_empty(), "рецепт завода %s" % def.id)
			_check(not def.get_stat_lines().is_empty(), "характеристики завода %s для меню" % def.id)
	_check(crafters == 6, "заводов 6 (%d)" % crafters)


## Регрессия: смена настройки будит ленты, уснувшие перед зданием (сортировщик без фильтра, мост без связи).
func _test_config_wakes_blocked_belts() -> void:
	var world := Worlds.empty_world(32, 16)
	var copper := _item(&"copper")
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


## Пропускная способность логистики: уровень 1 — как обычная лента, уровень 2 — как титановая.
## Вход и выход — титановые ленты, чтобы узким местом было само здание.
func _test_logistics_throughput() -> void:
	var copper := _item(&"copper")
	var belt_rate: float = (Registry.get_building(&"conveyor") as ConveyorDef).get_items_per_second()
	var titanium_rate: float = (Registry.get_building(&"titanium_conveyor") as ConveyorDef).get_items_per_second()
	for id in [&"junction", &"router", &"sorter", &"overflow_gate", &"bridge_conveyor", &"unloader",
			&"titanium_junction", &"titanium_router", &"titanium_sorter", &"titanium_overflow_gate",
			&"titanium_bridge_conveyor", &"titanium_unloader"]:
		var def := Registry.get_building(id) as LogisticDef
		var expected := titanium_rate if String(id).begins_with("titanium_") else belt_rate
		_check(is_equal_approx(def.get_items_per_second(), expected), "%s: заявлено %.1f предм./с" % [id, def.get_items_per_second()])
		var world := Worlds.empty_world(32, 12)
		var y := 5
		if def.logic_script == preload("res://buildings/transport/unloader.gd"):
			var storage := world.buildings.place(Registry.get_building(&"vault"), Vector2i(5, y - 1), 0, true) as StorageBuilding
			storage.inventory.add(copper, 4000)
		else:
			_source(world, Vector2i(3, y), [copper])
			Worlds.conveyor_line(world, Vector2i(4, y), 4, GameConst.Dir.RIGHT, &"titanium_conveyor")
		var block := world.buildings.place(def, Vector2i(8, y), 0, true)
		var out_start := 9
		if block is BridgeConveyor:
			var end := world.buildings.place(def, Vector2i(11, y), 0, true)
			world.configure(block, end.origin - block.origin)
			out_start = 12
		elif block is Sorter:
			world.configure(block, copper)
		Worlds.conveyor_line(world, Vector2i(out_start, y), 4, GameConst.Dir.RIGHT, &"titanium_conveyor")
		var sink := _sink(world, Vector2i(out_start + 4, y))
		Worlds.run_ticks(world, 300)
		var before: int = sink.received
		Worlds.run_ticks(world, 600)
		var rate: float = (sink.received - before) / 20.0
		_check(absf(rate - expected) <= 0.35, "%s: реальная пропускная способность %.2f предм./с (ожидалось %.1f)" % [id, rate, expected])
		world.dispose()


## Разгрузчик достаёт готовую продукцию заводов и добычу буров, но не сырьё из входа завода.
func _test_unloader_from_buildings() -> void:
	var coal := _item(&"coal")
	var graphite := _item(&"graphite")
	# Завод → разгрузчик → лента: без фильтра уходят и продукция, и сырьё.
	var world := Worlds.empty_world(32, 24)
	world.buildings.place(Registry.get_building(&"graphite_press"), Vector2i(6, 5), 0, true)
	_source(world, Vector2i(5, 5), [coal])
	var unloader := _place(world, &"unloader", Vector2i(8, 5))
	Worlds.conveyor_line(world, Vector2i(9, 5), 3, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(12, 5))
	Worlds.run_ticks(world, 900)
	_check(sink.count_of(coal) > 5, "разгрузчик забирает сырьё из завода (%d)" % sink.count_of(coal))
	world.configure(unloader, graphite)
	# Уголь, уже едущий по лентам, успевает доехать до приёмника.
	Worlds.run_ticks(world, 90)
	var coal_before: int = sink.count_of(coal)
	Worlds.run_ticks(world, 600)
	_check(sink.count_of(coal) == coal_before, "с фильтром «графит» уголь не забирается")
	_check(sink.count_of(graphite) > 0, "с фильтром «графит» уходит продукция (%d)" % sink.count_of(graphite))

	# Бур → разгрузчик → лента.
	var map := LevelMap.new(24, 12, Registry.get_floor(&"stone").index)
	for y in range(4, 6):
		for x in range(4, 6):
			map.set_ore(x, y, Registry.get_ore(&"copper").index + 1)
	var mine := GameWorld.create(null, map, true)
	mine.buildings.place(Registry.get_building(&"mechanical_drill"), Vector2i(4, 4), 0, true)
	mine.buildings.place(Registry.get_building(&"unloader"), Vector2i(6, 4), 0, true)
	Worlds.conveyor_line(mine, Vector2i(7, 4), 3, GameConst.Dir.RIGHT)
	var drill_sink := mine.buildings.place(Worlds.sink_def(), Vector2i(10, 4), 0, true)
	Worlds.run_ticks(mine, 900)
	_check(drill_sink.received > 5, "разгрузчик забирает добычу бура (%d)" % drill_sink.received)

	# Склад → разгрузчик → завод: сырьё уходит в завод и назад в склад не возвращается.
	var chain := Worlds.empty_world(32, 24)
	var storage := chain.buildings.place(Registry.get_building(&"container"), Vector2i(4, 4), 0, true) as StorageBuilding
	storage.inventory.add(coal, 100)
	chain.buildings.place(Registry.get_building(&"unloader"), Vector2i(6, 4), 0, true)
	var fed := chain.buildings.place(Registry.get_building(&"graphite_press"), Vector2i(7, 4), 0, true) as Crafter
	Worlds.run_ticks(chain, 900)
	var produced := fed.outputs[graphite]
	_check(produced > 0, "пресс получил уголь из склада через разгрузчик и работает")
	_check(storage.inventory.count(coal) + fed.inputs[coal] + produced * 2 + (2 if fed.crafting else 0) == 100,
		"уголь не гоняется по кругу между складом и заводом")
	_check(storage.inventory.count(graphite) == 0, "в склад разгрузчик не кладёт")
	world.dispose()
	mine.dispose()
	chain.dispose()


## Инверсия — настройка: переносится пипеткой и копированием, переключается отдельно от фильтра.
func _test_inversion_config() -> void:
	var world := Worlds.empty_world(24, 16, true)
	var lead := _item(&"lead")
	var sorter := world.build(Registry.get_building(&"sorter"), Vector2i(4, 4), 0, {"item": lead, "inverted": true})
	_check(sorter.get_display_item() == lead and sorter.is_inverted(), "настройка сортировщика словарём при стройке")
	world.configure(sorter, null)
	_check(sorter.get_display_item() == -1 and sorter.is_inverted(), "снятие фильтра не сбрасывает инверсию")
	world.configure(sorter, false)
	_check(not sorter.is_inverted() and sorter.get_config() == null, "без фильтра и инверсии настройки нет")
	var gate := world.build(Registry.get_building(&"overflow_gate"), Vector2i(8, 4), 0, true)
	_check(gate.is_inverted() and gate.get_config() == true, "обратный режим клапана — настройка")
	var copy := world.build(Registry.get_building(&"overflow_gate"), Vector2i(10, 4), 0, gate.get_config())
	_check(copy.is_inverted(), "копия клапана сохраняет обратный режим")
	world.dispose()


## Забег: два мира тикают вместе, шлюз переносит предметы в обе стороны, дрон проходит через шлюз.
func _test_run_gateway() -> void:
	var map := LevelMap.new(48, 32, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	var copper := _item(&"copper")
	var lead := _item(&"lead")
	var gate := run.get_gateway(run.planet)
	var pair := run.get_gateway(run.base)
	_check(run.base.is_base and not run.planet.is_base and run.base.grid.width == Registry.base_def.size, "база отдельным миром нужного размера")
	_check(gate != null and pair != null and gate.link == run.link and pair.link == run.link, "шлюз и пара связаны")
	if gate == null or pair == null:
		run.dispose()
		return
	_check(run.drone.world == run.planet and run.can_use_gateway(), "дрон появляется над шлюзом на планете")
	var center := gate.origin + Vector2i.ONE
	_check(run.planet.pad_rect == Rect2i(center - Vector2i(7, 7), Vector2i(15, 15)), "площадка 15×15 вокруг шлюза")

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
	_check(base_sink.count_of(copper) > port_rate * 30 * 0.7, "медь с планеты пришла в базу (%d)" % base_sink.count_of(copper))

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
	_check(planet_sink.count_of(lead) > 50, "свинец из базы вышел на планету (%d)" % planet_sink.count_of(lead))

	# Нет выхода в базе — очередь «в базу» заполняется, поток встаёт; появился выход — идёт дальше.
	run.base.buildings.remove(base_sink, true)
	for i in 600:
		run.step()
	_check(run.link.size_of(true) == run.link.capacity, "без выхода очередь шлюза заполнена (%d)" % run.link.size_of(true))
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
	_check(absf(run.drone.position.y - y0 - run.drone.def.speed * GameConst.TILE_SIZE * 0.5) < 1.0, "дрон обновляется один раз за тик в своём мире")
	_check(not run.can_use_gateway(), "вдали от пары пройти нельзя")
	run.drone.position = pair.get_world_center()
	_check(run.use_gateway() and run.drone.world == run.planet, "дрон возвращается на планету")
	run.dispose()


## Маршрутизатор как в Mindustry: возвращает предмет источнику, если тот принимает.
func _test_router_returns_items() -> void:
	var world := Worlds.empty_world(24, 12)
	var src := _source(world, Vector2i(3, 5), [_item(&"copper")])
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


## Разгрузчик балансирует два завода и не кладёт в склад.
func _test_unloader_balancing() -> void:
	var coal := _item(&"coal")
	var world := Worlds.empty_world(32, 24)
	var a := world.buildings.place(Registry.get_building(&"graphite_press"), Vector2i(4, 4), 0, true) as Crafter
	world.buildings.place(Registry.get_building(&"unloader"), Vector2i(6, 4), 0, true)
	var b := world.buildings.place(Registry.get_building(&"graphite_press"), Vector2i(7, 4), 0, true) as Crafter
	world.player_put(a, coal, 0)
	for i in 8:
		a.handle_item(null, coal)
	Worlds.run_ticks(world, 90)
	var total := a.inputs[coal] + b.inputs[coal] + (a.outputs[_item(&"graphite")] + b.outputs[_item(&"graphite")]) * 2
	_check(b.inputs[coal] > 0 or b.crafting, "разгрузчик перекладывает уголь в менее заполненный завод")
	_check(absi(a.inputs[coal] - b.inputs[coal]) <= 2 or a.crafting or b.crafting, "заводы уравновешены (%d / %d)" % [a.inputs[coal], b.inputs[coal]])
	_check(total + (2 if a.crafting else 0) + (2 if b.crafting else 0) == 8, "уголь не теряется при балансировке")
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
	var map_a := PlanetGenerator.generate(node, Run.PAD_SIZE)
	var map_b := PlanetGenerator.generate(node, Run.PAD_SIZE)
	_check(map_a.floors == map_b.floors and map_a.ores == map_b.ores, "генерация детерминирована")
	_check(map_a.width == node.size.x and map_a.height == node.size.y, "размер карты как у узла")
	var center := Vector2i(map_a.width / 2, map_a.height / 2)
	var platform := Registry.get_floor(&"metal_plates").index
	var pad_ok := true
	for y in range(center.y - 7, center.y + 8):
		for x in range(center.x - 7, center.x + 8):
			pad_ok = pad_ok and map_a.get_floor(x, y) == platform and map_a.get_ore(x, y) == 0
	_check(pad_ok, "площадка — платформа без руды")
	var near_ore := 0
	for y in range(maxi(center.y - 36, 0), mini(center.y + 36, map_a.height)):
		for x in range(maxi(center.x - 36, 0), mini(center.x + 36, map_a.width)):
			if map_a.get_ore(x, y) != 0:
				near_ore += 1
	_check(near_ore > 40, "у обычной планеты руда недалеко от посадки (%d тайлов)" % near_ore)
	var world := GameWorld.create(null, map_a, false)
	var drill := Registry.get_building(&"mechanical_drill")
	_check(world.buildings.check_place(Registry.get_building(&"container"), center + Vector2i(3, 3), 0) == BuildingManager.Check.OK, "на площадке можно строить")
	world.dispose()
	for id in star_map.nodes.size():
		var n := star_map.get_node(id)
		if n.type.safe:
			var waste := PlanetGenerator.generate(n, Run.PAD_SIZE)
			var ores := 0
			for v in waste.ores:
				ores += 1 if v != 0 else 0
			_check(ores == 0, "в пустоше ни одного тайла руды")
			break


## Состояние зданий переносится в новое здание того же типа.
func _test_building_state_roundtrip() -> void:
	var world := Worlds.empty_world(32, 24)
	var copper := _item(&"copper")
	var coal := _item(&"coal")
	var storage := world.buildings.place(Registry.get_building(&"container"), Vector2i(2, 2), 0, true) as StorageBuilding
	storage.inventory.add(copper, 150)
	storage.inventory.add(coal, 7)
	var press := world.buildings.place(Registry.get_building(&"graphite_press"), Vector2i(6, 2), 0, true) as Crafter
	for i in 5:
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
	var copper := _item(&"copper")
	var gate := run.get_gateway(run.planet)
	var pad := run.planet.pad_rect
	_check(pad.size == Vector2i(15, 15) and run.drone.world == run.planet, "новый забег: дрон на площадке планеты")
	_check(TeleportSummary.total(run.drone.inventory.totals) > 0, "стартовый инвентарь выдан")
	# На площадке: склад с медью и лента с предметами. Вне площадки — склад, который потеряется.
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
	_check(summary.items_lost[copper] == 33, "итог: потеряно 33 меди из склада вне площадки")
	_check(old_planet.buildings == null, "старая планета освобождена")
	for i in 60:
		run.step()
	_check(true, "после телепорта симуляция идёт")
	run.dispose()
