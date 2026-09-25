class_name OreDef
extends Resource
## Месторождение (верхний слой карты). Бур или дрон добывает с него предмет item;
## месторождение жидкости (fluid, например вода) — только насосом.

@export var id: StringName
## Название залежи; если пусто — используется название предмета.
@export var name_key: String
@export var item: ItemType
## Жидкость месторождения (тогда item пуст).
@export var fluid: FluidDef
## Твёрдость: влияет на скорость добычи и требуемый уровень бура (этап 2).
@export_range(0, 5) var hardness: int = 1
@export var sort_order: int = 0
## Готовая текстура 32x32 с прозрачностью. Пусто — плейсхолдер цвета предмета.
@export var texture: Texture2D

## Богатство клетки руды (отдельный слой карты). Порядок значений выбран так, чтобы ноль —
## значение по умолчанию у старых сохранений и готовых уровней — был обычной, средней клеткой.
enum Richness { MEDIUM, POOR, RICH, ULTRA }
## Во сколько раз клетка даёт больше руды в секунду, чем средняя (по значению Richness).
const RICHNESS_YIELD: PackedFloat32Array = [1.0, 0.5, 1.6, 2.5]
## Названия богатства по значению Richness.
const RICHNESS_KEYS: PackedStringArray = ["ORE_RICHNESS_MEDIUM", "ORE_RICHNESS_POOR", "ORE_RICHNESS_RICH", "ORE_RICHNESS_ULTRA"]

## Плотный индекс; в сетке хранится index + 1 (0 — руды нет).
var index: int = -1


## Множитель выхода клетки с богатством richness (неизвестное значение — как средняя).
static func yield_of(richness: int) -> float:
	return RICHNESS_YIELD[richness] if richness >= 0 and richness < RICHNESS_YIELD.size() else 1.0


func get_name_key() -> String:
	if not name_key.is_empty():
		return name_key
	if item != null:
		return item.name_key
	return fluid.name_key if fluid != null else String(id)


func get_color() -> Color:
	if item != null:
		return item.color
	return fluid.color if fluid != null else Color.MAGENTA
