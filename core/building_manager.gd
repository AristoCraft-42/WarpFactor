class_name BuildingManager
extends RefCounted
## Установка и снос зданий, поиск по тайлам и чанкам.
## Здания хранятся в массиве по id (с переиспользованием свободных id),
## плюс для каждого чанка — список id зданий, чей левый верхний тайл лежит в этом чанке.

signal building_added(building: Building)
signal building_removed(building: Building)
signal building_rotated(building: Building)
## Изменилась настройка или внешний вид здания (перерисовать чанк).
signal building_changed(building: Building)

## Результат проверки размещения.
enum Check {
	OK, ## можно ставить
	REPLACE, ## заменит существующее здание с тем же прямоугольником (поворот/апгрейд)
	SAME, ## такое же здание уже стоит — ничего не делать
	OUT_OF_BOUNDS,
	BAD_TERRAIN,
	OCCUPIED,
	NO_ORE, ## буру нечего добывать
	NO_ITEM, ## постройки нет в инвентаре дрона (выставляет GameWorld)
	OUT_OF_RANGE, ## вне радиуса дрона (выставляет GameWorld)
	ON_FLUID, ## на воде можно ставить только трубы и насосы
}

var grid: WorldGrid
var _world: GameWorld
var _by_id: Array[Building] = [null]
var _free_ids: PackedInt32Array = PackedInt32Array()
var _chunk_lists: Array[PackedInt32Array] = []
var _count: int = 0


func _init(p_world: GameWorld, p_grid: WorldGrid) -> void:
	_world = p_world
	grid = p_grid
	_chunk_lists.resize(grid.chunks_x() * grid.chunks_y())
	for i in _chunk_lists.size():
		_chunk_lists[i] = PackedInt32Array()


func get_count() -> int:
	return _count


func get_by_id(id: int) -> Building:
	return _by_id[id] if id > 0 and id < _by_id.size() else null


func get_at(tile: Vector2i) -> Building:
	if not grid.in_bounds_v(tile):
		return null
	return get_by_id(grid.building_ids[grid.index_of(tile.x, tile.y)])


static func is_valid_check(check: Check) -> bool:
	return check == Check.OK or check == Check.REPLACE or check == Check.SAME


## Проверка: можно ли поставить def с левым верхним тайлом origin и поворотом rotation.
func check_place(def: BuildingDef, origin: Vector2i, rotation: int) -> Check:
	var rect := Rect2i(origin, Vector2i(def.size, def.size))
	if not grid.rect_in_bounds(rect):
		return Check.OUT_OF_BOUNDS
	var existing_id := 0
	var occupied_by_other := false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not grid.is_buildable(x, y):
				return Check.BAD_TERRAIN
			if not def.allowed_on_fluid:
				var ore := grid.get_ore_def(x, y)
				if ore != null and ore.fluid != null:
					return Check.ON_FLUID
			var id := grid.building_ids[grid.index_of(x, y)]
			if id != 0:
				if existing_id == 0:
					existing_id = id
				elif existing_id != id:
					occupied_by_other = true
	var extra := def.check_placement(grid, origin)
	if extra != Check.OK:
		return extra as Check
	if existing_id == 0:
		return Check.OK
	if occupied_by_other:
		return Check.OCCUPIED
	var existing := _by_id[existing_id]
	if existing.get_rect() != rect:
		return Check.OCCUPIED
	if existing.def == def and (existing.rotation == rotation or not def.rotatable):
		return Check.SAME
	if not existing.def.removable:
		return Check.OCCUPIED
	return Check.REPLACE


## Ставит здание. При force=false проверяет размещение (REPLACE сносит старое здание).
## forced_id — занять конкретный id (загрузка сохранения). Возвращает новое здание или null.
func place(def: BuildingDef, origin: Vector2i, rotation: int, force: bool = false, forced_id: int = 0) -> Building:
	var check := check_place(def, origin, rotation)
	if check == Check.SAME:
		return null
	if not force and not is_valid_check(check):
		return null
	if check == Check.REPLACE or (force and check == Check.OCCUPIED):
		for b in collect_in_rect(Rect2i(origin, Vector2i(def.size, def.size))):
			remove(b, true)
	elif force and (check == Check.OUT_OF_BOUNDS):
		return null

	var building := def.create_building()
	building.def = def
	building.origin = origin
	building.rotation = posmod(rotation, 4) if def.rotatable else 0
	building.world = _world
	building.health = def.get_max_health()
	building.id = _reserve_id(forced_id) if forced_id > 0 else _allocate_id()
	_by_id[building.id] = building

	var rect := building.get_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid.building_ids[grid.index_of(x, y)] = building.id

	var chunk_idx := grid.chunk_index(GameConst.tile_to_chunk(origin))
	_chunk_lists[chunk_idx].append(building.id)
	_count += 1

	building.on_placed()
	building_added.emit(building)
	return building


## Поворачивает здание на новое направление. false — если поворот невозможен или не нужен.
func rotate(building: Building, new_rotation: int) -> bool:
	if building == null or building.id == 0 or not building.def.rotatable:
		return false
	var old := building.rotation
	building.rotation = posmod(new_rotation, 4)
	if building.rotation == old:
		return false
	building.on_rotated(old)
	building_rotated.emit(building)
	return true


func notify_changed(building: Building) -> void:
	if building != null and building.id != 0:
		building_changed.emit(building)


## Сносит здание. Неудаляемые сносятся только с force=true.
func remove(building: Building, force: bool = false) -> bool:
	if building == null or building.id == 0 or get_by_id(building.id) != building:
		return false
	if not force and not building.def.removable:
		return false

	building.on_removed()

	var rect := building.get_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid.building_ids[grid.index_of(x, y)] = 0

	var chunk_idx := grid.chunk_index(GameConst.tile_to_chunk(building.origin))
	var pos := _chunk_lists[chunk_idx].find(building.id)
	if pos >= 0:
		_chunk_lists[chunk_idx].remove_at(pos)

	_by_id[building.id] = null
	_free_ids.append(building.id)
	_count -= 1

	building_removed.emit(building)
	building.world = null
	building.id = 0
	return true


## Уникальные здания, пересекающие прямоугольник тайлов.
## Перебираются только чанки, в которых могут лежать левые верхние углы таких зданий.
func collect_in_rect(rect: Rect2i) -> Array[Building]:
	var result: Array[Building] = []
	var clipped := rect.intersection(Rect2i(0, 0, grid.width, grid.height))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return result
	var reach := GameConst.MAX_BUILDING_SIZE - 1
	var c0 := GameConst.tile_to_chunk(Vector2i(maxi(clipped.position.x - reach, 0), maxi(clipped.position.y - reach, 0)))
	var c1 := GameConst.tile_to_chunk(clipped.end - Vector2i.ONE)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for id in _chunk_lists[cy * grid.chunks_x() + cx]:
				var b := _by_id[id]
				if b.get_rect().intersects(clipped):
					result.append(b)
	return result


## id зданий, чей левый верхний тайл лежит в чанке.
func get_chunk_ids(chunk_idx: int) -> PackedInt32Array:
	return _chunk_lists[chunk_idx]


func get_all() -> Array[Building]:
	var result: Array[Building] = []
	for b in _by_id:
		if b != null:
			result.append(b)
	return result


func find_first(def_id: StringName) -> Building:
	for b in _by_id:
		if b != null and b.def.id == def_id:
			return b
	return null


## Разрывает ссылки здание → мир (RefCounted-циклы), вызывается при выгрузке уровня.
func dispose() -> void:
	for b in _by_id:
		if b != null:
			b.world = null
			b.proximity = []
	_by_id.clear()
	_world = null


## Сколько id выделено (включая свободные) и список свободных — для сохранения.
func get_id_capacity() -> int:
	return _by_id.size()


func get_free_ids() -> PackedInt32Array:
	return _free_ids.duplicate()


## Восстановить выдачу id как в сохранении (после расстановки зданий с их id).
func restore_ids(capacity: int, free_ids: PackedInt32Array) -> void:
	while _by_id.size() < capacity:
		_by_id.append(null)
	_free_ids = PackedInt32Array()
	for id in free_ids:
		if id > 0 and id < _by_id.size() and _by_id[id] == null:
			_free_ids.append(id)


func _reserve_id(id: int) -> int:
	while _by_id.size() <= id:
		_by_id.append(null)
	var pos := _free_ids.find(id)
	if pos >= 0:
		_free_ids.remove_at(pos)
	return id


func _allocate_id() -> int:
	if not _free_ids.is_empty():
		var id := _free_ids[_free_ids.size() - 1]
		_free_ids.remove_at(_free_ids.size() - 1)
		return id
	_by_id.append(null)
	return _by_id.size() - 1
