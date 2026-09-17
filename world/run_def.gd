class_name RunDef
extends Resource
## Параметры забега (world/run.tres): стартовый инвентарь, зарядка телепорта, звёздная карта.

## Стартовый инвентарь дрона в новом забеге.
@export var starting_items: Array[ItemStack] = []
## Время зарядки телепорта, секунд.
@export var charge_seconds: float = 30.0
## Тип первой планеты забега.
@export var first_planet_type: PlanetTypeDef
## На сколько шагов вперёд видна звёздная карта (позже — открывается исследованиями).
@export var visible_depth: int = 3
## Сторона площадки шлюза на планете в начале и прирост за каждое исследование «Расширение площадки», тайлов.
@export var pad_start_size: int = 20
@export var pad_size_step: int = 4
## Сколько планет в каждом шаге звёздной карты.
@export var min_nodes_per_step: int = 2
@export var max_nodes_per_step: int = 3


func get_charge_ticks() -> int:
	return maxi(1, roundi(charge_seconds * GameConst.TICK_RATE))
