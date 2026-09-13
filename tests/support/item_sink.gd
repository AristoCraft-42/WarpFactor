extends Building
## Тестовый приёмник: принимает всё и считает (всего и по типам предметов).

var received: int = 0
var by_item: Dictionary = {}


func accept_item(_source: Building, _item: int) -> bool:
	return true


func handle_item(_source: Building, item: int) -> void:
	received += 1
	by_item[item] = int(by_item.get(item, 0)) + 1


func count_of(item: int) -> int:
	return int(by_item.get(item, 0))
