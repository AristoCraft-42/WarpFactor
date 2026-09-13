class_name LogisticDef
extends BuildingDef
## Параметры логистических зданий: перекрёсток, делитель, сортировщики, шлюзы, мост, разгрузчик.

## Инвертированное поведение (инвертированный сортировщик, обратный шлюз).
@export var inverted: bool = false
## Задержка передачи предмета, тиков (0 — мгновенно).
@export var transfer_ticks: int = 0
## Вместимость буфера (для перекрёстка — на каждое направление).
@export var capacity: int = 1
## Дальность связи моста, тайлов (0 — не мост).
@export var link_range: int = 0


func get_line_step() -> int:
	return link_range if link_range > 0 else size


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if link_range > 0:
		lines.append(tr("STAT_BRIDGE_RANGE") % link_range)
	if transfer_ticks > 0:
		lines.append(tr("STAT_TRANSFER_TIME") % (float(transfer_ticks) / GameConst.TICK_RATE))
	return lines
