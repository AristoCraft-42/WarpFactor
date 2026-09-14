class_name TeleportSummary
extends RefCounted
## Итог пребывания на планете после телепорта: что ушло в базу, что переехало с площадкой, что потеряно.

var from_title: String = ""
var to_title: String = ""
var to_safe: bool = false
var seconds_on_planet: float = 0.0
## Предметы, отправленные через шлюз в базу (по индексу предмета).
var sent_to_base := PackedInt32Array()
## Постройки площадки, переехавшие на новую планету.
var buildings_moved: int = 0
## Постройки вне площадки, оставшиеся на старой планете.
var buildings_lost: int = 0
## Содержимое потерянных построек (по индексу предмета).
var items_lost := PackedInt32Array()


func _init() -> void:
	items_lost.resize(Registry.items.size())
	items_lost.fill(0)


static func total(counts: PackedInt32Array) -> int:
	var sum := 0
	for c in counts:
		sum += c
	return sum
