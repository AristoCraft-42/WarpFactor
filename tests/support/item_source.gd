extends Building
## Тестовый источник: каждый тик пытается отдать предмет соседям (по очереди из items).
## Если отдать некуда — ждёт освобождения места.

var items := PackedInt32Array([0])
var produced: int = 0
## Ограничение количества (-1 — бесконечно).
var limit: int = -1

var _cursor: int = 0


func on_placed() -> void:
	wake()


func update_tick(_tick: int) -> bool:
	if limit >= 0 and produced >= limit:
		return false
	var item := items[_cursor % items.size()]
	if dump(item):
		produced += 1
		_cursor += 1
		return true
	wait_for_proximity()
	return false
