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

## Плотный индекс; в сетке хранится index + 1 (0 — руды нет).
var index: int = -1


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
