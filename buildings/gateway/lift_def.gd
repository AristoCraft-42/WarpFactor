class_name LiftDef
extends BuildingDef
## Лифт между площадкой шлюза и подземным этажом.

## Сколько предметов ждёт перехода.
@export var buffer_capacity: int = 10
## Скорость выдачи — как у этой ленты.
@export var throughput_of: ConveyorDef
## Шахта котельной проводит ещё ток и жидкости: этаж-электростанция иначе некуда девать.
@export var energy_link: bool = false


func get_ticks_per_item() -> int:
	return throughput_of.get_ticks_per_item() if throughput_of != null else 1


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_THROUGHPUT") % (float(GameConst.TICK_RATE) / get_ticks_per_item())])
