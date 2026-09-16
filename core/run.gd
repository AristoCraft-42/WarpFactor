class_name Run
extends RefCounted
## Забег: мир текущей планеты, мир мобильной базы, общий дрон, связь центрального шлюза и звёздная карта.
## Оба мира тикают в одном шаге (step) при любом активном виде. Дрон обновляется в симуляции
## того мира, где он сейчас находится, и переходит между мирами через шлюз (use_gateway).
##
## Телепорт: у шлюза выбирается соседняя планета звёздной карты, идёт зарядка (игра продолжается,
## можно отменить). По окончании мир планеты заменяется новым: площадка шлюза переезжает со всеми
## постройками и их содержимым, остальное на старой планете теряется. База не меняется.
##
## Прорыв: враги обнулили прочность центрального шлюза — сразу, без зарядки, аварийный телепорт
## на случайную соседнюю планету. Площадка переезжает как обычно (разрушенное уже потеряно),
## шлюз на новой планете пересобирается с полной прочностью.

## Сторона площадки центрального шлюза на планете, тайлов (площадка переезжает вместе с базой).
const PAD_SIZE := 15

## Дрон перешёл в другой мир.
signal drone_changed_world
## Мир планеты заменён новым (после телепорта); итог — в last_summary.
signal planet_changed
## Зарядка телепорта началась, отменена или закончилась.
signal teleport_state_changed
## Телепорт сейчас произойдёт (мир ещё прежний) — время для автосохранения.
signal teleport_starting

var planet: GameWorld
var base: GameWorld
var research: ResearchState
var drone: Drone
var link: GatewayLink
var star_map: StarMap
var run_def: RunDef
var creative: bool = false
var run_seed: int = 0

## Узел, куда идёт зарядка (-1 — телепорт не заряжается).
var charge_target: int = -1
var charge_ticks_left: int = 0
var charge_ticks_total: int = 0
## Тик прибытия на текущую планету.
var planet_arrival_tick: int = 0
var last_summary: TeleportSummary

## Уровень, если первая планета — готовая карта (разработка и тесты); иначе пусто.
var level_id: StringName = &""


## Новый забег: первая планета генерируется по сиду, дрон получает стартовый инвентарь забега.
static func create_new(p_seed: int, p_creative: bool) -> Run:
	var run := Run.new()
	run.run_seed = p_seed
	run.creative = p_creative
	run.run_def = Registry.run_def
	run.star_map = StarMap.new(p_seed, run.run_def, Registry.planet_types)
	var map := PlanetGenerator.generate(run.star_map.get_current(), PAD_SIZE)
	run._setup(null, map)
	for stack in run.run_def.starting_items:
		if stack != null and stack.item != null:
			run.drone.inventory.add(stack.item.index, stack.amount)
	return run


## Забег на готовой карте уровня (разработка, тесты): шлюз — на месте появления дрона.
static func create(level: LevelDef, map: LevelMap, p_creative: bool) -> Run:
	var run := Run.new()
	run.run_seed = hash(String(level.id)) & 0x7fffffff if level != null else 1
	run.creative = p_creative
	run.run_def = Registry.run_def
	run.star_map = StarMap.new(run.run_seed, run.run_def, Registry.planet_types)
	if level != null:
		run.level_id = level.id
	run._setup(level, map)
	return run


func _setup(level: LevelDef, map: LevelMap) -> void:
	planet = GameWorld.create(level, map, creative)
	drone = planet.drone
	base = GameWorld.create_base(Registry.base_def, creative, drone)
	setup_research(ResearchState.new())
	link = GatewayLink.new()
	var spawn := drone.get_tile()
	var planet_gate := planet.place_gateway(Registry.get_building(&"central_gateway") as GatewayDef, spawn - Vector2i.ONE)
	var base_size := base.grid.width
	var base_gate := base.place_gateway(Registry.get_building(&"base_gateway") as GatewayDef,
		Vector2i((base_size - 3) / 2, (base_size - 3) / 2))
	if planet_gate == null or base_gate == null:
		return
	link.planet_gateway = planet_gate
	link.base_gateway = base_gate
	link.capacity = planet_gate.get_gateway_def().buffer_capacity
	planet_gate.link = link
	base_gate.link = link
	planet.pad_rect = _pad_around(planet_gate)
	_setup_threat(planet, star_map.get_current(), 0)


## Исследования забега: общие для обоих миров, фильтр ручного крафта дрона.
func setup_research(state: ResearchState) -> void:
	research = state
	research.creative = creative
	planet.research = research
	base.research = research
	drone.crafting.recipe_filter = research.is_hand_recipe_unlocked
	research.changed.connect(_on_research_changed)


func _on_research_changed() -> void:
	for world in [planet, base]:
		if world == null or world.buildings == null:
			continue
		for b in world.buildings.get_all():
			if b is ScienceWorkshop:
				b.wake()


## Один логический тик обоих миров, исследований и зарядки телепорта.
func step() -> void:
	planet.simulation.step()
	base.simulation.step()
	research.step()
	if planet.breached:
		emergency_teleport()
		return
	if charge_target >= 0:
		charge_ticks_left -= 1
		if charge_ticks_left <= 0:
			_teleport(charge_target)


func get_gateway(world: GameWorld) -> GatewayBuilding:
	if link == null:
		return null
	return link.base_gateway if world == base else link.planet_gateway


## Название мира для интерфейса: база, готовый уровень или «тип + код» сгенерированной планеты.
func get_world_title(world: GameWorld) -> String:
	if world == base:
		return TranslationServer.translate(Registry.base_def.title_key)
	var node := star_map.get_current()
	var level := Registry.get_level(level_id) if level_id != &"" else null
	if level != null and node.id == 0:
		return TranslationServer.translate(level.title_key)
	return "%s %s" % [TranslationServer.translate(node.type.name_key), node.code]


func is_planet_safe() -> bool:
	return star_map.get_current().type.safe


## Угроза планеты по типу узла звёздной карты (у безопасной планеты и в творческом режиме её нет).
func _setup_threat(world: GameWorld, node: StarMap.StarNode, start_tick: int, compute: bool = true) -> void:
	if creative or node.type.safe or node.type.threat == null:
		return
	world.setup_threat(node.type.threat, start_tick, node.planet_seed, compute)


# --- Дрон и шлюз ---

## Дрон над центральным шлюзом своего мира — можно пройти в другой мир.
func can_use_gateway() -> bool:
	if drone.dead:
		return false
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


# --- Телепорт ---

func is_charging() -> bool:
	return charge_target >= 0


## Доля зарядки (0..1).
func get_charge_fraction() -> float:
	if charge_ticks_total <= 0:
		return 0.0
	return clampf(1.0 - float(charge_ticks_left) / charge_ticks_total, 0.0, 1.0)


func get_charge_seconds_left() -> float:
	return float(maxi(charge_ticks_left, 0)) / GameConst.TICK_RATE


## Начать зарядку телепорта на соседнюю планету звёздной карты.
func start_teleport(node_id: int) -> bool:
	if is_charging() or not star_map.can_travel_to(node_id):
		return false
	charge_target = node_id
	charge_ticks_total = run_def.get_charge_ticks()
	charge_ticks_left = charge_ticks_total
	teleport_state_changed.emit()
	return true


func cancel_teleport() -> void:
	if not is_charging():
		return
	charge_target = -1
	charge_ticks_left = 0
	teleport_state_changed.emit()


## Аварийный телепорт при прорыве: случайная соседняя планета, без зарядки.
func emergency_teleport() -> void:
	var next := star_map.get_next()
	if next.is_empty():
		planet.breached = false
		if link.planet_gateway != null:
			link.planet_gateway.health = link.planet_gateway.get_max_health()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, star_map.current_id, planet.simulation.tick, "breach"])
	_teleport(next[rng.randi_range(0, next.size() - 1)].id, true)


## Перелёт: новая планета, переезд площадки со всеми постройками и их содержимым.
func _teleport(node_id: int, emergency: bool = false) -> void:
	teleport_starting.emit()
	var node := star_map.get_node(node_id)
	var old := planet
	var old_gate := link.planet_gateway
	var summary := TeleportSummary.new()
	summary.from_title = get_world_title(old)
	summary.seconds_on_planet = float(old.simulation.tick - planet_arrival_tick) / GameConst.TICK_RATE
	summary.sent_to_base = link.sent_to_base.duplicate()
	summary.emergency = emergency
	summary.buildings_destroyed = old.destroyed_count
	summary.waves = old.threat.wave if old.threat != null else 0
	summary.enemies_killed = old.enemies.killed

	# Что переезжает: постройки целиком на площадке (кроме самого шлюза — он ставится заново).
	var pad := old.pad_rect
	var entries: Array[Dictionary] = []
	for b in old.buildings.get_all():
		if b == old_gate:
			continue
		if pad.size != Vector2i.ZERO and pad.encloses(b.get_rect()):
			entries.append({"def": b.def, "offset": b.origin - pad.position, "rotation": b.rotation,
				"config": b.get_config(), "state": b.save_state(), "health": b.health})
		else:
			summary.buildings_lost += 1
			b.collect_contents(summary.items_lost)
	var gate_rotation := old_gate.rotation if old_gate != null else 0
	var gate_state := old_gate.save_state() if old_gate != null else {}
	var drone_on_planet := drone.world == old
	var drone_offset := drone.position - old_gate.get_world_center() if old_gate != null else Vector2.ZERO
	var drone_on_pad := pad.has_point(drone.get_tile())
	var gate_center := old_gate.get_world_center() if old_gate != null else Vector2.ZERO
	var crates: Array[DroneCrate] = []
	for crate in old.crates:
		if pad.size != Vector2i.ZERO and pad.has_point(GameConst.world_to_tile(crate.position)):
			crate.position -= gate_center
			crates.append(crate)
		else:
			crate.collect_into(summary.items_lost)

	# Новая планета: тики синхронны с базой, шлюз и площадка — в центре карты.
	star_map.move_to(node_id)
	var map := PlanetGenerator.generate(node, PAD_SIZE)
	var fresh := GameWorld.create(null, map, creative, drone)
	fresh.research = research
	fresh.simulation.tick = base.simulation.tick
	var center := Vector2i(map.width / 2, map.height / 2)
	var new_gate := fresh.place_gateway(Registry.get_building(&"central_gateway") as GatewayDef, center - Vector2i.ONE, gate_rotation)
	fresh.pad_rect = _pad_around(new_gate)
	for e in entries:
		var b := fresh.buildings.place(e["def"], fresh.pad_rect.position + (e["offset"] as Vector2i), e["rotation"], true)
		if b == null:
			summary.buildings_lost += 1
			continue
		if e["config"] != null:
			b.set_config(e["config"])
			fresh.buildings.notify_changed(b)
		b.load_state(e["state"])
		b.health = minf(float(e["health"]), b.get_max_health())
		if b.is_damaged():
			fresh.damaged[b.id] = true
		summary.buildings_moved += 1
	for crate in crates:
		crate.position += new_gate.get_world_center() if new_gate != null else Vector2.ZERO
		fresh.crates.append(crate)

	if old_gate != null:
		old_gate.link = null
	link.planet_gateway = new_gate
	if new_gate != null:
		new_gate.link = link
		new_gate.load_state(gate_state)
	link.reset_counters()

	if drone_on_planet:
		drone.stop_mining()
		drone.world = fresh
		var target := new_gate.get_world_center() + (drone_offset if drone_on_pad else Vector2.ZERO)
		drone.position = target
		drone.prev_position = target
		drone.move_input = Vector2.ZERO

	_setup_threat(fresh, node, fresh.simulation.tick)
	old.dispose()
	planet = fresh
	planet_arrival_tick = fresh.simulation.tick
	charge_target = -1
	charge_ticks_left = 0
	summary.to_title = get_world_title(fresh)
	summary.to_safe = node.type.safe
	last_summary = summary
	planet_changed.emit()
	teleport_state_changed.emit()


func _pad_around(gate: GatewayBuilding) -> Rect2i:
	if gate == null:
		return Rect2i()
	var center := gate.origin + Vector2i.ONE
	return Rect2i(center - Vector2i.ONE * (PAD_SIZE / 2), Vector2i(PAD_SIZE, PAD_SIZE))


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
