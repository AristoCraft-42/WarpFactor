class_name SteamService
extends RefCounted
## Обёртка над GodotSteam: инициализация, обратные вызовы и проверка «а есть ли вообще Steam».
##
## Аддон (addons/godotsteam) — необязательный: если его нет или Steam не запущен, игра работает
## как раньше, по локальной сети и прямому IP. Поэтому к синглтону обращаемся только через
## Engine.get_singleton и вызываем методы по имени: так проект собирается и без аддона.
##
## Имена функций в GodotSteam — camelCase (sendP2PPacket), имена сигналов — snake_case
## (p2p_session_request). Версии немного расходятся, поэтому перед вызовом проверяем has_method.

## App ID для разработки — Spacewar, тестовое приложение Valve.
const DEV_APP_ID := 480

static var _steam: Object
static var _ready: bool = false
## Последнее записанное в журнал состояние ретрансляторов Valve (ESteamNetworkingAvailability).
static var _relay_status: int = -1000
static var _status: String = ""


## Синглтон Steam, если аддон загружен (иначе null).
static func api() -> Object:
	if _steam == null and Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
	return _steam


## Подменить Steam своим объектом — только для тестов: настоящий Steam в них не поднять,
## а проверить рукопожатие и нумерацию участников надо.
static func override_api(fake: Object, ready: bool) -> void:
	_steam = fake
	_ready = ready
	_status = "test" if fake != null else ""


## Аддон установлен и загрузился.
static func has_addon() -> bool:
	return api() != null


## Steam запущен и готов принимать вызовы.
static func is_ready() -> bool:
	return _ready


static func status() -> String:
	return _status


## App ID из настроек (0 — берём тестовый Spacewar).
static func app_id() -> int:
	var configured := Settings.get_int(&"game/steam_app_id")
	return configured if configured > 0 else DEV_APP_ID


## Поднять Steam. Возвращает true, если API готов к работе.
static func start() -> bool:
	if _ready:
		return true
	var steam := api()
	if steam == null:
		_status = "no_addon"
		return false
	# steam_appid.txt рядом с игрой нужен, когда игра запущена не из Steam.
	# В GodotSteam 4.22 — steamInitEx(app_id, embed_callbacks); embed_callbacks = true просит
	# аддон самому крутить обратные вызовы Steam.
	var result: Variant = null
	if steam.has_method("steamInitEx"):
		result = steam.call("steamInitEx", app_id(), true)
	elif steam.has_method("steamInit"):
		result = steam.call("steamInit", app_id(), true)
	else:
		_status = "no_init"
		return false
	var code := 1
	if result is Dictionary:
		code = int((result as Dictionary).get("status", 1))
		_status = String((result as Dictionary).get("verbal", ""))
	elif result is int:
		code = int(result)
	_ready = code == 0
	if not _ready and _status.is_empty():
		_status = "init_failed_%d" % code
	if _ready:
		# Ретрансляция через серверы Steam: без неё связь между двумя домашними роутерами
		# может работать только в одну сторону. По умолчанию она включена, но полагаться на это
		# не будем.
		if steam.has_method("allowP2PPacketRelay"):
			steam.call("allowP2PPacketRelay", true)
		if steam.has_method("initRelayNetworkAccess"):
			steam.call("initRelayNetworkAccess")
		NetLog.write("steam", "Steam поднят: App ID %d, я %d «%s», оверлей %s" % [app_id(), self_id(),
			self_name(), str(steam.call("isOverlayEnabled")) if steam.has_method("isOverlayEnabled") else "?"])
	else:
		NetLog.write("steam", "Steam НЕ поднялся: код %d, «%s»" % [code, _status])
	return _ready


## Обратные вызовы Steam: зовётся каждый кадр, пока Steam работает.
static func poll() -> void:
	if not _ready:
		return
	var steam := api()
	if steam != null and steam.has_method("run_callbacks"):
		steam.call("run_callbacks")
	if steam != null and steam.has_method("getRelayNetworkStatus"):
		var status := int(steam.call("getRelayNetworkStatus"))
		if status != _relay_status:
			_relay_status = status
			NetLog.write("steam", "ретрансляторы Valve: %s (%d)" % [_relay_text(status), status])


## ESteamNetworkingAvailability словами.
static func _relay_text(status: int) -> String:
	match status:
		100: return "доступны"
		3: return "подключаемся"
		2: return "ждём"
		1: return "ещё не пробовали"
		-10: return "повторяем попытку"
		-100: return "были, но пропали"
		-101: return "НЕ ДОСТУПНЫ"
		-102: return "нельзя даже попробовать"
	return "?"


static func stop() -> void:
	var steam := api()
	if _ready and steam != null and steam.has_method("steamShutdown"):
		steam.call("steamShutdown")
	_ready = false


## Наш Steam ID (0 — Steam не готов).
static func self_id() -> int:
	var steam := api()
	if not _ready or steam == null or not steam.has_method("getSteamID"):
		return 0
	return int(steam.call("getSteamID"))


## Имя игрока в Steam (пусто — Steam не готов).
static func self_name() -> String:
	var steam := api()
	if not _ready or steam == null or not steam.has_method("getPersonaName"):
		return ""
	return String(steam.call("getPersonaName"))
