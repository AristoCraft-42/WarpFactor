class_name PauseMenu
extends CanvasLayer
## Меню паузы в игре: продолжить, настройки, сохранение (этап 6), выход в меню или из игры.

signal closed

var _dimmer: ColorRect
var _main_panel: PanelContainer
var _settings_holder: CenterContainer
var _settings: SettingsMenu


func _ready() -> void:
	layer = 50
	visible = false

	var root := UiUtil.full_rect(Control.new())
	root.theme = UiTheme.get_theme()
	add_child(root)

	_dimmer = UiUtil.dimmer(0.55)
	root.add_child(_dimmer)

	var center := CenterContainer.new()
	UiUtil.full_rect(center)
	root.add_child(center)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(_main_panel)
	var column := UiUtil.vbox(10)
	_main_panel.add_child(column)
	var title := UiUtil.label("PAUSE_TITLE", &"HeaderLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(HSeparator.new())
	column.add_child(UiUtil.button("PAUSE_RESUME", close, &"AccentButton"))
	column.add_child(UiUtil.button("MENU_SETTINGS", _open_settings))
	var save_button := UiUtil.button("PAUSE_SAVE")
	save_button.disabled = true
	save_button.tooltip_text = "TOOLTIP_SAVES_LATER"
	column.add_child(save_button)
	var load_button := UiUtil.button("MENU_LOAD")
	load_button.disabled = true
	load_button.tooltip_text = "TOOLTIP_SAVES_LATER"
	column.add_child(load_button)
	column.add_child(HSeparator.new())
	column.add_child(UiUtil.button("PAUSE_EXIT_TO_MENU", func() -> void: Session.exit_to_menu()))
	column.add_child(UiUtil.button("MENU_QUIT", func() -> void: Session.quit_game()))

	_settings_holder = CenterContainer.new()
	UiUtil.full_rect(_settings_holder)
	_settings_holder.visible = false
	root.add_child(_settings_holder)
	_settings = SettingsMenu.new()
	_settings.closed.connect(_close_settings)
	_settings_holder.add_child(_settings)


func open() -> void:
	visible = true
	_main_panel.visible = true
	_settings_holder.visible = false


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		if _settings_holder.visible:
			if not _settings.is_capturing():
				_close_settings()
		else:
			close()


func _open_settings() -> void:
	_main_panel.visible = false
	_settings_holder.visible = true
	_settings.refresh()


func _close_settings() -> void:
	_settings_holder.visible = false
	_main_panel.visible = true
