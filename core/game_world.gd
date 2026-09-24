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
## Пол или руда изменились в прямоугольнике тайлов (расширение площадки или этажа) — перерисовать террейн.
signal terrain_changed(rect: Rect2i)
## Площадка или открытая часть мира изменили размер.
signal bounds_changed

## Почему не удалось последнее действие игрока (для уведомлений).
enum ActionError { NONE, OUT_OF_RANGE, INVENTORY_FULL, NOT_ALLOWED }

var level: LevelDef
var grid: WorldGrid
var buildings: BuildingManager
var simulation: Simulation
## Дроны, которые сейчас в этом мире (у каждого игрока свой), по возрастанию id игрока.
var drones: Array[Drone] = []
## Дрон локального игрока — его ставит забег; интерфейс смотрит на мир его глазами.
var view_drone: Drone
## Забег, которому принадлежит мир (пусто — отдельный мир уровня или теста).
var run: Run
## Дрон, от лица которого выполняется действие игрока: забег ставит его на время команды.
## Пусто — действует дрон по умолчанию (в одиночной игре и в тестах он единственный).
var actor: Drone

## Дрон «по умолчанию» для интерфейса и старого кода: локальный, если он здесь, иначе первый.
var drone: Drone:
	get:
		if view_drone != null and view_drone.world == self:
			return view_drone
		return drones[0] if not drones.is_empty() else null
## Генератор случайных чисел мира (сепаратор): детерминирован от id уровня.
var rng := RandomNumberGenerator.new()
var creative: bool = false
## Мир мобильной базы (иначе — планета).
var is_base: bool = false
## Описание этажа, если это этаж базы: по нему открываются части, кладётся пол и считаются комнаты.
var floor_plan: BaseDef
## Площадка центрального шлюза на планете (size 0 — нет): переезжает вместе с базой.
var pad_rect: Rect2i = Rect2i()
## Открытая часть мира, тайлов: дрон и камера не выходят за неё (size 0 — вся карта).
var play_rect: Rect2i = Rect2i()
## Из чего она складывается на подземном этаже: центральная часть, комнаты добычи и туннели.
## Не сохраняется — восстанавливается из исследований вместе с размерами (apply_research_effects).
var open_rects: Array[Rect2i] = []
## Проверка места лифта (задаёт забег): func(world, def, origin) -> BuildingManager.Check.
var lift_check: Callable
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
## spawn_drone = false — мир создаётся без дронов (их добавит забег: при загрузке или для нового игрока).
static func create(level_def: LevelDef, map: LevelMap, p_creative: bool, shared_drone: Drone = null,
		spawn_drone: bool = true) -> GameWorld:
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
		world.add_drone(shared_drone)
		shared_drone.world = world
		return world
	if not spawn_drone:
		return world
	var spawn_tile := Vector2i(map.width / 2, map.height / 2)
	if level_def != null and world.grid.in_bounds_v(level_def.spawn):
		spawn_tile = level_def.spawn
	var spawn := Vector2(spawn_tile * GameConst.TILE_SIZE) + Vector2.ONE * GameConst.TILE_SIZE * 0.5
	var first := Drone.new(Registry.drone_def, world, spawn)
	world.add_drone(first)
	if level_def != null:
		for stack in level_def.starting_items:
			if stack != null and stack.item != null:
				first.inventory.add(stack.item.index, stack.amount)
	return world


## Подземный этаж базы: карта наибольшего размера, заполненная пустотой; открытая часть — start_size
## в центре (пока этаж не открыт исследованием, дрон туда не попадает).
## Этаж базы по описанию: подземный этаж или этаж добычи. Карта сразу наибольшего размера,
## открыта только центральная часть — остальное открывают исследования.
static func create_base(base_def: BaseDef, p_creative: bool) -> GameWorld:
	var void_def := Registry.get_floor(base_def.void_floor_id)
	var map := LevelMap.new(base_def.size, base_def.size, void_def.index if void_def != null else 0)
	var world := GameWorld.create(null, map, p_creative, null, false)
	world.is_base = true
	world.floor_plan = base_def
	world.rng.seed = hash(String(base_def.id))
	world.open_area(base_rect(base_def, base_def.start_size), false)
	return world


## Прямоугольник открытой части этажа стороной side в центре карты.
static func base_rect(base_def: BaseDef, side: int) -> Rect2i:
	var s := clampi(side, 1, base_def.size)
	var corner := (base_def.size - s) / 2
	return Rect2i(corner, corner, s, s)


## Открыть центральную часть подземного этажа: пустота внутри rect становится полом.
## Комнаты добычи открываются отдельно (open_room) и из этой рамки выпадают, поэтому
## play_rect — общая рамка всего открытого, а не один прямоугольник.
func open_area(rect: Rect2i, notify: bool = true) -> void:
	if open_rects.is_empty():
		open_rects.append(rect)
	else:
		open_rects[0] = rect
	_open_tiles(rect)
	_refresh_play_rect(rect, notify)


## Открыть комнату добычи с туннелем до центра. Комната добавляется к открытому, а не заменяет его.
func open_room(rect: Rect2i, tunnel: Rect2i, notify: bool = true) -> void:
	# В старых сохранениях карта этажа меньше — комнаты туда просто не помещаются.
	if open_rects.has(rect) or not grid.rect_in_bounds(rect) or not grid.rect_in_bounds(tunnel):
		return
	open_rects.append(rect)
	open_rects.append(tunnel)
	_open_tiles(rect)
	_open_tiles(tunnel)
	if notify:
		terrain_changed.emit(tunnel)
	_refresh_play_rect(rect, notify)


func _open_tiles(rect: Rect2i) -> void:
	var plan := floor_plan if floor_plan != null else Registry.base_def
	var open_def := Registry.get_floor(plan.floor_id)
	var void_def := Registry.get_floor(plan.void_floor_id)
	if open_def == null or void_def == null:
		return
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if grid.in_bounds(x, y) and grid.get_floor(x, y) == void_def.index:
				grid.floors[grid.index_of(x, y)] = open_def.index


## Общая рамка всего открытого: за неё не выходят ни камера, ни дрон.
func _refresh_play_rect(changed: Rect2i, notify: bool) -> void:
	var bounds := open_rects[0]
	for r in open_rects:
		bounds = bounds.merge(r)
	if play_rect == bounds:
		if notify:
			terrain_changed.emit(changed)
		return
	play_rect = bounds
	if notify:
		terrain_changed.emit(changed)
		bounds_changed.emit()


## Место платформы в комнате: пока платформа на планете, там пустота (строить нельзя),
## когда вернулась — обычный пол этажа.
func set_platform_open(rect: Rect2i, open: bool) -> void:
	var plan := floor_plan if floor_plan != null else Registry.base_def
	var def := Registry.get_floor(plan.floor_id if open else plan.void_floor_id)
	if def == null:
		return
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			# Под постройкой, которая осталась в комнате (торчала за край платформы), пол не убираем.
			if grid.in_bounds(x, y) and (open or buildings.get_at(Vector2i(x, y)) == null):
				grid.floors[grid.index_of(x, y)] = def.index
	terrain_changed.emit(rect)


## Новая площадка шлюза: свободные пригодные тайлы добавленной части становятся платформой без руды
## (где стоят постройки — пол и руда остаются как были).
func resize_pad(rect: Rect2i) -> void:
	if rect == pad_rect:
		return
	var platform := Registry.get_floor(&"metal_plates")
	if platform != null:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not grid.in_bounds(x, y) or pad_rect.has_point(Vector2i(x, y)):
					continue
				if not grid.is_buildable(x, y) or buildings.get_at(Vector2i(x, y)) != null:
					continue
				var i := grid.index_of(x, y)
				grid.floors[i] = platform.index
	pad_rect = rect
	terrain_changed.emit(rect)
	bounds_changed.emit()


## Открытая часть мира в пикселях (вся карта, если не задана).
func get_play_rect_px() -> Rect2:
	var rect := play_rect if play_rect.size != Vector2i.ZERO else Rect2i(Vector2i.ZERO, Vector2i(grid.width, grid.height))
	return Rect2(Vector2(rect.position * GameConst.TILE_SIZE), Vector2(rect.size * GameConst.TILE_SIZE))


## Ставит шлюз (или его пару), убирая всё, что стоит на его месте.
func place_gateway(def: GatewayDef, origin: Vector2i, rotation: int = 0) -> GatewayBuilding:
	if def == null:
		return null
	for old in buildings.collect_in_rect(Rect2i(origin, Vector2i(def.size, def.size))):
		buildings.remove(old, true)
	gateway = buildings.place(def, origin, rotation, true) as GatewayBuilding
	return gateway


## Левый верхний тайл шлюза, чтобы его центр пришёлся на тайл center.
static func gateway_origin(def: GatewayDef, center: Vector2i, gate_size: int = 0) -> Vector2i:
	var s := gate_size if gate_size > 0 else def.start_size
	return center - Vector2i.ONE * (s / 2)


## Угроза опасной планеты: поле потоков к шлюзу, точки появления, расписание волн.
## compute — сразу посчитать поле (при загрузке оно восстанавливается из сохранения).
func setup_threat(def: ThreatDef, start_tick: int, seed_value: int, compute: bool = true) -> void:
	if def == null:
		return
	ensure_flow(compute)
	if spawn_points.is_empty() and gateway != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "spawns"])
		var center := gateway.origin + Vector2i.ONE * (gateway.get_size() / 2)
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
	if building is PlatformCore:
		# Якорь не исчезает: платформа аварийно отзывается в комнату вместе со всем, что уцелело.
		building.health = building.get_max_health()
		damaged.erase(building.id)
		var console := (building as PlatformCore).link.console if (building as PlatformCore).link != null else null
		if console != null:
			# Сворачиваем не здесь, а в тике самого пульта: посреди боя мир менять нельзя.
			console.recall()
			Events.toast(tr("TOAST_PLATFORM_RECALLED"), Events.ToastKind.WARNING)
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
func damage_drone(drone: Drone, amount: float, tick: int) -> void:
	if creative or drone == null or drone.world != self or not drone.is_targetable(tick):
		return
	drone.health -= amount
	if drone.health <= 0.0:
		kill_drone(drone, tick)


## Дрон сбит: инвентарь и отменённая очередь крафта падают грузом, через паузу — появление у шлюза.
func kill_drone(drone: Drone, tick: int) -> void:
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


## Дрон, которым сейчас играет этот клиент (для камеры, радиуса стройки и превью).
## Если локальный дрон в другом мире, берётся первый из здешних — так тесты и уровни
## продолжают работать с единственным дроном.
func add_drone(d: Drone) -> void:
	if drones.has(d):
		return
	drones.append(d)
	# Порядок дронов — по id игрока: от него зависит порядок в тике, он должен совпадать у всех.
	drones.sort_custom(func(a: Drone, b: Drone) -> bool: return a.player_id < b.player_id)


func remove_drone(d: Drone) -> void:
	drones.erase(d)


## Ближайший к точке живой дрон, которого можно атаковать (null — таких нет).
func nearest_targetable_drone(at: Vector2, tick: int) -> Drone:
	var best: Drone = null
	var best_distance := INF
	for d in drones:
		if not d.is_targetable(tick):
			continue
		var distance := d.position.distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best = d
	return best


func respawn_drone(drone: Drone, tick: int) -> void:
	if drone == null or not drone.dead:
		return
	drone.dead = false
	drone.health = drone.get_max_health()
	drone.invulnerable_until = tick + drone.def.get_invulnerable_ticks()
	if gateway != null and gateway.world == self:
		drone.position = gateway.get_world_center()
	drone.prev_position = drone.position
	drone_respawned.emit()


## Дрон подбирает груз в радиусе: сколько поместится; пустой груз исчезает.
func pickup_crates() -> int:
	if crates.is_empty():
		return 0
	var moved := 0
	for d in drones:
		moved += _pickup_for(d)
	return moved


## Подбор груза одним дроном: сколько предметов он забрал.
func _pickup_for(drone: Drone) -> int:
	if drone == null or drone.dead:
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


## Отдать команду от локального игрока. В отдельном мире (тесты, уровни) забега нет —
## там интерфейс не работает, а код зовёт действия напрямую.
func submit(kind: Command.Kind, args: Dictionary = {}) -> void:
	if run != null:
		run.submit(kind, args)


## Чей дрон действует сейчас: назначенный командой или дрон по умолчанию.
func acting_drone() -> Drone:
	if actor != null and actor.world == self:
		return actor
	return drone


## Дрон сейчас в этом мире и не сбит (действовать можно только здесь).
func has_drone() -> bool:
	var who := acting_drone()
	return who != null and who.world == self and not who.dead


## Может ли игрок взаимодействовать со зданием (настройка, окно, поворот): в радиусе дрона.
func can_interact(building: Building) -> bool:
	if building == null or building.world != self or not has_drone():
		return false
	return creative or acting_drone().can_reach_tiles(building.get_rect())


## Проверка строительства игроком: размещение, радиус дрона, постройка в инвентаре.
## budget — для планирования ряда построек: при успехе постройка резервируется в нём,
## иначе проверяется текущий инвентарь.
## Творческие блоки доступны только в творческом режиме.
func is_def_allowed(def: BuildingDef) -> bool:
	return not def.creative_only or creative


func check_build(def: BuildingDef, origin: Vector2i, rotation: int, budget: Inventory.Budget = null) -> BuildingManager.Check:
	if not is_def_allowed(def):
		return BuildingManager.Check.LOCKED
	var check := buildings.check_place(def, origin, rotation)
	if check != BuildingManager.Check.OK and check != BuildingManager.Check.REPLACE:
		return check
	if def is LiftDef and lift_check.is_valid():
		var lift := lift_check.call(self, def, origin) as BuildingManager.Check
		if lift != BuildingManager.Check.OK:
			return lift
	if not has_drone():
		return BuildingManager.Check.OUT_OF_RANGE
	if creative:
		return check
	var who := acting_drone()
	if not who.can_reach_tiles(Rect2i(origin, Vector2i(def.size, def.size))):
		return BuildingManager.Check.OUT_OF_RANGE
	if def.item == null:
		return BuildingManager.Check.NO_ITEM
	var local := budget if budget != null else who.inventory.make_budget()
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
	if not creative and acting_drone().inventory.remove(def.item.index, 1) == 0:
		return null
	var building := buildings.place(def, origin, rotation)
	if building == null and not creative:
		acting_drone().inventory.add(def.item.index, 1)
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
		if not acting_drone().can_reach_tiles(building.get_rect()):
			last_error = ActionError.OUT_OF_RANGE
			return false
		if item != null and acting_drone().inventory.space_for(item.index) < 1:
			last_error = ActionError.INVENTORY_FULL
			return false
	var contents := PackedInt32Array()
	contents.resize(Registry.items.size())
	contents.fill(0)
	building.collect_contents(contents)
	if not buildings.remove(building):
		return false
	if not creative and item != null:
		acting_drone().inventory.add(item.index, 1)
	for i in contents.size():
		if contents[i] > 0:
			last_lost_items += contents[i] - acting_drone().inventory.add(i, contents[i])
	return true


## Постройки группы, которые вообще умеют переезжать: остальное (шлюз, лифты) стоит на месте.
## Лифт привязан к паре на другом этаже, поэтому переносится только вместе с ней — пока никак.
static func can_move_building(building: Building) -> bool:
	return building != null and building.def.removable and building.def.player_buildable 		and not (building is Lift) and not (building is GatewayBuilding)


## Тайлы, занятые группой: при переносе они считаются свободными — постройки группы
## могут наезжать на места друг друга.
static func group_tiles(group: Array[Building]) -> Dictionary[Vector2i, bool]:
	var inside: Dictionary[Vector2i, bool] = {}
	for b in group:
		var rect := b.get_rect()
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				inside[Vector2i(x, y)] = true
	return inside


## Проверка переноса одной постройки группы: место, местность и радиус дрона (старое место
## и новое). Постройки в инвентаре не нужны — переезд ничего не тратит.
func check_move(building: Building, offset: Vector2i, inside: Dictionary[Vector2i, bool]) -> BuildingManager.Check:
	if not can_move_building(building):
		return BuildingManager.Check.OCCUPIED
	var check := buildings.check_move(building, offset, inside)
	if check != BuildingManager.Check.OK:
		return check
	if not has_drone():
		return BuildingManager.Check.OUT_OF_RANGE
	if creative:
		return check
	var rect := building.get_rect()
	var who := acting_drone()
	if not who.can_reach_tiles(rect) or not who.can_reach_tiles(Rect2i(rect.position + offset, rect.size)):
		return BuildingManager.Check.OUT_OF_RANGE
	return check


## Переносит группу построек на offset тайлов: всё или ничего. Постройки не сносятся и не строятся
## заново, а переезжают вместе со своим состоянием — содержимым, настройкой, прочностью и id;
## предметы на лентах едут вместе с ними. Ничего не тратится и не возвращается в инвентарь.
## Возвращает, сколько построек переехало (0 — не поместились, причина в last_error).
func move_group(ids: PackedInt32Array, offset: Vector2i) -> int:
	last_error = ActionError.NONE
	if offset == Vector2i.ZERO:
		return 0
	var moving: Array[Building] = []
	var seen: Dictionary[int, bool] = {}
	for id in ids:
		var b := buildings.get_by_id(id)
		if b == null or seen.has(id) or not can_move_building(b):
			continue
		seen[id] = true
		moving.append(b)
	if moving.is_empty():
		last_error = ActionError.NOT_ALLOWED
		return 0
	var inside := group_tiles(moving)
	for b in moving:
		var check := check_move(b, offset, inside)
		if check == BuildingManager.Check.OUT_OF_RANGE:
			last_error = ActionError.OUT_OF_RANGE
			return 0
		if check != BuildingManager.Check.OK:
			last_error = ActionError.NOT_ALLOWED
			return 0

	# Снимок всей группы до сноса: снимается так же, как в сохранении.
	var snapshots: Array[Dictionary] = []
	for b in moving:
		snapshots.append({"def": b.def, "origin": b.origin + offset, "rotation": b.rotation, "id": b.id,
			"size": b.size, "config": b.get_config(), "state": b.save_state(), "dump": b.get_dump_cursor(),
			"health": b.health})
		# Провода к оставшимся на месте опорам после переезда указывали бы в пустоту.
		if b is PowerPole:
			for other in (b as PowerPole).get_linked_poles():
				if not seen.has(other.id):
					(b as PowerPole).unlink(other)
					other.unlink(b as PowerPole)
	for b in moving:
		buildings.remove(b, true)
	var moved := 0
	var poles: Array[PowerPole] = []
	for snap in snapshots:
		var b := buildings.place(snap["def"], snap["origin"], snap["rotation"], true, snap["id"], snap["size"])
		if b == null:
			push_warning("GameWorld: постройка %s не встала после переноса" % snap["def"].id)
			continue
		if snap["config"] != null:
			b.set_config(snap["config"])
		b.set_dump_cursor(snap["dump"])
		b.load_state(snap["state"])
		b.health = clampf(snap["health"], 0.0, b.get_max_health())
		if b.is_damaged():
			damaged[b.id] = true
		if b is PowerPole:
			poles.append(b as PowerPole)
		moved += 1
	# Опоры на новом месте дотягиваются до соседей сами; связи внутри группы уже восстановлены.
	for pole in poles:
		power.auto_link(pole)
	return moved


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
	var who := acting_drone()
	var room := who.inventory.space_for(item)
	if room <= 0:
		last_error = ActionError.INVENTORY_FULL
		return 0
	var taken := building.take_player_items(item, mini(amount, room))
	if taken > 0:
		who.inventory.add(item, taken)
		who.note_move(item, taken, building.origin)
	return taken


## Shift+ЛКМ: забрать из здания всю накопленную продукцию. Возвращает, сколько забрано.
func player_take_output(building: Building) -> int:
	var taken := 0
	for stack in building.get_player_output_stacks():
		taken += player_take(building, stack.x, stack.y)
	return taken


## Shift+ПКМ: загрузить в здание всё подходящее из инвентаря дрона, сколько влезет.
func player_fill(building: Building) -> int:
	if not building.accepts_player_items():
		return 0
	var put := 0
	var who := acting_drone()
	for item in who.inventory.totals.size():
		var have := who.inventory.count(item)
		if have > 0 and building.accept_item(null, item):
			put += player_put(building, item, have)
	return put


## Положить предметы из инвентаря дрона в здание (сколько оно примет). Возвращает количество.
func player_put(building: Building, item: int, amount: int) -> int:
	if not can_interact(building) or not building.accepts_player_items() or item < 0:
		return 0
	var who := acting_drone()
	var limit := mini(amount, who.inventory.count(item))
	var put := 0
	while put < limit and building.accept_item(null, item):
		building.handle_item(null, item)
		put += 1
	if put > 0:
		who.inventory.remove(item, put)
		who.note_move(item, -put, building.origin)
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
