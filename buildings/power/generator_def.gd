class_name GeneratorDef
extends BuildingDef
## Генератор: термогенератор жжёт топливо (предметы с fuel_value), паровой — берёт пар из труб.

enum Kind { FUEL, STEAM }

@export var kind: Kind = Kind.FUEL
## Наибольшая мощность, кВт.
@export var max_output: float = 150.0
## КПД сжигания топлива (доля энергии топлива, ставшая электричеством).
@export var efficiency: float = 0.5
## Сколько предметов топлива держит.
@export var fuel_capacity: int = 10
## Энергия единицы пара, кДж (паровой генератор).
@export var steam_energy: float = 16.67
@export var steam_fluid: FluidDef


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray([tr("STAT_POWER_OUTPUT") % roundi(max_output)])
	if kind == Kind.STEAM and steam_energy > 0.0:
		lines.append(tr("STAT_STEAM_USE") % (max_output / steam_energy))
	else:
		lines.append(tr("STAT_FUEL_EFFICIENCY") % roundi(efficiency * 100.0))
	return lines
