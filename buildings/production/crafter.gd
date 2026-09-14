class_name Crafter
extends Building
## Завод по рецепту (CrafterDef.recipe). Принимает только входы рецепта в свой буфер,
## в начале цикла списывает их, в конце кладёт результат в выходной буфер и раздаёт соседям.
## Во время цикла спит до его окончания; без сырья — до прихода предмета; с полным выходом —
## до освобождения места у соседей.

var inputs: PackedInt32Array = PackedInt32Array()
var outputs: PackedInt32Array = PackedInt32Array()
var crafting: bool = false
var start_tick: int = 0
var finish_tick: int = 0
var status: Status = Status.IDLE

var _output_cursor: int = 0


func _init() -> void:
	inputs.resize(Registry.items.size())
	inputs.fill(0)
	outputs.resize(Registry.items.size())
	outputs.fill(0)


func get_recipe() -> Recipe:
	return (def as CrafterDef).recipe


func get_output_capacity() -> int:
	return (def as CrafterDef).item_capacity


func get_input_capacity(item: int) -> int:
	var capacity := 0
	for c in get_recipe().consumes:
		capacity = maxi(capacity, c.item_capacity(item, (def as CrafterDef).item_capacity))
	return capacity


## Доля выполнения текущего цикла (0..1) на тике tick.
func get_progress(tick: int) -> float:
	if not crafting or finish_tick <= start_tick:
		return 0.0
	return clampf(float(tick - start_tick) / (finish_tick - start_tick), 0.0, 1.0)


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


func accept_item(_source: Building, item: int) -> bool:
	var recipe := get_recipe()
	return recipe != null and recipe.accepts_item(item) and inputs[item] < get_input_capacity(item)


func handle_item(_source: Building, item: int) -> void:
	inputs[item] += 1
	if not crafting:
		wake()


func update_tick(tick: int) -> bool:
	var recipe := get_recipe()
	if recipe == null:
		return false

	if crafting and tick >= finish_tick:
		if _outputs_free(recipe):
			for p in recipe.produces:
				p.produce(self, world.rng)
			crafting = false
			# Разгрузчики, ждущие продукцию.
			if world.simulation.has_waiters(id):
				notify_space()
		else:
			status = Status.OUTPUT_BLOCKED

	if not crafting:
		if not _inputs_ready(recipe):
			status = Status.NO_INPUT
		elif not _outputs_free(recipe):
			status = Status.OUTPUT_BLOCKED
		else:
			for c in recipe.consumes:
				c.consume(self)
			crafting = true
			start_tick = tick
			finish_tick = tick + maxi(1, ceili(recipe.get_craft_ticks() / _efficiency(recipe)))
			status = Status.WORKING
			# Во входном буфере освободилось место.
			notify_space()

	var dumped := _dump_one()
	var has_outputs := _has_outputs()
	if has_outputs and not dumped:
		wait_for_proximity()
	if has_outputs and dumped:
		return true
	if crafting:
		sleep_until(finish_tick)
	return false


func collect_contents(out: PackedInt32Array) -> void:
	for i in inputs.size():
		out[i] += inputs[i] + outputs[i]
	if crafting:
		for c in get_recipe().consumes:
			c.refund(out)


func get_status() -> Status:
	return status


func accepts_player_items() -> bool:
	return true


## Разгрузчик забирает только готовую продукцию: сырьё из входного буфера не трогается.
func can_unload() -> bool:
	return true


func has_item(item: int) -> bool:
	return outputs[item] > 0


func unload_item(item: int) -> bool:
	if outputs[item] <= 0:
		return false
	outputs[item] -= 1
	wake()
	return true


## Сначала готовая продукция, затем сырьё во входном буфере.
func get_player_stacks() -> Array[Vector2i]:
	var stacks: Array[Vector2i] = []
	for item in outputs.size():
		if outputs[item] > 0:
			stacks.append(Vector2i(item, outputs[item]))
	for item in inputs.size():
		if inputs[item] > 0:
			stacks.append(Vector2i(item, inputs[item]))
	return stacks


func take_player_items(item: int, amount: int) -> int:
	var from_outputs := mini(outputs[item], amount)
	outputs[item] -= from_outputs
	var from_inputs := mini(inputs[item], amount - from_outputs)
	inputs[item] -= from_inputs
	if from_inputs > 0:
		notify_space()
	if from_outputs + from_inputs > 0:
		wake()
	return from_outputs + from_inputs


func get_missing_inputs() -> PackedStringArray:
	var missing := PackedStringArray()
	for c in get_recipe().consumes:
		missing.append_array(c.describe_missing(self))
	return missing


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var recipe := get_recipe()
	if recipe == null:
		return lines
	var in_parts := PackedStringArray()
	for c in recipe.consumes:
		for s in c.display_stacks():
			in_parts.append("%s %d/%d" % [tr(s.item.name_key), inputs[s.item.index], get_input_capacity(s.item.index)])
	if not in_parts.is_empty():
		lines.append(tr("INFO_INPUTS") % ", ".join(in_parts))
	var out_parts := PackedStringArray()
	for item in recipe.output_items():
		out_parts.append("%s %d/%d" % [tr(Registry.items[item].name_key), outputs[item], get_output_capacity()])
	if not out_parts.is_empty():
		lines.append(tr("INFO_OUTPUTS") % ", ".join(out_parts))
	return lines


func _inputs_ready(recipe: Recipe) -> bool:
	for c in recipe.consumes:
		if not c.is_satisfied(self):
			return false
	return true


func _outputs_free(recipe: Recipe) -> bool:
	for p in recipe.produces:
		if not p.can_output(self):
			return false
	return true


func _efficiency(recipe: Recipe) -> float:
	var value := 1.0
	for c in recipe.consumes:
		value = minf(value, c.efficiency(self))
	return maxf(value, 0.01)


func _has_outputs() -> bool:
	for count in outputs:
		if count > 0:
			return true
	return false


## Отдать соседям один предмет из выходного буфера (типы по очереди).
func _dump_one() -> bool:
	var n := outputs.size()
	for k in n:
		var item := (_output_cursor + k) % n
		if outputs[item] > 0 and dump(item):
			outputs[item] -= 1
			_output_cursor = (item + 1) % n
			return true
	return false
