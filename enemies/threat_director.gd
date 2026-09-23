class_name ThreatDirector
extends RefCounted
## Угроза планеты: расписание волн по ThreatDef и выпуск врагов из точек появления.
##
## Волна: бюджет очков угрозы набирается случайными доступными врагами, враги выходят равномерно
## за время появления из нескольких точек (с номером волны точек больше). Следующая волна начинается
## после затишья; затишья сокращаются, пока волны не пойдут встык — одна непрерывная усиливающаяся волна.
## Если живых врагов больше предела, появление откладывается. Всё случайное — от своего RNG (сохраняется).

var def: ThreatDef
var start_tick: int = 0
## Сколько волн уже началось.
var wave: int = 0
var next_wave_tick: int = 0
## Тик, до которого выпускается последняя начатая волна.
var spawn_end_tick: int = 0
var last_budget: float = 0.0
var rng := RandomNumberGenerator.new()

var _world: GameWorld
var _enemies: Array[EnemyDef] = []
var _from_wave := PackedInt32Array()
var _weights := PackedFloat32Array()
## Очередь появлений: тик, индекс EnemyDef, номер точки.
var _queue_ticks := PackedInt32Array()
var _queue_types := PackedInt32Array()
var _queue_points := PackedInt32Array()
## Стая и её намерение для каждого врага в очереди: рождённые вместе идут вместе.
var _queue_squads := PackedInt32Array()
var _queue_moods := PackedInt32Array()
var _queue_cursor: int = 0


func _init(world: GameWorld, p_def: ThreatDef, p_start_tick: int, seed_value: int) -> void:
	_world = world
	def = p_def
	start_tick = p_start_tick
	rng.seed = seed_value
	next_wave_tick = start_tick + def.get_first_wave_ticks()
	for i in def.enemy_ids.size():
		var enemy := Registry.get_enemy(def.enemy_ids[i])
		if enemy == null:
			continue
		_enemies.append(enemy)
		_from_wave.append(def.enemy_from_wave[i] if i < def.enemy_from_wave.size() else 1)
		_weights.append(def.enemy_weights[i] if i < def.enemy_weights.size() else 1.0)


func dispose() -> void:
	_world = null


func update(tick: int) -> void:
	if tick >= next_wave_tick:
		_start_wave(tick)
	if _queue_cursor >= _queue_ticks.size():
		return
	var enemies := _world.enemies
	var points := _world.spawn_points
	var t := float(GameConst.TILE_SIZE)
	while _queue_cursor < _queue_ticks.size() and _queue_ticks[_queue_cursor] <= tick:
		if enemies.count >= def.max_alive:
			break
		var enemy := Registry.enemies[_queue_types[_queue_cursor]]
		var point := points[_queue_points[_queue_cursor] % points.size()]
		var offset := Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0))
		var squad_id: int = _queue_squads[_queue_cursor] if _queue_cursor < _queue_squads.size() else 0
		var squad_mood: int = _queue_moods[_queue_cursor] if _queue_cursor < _queue_moods.size() else EnemySystem.Mood.GATE
		enemies.spawn(enemy, Vector2(point) * t + Vector2.ONE * t * 0.5 + offset, tick, squad_id, squad_mood)
		_queue_cursor += 1
	if _queue_cursor >= _queue_ticks.size():
		_queue_ticks.clear()
		_queue_types.clear()
		_queue_points.clear()
		_queue_squads.clear()
		_queue_moods.clear()
		_queue_cursor = 0


## Вызвать следующую волну сейчас (отладка).
func call_next_wave(tick: int) -> void:
	next_wave_tick = mini(next_wave_tick, tick)


## Отменить ещё не выпущенных врагов (отладка, автопрогон).
func clear_pending() -> void:
	_queue_ticks.clear()
	_queue_types.clear()
	_queue_points.clear()
	_queue_squads.clear()
	_queue_moods.clear()
	_queue_cursor = 0


## Отложить следующую волну на ticks (автопрогон).
func delay_next_wave(ticks: int) -> void:
	next_wave_tick += ticks


func get_ticks_to_next_wave(tick: int) -> int:
	return maxi(next_wave_tick - tick, 0)


func is_spawning(tick: int) -> bool:
	return wave > 0 and tick < spawn_end_tick


## Волны уже идут встык.
func is_continuous() -> bool:
	return wave > 0 and def.get_gap_ticks(wave) == 0


func is_warning(tick: int) -> bool:
	return not is_continuous() and next_wave_tick - tick <= def.get_warning_ticks()


func get_pending_spawns() -> int:
	return _queue_ticks.size() - _queue_cursor


func _start_wave(tick: int) -> void:
	wave += 1
	var minutes := float(tick - start_tick) / (60.0 * GameConst.TICK_RATE)
	var budget := def.get_budget(wave, minutes)
	last_budget = budget
	var duration := def.get_spawn_ticks(wave)
	spawn_end_tick = tick + duration
	next_wave_tick = tick + duration + def.get_gap_ticks(wave)
	var point_count := _world.spawn_points.size()
	if point_count == 0 or _enemies.is_empty():
		return
	var picks := _compose(budget)
	# С номером волны точек больше: 1 на первых волнах, затем все.
	var active := mini(point_count, 1 + (wave - 1) / 3)
	var first := rng.randi_range(0, point_count - 1)
	# Каждая точка выпускает свою стаю со своим намерением: одни идут к шлюзу, другие охотятся
	# за игроком, третьи грызут всё по дороге. Чем дальше волна, тем чаще стая ведёт себя нагло.
	var moods := PackedInt32Array()
	for k in active:
		moods.append(_pick_mood())
	for k in picks.size():
		var slot := k % active
		_queue_ticks.append(tick + duration * k / maxi(picks.size(), 1))
		_queue_types.append(picks[k])
		_queue_points.append(first + slot)
		_queue_squads.append(wave * 16 + slot)
		_queue_moods.append(moods[slot])


## Намерение стаи: к шлюзу, охота на игрока или налёт на постройки.
func _pick_mood() -> int:
	var to_gate := 6.0
	var to_hunt := 1.0 + wave * 0.25
	var to_raid := 1.5 + wave * 0.2
	var roll := rng.randf() * (to_gate + to_hunt + to_raid)
	if roll < to_gate:
		return EnemySystem.Mood.GATE
	return EnemySystem.Mood.HUNT if roll < to_gate + to_hunt else EnemySystem.Mood.RAID


## Состав волны на бюджет: случайные доступные враги, пока хватает очков.
func _compose(budget: float) -> PackedInt32Array:
	var picks := PackedInt32Array()
	var remaining := budget
	var guard := 0
	while guard < 5000:
		guard += 1
		var total := 0.0
		for i in _enemies.size():
			if wave >= _from_wave[i] and _enemies[i].threat_cost <= remaining:
				total += _weights[i]
		if total <= 0.0:
			break
		var roll := rng.randf() * total
		var chosen := -1
		for i in _enemies.size():
			if wave >= _from_wave[i] and _enemies[i].threat_cost <= remaining:
				roll -= _weights[i]
				chosen = i
				if roll <= 0.0:
					break
		picks.append(_enemies[chosen].index)
		remaining -= _enemies[chosen].threat_cost
	return picks


# --- Сохранение ---

func save_data() -> Dictionary:
	return {"start": start_tick, "wave": wave, "next": next_wave_tick, "spawn_end": spawn_end_tick,
		"budget": last_budget, "rng_seed": rng.seed, "rng_state": rng.state,
		"queue_ticks": _queue_ticks.slice(_queue_cursor), "queue_types": _queue_types.slice(_queue_cursor),
		"queue_points": _queue_points.slice(_queue_cursor),
		"queue_squads": _queue_squads.slice(_queue_cursor), "queue_moods": _queue_moods.slice(_queue_cursor)}


## type_map — сохранённый индекс врага → текущий.
func load_data(data: Dictionary, type_map: PackedInt32Array) -> void:
	start_tick = int(data.get("start", start_tick))
	wave = int(data.get("wave", 0))
	next_wave_tick = int(data.get("next", next_wave_tick))
	spawn_end_tick = int(data.get("spawn_end", 0))
	last_budget = float(data.get("budget", 0.0))
	rng.seed = int(data.get("rng_seed", rng.seed))
	rng.state = int(data.get("rng_state", rng.state))
	_queue_ticks.clear()
	_queue_types.clear()
	_queue_points.clear()
	_queue_squads.clear()
	_queue_moods.clear()
	_queue_cursor = 0
	var ticks: PackedInt32Array = data.get("queue_ticks", PackedInt32Array())
	var saved_types: PackedInt32Array = data.get("queue_types", PackedInt32Array())
	var saved_points: PackedInt32Array = data.get("queue_points", PackedInt32Array())
	var saved_squads: PackedInt32Array = data.get("queue_squads", PackedInt32Array())
	var saved_moods: PackedInt32Array = data.get("queue_moods", PackedInt32Array())
	for i in mini(ticks.size(), mini(saved_types.size(), saved_points.size())):
		var type := saved_types[i]
		if type_map.size() > 0:
			type = type_map[type] if type >= 0 and type < type_map.size() else -1
		if type < 0 or type >= Registry.enemies.size():
			continue
		_queue_ticks.append(ticks[i])
		_queue_types.append(type)
		_queue_squads.append(saved_squads[i] if i < saved_squads.size() else 0)
		_queue_moods.append(saved_moods[i] if i < saved_moods.size() else EnemySystem.Mood.GATE)
		_queue_points.append(saved_points[i])
