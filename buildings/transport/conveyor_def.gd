class_name ConveyorDef
extends BuildingDef
## Параметры ленты.

## Скорость движения предметов, тайлов в секунду.
@export var tiles_per_second: float = 2.4


## Пропускная способность при плотном потоке: предмет встаёт на ленту раз в ceil(зазор / шаг) тиков.
func get_items_per_second() -> float:
	var ticks_per_item := ceili(float(ConveyorSystem.SPACE) / ConveyorSystem.step_for(self))
	return float(GameConst.TICK_RATE) / ticks_per_item


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_THROUGHPUT") % get_items_per_second()])
