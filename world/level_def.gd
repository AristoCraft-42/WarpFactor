class_name LevelDef
extends Resource
## Описание уровня кампании. Карта (тайлы и предустановленные здания) лежит в бинарном файле map_path.
## На следующих этапах сюда добавятся разблокировки, контракты и цели.

@export var id: StringName
@export var title_key: String
@export_multiline var description_key: String
## Порядок в кампании.
@export var order: int = 0
@export_file("*.fwmap") var map_path: String
## Стартовый запас ядра (не засчитывается как доставка).
@export var starting_items: Array[ItemStack] = []
