class_name Registry
extends RefCounted
## Реестр статических данных: предметы, полы, руды, здания, уровни.
## Всё загружается из .tres-файлов в фиксированных папках; порядок — по sort_order, затем по id.
## Реестр статический, поэтому доступен из любых скриптов, потоков и тестов без автозагрузки.

const ITEMS_DIR := "res://items/types/"
const FLOORS_DIR := "res://world/floors/"
const ORES_DIR := "res://world/ores/"
const BUILDINGS_DIR := "res://buildings/defs/"
const LEVELS_DIR := "res://levels/"

static var items: Array[ItemType] = []
static var floors: Array[FloorDef] = []
static var ores: Array[OreDef] = []
static var buildings: Array[BuildingDef] = []
static var levels: Array[LevelDef] = []

static var _items_by_id: Dictionary[StringName, ItemType] = {}
static var _floors_by_id: Dictionary[StringName, FloorDef] = {}
static var _ores_by_id: Dictionary[StringName, OreDef] = {}
static var _buildings_by_id: Dictionary[StringName, BuildingDef] = {}
static var _levels_by_id: Dictionary[StringName, LevelDef] = {}

## Таблица «пол → можно строить» для быстрых проверок в сетке.
static var floor_buildable: PackedByteArray = PackedByteArray()

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	for res in _load_dir(ITEMS_DIR):
		if res is ItemType:
			items.append(res)
	for res in _load_dir(FLOORS_DIR):
		if res is FloorDef:
			floors.append(res)
	for res in _load_dir(ORES_DIR):
		if res is OreDef:
			ores.append(res)
	for res in _load_dir(BUILDINGS_DIR):
		if res is BuildingDef:
			buildings.append(res)
	for res in _load_dir(LEVELS_DIR):
		if res is LevelDef:
			levels.append(res)

	items.sort_custom(func(a: ItemType, b: ItemType) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	floors.sort_custom(func(a: FloorDef, b: FloorDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	ores.sort_custom(func(a: OreDef, b: OreDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	buildings.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	levels.sort_custom(func(a: LevelDef, b: LevelDef) -> bool: return _less(a.order, a.id, b.order, b.id))

	for i in items.size():
		items[i].index = i
		_register(_items_by_id, items[i].id, items[i], "item")
	for i in floors.size():
		floors[i].index = i
		_register(_floors_by_id, floors[i].id, floors[i], "floor")
	for i in ores.size():
		ores[i].index = i
		_register(_ores_by_id, ores[i].id, ores[i], "ore")
	for i in buildings.size():
		buildings[i].index = i
		_register(_buildings_by_id, buildings[i].id, buildings[i], "building")
	for level in levels:
		_register(_levels_by_id, level.id, level, "level")

	floor_buildable.resize(256)
	floor_buildable.fill(0)
	for f in floors:
		floor_buildable[f.index] = 1 if f.buildable else 0

	for error in validate():
		push_error("Registry: " + error)


static func get_item(id: StringName) -> ItemType:
	return _items_by_id.get(id)


static func get_floor(id: StringName) -> FloorDef:
	return _floors_by_id.get(id)


static func get_ore(id: StringName) -> OreDef:
	return _ores_by_id.get(id)


static func get_building(id: StringName) -> BuildingDef:
	return _buildings_by_id.get(id)


static func get_level(id: StringName) -> LevelDef:
	return _levels_by_id.get(id)


## Здания категории для меню строительства (только доступные игроку).
static func buildings_in_category(category: BuildingDef.Category) -> Array[BuildingDef]:
	var result: Array[BuildingDef] = []
	for def in buildings:
		if def.category == category and def.player_buildable:
			result.append(def)
	return result


## Проверка целостности данных. Возвращает список ошибок.
static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if floors.is_empty():
		errors.append("нет ни одного типа пола в " + FLOORS_DIR)
	if floors.size() > 255:
		errors.append("типов пола больше 255")
	if ores.size() > 254:
		errors.append("типов руды больше 254")
	for ore in ores:
		if ore.item == null:
			errors.append("руда %s без предмета" % ore.id)
	for def in buildings:
		if def is CrafterDef:
			var recipe := (def as CrafterDef).recipe
			if recipe == null:
				errors.append("завод %s без рецепта" % def.id)
			else:
				errors.append_array(recipe.validate())
		if def.size < 1 or def.size > GameConst.MAX_BUILDING_SIZE:
			errors.append("здание %s: недопустимый размер %d" % [def.id, def.size])
		for stack in def.cost:
			if stack == null or stack.item == null:
				errors.append("здание %s: пустая позиция стоимости" % def.id)
	for level in levels:
		if not FileAccess.file_exists(level.map_path):
			errors.append("уровень %s: нет файла карты %s" % [level.id, level.map_path])
	return errors


static func _load_dir(dir: String) -> Array[Resource]:
	var result: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for file_name in ResourceLoader.list_directory(dir):
		if file_name.ends_with("/"):
			continue
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var res := load(dir.path_join(file_name))
		if res != null:
			result.append(res)
	return result


static func _register(table: Dictionary, id: StringName, value: Variant, kind: String) -> void:
	if id.is_empty():
		push_error("Registry: %s без id" % kind)
		return
	if table.has(id):
		push_error("Registry: повторяющийся id %s «%s»" % [kind, id])
		return
	table[id] = value


static func _less(order_a: int, id_a: StringName, order_b: int, id_b: StringName) -> bool:
	if order_a != order_b:
		return order_a < order_b
	return String(id_a) < String(id_b)
