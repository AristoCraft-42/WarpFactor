class_name ScienceWorkshop
extends Building
## Научный цех: принимает научные наборы (лентой или руками) и тратит их на выбранное исследование.
## Работает от электричества; один набор — ScienceWorkshopDef.seconds_per_kit секунд при полном питании.

var kits := PackedInt32Array()
var working_item: int = -1
var progress: float = 0.0
var status: Status = Status.IDLE


func _init() -> void:
	kits.resize(Registry.items.size())
	kits.fill(0)


func get_workshop_def() -> ScienceWorkshopDef:
	return def as ScienceWorkshopDef


func on_placed() -> void:
	wake()


func total_kits() -> int:
	var sum := 0
	for c in kits:
		sum += c
	return sum


func accept_item(_source: Building, item: int) -> bool:
	return Registry.items[item].science_tier > 0 and total_kits() < get_workshop_def().kit_capacity


func handle_item(_source: Building, item: int) -> void:
	kits[item] += 1
	wake()


func update_tick(_tick: int) -> bool:
	power_request = 0.0
	var research := world.research
	if research == null:
		status = Status.NO_RESEARCH
		return false
	if working_item < 0:
		for item in kits.size():
			if kits[item] > 0 and research.wants_kit(item):
				working_item = item
				kits[item] -= 1
				progress = 0.0
				notify_space()
				break
	if working_item < 0:
		status = Status.NO_RESEARCH if research.get_active() == null else Status.NO_INPUT
		# Проснёмся, когда придёт набор; выбор исследования будит цеха через GameWorld.
		return false
	var rate := get_power_satisfaction()
	power_request = def.power_use
	progress += rate * research.speed_factor() / maxf(get_workshop_def().seconds_per_kit * GameConst.TICK_RATE, 1.0)
	status = Status.WORKING if rate > 0.0 else Status.NO_POWER
	if progress >= 1.0:
		if research.add_kit(working_item):
			working_item = -1
			progress = 0.0
		else:
			# Исследование сменили или завершили — набор возвращается в буфер.
			kits[working_item] += 1
			working_item = -1
			progress = 0.0
			status = Status.NO_RESEARCH
			return false
	return true


func collect_contents(out: PackedInt32Array) -> void:
	for item in kits.size():
		out[item] += kits[item]
	if working_item >= 0:
		out[working_item] += 1


func accepts_player_items() -> bool:
	return true


func get_player_stacks() -> Array[Vector2i]:
	var stacks: Array[Vector2i] = []
	for item in kits.size():
		if kits[item] > 0:
			stacks.append(Vector2i(item, kits[item]))
	return stacks


func take_player_items(item: int, amount: int) -> int:
	var taken := mini(kits[item], amount)
	kits[item] -= taken
	if taken > 0:
		notify_space()
	return taken


func save_state() -> Dictionary:
	return {"kits": kits.duplicate(), "working": working_item, "progress": progress, "status": status, "power": power_request}


func load_state(state: Dictionary) -> void:
	var counts := SaveContext.counts(state.get("kits", PackedInt32Array()))
	for i in mini(counts.size(), kits.size()):
		kits[i] = counts[i]
	working_item = SaveContext.item(int(state.get("working", -1)))
	progress = float(state.get("progress", 0.0))
	status = int(state.get("status", Status.IDLE)) as Status
	power_request = float(state.get("power", 0.0))
	wake()


func get_status() -> Status:
	return status


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray([tr("INFO_WORKSHOP_KITS") % [total_kits(), get_workshop_def().kit_capacity]])
	var active := world.research.get_active() if world.research != null else null
	lines.append(tr("INFO_WORKSHOP_RESEARCH") % (tr(active.name_key) if active != null else "—"))
	lines.append(power_info_line())
	return lines


# --- Окно ---

func get_window_sections() -> Array[WindowSection]:
	var kit_hint := -1
	for item in Registry.items:
		if item.science_tier > 0:
			kit_hint = item.index
			break
	var stacks: Array[Vector2i] = []
	var hints := PackedInt32Array()
	for item in kits.size():
		if kits[item] > 0:
			stacks.append(Vector2i(item, kits[item]))
			hints.append(item)
	if stacks.is_empty():
		stacks.append(Vector2i(-1, 0))
		hints.append(kit_hint)
	var sections: Array[WindowSection] = [WindowSection.slots(tr("WINDOW_KITS"), stacks, hints)]
	sections.append(WindowSection.progress(progress if working_item >= 0 else 0.0))
	sections.append(WindowSection.power(self))
	return sections
