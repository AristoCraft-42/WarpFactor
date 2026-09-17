class_name ResearchState
extends RefCounted
## Исследования забега (общие для базы и всех планет): завершённые, прогресс, выбранное исследование.
##
## Прогресс — сколько наборов уже потрачено. Два источника наборов:
## - ручная сдача: игрок кладёт наборы первого уровня из инвентаря в очередь, очередь обрабатывается
##   медленно (MANUAL_SECONDS на набор) и только для выбранного исследования;
## - научный цех: берёт наборы с ленты, работает от электричества и гораздо быстрее.
## Постройки и рецепты без исследования доступны сразу; в творческом режиме открыто всё.

signal completed(research: ResearchDef)
signal changed

## Секунд на один набор при ручной сдаче.
const MANUAL_SECONDS := 8.0

var creative: bool = false
var done: Dictionary[StringName, bool] = {}
var progress: Dictionary[StringName, int] = {}
var active: StringName = &""
## Наборы, сданные вручную и ещё не обработанные.
var manual_queue: int = 0
var manual_ticks: int = 0

var _effect_counts: Dictionary[StringName, int] = {}
var _effects_signature: int = -1


func is_done(id: StringName) -> bool:
	return done.has(id)


func get_progress(research: ResearchDef) -> int:
	return research.cost_amount if is_done(research.id) else int(progress.get(research.id, 0))


func get_active() -> ResearchDef:
	return Registry.get_research(active) if active != &"" else null


## Можно ли начать: не завершено и все предшествующие завершены.
func is_available(research: ResearchDef) -> bool:
	if research == null or is_done(research.id):
		return false
	for id in research.prerequisites:
		if not is_done(id):
			return false
	return true


func set_active(id: StringName) -> bool:
	var research := Registry.get_research(id)
	if id != &"" and not is_available(research):
		return false
	active = id
	changed.emit()
	return true


## Сколько завершённых исследований дают эффект (в творческом режиме — все такие исследования).
## Кэш пересчитывается, когда меняется число завершённых исследований или режим.
func count_effect(effect: StringName) -> int:
	var signature := done.size() * 2 + (1 if creative else 0)
	if signature != _effects_signature:
		_effects_signature = signature
		_effect_counts.clear()
		for research in Registry.researches:
			if creative or is_done(research.id):
				for e in research.effects:
					_effect_counts[e] = int(_effect_counts.get(e, 0)) + 1
	return int(_effect_counts.get(effect, 0))


func has_effect(effect: StringName) -> bool:
	return count_effect(effect) > 0


## Сколько всего исследований дают эффект (наибольшее число шагов).
static func max_effect(effect: StringName) -> int:
	var n := 0
	for research in Registry.researches:
		if research.effects.has(effect):
			n += 1
	return n


func is_building_unlocked(def: BuildingDef) -> bool:
	if creative or def == null:
		return true
	var research := Registry.get_building_research(def)
	return research == null or is_done(research.id)


func is_recipe_unlocked(recipe: Recipe) -> bool:
	if creative or recipe == null:
		return true
	var research := Registry.get_recipe_research(recipe)
	return research == null or is_done(research.id)


func is_hand_recipe_unlocked(hand: HandRecipe) -> bool:
	if hand.building != null:
		return is_building_unlocked(hand.building)
	return is_recipe_unlocked(hand.recipe)


## Сколько наборов ещё нужно выбранному исследованию (с учётом ручной очереди).
func get_needed(research: ResearchDef) -> int:
	return maxi(research.cost_amount - get_progress(research), 0)


## Сдать вручную наборы первого уровня из инвентаря. Возвращает, сколько сдано.
func deposit_manual(inventory: Inventory) -> int:
	var research := get_active()
	if research == null or research.cost_item == null or research.cost_item.science_tier != 1:
		return 0
	var room := get_needed(research) - manual_queue
	var moved := inventory.remove(research.cost_item.index, maxi(room, 0))
	manual_queue += moved
	if moved > 0:
		changed.emit()
	return moved


## Научный цех отдаёт один набор. true — набор принят выбранным исследованием.
func add_kit(item: int) -> bool:
	var research := get_active()
	if research == null or research.cost_item == null or research.cost_item.index != item:
		return false
	if get_needed(research) <= 0:
		return false
	_advance(research)
	return true


## Нужен ли выбранному исследованию набор item (для научного цеха).
func wants_kit(item: int) -> bool:
	var research := get_active()
	return research != null and research.cost_item != null and research.cost_item.index == item and get_needed(research) > 0


## Тик забега: обработка ручной очереди.
func step() -> void:
	if manual_queue <= 0:
		return
	var research := get_active()
	if research == null:
		return
	manual_ticks += 1
	if manual_ticks >= roundi(MANUAL_SECONDS * GameConst.TICK_RATE):
		manual_ticks = 0
		manual_queue -= 1
		_advance(research)


func get_manual_fraction() -> float:
	return float(manual_ticks) / roundi(MANUAL_SECONDS * GameConst.TICK_RATE)


func _advance(research: ResearchDef) -> void:
	progress[research.id] = int(progress.get(research.id, 0)) + 1
	if int(progress[research.id]) >= research.cost_amount:
		done[research.id] = true
		progress.erase(research.id)
		if active == research.id:
			active = &""
		completed.emit(research)
	changed.emit()


func save_data() -> Dictionary:
	var done_ids := PackedStringArray()
	for id in done:
		done_ids.append(String(id))
	var progress_ids := PackedStringArray()
	var progress_values := PackedInt32Array()
	for id in progress:
		progress_ids.append(String(id))
		progress_values.append(progress[id])
	return {"done": done_ids, "progress_ids": progress_ids, "progress_values": progress_values,
		"active": String(active), "manual_queue": manual_queue, "manual_ticks": manual_ticks}


func load_data(data: Dictionary) -> void:
	done.clear()
	progress.clear()
	for id in (data.get("done", PackedStringArray()) as PackedStringArray):
		if Registry.get_research(StringName(id)) != null:
			done[StringName(id)] = true
	var ids: PackedStringArray = data.get("progress_ids", PackedStringArray())
	var values: PackedInt32Array = data.get("progress_values", PackedInt32Array())
	for i in mini(ids.size(), values.size()):
		if Registry.get_research(StringName(ids[i])) != null:
			progress[StringName(ids[i])] = values[i]
	active = StringName(data.get("active", ""))
	if active != &"" and Registry.get_research(active) == null:
		active = &""
	manual_queue = int(data.get("manual_queue", 0))
	manual_ticks = int(data.get("manual_ticks", 0))
