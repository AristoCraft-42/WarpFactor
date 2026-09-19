class_name CreativeBlockDef
extends BuildingDef
## Творческий блок: бесконечный источник предметов, энергии или жидкости и поглотитель всего сразу.
## Строится только в творческом режиме (BuildingManager проверяет creative_only).

enum Kind {
	ITEM,   ## выдаёт выбранный предмет, шт./с
	POWER,  ## даёт энергию в сеть, кВт
	FLUID,  ## наливает выбранную жидкость, ед./с
	VOID,   ## принимает и уничтожает предметы, жидкость и энергию
}

@export var kind: Kind = Kind.ITEM
## Ступени регулировки (единицы зависят от вида блока). Настройка хранит номер ступени.
@export var rates: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0])
## Ступень по умолчанию.
@export var default_rate: int = 3


func get_rate(index: int) -> float:
	if rates.is_empty():
		return 0.0
	return rates[clampi(index, 0, rates.size() - 1)]


func get_stat_lines() -> PackedStringArray:
	var key := "STAT_CREATIVE_ITEM"
	match kind:
		Kind.POWER:
			key = "STAT_CREATIVE_POWER"
		Kind.FLUID:
			key = "STAT_CREATIVE_FLUID"
		Kind.VOID:
			key = "STAT_CREATIVE_VOID"
	return PackedStringArray([tr(key) % get_rate(default_rate), tr("STAT_CREATIVE_ONLY")])
