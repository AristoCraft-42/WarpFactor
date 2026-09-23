class_name Lift
extends Building
## Лифт между площадкой шлюза (планета) и подземным этажом: пара лифтов стоит в одном и том же месте
## относительно шлюза на обоих этажах. Пары связывает забег (Run); лифт без пары ничего не делает.
## Направление — настройка, общая для пары: вниз (площадка → этаж) или вверх (этаж → площадка).
## Лифт на исходном этаже принимает предметы от соседей в буфер, лифт на другом этаже отдаёт их соседям
## по кругу не чаще, чем лента. Ток и жидкости проходят, если открыты «Передача энергии» и
## «Передача жидкостей». Дрон переходит по F (Run.use_gateway).

enum Direction { DOWN, UP }

var pair: Lift
var direction: int = Direction.DOWN
## Предметы, ждущие перехода (хранятся в лифте исходного этажа).
var buffer := PackedInt32Array()
var _next_out: int = 0


func get_lift_def() -> LiftDef:
	return def as LiftDef


## Этот лифт принимает предметы (его этаж — исходный для направления).
func is_source() -> bool:
	if world == null:
		return false
	return (direction == Direction.DOWN) != world.is_base


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


func accept_item(source: Building, _item: int) -> bool:
	return pair != null and not (source is Lift) and is_source() and buffer.size() < get_lift_def().buffer_capacity


func handle_item(_source: Building, item: int) -> void:
	buffer.append(item)
	if pair != null:
		pair.wake()


func update_tick(tick: int) -> bool:
	if pair == null or is_source() or pair.buffer.is_empty():
		return false
	if tick < _next_out:
		sleep_until(_next_out)
		return false
	if not dump(pair.buffer[0]):
		wait_for_proximity()
		return false
	pair.buffer.remove_at(0)
	pair.notify_space()
	_next_out = tick + GatewayBuilding.throughput_ticks(get_lift_def().get_ticks_per_item(), world)
	if not pair.buffer.is_empty():
		sleep_until(_next_out)
	return false


# --- Связь этажей ---

func is_power_link() -> bool:
	return pair != null and world != null and world.research != null and world.research.has_effect(&"gateway_power")


## Все стороны — одна сеть труб, общая с лифтом другого этажа (если открыта «Передача жидкостей»).
func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	if pair == null or world == null or world.research == null or not world.research.has_effect(&"gateway_fluids"):
		return ports
	for side in 4:
		ports.append(FluidGraph.Port.new(side, null, 0))
	return ports


# --- Настройка ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.MODE


func get_config() -> Variant:
	return direction


## Направление пары: при смене буфер переезжает в лифт нового исходного этажа.
func set_config(value: Variant) -> void:
	var next := clampi(int(value), Direction.DOWN, Direction.UP) if value is int else Direction.DOWN
	if next == direction:
		return
	direction = next
	if pair != null and pair.direction != next:
		pair.direction = next
		var waiting := PackedInt32Array()
		waiting.append_array(buffer)
		waiting.append_array(pair.buffer)
		buffer.clear()
		pair.buffer.clear()
		var source := self if is_source() else pair
		source.buffer = waiting
		pair.wake()
		pair.notify_space()
		if pair.world != null:
			pair.world.buildings.notify_changed(pair)
	notify_space()
	wake()


func has_player_window() -> bool:
	return true


func save_state() -> Dictionary:
	return {"buffer": buffer.duplicate(), "next_out": _next_out}


func load_state(state: Dictionary) -> void:
	buffer = SaveContext.items(state.get("buffer", PackedInt32Array()))
	_next_out = int(state.get("next_out", 0))
	wake()


## При сносе возвращается и то, что ждёт в паре (пару забег сносит вместе с этим лифтом).
func collect_contents(out: PackedInt32Array) -> void:
	for item in buffer:
		out[item] += 1
	if pair != null:
		for item in pair.buffer:
			out[item] += 1


func get_display_item() -> int:
	return -1


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if pair == null:
		lines.append(tr("INFO_LIFT_NO_PAIR"))
		return lines
	lines.append(tr("INFO_LIFT_DOWN") if direction == Direction.DOWN else tr("INFO_LIFT_UP"))
	var source := self if is_source() else pair
	lines.append(tr("INFO_LIFT_BUFFER") % [source.buffer.size(), get_lift_def().buffer_capacity])
	return lines


func get_window_sections() -> Array[WindowSection]:
	var source := self if is_source() or pair == null else pair
	var stacks: Array[Vector2i] = []
	var counts := {}
	var order: Array[int] = []
	for item in source.buffer:
		if not counts.has(item):
			counts[item] = 0
			order.append(item)
		counts[item] = int(counts[item]) + 1
	for item in order:
		stacks.append(Vector2i(item, int(counts[item])))
	if stacks.is_empty():
		stacks.append(Vector2i(-1, 0))
	var cap := get_lift_def().buffer_capacity
	return [WindowSection.slots(tr("WINDOW_LIFT_QUEUE"), stacks, PackedInt32Array(), false),
		WindowSection.bar(tr("WINDOW_LIFT_LOAD"), float(source.buffer.size()) / maxi(cap, 1), "%d / %d" % [source.buffer.size(), cap])]
