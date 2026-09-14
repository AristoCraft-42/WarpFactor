class_name PlanetTypeDef
extends Resource
## Тип планеты (world/planet_types/*.tres): размер, рельеф, какие руды встречаются, безопасна ли.
## Генератор (PlanetGenerator) строит карту по типу и сиду узла звёздной карты.

@export var id: StringName
@export var name_key: String
@export_multiline var description_key: String
## На безопасной планете враг не нападает.
@export var safe: bool = false
## Кривая угрозы (волны врагов). У безопасной планеты не используется.
@export var threat: ThreatDef
## Шанс, что узел звёздной карты (кроме первого) будет этого типа — вес при выборе.
@export var weight: float = 1.0
@export var min_size: Vector2i = Vector2i(112, 84)
@export var max_size: Vector2i = Vector2i(160, 120)

@export_group("Рельеф")
@export var base_floor: StringName = &"stone"
## Пятна другого пола поверх основного.
@export var patch_floors: Array[StringName] = []
## Доля карты под скалами (0..1).
@export_range(0.0, 0.6) var rock_density: float = 0.18

@export_group("Руды")
## Руды, которые могут встретиться, и шанс каждой (0..1). Пустой список — руды нет вовсе.
@export var ore_ids: Array[StringName] = []
@export var ore_chances: PackedFloat32Array = PackedFloat32Array()
## Сколько залежей каждой руды на 10 000 тайлов карты.
@export var deposits_per_10k: float = 3.0

@export_group("Внешний вид")
## Цвет узла на звёздной карте.
@export var map_color: Color = Color(0.51, 0.65, 0.6)
