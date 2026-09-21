class_name FakeSteam
extends RefCounted
## Подделка синглтона Steam для тестов: две стороны в одном процессе.
## Настоящий Steam в тестах не поднять (нужен клиент и App ID), а проверить рукопожатие
## SteamTransport, нумерацию участников и доставку пакетов нужно.
##
## У настоящего Steam в процессе один пользователь, поэтому «кто сейчас читает почту»
## тест переключает сам: fake.active = steam_id перед poll() нужной стороны.

signal p2p_session_request(steam_id: int)
signal p2p_session_connect_fail(steam_id: int, session_error: int)

## Чей сейчас процесс (какому SteamID адресованы чтения).
var active: int = 0
## SteamID → очередь пакетов [{"remote_steam_id": int, "data": PackedByteArray}].
var mail: Dictionary[int, Array] = {}
## Кому разрешили сессию (проверка, что транспорт принимает запросы).
var accepted: PackedInt64Array = PackedInt64Array()
var closed: PackedInt64Array = PackedInt64Array()
var sent: int = 0
## Сколько сообщений не ушло из-за предела в мегабайт.
var too_big: int = 0
## Сколько следующих отправок отвергнуть, как настоящий Steam при полном буфере.
var refuse_next: int = 0
## Путь между двумя домашними сетями из журналов игроков: сообщения крупнее этого Steam
## принимает (sendP2PPacket отвечает true), но они так и не доходят (0 — всё доходит).
var lose_over: int = 0
var lost: int = 0


func getSteamID() -> int:
	return active


func getPersonaName() -> String:
	return "Тестовый игрок"


func steamInitEx(_stats: bool = true, _app_id: int = 0, _embed: bool = false) -> Dictionary:
	return {"status": 0, "verbal": "ok"}


func run_callbacks() -> void:
	pass


## Как у настоящего Steam: сообщение больше мегабайта не уходит вовсе.
const MAX_MESSAGE := 1048576


func sendP2PPacket(steam_id: int, data: PackedByteArray, _send_type: int, _channel: int) -> bool:
	if data.size() > MAX_MESSAGE:
		too_big += 1
		return false
	if refuse_next > 0:
		refuse_next -= 1
		return false
	if lose_over > 0 and data.size() > lose_over:
		lost += 1
		sent += 1
		return true
	var box: Array = mail.get(steam_id, [])
	box.append({"remote_steam_id": active, "data": data.duplicate()})
	mail[steam_id] = box
	sent += 1
	return true


func getAvailableP2PPacketSize(_channel: int = 0) -> int:
	var box: Array = mail.get(active, [])
	if box.is_empty():
		return 0
	return (box[0] as Dictionary)["data"].size()


func readP2PPacket(_size: int, _channel: int) -> Dictionary:
	var box: Array = mail.get(active, [])
	if box.is_empty():
		return {}
	var packet: Dictionary = box[0]
	box.remove_at(0)
	mail[active] = box
	return packet


func acceptP2PSessionWithUser(steam_id: int) -> bool:
	accepted.append(steam_id)
	return true


func closeP2PSessionWithUser(steam_id: int) -> bool:
	closed.append(steam_id)
	return true


## Разбудить «запрос сессии» у стороны, которая сейчас активна.
func request_session(from_steam: int) -> void:
	p2p_session_request.emit(from_steam)


func fail_session(with_steam: int) -> void:
	p2p_session_connect_fail.emit(with_steam, 1)
