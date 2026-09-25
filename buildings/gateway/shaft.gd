class_name Shaft
extends Building
## Шахта с подземного этажа вниз: на этаж добычи и в котельную. Пара зданий 4×4, стоит сама,
## когда этаж открыт исследованием, и не сносится — это единственный путь туда.
##
## Порты как у центрального шлюза: четыре входа на одной стороне и четыре выхода на противоположной,
## k-й выход отдаёт то, что вошло в k-й вход пары. Направление (вниз или вверх) — общая настройка пары,
## дрон переходит по F. Ток и жидкости идут только через шахту котельной (LiftDef.energy_link):
## этаж добычи живёт на своих проводах и трубах.

enum Direction { DOWN, UP }

var pair: Shaft
var direction: int = Direction.DOWN
## Очереди по портам (хранятся в шахте исходного этажа): buffers[k] — то, что вошло в k-й вход.
var buffers: Array[PackedInt32Array] = []
## Тик, не раньше которого отдаёт каждый выходной порт.
var _next_out := PackedInt32Array()


func get_shaft_def() -> LiftDef:
	return def as LiftDef


## Сколько портов у шахты — по тайлу на сторону.
func port_count() -> int:
	return get_size()


func _ensure_buffers() -> void:
	if buffers.size() == port_count():
		return
	while buffers.size() < port_count():
		buffers.append(PackedInt32Array())
	buffers.resize(port_count())


## Этот конец принимает предметы: вниз грузят наверху, вверх — внизу.
## Какой конец нижний, решает номер этажа — шахт в забеге две (добыча и котельная).
func is_source() -> bool:
	if world == null or world.run == null or pair == null or pair.world == null:
		return false
	var deeper := world.run.floor_of(world) > world.run.floor_of(pair.world)
	return (direction == Direction.DOWN) != deeper


func get_input_side() -> int:
	return posmod(rotation + 2, 4)


func get_output_side() -> int:
	return rotation


func get_input_tiles() -> Array[Vector2i]:
	return GatewayDef.get_port_tiles(origin, get_size(), get_input_side(), port_count())


func get_output_tiles() -> Array[Vector2i]:
	return GatewayDef.get_port_tiles(origin, get_size(), get_output_side(), port_count())


func get_input_tile() -> Vector2i:
	var tiles := get_input_tiles()
	return tiles[0] if not tiles.is_empty() else origin


func get_output_tile() -> Vector2i:
	var tiles := get_output_tiles()
	return tiles[0] if not tiles.is_empty() else origin


## Номер порта, к которому примыкает сосед (−1 — сосед не у порта).
func input_port_of(source: Building) -> int:
	if source == null:
		return -1
	var tiles := get_input_tiles()
	for k in tiles.size():
		if source.occupies(tiles[k]):
			return k
	return -1


## Шахта котельной проводит ток: её концы сшивают электросети своих этажей.
func is_power_link() -> bool:
	return pair != null and get_shaft_def().energy_link


## И трубы: все четыре стороны — одна сеть, общая с шахтой другого этажа.
func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	if not get_shaft_def().energy_link:
		return ports
	for side in 4:
		ports.append(FluidGraph.Port.new(side, null, 0))
	return ports


func on_placed() -> void:
	_ensure_buffers()
	wake()


func on_proximity_changed() -> void:
	wake()


func on_rotated(_old_rotation: int) -> void:
	if pair != null and pair.rotation != rotation and pair.world != null:
		pair.world.buildings.rotate(pair, rotation)
	notify_space()
	wake()


func accept_item(source: Building, _item: int) -> bool:
	if pair == null or source is Shaft or not is_source():
		return false
	var port := input_port_of(source)
	if port < 0:
		return false
	_ensure_buffers()
	return buffers[port].size() < get_shaft_def().buffer_capacity


func handle_item(source: Building, item: int) -> void:
	_ensure_buffers()
	buffers[maxi(input_port_of(source), 0)].append(item)
	if pair != null:
		pair.wake()


func update_tick(tick: int) -> bool:
	if pair == null or is_source():
		return false
	pair._ensure_buffers()
	if pair.total_waiting() == 0:
		# Проснёмся, когда на том конце что-нибудь положат в очередь.
		return false
	var tiles := get_output_tiles()
	if _next_out.size() != tiles.size():
		_next_out.resize(tiles.size())
	var soonest := 1 << 30
	var gave := false
	# У каждого порта своя очередь: k-й выход отдаёт то, что вошло в k-й вход пары.
	for k in tiles.size():
		if k >= pair.buffers.size() or pair.buffers[k].is_empty():
			continue
		if tick < _next_out[k]:
			soonest = mini(soonest, _next_out[k])
			continue
		var target := world.buildings.get_at(tiles[k])
		var item: int = pair.buffers[k][0]
		if target == null or not target.accept_item(self, item):
			if target != null:
				wait_for(target)
			else:
				wait_for_proximity()
			continue
		target.handle_item(self, item)
		pair.buffers[k].remove_at(0)
		pair.notify_space()
		_next_out[k] = tick + get_shaft_def().get_ticks_per_item()
		soonest = mini(soonest, _next_out[k])
		gave = true
	if gave or soonest < 1 << 30:
		sleep_until(soonest if soonest < 1 << 30 else tick + 1)
	return false


## Сколько предметов ждёт перехода в этой шахте.
func total_waiting() -> int:
	var sum := 0
	for queue in buffers:
		sum += queue.size()
	return sum


# --- Настройка ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.MODE


func get_config() -> Variant:
	return direction


## Направление пары: при смене очереди переезжают в шахту нового исходного этажа.
func set_config(value: Variant) -> void:
	var next := clampi(int(value), Direction.DOWN, Direction.UP) if value is int else Direction.DOWN
	if next == direction:
		return
	direction = next
	if pair != null and pair.direction != next:
		pair.direction = next
		_ensure_buffers()
		pair._ensure_buffers()
		var waiting: Array[PackedInt32Array] = []
		for k in port_count():
			var queue := PackedInt32Array()
			queue.append_array(buffers[k])
			if k < pair.buffers.size():
				queue.append_array(pair.buffers[k])
			waiting.append(queue)
			buffers[k] = PackedInt32Array()
			pair.buffers[k] = PackedInt32Array()
		var source := self if is_source() else pair
		source.buffers = waiting
		pair.wake()
		pair.notify_space()
		if pair.world != null:
			pair.world.buildings.notify_changed(pair)
	notify_space()
	wake()


func has_player_window() -> bool:
	return true


func collect_contents(out: PackedInt32Array) -> void:
	for queue in buffers:
		for item in queue:
			out[item] += 1


func save_state() -> Dictionary:
	var queues: Array[PackedInt32Array] = []
	for queue in buffers:
		queues.append(queue.duplicate())
	return {"buffers": queues, "next_out": _next_out.duplicate(), "direction": direction}


func load_state(state: Dictionary) -> void:
	buffers.clear()
	if state.has("buffers"):
		for queue in (state.get("buffers") as Array):
			buffers.append(SaveContext.items(queue))
	elif state.has("buffer"):
		# Старое сохранение: очередь была одна на шахту — отдаём её первому порту.
		buffers.append(SaveContext.items(state.get("buffer", PackedInt32Array())))
	_ensure_buffers()
	var value: Variant = state.get("next_out", PackedInt32Array())
	_next_out = value if value is PackedInt32Array else PackedInt32Array()
	direction = clampi(int(state.get("direction", Direction.DOWN)), Direction.DOWN, Direction.UP)
	wake()


func get_info_lines() -> PackedStringArray:
	var waiting := total_waiting() if is_source() else (pair.total_waiting() if pair != null else 0)
	return PackedStringArray([tr("INFO_SHAFT_QUEUE") % [waiting, get_shaft_def().buffer_capacity * port_count()]])
