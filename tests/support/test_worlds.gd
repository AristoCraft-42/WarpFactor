extends RefCounted
## Построение тестовых миров в коде для тестов и бенчмарков.

const SOURCE_SCRIPT := preload("res://tests/support/item_source.gd")
const SINK_SCRIPT := preload("res://tests/support/item_sink.gd")
const GENERATOR_SCRIPT := preload("res://tests/support/test_generator.gd")


static func empty_world(width: int, height: int, sandbox: bool = true) -> GameWorld:
	Registry.ensure_loaded()
	var map := LevelMap.new(width, height, Registry.get_floor(&"stone").index)
	return GameWorld.create(null, map, sandbox)


static func source_def() -> BuildingDef:
	var def := BuildingDef.new()
	def.id = &"test_source"
	def.size = 1
	def.rotatable = false
	def.logic_script = SOURCE_SCRIPT
	return def


static func sink_def() -> BuildingDef:
	var def := BuildingDef.new()
	def.id = &"test_sink"
	def.size = 1
	def.rotatable = false
	def.logic_script = SINK_SCRIPT
	return def


## Прямая линия лент длиной length от start в направлении dir.
## Линия лент; def_override — своё описание ленты (например, ускоренная для тестов пропускной способности).
static func conveyor_line(world: GameWorld, start: Vector2i, length: int, dir: int, def_id: StringName = &"conveyor",
		def_override: BuildingDef = null) -> void:
	var def := def_override if def_override != null else Registry.get_building(def_id)
	var step := GameConst.dir_vector(dir)
	for i in length:
		world.buildings.place(def, start + step * i, dir, true)


static func run_ticks(world: GameWorld, ticks: int) -> void:
	for i in ticks:
		world.simulation.step()


static func generator_def() -> BuildingDef:
	var def := BuildingDef.new()
	def.id = &"test_generator"
	def.size = 1
	def.rotatable = false
	def.logic_script = GENERATOR_SCRIPT
	return def


## Питание для квадрата со стороной side от top_left: опоры сеткой через 5 тайлов (со сдвигом 2 внутрь,
## зона опоры 5×5), связанные проводами, и бесконечный генератор на тайле generator_tile.
static func power_area(world: GameWorld, top_left: Vector2i, side: int, generator_tile: Vector2i) -> void:
	var pole_def := Registry.get_building(&"small_power_pole")
	var poles: Array[PowerPole] = []
	for y in range(top_left.y + 2, top_left.y + side + 2, 5):
		for x in range(top_left.x + 2, top_left.x + side + 2, 5):
			if world.buildings.get_at(Vector2i(x, y)) != null:
				continue
			var pole := world.buildings.place(pole_def, Vector2i(x, y), 0, true) as PowerPole
			if pole != null:
				poles.append(pole)
				world.power.auto_link(pole)
	if world.buildings.get_at(generator_tile) == null:
		world.buildings.place(generator_def(), generator_tile, 0, true)


## Артиллерийская турель из кода: в ранней игре её нет в данных, механика остаётся для тестов и бенчмарков.
static func artillery_def() -> TurretDef:
	var def := TurretDef.new()
	def.id = &"test_artillery"
	def.size = 2
	def.rotatable = false
	def.health = 520.0
	def.logic_script = preload("res://buildings/defense/turret.gd")
	def.shoot_range = 17.0
	def.min_range = 3.5
	def.reload_seconds = 1.8
	def.rotate_speed = 180.0
	def.shoot_cone = 8.0
	def.inaccuracy = 4.0
	def.max_ammo = 16
	def.artillery = true
	def.barrel_length = 22.0
	var ammo := TurretAmmo.new()
	ammo.item = Registry.get_item(&"cartridge_iron")
	ammo.shots_per_item = 1
	ammo.damage = 33.0
	ammo.splash_radius = 1.4
	ammo.speed = 6.0
	def.ammo = [ammo]
	return def
