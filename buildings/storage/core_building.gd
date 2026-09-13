class_name CoreBuilding
extends Building
## Ядро: принимает любые предметы со всех сторон в глобальный склад уровня.
## Не блокирует ленты: излишек сверх лимита сгорает, но засчитывается как доставка.


func accept_item(_source: Building, _item: int) -> bool:
	return true


func handle_item(_source: Building, item: int) -> void:
	world.core_storage.deliver(item, 1)


func get_info_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_CAPACITY") % world.core_storage.capacity])
