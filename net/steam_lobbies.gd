class_name SteamLobbies
extends RefCounted
## Лобби Steam: создать игру, найти открытые игры, принять приглашение друга.
## Работает только когда установлен аддон GodotSteam и запущен Steam; иначе остаётся
## поиск в локальной сети и прямой адрес.
##
## Лобби нужно только чтобы найти хоста и узнать его SteamID — сама игра идёт через SteamTransport.

## Ключи в данных лобби.
const KEY_GAME := "game"
const KEY_NAME := "name"
const KEY_PLAYERS := "players"
## Доступны ли хосту ретрансляторы Valve: "1" или "0". Нет ключа — старая сборка, считаем «да».
const KEY_RELAY := "relay"
const GAME_TAG := "warpfactor"
## Тип лобби: 2 — публичное (ELobbyType.LOBBY_TYPE_PUBLIC).
const LOBBY_PUBLIC := 2
## Искать по всему миру (LOBBY_DISTANCE_FILTER_WORLDWIDE): иначе Steam покажет только свой регион.
const DISTANCE_WORLDWIDE := 3
## Сравнение «равно» в фильтре лобби (LOBBY_COMPARISON_EQUAL).
const COMPARE_EQUAL := 0

## Лобби создано: игра открыта, id лобби внутри.
signal hosted(lobby_id: int)
## Пришёл список лобби: [{"id": int, "name": String, "players": int, "host": int}].
signal listed(lobbies: Array)
## Мы вошли в лобби (сами или по приглашению) — хост известен.
signal entered(lobby_id: int, host_steam_id: int)
signal failed(reason: String)

var current_lobby: int = 0

var _steam: Object
var _connected: bool = false


func _init() -> void:
	_steam = SteamService.api()


func available() -> bool:
	return _steam != null and SteamService.is_ready()


## Слушать события Steam с самого запуска: приглашение из оверлея может прийти в любой момент.
func watch() -> void:
	_connect_signals()


func _connect_signals() -> void:
	if _connected or _steam == null:
		return
	_connected = true
	for pair in [["lobby_created", _on_lobby_created], ["lobby_match_list", _on_lobby_list],
			["lobby_joined", _on_lobby_joined], ["join_requested", _on_join_requested],
			["join_game_requested", _on_join_game_requested]]:
		var name: String = pair[0]
		var handler: Callable = pair[1]
		if _steam.has_signal(name) and not _steam.is_connected(name, handler):
			_steam.connect(name, handler)


## Открыть игру: создаётся публичное лобби, в его данных — имя и метка игры.
func host(title: String, players: int) -> void:
	if not available():
		failed.emit("no_steam")
		return
	_connect_signals()
	if _steam.has_method("createLobby"):
		NetLog.write("лобби", "создаю лобби «%s»" % title)
		_steam.call("createLobby", LOBBY_PUBLIC, NetProtocol.MAX_PLAYERS)
		_pending_title = title
		_pending_players = players


var _pending_title: String = ""
var _pending_players: int = 1


func _on_lobby_created(status: int, lobby_id: int) -> void:
	NetLog.write("лобби", "лобби создано: статус %d, id %d" % [status, lobby_id])
	if status != 1:
		failed.emit("lobby_create")
		return
	current_lobby = lobby_id
	# «Присоединиться» в списке друзей Steam работает по этой строке: если игра друга запущена,
	# придёт join_game_requested, если нет — Steam запустит её с этими аргументами.
	if _steam.has_method("setRichPresence"):
		_steam.call("setRichPresence", "connect", "+connect_lobby %d" % lobby_id)
	if _steam.has_method("setLobbyData"):
		_steam.call("setLobbyData", lobby_id, KEY_GAME, GAME_TAG)
		_steam.call("setLobbyData", lobby_id, KEY_NAME, _pending_title)
		_steam.call("setLobbyData", lobby_id, KEY_PLAYERS, str(_pending_players))
		set_relay(SteamService.relay_status() == 100)
	hosted.emit(lobby_id)


## Запросить список открытых игр (ответ придёт сигналом listed).
func refresh() -> void:
	if not available():
		return
	_connect_signals()
	if _steam.has_method("addRequestLobbyListDistanceFilter"):
		_steam.call("addRequestLobbyListDistanceFilter", DISTANCE_WORLDWIDE)
	if _steam.has_method("addRequestLobbyListStringFilter"):
		_steam.call("addRequestLobbyListStringFilter", KEY_GAME, GAME_TAG, COMPARE_EQUAL)
	if _steam.has_method("requestLobbyList"):
		_steam.call("requestLobbyList")


func _on_lobby_list(lobbies: Array) -> void:
	NetLog.write("лобби", "список лобби: %d шт." % lobbies.size())
	var out := []
	for id in lobbies:
		var lobby_id := int(id)
		out.append({
			"id": lobby_id,
			"name": _lobby_data(lobby_id, KEY_NAME),
			"players": _lobby_data(lobby_id, KEY_PLAYERS).to_int(),
			"host": _lobby_owner(lobby_id),
		})
	# Лобби без хозяина (он только что ушёл, Steam ещё не убрал его из списка) — войти некуда.
	out = out.filter(func(entry: Dictionary) -> bool: return int(entry["host"]) != 0)
	for entry in out:
		NetLog.write("лобби", "  лобби %d «%s», хозяин %d, игроков %d" % [int(entry["id"]), String(entry["name"]), int(entry["host"]), int(entry["players"])])
	listed.emit(out)


func join(lobby_id: int) -> void:
	if not available():
		failed.emit("no_steam")
		return
	_connect_signals()
	NetLog.write("лобби", "вхожу в лобби %d" % lobby_id)
	if _steam.has_method("joinLobby"):
		_steam.call("joinLobby", lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# 1 — успех (ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS).
	NetLog.write("лобби", "ответ на вход в лобби %d: %d (%s), хозяин %d" % [lobby_id, response, "успех" if response == 1 else "ОТКАЗ", _lobby_owner(lobby_id)])
	if response != 1:
		failed.emit("lobby_join")
		return
	current_lobby = lobby_id
	entered.emit(lobby_id, _lobby_owner(lobby_id))


## Друг пригласил из оверлея Steam.
func _on_join_requested(lobby_id: int, friend_id: int) -> void:
	NetLog.write("лобби", "оверлей: присоединиться к лобби %d друга %d" % [lobby_id, friend_id])
	join(lobby_id)


## «Присоединиться» из списка друзей, когда у друга выставлена строка connect.
func _on_join_game_requested(friend_id: int, connect: String) -> void:
	var lobby_id := lobby_from_args(connect.split(" ", false))
	NetLog.write("лобби", "оверлей: присоединиться к игре друга %d («%s») → лобби %d" % [friend_id, connect, lobby_id])
	if lobby_id != 0:
		join(lobby_id)


## Номер лобби из аргументов вида «+connect_lobby 123» (0 — нет).
static func lobby_from_args(args: PackedStringArray) -> int:
	for i in args.size() - 1:
		if args[i] == "+connect_lobby":
			return args[i + 1].to_int()
	return 0


var _published_relay: int = -1


## Хост: сообщить гостям через лобби, доступны ли ему ретрансляторы Valve.
func set_relay(ok: bool) -> void:
	if current_lobby == 0 or _steam == null or not _steam.has_method("setLobbyData"):
		return
	if _published_relay == int(ok):
		return
	_published_relay = int(ok)
	_steam.call("setLobbyData", current_lobby, KEY_RELAY, "1" if ok else "0")
	NetLog.write("лобби", "сообщаю гостям: ретрансляторы Valve у меня %s" % ("есть" if ok else "НЕДОСТУПНЫ"))


## Гость: доступны ли ретрансляторы Valve у хозяина лобби.
func lobby_relay(lobby_id: int) -> bool:
	return _lobby_data(lobby_id, KEY_RELAY) != "0"


func leave() -> void:
	if current_lobby != 0 and _steam != null and _steam.has_method("leaveLobby"):
		NetLog.write("лобби", "выхожу из лобби %d" % current_lobby)
		_steam.call("leaveLobby", current_lobby)
	if current_lobby != 0 and _steam != null and _steam.has_method("clearRichPresence"):
		_steam.call("clearRichPresence")
	current_lobby = 0
	_published_relay = -1


## Доступен ли оверлей Steam. Он появляется только в игре, запущенной самим Steam:
## из редактора и по двойному клику по exe оверлея нет, значит нет и окна приглашения.
func overlay_available() -> bool:
	if _steam == null or not SteamService.is_ready():
		return false
	if not _steam.has_method("isOverlayEnabled"):
		return false
	return bool(_steam.call("isOverlayEnabled"))


## Позвать друзей через оверлей Steam. false — оверлея нет или игра ещё не открыта.
func invite_overlay() -> bool:
	if current_lobby == 0 or not overlay_available():
		return false
	if not _steam.has_method("activateGameOverlayInviteDialog"):
		return false
	_steam.call("activateGameOverlayInviteDialog", current_lobby)
	return true


func _lobby_data(lobby_id: int, key: String) -> String:
	if _steam == null or not _steam.has_method("getLobbyData"):
		return ""
	return String(_steam.call("getLobbyData", lobby_id, key))


func _lobby_owner(lobby_id: int) -> int:
	if _steam == null or not _steam.has_method("getLobbyOwner"):
		return 0
	return int(_steam.call("getLobbyOwner", lobby_id))
