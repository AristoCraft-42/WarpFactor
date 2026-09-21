class_name NetworkScreen
extends PanelContainer
## Подключение к совместной игре: имя игрока, список игр в локальной сети и прямой адрес.
## Сама игра приходит снимком от хоста — свой забег для этого не нужен.

signal back_requested

const REFRESH := 1.5

var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: LineEdit
var _list: ItemList
var _status: Label
var _join_button: Button
var _timer: float = 0.0
var _addresses: PackedStringArray = PackedStringArray()
var _steam_box: VBoxContainer
var _steam_list: ItemList
var _lobbies: Array = []
## До какого момента (мс) показываем в статусе проверку связи со Steam.
var _probe_until: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(760, 520)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := UiUtil.vbox(12)
	add_child(root)
	var title := UiUtil.label("NET_JOIN_TITLE", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	root.add_child(UiUtil.label("NET_JOIN_HINT", &"DimLabel"))

	var name_row := UiUtil.hbox(8)
	root.add_child(name_row)
	name_row.add_child(UiUtil.label("NET_PLAYER_NAME"))
	_name_edit = LineEdit.new()
	_name_edit.text = Session.get_player_name()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)

	# Лобби Steam — только если установлен аддон GodotSteam.
	_steam_box = UiUtil.vbox(6)
	root.add_child(_steam_box)
	_steam_box.add_child(UiUtil.label("NET_STEAM_LOBBIES", &"DimLabel"))
	_steam_list = ItemList.new()
	_steam_list.custom_minimum_size = Vector2(0, 120)
	_steam_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_steam_list.item_activated.connect(func(index: int) -> void: _join_lobby(index))
	_steam_box.add_child(_steam_list)
	var steam_row := UiUtil.hbox(8)
	_steam_box.add_child(steam_row)
	steam_row.add_child(UiUtil.button("NET_STEAM_JOIN", func() -> void:
		var selected := _steam_list.get_selected_items()
		if not selected.is_empty():
			_join_lobby(selected[0])))
	steam_row.add_child(UiUtil.button("NET_STEAM_REFRESH", func() -> void:
		var lobbies := Session.get_lobbies()
		if lobbies != null:
			lobbies.refresh()))
	steam_row.add_child(UiUtil.button("NET_STEAM_PROBE", func() -> void:
		_probe_until = Time.get_ticks_msec() + 30000
		NetLog.write("проверка", "игрок нажал «Проверить связь со Steam»")))
	_steam_box.visible = false

	root.add_child(UiUtil.label("NET_FOUND", &"DimLabel"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(func(index: int) -> void:
		_on_item_selected(index)
		_join())
	root.add_child(_list)

	var address_row := UiUtil.hbox(8)
	root.add_child(address_row)
	address_row.add_child(UiUtil.label("NET_ADDRESS"))
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "127.0.0.1"
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(_address_edit)
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetProtocol.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(90, 0)
	address_row.add_child(_port_edit)

	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.theme_type_variation = &"DimLabel"
	root.add_child(_status)

	var buttons := UiUtil.hbox(8)
	root.add_child(buttons)
	_join_button = UiUtil.button("NET_CONNECT", _join, &"AccentButton")
	buttons.add_child(_join_button)
	buttons.add_child(UiUtil.button("NET_OPEN_LOG", func() -> void:
		DirAccess.make_dir_recursive_absolute(NetLog.DIR)
		OS.shell_open(NetLog.folder())))
	buttons.add_child(UiUtil.spacer(true))
	buttons.add_child(UiUtil.button("BACK", func() -> void: back_requested.emit()))

	if Session.discovery == null:
		Session.discovery = LanDiscovery.new()
	Session.discovery.listen()
	Session.discovery.refresh()
	Session.net.notice.connect(_on_notice)
	_setup_steam()


## Steam: поднимаем API и подписываемся на список лобби, если аддон установлен.
func _setup_steam() -> void:
	if not SteamService.has_addon() or not SteamService.start():
		return
	var lobbies := Session.get_lobbies()
	if lobbies == null:
		return
	_steam_box.visible = true
	if not lobbies.listed.is_connected(_on_lobbies):
		lobbies.listed.connect(_on_lobbies)
	if not Session.join_status.is_connected(_on_join_status):
		Session.join_status.connect(_on_join_status)
	if not SteamService.self_name().is_empty():
		_name_edit.text = SteamService.self_name()
	lobbies.refresh()


func _on_lobbies(list: Array) -> void:
	_lobbies = list
	_steam_list.clear()
	for entry in list:
		var lobby: Dictionary = entry
		_steam_list.add_item("%s (%d)" % [String(lobby.get("name", "?")), int(lobby.get("players", 1))])
	if list.is_empty() and not Session.net.is_networked():
		_status.text = tr("NET_STEAM_EMPTY")


func _join_lobby(index: int) -> void:
	if index < 0 or index >= _lobbies.size():
		return
	var lobbies := Session.get_lobbies()
	if lobbies == null:
		return
	Session.player_name = _name_edit.text.strip_edges()
	_status.text = tr("NET_CONNECTING") % String((_lobbies[index] as Dictionary).get("name", "?"))
	lobbies.join(int((_lobbies[index] as Dictionary).get("id", 0)))


func _on_join_status(text: String) -> void:
	_status.text = text


func _exit_tree() -> void:
	if Session.discovery != null:
		Session.discovery.stop()
	# Ушли с экрана, так и не войдя: попытку закрываем, чтобы она не прицепилась к своей игре.
	Session.drop_pending_join()


func _process(delta: float) -> void:
	if Time.get_ticks_msec() < _probe_until:
		var status := SteamService.relay_status()
		if status == 100:
			_status.text = tr("NET_PROBE_OK")
			_probe_until = 0
			NetLog.write("проверка", "ретрансляторы Valve доступны")
			for line in SteamService.nearest_pops():
				NetLog.write("проверка", "  " + line)
		elif status <= -100:
			_status.text = tr("NET_PROBE_FAILED")
			_probe_until = 0
			NetLog.write("проверка", "ретрансляторы Valve НЕ доступны (%d)" % status)
		else:
			_status.text = tr("NET_PROBE_WAIT")
		return
	# Идёт вход: показываем, как он идёт, и не затираем это поиском игр.
	if Session.net.role == NetSession.Role.CLIENT and Session.net.run == null:
		_status.text = _join_progress()
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	if Session.discovery != null:
		Session.discovery.refresh()
	_refresh_list()


func _join_progress() -> String:
	var steam := Session.net.transport as SteamTransport
	if steam != null:
		var progress := steam.incoming_progress()
		if progress.y > 0:
			return tr("NET_RECEIVING_WORLD") % [progress.x, progress.y]
		if steam.is_connecting():
			return tr("NET_KNOCKING")
	return tr("NET_WAITING_WORLD")


func _refresh_list() -> void:
	var found := Session.discovery.found if Session.discovery != null else {}
	var selected := _list.get_selected_items()
	var keep := _addresses[selected[0]] if not selected.is_empty() and selected[0] < _addresses.size() else ""
	_list.clear()
	_addresses = PackedStringArray()
	for address in found:
		var info: Dictionary = found[address]
		_list.add_item("%s — %s:%d (%d)" % [String(info.get("name", address)), address,
			int(info.get("port", NetProtocol.DEFAULT_PORT)), int(info.get("players", 1))])
		_addresses.append(address)
	if _list.item_count == 0 and _status.text.is_empty():
		_status.text = tr("NET_SEARCHING")
	for i in _addresses.size():
		if _addresses[i] == keep:
			_list.select(i)


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _addresses.size():
		return
	var address := _addresses[index]
	var info: Dictionary = Session.discovery.found.get(address, {})
	_address_edit.text = address
	_port_edit.text = str(int(info.get("port", NetProtocol.DEFAULT_PORT)))


func _join() -> void:
	var address := _address_edit.text.strip_edges()
	if address.is_empty():
		_status.text = tr("NET_NEED_ADDRESS")
		return
	Session.player_name = _name_edit.text.strip_edges()
	Settings.set_value(&"game/player_name", Session.player_name)
	var port := _port_edit.text.to_int()
	if port <= 0:
		port = NetProtocol.DEFAULT_PORT
	_status.text = tr("NET_CONNECTING") % address
	_join_button.disabled = true
	if not Session.net.join_run(address, port, Session.get_player_name()):
		_status.text = tr("NET_CONNECT_FAILED")
		_join_button.disabled = false
		return
	# Как только придёт снимок мира, переходим в игровую сцену.
	Session.net.run_replaced.connect(_on_run_ready, CONNECT_ONE_SHOT)


func _on_run_ready(_run: Run) -> void:
	Session.load_path = ""
	Session.run_seed = -1
	Session.level = null
	get_tree().paused = false
	get_tree().change_scene_to_file(Session.GAME_SCENE)


func _on_notice(text: String) -> void:
	_status.text = text
	_join_button.disabled = false
