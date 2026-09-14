class_name LogisticDef
extends BuildingDef
## Параметры логистических зданий: перекрёсток, делитель, сортировщик, клапан, мост, разгрузчик.
## Пропускная способность привязана к ленте того же уровня (throughput_of): здание пропускает
## не больше предметов в секунду, чем эта лента при плотном потоке. Уровень 1 — обычная лента,
## уровень 2 (титановые версии) — титановая.

## Лента, чью пропускную способность имеет здание.
@export var throughput_of: ConveyorDef
## Минимальное время прохода предмета сквозь здание, тиков (перекрёсток, мост).
@export var transfer_ticks: int = 0
## Вместимость буфера (для перекрёстка — на каждое направление).
@export var capacity: int = 1
## Дальность связи моста, тайлов (0 — не мост).
@export var link_range: int = 0


## Сколько тиков минимум между двумя предметами, прошедшими через здание.
func get_ticks_per_item() -> int:
	return throughput_of.get_ticks_per_item() if throughput_of != null else 1


func get_items_per_second() -> float:
	return float(GameConst.TICK_RATE) / get_ticks_per_item()


func get_line_step() -> int:
	return link_range if link_range > 0 else size


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray([tr("STAT_THROUGHPUT") % get_items_per_second()])
	if link_range > 0:
		lines.append(tr("STAT_BRIDGE_RANGE") % link_range)
	return lines
