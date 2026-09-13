class_name StorageDef
extends BuildingDef
## Параметры хранилища (ядро, контейнер, склад).

## Лимит по каждому предмету.
@export var item_capacity: int = 300


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_CAPACITY") % item_capacity])
