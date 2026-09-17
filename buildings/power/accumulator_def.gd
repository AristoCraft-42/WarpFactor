class_name AccumulatorDef
extends BuildingDef
## Аккумулятор: запасает излишек электросети и отдаёт его при нехватке.

## Ёмкость, кДж.
@export var capacity_kj: float = 5000.0
## Наибольшая мощность заряда и разряда, кВт.
@export var max_rate: float = 300.0


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_ACCUMULATOR") % [capacity_kj / 1000.0, roundi(max_rate)]])
