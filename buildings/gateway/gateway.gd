class_name GatewayBuilding
extends Building
## Центральный шлюз на планете и его пара на подземном этаже — зеркальные порты между мирами (GatewayLink).
## На планете входы (inbound_side) принимают предметы в очередь «в базу», выходы (outbound_side)
## отдают очередь «наружу». На этаже на тех же сторонах наоборот. Каждый выходной порт отдаёт не чаще,
## чем лента порта; очередь вмещает buffer_capacity на каждый открытый порт.
## Предмет принимается только от здания, стоящего на тайле открытого входного порта.
## Передача предметов открывается исследованием (эффект gateway_items), ещё порты — «Порты шлюза».
## Шлюз и пара поворачиваются независимо (R): стороны портов поворачиваются вместе со зданием.
## Через шлюз проходит дрон (Run.use_gateway).

var link: GatewayLink
## Тик, не раньше которого может отдать каждый выходной порт.
var _next_out := PackedInt32Array()


## Через сколько тиков шлюз (или лифт) выпускает следующий предмет с учётом ветки «Разгон шлюза».
static func throughput_ticks(base: int, world: GameWorld) -> int:
	var steps := world.research.count_effect(&"gateway_speed") if world != null and world.research != null else 0
	return maxi(1, roundi(float(base) / (1.0 + 0.5 * steps)))


func get_throughput_ticks() -> int:
	return throughput_ticks(get_gateway_def().get_ticks_per_item(), world)


func get_gateway_def() -> GatewayDef:
	return def as GatewayDef


func is_in_base() -> bool:
	return get_gateway_def().in_base


## Сторона, через которую предметы входят в это здание (с учётом поворота).
func get_input_side() -> int:
	var d := get_gateway_def()
	return posmod((d.outbound_side if d.in_base else d.inbound_side) + rotation, 4)


## Сторона, через которую предметы выходят из этого здания (с учётом поворота).
func get_output_side() -> int:
	var d := get_gateway_def()
	return posmod((d.inbound_side if d.in_base else d.outbound_side) + rotation, 4)


func get_input_tile() -> Vector2i:
	return get_gateway_def().get_port_tile(origin, get_size(), get_input_side())


func get_output_tile() -> Vector2i:
	return get_gateway_def().get_port_tile(origin, get_size(), get_output_side())


## Шлюз начинает забег стороной start_size и вырастает до grown_size, когда открыты все «Порты шлюза».
func get_initial_size() -> int:
	var d := get_gateway_def()
	if world == null or world.research == null:
		return d.start_size
	var steps := ResearchState.max_effect(&"gateway_ports")
	return d.grown_size if steps > 0 and world.research.count_effect(&"gateway_ports") >= steps else d.start_size


## Передаёт ли шлюз предметы (исследование «Передача предметов»; вне забега — всегда).
func items_enabled() -> bool:
	return world == null or world.research == null or world.research.has_effect(&"gateway_items")


## Сколько портов открыто на каждой стороне (1 + исследования «Порты шлюза», не больше стороны здания).
func port_count() -> int:
	var extra := world.research.count_effect(&"gateway_ports") if world != null and world.research != null else 0
	return clampi(1 + extra, 1, get_size())


## Шлюз соединяет электросети этажей (исследование «Передача энергии»).
func is_power_link() -> bool:
	return link != null and world != null and world.research != null and world.research.has_effect(&"gateway_power")


func fluids_enabled() -> bool:
	return link != null and world != null and world.research != null and world.research.has_effect(&"gateway_fluids")


## Сторона порта жидкости: relative 1 и 3 — стороны, свободные от портов предметов (с учётом поворота).
## Пара зеркальна: порт relative шлюза соединён с портом relative пары.
func get_fluid_side(relative: int) -> int:
	return posmod(get_gateway_def().inbound_side + relative + rotation, 4)


## Порты жидкостей на двух свободных сторонах — две отдельные сети (исследование «Передача жидкостей»).
func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	if fluids_enabled():
		for relative in [1, 3]:
			ports.append(FluidGraph.Port.new(get_fluid_side(relative), null, relative))
	return ports


func get_input_tiles() -> Array[Vector2i]:
	return get_gateway_def().get_port_tiles(origin, get_size(), get_input_side(), port_count())


func get_output_tiles() -> Array[Vector2i]:
	return get_gateway_def().get_port_tiles(origin, get_size(), get_output_side(), port_count())


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


func on_rotated(_old_rotation: int) -> void:
	# Выход сменил сторону: ждавшие у старого порта ленты должны проверить обстановку.
	notify_space()
	wake()
	world.fluids.mark_dirty()


## Клик по шлюзу открывает окно телепорта.
func has_player_window() -> bool:
	return true


func save_state() -> Dictionary:
	return {"next_out": _next_out.duplicate()}


func load_state(state: Dictionary) -> void:
	var value: Variant = state.get("next_out", PackedInt32Array())
	_next_out = value if value is PackedInt32Array else PackedInt32Array()
	wake()


func accept_item(source: Building, _item: int) -> bool:
	if link == null or source == null or not items_enabled():
		return false
	var from_port := false
	for tile in get_input_tiles():
		if source.occupies(tile):
			from_port = true
			break
	return from_port and link.size_of(not is_in_base()) < link.capacity * port_count()


func handle_item(_source: Building, item: int) -> void:
	link.push(not is_in_base(), item)
	var other := link.other(self)
	if other != null and other.world != null:
		other.wake()


func update_tick(tick: int) -> bool:
	if link == null:
		return false
	var to_base := is_in_base()
	if link.size_of(to_base) == 0:
		# Проснёмся, когда другая сторона положит предмет в очередь.
		return false
	if not items_enabled():
		return false
	var tiles := get_output_tiles()
	if _next_out.size() != tiles.size():
		_next_out.resize(tiles.size())
	var soonest := 1 << 30
	var gave := false
	for k in tiles.size():
		if link.size_of(to_base) == 0:
			break
		if tick < _next_out[k]:
			soonest = mini(soonest, _next_out[k])
			continue
		var target := world.buildings.get_at(tiles[k])
		if target == null:
			# Выхода нет — ждём, пока рядом что-нибудь построят (on_proximity_changed).
			continue
		var item := link.peek(to_base)
		if not target.accept_item(self, item):
			wait_for(target)
			continue
		link.pop(to_base)
		target.handle_item(self, item)
		_next_out[k] = tick + get_throughput_ticks()
		soonest = mini(soonest, _next_out[k])
		gave = true
	if gave:
		# В очереди освободилось место — ленты у входов другой стороны могут отдавать дальше.
		var other := link.other(self)
		if other != null and other.world != null:
			other.notify_space()
	if link.size_of(to_base) > 0 and soonest < (1 << 30):
		sleep_until(soonest)
	return false


func get_info_lines() -> PackedStringArray:
	if link == null:
		return PackedStringArray()
	if not items_enabled():
		return PackedStringArray([tr("INFO_GATEWAY_ITEMS_LOCKED") % tr(Registry.get_research(&"gateway_items").name_key)])
	var limit := link.capacity * port_count()
	return PackedStringArray([
		tr("INFO_GATEWAY_TO_BASE") % [link.size_of(true), limit],
		tr("INFO_GATEWAY_TO_PLANET") % [link.size_of(false), limit],
		tr("INFO_GATEWAY_PORTS") % port_count(),
	])
