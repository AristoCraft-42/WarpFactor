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
## Своя команда ушла в сеть и ждёт своего тика (в одиночной игре не зовётся).
signal command_sent(cmd: Command)
## Команда применена к миру — её предсказание больше не нужно.
signal command_applied(cmd: Command)


signal drone_changed_world
## Состав игроков или локальный игрок изменились.
signal players_changed
## Мир планеты заменён новым (после телепорта); итог — в last_summary.
signal planet_changed
## Зарядка телепорта началась, отменена или закончилась.
signal teleport_state_changed
## Телепорт сейчас произойдёт (мир ещё прежний) — время для автосохранения.
signal teleport_starting

var planet: GameWorld
var base: GameWorld
var research: ResearchState
## Игроки забега по возрастанию id: у каждого свой дрон, инвентарь и очередь крафта.
var players: Array[Player] = []
## Чей дрон показывает и слушает этот клиент.
var local_player: int = 1
## Следующий свободный id игрока (id не переиспользуются: по ним сортируются команды).
var next_player_id: int = 1
## Очередь команд: через неё идут все действия игроков (см. core/command.gd).
var commands := CommandQueue.new()
## Куда уходит отданная команда. Пусто — сразу в очередь (одиночная игра); в сетевой игре
## её ставит NetSession: команда идёт хосту и вернётся окончательным списком на тик.
var command_router: Callable

## Дрон локального игрока — старый код и интерфейс обращаются к нему как раньше.
var drone: Drone:
	get:
		var player := get_player(local_player)
		if player != null:
			return player.drone
		return players[0].drone if not players.is_empty() else null
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
	var drone := planet.drone
	_register_player("", drone)
	base = GameWorld.create_base(Registry.base_def, creative)
	attach_world(planet)
	attach_world(base)
	setup_research(ResearchState.new())
	link = GatewayLink.new()
	var spawn := drone.get_tile()
	var planet_def := Registry.get_building(&"central_gateway") as GatewayDef
	var planet_gate := planet.place_gateway(planet_def, GameWorld.gateway_origin(planet_def, spawn))
	var base_size := base.grid.width
	var base_def := Registry.get_building(&"base_gateway") as GatewayDef
	var base_gate := base.place_gateway(base_def,
		GameWorld.gateway_origin(base_def, Vector2i(base_size / 2, base_size / 2)))
	if planet_gate == null or base_gate == null:
		return
	link.planet_gateway = planet_gate
	link.base_gateway = base_gate
	link.capacity = planet_gate.get_gateway_def().buffer_capacity
	planet_gate.link = link
	base_gate.link = link
	# Через resize_pad, а не присваиванием: площадка может быть больше стартовой (исследования,
	# творческий режим), и её расширенную часть нужно вымостить, иначе там остаётся голая земля.
	planet.resize_pad(_pad_around(planet_gate))
	set_local_player(local_player)
	apply_research_effects()
	_setup_threat(planet, star_map.get_current(), 0)


# --- Игроки ---

func get_player(id: int) -> Player:
	for p in players:
		if p.id == id:
			return p
	return null


func get_local_player() -> Player:
	return get_player(local_player)


## Завести игрока с готовым дроном (при создании забега и при загрузке).
func _register_player(name: String, p_drone: Drone, id: int = 0) -> Player:
	var player_id := id if id > 0 else next_player_id
	next_player_id = maxi(next_player_id, player_id + 1)
	var player := Player.create(player_id, name if not name.is_empty() else tr("PLAYER_DEFAULT_NAME") % player_id, p_drone)
	players.append(player)
	players.sort_custom(func(a: Player, b: Player) -> bool: return a.id < b.id)
	if p_drone.world != null:
		p_drone.world.add_drone(p_drone)
	return player


## Новый игрок: дрон появляется у центрального шлюза планеты со стартовым набором забега.
func add_player(name: String = "", id: int = 0) -> Player:
	var gate := get_gateway(planet)
	var spawn := gate.get_world_center() if gate != null else Vector2(planet.grid.width, planet.grid.height) * GameConst.TILE_SIZE * 0.5
	var fresh := Drone.new(Registry.drone_def, planet, spawn)
	var player := _register_player(name, fresh, id)
	fresh.crafting.recipe_filter = research.is_hand_recipe_unlocked if research != null else Callable()
	if research != null:
		fresh.apply_upgrades(research, false)
	players_changed.emit()
	return player


## Игрок вышел: дрон и его вещи исчезают вместе с ним (вещи не пропадают — падают грузом).
func remove_player(id: int) -> void:
	var player := get_player(id)
	if player == null or players.size() <= 1:
		return
	var world := player.drone.world
	if world != null:
		world.kill_drone(player.drone, world.simulation.tick)
		world.remove_drone(player.drone)
	players.erase(player)
	if local_player == id:
		set_local_player(players[0].id)
	players_changed.emit()


## Сменить локального игрока: интерфейс и камера переезжают к его дрону.
func set_local_player(id: int) -> void:
	var player := get_player(id)
	if player == null:
		return
	local_player = id
	for world in [planet, base]:
		if world != null:
			world.view_drone = player.drone
	players_changed.emit()
	drone_changed_world.emit()


## Инвентарь, из которого исследование берёт наборы при ручной сдаче (пусто — сдающего нет).
func _manual_kits() -> Inventory:
	var player := get_player(research.manual_player) if research != null else null
	return player.drone.inventory if player != null and player.drone != null else null


## Исследования забега: общие для обоих миров, фильтр ручного крафта дрона.
## Творческий режим: включить или выключить волны на текущей планете.
func set_creative_threat(on: bool) -> void:
	if not creative or planet == null:
		return
	if on:
		if planet.threat != null:
			return
		var node := star_map.get_current()
		var def := node.type.threat if node != null and node.type != null else null
		if def == null:
			for type in Registry.planet_types:
				if type.threat != null:
					def = type.threat
					break
		if def == null:
			return
		planet.setup_threat(def, planet.simulation.tick, node.planet_seed if node != null else 0)
	elif planet.threat != null:
		planet.threat.dispose()
		planet.threat = null


func has_creative_threat() -> bool:
	return planet != null and planet.threat != null


## Творческий режим: позвать волну сейчас (включив волны, если они были выключены).
func call_creative_wave() -> void:
	set_creative_threat(true)
	if planet != null and planet.threat != null:
		planet.threat.call_next_wave(planet.simulation.tick)


func setup_research(state: ResearchState) -> void:
	state.sandbox = creative
	research = state
	if not research.loaded:
		research.creative = creative
	planet.research = research
	base.research = research
	for p in players:
		p.drone.crafting.recipe_filter = research.is_hand_recipe_unlocked
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
	_grow_gateways()
	if planet != null and link != null and link.planet_gateway != null:
		planet.resize_pad(_pad_around(link.planet_gateway))
	if base != null:
		base.open_area(GameWorld.base_rect(Registry.base_def, get_underground_size()))
	for p in players:
		p.drone.apply_upgrades(research, notify)
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
# --- Команды ---

## Отдать команду от локального игрока.
func submit(kind: Command.Kind, args: Dictionary = {}) -> void:
	submit_for(local_player, kind, args)


## Отдать команду от имени игрока (из сети — от того, кто её прислал).
func submit_for(player_id: int, kind: Command.Kind, args: Dictionary = {}) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	var cmd := Command.make(kind, player_id, args)
	cmd.seq = player.next_seq
	player.next_seq += 1
	if command_router.is_valid():
		command_router.call(cmd)
		# В сетевой игре команда применится через задержку: интерфейс покажет её результат сразу
		# (NetPredict), а сам мир останется нетронутым.
		command_sent.emit(cmd)
	else:
		commands.submit(cmd, get_tick())


## Названия частей отпечатка состояния — по ним сообщается, что именно разошлось.
const STATE_PART_NAMES := [
	"тик", "исследования",
	"постройки планеты", "предметы на лентах планеты", "враги планеты",
	"постройки базы", "предметы на лентах базы", "враги базы",
	"игроки"]


## Отпечаток состояния забега для сверки между участниками сетевой игры.
## Считается быстро (без сериализации) и по всему, что влияет на ход игры: тик, постройки
## и их состояние, предметы на лентах, дроны с инвентарями, исследования.
## Расходится — значит симуляции разъехались.
func state_hash() -> int:
	return hash(state_parts())


## Отпечаток по частям: если участники разошлись, по индексу разной части сразу видно, где именно.
## Порядок частей зафиксирован STATE_PART_NAMES — менять их можно только вместе.
func state_parts() -> PackedInt64Array:
	var parts := PackedInt64Array()
	parts.append(get_tick())
	parts.append(research.done.size() * 1000 + research.manual_queue)
	for world in [planet, base]:
		if world == null or world.buildings == null:
			parts.append(0)
			parts.append(0)
			parts.append(0)
			continue
		var acc := 0
		for b in world.buildings.get_all():
			acc = (acc * 31 + b.id) & 0x3FFFFFFF
			acc = (acc * 31 + b.origin.x * 1013 + b.origin.y * 7919 + b.rotation) & 0x3FFFFFFF
			acc = (acc * 31 + roundi(b.health)) & 0x3FFFFFFF
		parts.append(world.buildings.get_count() * 1000003 + acc)
		parts.append(world.simulation.conveyors.get_item_count())
		# Врагов мало и они быстро меняются, поэтому считаем их подробно: по одному лишь
		# числу живых расхождение в их движении не видно, а дроны от него страдают сразу.
		var foes: int = world.enemies.count * 1000003 + world.enemies.killed
		for i in world.enemies.count:
			foes = (foes * 31 + world.enemies.uid[i]) & 0x3FFFFFFF
			foes = (foes * 31 + roundi(world.enemies.pos_x[i] * 8.0)) & 0x3FFFFFFF
			foes = (foes * 31 + roundi(world.enemies.pos_y[i] * 8.0)) & 0x3FFFFFFF
			foes = (foes * 31 + roundi(world.enemies.health[i])) & 0x3FFFFFFF
			foes = (foes * 31 + world.enemies.target[i]) & 0x3FFFFFFF
		parts.append(foes)
	var people := 0
	for p in players:
		var d := p.drone
		var items := 0
		for i in d.inventory.totals.size():
			items = (items * 17 + d.inventory.totals[i] * (i + 1)) & 0x3FFFFFFF
		people = (people * 31 + p.id) & 0x3FFFFFFF
		people = (people * 31 + roundi(d.position.x * 8.0)) & 0x3FFFFFFF
		people = (people * 31 + roundi(d.position.y * 8.0)) & 0x3FFFFFFF
		people = (people * 31 + roundi(d.health)) & 0x3FFFFFFF
		people = (people * 31 + items) & 0x3FFFFFFF
	parts.append(people)
	return parts


## Текущий тик забега (оба мира тикают вместе).
func get_tick() -> int:
	return planet.simulation.tick if planet != null and planet.simulation != null else 0


## Применить команды этого тика по порядку.
func _apply_commands() -> void:
	for cmd in commands.take(get_tick()):
		execute(cmd)


## Выполнить одну команду. Все изменения мира проходят здесь: и в одиночной игре, и в сетевой.
func execute(cmd: Command) -> void:
	if cmd.kind == Command.Kind.PLAYER_ADD:
		add_player(String(cmd.args.get("name", "")), int(cmd.args.get("id", 0)))
		return
	if cmd.kind == Command.Kind.PLAYER_REMOVE:
		remove_player(int(cmd.args.get("player", cmd.player)))
		return
	var player := get_player(cmd.player)
	if player == null:
		return
	var actor := player.drone
	var world := actor.world
	if world == null:
		return
	world.actor = actor
	_run_command(cmd, player, actor, world)
	world.actor = null
	command_applied.emit(cmd)


func _run_command(cmd: Command, player: Player, actor: Drone, world: GameWorld) -> void:
	var args := cmd.args
	match cmd.kind:
		Command.Kind.MOVE:
			actor.move_input = args.get("dir", Vector2.ZERO)
		Command.Kind.MINE:
			var tile: Vector2i = args.get("tile", Drone.NO_TILE)
			if tile == Drone.NO_TILE:
				actor.stop_mining()
			else:
				actor.set_mine_target(tile)
		Command.Kind.BUILD:
			_execute_build(cmd, player, world)
		Command.Kind.REMOVE:
			_execute_remove(cmd, world)
		Command.Kind.ROTATE:
			var b := world.buildings.get_by_id(int(args.get("id", 0)))
			if b != null:
				world.rotate_building(b, int(args.get("delta", 1)))
		Command.Kind.CONFIGURE:
			var b := world.buildings.get_by_id(int(args.get("id", 0)))
			if b != null:
				world.configure(b, args.get("value", null))
		Command.Kind.TAKE:
			var b := world.buildings.get_by_id(int(args.get("id", 0)))
			if b != null:
				world.player_take(b, int(args.get("item", -1)), int(args.get("amount", 0)))
		Command.Kind.PUT:
			var b := world.buildings.get_by_id(int(args.get("id", 0)))
			if b != null:
				world.player_put(b, int(args.get("item", -1)), int(args.get("amount", 0)))
		Command.Kind.TAKE_OUTPUT:
			var b := world.buildings.get_by_id(int(args.get("id", 0)))
			if b != null:
				world.player_take_output(b)
		Command.Kind.FILL:
			var b := world.buildings.get_by_id(int(args.get("id", 0)))
			if b != null:
				world.player_fill(b)
		Command.Kind.CRAFT:
			# Рецепт ручного крафта опознаётся по предмету, который он делает.
			var recipe := Registry.get_hand_recipe(int(args.get("item", -1)))
			if recipe != null:
				actor.crafting.enqueue(recipe, int(args.get("count", 1)))
		Command.Kind.CRAFT_CANCEL:
			var recipe := Registry.get_hand_recipe(int(args.get("item", -1)))
			if recipe != null:
				actor.crafting.cancel_last(recipe, int(args.get("count", 1)))
		Command.Kind.RESEARCH_SELECT:
			research.set_active(StringName(args.get("research", "")))
		Command.Kind.RESEARCH_QUEUE:
			var id := StringName(args.get("research", ""))
			if research.queue_position(id) > 0:
				research.queue_remove(id)
			else:
				research.queue_add(id)
		Command.Kind.RESEARCH_DEPOSIT:
			research.deposit_manual(actor.inventory, cmd.player)
		Command.Kind.USE_PASSAGE:
			use_gateway(actor)
		Command.Kind.TELEPORT:
			var node := int(args.get("node", -1))
			if node < 0:
				cancel_teleport()
			else:
				start_teleport(node)
		Command.Kind.CREATIVE_WAVE:
			call_creative_wave()
		Command.Kind.CREATIVE_THREAT:
			set_creative_threat(bool(args.get("on", true)))
		Command.Kind.RESEARCH_RESET:
			research.reset_progress()
			apply_research_effects()
		Command.Kind.RESEARCH_UNLOCK:
			research.unlock_everything()
			apply_research_effects()
		Command.Kind.CREATIVE_GIVE:
			var item := int(args.get("item", -1))
			if world.creative and item >= 0 and item < Registry.stack_sizes.size():
				actor.inventory.add(item, clampi(int(args.get("count", 1)), 1, 1000))


## Постройка списком: одно действие игрока (клик или протягивание) — одна команда.
## Мосты, поставленные подряд, связываются между собой и с прошлым мостом игрока.
func _execute_build(cmd: Command, player: Player, world: GameWorld) -> void:
	var mine := cmd.player == local_player
	var built: Array[Building] = []
	var no_item := ""
	var out_of_range := false
	var inventory_full := false
	for entry in (cmd.args.get("places", []) as Array):
		var place: Dictionary = entry
		var def := Registry.get_building(StringName(place.get("def", "")))
		if def == null:
			continue
		var origin: Vector2i = place.get("origin", Vector2i.ZERO)
		var rotation := int(place.get("rotation", 0))
		var check := world.check_build(def, origin, rotation)
		if check == BuildingManager.Check.NO_ITEM:
			no_item = def.name_key
			continue
		if check == BuildingManager.Check.OUT_OF_RANGE:
			out_of_range = true
			continue
		var b := world.build(def, origin, rotation, place.get("config", null))
		if b != null:
			built.append(b)
		elif world.last_error == GameWorld.ActionError.INVENTORY_FULL:
			inventory_full = true
	if command_router.is_valid():
		NetLog.write("мир", "тик %d: игрок %d строит — поставлено %d из %d%s%s%s" % [get_tick(), cmd.player,
			built.size(), (cmd.args.get("places", []) as Array).size(),
			(", нет предмета " + tr(no_item)) if not no_item.is_empty() else "",
			", далеко" if out_of_range else "", ", инвентарь полон" if inventory_full else ""])
	if bool(cmd.args.get("link_bridges", false)):
		_link_bridges(player, built, cmd.args.get("config", null) != null)
	if not mine:
		return
	if inventory_full:
		Events.toast(tr("TOAST_INVENTORY_FULL"), Events.ToastKind.WARNING)
	elif not no_item.is_empty():
		Events.toast(tr("TOAST_NO_ITEM") % tr(no_item), Events.ToastKind.WARNING)
	elif out_of_range and built.is_empty():
		Events.toast(tr("TOAST_OUT_OF_RANGE"), Events.ToastKind.WARNING)


## Связать только что поставленные мосты в цепочку (если игрок не нёс в руке готовую настройку).
func _link_bridges(player: Player, built: Array[Building], has_config: bool) -> void:
	var bridges: Array[BridgeConveyor] = []
	for b in built:
		if b is BridgeConveyor:
			bridges.append(b)
	if bridges.is_empty():
		return
	if not has_config:
		var last := player.last_bridge
		if last != null and last.world != null and last.link == Vector2i.ZERO and last.can_link_to(bridges[0]):
			last.world.configure(last, bridges[0].origin - last.origin)
		for i in bridges.size() - 1:
			if bridges[i].can_link_to(bridges[i + 1]):
				bridges[i].world.configure(bridges[i], bridges[i + 1].origin - bridges[i].origin)
	player.last_bridge = bridges[bridges.size() - 1]


## Снос списком: подсказки о причинах — только тому, кто сносил.
func _execute_remove(cmd: Command, world: GameWorld) -> void:
	var out_of_range := 0
	var inventory_full := 0
	var lost := 0
	for id in (cmd.args.get("ids", PackedInt32Array()) as PackedInt32Array):
		var b := world.buildings.get_by_id(id)
		if b == null:
			continue
		if world.demolish(b):
			lost += world.last_lost_items
		elif world.last_error == GameWorld.ActionError.OUT_OF_RANGE:
			out_of_range += 1
		elif world.last_error == GameWorld.ActionError.INVENTORY_FULL:
			inventory_full += 1
	if cmd.player != local_player:
		return
	if inventory_full > 0:
		Events.toast(tr("TOAST_INVENTORY_FULL"), Events.ToastKind.WARNING)
	elif out_of_range > 0:
		Events.toast(tr("TOAST_OUT_OF_RANGE"), Events.ToastKind.WARNING)
	if lost > 0:
		Events.toast(tr("TOAST_ITEMS_LOST") % lost, Events.ToastKind.WARNING)


func step() -> void:
	_apply_commands()
	_balance_fluids()
	_balance_power()
	planet.simulation.step()
	base.simulation.step()
	research.step(_manual_kits())
	if planet.breached:
		emergency_teleport()
	elif has_time_limit() and get_planet_ticks() >= get_planet_time_ticks():
		# Время на планете вышло: улетаем сами, как при прорыве — уцелеет площадка и то,
		# что у игроков в инвентарях.
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
func get_passage(who: Drone = null) -> Building:
	var d := who if who != null else drone
	if d == null or d.dead or d.world == null:
		return null
	var gate := get_gateway(d.world)
	if gate != null and gate.world != null and gate.get_world_rect().has_point(d.position):
		return gate
	var lift := d.world.buildings.get_at(d.get_tile()) as Lift
	return lift if lift != null and lift.pair != null else null


## «Порты шлюза II» растят оба шлюза с 2×2 до 4×4, центр остаётся на месте.
func _grow_gateways() -> void:
	var size := _gateway_size()
	for world in [planet, base]:
		if world == null or world.buildings == null:
			continue
		var gate := get_gateway(world)
		if gate != null and gate.world == world and gate.get_size() != size:
			world.buildings.resize_building(gate, size)
			world.gateway = gate


## Дрон над проходом между этажами (переход может быть закрыт исследованием).
func is_over_gateway(who: Drone = null) -> bool:
	return get_passage(who) != null


## Дрон над проходом и подземный этаж открыт — можно пройти на другой этаж.
func can_use_gateway(who: Drone = null) -> bool:
	return is_over_gateway(who) and is_underground_open()


## Переносит дрона через шлюз или лифт: он оказывается над парой на другом этаже в той же точке.
func use_gateway(who: Drone = null) -> bool:
	var d := who if who != null else drone
	if not can_use_gateway(d):
		return false
	var from := get_passage(d)
	var to: Building = (from as Lift).pair if from is Lift else get_gateway(base if d.world == planet else planet)
	var to_world := to.world
	var offset := d.position - from.get_world_center()
	d.stop_mining()
	d.move_to_world(to_world)
	d.position = to.get_world_center() + offset
	d.prev_position = d.position
	d.move_input = Vector2.ZERO
	if d == drone:
		drone_changed_world.emit()
	return true


# --- Телепорт ---

## Сколько времени мира можно пробыть на планете (тиков). Исследования «Запас хода» прибавляют.
func get_planet_time_ticks() -> int:
	var seconds := run_def.planet_time_seconds \
		+ run_def.planet_time_step_seconds * research.count_effect(&"planet_time")
	return maxi(1, roundi(seconds * GameConst.TICK_RATE))


## Перезарядка телепорта после прибытия (тиков). Исследования «Разгон телепорта» сокращают.
func get_teleport_cooldown_ticks() -> int:
	var seconds := run_def.teleport_cooldown_seconds \
		- run_def.teleport_cooldown_step_seconds * research.count_effect(&"teleport_charge")
	return maxi(0, roundi(maxf(seconds, run_def.teleport_cooldown_min_seconds) * GameConst.TICK_RATE))


## Сколько времени мира прошло на этой планете (тиков).
func get_planet_ticks() -> int:
	return planet.simulation.tick - planet_arrival_tick if planet != null else 0


## Сколько осталось до принудительного вылета, секунд (0 — время вышло).
func get_planet_seconds_left() -> float:
	return maxf(float(get_planet_time_ticks() - get_planet_ticks()) / GameConst.TICK_RATE, 0.0)


## Сколько осталось до конца перезарядки телепорта, секунд (0 — можно лететь).
func get_teleport_ready_seconds() -> float:
	return maxf(float(get_teleport_cooldown_ticks() - get_planet_ticks()) / GameConst.TICK_RATE, 0.0)


## Телепорт перезарядился и готов к старту.
func is_teleport_ready() -> bool:
	return get_planet_ticks() >= get_teleport_cooldown_ticks()


## Действует ли предел пребывания. В творческом режиме — только вместе с волнами: песочница
## не должна выкидывать с планеты посреди опытов.
func has_time_limit() -> bool:
	return planet != null and (not creative or planet.threat != null)


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
	if is_charging() or not star_map.can_travel_to(node_id) or not is_teleport_ready():
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
	# Кто из игроков летит с планетой и куда его поставить у нового шлюза.
	var travelers: Array[Dictionary] = []
	for p in players:
		if p.drone.world != old:
			continue
		var offset := p.drone.position - old_gate.get_world_center() if old_gate != null else Vector2.ZERO
		travelers.append({"drone": p.drone, "offset": offset, "on_pad": pad.has_point(p.drone.get_tile())})
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
	var fresh := GameWorld.create(null, map, creative, null, false)
	fresh.research = research
	# Пары лифтов свяжутся, когда новая планета станет текущей (шлюз и площадка уже на месте).
	_pairing_suspended = true
	attach_world(fresh)
	fresh.simulation.tick = base.simulation.tick
	var center := Vector2i(map.width / 2, map.height / 2)
	var fresh_def := Registry.get_building(&"central_gateway") as GatewayDef
	var new_gate := fresh.place_gateway(fresh_def,
		GameWorld.gateway_origin(fresh_def, center, _gateway_size()), gate_rotation)
	fresh.resize_pad(_pad_around(new_gate))
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

	for traveler in travelers:
		var moved: Drone = traveler["drone"]
		moved.stop_mining()
		moved.move_to_world(fresh)
		var target := new_gate.get_world_center() + ((traveler["offset"] as Vector2) if traveler["on_pad"] else Vector2.ZERO)
		moved.position = target
		moved.prev_position = target
		moved.move_input = Vector2.ZERO

	_setup_threat(fresh, node, fresh.simulation.tick)
	old.dispose()
	planet = fresh
	# Новая планета должна знать, чей дрон «свой»: иначе интерфейс покажет дрона по умолчанию —
	# первого игрока. У клиента это был хост: инвентарь на экране чужой, а тратится свой.
	var me := get_player(local_player)
	if me != null:
		fresh.view_drone = me.drone
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
	world.run = self
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
	for p in players:
		if p.last_bridge == building:
			p.last_bridge = null
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
	var center := gate.origin + Vector2i.ONE * (gate.get_size() / 2)
	return Rect2i(center - Vector2i.ONE * (size / 2), Vector2i(size, size))


## Сторона шлюза по исследованиям «Порты шлюза».
func _gateway_size() -> int:
	var def := Registry.get_building(&"central_gateway") as GatewayDef
	if def == null:
		return 2
	var steps := ResearchState.max_effect(&"gateway_ports")
	return def.grown_size if steps > 0 and research != null and research.count_effect(&"gateway_ports") >= steps else def.start_size


func dispose() -> void:
	if link != null:
		link.dispose()
	if planet != null:
		planet.dispose()
	if base != null:
		base.dispose()
	if planet != null:
		planet.run = null
	if base != null:
		base.run = null
	planet = null
	base = null
	players.clear()
