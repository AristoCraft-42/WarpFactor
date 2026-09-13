class_name BuildingDef
extends Resource
## Статическое описание здания. Логика живёт в скрипте logic_script (наследник Building),
## внешний вид — в sprite (или процедурный плейсхолдер), параметры — в .tres.
## Параметры конкретных видов зданий задаются подклассами (ConveyorDef, DrillDef, StorageDef).

enum Category { EXTRACTION, TRANSPORT, PRODUCTION, STORAGE }

## Глиф на процедурном плейсхолдере.
enum Glyph { NONE, CHEVRONS, CROSS, ROUTER, FILTER, GATE, BRIDGE, UNLOAD, DRILL, GEAR, PRESS, FLAME, MIXER, SPLIT, BOX, CORE }

@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var category: Category = Category.TRANSPORT
@export_range(1, 3) var size: int = 1
## Здание можно поворачивать (при строительстве и клавишей R по уже стоящему).
@export var rotatable: bool = true
@export var removable: bool = true
## Показывать в меню строительства (ядро ставится только уровнем).
@export var player_buildable: bool = true
## Протягивание мышью строит цепочку с автоповоротом по трассе (ленты).
@export var line_placement: bool = false
@export var sort_order: int = 0
## Стоимость строительства: списывается из ядра, при сносе возвращается.
@export var cost: Array[ItemStack] = []

@export_group("Внешний вид")
@export var color: Color = Color(0.5, 0.5, 0.5)
@export var glyph: Glyph = Glyph.NONE
## Готовый спрайт размером size*32 (нарисован «вправо»). Пусто — плейсхолдер.
@export var sprite: Texture2D

@export_group("Логика")
## Скрипт логики, наследник Building. Пусто — инертное здание.
@export var logic_script: Script

var index: int = -1


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


## Строки характеристик для подсказок меню строительства.
func get_stat_lines() -> PackedStringArray:
	return PackedStringArray()
