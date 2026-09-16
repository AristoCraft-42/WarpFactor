class_name BuildingDef
extends Resource
## Статическое описание здания. Логика живёт в скрипте logic_script (наследник Building),
## внешний вид — в sprite (или процедурный плейсхолдер), параметры — в .tres.
## Параметры конкретных видов зданий задаются подклассами (ConveyorDef, DrillDef, StorageDef).
## Постройка ставится из инвентаря дрона: у каждой строящейся постройки есть свой ItemType
## (items/types/buildings/), а cost — рецепт её ручного крафта.

enum Category { TRANSPORT, PRODUCTION, POWER, DEFENSE }

## Глиф на процедурном плейсхолдере.
enum Glyph { NONE, CHEVRONS, CROSS, ROUTER, FILTER, GATE, BRIDGE, UNLOAD, DRILL, GEAR, PRESS, FLAME, MIXER, SPLIT, BOX, CORE, WALL, TURRET, ARTILLERY,
	PIPE, PUMP, BOILER, TURBINE, POLE, FLASK, GENERATOR, UNDERGROUND_PIPE }

@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var category: Category = Category.TRANSPORT
@export_range(1, 3) var size: int = 1
## Здание можно поворачивать (при строительстве и клавишей R по уже стоящему).
@export var rotatable: bool = true
@export var removable: bool = true
## Показывать в меню строительства и крафта (служебные здания ставятся только картой).
@export var player_buildable: bool = true
## Протягивание мышью строит цепочку с автоповоротом по трассе (ленты).
@export var line_placement: bool = false
@export var sort_order: int = 0

@export_group("Крафт")
## Ингредиенты ручного крафта постройки.
@export var cost: Array[ItemStack] = []
## Время ручного крафта одной партии, секунд.
@export var craft_time: float = 0.5
## Сколько построек даёт одна партия.
@export var craft_amount: int = 1

@export_group("Энергия")
## Потребление электричества при работе, кВт (0 — не потребитель). Без питания работает медленнее.
@export var power_use: float = 0.0

@export_group("Прочность")
## Прочность постройки (0 — по размеру: 60 × size²).
@export var health: float = 0.0
## Твёрдая постройка: враги не проходят сквозь неё, а ломают. Ленты и логистика проходимы —
## враги идут поверх, но могут бить их по дороге.
@export var solid: bool = true
## Можно ставить на месторождение жидкости (вода): трубы и насосы. Остальное на воду не ставится.
@export var allowed_on_fluid: bool = false

@export_group("Внешний вид")
@export var color: Color = Color(0.5, 0.5, 0.5)
@export var glyph: Glyph = Glyph.NONE
## Готовый спрайт размером size*32 (нарисован «вправо»). Пусто — плейсхолдер.
@export var sprite: Texture2D

@export_group("Логика")
## Скрипт логики, наследник Building. Пусто — инертное здание.
@export var logic_script: Script

var index: int = -1
## Индекс предмета-постройки (назначается реестром; -1 — здание нельзя поставить из инвентаря).
## Хранится индекс, а не ссылка: предмет уже ссылается на здание, и цикл ресурсов не освободился бы.
var item_index: int = -1
## Предмет-постройка или null.
var item: ItemType:
	get:
		return Registry.items[item_index] if item_index >= 0 else null


func get_max_health() -> float:
	return health if health > 0.0 else 60.0 * size * size


## Цена прохода тайла этой постройки для поля потоков врагов (1 — как пустая земля).
## Твёрдые постройки проходимы «с ценой»: враг обойдёт их, если обход короче, иначе сломает.
func get_path_cost() -> int:
	if not solid:
		return 1
	return mini(8 + ceili(get_max_health() / 25.0), FlowField.MAX_COST)


func create_building() -> Building:
	if logic_script != null:
		var instance: Variant = logic_script.new()
		if instance is Building:
			return instance
		push_error("BuildingDef %s: logic_script не наследует Building" % id)
	return Building.new()


func get_pixel_size() -> Vector2:
	return Vector2(size, size) * GameConst.TILE_SIZE


## Дополнительная проверка размещения, зависящая от вида здания (например, бур требует руду).
## Возвращает значение BuildingManager.Check.
func check_placement(_grid: WorldGrid, _origin: Vector2i) -> int:
	return BuildingManager.Check.OK


## Шаг при протягивании ряда (для моста — его дальность).
func get_line_step() -> int:
	return size


## Поворот, с которым постройка встанет в origin, если игрок держит поворот rotation
## (подземная труба сама разворачивается навстречу своей паре).
func placement_rotation(_world: GameWorld, _origin: Vector2i, rotation: int) -> int:
	return rotation


## Строки характеристик для подсказок меню строительства.
func get_stat_lines() -> PackedStringArray:
	return PackedStringArray()
