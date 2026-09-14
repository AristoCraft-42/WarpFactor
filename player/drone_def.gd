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

@export_group("Внешний вид")
@export var color: Color = Color(0.98, 0.74, 0.18)
## Готовый спрайт (нарисован «вправо»). Пусто — плейсхолдер.
@export var sprite: Texture2D


func get_reach_px() -> float:
	return reach * GameConst.TILE_SIZE


## Скорость, пикселей за тик симуляции.
func get_speed_per_tick() -> float:
	return speed * GameConst.TILE_SIZE / GameConst.TICK_RATE


func get_respawn_ticks() -> int:
	return maxi(1, roundi(respawn_seconds * GameConst.TICK_RATE))


func get_invulnerable_ticks() -> int:
	return roundi(invulnerable_seconds * GameConst.TICK_RATE)


func mine_ticks(ore: OreDef) -> int:
	return maxi(1, roundi((mine_base_seconds + mine_hardness_seconds * ore.hardness) * GameConst.TICK_RATE))
