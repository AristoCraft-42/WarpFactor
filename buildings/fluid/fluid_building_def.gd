class_name FluidBuildingDef
extends BuildingDef
## Параметры построек с жидкостями: трубы, подземной трубы, насоса, бойлера.
## Подземная труба: вход и выход соединяются под землёй на расстоянии до underground_range тайлов.
## Насос: сколько жидкости в секунду даёт тайл месторождения под ним.
## Бойлер: мощность сжигания топлива, сколько пара в секунду даёт на полной мощности, запас топлива.

enum Role { PIPE, PUMP, BOILER, UNDERGROUND }

@export var role: Role = Role.PIPE
@export var fluid_capacity: float = 100.0
## Подземная труба: наибольшее расстояние до пары, тайлов.
@export var underground_range: int = 10
@export_group("Насос")
@export var pump_per_tile: float = 120.0
## Какую жидкость качает (null — любую): обычный насос берёт только воду, нефть — вышка.
@export var pump_fluid: FluidDef
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
		if power_use > 0.0:
			lines.append(tr("STAT_POWER_USE") % roundi(power_use))
	elif role == Role.BOILER:
		lines.append(tr("STAT_BOILER") % [roundi(fuel_power), steam_per_second])
	elif role == Role.UNDERGROUND:
		lines.append(tr("STAT_UNDERGROUND_RANGE") % underground_range)
	else:
		lines.append(tr("STAT_PIPE_CAPACITY") % roundi(fluid_capacity))
	return lines


## Подземная труба, поставленная за свободным входом (в пределах дальности, смотрящим в её сторону),
## разворачивается к нему — вход и выход ставятся одним и тем же поворотом.
func placement_rotation(world: GameWorld, origin: Vector2i, rotation: int) -> int:
	if role != Role.UNDERGROUND or world == null:
		return rotation
	var back := (rotation + 2) % 4
	var step := GameConst.dir_vector(back)
	for i in range(1, underground_range + 1):
		var other := world.buildings.get_at(origin + step * i) as UndergroundPipe
		if other == null:
			continue
		if other.rotation == rotation and other.find_partner() == null:
			return back
		break
	return rotation


## Насос ставится только на месторождение своей жидкости.
func check_placement(grid: WorldGrid, origin: Vector2i) -> int:
	if role != Role.PUMP:
		return BuildingManager.Check.OK
	return BuildingManager.Check.OK if count_fluid_tiles(grid, origin) > 0 else BuildingManager.Check.NO_ORE


## Число тайлов месторождения подходящей жидкости под постройкой.
func count_fluid_tiles(grid: WorldGrid, origin: Vector2i) -> int:
	var n := 0
	for y in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			if grid.in_bounds(x, y) and pumps(grid.get_ore_def(x, y)):
				n += 1
	return n


## Качает ли насос это месторождение.
func pumps(ore: OreDef) -> bool:
	return ore != null and ore.fluid != null and (pump_fluid == null or ore.fluid == pump_fluid)
