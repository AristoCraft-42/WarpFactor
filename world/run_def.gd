class_name RunDef
extends Resource
## Параметры забега (world/run.tres): стартовый инвентарь, зарядка телепорта, звёздная карта.

## Стартовый инвентарь дрона в новом забеге.
@export var starting_items: Array[ItemStack] = []
## Время зарядки телепорта, секунд.
@export var charge_seconds: float = 30.0
## Сколько можно пробыть на планете, секунд времени мира. По истечении — аварийный телепорт:
## уцелеет только то, что на площадке и в инвентарях игроков, как при прорыве.
@export var planet_time_seconds: float = 600.0
## Сколько прибавляет каждая ступень исследования «Запас хода».
@export var planet_time_step_seconds: float = 120.0
## Перезарядка телепорта после прибытия: раньше неё улететь нельзя.
@export var teleport_cooldown_seconds: float = 300.0
## Сколько снимает с перезарядки каждая ступень исследования «Разгон телепорта».
@export var teleport_cooldown_step_seconds: float = 60.0
## Меньше этого перезарядка не опускается.
@export var teleport_cooldown_min_seconds: float = 60.0
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
