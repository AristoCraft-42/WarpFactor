class_name ScienceWorkshopDef
extends BuildingDef
## Параметры научного цеха: время на набор при полном питании и сколько наборов держит.

@export var seconds_per_kit: float = 2.0
@export var kit_capacity: int = 10


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_WORKSHOP") % seconds_per_kit, tr("STAT_POWER_USE") % roundi(power_use)])
