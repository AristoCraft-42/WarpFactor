class_name Registry
extends RefCounted
## Реестр статических данных: предметы, полы, руды, здания, уровни, дрон.
## Всё загружается из .tres-файлов в фиксированных папках; порядок — по sort_order, затем по id.
## Реестр статический, поэтому доступен из любых скриптов, потоков и тестов без автозагрузки.
##
## Предметы-постройки лежат отдельно (items/types/buildings/) и ссылаются на своё здание;
## реестр связывает здание с предметом и строит из стоимости здания рецепт ручного крафта.

const ITEMS_DIR := "res://items/types/"
const BUILDING_ITEMS_DIR := "res://items/types/buildings/"
const FLOORS_DIR := "res://world/floors/"
const ORES_DIR := "res://world/ores/"
const BUILDINGS_DIR := "res://buildings/defs/"
const LEVELS_DIR := "res://levels/"
const DRONE_PATH := "res://player/drone.tres"
const BASE_PATH := "res://world/base.tres"

static var items: Array[ItemType] = []
static var floors: Array[FloorDef] = []
static var ores: Array[OreDef] = []
static var buildings: Array[BuildingDef] = []
static var levels: Array[LevelDef] = []
static var hand_recipes: Array[HandRecipe] = []
static var drone_def: DroneDef
static var base_def: BaseDef

## Размер стака по индексу предмета (горячий путь инвентаря).
static var stack_sizes: PackedInt32Array = PackedInt32Array()
## Таблица «пол → можно строить» для быстрых проверок в сетке.
static var floor_buildable: PackedByteArray = PackedByteArray()

static var _items_by_id: Dictionary[StringName, ItemType] = {}
static var _floors_by_id: Dictionary[StringName, FloorDef] = {}
static var _ores_by_id: Dictionary[StringName, OreDef] = {}
static var _buildings_by_id: Dictionary[StringName, BuildingDef] = {}
static var _levels_by_id: Dictionary[StringName, LevelDef] = {}
static var _recipe_by_item: Dictionary[int, HandRecipe] = {}

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	for dir in [ITEMS_DIR, BUILDING_ITEMS_DIR]:
		for res in _load_dir(dir):
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
	if ResourceLoader.exists(DRONE_PATH):
		drone_def = load(DRONE_PATH) as DroneDef
	if drone_def == null:
		drone_def = DroneDef.new()
	if ResourceLoader.exists(BASE_PATH):
		base_def = load(BASE_PATH) as BaseDef
	if base_def == null:
		base_def = BaseDef.new()

	items.sort_custom(func(a: ItemType, b: ItemType) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	floors.sort_custom(func(a: FloorDef, b: FloorDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	ores.sort_custom(func(a: OreDef, b: OreDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	buildings.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	levels.sort_custom(func(a: LevelDef, b: LevelDef) -> bool: return _less(a.order, a.id, b.order, b.id))

	stack_sizes.resize(items.size())
	for i in items.size():
		items[i].index = i
		stack_sizes[i] = maxi(items[i].stack_size, 1)
		_register(_items_by_id, items[i].id, items[i], "item")
		if items[i].building != null:
			items[i].building.item_index = i
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

	# Рецепты ручного крафта — в порядке предметов.
	for item in items:
		var def := item.building
		if def == null or not def.player_buildable or def.cost.is_empty():
			continue
		var recipe := HandRecipe.new(item, def.craft_amount, def.cost, roundi(def.craft_time * GameConst.TICK_RATE))
		hand_recipes.append(recipe)
		_recipe_by_item[item.index] = recipe

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


## Рецепт ручного крафта предмета (null — руками не делается).
static func get_hand_recipe(item: int) -> HandRecipe:
	return _recipe_by_item.get(item)


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
	for item in items:
		if item.stack_size < 1:
			errors.append("предмет %s: размер стака меньше 1" % item.id)
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
		if def.player_buildable:
			if def.item == null:
				errors.append("здание %s: нет предмета-постройки в %s" % [def.id, BUILDING_ITEMS_DIR])
			if def.cost.is_empty():
				errors.append("здание %s: нет рецепта крафта (cost)" % def.id)
	if get_floor(base_def.floor_id) == null:
		errors.append("база: нет пола %s" % base_def.floor_id)
	for id in [&"central_gateway", &"base_gateway"]:
		if not (get_building(id) is GatewayDef):
			errors.append("нет шлюза %s" % id)
	for level in levels:
		if not FileAccess.file_exists(level.map_path):
			errors.append("уровень %s: нет файла карты %s" % [level.id, level.map_path])
		for stack in level.starting_items:
			if stack == null or stack.item == null:
				errors.append("уровень %s: пустая позиция стартового инвентаря" % level.id)
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
