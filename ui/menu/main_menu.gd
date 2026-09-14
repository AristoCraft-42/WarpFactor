class_name MainMenu
extends Control
## Главное меню: слева — кнопки, справа — открытая страница (новый забег, загрузка или настройки).
## «Продолжить» загружает последнее сохранение.
## На фоне медленно проплывает карта одного из уровней.

const VERSION_TEXT := "v%s"

var _background: TextureRect
var _pages: CenterContainer
var _new_run: NewRunScreen
var _saves: SavesScreen
var _settings: SettingsMenu
var _buttons: Array[Button] = []


func _ready() -> void:
	Registry.ensure_loaded()
	ArtRegistry.ensure_built()
	UiUtil.full_rect(self, false)

	_build_background()

	var margin := UiUtil.margin(56)
	UiUtil.full_rect(margin)
	add_child(margin)
	var layout := UiUtil.hbox(48)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	var left := UiUtil.vbox(14)
	left.custom_minimum_size = Vector2(380, 0)
	layout.add_child(left)
	left.add_child(UiUtil.spacer(false))
	var title := Label.new()
	title.text = "FLOWWORKS"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = &"TitleLabel"
	left.add_child(title)
	var subtitle := UiUtil.label("MENU_SUBTITLE", &"DimLabel")
	subtitle.add_theme_font_size_override("font_size", 18)
	left.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	left.add_child(gap)

	var has_saves := not SaveIO.list_saves().is_empty()
	var continue_button := _add_menu_button(left, "MENU_CONTINUE", _continue_latest, &"BigButton")
	continue_button.disabled = not has_saves
	_add_menu_button(left, "MENU_NEW_RUN", _show_new_run, &"BigButton")
	var load_button := _add_menu_button(left, "MENU_LOAD", _show_saves, &"BigButton")
	load_button.disabled = not has_saves
	_add_menu_button(left, "MENU_SETTINGS", _show_settings, &"BigButton")
	_add_menu_button(left, "MENU_QUIT", func() -> void: Session.quit_game(), &"BigButton")

	left.add_child(UiUtil.spacer(false))
	var version := Label.new()
	version.text = VERSION_TEXT % ProjectSettings.get_setting("application/config/version", "0.0.0")
	version.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	version.theme_type_variation = &"DimLabel"
	left.add_child(version)

	_pages = CenterContainer.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_pages)

	_new_run = NewRunScreen.new()
	_new_run.visible = false
	_new_run.back_requested.connect(_close_pages)
	_pages.add_child(_new_run)
	_saves = SavesScreen.new()
	_saves.visible = false
	_saves.back_requested.connect(_close_pages)
	_pages.add_child(_saves)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_close_pages)
	_pages.add_child(_settings)

	if not _buttons.is_empty():
		_buttons[0].grab_focus.call_deferred()

	if OS.get_cmdline_user_args().has("--autoshot"):
		# Отладочный прогон со скриншотами (tests/autoshot.gd), только по флагу командной строки.
		var script: Script = load("res://tests/autoshot.gd")
		if script != null:
			add_child(script.new())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and (_new_run.visible or _settings.visible or _saves.visible):
		if _settings.visible and _settings.is_capturing():
			return
		get_viewport().set_input_as_handled()
		_close_pages()


func _add_menu_button(parent: Control, key: String, callback: Callable, variation: StringName) -> Button:
	var b := UiUtil.button(key, callback, variation)
	b.custom_minimum_size = Vector2(320, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(b)
	_buttons.append(b)
	return b


func _show_new_run() -> void:
	_settings.visible = false
	_saves.visible = false
	_new_run.visible = true


func _show_saves() -> void:
	_settings.visible = false
	_new_run.visible = false
	_saves.open(SavesScreen.Mode.LOAD)


func _continue_latest() -> void:
	var path := SaveIO.latest_save_path()
	if not path.is_empty():
		Session.load_game(path)


func _show_settings() -> void:
	_new_run.visible = false
	_saves.visible = false
	_settings.visible = true
	_settings.refresh()


func _close_pages() -> void:
	_new_run.visible = false
	_saves.visible = false
	_settings.visible = false


func _build_background() -> void:
	var base := ColorRect.new()
	base.color = UiTheme.BG_HARD
	UiUtil.full_rect(base)
	add_child(base)

	_background = TextureRect.new()
	UiUtil.full_rect(_background)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.modulate = Color(0.55, 0.55, 0.55)
	add_child(_background)

	# Самая большая карта кампании лучше всего смотрится на фоне.
	var best: LevelMap = null
	for level in Registry.levels:
		var map := LevelIO.load_map(level.map_path)
		if map != null and (best == null or map.width * map.height > best.width * best.height):
			best = map
	if best != null:
		var img := MapPreview.build_terrain_image(best.width, best.height, best.floors, best.ores)
		MapPreview.draw_placements(img, best.placements)
		_background.texture = ImageTexture.create_from_image(img)
		_background.resized.connect(func() -> void: _background.pivot_offset = _background.size * 0.5)
		var tween := create_tween().set_loops()
		tween.tween_property(_background, "scale", Vector2(1.12, 1.12), 18.0).set_trans(Tween.TRANS_SINE)
		tween.tween_property(_background, "scale", Vector2(1.0, 1.0), 18.0).set_trans(Tween.TRANS_SINE)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiTheme.BG_HARD, 0.92))
	gradient.set_color(1, Color(UiTheme.BG_HARD, 0.25))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(1, 0)
	var shade_rect := TextureRect.new()
	UiUtil.full_rect(shade_rect)
	shade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade_rect.stretch_mode = TextureRect.STRETCH_SCALE
	shade_rect.texture = gradient_texture
	add_child(shade_rect)
