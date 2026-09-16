class_name Crafter
extends Building
## Завод по рецептам CrafterDef. Принимает входы текущего рецепта в свой буфер, в начале цикла списывает их,
## в конце кладёт результат в выходной буфер и раздаёт соседям.
##
## Рецепт: FIXED — единственный; AUTO (печь) — берётся по первому пришедшему сырью, сменить можно,
## когда входной буфер пуст и цикл не идёт; SELECT (сборщик) — настройка здания, выбирает игрок.
## Цикл идёт по тикам: скорость = удовлетворённость электросети (если нужен ток) и 0 без топлива
## (если нужно топливо). Пока идёт цикл, завод бодрствует и просит ток; без сырья спит до прихода
## предмета, с полным выходом — до освобождения места у соседей.

var inputs: PackedInt32Array = PackedInt32Array()
var outputs: PackedInt32Array = PackedInt32Array()
## Топливо: предметы по индексу и остаток энергии горящего, кДж.
var fuel_counts: PackedInt32Array = PackedInt32Array()
var fuel_energy: float = 0.0
var recipe_index: int = -1
var crafting: bool = false
## Доля выполнения цикла 0..1.
var progress: float = 0.0
var status: Status = Status.IDLE

var _output_cursor: int = 0


func _init() -> void:
	inputs.resize(Registry.items.size())
	inputs.fill(0)
	outputs.resize(Registry.items.size())
	outputs.fill(0)
	fuel_counts.resize(Registry.items.size())
	fuel_counts.fill(0)


func get_crafter_def() -> CrafterDef:
	return def as CrafterDef


func get_recipe() -> Recipe:
	var d := get_crafter_def()
	if d.recipe_mode == CrafterDef.RecipeMode.FIXED:
		return d.recipes[0] if not d.recipes.is_empty() else null
	return d.recipes[recipe_index] if recipe_index >= 0 and recipe_index < d.recipes.size() else null


func get_output_capacity() -> int:
	return get_crafter_def().item_capacity


func get_input_capacity(item: int) -> int:
	var recipe := get_recipe()
	if recipe == null:
		return 0
	var capacity := 0
	for c in recipe.consumes:
		capacity = maxi(capacity, c.item_capacity(item, get_crafter_def().item_capacity))
	return capacity


## Доля выполнения текущего цикла (0..1).
func get_progress(_tick: int = 0) -> float:
	return clampf(progress, 0.0, 1.0) if crafting else 0.0


func on_placed() -> void:
	wake()


func on_proximity_changed() -> void:
	wake()


# --- Предметы ---

func accept_item(_source: Building, item: int) -> bool:
	var d := get_crafter_def()
	var recipe := get_recipe()
	if recipe != null and recipe.accepts_item(item):
		return inputs[item] < get_input_capacity(item)
	if d.fuel_use > 0.0 and Registry.items[item].is_fuel():
		return total_fuel() < d.fuel_capacity
	if d.recipe_mode == CrafterDef.RecipeMode.AUTO and not crafting and _inputs_empty():
		return _auto_recipe_for(item) >= 0
	return false


func handle_item(_source: Building, item: int) -> void:
	var d := get_crafter_def()
	var recipe := get_recipe()
	if recipe == null or not recipe.accepts_item(item):
		if d.fuel_use > 0.0 and Registry.items[item].is_fuel():
			fuel_counts[item] += 1
			wake()
			return
		if d.recipe_mode == CrafterDef.RecipeMode.AUTO:
			recipe_index = _auto_recipe_for(item)
	inputs[item] += 1
	if not crafting:
		wake()


func _auto_recipe_for(item: int) -> int:
	var d := get_crafter_def()
	for i in d.recipes.size():
		if d.recipes[i] != null and d.recipes[i].accepts_item(item):
			return i
	return -1


func _inputs_empty() -> bool:
	for c in inputs:
		if c > 0:
			return false
	return true


func total_fuel() -> int:
	var sum := 0
	for c in fuel_counts:
		sum += c
	return sum


# --- Тик ---

func update_tick(_tick: int) -> bool:
	var recipe := get_recipe()
	power_request = 0.0
	if recipe == null:
		status = Status.NO_RECIPE
		return false

	if crafting:
		var rate := _work_rate()
		if rate > 0.0:
			progress += rate / recipe.get_craft_ticks()
			_burn_fuel(rate)
		if progress >= 1.0:
			progress = 1.0
			if _outputs_free(recipe):
				for p in recipe.produces:
					p.produce(self, world.rng)
				crafting = false
				progress = 0.0
				# Разгрузчики, ждущие продукцию.
				if world.simulation.has_waiters(id):
					notify_space()
			else:
				status = Status.OUTPUT_BLOCKED
		else:
			status = Status.WORKING if rate > 0.0 else _stall_status()

	if not crafting:
		if not _inputs_ready(recipe):
			status = Status.NO_INPUT
		elif not _outputs_free(recipe):
			status = Status.OUTPUT_BLOCKED
		else:
			for c in recipe.consumes:
				c.consume(self)
			crafting = true
			progress = 0.0
			status = Status.WORKING
			# Во входном буфере освободилось место.
			notify_space()

	var dumped := _dump_one()
	var has_outputs := _has_outputs()
	if has_outputs and not dumped:
		wait_for_proximity()
	var running := crafting and status != Status.OUTPUT_BLOCKED
	if running and get_crafter_def().power_use > 0.0:
		power_request = get_crafter_def().power_use
	# Без топлива спим до его прихода (handle_item будит); без тока — бодрствуем: сеть может ожить в любой тик.
	if running and status == Status.NO_FUEL:
		running = false
	if running or (has_outputs and dumped):
		return true
	return false


## Скорость цикла: ток (удовлетворённость сети) и наличие топлива.
func _work_rate() -> float:
	var d := get_crafter_def()
	var rate := 1.0
	if d.power_use > 0.0:
		rate = get_power_satisfaction()
	if d.fuel_use > 0.0 and fuel_energy <= 0.0 and total_fuel() == 0:
		rate = 0.0
	return rate


func _stall_status() -> Status:
	var d := get_crafter_def()
	if d.fuel_use > 0.0 and fuel_energy <= 0.0 and total_fuel() == 0:
		return Status.NO_FUEL
	return Status.NO_POWER


func _burn_fuel(rate: float) -> void:
	var d := get_crafter_def()
	if d.fuel_use <= 0.0:
		return
	var need := d.fuel_use * GameConst.TICK_DT * rate
	while fuel_energy < need:
		var item := _take_fuel()
		if item < 0:
			break
		fuel_energy += Registry.items[item].fuel_value
	fuel_energy = maxf(fuel_energy - need, 0.0)


func _take_fuel() -> int:
	for item in fuel_counts.size():
		if fuel_counts[item] > 0:
			fuel_counts[item] -= 1
			notify_space()
			return item
	return -1


func collect_contents(out: PackedInt32Array) -> void:
	for i in inputs.size():
		out[i] += inputs[i] + outputs[i] + fuel_counts[i]
	if crafting and get_recipe() != null:
		for c in get_recipe().consumes:
			c.refund(out)


# --- Настройка (сборщик) ---

func get_config_kind() -> ConfigKind:
	return ConfigKind.RECIPE if get_crafter_def().recipe_mode == CrafterDef.RecipeMode.SELECT else ConfigKind.NONE


func get_config() -> Variant:
	if get_crafter_def().recipe_mode != CrafterDef.RecipeMode.SELECT:
		return null
	var recipe := get_recipe()
	return recipe.id if recipe != null else null


## Смена рецепта: идущий цикл отменяется, списанное сырьё возвращается во входной буфер.
func set_config(value: Variant) -> void:
	var d := get_crafter_def()
	if d.recipe_mode != CrafterDef.RecipeMode.SELECT:
		return
	var index := d.find_recipe_index(StringName(value)) if (value is StringName or value is String) else -1
	if index == recipe_index:
		return
	if crafting and get_recipe() != null:
		for c in get_recipe().consumes:
			c.refund(inputs)
	crafting = false
	progress = 0.0
	recipe_index = index
	if world != null:
		wake()
		notify_space()


func get_display_item() -> int:
	if get_crafter_def().recipe_mode != CrafterDef.RecipeMode.SELECT:
		return -1
	var recipe := get_recipe()
	var main := recipe.get_main_output() if recipe != null else null
	return main.item.index if main != null else -1


# --- Состояние ---

func save_state() -> Dictionary:
	return {"inputs": inputs.duplicate(), "outputs": outputs.duplicate(), "fuel": fuel_counts.duplicate(),
		"energy": fuel_energy, "recipe": recipe_index, "crafting": crafting, "progress": progress,
		"cursor": _output_cursor, "status": status, "power": power_request}


func load_state(state: Dictionary) -> void:
	var src_inputs := SaveContext.counts(state.get("inputs", PackedInt32Array()))
	var src_outputs := SaveContext.counts(state.get("outputs", PackedInt32Array()))
	var src_fuel := SaveContext.counts(state.get("fuel", PackedInt32Array()))
	for i in mini(src_inputs.size(), inputs.size()):
		inputs[i] = src_inputs[i]
	for i in mini(src_outputs.size(), outputs.size()):
		outputs[i] = src_outputs[i]
	for i in mini(src_fuel.size(), fuel_counts.size()):
		fuel_counts[i] = src_fuel[i]
	fuel_energy = float(state.get("energy", 0.0))
	var d := get_crafter_def()
	recipe_index = clampi(int(state.get("recipe", -1)), -1, d.recipes.size() - 1)
	crafting = bool(state.get("crafting", false))
	progress = float(state.get("progress", 0.0))
	_output_cursor = clampi(SaveContext.item(int(state.get("cursor", 0))), 0, maxi(outputs.size() - 1, 0))
	status = int(state.get("status", Status.IDLE)) as Status
	power_request = float(state.get("power", 0.0))
	wake()


func get_status() -> Status:
	return status


# --- Игрок и разгрузчик ---

func accepts_player_items() -> bool:
	return true


## Разгрузчик забирает и готовую продукцию, и сырьё из входного буфера (сначала продукцию).
func can_unload() -> bool:
	return true


func has_item(item: int) -> bool:
	return outputs[item] > 0 or inputs[item] > 0


func unload_item(item: int) -> bool:
	if outputs[item] > 0:
		outputs[item] -= 1
	elif inputs[item] > 0:
		inputs[item] -= 1
		notify_space()
	else:
		return false
	wake()
	return true


func get_load_factor(item: int) -> float:
	var capacity := maxi(get_input_capacity(item), get_output_capacity())
	return float(inputs[item] + outputs[item]) / maxi(capacity, 1)


## Сначала готовая продукция, затем сырьё во входном буфере и топливо.
func get_player_stacks() -> Array[Vector2i]:
	var stacks: Array[Vector2i] = []
	for item in outputs.size():
		if outputs[item] > 0:
			stacks.append(Vector2i(item, outputs[item]))
	for item in inputs.size():
		if inputs[item] > 0:
			stacks.append(Vector2i(item, inputs[item]))
	for item in fuel_counts.size():
		if fuel_counts[item] > 0:
			stacks.append(Vector2i(item, fuel_counts[item]))
	return stacks


func take_player_items(item: int, amount: int) -> int:
	var from_outputs := mini(outputs[item], amount)
	outputs[item] -= from_outputs
	var from_inputs := mini(inputs[item], amount - from_outputs)
	inputs[item] -= from_inputs
	var from_fuel := mini(fuel_counts[item], amount - from_outputs - from_inputs)
	fuel_counts[item] -= from_fuel
	if from_inputs + from_fuel > 0:
		notify_space()
	if from_outputs + from_inputs + from_fuel > 0:
		wake()
	return from_outputs + from_inputs + from_fuel


func get_missing_inputs() -> PackedStringArray:
	var missing := PackedStringArray()
	var recipe := get_recipe()
	if recipe == null:
		return missing
	for c in recipe.consumes:
		missing.append_array(c.describe_missing(self))
	return missing


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var d := get_crafter_def()
	var recipe := get_recipe()
	if recipe == null:
		lines.append(tr("INFO_NO_RECIPE"))
	else:
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
	if d.fuel_use > 0.0:
		lines.append(tr("INFO_FUEL") % total_fuel())
	if d.power_use > 0.0:
		lines.append(power_info_line())
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
