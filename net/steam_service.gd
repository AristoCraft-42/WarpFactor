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
	var result: Variant = null
	if steam.has_method("steamInitEx"):
		result = steam.call("steamInitEx", true, app_id(), true)
	elif steam.has_method("steamInit"):
		result = steam.call("steamInit", true, app_id(), true)
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
	return _ready


## Обратные вызовы Steam: зовётся каждый кадр, пока Steam работает.
static func poll() -> void:
	if not _ready:
		return
	var steam := api()
	if steam != null and steam.has_method("run_callbacks"):
		steam.call("run_callbacks")


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
