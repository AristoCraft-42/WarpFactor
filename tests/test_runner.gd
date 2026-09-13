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
	_test_drill_to_core()
	_test_costs_and_demolish()
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
	_check(Registry.items.size() == 11, "ожидалось 11 предметов, есть %d" % Registry.items.size())
	_check(Registry.ores.size() == 6, "ожидалось 6 руд, есть %d" % Registry.ores.size())
	_check(Registry.floors.size() >= 4, "мало типов пола")
	_check(Registry.buildings.size() == 21, "ожидалось 21 здание, есть %d" % Registry.buildings.size())
	_check(Registry.levels.size() >= 2, "ожидалось не меньше 2 уровней")
	_check(Registry.validate().is_empty(), "ошибки валидации: %s" % ", ".join(Registry.validate()))
	for i in Registry.items.size():
		_check(Registry.items[i].index == i, "индекс предмета не совпадает")
	_check(Registry.get_building(&"core") != null and not Registry.get_building(&"core").removable, "ядро должно быть неудаляемым")
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
	map.add_placement(Registry.get_building(&"core"), Vector2i(18, 13))
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
		_check(world.get_core() != null, "на уровне %s есть ядро" % level.id)
		world.dispose()


# --- Размещение и снос ---

func _test_building_manager() -> void:
	var map := LevelMap.new(64, 64, Registry.get_floor(&"stone").index)
	for y in 64:
		map.set_floor(20, y, Registry.get_floor(&"rock").index)
	var copper := Registry.get_ore(&"copper").index + 1
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6), Vector2i(18, 5)]:
		map.set_ore(p.x, p.y, copper)
	map.add_placement(Registry.get_building(&"core"), Vector2i(40, 40))
	var world := GameWorld.create(null, map, false)
	var bm := world.buildings
	var conveyor := Registry.get_building(&"conveyor")
	var drill := Registry.get_building(&"mechanical_drill")
	var vault := Registry.get_building(&"vault")

	_check(bm.get_count() == 1, "ядро поставлено уровнем")
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

	var core := world.get_core()
	_check(not bm.remove(core), "ядро не сносится")
	var in_rect := bm.collect_in_rect(Rect2i(0, 0, 64, 64))
	_check(in_rect.size() == 3, "в рамке 3 здания (бур, лента, ядро), найдено %d" % in_rect.size())
	var partial := bm.collect_in_rect(Rect2i(6, 6, 1, 1))
	_check(partial.size() == 1 and partial[0] == d, "рамка ловит здание за любой его тайл")
	var edge := bm.collect_in_rect(Rect2i(42, 42, 1, 1))
	_check(edge.size() == 1 and edge[0] == core, "рамка в правом нижнем тайле ядра")

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
func _test_drill_to_core() -> void:
	var map := LevelMap.new(48, 20, Registry.get_floor(&"stone").index)
	var copper := Registry.get_ore(&"copper").index + 1
	for y in range(8, 10):
		for x in range(4, 6):
			map.set_ore(x, y, copper)
	map.add_placement(Registry.get_building(&"core"), Vector2i(30, 8))
	var world := GameWorld.create(null, map, true)
	var drill: Drill = world.buildings.place(Registry.get_building(&"mechanical_drill"), Vector2i(4, 8), 0, true)
	_check(drill.ore != null and drill.ore_tiles == 4, "бур нашёл 4 тайла меди")
	var expected_ticks := roundi((8.0 + 2.0 * 1) / 4 * GameConst.TICK_RATE)
	_check(drill.ticks_per_item == expected_ticks, "время на предмет %d тиков (ожидалось %d)" % [drill.ticks_per_item, expected_ticks])
	Worlds.conveyor_line(world, Vector2i(6, 9), 24, GameConst.Dir.RIGHT)
	var copper_index := Registry.get_item(&"copper").index
	Worlds.run_ticks(world, 60 * GameConst.TICK_RATE)
	var delivered: int = world.core_storage.delivered[copper_index]
	var in_transit := world.simulation.conveyors.get_item_count() + drill.buffer
	var produced := 60 * GameConst.TICK_RATE / drill.ticks_per_item
	_check(delivered > 0, "медь доставлена в ядро (%d)" % delivered)
	_check(absi(delivered + in_transit - produced) <= 1, "добыто %d ≈ доставлено %d + в пути %d" % [produced, delivered, in_transit])
	_check(world.core_storage.get_count(copper_index) == delivered, "медь лежит в ядре")
	_check(world.stats.income_per_second(copper_index) > 0.2, "статистика видит поступление")
	world.dispose()


func _test_costs_and_demolish() -> void:
	var world := Worlds.empty_world(32, 16, false)
	var conveyor := Registry.get_building(&"conveyor")
	var copper := Registry.get_item(&"copper").index
	_check(world.check_build(conveyor, Vector2i(5, 5), 0) == BuildingManager.Check.NOT_AFFORDABLE, "без меди лента недоступна")
	_check(world.build(conveyor, Vector2i(5, 5), 0) == null, "без меди лента не строится")
	world.core_storage.add_without_delivery(copper, 10)
	var budget := world.core_storage.make_budget()
	var affordable := 0
	for x in 20:
		if world.check_build(conveyor, Vector2i(x, 8), 0, budget) == BuildingManager.Check.OK:
			affordable += 1
	_check(affordable == 10, "бюджет протягивания хватает ровно на 10 лент (%d)" % affordable)
	var built := world.build(conveyor, Vector2i(5, 5), 0)
	_check(built != null and world.core_storage.get_count(copper) == 9, "стройка списала 1 медь")
	# Содержимое снесённой ленты уходит в ядро как доставка, стоимость возвращается.
	world.buildings.place(Worlds.source_def(), Vector2i(4, 5), 0, true)
	Worlds.run_ticks(world, 120)
	var on_belt := world.simulation.conveyors.counts[world.simulation.conveyors.index_of(built.id)]
	var delivered_before: int = world.core_storage.delivered[0]
	_check(world.demolish(built), "снос ленты")
	_check(world.core_storage.get_count(copper) == 10 + on_belt, "возврат стоимости и содержимое в ядре (%d)" % world.core_storage.get_count(copper))
	_check(world.core_storage.delivered[0] - delivered_before == on_belt, "содержимое засчитано как доставка, возврат — нет")
	# Лимит ядра: излишек сгорает, но засчитывается.
	world.core_storage.deliver(copper, world.core_storage.capacity + 50)
	_check(world.core_storage.get_count(copper) == world.core_storage.capacity, "запас не превышает лимит")
	_check(world.core_storage.burned[copper] >= 50, "излишек сгорел")
	# Песочница строит бесплатно.
	var sandbox := Worlds.empty_world(16, 16, true)
	_check(sandbox.build(conveyor, Vector2i(2, 2), 0) != null, "в песочнице стройка бесплатна")
	world.dispose()
	sandbox.dispose()


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
		var sorter := _place(world, &"inverted_sorter" if inverted else &"sorter", Vector2i(6, 10))
		world.configure(sorter, copper)
		Worlds.conveyor_line(world, Vector2i(7, 10), 2, GameConst.Dir.RIGHT)
		var forward := _sink(world, Vector2i(9, 10))
		Worlds.conveyor_line(world, Vector2i(6, 9), 2, GameConst.Dir.UP)
		var up := _sink(world, Vector2i(6, 7))
		Worlds.conveyor_line(world, Vector2i(6, 11), 2, GameConst.Dir.DOWN)
		var down := _sink(world, Vector2i(6, 13))
		Worlds.run_ticks(world, 900)
		var matched := lead if inverted else copper
		var other := copper if inverted else lead
		var name := "инвертированный сортировщик" if inverted else "сортировщик"
		_check(forward.received > 30 and forward.count_of(other) == 0, "%s: вперёд только выбранное (%d)" % [name, forward.received])
		_check(up.count_of(matched) == 0 and down.count_of(matched) == 0 and up.received > 5 and down.received > 5,
			"%s: в стороны остальное, поровну (%d / %d)" % [name, up.received, down.received])
		_check(sorter.get_display_item() == copper, "%s: иконка фильтра" % name)
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
	_place(world, &"underflow_gate", Vector2i(6, 10))
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
	map.add_placement(Registry.get_building(&"core"), Vector2i(10, 10))
	var world := GameWorld.create(null, map, true)
	var copper := Registry.get_item(&"copper").index
	var lead := Registry.get_item(&"lead").index
	world.core_storage.deliver(copper, 50)
	var unloader := _place(world, &"unloader", Vector2i(13, 11))
	Worlds.conveyor_line(world, Vector2i(14, 11), 3, GameConst.Dir.RIGHT)
	var sink := _sink(world, Vector2i(17, 11))
	world.configure(unloader, lead)
	Worlds.run_ticks(world, 200)
	_check(sink.received == 0, "разгрузчик со свинцовым фильтром не берёт медь")
	world.configure(unloader, copper)
	Worlds.run_ticks(world, 600)
	_check(sink.received > 20, "разгрузчик выгружает медь (%d)" % sink.received)
	var in_core := world.core_storage.get_count(copper)
	var on_belts := world.simulation.conveyors.get_item_count()
	_check(in_core + on_belts + sink.received == 50, "предметы из ядра не теряются")
	_check(world.core_storage.delivered[copper] == in_core, "доставка учитывается нетто (изъятое вычтено)")
	# Петля «ядро → разгрузчик → лента → ядро» не накручивает доставку.
	world.buildings.remove(sink, true)
	Worlds.conveyor_line(world, Vector2i(16, 11), 1, GameConst.Dir.UP)
	Worlds.conveyor_line(world, Vector2i(16, 10), 1, GameConst.Dir.LEFT)
	Worlds.conveyor_line(world, Vector2i(15, 10), 2, GameConst.Dir.LEFT)
	var delivered_before: int = world.core_storage.delivered[copper]
	Worlds.run_ticks(world, 900)
	var looped := world.simulation.conveyors.get_item_count()
	_check(world.core_storage.delivered[copper] + looped >= delivered_before - 1 and world.core_storage.delivered[copper] <= delivered_before,
		"петля через ядро не увеличивает доставку (%d → %d)" % [delivered_before, world.core_storage.delivered[copper]])
	world.dispose()


## Цепочка мгновенных зданий работает, а петля из сортировщиков не зацикливает передачу.
func _test_pass_through_chains() -> void:
	var world := Worlds.empty_world(32, 24)
	_source(world, Vector2i(2, 10), [0])
	Worlds.conveyor_line(world, Vector2i(3, 10), 2, GameConst.Dir.RIGHT)
	_place(world, &"overflow_gate", Vector2i(5, 10))
	_place(world, &"overflow_gate", Vector2i(6, 10))
	_place(world, &"inverted_sorter", Vector2i(7, 10))
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
	var map := LevelMap.new(24, 16, Registry.get_floor(&"stone").index)
	map.add_placement(Registry.get_building(&"core"), Vector2i(18, 6))
	var world := GameWorld.create(null, map, true)
	var lead := Registry.get_item(&"lead").index
	var sorter := world.build(Registry.get_building(&"sorter"), Vector2i(4, 4), 0, lead)
	_check(sorter != null and sorter.get_config() == lead, "настройка применяется при строительстве")
	var bridge := world.build(Registry.get_building(&"bridge_conveyor"), Vector2i(4, 8), 0, Vector2i(3, 0))
	_check(bridge.get_config() == Vector2i(3, 0), "настройка моста копируется как смещение")
	var router := world.build(Registry.get_building(&"router"), Vector2i(10, 10), 0)
	router.handle_item(null, lead)
	var delivered_before: int = world.core_storage.delivered[lead]
	_check(world.demolish(router), "снос делителя")
	_check(world.core_storage.delivered[lead] == delivered_before + 1, "предмет из делителя ушёл в ядро")
	world.dispose()
