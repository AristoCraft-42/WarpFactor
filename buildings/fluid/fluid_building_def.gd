class_name FluidBuildingDef
extends BuildingDef
## Параметры построек с жидкостями: трубы, насоса, бойлера.
## Насос: сколько жидкости в секунду даёт тайл месторождения под ним.
## Бойлер: мощность сжигания топлива, сколько пара в секунду даёт на полной мощности, запас топлива.

enum Role { PIPE, PUMP, BOILER }

@export var role: Role = Role.PIPE
@export var fluid_capacity: float = 100.0
@export_group("Насос")
@export var pump_per_tile: float = 120.0
@export_group("Бойлер")
@export var fuel_power: float = 1000.0
@export var steam_per_second: float = 60.0
@export var fuel_capacity: int = 10
@export var water_fluid: FluidDef
@export var steam_fluid: FluidDef


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if role == Role.PUMP:
		lines.append(tr("STAT_PUMP_RATE") % pump_per_tile)
	elif role == Role.BOILER:
		lines.append(tr("STAT_BOILER") % [roundi(fuel_power), steam_per_second])
	else:
		lines.append(tr("STAT_PIPE_CAPACITY") % roundi(fluid_capacity))
	return lines


## Насос ставится только на месторождение жидкости.
func check_placement(grid: WorldGrid, origin: Vector2i) -> int:
	if role != Role.PUMP:
		return BuildingManager.Check.OK
	return BuildingManager.Check.OK if count_fluid_tiles(grid, origin) > 0 else BuildingManager.Check.NO_ORE


## Число тайлов месторождения жидкости под постройкой.
func count_fluid_tiles(grid: WorldGrid, origin: Vector2i) -> int:
	var n := 0
	for y in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			if grid.in_bounds(x, y):
				var ore := grid.get_ore_def(x, y)
				if ore != null and ore.fluid != null:
					n += 1
	return n
