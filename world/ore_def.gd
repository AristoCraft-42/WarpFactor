class_name OreDef
extends Resource
## Залежь руды (верхний слой карты). Бур добывает с неё предмет item.

@export var id: StringName
## Название залежи; если пусто — используется название предмета.
@export var name_key: String
@export var item: ItemType
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
	return item.name_key if item != null else String(id)


func get_color() -> Color:
	return item.color if item != null else Color.MAGENTA
