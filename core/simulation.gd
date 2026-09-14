class_name Simulation
extends RefCounted
## Логическая симуляция уровня с фиксированным тиком (GameConst.TICK_RATE).
## Никакого обхода всех зданий или тайлов: обновляются только бодрствующие здания и ленты.
##
## Порядок тика:
##   1. планировщик будит здания, чьё время пришло;
##   2. ConveyorSystem двигает бодрствующие ленты;
##   3. бодрствующие здания выполняют update_tick;
##   4. дрон игрока (движение, добыча, ручной крафт).
## Здание, разбуженное во время тика, обновится на следующем тике — так предмет не может
## пройти несколько построек за один тик независимо от порядка обновления.

var tick: int = 0
var conveyors: ConveyorSystem

## Время последнего тика и сглаженное среднее, мкс.
var last_tick_usec: int = 0
var avg_tick_usec: float = 0.0
var last_awake_buildings: int = 0

var _world: GameWorld
var _manager: BuildingManager
var _scheduler := Scheduler.new()
var _awake: Array[Building] = []
## id получателя → id зданий, ждущих, пока у него освободится место.
var _waiters: Dictionary[int, PackedInt32Array] = {}
var _due := PackedInt32Array()


func _init(world: GameWorld, manager: BuildingManager) -> void:
	_world = world
	_manager = manager
	conveyors = ConveyorSystem.new(self, manager)
	manager.building_added.connect(_on_building_added)
	manager.building_removed.connect(_on_building_removed)
	manager.building_rotated.connect(_on_building_rotated)


## Разрывает циклические ссылки перед выгрузкой.
func dispose() -> void:
	if conveyors != null:
		conveyors.dispose()
	conveyors = null
	_world = null
	_manager = null
	_awake.clear()
	_waiters.clear()


func step() -> void:
	var start := Time.get_ticks_usec()
	tick += 1

	_due.clear()
	_scheduler.pop_due(tick, _due)
	for id in _due:
		wake_id(id)

	conveyors.update(tick)

	var current := _awake
	_awake = []
	for b in current:
		b.awake = false
	for b in current:
		if b.world != null and b.update_tick(tick):
			wake(b)
	last_awake_buildings = current.size()

	if _world.drone != null:
		_world.drone.update_tick(tick)

	last_tick_usec = Time.get_ticks_usec() - start
	avg_tick_usec = lerpf(avg_tick_usec, float(last_tick_usec), 0.05)


func wake(building: Building) -> void:
	if building is Conveyor:
		conveyors.wake_building(building.id)
		return
	if building.awake or building.world == null:
		return
	building.awake = true
	_awake.append(building)


func wake_id(building_id: int) -> void:
	var b := _manager.get_by_id(building_id)
	if b != null:
		wake(b)


func schedule(building: Building, at_tick: int) -> void:
	_scheduler.schedule(building.id, maxi(at_tick, tick + 1))


func add_waiter(target_id: int, waiter_id: int) -> void:
	# Мгновенные здания (сортировщик, шлюзы) не имеют буфера и сами никого не будят:
	# ждём их соседей — именно у них освободится место.
	var target := _manager.get_by_id(target_id)
	if target is PassThroughBuilding:
		_add_waiter_through(target, waiter_id, 0)
		return
	_add_waiter_direct(target_id, waiter_id)


func _add_waiter_through(target: Building, waiter_id: int, depth: int) -> void:
	for other in target.proximity:
		if other.id == waiter_id:
			continue
		if other is PassThroughBuilding:
			if depth < PassThroughBuilding.MAX_DEPTH:
				_add_waiter_through(other, waiter_id, depth + 1)
		else:
			_add_waiter_direct(other.id, waiter_id)


func _add_waiter_direct(target_id: int, waiter_id: int) -> void:
	if not _waiters.has(target_id):
		_waiters[target_id] = PackedInt32Array()
	var list := _waiters[target_id]
	if not list.has(waiter_id):
		list.append(waiter_id)
		_waiters[target_id] = list
	conveyors.set_has_waiters(target_id, true)


func has_waiters(target_id: int) -> bool:
	return _waiters.has(target_id)


func notify_space(target_id: int) -> void:
	if not _waiters.has(target_id):
		return
	var list := _waiters[target_id]
	_waiters.erase(target_id)
	conveyors.set_has_waiters(target_id, false)
	for id in list:
		wake_id(id)


## Здание изменилось так, что соседи могут снова передавать через него (настройка, связь моста):
## будим его самого, соседей и всех, кто ждал у него места.
func on_building_reconfigured(building: Building) -> void:
	wake(building)
	notify_space(building.id)
	for other in building.proximity:
		wake(other)


func get_awake_building_count() -> int:
	return _awake.size()


# --- Соседство ---

func _on_building_added(building: Building) -> void:
	_refresh_proximity(building)
	for other in building.proximity:
		_refresh_proximity(other)
		other.on_proximity_changed()
		wake(other)
	building.on_proximity_changed()
	wake(building)


func _on_building_removed(building: Building) -> void:
	for other in building.proximity:
		if other.world == null:
			continue
		_refresh_proximity(other)
		other.on_proximity_changed()
		wake(other)
	# Ждавшие этого здания — пусть проверят обстановку заново.
	notify_space(building.id)
	building.proximity = []


func _on_building_rotated(building: Building) -> void:
	building.on_proximity_changed()
	wake(building)
	for other in building.proximity:
		other.on_proximity_changed()
		wake(other)


## Пересчитывает соседей по граням (без углов).
func _refresh_proximity(building: Building) -> void:
	var rect := building.get_rect()
	var result: Array[Building] = []
	for x in range(rect.position.x, rect.end.x):
		_add_neighbor(result, building, Vector2i(x, rect.position.y - 1))
		_add_neighbor(result, building, Vector2i(x, rect.end.y))
	for y in range(rect.position.y, rect.end.y):
		_add_neighbor(result, building, Vector2i(rect.position.x - 1, y))
		_add_neighbor(result, building, Vector2i(rect.end.x, y))
	building.proximity = result


func _add_neighbor(result: Array[Building], building: Building, tile: Vector2i) -> void:
	var other := _manager.get_at(tile)
	if other != null and other != building and not result.has(other):
		result.append(other)
