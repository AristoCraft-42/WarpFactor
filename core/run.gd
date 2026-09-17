class_name Run
extends RefCounted
## Забег: мир текущей планеты, подземный этаж мобильной базы (отдельный мир), общий дрон,
## связь центрального шлюза и звёздная карта.
## Мобильная база — площадка шлюза на планете (верхний этаж, переезжает при телепорте) и подземный
## этаж под ней. Размер площадки и открытой части этажа, доступ на этаж и то, что передаёт шлюз,
## зависят от исследований (apply_research_effects).
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

## Пока идёт переезд, лифты новой площадки не ищут пары (планета ещё не стала текущей).
var _pairing_suspended: bool = false
## Лифты площадки, у которых есть пара (для балансов тока и жидкостей без обхода всех зданий).
var _linked_lifts: Array[Lift] = []

## Уровень, если первая планета — готовая карта (разработка и тесты); иначе пусто.
var level_id: StringName = &""


## Новый забег: первая планета генерируется по сиду, дрон получает стартовый инвентарь забега.
static func create_new(p_seed: int, p_creative: bool) -> Run:
	var run := Run.new()
	run.run_seed = p_seed
	run.creative = p_creative
	run.run_def = Registry.run_def
	run.star_map = StarMap.new(p_seed, run.run_def, Registry.planet_types)
	var map := PlanetGenerator.generate(run.star_map.get_current(), run.run_def.pad_start_size, max_pad_size())
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
	attach_world(planet)
	attach_world(base)
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
	apply_research_effects()
	_setup_threat(planet, star_map.get_current(), 0)


## Исследования забега: общие для обоих миров, фильтр ручного крафта дрона.
func setup_research(state: ResearchState) -> void:
	research = state
	research.creative = creative
	planet.research = research
	base.research = research
	drone.crafting.recipe_filter = research.is_hand_recipe_unlocked
	research.changed.connect(_on_research_changed)
	research.completed.connect(func(_research: ResearchDef) -> void: apply_research_effects())


# --- Эффекты исследований ---

## Скорость перетекания жидкости между этажами через одну пару портов, единиц в секунду.
const FLUID_LINK_RATE := 1200.0


## Сторона площадки шлюза на планете с учётом исследований «Расширение площадки».
func get_pad_size() -> int:
	var steps := research.count_effect(&"pad_size") if research != null else 0
	return run_def.pad_start_size + run_def.pad_size_step * steps


## Наибольшая площадка после всех расширений (генератор расчищает под неё место заранее).
static func max_pad_size() -> int:
	return Registry.run_def.pad_start_size + Registry.run_def.pad_size_step * ResearchState.max_effect(&"pad_size")


## Сторона открытой части подземного этажа с учётом исследований «Расширение подземного этажа».
func get_underground_size() -> int:
	var steps := research.count_effect(&"underground_size") if research != null else 0
	return Registry.base_def.start_size + Registry.base_def.size_step * steps


func is_underground_open() -> bool:
	return research != null and research.has_effect(&"underground")


## Применить исследования к мирам: площадка и открытая часть этажа растут, шлюз перерисовывает порты,
## сети труб и электросети пересобираются (шлюз и лифты могли начать их соединять).
## notify = false — после загрузки: размеры сверяются, но здания не будятся и сети не пересобираются
## (состояние симуляции должно совпасть с сохранённым).
func apply_research_effects(notify: bool = true) -> void:
	if planet != null and link != null and link.planet_gateway != null:
		planet.resize_pad(_pad_around(link.planet_gateway))
	if base != null:
		base.open_area(GameWorld.base_rect(Registry.base_def, get_underground_size()))
	if not notify:
		return
	for world in [planet, base]:
		if world == null or world.buildings == null:
			continue
		world.power.mark_dirty()
		world.fluids.mark_dirty()
		var gate := get_gateway(world)
		if gate != null and gate.world == world:
			world.buildings.notify_changed(gate)
			gate.notify_space()
			gate.wake()


func _on_research_changed() -> void:
	for world in [planet, base]:
		if world == null or world.buildings == null:
			continue
		for b in world.buildings.get_all():
			if b is ScienceWorkshop:
				b.wake()


## Один логический тик обоих миров, исследований и зарядки телепорта. Перед тиками миров —
## общие балансы: жидкости и электричество между этажами (через шлюз и лифты).
func step() -> void:
	_balance_fluids()
	_balance_power()
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

## Проход между этажами под дроном: центральный шлюз (или его пара) либо лифт с парой.
func get_passage() -> Building:
	if drone.dead or drone.world == null:
		return null
	var gate := get_gateway(drone.world)
	if gate != null and gate.world != null and gate.get_world_rect().has_point(drone.position):
		return gate
	var lift := drone.world.buildings.get_at(drone.get_tile()) as Lift
	return lift if lift != null and lift.pair != null else null


## Дрон над проходом между этажами (переход может быть закрыт исследованием).
func is_over_gateway() -> bool:
	return get_passage() != null


## Дрон над проходом и подземный этаж открыт — можно пройти на другой этаж.
func can_use_gateway() -> bool:
	return is_over_gateway() and is_underground_open()


## Переносит дрона через шлюз или лифт: он оказывается над парой на другом этаже в той же точке.
func use_gateway() -> bool:
	if not can_use_gateway():
		return false
	var from := get_passage()
	var to: Building = (from as Lift).pair if from is Lift else get_gateway(base if drone.world == planet else planet)
	var to_world := to.world
	var offset := drone.position - from.get_world_center()
	drone.stop_mining()
	drone.world = to_world
	drone.position = to.get_world_center() + offset
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
	# Лифты старой планеты отпускают пары на этаже: новые лифты площадки свяжутся с ними заново.
	for b in old.buildings.get_all():
		if b is Lift and (b as Lift).pair != null:
			(b as Lift).pair.pair = null
			(b as Lift).pair = null
	_linked_lifts.clear()
	star_map.move_to(node_id)
	var map := PlanetGenerator.generate(node, get_pad_size(), max_pad_size())
	var fresh := GameWorld.create(null, map, creative, drone)
	fresh.research = research
	# Пары лифтов свяжутся, когда новая планета станет текущей (шлюз и площадка уже на месте).
	_pairing_suspended = true
	attach_world(fresh)
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
	_pairing_suspended = false
	relink_lifts()
	# Лифты этажа, чья пара не переехала (не поместилась на площадке), убираются.
	for b in base.buildings.get_all():
		if b is Lift and (b as Lift).pair == null:
			summary.buildings_lost += 1
			base.buildings.remove(b, true)
	planet_arrival_tick = fresh.simulation.tick
	charge_target = -1
	charge_ticks_left = 0
	summary.to_title = get_world_title(fresh)
	summary.to_safe = node.type.safe
	last_summary = summary
	planet_changed.emit()
	teleport_state_changed.emit()


## Площадка вокруг центра шлюза (при чётной стороне на тайл больше влево и вверх).
# --- Связь этажей: лифты, электричество, жидкости ---

## Подключить мир к забегу: баланс тока ведёт забег, лифты связываются в пары.
func attach_world(world: GameWorld) -> void:
	world.power.managed = true
	world.lift_check = _check_lift
	world.buildings.building_added.connect(_on_building_added.bind(world))
	world.buildings.building_removed.connect(_on_building_removed.bind(world))


func _other_world(world: GameWorld) -> GameWorld:
	return base if world == planet else planet


## Где на другом этаже стоит пара здания с левым верхним тайлом origin (относительно шлюза).
func pair_origin(world: GameWorld, origin: Vector2i) -> Vector2i:
	var from := get_gateway(world)
	var to := get_gateway(_other_world(world))
	if from == null or to == null:
		return origin
	return to.origin + (origin - from.origin)


## Место лифта: этаж открыт и лифт изучен; на площадке (планета) или в открытой части этажа, и пара
## на другом этаже помещается туда же и на свободное место.
func _check_lift(world: GameWorld, def: BuildingDef, origin: Vector2i) -> BuildingManager.Check:
	if not is_underground_open() or not research.is_building_unlocked(def):
		return BuildingManager.Check.LOCKED
	var rect := Rect2i(origin, Vector2i(def.size, def.size))
	var other := _other_world(world)
	if other == null or get_gateway(world) == null or get_gateway(other) == null:
		return BuildingManager.Check.LIFT_AREA
	var area := world.pad_rect if world == planet else world.play_rect
	if not area.encloses(rect):
		return BuildingManager.Check.LIFT_AREA
	var target := pair_origin(world, origin)
	var other_area := other.pad_rect if other == planet else other.play_rect
	if not other_area.encloses(Rect2i(target, rect.size)):
		return BuildingManager.Check.LIFT_AREA
	if other.buildings.check_place(def, target, 0) != BuildingManager.Check.OK:
		return BuildingManager.Check.LIFT_PAIR
	return BuildingManager.Check.OK


func _on_building_added(building: Building, world: GameWorld) -> void:
	if building is Lift and (building as Lift).pair == null and not _pairing_suspended:
		pair_lift(building as Lift, world)


## Найти или поставить пару лифта на другом этаже. У пары — направление уже стоящего лифта.
func pair_lift(lift: Lift, world: GameWorld) -> void:
	var other := _other_world(world)
	if other == null or other.buildings == null or get_gateway(world) == null or get_gateway(other) == null:
		return
	var target := pair_origin(world, lift.origin)
	var existing := other.buildings.get_at(target) as Lift
	if existing != null and existing.origin == target:
		if existing.pair == null:
			lift.pair = existing
			existing.pair = lift
			lift.direction = existing.direction
			_linked_lifts.append(lift if lift.world == planet else existing)
			_on_lift_linked(lift)
		return
	var placed := other.buildings.place(lift.def, target, 0) as Lift
	if placed != null and placed.pair == lift:
		placed.set_config(lift.direction)


func _on_lift_linked(lift: Lift) -> void:
	for l in [lift, lift.pair]:
		if l.world != null:
			l.world.buildings.notify_changed(l)
			l.world.power.mark_dirty()
			l.world.fluids.mark_dirty()
			l.wake()


## Снос лифта сносит и его пару (содержимое пары уже учтено в сносе).
func _on_building_removed(building: Building, _world: GameWorld) -> void:
	if not (building is Lift):
		return
	var lift := building as Lift
	var paired := lift.pair
	if paired == null:
		return
	_linked_lifts.erase(lift)
	_linked_lifts.erase(paired)
	lift.pair = null
	paired.pair = null
	paired.buffer.clear()
	if paired.world != null and paired.world.buildings != null:
		paired.world.buildings.remove(paired, true)


## После загрузки: лифты площадки и этажа находят свои пары.
func relink_lifts() -> void:
	for b in planet.buildings.get_all():
		if b is Lift and (b as Lift).pair == null:
			pair_lift(b as Lift, planet)


## Пары зданий, соединяющих этажи (шлюз и лифты): [здание на планете, здание на этаже].
func _floor_links() -> Array:
	var result: Array = []
	if link != null and link.planet_gateway != null and link.base_gateway != null:
		result.append([link.planet_gateway, link.base_gateway])
	for lift in _linked_lifts:
		if lift.world != null and lift.pair != null and lift.pair.world != null:
			result.append([lift, lift.pair])
	return result


## Электросети обоих этажей: подготовка, объединение сетей, связанных шлюзом и лифтами, общий баланс групп.
func _balance_power() -> void:
	planet.power.prepare()
	base.power.prepare()
	var nets: Array[PowerGraph.PowerNetwork] = []
	nets.append_array(planet.power.networks)
	nets.append_array(base.power.networks)
	if nets.is_empty():
		return
	var index: Dictionary[PowerGraph.PowerNetwork, int] = {}
	for i in nets.size():
		index[nets[i]] = i
	var parent := PackedInt32Array()
	parent.resize(nets.size())
	for i in nets.size():
		parent[i] = i
	for pair in _floor_links():
		var a: Building = pair[0]
		var b: Building = pair[1]
		if a.power_net == null or b.power_net == null or not index.has(a.power_net) or not index.has(b.power_net):
			continue
		var ra := _root(parent, index[a.power_net])
		var rb := _root(parent, index[b.power_net])
		if ra != rb:
			parent[maxi(ra, rb)] = mini(ra, rb)
	var groups: Dictionary[int, Array] = {}
	var roots := PackedInt32Array()
	for i in nets.size():
		var r := _root(parent, i)
		if not groups.has(r):
			groups[r] = []
			roots.append(r)
		groups[r].append(nets[i])
	for r in roots:
		var group: Array[PowerGraph.PowerNetwork] = []
		group.assign(groups[r])
		PowerGraph.balance(group)


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


## Жидкости между этажами: связанные порты шлюза и лифтов выравнивают заполненность своих сетей.
func _balance_fluids() -> void:
	planet.fluids.update()
	base.fluids.update()
	var limit := FLUID_LINK_RATE * GameConst.TICK_DT
	for pair in _floor_links():
		var a: Building = pair[0]
		var b: Building = pair[1]
		if a is GatewayBuilding:
			var ga := a as GatewayBuilding
			var gb := b as GatewayBuilding
			if not ga.fluids_enabled():
				continue
			for relative in [1, 3]:
				_balance_fluid_pair(planet.fluids.get_port_network(ga, ga.get_fluid_side(relative)),
					base.fluids.get_port_network(gb, gb.get_fluid_side(relative)), limit)
		elif not a.get_fluid_ports().is_empty():
			_balance_fluid_pair(planet.fluids.get_port_network(a, 0), base.fluids.get_port_network(b, 0), limit)


## Выровнять долю заполнения двух сетей одной жидкости (не больше limit за тик).
static func _balance_fluid_pair(a: FluidGraph.FluidNetwork, b: FluidGraph.FluidNetwork, limit: float) -> void:
	if a == null or b == null or a == b or a.capacity + b.capacity <= 0.0:
		return
	var fluid := a.fluid if a.fluid >= 0 else b.fluid
	if fluid < 0 or (a.fluid >= 0 and a.fluid != fluid) or (b.fluid >= 0 and b.fluid != fluid):
		return
	var target_a := (a.amount + b.amount) * a.capacity / (a.capacity + b.capacity)
	var move := clampf(target_a - a.amount, -limit, limit)
	if move > 0.000001:
		var taken := b.extract(fluid, move)
		var put := a.insert(fluid, taken)
		b.insert(fluid, taken - put)
	elif move < -0.000001:
		var taken := a.extract(fluid, -move)
		var put := b.insert(fluid, taken)
		a.insert(fluid, taken - put)


func _pad_around(gate: GatewayBuilding) -> Rect2i:
	if gate == null:
		return Rect2i()
	var size := get_pad_size()
	var center := gate.origin + Vector2i.ONE * (gate.def.size / 2)
	return Rect2i(center - Vector2i.ONE * (size / 2), Vector2i(size, size))


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
