class_name ResearchState
extends RefCounted
## Исследования забега (общие для базы и всех планет): завершённые, прогресс, выбранное исследование.
##
## Прогресс — сколько наборов уже потрачено. Два источника наборов:
## - ручная сдача: игрок кладёт наборы первого уровня из инвентаря в очередь, очередь обрабатывается
##   медленно (MANUAL_SECONDS на набор) и только для выбранного исследования;
## - научный цех: берёт наборы с ленты, работает от электричества и гораздо быстрее.
## Постройки и рецепты без исследования доступны сразу; в творческом режиме открыто всё.
##
## Очередь (queue): что исследовать после текущего, до QUEUE_MAX штук. Когда исследование
## завершается, из очереди берётся первое доступное — недоступные остаются ждать своих
## предшественников, уже завершённые выбрасываются.

signal completed(research: ResearchDef)
signal changed
## Из очереди выбрано следующее исследование.
signal next_taken(research: ResearchDef)

## Секунд на один набор при ручной сдаче.
const MANUAL_SECONDS := 12.0
## Сколько исследований помещается в очередь.
const QUEUE_MAX := 5

## Всё открыто (творческий режим). Кнопкой «Исследовать заново» выключается, чтобы пройти дерево.
## Исследования, которые разделили на несколько: старое id → новые (для старых сохранений).
const LEGACY_SPLIT: Dictionary[StringName, Array] = {
	&"advanced_defense": [&"tesla_defense", &"repair_defense", &"fluid_defense"],
}

var creative: bool = false
## Забег творческий: доступен полигон и кнопки управления деревом.
var sandbox: bool = false
var done: Dictionary[StringName, bool] = {}
## Прогресс по каждому виду набора: [сдано наборов первого уровня, второго, ...].
var progress: Dictionary[StringName, PackedInt32Array] = {}
var active: StringName = &""
## Очередь следующих исследований (id, по порядку).
var queue: Array[StringName] = []
## Наборы, сданные вручную и ещё не обработанные.
var manual_queue: int = 0
## Кто сдаёт наборы вручную (id игрока). Сами наборы лежат у него в инвентаре и уходят
## по одному, когда исследование их использует, — как в научном цехе. Раньше сдача забирала
## все наборы сразу, и при смене исследования они были уже потрачены.
var manual_player: int = 0
var manual_ticks: int = 0

var _effect_counts: Dictionary[StringName, int] = {}
var _effects_signature: int = -1
## Состояние пришло из сохранения — «всё открыто» не перезаписывать флагом забега.
var loaded: bool = false


func is_done(id: StringName) -> bool:
	return done.has(id)


## Сколько наборов всего сдано в исследование (для полоски).
func get_progress(research: ResearchDef) -> int:
	if is_done(research.id):
		return research.total_cost()
	var sum := 0
	for value in _progress_of(research):
		sum += value
	return sum


## Сколько сдано наборов вида k.
func get_progress_of(research: ResearchDef, k: int) -> int:
	if is_done(research.id):
		var costs := research.costs()
		return costs[k].amount if k < costs.size() else 0
	var values := _progress_of(research)
	return values[k] if k < values.size() else 0


## Прогресс исследования по видам наборов (нужной длины).
func _progress_of(research: ResearchDef) -> PackedInt32Array:
	var values: PackedInt32Array = progress.get(research.id, PackedInt32Array())
	var needed := research.costs().size()
	if values.size() < needed:
		values = values.duplicate()
		values.resize(needed)
		progress[research.id] = values
	return values


func get_active() -> ResearchDef:
	return Registry.get_research(active) if active != &"" else null


## Можно ли начать: не завершено и все предшествующие завершены.
func is_available(research: ResearchDef) -> bool:
	if research == null or is_done(research.id):
		return false
	if research.creative_only and not sandbox:
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
	queue.erase(id)
	# Обещанные наборы больше никуда не идут: они так и лежат в инвентаре.
	manual_queue = 0
	manual_ticks = 0
	changed.emit()
	return true


## Поставить исследование в очередь. false — уже завершено, уже выбрано, уже в очереди
## или очередь полна.
func queue_add(id: StringName) -> bool:
	if id == &"" or id == active or is_done(id) or queue.has(id) or queue.size() >= QUEUE_MAX:
		return false
	if Registry.get_research(id) == null:
		return false
	# Пустой слот текущего исследования заполняем сразу, если оно доступно.
	if active == &"" and is_available(Registry.get_research(id)):
		return set_active(id)
	queue.append(id)
	changed.emit()
	return true


func queue_remove(id: StringName) -> void:
	if queue.has(id):
		queue.erase(id)
		changed.emit()


## Место в очереди начиная с 1 (0 — не в очереди).
func queue_position(id: StringName) -> int:
	return queue.find(id) + 1


## Взять из очереди первое доступное исследование. Завершённые выбрасываются.
func _take_from_queue() -> void:
	var i := 0
	while i < queue.size():
		var id := queue[i]
		if is_done(id):
			queue.remove_at(i)
			continue
		if is_available(Registry.get_research(id)):
			queue.remove_at(i)
			active = id
			next_taken.emit(Registry.get_research(id))
			return
		i += 1


## Творческий режим: начать дерево заново (creative выключается — эффекты считаются по done).
func reset_progress() -> void:
	done.clear()
	progress.clear()
	queue.clear()
	active = &""
	manual_queue = 0
	manual_ticks = 0
	creative = false
	_effects_signature = -1
	changed.emit()


## Творческий режим: открыть всё разом.
func unlock_everything() -> void:
	for research in Registry.researches:
		if not research.creative_only:
			done[research.id] = true
	progress.clear()
	queue.clear()
	active = &""
	creative = true
	_effects_signature = -1
	changed.emit()


## Сколько завершённых исследований дают эффект (в творческом режиме — все такие исследования).
## Кэш пересчитывается, когда меняется число завершённых исследований или режим.
func count_effect(effect: StringName) -> int:
	var signature := done.size() * 2 + (1 if creative else 0)
	if signature != _effects_signature:
		_effects_signature = signature
		_effect_counts.clear()
		for research in Registry.researches:
			if (creative and not research.creative_only) or is_done(research.id):
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
## Во сколько раз быстрее работает научный цех (ветка «Методика исследований»). Ручная сдача
## идёт своим темпом: она задумана как медленный запасной путь без автоматики.
func speed_factor() -> float:
	return 1.0 + 0.25 * count_effect(&"science_speed")


## Сколько наборов ещё нужно всего.
func get_needed(research: ResearchDef) -> int:
	return maxi(research.total_cost() - get_progress(research), 0)


## Сколько ещё нужно наборов вида k.
func get_needed_of(research: ResearchDef, k: int) -> int:
	var costs := research.costs()
	if k >= costs.size():
		return 0
	return maxi(costs[k].amount - get_progress_of(research, k), 0)


## Какой вид наборов ждёт предмет item (−1 — исследованию он не нужен).
func cost_index_of(research: ResearchDef, item: int) -> int:
	var costs := research.costs()
	for k in costs.size():
		if costs[k].item.index == item and get_needed_of(research, k) > 0:
			return k
	return -1


## Отдать исследованию наборы первого уровня из инвентаря игрока. Наборы остаются у него
## и расходуются по одному; возвращает, сколько их обещано отдать.
func deposit_manual(inventory: Inventory, player_id: int) -> int:
	var research := get_active()
	if research == null or research.cost_item == null or research.cost_item.science_tier != 1:
		return 0
	# Руками сдают только наборы первого уровня: остальные уровни — через научный цех.
	var room := get_needed_of(research, 0) - manual_queue
	var promised := mini(maxi(room, 0), inventory.count(research.cost_item.index))
	if promised <= 0:
		return 0
	manual_queue += promised
	manual_player = player_id
	changed.emit()
	return promised


## Научный цех отдаёт один набор. true — набор принят выбранным исследованием.
func add_kit(item: int) -> bool:
	var research := get_active()
	if research == null:
		return false
	var k := cost_index_of(research, item)
	if k < 0:
		return false
	_advance(research, k)
	return true


## Нужен ли выбранному исследованию набор item (для научного цеха).
func wants_kit(item: int) -> bool:
	var research := get_active()
	return research != null and cost_index_of(research, item) >= 0


## Тик забега: ручная сдача. Набор уходит из инвентаря игрока в тот момент, когда его
## использовали, а не при нажатии кнопки.
func step(inventory: Inventory = null) -> void:
	if manual_queue <= 0:
		return
	var research := get_active()
	if research == null or research.cost_item == null:
		return
	# Наборы кончились (потратили на крафт, отдали напарнику) — ручная сдача прекращается.
	if inventory == null or inventory.count(research.cost_item.index) <= 0:
		manual_queue = 0
		manual_ticks = 0
		changed.emit()
		return
	manual_ticks += 1
	if manual_ticks >= roundi(MANUAL_SECONDS * GameConst.TICK_RATE):
		manual_ticks = 0
		manual_queue -= 1
		inventory.remove(research.cost_item.index, 1)
		_advance(research, 0)


func get_manual_fraction() -> float:
	return float(manual_ticks) / roundi(MANUAL_SECONDS * GameConst.TICK_RATE)


func _advance(research: ResearchDef, k: int) -> void:
	var values := _progress_of(research)
	if k < 0 or k >= values.size():
		return
	values[k] += 1
	progress[research.id] = values
	if get_needed(research) <= 0:
		done[research.id] = true
		progress.erase(research.id)
		if active == research.id:
			active = &""
			_take_from_queue()
		completed.emit(research)
	changed.emit()


func save_data() -> Dictionary:
	var done_ids := PackedStringArray()
	for id in done:
		done_ids.append(String(id))
	var progress_ids := PackedStringArray()
	# По виду наборов на исследование: [первого уровня, второго, ...].
	var progress_values: Array = []
	for id in progress:
		progress_ids.append(String(id))
		progress_values.append((progress[id] as PackedInt32Array).duplicate())
	return {"done": done_ids, "progress_ids": progress_ids, "progress_values": progress_values,
		"active": String(active), "manual_queue": manual_queue, "manual_ticks": manual_ticks,
		"manual_player": manual_player,
		"queue": _queue_ids(), "creative": creative}


func _queue_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id in queue:
		ids.append(String(id))
	return ids


func load_data(data: Dictionary) -> void:
	done.clear()
	progress.clear()
	for id in (data.get("done", PackedStringArray()) as PackedStringArray):
		if Registry.get_research(StringName(id)) != null:
			done[StringName(id)] = true
		# Исследование разделили на несколько — в старом сохранении завершены все его части.
		for part: StringName in LEGACY_SPLIT.get(StringName(id), []):
			if Registry.get_research(part) != null:
				done[part] = true
	var ids: PackedStringArray = data.get("progress_ids", PackedStringArray())
	var values: Array = data.get("progress_values", [])
	for i in mini(ids.size(), values.size()):
		if Registry.get_research(StringName(ids[i])) == null:
			continue
		# В старых сохранениях на исследование хранилось одно число — это наборы первого уровня.
		var value: Variant = values[i]
		progress[StringName(ids[i])] = value if value is PackedInt32Array else PackedInt32Array([int(value)])
	active = StringName(data.get("active", ""))
	if active != &"" and Registry.get_research(active) == null:
		active = &""
	manual_queue = int(data.get("manual_queue", 0))
	manual_ticks = int(data.get("manual_ticks", 0))
	manual_player = int(data.get("manual_player", 0))
	if data.has("creative"):
		creative = bool(data["creative"])
		loaded = true
	_effects_signature = -1
	queue.clear()
	for id in (data.get("queue", PackedStringArray()) as PackedStringArray):
		var name := StringName(id)
		if Registry.get_research(name) != null and not is_done(name) and queue.size() < QUEUE_MAX:
			queue.append(name)
