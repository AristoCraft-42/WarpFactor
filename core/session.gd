extends Node
## Параметры текущего запуска и переходы между сценами (автозагрузка Session).

const MENU_SCENE := "res://ui/menu/main_menu.tscn"
const GAME_SCENE := "res://core/game.tscn"

## Уровень, который нужно запустить в игровой сцене (разработка и тесты).
var level: LevelDef
## Сид нового забега (-1 — забег не выбран, запускается уровень).
var run_seed: int = -1
## Файл сохранения, который нужно загрузить при старте игровой сцены (пусто — не загружать).
var load_path: String = ""
## Творческий режим: постройки не расходуются, радиус дрона не ограничен.
var creative: bool = false
## Совместная игра: одна на всё приложение, переживает смену сцен.
var net := NetSession.new()
## Имя игрока в сети.
var player_name: String = ""
## Поиск игр в локальной сети (создаётся по требованию).
var discovery: LanDiscovery
## Лобби Steam (создаются по требованию, только если установлен аддон GodotSteam).
var lobbies: SteamLobbies

## Как идёт вход в чужую игру через Steam — для экрана сети.
signal join_status(text: String)


func _ready() -> void:
	NetLog.write("игра", "запуск, имя игрока «%s»" % get_player_name())
	NetLog.write("игра", "журнал: %s" % NetLog.path())
	_log_network_adapters()
	# Steam поднимаем сразу: приглашение из оверлея или «Присоединиться» в списке друзей может
	# прийти в любой момент — в меню или посреди своей игры, и его должен кто-то принять.
	# В тестах (headless) Steam поднимают сами проверки.
	# Проверка связи работает и без окна: её запускают из командной строки.
	if OS.get_cmdline_user_args().has("--net-probe") or OS.get_cmdline_args().has("--net-probe"):
		if SteamService.start():
			_run_net_probe()
		else:
			NetLog.write("проверка", "Steam не поднялся: %s" % SteamService.status())
			get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless" or not SteamService.has_addon() or not SteamService.start():
		return
	var steam_lobbies := get_lobbies()
	if steam_lobbies == null:
		return
	steam_lobbies.watch()
	steam_lobbies.entered.connect(_on_lobby_entered)
	steam_lobbies.failed.connect(func(reason: String) -> void:
		NetLog.write("лобби", "ошибка: %s" % reason)
		join_status.emit(tr("NET_LOBBY_FAILED") % reason))
	# Игру запустили кнопкой «Присоединиться»: Steam передал номер лобби в аргументах.
	var lobby_id := SteamLobbies.lobby_from_args(OS.get_cmdline_args())
	if lobby_id != 0:
		NetLog.write("лобби", "запущен с +connect_lobby %d" % lobby_id)
		steam_lobbies.join.call_deferred(lobby_id)


## Сетевые адаптеры в журнал. VPN и прокси в режиме туннеля (Throne, v2ray, WireGuard, Hamachi…)
## пропускают трафик Steam через себя, и связь между игроками ломается самым странным образом —
## по журналу это видно сразу.
func _log_network_adapters() -> void:
	var names := PackedStringArray()
	var suspicious := PackedStringArray()
	for entry in IP.get_local_interfaces():
		var name := String((entry as Dictionary).get("friendly", (entry as Dictionary).get("name", "")))
		names.append(name)
		var low := name.to_lower()
		if low.contains("teredo") or low.contains("loopback"):
			continue
		for mark in ["tun", "tap", "vpn", "throne", "wireguard", "wg", "hamachi", "zerotier", "radmin", "tailscale", "outline", "proton", "nord", "v2ray", "clash", "sing"]:
			if low.contains(mark):
				suspicious.append(name)
				break
	NetLog.write("игра", "сетевые адаптеры: %s" % ", ".join(names))
	if not suspicious.is_empty():
		NetLog.write("игра", "ВНИМАНИЕ: VPN/туннели: %s — если сетевая игра не соединяется, отключите их или исключите игру и Steam" % ", ".join(suspicious))


## Проверка связи со Steam (запуск с «-- --net-probe»): ждём ответа ретрансляторов Valve, пишем
## в журнал, что вышло и какой пинг до ближайших площадок, и закрываем игру. Так проверяется
## именно собранная игра — с её правилами брандмауэра и прокси, а не редактор.
func _run_net_probe() -> void:
	NetLog.write("проверка", "начинаю проверку связи со Steam")
	var started := Time.get_ticks_msec()
	var status := -1000
	while Time.get_ticks_msec() - started < 30000:
		SteamService.poll()
		status = SteamService.relay_status()
		if status == 100 or status <= -100:
			break
		await get_tree().create_timer(0.25).timeout
	NetLog.write("проверка", "ретрансляторы Valve: %s (%d) за %.1f с" % [SteamService.relay_text(status), status,
		float(Time.get_ticks_msec() - started) / 1000.0])
	for line in SteamService.nearest_pops():
		NetLog.write("проверка", "  " + line)
	NetLog.write("проверка", "ИТОГ: %s" % ("связь со Steam в порядке" if status == 100
		else "ретрансляторы Valve недоступны — мешает VPN/прокси или брандмауэр"))
	get_tree().quit(0 if status == 100 else 1)


## Мы в чужом лобби — подключаемся к его хозяину. Это может случиться где угодно, поэтому
## обработка здесь, а не на экране сети.
func _on_lobby_entered(lobby_id: int, host_steam_id: int) -> void:
	if host_steam_id == 0:
		NetLog.write("лобби", "у лобби %d нет хозяина — войти некуда" % lobby_id)
		join_status.emit(tr("NET_CONNECT_FAILED"))
		return
	if host_steam_id == SteamService.self_id():
		return
	if net.is_host():
		NetLog.write("лобби", "приглашение в лобби %d пропущено: я сам хост" % lobby_id)
		Events.toast(tr("NET_CLOSE_OWN_FIRST"), Events.ToastKind.WARNING)
		return
	if net.run != null:
		NetLog.write("лобби", "приглашение в лобби %d пропущено: я уже в чужой игре" % lobby_id)
		return
	# Своя игра на экране: уходим в меню, иначе её сцена подхватила бы чужой мир на полпути.
	if get_tree().current_scene is Game:
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE)
	join_status.emit(tr("NET_CONNECTING_HOST"))
	if net.join_run(str(host_steam_id), 0, get_player_name(), SteamTransport.new()):
		if not net.run_replaced.is_connected(_on_joined_run):
			net.run_replaced.connect(_on_joined_run, CONNECT_ONE_SHOT)
	else:
		join_status.emit(tr("NET_CONNECT_FAILED"))


func _on_joined_run(_run: Run) -> void:
	NetLog.write("игра", "вхожу в игровую сцену с миром хоста")
	load_path = ""
	run_seed = -1
	level = null
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _process(_delta: float) -> void:
	# Транспорт опрашивается и в меню: так работает подключение до загрузки игровой сцены.
	SteamService.poll()
	if net.is_networked():
		net.poll()
	# Сессии нет, а мы всё ещё в лобби: вход не удался или игру закрыли. Остаться нельзя —
	# когда хозяин уйдёт, Steam сделает хозяином нас, и в списке появится лобби-призрак
	# с чужим именем, в которое никто не сможет войти.
	if lobbies != null and lobbies.current_lobby != 0 and not net.is_networked():
		NetLog.write("лобби", "сессии нет — выхожу из лобби %d" % lobbies.current_lobby)
		lobbies.leave()
	if discovery != null:
		discovery.poll()


## Имя игрока: из настроек (там оно и правится), иначе имя пользователя системы.
func get_player_name() -> String:
	if not player_name.is_empty():
		return player_name
	var saved := Settings.get_string(&"game/player_name").strip_edges()
	return saved if not saved.is_empty() else "Player"


## Загрузить сохранение: игровая сцена перезапускается и берёт забег из файла.
func load_game(path: String) -> void:
	load_path = path
	run_seed = -1
	level = null
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## Новый забег: первая планета генерируется по сиду.
func start_run(p_seed: int, p_creative: bool) -> void:
	load_path = ""
	run_seed = p_seed
	level = null
	creative = p_creative
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func start_level(level_def: LevelDef, p_creative: bool) -> void:
	load_path = ""
	level = level_def
	run_seed = -1
	creative = p_creative
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## Лобби Steam: создаются при первом обращении, если аддон установлен.
func get_lobbies() -> SteamLobbies:
	if lobbies == null and SteamService.has_addon():
		lobbies = SteamLobbies.new()
	return lobbies


## Открыть текущий забег для сети: через Steam, если он готов, иначе по ENet.
func host_run(run: Run, use_steam: bool) -> bool:
	if use_steam:
		if not SteamService.start():
			return false
		if not net.host_run(run, 0, SteamTransport.new()):
			return false
		var steam_lobbies := get_lobbies()
		if steam_lobbies != null:
			steam_lobbies.host(get_player_name(), run.players.size())
		return true
	if not net.host_run(run, NetProtocol.DEFAULT_PORT):
		return false
	if discovery == null:
		discovery = LanDiscovery.new()
	discovery.serve(get_player_name(), NetProtocol.DEFAULT_PORT)
	discovery.set_players(run.players.size())
	return true


## Попытка входа, которая так и не получила мир хоста, — закрыть. Иначе она живёт дальше,
## и следующая своя игра подключилась бы к ней: команды и скорость уходили бы чужому хосту.
func drop_pending_join() -> void:
	if net.role != NetSession.Role.CLIENT or net.run != null:
		return
	net.close()
	if lobbies != null:
		lobbies.leave()


func exit_to_menu() -> void:
	net.close()
	if lobbies != null:
		lobbies.leave()
	if discovery != null:
		discovery.stop()
		discovery = null
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func quit_game() -> void:
	Settings.save_now()
	get_tree().quit()
