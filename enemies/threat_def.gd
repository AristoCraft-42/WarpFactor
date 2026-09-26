class_name ThreatDef
extends Resource
## Кривая угрозы типа планеты (enemies/threats/*.tres).
##
## После тихого начала идут волны. Каждая волна выпускает врагов равномерно за время появления,
## затем наступает затишье до следующей. Затишья сокращаются от волны к волне, время появления растёт;
## когда затишье становится короче continuous_below_seconds, волны идут встык — одна бесконечная волна.
## Бюджет волны (очки угрозы) растёт с номером волны, с временем на планете и с развитием игрока:
## развитие = завершённые исследования × производственные постройки на этой планете (считается
## в начале волны). Потерявший заводы игрок снова встречает слабые волны — развиться заново можно.

## Тихое начало до первой волны, секунд.
@export var first_wave_seconds: float = 180.0
## Затишье после первой волны, секунд.
@export var first_gap_seconds: float = 120.0
## Множитель затишья от волны к волне (меньше 1 — затишья короче).
@export_range(0.1, 1.0) var gap_multiplier: float = 0.8
## Короче этого затишья нет вовсе: волны идут встык.
@export var continuous_below_seconds: float = 10.0
## Время появления врагов первой волны и прирост за каждую следующую, секунд.
@export var spawn_seconds: float = 8.0
@export var spawn_seconds_per_wave: float = 2.5
@export var max_spawn_seconds: float = 45.0
## Предупреждение до волны, секунд.
@export var warning_seconds: float = 15.0

@export_group("Сила")
## Прочность и урон врага растут от номера волны и от глубины звёздной карты: та же порода
## с каждой волной крепче и больнее бьёт. Множитель считается при рождении и едет с врагом.
@export var health_per_wave: float = 0.05
@export var health_per_depth: float = 0.2
@export var damage_per_wave: float = 0.035
@export var damage_per_depth: float = 0.15
## Выше этих множителей сила не растёт.
@export var max_health_scale: float = 6.0
@export var max_damage_scale: float = 4.0

@export_group("Развитие")
## За каждую единицу развития (исследования × производственные постройки планеты) бюджет волны
## растёт на progress_budget очков, но не больше progress_budget_max; прочность врагов — на progress_health
## (в общий потолок max_health_scale).
@export var progress_budget: float = 0.015
@export var progress_budget_max: float = 80.0
@export var progress_health: float = 0.0002

@export_group("Бюджет")
## Очки угрозы первой волны, прирост за волну и за минуту на планете.
@export var budget_base: float = 6.0
@export var budget_per_wave: float = 4.0
@export var budget_per_minute: float = 1.5

@export_group("Враги")
## Какие враги приходят, с какой волны и с каким весом при выборе.
@export var enemy_ids: Array[StringName] = []
@export var enemy_from_wave: PackedInt32Array = PackedInt32Array()
@export var enemy_weights: PackedFloat32Array = PackedFloat32Array()
## Сколько точек появления у краёв карты.
@export_range(1, 8) var spawn_point_count: int = 3
## Предел живых врагов: сверх него появление откладывается.
@export var max_alive: int = 1500


func get_first_wave_ticks() -> int:
	return roundi(first_wave_seconds * GameConst.TICK_RATE)


func get_warning_ticks() -> int:
	return roundi(warning_seconds * GameConst.TICK_RATE)


## Затишье после волны wave (с 1), тиков; 0 — волны идут встык.
func get_gap_ticks(wave: int) -> int:
	var gap := first_gap_seconds * pow(gap_multiplier, maxi(wave - 1, 0))
	if gap < continuous_below_seconds:
		return 0
	return roundi(gap * GameConst.TICK_RATE)


## Время появления врагов волны wave (с 1), тиков.
func get_spawn_ticks(wave: int) -> int:
	var seconds := minf(spawn_seconds + spawn_seconds_per_wave * maxi(wave - 1, 0), max_spawn_seconds)
	return maxi(1, roundi(seconds * GameConst.TICK_RATE))


## Бюджет волны: номер с 1, минуты на планете к её началу.
func get_budget(wave: int, minutes: float) -> float:
	return budget_base + budget_per_wave * maxi(wave - 1, 0) + budget_per_minute * maxf(minutes, 0.0)


## Прибавка к бюджету волны от развития игрока (progress — исследования × производственные постройки).
func get_progress_budget(progress: int) -> float:
	return minf(progress_budget * maxi(progress, 0), progress_budget_max)


## Во сколько раз крепче враги волны wave на глубине depth звёздной карты при развитии progress.
func get_health_scale(wave: int, depth: int, progress: int = 0) -> float:
	return minf(1.0 + health_per_wave * maxi(wave - 1, 0) + health_per_depth * maxi(depth, 0)
		+ progress_health * maxi(progress, 0), max_health_scale)


## Во сколько раз больнее они бьют.
func get_damage_scale(wave: int, depth: int) -> float:
	return minf(1.0 + damage_per_wave * maxi(wave - 1, 0) + damage_per_depth * maxi(depth, 0), max_damage_scale)
