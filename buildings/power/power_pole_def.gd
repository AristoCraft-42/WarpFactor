class_name PowerPoleDef
extends BuildingDef
## Опора ЛЭП: радиус проводов до других опор, зона питания и число связей.

## Дальность провода до другой опоры, тайлов (между центрами).
@export var wire_range: float = 7.5
## Сторона квадратной зоны питания, тайлов (центр — опора).
@export var supply_size: int = 5
@export var max_links: int = 5


## Протягивание ставит опоры на наибольшем расстоянии, при котором провод ещё достаёт.
func get_line_step() -> int:
	return maxi(size, floori(wire_range))


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_POLE_WIRE") % wire_range, tr("STAT_POLE_SUPPLY") % [supply_size, supply_size]])
