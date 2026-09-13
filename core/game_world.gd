class_name GameWorld
extends RefCounted
## Модель запущенного уровня: сетка, здания, симуляция, склад ядра, статистика.
## Не содержит нод — представления (render/, ui/) подписываются на её сигналы.
## Все действия игрока (строительство, снос, поворот) проходят через этот класс:
## здесь учитываются стоимость, возврат и перенос содержимого снесённых зданий в ядро.

const DEFAULT_CORE_CAPACITY := 4000

var level: LevelDef
var grid: WorldGrid
var buildings: BuildingManager
var simulation: Simulation
var core_storage: CoreStorage
var stats: ItemStats
## Режим песочницы: бесплатное строительство, всё открыто, цели не засчитываются.
var sandbox: bool = false


## Создаёт мир из карты уровня: копирует слои, ставит предустановленные здания, кладёт стартовые запасы.
static func create(level_def: LevelDef, map: LevelMap, p_sandbox: bool) -> GameWorld:
	var world := GameWorld.new()
	world.level = level_def
	world.sandbox = p_sandbox
	world.grid = WorldGrid.from_level_map(map)
	world.stats = ItemStats.new(Registry.items.size())
	var core_def := Registry.get_building(&"core") as StorageDef
	var capacity := core_def.item_capacity if core_def != null else DEFAULT_CORE_CAPACITY
	world.core_storage = CoreStorage.new(Registry.items.size(), capacity, world.stats)
	world.buildings = BuildingManager.new(world, world.grid)
	world.simulation = Simulation.new(world, world.buildings)
	for p in map.placements:
		if world.buildings.place(p.def, p.origin, p.rotation, true) == null:
			push_warning("GameWorld: не удалось поставить %s в %s" % [p.def.id, p.origin])
	if level_def != null:
		for stack in level_def.starting_items:
			if stack != null and stack.item != null:
				world.core_storage.add_without_delivery(stack.item.index, stack.amount)
	return world


## Ядро уровня (первое найденное) или null.
func get_core() -> Building:
	return buildings.find_first(&"core")


## Проверка строительства с учётом стоимости. budget — для планирования ряда построек:
## при успехе стоимость резервируется в нём, иначе проверяются текущие запасы ядра.
func check_build(def: BuildingDef, origin: Vector2i, rotation: int, budget: CoreStorage.Budget = null) -> BuildingManager.Check:
	var check := buildings.check_place(def, origin, rotation)
	if check != BuildingManager.Check.OK and check != BuildingManager.Check.REPLACE:
		return check
	if sandbox:
		return check
	var local := budget if budget != null else core_storage.make_budget()
	if check == BuildingManager.Check.REPLACE:
		var existing := buildings.get_at(origin)
		if existing != null:
			local.add(existing.def.cost)
	if not local.reserve(def.cost):
		return BuildingManager.Check.NOT_AFFORDABLE
	return check


## Строит здание игроком: списывает стоимость (при замене — сначала сносит старое с возвратом).
func build(def: BuildingDef, origin: Vector2i, rotation: int) -> Building:
	var check := check_build(def, origin, rotation)
	if check != BuildingManager.Check.OK and check != BuildingManager.Check.REPLACE:
		return null
	if check == BuildingManager.Check.REPLACE:
		for old in buildings.collect_in_rect(Rect2i(origin, Vector2i(def.size, def.size))):
			demolish(old)
	if not sandbox and not core_storage.spend(def.cost):
		return null
	var building := buildings.place(def, origin, rotation)
	if building == null and not sandbox:
		core_storage.refund(def.cost)
	return building


## Сносит здание игроком: возврат стоимости, содержимое — в ядро (засчитывается как доставка).
func demolish(building: Building) -> bool:
	if building == null or building.world != self or not building.def.removable:
		return false
	var contents := PackedInt32Array()
	contents.resize(Registry.items.size())
	contents.fill(0)
	building.collect_contents(contents)
	if not buildings.remove(building):
		return false
	if not sandbox:
		core_storage.refund(building.def.cost)
	for item in contents.size():
		if contents[item] > 0:
			core_storage.deliver(item, contents[item])
	return true


## Поворачивает стоящее здание на delta шагов по часовой стрелке.
func rotate_building(building: Building, delta: int = 1) -> bool:
	if building == null or building.world != self:
		return false
	return buildings.rotate(building, building.rotation + delta)


## Разрывает циклические ссылки перед выгрузкой.
func dispose() -> void:
	if buildings != null:
		buildings.dispose()
	buildings = null
	if simulation != null:
		simulation.dispose()
	simulation = null
	grid = null
