class_name GameWorld
extends RefCounted
## Модель запущенного уровня: сетка, здания, параметры сессии.
## Не содержит нод — представления (render/, ui/) подписываются на её сигналы.

var level: LevelDef
var grid: WorldGrid
var buildings: BuildingManager
## Режим песочницы: бесплатное строительство, всё открыто, цели не засчитываются.
var sandbox: bool = false


## Создаёт мир из карты уровня: копирует слои и ставит предустановленные здания.
static func create(level_def: LevelDef, map: LevelMap, p_sandbox: bool) -> GameWorld:
	var world := GameWorld.new()
	world.level = level_def
	world.sandbox = p_sandbox
	world.grid = WorldGrid.from_level_map(map)
	world.buildings = BuildingManager.new(world, world.grid)
	for p in map.placements:
		if world.buildings.place(p.def, p.origin, p.rotation, true) == null:
			push_warning("GameWorld: не удалось поставить %s в %s" % [p.def.id, p.origin])
	return world


## Ядро уровня (первое найденное) или null.
func get_core() -> Building:
	return buildings.find_first(&"core")


## Разрывает циклические ссылки перед выгрузкой.
func dispose() -> void:
	if buildings != null:
		buildings.dispose()
	buildings = null
	grid = null
