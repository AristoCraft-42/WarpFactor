class_name TurretAmmo
extends Resource
## Вид патронов турели: какой предмет, сколько выстрелов даёт, урон и снаряд.
## Патроны — обычные предметы: приходят лентой или кладутся руками в окне турели.

@export var item: ItemType
## Выстрелов из одного предмета.
@export var shots_per_item: int = 2
## Урон прямого попадания (пуля) или взрыва (снаряд артиллерии).
@export var damage: float = 9.0
## Радиус взрыва, тайлов (0 — без урона по площади).
@export var splash_radius: float = 0.0
## Скорость снаряда, тайлов в секунду.
@export var speed: float = 14.0
## Множитель паузы между выстрелами (меньше 1 — стреляет чаще).
@export var reload_multiplier: float = 1.0
@export var color: Color = Color(0.98, 0.74, 0.18)


func get_speed_per_tick() -> float:
	return speed * GameConst.TILE_SIZE / GameConst.TICK_RATE


func get_splash_px() -> float:
	return splash_radius * GameConst.TILE_SIZE
