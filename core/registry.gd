class_name Registry
extends RefCounted
## Реестр статических данных: предметы, жидкости, полы, руды, рецепты, здания, исследования, уровни, дрон, враги.
## Всё загружается из .tres-файлов в фиксированных папках; порядок — по sort_order, затем по id.
## Реестр статический, поэтому доступен из любых скриптов, потоков и тестов без автозагрузки.
##
## Предметы-постройки лежат отдельно (items/types/buildings/) и ссылаются на своё здание;
## реестр связывает здание с предметом и строит из стоимости здания рецепт ручного крафта.
## Рецепты компонентов с hand_craftable тоже становятся ручными. Для построек и рецептов запоминается,
## каким исследованием они открываются (без исследования — доступны сразу).

const ITEMS_DIR := "res://items/types/"
const BUILDING_ITEMS_DIR := "res://items/types/buildings/"
const FLOORS_DIR := "res://world/floors/"
const ORES_DIR := "res://world/ores/"
const BUILDINGS_DIR := "res://buildings/defs/"
const LEVELS_DIR := "res://levels/"
const DRONE_PATH := "res://player/drone.tres"
const BASE_PATH := "res://world/base.tres"
const MINING_PATH := "res://world/mining.tres"
const RUN_PATH := "res://world/run.tres"
const PLANET_TYPES_DIR := "res://world/planet_types/"
const ENEMIES_DIR := "res://enemies/defs/"
const FLUIDS_DIR := "res://fluids/defs/"
const RECIPES_DIR := "res://items/recipes/"
const RESEARCH_DIR := "res://research/defs/"

static var items: Array[ItemType] = []
static var floors: Array[FloorDef] = []
static var ores: Array[OreDef] = []
static var buildings: Array[BuildingDef] = []
static var levels: Array[LevelDef] = []
static var hand_recipes: Array[HandRecipe] = []
static var drone_def: DroneDef
static var base_def: BaseDef
## Этаж добычи: центральная комната, четыре комнаты с платформами и туннели к ним.
static var mining_def: BaseDef
static var run_def: RunDef
static var planet_types: Array[PlanetTypeDef] = []
static var enemies: Array[EnemyDef] = []
static var fluids: Array[FluidDef] = []
static var recipes: Array[Recipe] = []
static var researches: Array[ResearchDef] = []

## Размер стака по индексу предмета (горячий путь инвентаря).
static var stack_sizes: PackedInt32Array = PackedInt32Array()
## Таблица «пол → можно строить» для быстрых проверок в сетке.
static var floor_buildable: PackedByteArray = PackedByteArray()

static var _items_by_id: Dictionary[StringName, ItemType] = {}
static var _floors_by_id: Dictionary[StringName, FloorDef] = {}
static var _ores_by_id: Dictionary[StringName, OreDef] = {}
static var _buildings_by_id: Dictionary[StringName, BuildingDef] = {}
static var _levels_by_id: Dictionary[StringName, LevelDef] = {}
static var _enemies_by_id: Dictionary[StringName, EnemyDef] = {}
static var _recipe_by_item: Dictionary[int, HandRecipe] = {}
static var _fluids_by_id: Dictionary[StringName, FluidDef] = {}
static var _recipes_by_id: Dictionary[StringName, Recipe] = {}
static var _researches_by_id: Dictionary[StringName, ResearchDef] = {}
## Постройка или рецепт → исследование, которое их открывает.
static var _building_research: Dictionary[StringName, ResearchDef] = {}
static var _recipe_research: Dictionary[StringName, ResearchDef] = {}

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
	if ResourceLoader.exists(MINING_PATH):
		mining_def = load(MINING_PATH) as BaseDef
	if mining_def == null:
		mining_def = base_def
	if ResourceLoader.exists(RUN_PATH):
		run_def = load(RUN_PATH) as RunDef
	if run_def == null:
		run_def = RunDef.new()
	for res in _load_dir(PLANET_TYPES_DIR):
		if res is PlanetTypeDef:
			planet_types.append(res)
	planet_types.sort_custom(func(a: PlanetTypeDef, b: PlanetTypeDef) -> bool: return String(a.id) < String(b.id))
	for res in _load_dir(FLUIDS_DIR):
		if res is FluidDef:
			fluids.append(res)
	fluids.sort_custom(func(a: FluidDef, b: FluidDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	for i in fluids.size():
		fluids[i].index = i
		_register(_fluids_by_id, fluids[i].id, fluids[i], "fluid")
	for res in _load_dir(RECIPES_DIR):
		if res is Recipe:
			recipes.append(res)
	recipes.sort_custom(func(a: Recipe, b: Recipe) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	for recipe in recipes:
		_register(_recipes_by_id, recipe.id, recipe, "recipe")
	for res in _load_dir(RESEARCH_DIR):
		if res is ResearchDef:
			researches.append(res)
	researches.sort_custom(func(a: ResearchDef, b: ResearchDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	for i in researches.size():
		researches[i].index = i
		_register(_researches_by_id, researches[i].id, researches[i], "research")
		for def in researches[i].unlock_buildings:
			if def != null:
				_building_research[def.id] = researches[i]
		for recipe in researches[i].unlock_recipes:
			if recipe != null:
				_recipe_research[recipe.id] = researches[i]
	for res in _load_dir(ENEMIES_DIR):
		if res is EnemyDef:
			enemies.append(res)
	enemies.sort_custom(func(a: EnemyDef, b: EnemyDef) -> bool: return _less(a.sort_order, a.id, b.sort_order, b.id))
	for i in enemies.size():
		enemies[i].index = i
		_register(_enemies_by_id, enemies[i].id, enemies[i], "enemy")

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

	# Рецепты ручного крафта — в порядке предметов: постройки и компоненты с hand_craftable.
	var component_recipes: Dictionary[int, Recipe] = {}
	for recipe in recipes:
		var main := recipe.get_main_output()
		if recipe.hand_craftable and main != null and not component_recipes.has(main.item.index):
			component_recipes[main.item.index] = recipe
	for item in items:
		var def := item.building
		var hand: HandRecipe = null
		if def != null:
			if not def.player_buildable or def.cost.is_empty():
				continue
			hand = HandRecipe.new(item, def.craft_amount, def.cost, roundi(def.craft_time * GameConst.TICK_RATE))
			hand.building = def
		elif component_recipes.has(item.index):
			var recipe := component_recipes[item.index]
			var ingredients: Array[ItemStack] = []
			for c in recipe.consumes:
				ingredients.append_array(c.display_stacks())
			hand = HandRecipe.new(item, recipe.get_main_output().amount, ingredients, recipe.get_craft_ticks())
			hand.recipe = recipe
		if hand == null:
			continue
		hand_recipes.append(hand)
		_recipe_by_item[item.index] = hand

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


static func get_enemy(id: StringName) -> EnemyDef:
	return _enemies_by_id.get(id)


static func get_fluid(id: StringName) -> FluidDef:
	return _fluids_by_id.get(id)


static func get_recipe(id: StringName) -> Recipe:
	return _recipes_by_id.get(id)


static func get_research(id: StringName) -> ResearchDef:
	return _researches_by_id.get(id)


## Исследование, открывающее постройку (null — доступна сразу).
static func get_building_research(def: BuildingDef) -> ResearchDef:
	return _building_research.get(def.id) if def != null else null


## Исследование, открывающее рецепт (null — доступен сразу).
static func get_recipe_research(recipe: Recipe) -> ResearchDef:
	return _recipe_research.get(recipe.id) if recipe != null else null


## Рецепт ручного крафта предмета (null — руками не делается).
static func get_hand_recipe(item: int) -> HandRecipe:
	return _recipe_by_item.get(item)


## Здания категории для меню строительства (только доступные игроку).
static func buildings_in_category(category: BuildingDef.Category, creative: bool = true) -> Array[BuildingDef]:
	var result: Array[BuildingDef] = []
	for def in buildings:
		if def.category == category and def.player_buildable and (creative or not def.creative_only):
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
		if (ore.item == null) == (ore.fluid == null):
			errors.append("месторождение %s: нужен ровно один из предмета и жидкости" % ore.id)
	for item in items:
		if item.stack_size < 1:
			errors.append("предмет %s: размер стака меньше 1" % item.id)
	for recipe in recipes:
		errors.append_array(recipe.validate())
		if recipe.hand_craftable and recipe.get_main_output() == null:
			errors.append("ручной рецепт %s без предметного выхода" % recipe.id)
	for research in researches:
		if research.cost_item == null or research.cost_amount < 1:
			errors.append("исследование %s: неверная стоимость" % research.id)
		for id in research.prerequisites:
			if get_research(id) == null:
				errors.append("исследование %s: нет предшествующего %s" % [research.id, id])
	for def in buildings:
		if def is CrafterDef:
			var crafter := def as CrafterDef
			if crafter.recipes.is_empty() or crafter.recipes.has(null):
				errors.append("завод %s без рецептов" % def.id)
		if def.size < 1 or def.size > GameConst.MAX_BUILDING_SIZE:
			errors.append("здание %s: недопустимый размер %d" % [def.id, def.size])
		for stack in def.cost:
			if stack == null or stack.item == null:
				errors.append("здание %s: пустая позиция стоимости" % def.id)
		if def.player_buildable and not def.creative_only:
			if def.item == null:
				errors.append("здание %s: нет предмета-постройки в %s" % [def.id, BUILDING_ITEMS_DIR])
			if def.cost.is_empty():
				errors.append("здание %s: нет рецепта крафта (cost)" % def.id)
	if get_floor(base_def.floor_id) == null:
		errors.append("база: нет пола %s" % base_def.floor_id)
	if planet_types.is_empty():
		errors.append("нет ни одного типа планеты в " + PLANET_TYPES_DIR)
	for t in planet_types:
		if t.ore_ids.size() != t.ore_chances.size():
			errors.append("тип планеты %s: число руд и шансов не совпадает" % t.id)
		for ore_id in t.ore_ids:
			if get_ore(ore_id) == null:
				errors.append("тип планеты %s: нет руды %s" % [t.id, ore_id])
	for t in planet_types:
		if t.safe or t.threat == null:
			if not t.safe:
				errors.append("тип планеты %s: опасная планета без кривой угрозы" % t.id)
			continue
		var threat := t.threat
		if threat.enemy_ids.is_empty():
			errors.append("угроза типа %s: нет врагов" % t.id)
		if threat.enemy_ids.size() != threat.enemy_from_wave.size() or threat.enemy_ids.size() != threat.enemy_weights.size():
			errors.append("угроза типа %s: число врагов, волн и весов не совпадает" % t.id)
		for enemy_id in threat.enemy_ids:
			if get_enemy(enemy_id) == null:
				errors.append("угроза типа %s: нет врага %s" % [t.id, enemy_id])
	for def in buildings:
		if def is TurretDef:
			var turret := def as TurretDef
			if turret.ammo.is_empty():
				errors.append("турель %s без патронов" % def.id)
			for a in turret.ammo:
				if a == null or a.item == null:
					errors.append("турель %s: патроны без предмета" % def.id)
				elif a.shots_per_item < 1 or a.shots_per_item > turret.max_ammo:
					errors.append("турель %s: выстрелов из предмета %s должно быть от 1 до запаса" % [def.id, a.item.id])
				elif a.speed <= 0.0:
					errors.append("турель %s: скорость снаряда %s должна быть больше нуля" % [def.id, a.item.id])
	for enemy in enemies:
		if enemy.health <= 0.0 or enemy.speed <= 0.0 or enemy.threat_cost <= 0.0:
			errors.append("враг %s: прочность, скорость и стоимость должны быть больше нуля" % enemy.id)
		if enemy.radius >= GameConst.TILE_SIZE * 0.5:
			errors.append("враг %s: радиус должен быть меньше половины тайла" % enemy.id)
	for stack in run_def.starting_items:
		if stack == null or stack.item == null:
			errors.append("забег: пустая позиция стартового инвентаря")
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
