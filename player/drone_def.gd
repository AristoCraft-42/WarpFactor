class_name DroneDef
extends Resource
## Параметры дрона игрока (player/drone.tres).

@export var id: StringName = &"drone"
@export var name_key: String = "DRONE_NAME"
## Скорость полёта, тайлов в секунду.
@export var speed: float = 8.0
## Радиус строительства и взаимодействия, тайлов (от центра дрона до ближайшей точки здания).
@export var reach: float = 10.0
@export var inventory_slots: int = 40
## Максимальная твёрдость руды, которую дрон может добывать.
@export_range(0, 5) var mine_tier: int = 2
## Время добычи одного предмета: mine_base_seconds + mine_hardness_seconds × твёрдость руды.
@export var mine_base_seconds: float = 3.0
@export var mine_hardness_seconds: float = 1.0
## Множитель скорости ручного крафта.
@export var craft_speed: float = 1.0

@export_group("Выживание")
@export var health: float = 150.0
## Радиус тела для попаданий врагов, пикселей.
@export var hit_radius: float = 12.0
## Через сколько секунд сбитый дрон появляется у центрального шлюза.
@export var respawn_seconds: float = 6.0
## Неуязвимость после появления, секунд (успеть уйти через шлюз).
@export var invulnerable_seconds: float = 3.0
## С какого расстояния дрон подбирает выпавший груз, тайлов.
@export var pickup_radius: float = 1.5

@export_group("Автопушка и ремонт")
## Урон пули автопушки (0 — пушки нет), пауза между выстрелами, дальность и скорость пули.
@export var gun_damage: float = 6.0
@export var gun_reload_seconds: float = 0.35
@export var gun_range: float = 6.5
@export var gun_bullet_speed: float = 16.0
@export var gun_color: Color = Color(0.56, 0.75, 0.49)
## Сколько прочности в секунду дрон чинит постройке в радиусе (бесплатно).
@export var repair_per_second: float = 40.0

@export_group("Улучшения")
## Сколько добавляет одна ступень исследования: скорость (тайлов/с), множитель скорости добычи,
## прочность, урон автопушки и ремонт в секунду.
@export var speed_step: float = 1.0
@export var mine_speed_step: float = 0.25
@export var health_step: float = 50.0
@export var gun_damage_step: float = 3.0
@export var repair_step: float = 20.0

@export_group("Внешний вид")
@export var color: Color = Color(0.98, 0.74, 0.18)
## Готовый спрайт (нарисован «вправо»). Пусто — плейсхолдер.
@export var sprite: Texture2D


func get_reach_px() -> float:
	return reach * GameConst.TILE_SIZE


## Скорость, пикселей за тик симуляции.
func get_speed_per_tick() -> float:
	return speed * GameConst.TILE_SIZE / GameConst.TICK_RATE


func get_gun_ticks() -> int:
	return maxi(1, roundi(gun_reload_seconds * GameConst.TICK_RATE))


func get_gun_range_px() -> float:
	return gun_range * GameConst.TILE_SIZE


func get_gun_speed_per_tick() -> float:
	return gun_bullet_speed * GameConst.TILE_SIZE / GameConst.TICK_RATE


func get_respawn_ticks() -> int:
	return maxi(1, roundi(respawn_seconds * GameConst.TICK_RATE))


func get_invulnerable_ticks() -> int:
	return roundi(invulnerable_seconds * GameConst.TICK_RATE)


func mine_ticks(ore: OreDef) -> int:
	return maxi(1, roundi((mine_base_seconds + mine_hardness_seconds * ore.hardness) * GameConst.TICK_RATE))
