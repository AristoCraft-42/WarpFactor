class_name LevelDef
extends Resource
## Описание уровня. Карта (тайлы и предустановленные здания) лежит в бинарном файле map_path.
## На этапе «База и планета» уровень превратится в описание планеты.

@export var id: StringName
@export var title_key: String
@export_multiline var description_key: String
## Порядок в списке.
@export var order: int = 0
@export_file("*.fwmap") var map_path: String
## Тайл, где появляется дрон. (-1, -1) — центр карты.
@export var spawn: Vector2i = Vector2i(-1, -1)
## Стартовый инвентарь дрона: ресурсы и готовые постройки.
@export var starting_items: Array[ItemStack] = []
