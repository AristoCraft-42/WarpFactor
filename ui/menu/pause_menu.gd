class_name PauseMenu
extends CanvasLayer
## Меню паузы в игре: продолжить, настройки, сохранение и загрузка, выход в меню или из игры.

signal closed

var _dimmer: ColorRect
var _main_panel: PanelContainer
var _settings_holder: CenterContainer
var _settings: SettingsMenu
var _saves_holder: CenterContainer
var _saves: SavesScreen
## Текущий забег (для сохранения).
var run: Run
var _net_button: Button
var _steam_button: Button
var _invite_button: Button
var _net_status: Label


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
	_net_button = UiUtil.button("PAUSE_HOST", _toggle_host)
	column.add_child(_net_button)
	_steam_button = UiUtil.button("PAUSE_HOST_STEAM", _toggle_steam_host)
	column.add_child(_steam_button)
	_invite_button = UiUtil.button("PAUSE_STEAM_INVITE", func() -> void:
		var lobbies := Session.get_lobbies()
		if lobbies != null:
			lobbies.invite_overlay())
	column.add_child(_invite_button)
	_net_status = Label.new()
	_net_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_net_status.theme_type_variation = &"DimLabel"
	column.add_child(_net_status)
	column.add_child(UiUtil.button("PAUSE_SAVE", _open_saves.bind(SavesScreen.Mode.SAVE)))
	column.add_child(UiUtil.button("MENU_LOAD", _open_saves.bind(SavesScreen.Mode.LOAD)))
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

	_saves_holder = CenterContainer.new()
	UiUtil.full_rect(_saves_holder)
	_saves_holder.visible = false
	root.add_child(_saves_holder)
	_saves = SavesScreen.new()
	_saves.back_requested.connect(_close_saves)
	_saves_holder.add_child(_saves)


## Открыть текущий забег по локальной сети (или закрыть сетевую игру).
func _toggle_host() -> void:
	_host_or_close(false)


## Открыть текущий забег через Steam: друзья увидят лобби и смогут зайти по приглашению.
func _toggle_steam_host() -> void:
	_host_or_close(true)


func _host_or_close(use_steam: bool) -> void:
	if Session.net.is_networked():
		Session.net.close()
		if Session.discovery != null:
			Session.discovery.stop()
		if Session.lobbies != null:
			Session.lobbies.leave()
		_refresh_net()
		return
	if run == null:
		return
	Session.host_run(run, use_steam)
	_refresh_net()


func _refresh_net() -> void:
	if _net_button == null:
		return
	var net := Session.net
	_net_button.text = "PAUSE_NET_CLOSE" if net.is_networked() else "PAUSE_HOST"
	_steam_button.visible = SteamService.has_addon() and not net.is_networked()
	_invite_button.visible = SteamService.has_addon() and net.role == NetSession.Role.HOST \
		and Session.lobbies != null and Session.lobbies.current_lobby != 0
	if net.role == NetSession.Role.HOST:
		_net_status.text = tr("NET_HOSTING") % NetProtocol.DEFAULT_PORT
	elif net.role == NetSession.Role.CLIENT:
		_net_status.text = tr("NET_CONNECTED")
	elif net.last_error == "port":
		_net_status.text = tr("NET_PORT_BUSY") % NetProtocol.DEFAULT_PORT
	else:
		_net_status.text = ""


func open() -> void:
	visible = true
	_main_panel.visible = true
	_settings_holder.visible = false
	_saves_holder.visible = false
	_refresh_net()


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
		elif _saves_holder.visible:
			_close_saves()
		else:
			close()


func _open_settings() -> void:
	_main_panel.visible = false
	_settings_holder.visible = true
	_settings.refresh()


func _open_saves(mode: SavesScreen.Mode) -> void:
	_main_panel.visible = false
	_saves_holder.visible = true
	_saves.open(mode, run)


func _close_saves() -> void:
	_saves_holder.visible = false
	_main_panel.visible = true


func _close_settings() -> void:
	_settings_holder.visible = false
	_main_panel.visible = true
