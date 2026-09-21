extends Node
## Живая проверка Steam: требует запущенного клиента Steam.
## Создаёт лобби, читает его данные, ищет себя в списке лобби и поднимает хост на Steam-транспорте.
##
## Запуск: godot --headless --path D:\Mind res://tests/steam_live_check.tscn
##
## Двух игроков в одном процессе Steam не бывает, поэтому подключение клиента здесь не проверить —
## это делается с двух машин. Всё, что можно проверить в одиночку, проверяется тут.

## Сколько секунд ждём ответа Steam (в headless кадры идут очень быстро, считать их бессмысленно).
const WAIT_SECONDS := 15.0

var _checks: int = 0
var _fails: int = 0
var _lobby_id: int = 0
var _listed: Array = []
## Сколько раз Steam ответил списком (пустой ответ — тоже ответ).
var _list_answers: int = 0


func _expect(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("steam OK   " if ok else "steam FAIL ") + text)


func _ready() -> void:
	Registry.ensure_loaded()
	_run()


func _frames(count: int) -> void:
	for i in count:
		SteamService.poll()
		await get_tree().process_frame


## Ждать, пока условие не станет истинным (или не кончится время). Возвращает, сколько прошло секунд.
func _wait_for(check: Callable) -> float:
	var started := Time.get_ticks_msec()
	while not bool(check.call()):
		SteamService.poll()
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > WAIT_SECONDS * 1000.0:
			break
	return (Time.get_ticks_msec() - started) / 1000.0


func _run() -> void:
	_expect(SteamService.has_addon(), "аддон GodotSteam на месте")
	_expect(SteamService.start(), "Steam поднялся (%s)" % SteamService.status())
	if not SteamService.is_ready():
		_finish()
		return
	_expect(SteamService.self_id() != 0, "свой Steam ID: %d" % SteamService.self_id())
	_expect(not SteamService.self_name().is_empty(), "имя в Steam: %s" % SteamService.self_name())

	var lobbies := SteamLobbies.new()
	lobbies.hosted.connect(func(id: int) -> void: _lobby_id = id)
	lobbies.listed.connect(func(list: Array) -> void:
		_listed = list
		_list_answers += 1)
	lobbies.failed.connect(func(reason: String) -> void: _expect(false, "лобби не создалось: " + reason))

	lobbies.host("Проверка WarpFactor", 1)
	var waited := await _wait_for(func() -> bool: return _lobby_id != 0)
	_expect(_lobby_id != 0, "лобби создано за %.1f с (id %d)" % [waited, _lobby_id])
	if _lobby_id == 0:
		_finish()
		return

	var steam := SteamService.api()
	var owner := int(steam.call("getLobbyOwner", _lobby_id))
	_expect(owner == SteamService.self_id(), "владелец лобби — мы (%d)" % owner)
	_expect(String(steam.call("getLobbyData", _lobby_id, SteamLobbies.KEY_GAME)) == SteamLobbies.GAME_TAG,
		"в данных лобби стоит метка игры")
	_expect(String(steam.call("getLobbyData", _lobby_id, SteamLobbies.KEY_NAME)) == "Проверка WarpFactor",
		"в данных лобби стоит имя хоста")

	# Свой же список лобби: по метке игры должны найти хотя бы себя.
	lobbies.refresh()
	waited = await _wait_for(func() -> bool: return _list_answers > 0)
	_expect(_list_answers > 0, "Steam ответил на запрос списка за %.1f с (%d лобби)" % [waited, _listed.size()])
	var found := false
	for entry in _listed:
		if int((entry as Dictionary).get("id", 0)) == _lobby_id:
			found = true
	# Своё лобби Steam в списке показывать не обязан — важно, что механизм отвечает.
	print("steam ..   своё лобби в списке: ", "да" if found else "нет (Steam часто не показывает своё)")

	# Проверка, что список вообще умеет приносить чужие лобби: то же самое, но без фильтра по игре.
	# На тестовом приложении 480 обычно висят лобби других разработчиков.
	var any_lobbies := []
	var answered := [false]
	steam.connect("lobby_match_list", func(list: Array) -> void:
		any_lobbies = list
		answered[0] = true, CONNECT_ONE_SHOT)
	steam.call("addRequestLobbyListDistanceFilter", SteamLobbies.DISTANCE_WORLDWIDE)
	steam.call("requestLobbyList")
	waited = await _wait_for(func() -> bool: return answered[0])
	_expect(answered[0], "поиск без фильтра ответил за %.1f с (%d лобби на приложении %d)"
		% [waited, any_lobbies.size(), SteamService.app_id()])

	# Хост на Steam-транспорте: сессия должна подняться без сети.
	var run := Run.create(null, LevelMap.new(48, 32, Registry.get_floor(&"stone").index), false)
	var session := NetSession.new()
	var transport := SteamTransport.new()
	_expect(session.host_run(run, 0, transport), "забег открыт через Steam-транспорт")
	_expect(transport.host_steam_id() == SteamService.self_id(), "транспорт знает SteamID хоста")
	for i in 30:
		session.poll()
		if session.can_step():
			run.step()
			session.after_step()
		await _frames(1)
	_expect(run.get_tick() > 0, "забег считается, пока игра открыта (тик %d)" % run.get_tick())
	session.close()
	run.dispose()

	# Networking Messages на настоящем Steam: сообщение самому себе доходит целиком, отправитель —
	# числом. Через этот интерфейс идёт игра; подделка в логических тестах его только изображает.
	_expect(transport.uses_messages(), "транспорт выбрал Networking Messages")
	var probe := PackedByteArray()
	probe.resize(3000)
	probe[0] = 42
	_expect(int(steam.call("sendMessageToUser", SteamService.self_id(), probe, SteamTransport.MESSAGE_FLAGS,
		SteamTransport.CHANNEL + 7)) == SteamTransport.RESULT_OK, "Steam принял сообщение")
	var received: Array = []
	var waited_msg := await _wait_for(func() -> bool:
		SteamService.poll()
		var batch: Variant = steam.call("receiveMessagesOnChannel", SteamTransport.CHANNEL + 7, 8)
		if batch is Array:
			received.append_array(batch)
		return not received.is_empty())
	_expect(not received.is_empty(), "сообщение самому себе пришло за %.1f с" % waited_msg)
	if not received.is_empty():
		var message: Dictionary = received[0]
		_expect((message.get("payload", PackedByteArray()) as PackedByteArray) == probe, "сообщение пришло целиком")
		_expect(SteamTransport._steam_id_of(message.get("identity", 0)) == SteamService.self_id(), "отправитель узнан")

	lobbies.leave()
	await _frames(5)
	_finish()


func _finish() -> void:
	print("steam: провалов %d из %d" % [_fails, _checks])
	SteamService.stop()
	get_tree().quit(1 if _fails > 0 else 0)
