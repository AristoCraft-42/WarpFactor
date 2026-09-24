class_name SaveIO
extends RefCounted
## Сохранения забега: user://saves/<слот>.fwsave.
##
## Файл: "FWSV", версия (u32), заголовок (u32 длина + var_to_bytes словаря: название, планета, время игры,
## дата, творческий режим), тело (u32 исходная длина, u32 сжатая длина, ZSTD от var_to_bytes словаря).
## Заголовок читается без распаковки тела — список сохранений строится быстро.
##
## Тело — словарь секций: tables (id предметов, полов, руд, врагов), run, link, drone, planet, base.
## У мира планеты — ещё враги, угроза, поле потоков и выпавший груз (версия 2).
## Здания пишутся с их id, состоянием и настройкой; внутренности симуляции — как есть, поэтому после
## загрузки игра продолжается с того же тика так же, как без неё. Предметы, полы и руды хранятся
## индексами вместе с таблицами id: при изменении контента индексы переносятся (SaveContext).

const MAGIC := "FWSV"
const VERSION := 5
const DIR := "user://saves/"
## Автопрогон пишет в отдельную папку, чтобы не трогать сохранения игрока.
const AUTOSHOT_DIR := "user://saves_autoshot/"
const EXT := ".fwsave"

## Перенос индексов пола и руды (старый → новый) на время загрузки.
static var _floor_map := PackedInt32Array()
static var _dir: String = ""
static var _ore_map := PackedInt32Array()
## Перенос индексов врагов и жидкостей (пусто — без переноса).
static var _enemy_map := PackedInt32Array()
static var _fluid_map := PackedInt32Array()


# --- Файлы ---

## Сохранить забег в слот. name — имя, которое видит игрок (из него же строится имя файла).
static func save_run(run: Run, name: String) -> Error:
	return save_run_as(run, name, name)


## Сохранить в файл file_id с отображаемым именем name (служебные слоты: автосохранение, быстрое).
static func save_run_as(run: Run, file_id: String, name: String) -> Error:
	DirAccess.make_dir_recursive_absolute(get_dir())
	var path := slot_path(file_id)
	var header := {
		"name": name,
		"title": run.get_world_title(run.planet),
		"in_base": run.drone.world == run.base,
		"saved_at": int(Time.get_unix_time_from_system()),
		"playtime": float(run.base.simulation.tick) / GameConst.TICK_RATE,
		"creative": run.creative,
		"version": VERSION,
	}
	var body := var_to_bytes(run_to_dict(run))
	var packed := body.compress(FileAccess.COMPRESSION_ZSTD)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(VERSION)
	var header_bytes := var_to_bytes(header)
	file.store_32(header_bytes.size())
	file.store_buffer(header_bytes)
	file.store_32(body.size())
	file.store_32(packed.size())
	file.store_buffer(packed)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Загрузить забег из файла (null — файл повреждён или чужой).
static func load_run(path: String) -> Run:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveIO: не удалось открыть %s" % path)
		return null
	if file.get_length() < 16 or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		push_error("SaveIO: %s — не сохранение" % path)
		return null
	var version := file.get_32()
	if version > VERSION:
		push_error("SaveIO: %s — сохранение новой версии (%d)" % [path, version])
		return null
	file.get_buffer(file.get_32())
	var raw_size := file.get_32()
	var packed := file.get_buffer(file.get_32())
	var body := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if body.size() != raw_size:
		push_error("SaveIO: %s повреждён" % path)
		return null
	var data: Variant = bytes_to_var(body)
	if not (data is Dictionary):
		push_error("SaveIO: %s повреждён" % path)
		return null
	var run := run_from_dict(data)
	# Из файла игра начинается с дронами на месте: клавиши при загрузке никто не держит,
	# а команда «стоп» не придёт — управление шлёт её только при смене направления.
	if run != null:
		for player in run.players:
			if player.drone != null:
				player.drone.move_input = Vector2.ZERO
	return run


## Заголовок сохранения (пустой словарь — не сохранение). В заголовок добавляется "path".
static func read_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 16 or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return {}
	file.get_32()
	var header: Variant = bytes_to_var(file.get_buffer(file.get_32()))
	if not (header is Dictionary):
		return {}
	header["path"] = path
	return header


## Все сохранения, новые первыми.
static func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := get_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(EXT):
			var header := read_header(dir.path_join(file_name))
			if not header.is_empty():
				result.append(header)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return result


static func latest_save_path() -> String:
	var saves := list_saves()
	return String(saves[0]["path"]) if not saves.is_empty() else ""


static func delete_save(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func slot_path(name: String) -> String:
	var safe := name.strip_edges().validate_filename()
	if safe.is_empty():
		safe = "save"
	return get_dir().path_join(safe + EXT)


## Папка сохранений: обычная или отдельная для автопрогона (--autoshot).
static func get_dir() -> String:
	if _dir.is_empty():
		_dir = AUTOSHOT_DIR if OS.get_cmdline_user_args().has("--autoshot") else DIR
	return _dir


# --- Забег ---

static func run_to_dict(run: Run) -> Dictionary:
	var item_ids := PackedStringArray()
	for item in Registry.items:
		item_ids.append(String(item.id))
	var floor_ids := PackedStringArray()
	for f in Registry.floors:
		floor_ids.append(String(f.id))
	var ore_ids := PackedStringArray()
	for o in Registry.ores:
		ore_ids.append(String(o.id))
	var enemy_ids := PackedStringArray()
	for e in Registry.enemies:
		enemy_ids.append(String(e.id))
	var fluid_ids := PackedStringArray()
	for f in Registry.fluids:
		fluid_ids.append(String(f.id))
	return {
		"version": VERSION,
		"tables": {"items": item_ids, "floors": floor_ids, "ores": ore_ids, "enemies": enemy_ids, "fluids": fluid_ids},
		"run": {
			"seed": run.run_seed, "creative": run.creative, "level": String(run.level_id),
			"star_map": run.star_map.save_data(),
			"charge_target": run.charge_target, "charge_left": run.charge_ticks_left, "charge_total": run.charge_ticks_total,
			"arrival_tick": run.planet_arrival_tick, "drone_in_base": run.drone.world == run.base,
			"local_player": run.local_player, "next_player": run.next_player_id,
		},
		"research": run.research.save_data(),
		"link": run.link.save_data(),
		"players": _players_to_array(run),
		"planet": world_to_dict(run.planet),
		"base": world_to_dict(run.base),
	}


static func run_from_dict(data: Dictionary) -> Run:
	var tables: Dictionary = data.get("tables", {})
	SaveContext.begin(tables.get("items", PackedStringArray()))
	_floor_map = _layer_map(tables.get("floors", PackedStringArray()), true)
	_ore_map = _layer_map(tables.get("ores", PackedStringArray()), false)
	_enemy_map = _enemy_table(tables.get("enemies", PackedStringArray()))
	_fluid_map = _fluid_table(tables.get("fluids", PackedStringArray()))
	var run_data: Dictionary = data.get("run", {})
	var run := Run.new()
	run.run_seed = int(run_data.get("seed", 0))
	run.creative = bool(run_data.get("creative", false))
	run.level_id = StringName(run_data.get("level", ""))
	run.run_def = Registry.run_def
	run.star_map = StarMap.new(run.run_seed, run.run_def, Registry.planet_types)
	run.star_map.load_data(run_data.get("star_map", {}))
	run.planet = world_from_dict(data.get("planet", {}), null)
	run.base = world_from_dict(data.get("base", {}), null)
	_players_from_array(run, data.get("players", []))
	run.next_player_id = maxi(int(run_data.get("next_player", 1)), run.next_player_id)
	var research := ResearchState.new()
	research.load_data(data.get("research", {}))
	run.setup_research(research)
	run.set_local_player(int(run_data.get("local_player", 1)))

	var link_data: Dictionary = data.get("link", {})
	run.link = GatewayLink.new()
	run.link.load_data(link_data)
	run.link.planet_gateway = _find_gateway(run.planet, int(link_data.get("planet_gateway", 0)))
	run.link.base_gateway = _find_gateway(run.base, int(link_data.get("base_gateway", 0)))
	if run.link.planet_gateway != null:
		run.link.planet_gateway.link = run.link
	if run.link.base_gateway != null:
		run.link.base_gateway.link = run.link

	run.charge_target = int(run_data.get("charge_target", -1))
	if run.charge_target >= 0 and not run.star_map.can_travel_to(run.charge_target):
		run.charge_target = -1
	run.charge_ticks_left = int(run_data.get("charge_left", 0))
	run.charge_ticks_total = int(run_data.get("charge_total", 0))
	run.planet_arrival_tick = int(run_data.get("arrival_tick", 0))
	run.attach_world(run.planet)
	run.attach_world(run.base)
	run.relink_lifts()
	run.apply_research_effects(false)
	# Пульты и якоря платформ находят друг друга после того, как оба мира загружены.
	run.relink_platforms()

	# Угроза планеты: расписание, поле потоков — как в сохранении (старые сохранения начинают угрозу заново).
	var planet_data: Dictionary = data.get("planet", {})
	run._setup_threat(run.planet, run.star_map.get_current(), run.planet_arrival_tick, false)
	# Творческий забег с волнами, включёнными вручную: _setup_threat в творческом режиме угрозу
	# не заводит, а в сохранении она есть. Без этого волны пропадали бы при загрузке — и, что хуже,
	# у клиента сетевой игры после снимка, из-за чего враги расходились и мир чинился снова и снова.
	if run.planet.threat == null and planet_data.has("threat"):
		run.set_creative_threat(true)
	if run.planet.threat != null and planet_data.has("threat"):
		run.planet.threat.load_data(planet_data["threat"], _enemy_map)
	if run.planet.flow == null and run.planet.enemies.count > 0:
		run.planet.ensure_flow(false)
	if run.planet.flow != null:
		if planet_data.has("flow"):
			run.planet.flow.load_data(planet_data["flow"])
		else:
			run.planet.flow.compute_now()
	SaveContext.end()
	return run


# --- Мир ---

static func world_to_dict(world: GameWorld) -> Dictionary:
	var entries: Array = []
	for b in world.buildings.get_all():
		var entry := {"id": b.id, "def": String(b.def.id), "origin": b.origin, "rotation": b.rotation,
			"config": b.get_config(), "state": b.save_state(), "dump": b.get_dump_cursor()}
		# Занимаемый размер пишем, если он отличается от данных или может измениться (шлюз растёт
		# по исследованиям, а они загружаются уже после построек).
		if b.size != b.def.size or b is GatewayBuilding:
			entry["size"] = b.size
		if b.is_damaged():
			entry["hp"] = b.health
		entries.append(entry)
	var crates: Array = []
	for crate in world.crates:
		crates.append(crate.save_data())
	var result := {
		"width": world.grid.width, "height": world.grid.height,
		"floors": world.grid.floors.duplicate(), "ores": world.grid.ores.duplicate(),
		"is_base": world.is_base, "creative": world.creative, "pad": world.pad_rect, "play": world.play_rect,
		"level": String(world.level.id) if world.level != null else "",
		"rng_seed": world.rng.seed, "rng_state": world.rng.state,
		"buildings": entries,
		"id_capacity": world.buildings.get_id_capacity(), "free_ids": world.buildings.get_free_ids(),
		"sim": world.simulation.save_runtime(),
		"spawn_points": world.spawn_points.duplicate(), "crates": crates,
		"destroyed": world.destroyed_count, "breached": world.breached,
		"enemies": world.enemies.save_data(),
		"projectiles": world.projectiles.save_data(),
		"fluids": world.fluids.save_data(),
	}
	if world.threat != null:
		result["threat"] = world.threat.save_data()
	if world.flow != null:
		result["flow"] = world.flow.save_data()
	return result


## Игроки забега: имя, на каком этаже и всё состояние дрона.
static func _players_to_array(run: Run) -> Array:
	var out := []
	for p in run.players:
		out.append(p.save_data(run.base))
	return out


static func _players_from_array(run: Run, entries: Array) -> void:
	for entry in entries:
		var data: Dictionary = entry
		var world := run.base if bool(data.get("in_base", false)) else run.planet
		var drone := Drone.new(Registry.drone_def, world, Vector2.ZERO)
		drone.load_data(data.get("drone", {}))
		run._register_player(String(data.get("name", "")), drone, int(data.get("id", 0)))
	if run.players.is_empty():
		# Сохранение без игроков (не должно случаться) — заводим одного, чтобы забег был играбелен.
		var fallback := Drone.new(Registry.drone_def, run.planet, Vector2.ZERO)
		run._register_player("", fallback)


static func world_from_dict(d: Dictionary, drone: Drone) -> GameWorld:
	var w := int(d.get("width", GameConst.MIN_LEVEL_SIZE))
	var h := int(d.get("height", GameConst.MIN_LEVEL_SIZE))
	var map := LevelMap.new(w, h, 0)
	map.floors = _remap_layer(d.get("floors", PackedByteArray()), _floor_map, w * h, 0)
	map.ores = _remap_layer(d.get("ores", PackedByteArray()), _ore_map, w * h, 1)
	var level := Registry.get_level(StringName(d.get("level", ""))) if String(d.get("level", "")) != "" else null
	var world := GameWorld.create(level, map, bool(d.get("creative", false)), drone, false)
	world.is_base = bool(d.get("is_base", false))
	world.pad_rect = d.get("pad", Rect2i())
	world.play_rect = d.get("play", Rect2i())
	world.rng.seed = int(d.get("rng_seed", 1))
	world.rng.state = int(d.get("rng_state", world.rng.state))
	var sim: Dictionary = d.get("sim", {})
	world.simulation.tick = int(sim.get("tick", 0))

	# Ленты — первыми и в сохранённом порядке: так совпадут их индексы в ConveyorSystem.
	var entries: Array = d.get("buildings", [])
	var by_id := {}
	for entry in entries:
		by_id[int((entry as Dictionary).get("id", 0))] = entry
	var placed := {}
	var conveyors: Dictionary = sim.get("conveyors", {})
	for bid in (conveyors.get("order", PackedInt32Array()) as PackedInt32Array):
		if by_id.has(bid):
			_place_entry(world, by_id[bid])
			placed[bid] = true
	for entry in entries:
		var id := int((entry as Dictionary).get("id", 0))
		if not placed.has(id):
			_place_entry(world, entry)
	world.buildings.restore_ids(int(d.get("id_capacity", 1)), d.get("free_ids", PackedInt32Array()))
	world.simulation.load_runtime(sim)
	for b in world.buildings.get_all():
		if b is GatewayBuilding and world.gateway == null:
			world.gateway = b
		if b.is_damaged():
			world.damaged[b.id] = true
	world.spawn_points.clear()
	for p in (d.get("spawn_points", []) as Array):
		world.spawn_points.append(p)
	for crate_data in (d.get("crates", []) as Array):
		var crate := DroneCrate.from_data(crate_data)
		if not crate.is_empty():
			world.crates.append(crate)
	world.destroyed_count = int(d.get("destroyed", 0))
	world.breached = bool(d.get("breached", false))
	world.enemies.load_data(d.get("enemies", {}), _enemy_map)
	world.projectiles.load_data(d.get("projectiles", {}))
	world.fluids.load_data(d.get("fluids", {}), _fluid_map)
	return world


static func _place_entry(world: GameWorld, entry: Dictionary) -> void:
	var def := Registry.get_building(StringName(entry.get("def", "")))
	if def == null:
		push_warning("SaveIO: здание «%s» больше не существует — пропущено" % entry.get("def", ""))
		return
	var b := world.buildings.place(def, entry.get("origin", Vector2i.ZERO), int(entry.get("rotation", 0)), true,
		int(entry.get("id", 0)), int(entry.get("size", 0)))
	if b == null:
		return
	var config: Variant = entry.get("config", null)
	if config != null and b.get_config_kind() == Building.ConfigKind.ITEM:
		config = _remap_item_config(config)
	if config != null:
		b.set_config(config)
	b.set_dump_cursor(int(entry.get("dump", 0)))
	b.load_state(entry.get("state", {}))
	if entry.has("hp"):
		b.health = clampf(float(entry["hp"]), 0.0, b.get_max_health())


static func _remap_item_config(config: Variant) -> Variant:
	if config is int:
		var mapped := SaveContext.item(config)
		return mapped if mapped >= 0 else null
	if config is Dictionary:
		var copy := (config as Dictionary).duplicate()
		copy["item"] = SaveContext.item(int(copy.get("item", -1)))
		return copy
	return config


static func _find_gateway(world: GameWorld, id: int) -> GatewayBuilding:
	var b := world.buildings.get_by_id(id)
	if b is GatewayBuilding:
		return b
	for other in world.buildings.get_all():
		if other is GatewayBuilding:
			return other
	return null


## Таблица переноса врагов: старый индекс → новый (-1 — тип исчез). Пусто — порядок не изменился.
static func _enemy_table(saved_ids: PackedStringArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	var identity := saved_ids.size() == Registry.enemies.size()
	for i in saved_ids.size():
		var e := Registry.get_enemy(StringName(saved_ids[i]))
		result.append(e.index if e != null else -1)
		if result[i] != i:
			identity = false
	return PackedInt32Array() if identity else result


static func _fluid_table(saved_ids: PackedStringArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	var identity := saved_ids.size() == Registry.fluids.size()
	for i in saved_ids.size():
		var f := Registry.get_fluid(StringName(saved_ids[i]))
		result.append(f.index if f != null else -1)
		if result[i] != i:
			identity = false
	return PackedInt32Array() if identity else result


## Таблица переноса слоя: старый индекс → новый. Для руды значения в слое — индекс + 1.
static func _layer_map(saved_ids: PackedStringArray, floors: bool) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(saved_ids.size())
	for i in saved_ids.size():
		var id := StringName(saved_ids[i])
		if floors:
			var f := Registry.get_floor(id)
			result[i] = f.index if f != null else 0
		else:
			var o := Registry.get_ore(id)
			result[i] = o.index if o != null else -1
	return result


static func _remap_layer(layer: PackedByteArray, table: PackedInt32Array, expected: int, offset: int) -> PackedByteArray:
	var result := layer.duplicate()
	result.resize(expected)
	if table.is_empty():
		return result
	var identity := true
	for i in table.size():
		if table[i] != i:
			identity = false
			break
	if identity:
		return result
	for i in result.size():
		var v := result[i]
		if offset == 1:
			# Руда: 0 — нет руды, иначе индекс + 1.
			if v == 0:
				continue
			var mapped := table[v - 1] if v - 1 < table.size() else -1
			result[i] = mapped + 1 if mapped >= 0 else 0
		else:
			result[i] = table[v] if v < table.size() else 0
	return result
