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

var _simulation: Simulation
var _accumulator: float = 0.0


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	process_priority = -100


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
	if _simulation == null or not is_running():
		return
	_accumulator += minf(delta, MAX_FRAME_DELTA) * get_speed()
	while _accumulator >= GameConst.TICK_DT and ticks_last_frame < MAX_TICKS_PER_FRAME:
		_simulation.step()
		_accumulator -= GameConst.TICK_DT
		ticks_last_frame += 1
	if ticks_last_frame >= MAX_TICKS_PER_FRAME:
		_accumulator = minf(_accumulator, GameConst.TICK_DT)
	alpha = clampf(_accumulator / GameConst.TICK_DT, 0.0, 1.0)
