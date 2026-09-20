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


func _connect_signals() -> void:
	if _connected or _steam == null:
		return
	_connected = true
	for pair in [["lobby_created", _on_lobby_created], ["lobby_match_list", _on_lobby_list],
			["lobby_joined", _on_lobby_joined], ["join_requested", _on_join_requested]]:
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
		_steam.call("createLobby", LOBBY_PUBLIC, NetProtocol.MAX_PLAYERS)
		_pending_title = title
		_pending_players = players


var _pending_title: String = ""
var _pending_players: int = 1


func _on_lobby_created(status: int, lobby_id: int) -> void:
	if status != 1:
		failed.emit("lobby_create")
		return
	current_lobby = lobby_id
	if _steam.has_method("setLobbyData"):
		_steam.call("setLobbyData", lobby_id, KEY_GAME, GAME_TAG)
		_steam.call("setLobbyData", lobby_id, KEY_NAME, _pending_title)
		_steam.call("setLobbyData", lobby_id, KEY_PLAYERS, str(_pending_players))
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
	var out := []
	for id in lobbies:
		var lobby_id := int(id)
		out.append({
			"id": lobby_id,
			"name": _lobby_data(lobby_id, KEY_NAME),
			"players": _lobby_data(lobby_id, KEY_PLAYERS).to_int(),
			"host": _lobby_owner(lobby_id),
		})
	listed.emit(out)


func join(lobby_id: int) -> void:
	if not available():
		failed.emit("no_steam")
		return
	_connect_signals()
	if _steam.has_method("joinLobby"):
		_steam.call("joinLobby", lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# 1 — успех (ChatRoomEnterResponse.CHAT_ROOM_ENTER_RESPONSE_SUCCESS).
	if response != 1:
		failed.emit("lobby_join")
		return
	current_lobby = lobby_id
	entered.emit(lobby_id, _lobby_owner(lobby_id))


## Друг пригласил из оверлея Steam.
func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	join(lobby_id)


func leave() -> void:
	if current_lobby != 0 and _steam != null and _steam.has_method("leaveLobby"):
		_steam.call("leaveLobby", current_lobby)
	current_lobby = 0


## Позвать друзей через оверлей Steam.
func invite_overlay() -> void:
	if current_lobby != 0 and _steam != null and _steam.has_method("activateGameOverlayInviteDialog"):
		_steam.call("activateGameOverlayInviteDialog", current_lobby)


func _lobby_data(lobby_id: int, key: String) -> String:
	if _steam == null or not _steam.has_method("getLobbyData"):
		return ""
	return String(_steam.call("getLobbyData", lobby_id, key))


func _lobby_owner(lobby_id: int) -> int:
	if _steam == null or not _steam.has_method("getLobbyOwner"):
		return 0
	return int(_steam.call("getLobbyOwner", lobby_id))
