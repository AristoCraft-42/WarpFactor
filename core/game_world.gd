class_name GameWorld
extends RefCounted
## Модель запущенного уровня: сетка, здания, симуляция, дрон игрока.
## Не содержит нод — представления (render/, ui/) подписываются на её сигналы.
## Все действия игрока проходят через этот класс: здесь проверяются радиус дрона и наличие
## постройки в инвентаре, снос возвращает постройку и содержимое, игрок перекладывает предметы.
## Творческий режим: постройки не расходуются и не возвращаются, радиус не ограничен.
## В забеге миров два (планета и база) с общим дроном: действовать можно только в мире, где дрон.

## Почему не удалось последнее действие игрока (для уведомлений).
enum ActionError { NONE, OUT_OF_RANGE, INVENTORY_FULL, NOT_ALLOWED }

var level: LevelDef
var grid: WorldGrid
var buildings: BuildingManager
var simulation: Simulation
var drone: Drone
## Генератор случайных чисел мира (сепаратор): детерминирован от id уровня.
var rng := RandomNumberGenerator.new()
var creative: bool = false
## Мир мобильной базы (иначе — планета).
var is_base: bool = false
## Площадка центрального шлюза на планете (size 0 — нет): переезжает вместе с базой.
var pad_rect: Rect2i = Rect2i()
var last_error: ActionError = ActionError.NONE
## Сколько предметов из содержимого не поместилось в инвентарь при последнем сносе (они теряются).
var last_lost_items: int = 0


## Создаёт мир из карты уровня: копирует слои, ставит предустановленные здания, создаёт дрона
## со стартовым инвентарём. shared_drone — дрон уже созданного мира забега (тогда свой не создаётся).
static func create(level_def: LevelDef, map: LevelMap, p_creative: bool, shared_drone: Drone = null) -> GameWorld:
	var world := GameWorld.new()
	world.level = level_def
	world.creative = p_creative
	world.grid = WorldGrid.from_level_map(map)
	world.rng.seed = hash(String(level_def.id)) if level_def != null else 1
	world.buildings = BuildingManager.new(world, world.grid)
	world.simulation = Simulation.new(world, world.buildings)
	for p in map.placements:
		if world.buildings.place(p.def, p.origin, p.rotation, true) == null:
			push_warning("GameWorld: не удалось поставить %s в %s" % [p.def.id, p.origin])
	if shared_drone != null:
		world.drone = shared_drone
		return world
	var spawn_tile := Vector2i(map.width / 2, map.height / 2)
	if level_def != null and world.grid.in_bounds_v(level_def.spawn):
		spawn_tile = level_def.spawn
	var spawn := Vector2(spawn_tile * GameConst.TILE_SIZE) + Vector2.ONE * GameConst.TILE_SIZE * 0.5
	world.drone = Drone.new(Registry.drone_def, world, spawn)
	if level_def != null:
		for stack in level_def.starting_items:
			if stack != null and stack.item != null:
				world.drone.inventory.add(stack.item.index, stack.amount)
	return world


## Мир базы: пустое пространство размера base_def.size с общим дроном забега.
static func create_base(base_def: BaseDef, p_creative: bool, shared_drone: Drone) -> GameWorld:
	var floor_def := Registry.get_floor(base_def.floor_id)
	var map := LevelMap.new(base_def.size, base_def.size, floor_def.index if floor_def != null else 0)
	var world := GameWorld.create(null, map, p_creative, shared_drone)
	world.is_base = true
	world.rng.seed = hash(String(base_def.id))
	return world


## Ставит шлюз (или его пару), убирая всё, что стоит на его месте.
func place_gateway(def: GatewayDef, origin: Vector2i) -> GatewayBuilding:
	if def == null:
		return null
	for old in buildings.collect_in_rect(Rect2i(origin, Vector2i(def.size, def.size))):
		buildings.remove(old, true)
	return buildings.place(def, origin, 0, true) as GatewayBuilding


## Дрон сейчас в этом мире (действовать можно только здесь).
func has_drone() -> bool:
	return drone != null and drone.world == self


## Может ли игрок взаимодействовать со зданием (настройка, окно, поворот): в радиусе дрона.
func can_interact(building: Building) -> bool:
	if building == null or building.world != self or not has_drone():
		return false
	return creative or drone.can_reach_tiles(building.get_rect())


## Проверка строительства игроком: размещение, радиус дрона, постройка в инвентаре.
## budget — для планирования ряда построек: при успехе постройка резервируется в нём,
## иначе проверяется текущий инвентарь.
func check_build(def: BuildingDef, origin: Vector2i, rotation: int, budget: Inventory.Budget = null) -> BuildingManager.Check:
	var check := buildings.check_place(def, origin, rotation)
	if check != BuildingManager.Check.OK and check != BuildingManager.Check.REPLACE:
		return check
	if not has_drone():
		return BuildingManager.Check.OUT_OF_RANGE
	if creative:
		return check
	if not drone.can_reach_tiles(Rect2i(origin, Vector2i(def.size, def.size))):
		return BuildingManager.Check.OUT_OF_RANGE
	if def.item == null:
		return BuildingManager.Check.NO_ITEM
	var local := budget if budget != null else drone.inventory.make_budget()
	if check == BuildingManager.Check.REPLACE:
		var existing := buildings.get_at(origin)
		if existing != null and existing.def.item != null:
			local.give(existing.def.item.index, 1)
	if not local.take(def.item.index, 1):
		return BuildingManager.Check.NO_ITEM
	return check


## Строит здание игроком: берёт постройку из инвентаря (при замене старое здание сносится
## с возвратом). config — настройка, скопированная пипеткой (фильтр, связь моста).
func build(def: BuildingDef, origin: Vector2i, rotation: int, config: Variant = null) -> Building:
	var check := check_build(def, origin, rotation)
	if check != BuildingManager.Check.OK and check != BuildingManager.Check.REPLACE:
		return null
	# Сначала снос заменяемого (он возвращает свою постройку), затем списание новой.
	if check == BuildingManager.Check.REPLACE:
		for old in buildings.collect_in_rect(Rect2i(origin, Vector2i(def.size, def.size))):
			if not demolish(old):
				return null
	if not creative and drone.inventory.remove(def.item.index, 1) == 0:
		return null
	var building := buildings.place(def, origin, rotation)
	if building == null and not creative:
		drone.inventory.add(def.item.index, 1)
	if building != null and config != null:
		configure(building, config)
	return building


## Меняет настройку здания. Для мостов убирает встречную связь (A→B при B→A).
func configure(building: Building, value: Variant) -> void:
	if building == null or building.world != self or building.get_config_kind() == Building.ConfigKind.NONE:
		return
	if building is BridgeConveyor and value is Vector2i and value != Vector2i.ZERO:
		var target := buildings.get_at(building.origin + value)
		if target is BridgeConveyor and (target as BridgeConveyor).link == -(value as Vector2i):
			target.set_config(null)
			buildings.notify_changed(target)
			simulation.on_building_reconfigured(target)
	building.set_config(value)
	buildings.notify_changed(building)
	# Ленты, уснувшие перед зданием с прежней настройкой, должны проверить новый маршрут.
	simulation.on_building_reconfigured(building)


## Сносит здание игроком: постройка и содержимое уходят в инвентарь дрона.
## Нужны радиус и место под саму постройку; не поместившееся содержимое теряется (last_lost_items).
func demolish(building: Building) -> bool:
	last_error = ActionError.NONE
	last_lost_items = 0
	if building == null or building.world != self:
		return false
	if not building.def.removable:
		last_error = ActionError.NOT_ALLOWED
		return false
	var item := building.def.item
	if not has_drone():
		last_error = ActionError.OUT_OF_RANGE
		return false
	if not creative:
		if not drone.can_reach_tiles(building.get_rect()):
			last_error = ActionError.OUT_OF_RANGE
			return false
		if item != null and drone.inventory.space_for(item.index) < 1:
			last_error = ActionError.INVENTORY_FULL
			return false
	var contents := PackedInt32Array()
	contents.resize(Registry.items.size())
	contents.fill(0)
	building.collect_contents(contents)
	if not buildings.remove(building):
		return false
	if not creative and item != null:
		drone.inventory.add(item.index, 1)
	for i in contents.size():
		if contents[i] > 0:
			last_lost_items += contents[i] - drone.inventory.add(i, contents[i])
	return true


## Поворачивает стоящее здание на delta шагов по часовой стрелке.
func rotate_building(building: Building, delta: int = 1) -> bool:
	if not can_interact(building):
		return false
	return buildings.rotate(building, building.rotation + delta)


## Забрать предметы из здания в инвентарь дрона. Возвращает, сколько забрано.
func player_take(building: Building, item: int, amount: int) -> int:
	last_error = ActionError.NONE
	if not can_interact(building) or item < 0 or amount <= 0:
		return 0
	var room := drone.inventory.space_for(item)
	if room <= 0:
		last_error = ActionError.INVENTORY_FULL
		return 0
	var taken := building.take_player_items(item, mini(amount, room))
	if taken > 0:
		drone.inventory.add(item, taken)
	return taken


## Положить предметы из инвентаря дрона в здание (сколько оно примет). Возвращает количество.
func player_put(building: Building, item: int, amount: int) -> int:
	if not can_interact(building) or not building.accepts_player_items() or item < 0:
		return 0
	var limit := mini(amount, drone.inventory.count(item))
	var put := 0
	while put < limit and building.accept_item(null, item):
		building.handle_item(null, item)
		put += 1
	if put > 0:
		drone.inventory.remove(item, put)
	return put


## Разрывает циклические ссылки перед выгрузкой.
func dispose() -> void:
	if buildings != null:
		buildings.dispose()
	buildings = null
	if simulation != null:
		simulation.dispose()
	simulation = null
	if drone != null and drone.world == self:
		drone.world = null
	drone = null
	grid = null
