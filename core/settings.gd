extends Node
## Настройки игры (автозагрузка Settings).
## Описания настроек задаются списком SettingEntry — по нему строится меню,
## выполняется сохранение в user://settings.cfg и применение при запуске.

signal changed(key: StringName)
signal bindings_changed

const PATH := "user://settings.cfg"

const TAB_GRAPHICS := &"graphics"
const TAB_GAME := &"game"
const TAB_AUDIO := &"audio"

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

const SAVE_DELAY := 0.6

var entries: Array[SettingEntry] = []
var _by_key: Dictionary[StringName, SettingEntry] = {}
var _values: Dictionary[StringName, Variant] = {}
var _save_timer: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_entries()
	for e in entries:
		_values[e.key] = e.default_value
	InputActions.apply_bindings({})
	_ensure_audio_buses()
	load_from_disk()
	get_tree().root.theme = UiTheme.get_theme()
	apply_all()


func _process(delta: float) -> void:
	if _save_timer >= 0.0:
		_save_timer -= delta
		if _save_timer < 0.0:
			save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _save_timer >= 0.0:
			save_now()


# --- Доступ к значениям ---

func get_value(key: StringName) -> Variant:
	return _values.get(key)


func get_bool(key: StringName) -> bool:
	return bool(_values.get(key, false))


func get_float(key: StringName) -> float:
	return float(_values.get(key, 0.0))


func get_int(key: StringName) -> int:
	return int(_values.get(key, 0))


func get_string(key: StringName) -> String:
	return str(_values.get(key, ""))


func get_entry(key: StringName) -> SettingEntry:
	return _by_key.get(key)


func entries_for_tab(tab: StringName) -> Array[SettingEntry]:
	var result: Array[SettingEntry] = []
	for e in entries:
		if e.tab == tab:
			result.append(e)
	return result


func set_value(key: StringName, value: Variant) -> void:
	var entry: SettingEntry = _by_key.get(key)
	if entry == null:
		push_error("Settings: неизвестная настройка " + key)
		return
	var sanitized: Variant = entry.sanitize(value)
	if SettingEntry.same_value(_values.get(key), sanitized):
		return
	_values[key] = sanitized
	_apply(key)
	changed.emit(key)
	_schedule_save()


func reset_tab(tab: StringName) -> void:
	for e in entries_for_tab(tab):
		set_value(e.key, e.default_value)


# --- Управление ---

func set_action_codes(action: StringName, codes: PackedStringArray) -> void:
	var bindings := InputActions.current_bindings()
	bindings[action] = codes
	InputActions.apply_bindings(bindings)
	bindings_changed.emit()
	_schedule_save()


func reset_bindings() -> void:
	InputActions.apply_bindings({})
	bindings_changed.emit()
	_schedule_save()


# --- Сохранение ---

func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for e in entries:
		var parts := String(e.key).split("/")
		if cfg.has_section_key(parts[0], parts[1]):
			_values[e.key] = e.sanitize(cfg.get_value(parts[0], parts[1]))
	if cfg.has_section("input"):
		var bindings: Dictionary = {}
		for action in cfg.get_section_keys("input"):
			var v: Variant = cfg.get_value("input", action)
			if v is PackedStringArray:
				bindings[StringName(action)] = v
			elif v is Array:
				bindings[StringName(action)] = PackedStringArray(v)
		InputActions.apply_bindings(bindings)


func save_now() -> void:
	_save_timer = -1.0
	var cfg := ConfigFile.new()
	for e in entries:
		var parts := String(e.key).split("/")
		cfg.set_value(parts[0], parts[1], _values[e.key])
	var bindings := InputActions.current_bindings()
	for action in bindings:
		cfg.set_value("input", String(action), bindings[action])
	var error := cfg.save(PATH)
	if error != OK:
		push_error("Settings: не удалось сохранить %s (%s)" % [PATH, error_string(error)])


func apply_all() -> void:
	for e in entries:
		_apply(e.key)


func _schedule_save() -> void:
	_save_timer = SAVE_DELAY


# --- Применение ---

func _apply(key: StringName) -> void:
	match key:
		&"graphics/window_mode", &"graphics/resolution":
			_apply_window()
		&"graphics/vsync":
			if not is_headless():
				DisplayServer.window_set_vsync_mode(get_int(key) as DisplayServer.VSyncMode)
		&"graphics/max_fps":
			Engine.max_fps = get_int(key)
		&"graphics/smooth_textures":
			get_tree().root.canvas_item_default_texture_filter = \
				Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR if get_bool(key) \
				else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		&"game/language":
			TranslationServer.set_locale(get_string(key))
		&"game/ui_scale":
			get_tree().root.content_scale_factor = get_float(key)
		&"audio/master":
			_apply_bus_volume(BUS_MASTER, get_float(key))
		&"audio/music":
			_apply_bus_volume(BUS_MUSIC, get_float(key))
		&"audio/sfx":
			_apply_bus_volume(BUS_SFX, get_float(key))


func _apply_window() -> void:
	if is_headless():
		return
	match get_int(&"graphics/window_mode"):
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size := parse_resolution(get_string(&"graphics/resolution"))
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			if usable.size.x > 0 and usable.size.y > 0:
				size = size.min(usable.size)
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _apply_bus_volume(bus_name: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, volume <= 0.001)
	AudioServer.set_bus_volume_linear(index, maxf(volume, 0.0001))


func _ensure_audio_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, BUS_MASTER)


# --- Описание настроек ---

func _build_entries() -> void:
	# Графика
	_add(SettingEntry.make_choice(&"graphics/window_mode", TAB_GRAPHICS, 0, "SET_WINDOW_MODE",
		[[0, "SET_WINDOW_WINDOWED"], [1, "SET_WINDOW_BORDERLESS"], [2, "SET_WINDOW_EXCLUSIVE"]]))
	var resolutions := _resolution_choices()
	var default_resolution: String = resolutions[resolutions.size() - 1][0]
	for pair in resolutions:
		if pair[0] == "1600x900":
			default_resolution = "1600x900"
	_add(SettingEntry.make_choice(&"graphics/resolution", TAB_GRAPHICS, default_resolution, "SET_RESOLUTION",
		resolutions, "SET_RESOLUTION_HINT"))
	_add(SettingEntry.make_choice(&"graphics/vsync", TAB_GRAPHICS, 1, "SET_VSYNC",
		[[0, "SET_VSYNC_OFF"], [1, "SET_VSYNC_ON"], [2, "SET_VSYNC_ADAPTIVE"]], "SET_VSYNC_HINT"))
	_add(SettingEntry.make_choice(&"graphics/max_fps", TAB_GRAPHICS, 0, "SET_MAX_FPS",
		[[0, "SET_FPS_UNLIMITED"], [30, "30"], [60, "60"], [75, "75"], [120, "120"], [144, "144"], [165, "165"], [240, "240"]]))
	_add(SettingEntry.make_bool(&"graphics/smooth_textures", TAB_GRAPHICS, false, "SET_SMOOTH_TEXTURES", "SET_SMOOTH_TEXTURES_HINT"))
	_add(SettingEntry.make_bool(&"graphics/show_fps", TAB_GRAPHICS, false, "SET_SHOW_FPS"))

	# Игра и интерфейс
	_add(SettingEntry.make_choice(&"game/language", TAB_GAME, _default_locale(), "SET_LANGUAGE",
		[["ru", "Русский"], ["en", "English"]]))
	var ui_scale := SettingEntry.make_range(&"game/ui_scale", TAB_GAME, 1.0, "SET_UI_SCALE", 0.75, 2.0, 0.05, true, "SET_UI_SCALE_HINT")
	ui_scale.apply_on_release = true
	_add(ui_scale)
	var pan := SettingEntry.make_range(&"game/pan_speed", TAB_GAME, 1.0, "SET_PAN_SPEED", 0.25, 3.0, 0.05)
	pan.suffix = "×"
	_add(pan)
	var zoom := SettingEntry.make_range(&"game/zoom_speed", TAB_GAME, 1.0, "SET_ZOOM_SPEED", 0.25, 3.0, 0.05)
	zoom.suffix = "×"
	_add(zoom)
	_add(SettingEntry.make_bool(&"game/smooth_zoom", TAB_GAME, true, "SET_SMOOTH_ZOOM"))
	_add(SettingEntry.make_bool(&"game/edge_pan", TAB_GAME, false, "SET_EDGE_PAN", "SET_EDGE_PAN_HINT"))
	_add(SettingEntry.make_bool(&"game/show_grid", TAB_GAME, true, "SET_SHOW_GRID"))
	_add(SettingEntry.make_bool(&"game/confirm_mass_delete", TAB_GAME, true, "SET_CONFIRM_MASS_DELETE", "SET_CONFIRM_MASS_DELETE_HINT"))
	var autosave := SettingEntry.make_choice(&"game/autosave", TAB_GAME, 5, "SET_AUTOSAVE",
		[[0, "SET_AUTOSAVE_OFF"], [2, "SET_AUTOSAVE_2"], [5, "SET_AUTOSAVE_5"], [10, "SET_AUTOSAVE_10"]], "SET_AUTOSAVE_HINT")
	autosave.enabled = false
	_add(autosave)

	# Звук
	_add(SettingEntry.make_range(&"audio/master", TAB_AUDIO, 1.0, "SET_VOLUME_MASTER", 0.0, 1.0, 0.01, true))
	_add(SettingEntry.make_range(&"audio/music", TAB_AUDIO, 0.8, "SET_VOLUME_MUSIC", 0.0, 1.0, 0.01, true))
	_add(SettingEntry.make_range(&"audio/sfx", TAB_AUDIO, 0.8, "SET_VOLUME_SFX", 0.0, 1.0, 0.01, true))


func _add(entry: SettingEntry) -> void:
	entries.append(entry)
	_by_key[entry.key] = entry


func _resolution_choices() -> Array:
	var all: Array[Vector2i] = [
		Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	]
	var screen := Vector2i.ZERO
	if not is_headless():
		screen = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array = []
	for r in all:
		if screen.x <= 0 or (r.x <= screen.x and r.y <= screen.y) or r == Vector2i(1280, 720):
			var text := "%dx%d" % [r.x, r.y]
			result.append([text, text.replace("x", " × ")])
	return result


static func parse_resolution(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2:
		return Vector2i(1600, 900)
	return Vector2i(maxi(parts[0].to_int(), 640), maxi(parts[1].to_int(), 360))


func _default_locale() -> String:
	return "ru" if OS.get_locale_language() == "ru" else "en"


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
