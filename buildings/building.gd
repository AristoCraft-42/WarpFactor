class_name Building
extends RefCounted
## Базовое здание. Это лёгкий объект данных, а не нода сцены.
##
## Жизненный цикл: on_placed → (on_proximity_changed / on_rotated)* → on_removed.
## Симуляция: здание обновляется (update_tick) только пока бодрствует. Уснуть можно до тика
## (sleep_until) или до события: предмет пришёл (handle_item будит), сосед освободил место
## (wait_for → notify_space), изменилось соседство.
##
## Передача предметов: источник спрашивает accept_item и, получив true, вызывает handle_item.
## Задел под энергию и жидкости: такие протоколы добавятся методами с поведением «нет» по умолчанию.

## Вид настройки здания (что показывает панель настройки).
enum ConfigKind { NONE, ITEM, BRIDGE }
## Состояние здания для подсказки.
enum Status { NONE, WORKING, IDLE, NO_INPUT, OUTPUT_BLOCKED, NO_ORE }

## Уникальный id в BuildingManager (0 — «нет здания»).
var id: int = 0
var def: BuildingDef
## Левый верхний тайл.
var origin: Vector2i = Vector2i.ZERO
## Направление 0..3 (см. GameConst.Dir); спрайты нарисованы «вправо».
var rotation: int = 0
## Мир, которому принадлежит здание. Обнуляется при удалении/выгрузке мира.
var world: GameWorld
## Соседи по граням. Пересчитывается при изменении соседства, в тике по сетке никто не ищет.
var proximity: Array[Building] = []
## Флаг списка бодрствующих (управляется Simulation).
var awake: bool = false

var _dump_index: int = 0


func get_size() -> int:
	return def.size


func get_rect() -> Rect2i:
	return Rect2i(origin, Vector2i(def.size, def.size))


func get_world_rect() -> Rect2:
	return Rect2(Vector2(origin * GameConst.TILE_SIZE), def.get_pixel_size())


func get_world_center() -> Vector2:
	return get_world_rect().get_center()


func occupies(tile: Vector2i) -> bool:
	return get_rect().has_point(tile)


func get_display_name() -> String:
	return tr(def.name_key)


## С какой стороны примыкает other: направление от этого здания к other (0..3) или -1.
func side_of(other: Building) -> int:
	var r := get_rect()
	var o := other.get_rect()
	var overlap_y := o.position.y < r.end.y and o.end.y > r.position.y
	var overlap_x := o.position.x < r.end.x and o.end.x > r.position.x
	if overlap_y and o.position.x == r.end.x:
		return GameConst.Dir.RIGHT
	if overlap_y and o.end.x == r.position.x:
		return GameConst.Dir.LEFT
	if overlap_x and o.position.y == r.end.y:
		return GameConst.Dir.DOWN
	if overlap_x and o.end.y == r.position.y:
		return GameConst.Dir.UP
	return -1


# --- Жизненный цикл ---

## Здание занесено в сетку (соседство ещё не пересчитано).
func on_placed() -> void:
	pass


## Здание сейчас будет удалено из сетки.
func on_removed() -> void:
	pass


## Поворот уже изменён; old_rotation — прежнее направление.
func on_rotated(_old_rotation: int) -> void:
	pass


## Изменилось соседство (proximity уже пересчитан) или поворот соседей.
func on_proximity_changed() -> void:
	pass


# --- Симуляция ---

## Один логический тик. Вернуть true, чтобы остаться бодрствующим и на следующем тике.
func update_tick(_tick: int) -> bool:
	return false


func wake() -> void:
	if world != null:
		world.simulation.wake(self)


## Проснуться на указанном тике (если раньше не разбудит событие).
func sleep_until(tick: int) -> void:
	if world != null:
		world.simulation.schedule(self, tick)


## Проснуться, когда target освободит место.
func wait_for(target: Building) -> void:
	if world != null:
		world.simulation.add_waiter(target.id, id)


func wait_for_proximity() -> void:
	for target in proximity:
		wait_for(target)


## Сообщить ожидающим, что у здания появилось место.
func notify_space() -> void:
	if world != null:
		world.simulation.notify_space(id)


# --- Предметы ---

## Может ли здание принять предмет от source прямо сейчас.
func accept_item(_source: Building, _item: int) -> bool:
	return false


## Принять предмет (вызывается только после accept_item = true).
func handle_item(_source: Building, _item: int) -> void:
	pass


## Отдать предмет одному из соседей по кругу. true — предмет передан.
func dump(item: int) -> bool:
	var n := proximity.size()
	for k in n:
		var target := proximity[(_dump_index + k) % n]
		if target.accept_item(self, item):
			target.handle_item(self, item)
			_dump_index = (_dump_index + k + 1) % n
			return true
	return false


## Добавляет в out (индекс = индекс предмета) всё, что лежит внутри здания.
## При сносе это содержимое уходит в ядро.
func collect_contents(_out: PackedInt32Array) -> void:
	pass


# --- Интерфейс ---

## Строки состояния для инфо-панели.
func get_info_lines() -> PackedStringArray:
	return PackedStringArray()


func get_status() -> Status:
	return Status.NONE


# --- Хранилища (разгрузчик берёт из них предметы) ---

func can_unload() -> bool:
	return false


func has_item(_item: int) -> bool:
	return false


## Забрать один предмет. true — предмет изъят.
func unload_item(_item: int) -> bool:
	return false


# --- Настройка ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.NONE


## Настройка здания (фильтр сортировщика, связь моста и т. п.). Копируется пипеткой.
func get_config() -> Variant:
	return null


func set_config(_value: Variant) -> void:
	pass


## Предмет, иконку которого показать на здании (-1 — нет).
func get_display_item() -> int:
	return -1
