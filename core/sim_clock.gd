class_name SimClock
extends Node
## Часы симуляции: превращают время кадра в фиксированные логические тики.
## Логика никогда не видит delta кадра — только тики длиной GameConst.TICK_DT.
## Ускорение x2/x4 — это больше тиков той же длины, поэтому поведение не зависит от скорости.
## Если процессор не успевает, лишние тики отбрасываются: игра замедляется, но не зависает.

signal state_changed

const SPEEDS: Array[int] = [1, 2, 4]
const MAX_TICKS_PER_FRAME := 8
## Максимальный учитываемый кадр (после долгой загрузки или сворачивания окна).
const MAX_FRAME_DELTA := 0.25

## Доля времени до следующего тика — для интерполяции отрисовки (0..1).
var alpha: float = 0.0
var speed_index: int = 0
## Пауза игроком.
var paused: bool = false
## Пауза меню (не меняет выбор игрока).
var blocked: bool = false
var ticks_last_frame: int = 0

## Один логический шаг (тик забега: обе симуляции).
var _step: Callable
## Можно ли сейчас считать тик: в сетевой игре клиент ждёт команды хоста.
## Пусто — считаем всегда (одиночная игра).
var _can_step: Callable
## Во сколько раз быстрее идёт время. Клиент сетевой игры так подстраивается под темп хоста:
## чуть быстрее, когда отстал, чуть медленнее, когда подобрался вплотную. Пусто — ровно 1.0.
var _scale: Callable
var _accumulator: float = 0.0


func setup(step: Callable, can_step: Callable = Callable(), scale: Callable = Callable()) -> void:
	_step = step
	_can_step = can_step
	_scale = scale
	process_priority = -100


## Текущий множитель хода времени (для отладки и тестов).
func get_time_scale() -> float:
	return float(_scale.call()) if _scale.is_valid() else 1.0


func get_speed() -> int:
	return SPEEDS[speed_index]


func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	paused = false
	state_changed.emit()


func toggle_pause() -> void:
	paused = not paused
	state_changed.emit()


func is_running() -> bool:
	return not paused and not blocked


func _process(delta: float) -> void:
	ticks_last_frame = 0
	if not _step.is_valid() or not is_running():
		return
	_accumulator += minf(delta, MAX_FRAME_DELTA) * get_speed() * get_time_scale()
	var waiting := false
	while _accumulator >= GameConst.TICK_DT and ticks_last_frame < MAX_TICKS_PER_FRAME:
		if _can_step.is_valid() and not _can_step.call():
			waiting = true
			break
		_step.call()
		_accumulator -= GameConst.TICK_DT
		ticks_last_frame += 1
	if waiting:
		# Ждём команды хоста. Накопленное время не выбрасываем — иначе отставание только растёт
		# и уже не отыгрывается; но и копить бесконечно нельзя, иначе после задержки игра рванёт.
		_accumulator = minf(_accumulator, GameConst.TICK_DT * float(MAX_TICKS_PER_FRAME))
	elif ticks_last_frame >= MAX_TICKS_PER_FRAME:
		_accumulator = minf(_accumulator, GameConst.TICK_DT)
	alpha = clampf(_accumulator / GameConst.TICK_DT, 0.0, 1.0)
