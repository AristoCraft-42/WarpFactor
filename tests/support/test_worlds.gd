extends RefCounted
## Построение тестовых миров в коде для тестов и бенчмарков.

const SOURCE_SCRIPT := preload("res://tests/support/item_source.gd")
const SINK_SCRIPT := preload("res://tests/support/item_sink.gd")


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
static func conveyor_line(world: GameWorld, start: Vector2i, length: int, dir: int, def_id: StringName = &"conveyor") -> void:
	var def := Registry.get_building(def_id)
	var step := GameConst.dir_vector(dir)
	for i in length:
		world.buildings.place(def, start + step * i, dir, true)


static func run_ticks(world: GameWorld, ticks: int) -> void:
	for i in ticks:
		world.simulation.step()
