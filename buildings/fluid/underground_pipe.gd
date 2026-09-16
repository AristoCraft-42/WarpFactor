class_name UndergroundPipe
extends Pipe
## Подземная труба (как в Factorio): поворот — направление подземного участка. Сверху труба соединяется
## только с противоположной стороны; под землёй — с ближайшей подземной трубой по направлению, смотрящей
## навстречу, не дальше underground_range. Пара действует, только если обе трубы нашли друг друга.
## Между входом и выходом можно строить что угодно.


func get_range() -> int:
	return (def as FluidBuildingDef).underground_range


## Открытая сторона — противоположная подземному участку.
func connects_side(side: int) -> bool:
	return side == (rotation + 2) % 4


func on_rotated(_old_rotation: int) -> void:
	world.fluids.mark_dirty()


## Ближайшая по направлению поворота подземная труба, смотрящая навстречу (null — нет в пределах дальности).
func find_partner() -> UndergroundPipe:
	if world == null:
		return null
	var step := GameConst.dir_vector(rotation)
	var facing := (rotation + 2) % 4
	for i in range(1, get_range() + 1):
		var other := world.buildings.get_at(origin + step * i) as UndergroundPipe
		if other != null and other.rotation == facing:
			return other
	return null


## Пара, найденная с обеих сторон.
func get_linked_partner() -> UndergroundPipe:
	var partner := find_partner()
	return partner if partner != null and partner.find_partner() == self else null


func get_info_lines() -> PackedStringArray:
	var lines := super()
	var partner := get_linked_partner()
	if partner != null:
		lines.append(tr("INFO_UNDERGROUND_LINKED") % maxi(absi(partner.origin.x - origin.x), absi(partner.origin.y - origin.y)))
	else:
		lines.append(tr("INFO_UNDERGROUND_UNLINKED") % get_range())
	return lines
