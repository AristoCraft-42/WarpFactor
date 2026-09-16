class_name DrillDef
extends BuildingDef
## Параметры бура. Время на предмет = (base_seconds + hardness_seconds * твёрдость) / число тайлов руды.

## Максимальная твёрдость руды, которую может добывать бур.
@export_range(0, 5) var tier: int = 2
@export var base_seconds: float = 8.0
@export var hardness_seconds: float = 2.0
## Сколько добытых предметов бур держит, если их некуда отдать.
@export var item_capacity: int = 10


func seconds_per_item(ore: OreDef, tiles: int) -> float:
	return (base_seconds + hardness_seconds * ore.hardness) / maxi(tiles, 1)


## Самая частая доступная руда под буром: Vector2i(значение слоя руды, число тайлов).
## Значение 0 — подходящей руды нет. При равенстве выигрывает более мягкая руда.
func find_ore(grid: WorldGrid, origin: Vector2i) -> Vector2i:
	var counts := {}
	for y in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			if not grid.in_bounds(x, y):
				continue
			var value := grid.get_ore(x, y)
			if value == 0 or Registry.ores[value - 1].item == null or Registry.ores[value - 1].hardness > tier:
				continue
			counts[value] = int(counts.get(value, 0)) + 1
	var best := Vector2i.ZERO
	for value in counts:
		var n: int = counts[value]
		if n > best.y or (n == best.y and Registry.ores[value - 1].hardness < Registry.ores[best.x - 1].hardness):
			best = Vector2i(value, n)
	return best


func check_placement(grid: WorldGrid, origin: Vector2i) -> int:
	return BuildingManager.Check.OK if find_ore(grid, origin).x != 0 else BuildingManager.Check.NO_ORE


func get_stat_lines() -> PackedStringArray:
	var names := PackedStringArray()
	for ore in Registry.ores:
		if ore.item != null and ore.hardness <= tier:
			names.append(tr(ore.item.name_key))
	var lines := PackedStringArray([
		tr("STAT_DRILL_TIER") % [tier, ", ".join(names)],
		tr("STAT_DRILL_SPEED") % (float(size * size) / (base_seconds + hardness_seconds)),
	])
	if power_use > 0.0:
		lines.append(tr("STAT_POWER_USE") % roundi(power_use))
	return lines
