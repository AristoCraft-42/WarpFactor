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
## Полы областей поверх основного: крупный шум делит карту на зоны и выбирает из этого списка.
@export var patch_floors: Array[StringName] = []
## Какую долю карты занимает основной пол (остальное — области из patch_floors).
@export_range(0.2, 0.95) var base_floor_share: float = 0.55
## Частота шума областей: чем меньше, тем крупнее зоны.
@export var region_frequency: float = 0.004
## Доля карты под скалами (0..1).
@export_range(0.0, 0.6) var rock_density: float = 0.18
## Частота шума гряд: чем меньше, тем длиннее и ровнее хребты.
@export var ridge_frequency: float = 0.01
## Насколько гряды рваные: 0 — сплошные хребты, 1 — цепочки обломков с рваным краем.
@export_range(0.0, 1.5) var ridge_breakup: float = 0.6
## Разброс характера планет этого типа: каждая планета берёт свои частоты шума, долю скал,
## число озёр и густоту руды в пределах ±character_spread от значений типа.
@export_range(0.0, 0.8) var character_spread: float = 0.3

@export_group("Озёра")
## Сколько озёр на 10 000 тайлов карты (0 — озёр нет) и их размеры, тайлов.
## Озеро появляется, только если этому узлу выпала вода среди руд.
@export var lakes_per_10k: float = 0.35
@export var lake_min_radius: float = 6.0
@export var lake_max_radius: float = 12.0
## Пол полосы берега вокруг озера.
@export var shore_floor: StringName = &"gravel"

@export_group("Руды")
## Руды, которые могут встретиться, и шанс каждой (0..1). Пустой список — руды нет вовсе.
@export var ore_ids: Array[StringName] = []
@export var ore_chances: PackedFloat32Array = PackedFloat32Array()
## Сколько залежей каждой руды на 10 000 тайлов карты.
@export var deposits_per_10k: float = 3.0
## По сколько залежей в одном рудном поле: поле — это «своя сторона карты» для руды.
@export var ore_cluster_size: int = 3

@export_group("Внешний вид")
## Цвет узла на звёздной карте.
@export var map_color: Color = Color(0.51, 0.65, 0.6)
