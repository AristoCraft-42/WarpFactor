class_name EnemyDef
extends Resource
## Тип наземного врага (enemies/defs/*.tres). Враги идут к центральному шлюзу по полю потоков,
## по дороге бьют постройки и дрона в радиусе атаки, ломают постройки, перегородившие путь.
## Атака мгновенная (без снарядов): урон раз в attack_interval секунд.

## Глиф процедурного плейсхолдера.
enum Shape { BUG, SOLDIER, BRUTE }

@export var id: StringName
@export var name_key: String
@export var sort_order: int = 0

@export_group("Характеристики")
@export var health: float = 100.0
## Скорость, тайлов в секунду.
@export var speed: float = 2.0
## Радиус тела, пикселей (столкновения и дальность до цели считаются от края тела).
@export var radius: float = 8.0
@export var damage: float = 10.0
## Пауза между атаками, секунд.
@export var attack_interval: float = 1.0
## Дальность атаки от края тела до цели, тайлов (ближний бой — доли тайла).
@export var attack_range: float = 0.15
## Стоимость в очках угрозы: из бюджета волны набираются враги.
@export var threat_cost: float = 1.0

@export_group("Внешний вид")
@export var color: Color = Color(0.8, 0.3, 0.25)
@export var shape: Shape = Shape.BUG
## Размер спрайта на экране, пикселей.
@export var draw_size: float = 24.0
## Готовый спрайт (нарисован «вправо»). Пусто — плейсхолдер.
@export var sprite: Texture2D

var index: int = -1


func get_speed_per_tick() -> float:
	return speed * GameConst.TILE_SIZE / GameConst.TICK_RATE


func get_attack_ticks() -> int:
	return maxi(1, roundi(attack_interval * GameConst.TICK_RATE))


func get_range_px() -> float:
	return attack_range * GameConst.TILE_SIZE
