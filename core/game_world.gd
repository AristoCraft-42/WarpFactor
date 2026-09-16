class_name GameWorld
extends RefCounted
## Модель запущенного уровня: сетка, здания, симуляция, дрон игрока.
## Не содержит нод — представления (render/, ui/) подписываются на её сигналы.
## Все действия игрока проходят через этот класс: здесь проверяются радиус дрона и наличие
## постройки в инвентаре, снос возвращает постройку и содержимое, игрок перекладывает предметы.
## Творческий режим: постройки не расходуются и не возвращаются, радиус не ограничен.
## В забеге миров два (планета и база) с общим дроном: действовать можно только в мире, где дрон.
##
## Бой: здания получают урон и разрушаются без возврата вместе с содержимым. Центральный шлюз планеты
## не разрушается — при нуле прочности мир помечается «прорван» (breached), и забег уводит базу
## аварийным телепортом. Сбитый дрон роняет груз (DroneCrate) и появляется у шлюза через паузу.
## Угроза (волны), враги и поле потоков есть только у опасной планеты (setup_threat).

## Постройку разрушили враги (содержимое потеряно).
signal building_destroyed(def: BuildingDef, rect: Rect2i)
## Дрона сбили; груз — в crates.
signal drone_destroyed
signal drone_respawned
## Дрон подобрал moved предметов из выпавшего груза.
signal crate_picked(moved: int)

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

## Центральный шлюз (или его пара в базе) этого мира.
var gateway: GatewayBuilding
var enemies: EnemySystem
var projectiles: ProjectileSystem
var power: PowerGraph
var fluids: FluidGraph
## Исследования забега (общие для всех миров; null — мир вне забега).
var research: ResearchState
## Турели мира по id (для отрисовки стволов и радиусов).
var turrets: Dictionary[int, Turret] = {}
## Последняя атака врагов на постройку: тик и точка (для тревоги в интерфейсе).
var last_attack_tick: int = -1000000
var last_attack_position: Vector2 = Vector2.ZERO
var last_attack_gateway: bool = false
## Поле потоков к шлюзу (null — врагов в мире не бывает).
var flow: FlowField
## Угроза планеты (null — база или безопасная планета).
var threat: ThreatDirector
## Точки появления врагов у краёв карты.
var spawn_points: Array[Vector2i] = []
## Выпавший из сбитого дрона груз.
var crates: Array[DroneCrate] = []
## id повреждённых зданий (для полосок прочности).
var damaged: Dictionary[int, bool] = {}
## Сколько построек разрушили враги.
var destroyed_count: int = 0
## Шлюз планеты разрушен — нужна аварийная телепортация.
var breached: bool = false


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
	world.enemies = EnemySystem.new(world)
	world.projectiles = ProjectileSystem.new(world)
	world.power = PowerGraph.new(world)
	world.fluids = FluidGraph.new(world)
	world.spawn_points = map.spawn_points.duplicate()
	world.buildings.building_removed.connect(world._on_building_removed)
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
func place_gateway(def: GatewayDef, origin: Vector2i, rotation: int = 0) -> GatewayBuilding:
	if def == null:
		return null
	for old in buildings.collect_in_rect(Rect2i(origin, Vector2i(def.size, def.size))):
		buildings.remove(old, true)
	gateway = buildings.place(def, origin, rotation, true) as GatewayBuilding
	return gateway


## Угроза опасной планеты: поле потоков к шлюзу, точки появления, расписание волн.
## compute — сразу посчитать поле (при загрузке оно восстанавливается из сохранения).
func setup_threat(def: ThreatDef, start_tick: int, seed_value: int, compute: bool = true) -> void:
	if def == null:
		return
	ensure_flow(compute)
	if spawn_points.is_empty() and gateway != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "spawns"])
		var center := gateway.origin + Vector2i.ONE * (gateway.def.size / 2)
		spawn_points = SpawnPoints.find(grid.width, grid.height, grid.floors, center, def.spawn_point_count, rng)
	threat = ThreatDirector.new(self, def, start_tick, hash([seed_value, "threat"]))


## Поле потоков создаётся при первой необходимости (угроза или появление врага).
func ensure_flow(compute: bool = true) -> FlowField:
	if flow == null:
		flow = FlowField.new(self)
		if compute:
			flow.compute_now()
	return flow


func spawn_enemy(def: EnemyDef, position: Vector2) -> int:
	ensure_flow()
	return enemies.spawn(def, position, simulation.tick)


# --- Урон ---

func damage_building(building: Building, amount: float) -> void:
	if building == null or building.world != self or amount <= 0.0:
		return
	building.health -= amount
	last_attack_tick = simulation.tick
	last_attack_position = building.get_world_center()
	last_attack_gateway = building == gateway
	if building.health > 0.0:
		damaged[building.id] = true
		return
	if building == gateway and not is_base:
		# Шлюз не исчезает: база уходит аварийным телепортом (Run.step).
		building.health = 0.0
		damaged[building.id] = true
		breached = true
		return
	destroy_building(building)


## Починка (дрон): прочность не выше полной; полностью целое здание уходит из списка повреждённых.
func repair_building(building: Building, amount: float) -> void:
	if building == null or building.world != self or amount <= 0.0:
		return
	if not building.is_damaged():
		damaged.erase(building.id)
		return
	building.health = minf(building.health + amount, building.get_max_health())
	if not building.is_damaged():
		damaged.erase(building.id)


## Разрушение врагами: без возврата постройки, содержимое теряется.
func destroy_building(building: Building) -> void:
	if building == null or building.world != self:
		return
	var def := building.def
	var rect := building.get_rect()
	if buildings.remove(building, true):
		destroyed_count += 1
		building_destroyed.emit(def, rect)


## Урон дрону (творческий режим — неуязвим).
func damage_drone(amount: float, tick: int) -> void:
	if creative or drone == null or drone.world != self or not drone.is_targetable(tick):
		return
	drone.health -= amount
	if drone.health <= 0.0:
		kill_drone(tick)


## Дрон сбит: инвентарь и отменённая очередь крафта падают грузом, через паузу — появление у шлюза.
func kill_drone(tick: int) -> void:
	if drone == null or drone.dead:
		return
	var counts := PackedInt32Array()
	counts.resize(Registry.items.size())
	counts.fill(0)
	drone.crafting.drain_into(counts)
	drone.inventory.collect_into(counts)
	drone.inventory.clear()
	var crate := DroneCrate.from_counts(drone.position, counts)
	if not crate.is_empty():
		crates.append(crate)
	drone.stop_mining()
	drone.move_input = Vector2.ZERO
	drone.health = 0.0
	drone.dead = true
	drone.respawn_tick = tick + drone.def.get_respawn_ticks()
	drone_destroyed.emit()


func respawn_drone(tick: int) -> void:
	if drone == null or not drone.dead:
		return
	drone.dead = false
	drone.health = drone.def.health
	drone.invulnerable_until = tick + drone.def.get_invulnerable_ticks()
	if gateway != null and gateway.world == self:
		drone.position = gateway.get_world_center()
	drone.prev_position = drone.position
	drone_respawned.emit()


## Дрон подбирает груз в радиусе: сколько поместится; пустой груз исчезает.
func pickup_crates() -> int:
	if crates.is_empty() or drone == null or drone.dead:
		return 0
	var radius := drone.def.pickup_radius * GameConst.TILE_SIZE
	var moved := 0
	for i in range(crates.size() - 1, -1, -1):
		var crate := crates[i]
		if crate.position.distance_to(drone.position) > radius:
			continue
		moved += crate.transfer_to(drone.inventory)
		if crate.is_empty():
			crates.remove_at(i)
	if moved > 0:
		crate_picked.emit(moved)
	return moved


## Дрон сейчас в этом мире и не сбит (действовать можно только здесь).
func has_drone() -> bool:
	return drone != null and drone.world == self and not drone.dead


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
	if building is PowerPole:
		power.auto_link(building)
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


func _on_building_removed(building: Building) -> void:
	damaged.erase(building.id)
	if building == gateway:
		gateway = null


## Разрывает циклические ссылки перед выгрузкой.
func dispose() -> void:
	if threat != null:
		threat.dispose()
	threat = null
	if flow != null:
		flow.dispose()
	flow = null
	if enemies != null:
		enemies.dispose()
	enemies = null
	if projectiles != null:
		projectiles.dispose()
	projectiles = null
	if power != null:
		power.dispose()
	power = null
	if fluids != null:
		fluids.dispose()
	fluids = null
	research = null
	turrets.clear()
	crates.clear()
	gateway = null
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
