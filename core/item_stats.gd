class_name ItemStats
extends RefCounted
## Скользящая статистика поступления и расхода предметов ядра (в секундах симуляции).
## Считает по посекундным корзинам, среднее — по последним WINDOW завершённым секундам.

const WINDOW := 5

var _item_count: int = 0
## [секунда][предмет]
var _income: Array[PackedInt32Array] = []
var _outcome: Array[PackedInt32Array] = []
var _cursor: int = 0
var _ticks_in_second: int = 0
## Сколько секунд уже накоплено (для корректного среднего в первые секунды уровня).
var _filled: int = 0
## Меняется каждую завершённую секунду — интерфейсу есть смысл обновиться.
var revision: int = 0


func _init(item_count: int) -> void:
	_item_count = item_count
	_income.resize(WINDOW + 1)
	_outcome.resize(WINDOW + 1)
	for i in WINDOW + 1:
		_income[i] = _zeroes()
		_outcome[i] = _zeroes()


func record_income(item: int, amount: int) -> void:
	_income[_cursor][item] += amount


func record_outcome(item: int, amount: int) -> void:
	_outcome[_cursor][item] += amount


## Вызывается симуляцией каждый тик.
func on_tick() -> void:
	_ticks_in_second += 1
	if _ticks_in_second < GameConst.TICK_RATE:
		return
	_ticks_in_second = 0
	_cursor = (_cursor + 1) % (WINDOW + 1)
	_income[_cursor] = _zeroes()
	_outcome[_cursor] = _zeroes()
	_filled = mini(_filled + 1, WINDOW)
	revision += 1


func income_per_second(item: int) -> float:
	return _average(_income, item)


func outcome_per_second(item: int) -> float:
	return _average(_outcome, item)


func _average(buckets: Array[PackedInt32Array], item: int) -> float:
	if _filled == 0:
		return 0.0
	var total := 0
	for i in range(1, _filled + 1):
		total += buckets[posmod(_cursor - i, WINDOW + 1)][item]
	return float(total) / _filled


func _zeroes() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(_item_count)
	a.fill(0)
	return a
