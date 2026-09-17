class_name BaseDef
extends Resource
## Параметры подземного этажа мобильной базы (world/base.tres): размеры и пол.
## Этаж открывается исследованием «Подземный этаж» размером start_size и расширяется исследованиями
## «Расширение подземного этажа» на size_step. Карта мира сразу наибольшего размера (size), за краем
## открытой части — пустота (void_floor_id), на ней не строят. Пара центрального шлюза — в центре.

@export var id: StringName = &"base"
@export var title_key: String = "LOCATION_BASE"
## Сторона карты этажа (наибольший размер после всех расширений), тайлов.
@export var size: int = 46
## Сторона открытой части сразу после открытия этажа и прирост за шаг расширения.
@export var start_size: int = 16
@export var size_step: int = 6
@export var floor_id: StringName = &"metal_plates"
@export var void_floor_id: StringName = &"void"
