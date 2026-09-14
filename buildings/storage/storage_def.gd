class_name StorageDef
extends BuildingDef
## Параметры склада (контейнер, хранилище).

## Число ячеек; в ячейке лежит один тип предмета до размера его стака.
@export var slots: int = 16


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_SLOTS") % slots])
