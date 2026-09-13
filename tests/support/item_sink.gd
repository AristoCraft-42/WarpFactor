extends Building
## Тестовый приёмник: принимает всё и считает.

var received: int = 0


func accept_item(_source: Building, _item: int) -> bool:
	return true


func handle_item(_source: Building, _item: int) -> void:
	received += 1
