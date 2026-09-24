class_name Shaft
extends Building
## Шахта между подземным этажом и этажом добычи: пара зданий в середине обоих этажей.
## Ставится сама, когда открыт этаж добычи, и не сносится — это единственный путь вниз.
##
## Как лифт: один вход и один выход (середины противоположных сторон), направление —
## общая настройка пары (вниз, на этаж добычи, или вверх, к базе). Дрон переходит по F.
## Ток и жидкости через шахту не идут: этаж добычи живёт на своих проводах и трубах.

enum Direction { DOWN, UP }

var pair: Shaft
var direction: int = Direction.DOWN
## Предметы, ждущие перехода (хранятся в шахте исходного этажа).
var buffer := PackedInt32Array()
var _next_out: int = 0


func get_shaft_def() -> LiftDef:
	return def as LiftDef


## Этот конец принимает предметы: вниз грузят наверху, вверх — внизу.
func is_source() -> bool:
	if world == null or world.run == null:
		return false
	var on_mining := world == world.run.mining
	return (direction == Direction.DOWN) != on_mining


func get_input_side() -> int:
	return posmod(rotation + 2, 4)


func get_output_side() -> int:
	return rotation


func get_input_tile() -> Vector2i:
	return _side_tile(get_input_side())


func get_output_tile() -> Vector2i:
	return _side_tile(get_output_side())


func _side_tile(side: int) -> Vector2i:
	var size := get_size()
	var middle := size / 2
	match posmod(side, 4):
		GameConst.Dir.RIGHT:
			return origin + Vector2i(size, middle)
		GameConst.Dir.DOWN:
			return origin + Vector2i(middle, size)
		GameConst.Dir.LEFT:
			return origin + Vector2i(-1, middle)
		_:
			return origin + Vector2i(middle, -1)


func on_placed() -> void:
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
	if not source.occupies(get_input_tile()):
		return false
	return buffer.size() < get_shaft_def().buffer_capacity


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
	var target := world.buildings.get_at(get_output_tile())
	var item: int = pair.buffer[0]
	if target == null or not target.accept_item(self, item):
		if target != null:
			wait_for(target)
		else:
			wait_for_proximity()
		return false
	target.handle_item(self, item)
	pair.buffer.remove_at(0)
	pair.notify_space()
	_next_out = tick + get_shaft_def().get_ticks_per_item()
	if not pair.buffer.is_empty():
		sleep_until(_next_out)
	return false


# --- Настройка ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.MODE


func get_config() -> Variant:
	return direction


## Направление пары: при смене буфер переезжает в шахту нового исходного этажа.
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


func collect_contents(out: PackedInt32Array) -> void:
	for item in buffer:
		out[item] += 1


func save_state() -> Dictionary:
	return {"buffer": buffer.duplicate(), "next_out": _next_out, "direction": direction}


func load_state(state: Dictionary) -> void:
	buffer = SaveContext.items(state.get("buffer", PackedInt32Array()))
	_next_out = int(state.get("next_out", 0))
	direction = clampi(int(state.get("direction", Direction.DOWN)), Direction.DOWN, Direction.UP)
	wake()


func get_info_lines() -> PackedStringArray:
	var waiting := buffer.size() if is_source() else (pair.buffer.size() if pair != null else 0)
	return PackedStringArray([tr("INFO_SHAFT_QUEUE") % [waiting, get_shaft_def().buffer_capacity]])
