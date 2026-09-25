class_name AudioDirector
extends Node
## Режиссёр звука (автозагрузка Audio): звуки мира, интерфейса и музыка. Только представление —
## в симуляцию ничего не пишет и ничего из неё не меняет.
##
## Откуда берутся звуки:
## - мир пишет события в GameWorld.sounds (SoundLog): выстрелы, взрывы, гибель врагов, стройка…
##   Каждый кадр режиссёр забирает новые события активного мира, отбрасывает те, что далеко за
##   экраном, и на каждый вид события играет не больше одного голоса за кадр (самый близкий к
##   центру; чем больше одинаковых событий, тем громче) — сотня турелей не превращается в шум;
## - забег и интерфейс: волна (предупреждение и начало), исследование, телепорт, всплывающие
##   уведомления, нажатия кнопок (любая BaseButton в дереве);
## - фон цеха: петля, громкость которой зависит от числа работающих зданий на экране.
##
## Музыка — четыре синхронных слоя PlaceholderMusic, смешиваемых по обстановке (MusicState).
## Свои файлы (audio/sfx/<id>.ogg, audio/music/<состояние>*.ogg) заменяют заглушки — README рядом.
##
## Заглушки синтезируются в фоновом потоке при запуске (≈ 1 с); до готовности звуков просто нет.
## В headless (тесты) режиссёр спит.

enum MusicState { MENU, CALM, TENSION, COMBAT }

const MUSIC_STATE_NAMES: Array[String] = ["menu", "calm", "tension", "combat"]
## Громкость слоёв музыки (PAD, MELODY, BASS, DRUMS) по состояниям.
const LAYER_MIX := [
	[0.9, 0.8, 0.0, 0.0], # MENU
	[0.8, 0.7, 0.0, 0.0], # CALM
	[0.75, 0.3, 0.8, 0.0], # TENSION
	[0.6, 0.25, 0.9, 0.85], # COMBAT
]
## Музыка — фон: на столько дБ тише звуков при равных ползунках.
const MUSIC_GAIN_DB := -3.0
## Скорость смены громкости слоёв (доля полной громкости в секунду).
const FADE_PER_SECOND := 0.45
## Спуск на более спокойное состояние — только если оно держится столько секунд.
const CALM_DOWN_SECONDS := 8.0
## Как часто пересчитывать обстановку (с).
const STATE_PERIOD := 0.5

const WORLD_VOICES := 20
const UI_VOICES := 6
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"

## Параметры звуков: громкость (дБ), минимальный интервал (с), голосов одновременно, разброс высоты.
const SFX_PARAMS := {
	&"ui_click": [-10.0, 0.03, 2, 0.03],
	&"ui_error": [-10.0, 0.25, 1, 0.0],
	&"ui_success": [-8.0, 0.25, 1, 0.0],
	&"ui_notify": [-14.0, 0.3, 1, 0.0],
	&"build": [-6.0, 0.05, 3, 0.06],
	&"deconstruct": [-7.0, 0.05, 3, 0.06],
	&"rotate": [-12.0, 0.04, 2, 0.05],
	&"building_destroyed": [-4.0, 0.12, 3, 0.1],
	&"shot": [-12.0, 0.045, 4, 0.1],
	&"shell": [-9.0, 0.1, 3, 0.08],
	&"explosion": [-5.0, 0.1, 3, 0.1],
	&"hit": [-20.0, 0.06, 2, 0.15],
	&"zap": [-11.0, 0.08, 3, 0.1],
	&"repair": [-16.0, 0.2, 2, 0.05],
	&"spray": [-14.0, 0.15, 2, 0.08],
	&"enemy_death": [-8.0, 0.06, 3, 0.15],
	&"enemy_melee": [-15.0, 0.07, 2, 0.12],
	&"enemy_shot": [-15.0, 0.07, 2, 0.1],
	&"mine": [-10.0, 0.05, 2, 0.08],
	&"crate": [-8.0, 0.3, 1, 0.0],
	&"drone_destroyed": [-4.0, 0.5, 1, 0.0],
	&"drone_respawn": [-8.0, 0.5, 1, 0.0],
	&"wave_warning": [-6.0, 2.0, 1, 0.0],
	&"wave_start": [-5.0, 2.0, 1, 0.0],
	&"research_done": [-7.0, 0.5, 1, 0.0],
	&"teleport": [-6.0, 1.0, 1, 0.0],
}
const DEFAULT_PARAMS := [-10.0, 0.05, 2, 0.05]

## Звук на каждое событие мира (SoundLog.Kind).
const KIND_SOUNDS: Array[StringName] = [
	&"shot", &"shell", &"explosion", &"hit", &"zap", &"repair", &"spray",
	&"enemy_death", &"enemy_melee", &"enemy_shot",
	&"mine", &"build", &"deconstruct", &"rotate", &"building_destroyed",
	&"drone_destroyed", &"drone_respawn", &"crate",
]

## Звуки готовы (синтез закончился или отключён).
var is_ready: bool = false
var music_state: MusicState = MusicState.MENU
## Сколько раз прозвучал каждый звук (для проверок и отладки).
var played: Dictionary[StringName, int] = {}

var _enabled: bool = false
var _task: int = -1
## Результат фонового синтеза: id → AudioStreamWAV и слои музыки.
var _generated: Dictionary = {}
var _streams: Dictionary[StringName, Array] = {}
var _music_tracks: Dictionary[int, Array] = {}

var _world_voices: Array[AudioStreamPlayer2D] = []
var _world_voice_cursor: int = 0
var _ui_voices: Array[AudioStreamPlayer] = []
var _ui_voice_cursor: int = 0
var _last_played: Dictionary[StringName, float] = {}
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()

var _layers: Array[AudioStreamPlayer] = []
var _layer_amp: PackedFloat32Array = PackedFloat32Array()
var _tracks: Array[AudioStreamPlayer] = []
var _track_amp: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _track_target: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _track_state: PackedInt32Array = PackedInt32Array([-1, -1])
var _ambience: AudioStreamPlayer
var _ambience_amp: float = 0.0
var _ambience_target: float = 0.0

var _game: Game
var _world: GameWorld
var _cursor: int = 0
var _run: Run
var _state_timer: float = 0.0
var _lower_held: float = 0.0
var _last_wave: int = -1
var _was_warning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		is_ready = true
		return
	_load_user_files()
	_build_players()
	get_tree().node_added.connect(_on_node_added)
	Events.toast_requested.connect(_on_toast)
	var wanted: Array[StringName] = []
	for id in PlaceholderSounds.IDS:
		if not _streams.has(id):
			wanted.append(id)
	_task = WorkerThreadPool.add_task(_generate.bind(wanted), false, "placeholder audio")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Фоновый поток: только синтез и сборка ресурсов, никаких узлов.
func _generate(ids: Array[StringName]) -> void:
	var result := {}
	for id in ids:
		result[id] = Synth.to_stream(PlaceholderSounds.make(id), PlaceholderSounds.LOOPS.has(id))
	var layers: Array[AudioStreamWAV] = []
	for buf in PlaceholderMusic.make_layers():
		layers.append(Synth.to_stream(buf, true))
	result["__layers"] = layers
	_generated = result


func _finish_generation() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	for id in _generated:
		if id is StringName:
			_streams[id] = [_generated[id]]
	var layers: Array = _generated.get("__layers", [])
	for k in mini(layers.size(), _layers.size()):
		_layers[k].stream = layers[k]
	# Слои стартуют в одном кадре — дальше идут в ногу, петли одинаковой длины.
	for player in _layers:
		if player.stream != null:
			player.volume_db = -80.0
			player.play()
	if _streams.has(&"factory_loop"):
		_ambience.stream = _streams[&"factory_loop"][0]
		_ambience.volume_db = -80.0
		_ambience.play()
	_generated = {}
	is_ready = true


# --- Свои файлы ---

## audio/sfx/<id>.ogg|wav (и <id>_2.ogg… — случайный из вариантов), audio/music/<состояние>*.ogg.
func _load_user_files() -> void:
	for file_name in _list_audio("res://audio/sfx"):
		var id := StringName(_base_id(file_name.get_basename()))
		var stream := load("res://audio/sfx".path_join(file_name)) as AudioStream
		if stream == null:
			continue
		if not _streams.has(id):
			_streams[id] = []
		_streams[id].append(stream)
	for file_name in _list_audio("res://audio/music"):
		var base := file_name.get_basename().to_lower()
		for state in MUSIC_STATE_NAMES.size():
			if base.begins_with(MUSIC_STATE_NAMES[state]):
				var stream := load("res://audio/music".path_join(file_name)) as AudioStream
				if stream != null:
					if not _music_tracks.has(state):
						_music_tracks[state] = []
					_music_tracks[state].append(stream)


static func _list_audio(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file_name in ResourceLoader.list_directory(dir):
		var ext := file_name.get_extension().to_lower()
		if ext == "ogg" or ext == "wav" or ext == "mp3":
			out.append(file_name)
	return out


## «shot_2» → «shot»: варианты одного звука нумеруются через подчёркивание.
static func _base_id(file_base: String) -> String:
	var cut := file_base.rfind("_")
	if cut > 0 and file_base.substr(cut + 1).is_valid_int():
		return file_base.substr(0, cut)
	return file_base


# --- Проигрыватели ---

func _build_players() -> void:
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = SFX_BUS
		p.attenuation = 1.5
		add_child(p)
		_world_voices.append(p)
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_ui_voices.append(p)
	for i in PlaceholderMusic.LAYER_COUNT:
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		add_child(p)
		_layers.append(p)
	_layer_amp.resize(PlaceholderMusic.LAYER_COUNT)
	_layer_amp.fill(0.0)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		p.finished.connect(_on_track_finished.bind(i))
		add_child(p)
		_tracks.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = SFX_BUS
	add_child(_ambience)


func _params(id: StringName) -> Array:
	return SFX_PARAMS.get(id, DEFAULT_PARAMS)


## Можно ли сейчас сыграть звук: не чаще интервала и не больше голосов.
func _can_play(id: StringName) -> bool:
	if not _streams.has(id):
		return false
	var params := _params(id)
	return _time - _last_played.get(id, -1000.0) >= float(params[1])


func _pick_stream(id: StringName) -> AudioStream:
	var list: Array = _streams[id]
	return list[_rng.randi() % list.size()]


func _mark_played(id: StringName) -> void:
	_last_played[id] = _time
	played[id] = played.get(id, 0) + 1


## Звук интерфейса или события забега (без места).
func play_ui(id: StringName, volume_offset_db: float = 0.0) -> void:
	if not _enabled or not _can_play(id):
		return
	var params := _params(id)
	var voice := _ui_voices[_ui_voice_cursor]
	_ui_voice_cursor = (_ui_voice_cursor + 1) % _ui_voices.size()
	voice.stream = _pick_stream(id)
	voice.volume_db = float(params[0]) + volume_offset_db
	voice.pitch_scale = 1.0 + _rng.randf_range(-1.0, 1.0) * float(params[3])
	voice.play()
	_mark_played(id)


## Звук в точке мира (пиксели). Громкость и панорама — от положения относительно камеры.
func play_at(id: StringName, at: Vector2, volume_offset_db: float = 0.0) -> void:
	if not _enabled or not _can_play(id):
		return
	var params := _params(id)
	var limit := int(params[2])
	var busy := 0
	for v in _world_voices:
		if v.playing and v.get_meta(&"id", &"") == id:
			busy += 1
	if busy >= limit:
		return
	var voice := _free_world_voice()
	voice.stream = _pick_stream(id)
	voice.set_meta(&"id", id)
	voice.global_position = at
	voice.max_distance = _hearing_distance()
	voice.volume_db = float(params[0]) + volume_offset_db
	voice.pitch_scale = 1.0 + _rng.randf_range(-1.0, 1.0) * float(params[3])
	voice.play()
	_mark_played(id)


func _free_world_voice() -> AudioStreamPlayer2D:
	for k in _world_voices.size():
		var v := _world_voices[(_world_voice_cursor + k) % _world_voices.size()]
		if not v.playing:
			_world_voice_cursor = (_world_voice_cursor + k + 1) % _world_voices.size()
			return v
	# Все заняты — забираем самый старый по кругу.
	var oldest := _world_voices[_world_voice_cursor]
	_world_voice_cursor = (_world_voice_cursor + 1) % _world_voices.size()
	return oldest


## Дальше этого расстояния от центра экрана звук не слышен: весь экран и ещё полэкрана.
func _hearing_distance() -> float:
	if _game == null or _game.camera == null:
		return 2000.0
	var view := _game.camera.get_world_view_rect()
	return view.size.length() * 0.8


# --- Игра ---

## Подключить игровую сцену (Game зовёт в _build_scene) — звуки мира и музыка по обстановке.
func attach(game: Game) -> void:
	_game = game
	_world = null
	_bind_run(game.run)


func detach(game: Game) -> void:
	if _game == game:
		_game = null
		_world = null
		_bind_run(null)


func _bind_run(run: Run) -> void:
	if _run == run:
		return
	if _run != null:
		if _run.teleport_starting.is_connected(_on_teleport):
			_run.teleport_starting.disconnect(_on_teleport)
		if _run.research != null and _run.research.completed.is_connected(_on_research_completed):
			_run.research.completed.disconnect(_on_research_completed)
	_run = run
	_last_wave = -1
	_was_warning = false
	if _run != null:
		_run.teleport_starting.connect(_on_teleport)
		if _run.research != null:
			_run.research.completed.connect(_on_research_completed)


func _on_teleport() -> void:
	play_ui(&"teleport")


func _on_research_completed(_research: ResearchDef) -> void:
	play_ui(&"research_done")


func _on_toast(_text: String, kind: Events.ToastKind) -> void:
	match kind:
		Events.ToastKind.WARNING:
			play_ui(&"ui_error")
		Events.ToastKind.INFO:
			play_ui(&"ui_notify")


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not (node as BaseButton).pressed.is_connected(_on_button_pressed):
		(node as BaseButton).pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play_ui(&"ui_click")


# --- Кадр ---

func _process(delta: float) -> void:
	if not _enabled:
		return
	_time += delta
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		_finish_generation()
	if _game != null and not is_instance_valid(_game):
		_game = null
	if _game != null and _game.run != _run:
		# Забег заменён целиком (вход в сеть, снимок) — подписки на новый.
		_bind_run(_game.run)
	if _game != null and _game.world != null:
		_drain_world_sounds()
		_watch_threat()
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_PERIOD
		_update_music_state(STATE_PERIOD)
		_update_ambience()
	_mix_music(delta)


## Новые события активного мира: по голосу на вид события за кадр, ближайший к центру экрана.
func _drain_world_sounds() -> void:
	var world := _game.world
	var sound_log := world.sounds
	if world != _world:
		# Сменился этаж или мир: старые события не озвучиваем.
		_world = world
		_cursor = sound_log.written
		return
	var from := maxi(_cursor, sound_log.oldest())
	_cursor = sound_log.written
	if from >= sound_log.written:
		return
	var view := _game.camera.get_world_view_rect()
	var heard := view.grow(maxf(view.size.x, view.size.y) * 0.3)
	var center := view.get_center()
	var counts := PackedInt32Array()
	counts.resize(KIND_SOUNDS.size())
	counts.fill(0)
	var nearest: Array[Vector2] = []
	nearest.resize(KIND_SOUNDS.size())
	for n in range(from, sound_log.written):
		var slot := n % SoundLog.CAPACITY
		var at := Vector2(sound_log.xs[slot], sound_log.ys[slot])
		if not heard.has_point(at):
			continue
		var kind := int(sound_log.kinds[slot])
		if kind >= KIND_SOUNDS.size():
			continue
		if counts[kind] == 0 or at.distance_squared_to(center) < nearest[kind].distance_squared_to(center):
			nearest[kind] = at
		counts[kind] += 1
	for kind in counts.size():
		if counts[kind] > 0:
			# Много одинаковых событий за кадр — чуть громче, но не больше +6 дБ.
			play_at(KIND_SOUNDS[kind], nearest[kind], minf(3.0 * log(float(counts[kind])) / log(2.0), 6.0))


## Волна: предупреждение и начало — по состоянию угрозы планеты.
func _watch_threat() -> void:
	var planet := _game.run.planet if _game.run != null else null
	if planet == null or planet.threat == null:
		return
	var threat := planet.threat
	var tick := planet.simulation.tick
	var warning := threat.is_warning(tick)
	if warning and not _was_warning:
		play_ui(&"wave_warning")
	_was_warning = warning
	if _last_wave >= 0 and threat.wave > _last_wave:
		play_ui(&"wave_start")
	_last_wave = threat.wave


# --- Музыка ---

## Какое состояние музыки просит обстановка прямо сейчас.
func _wanted_state() -> MusicState:
	if _game == null or _game.run == null or _game.world == null:
		return MusicState.MENU
	var world := _game.world
	var view := _game.camera.get_world_view_rect()
	var near := view.grow(maxf(view.size.x, view.size.y) * 0.5)
	var enemies := world.enemies
	if enemies != null:
		for i in enemies.count:
			if near.has_point(Vector2(enemies.pos_x[i], enemies.pos_y[i])):
				return MusicState.COMBAT
	var tick := world.simulation.tick
	if tick - world.last_attack_tick < 4 * GameConst.TICK_RATE and near.has_point(world.last_attack_position):
		return MusicState.COMBAT
	var planet := _game.run.planet
	if planet != null and planet.threat != null:
		var planet_tick := planet.simulation.tick
		if planet.threat.is_warning(planet_tick) or planet.threat.is_spawning(planet_tick) or planet.enemies.count > 0:
			return MusicState.TENSION
	return MusicState.CALM


## Смена состояния с задержкой на спуск: вверх — сразу, вниз — если спокойнее уже held секунд.
static func next_state(current: int, wanted: int, held: float) -> int:
	if wanted > current:
		return wanted
	if wanted < current and held >= CALM_DOWN_SECONDS:
		return wanted
	return current


func _update_music_state(step: float) -> void:
	var wanted := _wanted_state()
	if wanted < music_state:
		_lower_held += step
	else:
		_lower_held = 0.0
	# Меню и игра сменяются сразу, без выдержки.
	var is_menu_switch := (wanted == MusicState.MENU) != (music_state == MusicState.MENU)
	var next := wanted if is_menu_switch else next_state(music_state, wanted, _lower_held)
	if next != music_state:
		music_state = next as MusicState
		_lower_held = 0.0
		_on_music_state_changed()


func _on_music_state_changed() -> void:
	var tracks: Array = _music_tracks.get(int(music_state), [])
	if tracks.is_empty():
		_track_target.fill(0.0)
		return
	# Свои треки этого состояния: включаем на свободном проигрывателе, другой гаснет.
	var slot := 0 if _track_amp[0] <= _track_amp[1] else 1
	_start_track(slot, int(music_state))
	_track_target[1 - slot] = 0.0


func _start_track(slot: int, state: int) -> void:
	var tracks: Array = _music_tracks.get(state, [])
	if tracks.is_empty():
		return
	var player := _tracks[slot]
	player.stream = tracks[_rng.randi() % tracks.size()]
	player.volume_db = -80.0
	_track_amp[slot] = 0.0
	player.play()
	_track_state[slot] = state
	_track_target[slot] = 1.0


func _on_track_finished(slot: int) -> void:
	# Трек кончился, а состояние то же — следующий трек того же состояния.
	if _track_target[slot] > 0.0 and _track_state[slot] == int(music_state):
		_start_track(slot, _track_state[slot])


func _mix_music(delta: float) -> void:
	var own_tracks := _music_tracks.has(int(music_state))
	var mix: Array = LAYER_MIX[int(music_state)]
	var step := FADE_PER_SECOND * delta
	for k in _layers.size():
		var target := 0.0 if own_tracks else float(mix[k])
		_layer_amp[k] = move_toward(_layer_amp[k], target, step)
		_layers[k].volume_db = linear_to_db(maxf(_layer_amp[k], 0.0001)) + MUSIC_GAIN_DB
	for k in _tracks.size():
		_track_amp[k] = move_toward(_track_amp[k], _track_target[k], step)
		_tracks[k].volume_db = linear_to_db(maxf(_track_amp[k], 0.0001)) + MUSIC_GAIN_DB
		if _track_amp[k] <= 0.0 and _track_target[k] <= 0.0 and _tracks[k].playing:
			_tracks[k].stop()
	_ambience_amp = move_toward(_ambience_amp, _ambience_target, step)
	if _ambience != null:
		_ambience.volume_db = linear_to_db(maxf(_ambience_amp * Settings.get_float(&"audio/ambience"), 0.0001))


## Фон цеха: чем больше работающих зданий на экране, тем громче (до 30 — полная громкость).
func _update_ambience() -> void:
	_ambience_target = 0.0
	if _game == null or _game.world == null or _game.camera == null:
		return
	var world := _game.world
	var grid := world.grid
	var view := _game.camera.get_world_view_rect()
	var chunks := grid.chunk_range_for_world_rect(view)
	var working := 0
	for cy in range(chunks.position.y, chunks.end.y):
		for cx in range(chunks.position.x, chunks.end.x):
			for id in world.buildings.get_chunk_ids(cy * grid.chunks_x() + cx):
				var b := world.buildings.get_by_id(id)
				if b != null and b.get_status() == Building.Status.WORKING:
					working += 1
	_ambience_target = clampf(float(working) / 30.0, 0.0, 1.0) * 0.5
