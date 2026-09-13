extends Building
## Тестовый источник: каждый тик пытается отдать предмет соседям. Если некуда — ждёт освобождения места.

var item: int = 0
var produced: int = 0


func on_placed() -> void:
	wake()


func update_tick(_tick: int) -> bool:
	if dump(item):
		produced += 1
		return true
	wait_for_proximity()
	return false
