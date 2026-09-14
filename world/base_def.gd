class_name BaseDef
extends Resource
## Параметры мобильной базы (world/base.tres): размер пространства и пол.
## Пара центрального шлюза ставится в центр базы.

@export var id: StringName = &"base"
@export var title_key: String = "LOCATION_BASE"
## Сторона квадратного пространства базы, тайлов.
@export var size: int = 24
@export var floor_id: StringName = &"metal_plates"
