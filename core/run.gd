class_name Run
extends RefCounted
## Забег: мир текущей планеты, мир мобильной базы, общий дрон и связь центрального шлюза.
## Оба мира тикают в одном шаге (step) при любом активном виде. Дрон обновляется в симуляции
## того мира, где он сейчас находится, и переходит между мирами через шлюз (use_gateway).

## Сторона площадки центрального шлюза на планете, тайлов (площадка переезжает вместе с базой).
const PAD_SIZE := 15

## Дрон перешёл в другой мир.
signal drone_changed_world

var planet: GameWorld
var base: GameWorld
var drone: Drone
var link: GatewayLink
var creative: bool = false


## Создаёт забег: планета из карты уровня (шлюз — на месте появления дрона) и пустая база с парой шлюза.
static func create(level: LevelDef, map: LevelMap, p_creative: bool) -> Run:
	var run := Run.new()
	run.creative = p_creative
	run.planet = GameWorld.create(level, map, p_creative)
	run.drone = run.planet.drone
	run.base = GameWorld.create_base(Registry.base_def, p_creative, run.drone)

	var spawn := run.drone.get_tile()
	var planet_gate := run.planet.place_gateway(Registry.get_building(&"central_gateway") as GatewayDef, spawn - Vector2i.ONE)
	var base_size := run.base.grid.width
	var base_gate := run.base.place_gateway(Registry.get_building(&"base_gateway") as GatewayDef,
		Vector2i((base_size - 3) / 2, (base_size - 3) / 2))
	run.link = GatewayLink.new()
	if planet_gate != null and base_gate != null:
		run.link.planet_gateway = planet_gate
		run.link.base_gateway = base_gate
		run.link.capacity = planet_gate.get_gateway_def().buffer_capacity
		planet_gate.link = run.link
		base_gate.link = run.link
		var center := planet_gate.origin + Vector2i.ONE
		run.planet.pad_rect = Rect2i(center - Vector2i.ONE * (PAD_SIZE / 2), Vector2i(PAD_SIZE, PAD_SIZE))
	return run


## Один логический тик обоих миров.
func step() -> void:
	planet.simulation.step()
	base.simulation.step()


func get_gateway(world: GameWorld) -> GatewayBuilding:
	if link == null:
		return null
	return link.base_gateway if world == base else link.planet_gateway


## Дрон над центральным шлюзом своего мира — можно пройти в другой мир.
func can_use_gateway() -> bool:
	var gate := get_gateway(drone.world)
	return gate != null and gate.world != null and gate.get_world_rect().has_point(drone.position)


## Переносит дрона через шлюз: он оказывается над парой в другом мире в той же точке шлюза.
func use_gateway() -> bool:
	if not can_use_gateway():
		return false
	var from_gate := get_gateway(drone.world)
	var to_world := base if drone.world == planet else planet
	var to_gate := get_gateway(to_world)
	var offset := drone.position - from_gate.get_world_center()
	drone.stop_mining()
	drone.world = to_world
	drone.position = to_gate.get_world_center() + offset
	drone.prev_position = drone.position
	drone.move_input = Vector2.ZERO
	drone_changed_world.emit()
	return true


func dispose() -> void:
	if link != null:
		link.dispose()
	if planet != null:
		planet.dispose()
	if base != null:
		base.dispose()
	planet = null
	base = null
	drone = null
