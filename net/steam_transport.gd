class_name SteamTransport
extends NetTransport
## Транспорт поверх Steam P2P: та же совместная игра, но через друзей и лобби Steam,
## без проброса портов. Реализует тот же интерфейс, что и ENet, — игра разницы не видит.
##
## Свои номера участников. В протоколе участники — маленькие числа (хост всегда 1), а в Steam —
## 64-битные SteamID. Транспорт держит перевод между ними: хост раздаёт номера по мере того,
## как участники присылают первый пакет, и сообщает их в ответ (служебный пакет HELLO_ID).

## Канал Steam, по которому идёт игра.
const CHANNEL := 0
## Служебный пакет: кусок большого сообщения (второй байт отличает его от ID_MARK).
const CHUNK_MARK := "\u0002WFCH"
## Сколько байт влезает в один пакет Steam. У старого P2P жёсткий предел в мегабайт на сообщение,
## а снимок мира растёт вместе с фабрикой: без нарезки он в какой-то момент просто перестаёт
## доходить, и починка мира молча ломается — снаружи это выглядит как «клиент застрял».
const MAX_PACKET := 100000
## Сколько байт отдавать Steam за один опрос. Буфер отправки у него ограничен: если вывалить
## снимок мира целиком, часть кусков будет отвергнута. Остальное ждёт в очереди следующего опроса.
const SEND_PER_POLL := 400000
## Надёжная доставка с гарантией порядка (P2PSend.P2P_SEND_RELIABLE).
const SEND_RELIABLE := 2
## Служебный пакет: «твой номер участника такой-то».
const ID_MARK := "\u0001WFID"

var _steam: Object
var _active: bool = false
var _is_host: bool = false
var _local_id: int = 0
## Номер участника → SteamID и обратно.
var _by_peer: Dictionary[int, int] = {}
var _by_steam: Dictionary[int, int] = {}
var _next_peer: int = 2
## SteamID хоста (у клиента).
var _host_steam: int = 0
## Сборка больших сообщений: "steam_id:номер" → {"n": сколько кусков, "parts": куски по индексу}.
var _assembly: Dictionary = {}
var _next_message: int = 1
## Очередь исходящих на каждого собеседника: SteamID → пакеты по порядку.
##
## Steam может отказаться принять пакет (буфер отправки полон — так бывает, когда снимок мира
## идёт кусками). Раньше отказ не проверялся, и кусок терялся навсегда: снимок не собирался,
## клиент вечно ждал мир хоста. Отвергнутый пакет и всё, что после него, ждут следующего опроса;
## обгонять его нельзя — порядок у протокола важен.
var _outbox: Dictionary = {}


func _init() -> void:
	_steam = SteamService.api()


## Хост: принимаем подключения от участников лобби. port не используется.
func host(_port: int) -> bool:
	if not SteamService.start():
		return false
	_active = true
	_is_host = true
	_local_id = HOST_ID
	_host_steam = SteamService.self_id()
	_listen()
	return true


## Клиент: подключиться к хосту по его SteamID (адрес — строка с числом).
func join(address: String, _port: int) -> bool:
	if not SteamService.start():
		return false
	_host_steam = address.to_int()
	if _host_steam == 0:
		return false
	_active = true
	_is_host = false
	_local_id = 0
	_listen()
	# Первый пакет разбудит сессию у хоста; номер участника он пришлёт в ответ.
	_send_raw(_host_steam, ID_MARK.to_utf8_buffer())
	return true


func _listen() -> void:
	if _steam == null:
		return
	if _steam.has_signal("p2p_session_request") and not _steam.is_connected("p2p_session_request", _on_session_request):
		_steam.connect("p2p_session_request", _on_session_request)
	if _steam.has_signal("p2p_session_connect_fail") and not _steam.is_connected("p2p_session_connect_fail", _on_session_failed):
		_steam.connect("p2p_session_connect_fail", _on_session_failed)


## Steam спрашивает разрешение на сессию: своим участникам всегда разрешаем.
func _on_session_request(steam_id: int) -> void:
	if _steam != null and _steam.has_method("acceptP2PSessionWithUser"):
		_steam.call("acceptP2PSessionWithUser", steam_id)


func _on_session_failed(steam_id: int, _session_error: int) -> void:
	var peer := int(_by_steam.get(steam_id, 0))
	if peer != 0:
		_forget(peer)
		peer_disconnected.emit(peer)
	elif steam_id == _host_steam and not _is_host:
		peer_disconnected.emit(HOST_ID)


func poll() -> void:
	if not _active or _steam == null:
		return
	SteamService.poll()
	_flush_all()
	while true:
		var size := int(_steam.call("getAvailableP2PPacketSize", CHANNEL)) if _steam.has_method("getAvailableP2PPacketSize") else 0
		if size <= 0:
			return
		var packet: Variant = _steam.call("readP2PPacket", size, CHANNEL)
		if not (packet is Dictionary):
			return
		var from := int((packet as Dictionary).get("remote_steam_id", 0))
		var data: PackedByteArray = (packet as Dictionary).get("data", PackedByteArray())
		_handle(from, data)


func _handle(from_steam: int, data: PackedByteArray) -> void:
	var mark := ID_MARK.to_utf8_buffer()
	if data.size() >= mark.size() and data.slice(0, mark.size()) == mark:
		_handle_service(from_steam, data, mark.size())
		return
	var chunk_mark := CHUNK_MARK.to_utf8_buffer()
	if data.size() >= chunk_mark.size() and data.slice(0, chunk_mark.size()) == chunk_mark:
		_handle_chunk(from_steam, data, chunk_mark.size())
		return
	var peer := int(_by_steam.get(from_steam, 0))
	if peer == 0:
		return
	packet_received.emit(peer, data)


## Пришёл кусок большого сообщения: складываем и, когда соберётся целиком, отдаём как обычный пакет.
func _handle_chunk(from_steam: int, data: PackedByteArray, offset: int) -> void:
	var value: Variant = bytes_to_var(data.slice(offset, data.size()))
	if not (value is Array) or (value as Array).size() != 4:
		return
	var head: Array = value
	var key := "%d:%d" % [from_steam, int(head[0])]
	var total := int(head[2])
	var entry: Dictionary = _assembly.get(key, {"n": total, "parts": {}})
	var parts: Dictionary = entry["parts"]
	parts[int(head[1])] = head[3]
	_assembly[key] = entry
	if parts.size() < total:
		return
	_assembly.erase(key)
	var whole := PackedByteArray()
	for i in total:
		whole.append_array(parts[i] as PackedByteArray)
	var peer := int(_by_steam.get(from_steam, 0))
	if peer != 0:
		packet_received.emit(peer, whole)


## Служебный обмен номерами участников.
func _handle_service(from_steam: int, data: PackedByteArray, offset: int) -> void:
	if _is_host:
		if _by_steam.has(from_steam):
			return
		var peer := _next_peer
		_next_peer += 1
		_by_steam[from_steam] = peer
		_by_peer[peer] = from_steam
		var answer := data.slice(0, offset)
		answer.append_array(var_to_bytes(peer))
		_send_raw(from_steam, answer)
		peer_connected.emit(peer)
		return
	# Клиент узнал свой номер и считает, что хост на связи.
	var value: Variant = bytes_to_var(data.slice(offset, data.size()))
	_local_id = int(value) if value is int else 0
	_by_steam[from_steam] = HOST_ID
	_by_peer[HOST_ID] = from_steam
	peer_connected.emit(HOST_ID)


func send(peer_id: int, data: PackedByteArray) -> void:
	if peer_id == HOST_ID and not _is_host:
		_send_raw(_host_steam, data)
		return
	var steam_id := int(_by_peer.get(peer_id, 0))
	if steam_id != 0:
		_send_raw(steam_id, data)


func broadcast(data: PackedByteArray) -> void:
	if _is_host:
		for peer in _by_peer:
			_send_raw(int(_by_peer[peer]), data)
	else:
		_send_raw(_host_steam, data)


func _send_raw(steam_id: int, data: PackedByteArray) -> void:
	if _steam == null or steam_id == 0 or not _steam.has_method("sendP2PPacket"):
		return
	var queue: Array = _outbox.get(steam_id, [])
	if data.size() > MAX_PACKET:
		queue.append_array(_chunks_of(data))
	else:
		queue.append(data)
	_outbox[steam_id] = queue
	_flush(steam_id)


## Большое сообщение — кусками с общим номером; собеседник соберёт его обратно.
func _chunks_of(data: PackedByteArray) -> Array:
	var message_id := _next_message
	_next_message += 1
	var total := int(ceil(float(data.size()) / float(MAX_PACKET)))
	var head := CHUNK_MARK.to_utf8_buffer()
	var out: Array = []
	for i in total:
		var from := i * MAX_PACKET
		var packet := head.duplicate()
		packet.append_array(var_to_bytes([message_id, i, total,
			data.slice(from, mini(from + MAX_PACKET, data.size()))]))
		out.append(packet)
	return out


## Отдать Steam пакеты из очереди по порядку, пока он их принимает и пока не исчерпан объём опроса.
func _flush(steam_id: int) -> void:
	var queue: Array = _outbox.get(steam_id, [])
	var budget := SEND_PER_POLL
	while not queue.is_empty() and budget > 0:
		var packet: PackedByteArray = queue[0]
		if not bool(_steam.call("sendP2PPacket", steam_id, packet, SEND_RELIABLE, CHANNEL)):
			break
		queue.pop_front()
		budget -= packet.size()
	if queue.is_empty():
		_outbox.erase(steam_id)


func _flush_all() -> void:
	for steam_id in _outbox.keys():
		_flush(int(steam_id))


## Сколько пакетов ещё ждут отправки (для отладки и тестов).
func pending_packets() -> int:
	var total := 0
	for steam_id in _outbox:
		total += (_outbox[steam_id] as Array).size()
	return total


func _forget(peer_id: int) -> void:
	var steam_id := int(_by_peer.get(peer_id, 0))
	_by_peer.erase(peer_id)
	_by_steam.erase(steam_id)
	_outbox.erase(steam_id)
	if _steam != null and _steam.has_method("closeP2PSessionWithUser") and steam_id != 0:
		_steam.call("closeP2PSessionWithUser", steam_id)


func close() -> void:
	for peer in _by_peer.keys():
		_forget(peer)
	if not _is_host and _host_steam != 0 and _steam != null and _steam.has_method("closeP2PSessionWithUser"):
		_steam.call("closeP2PSessionWithUser", _host_steam)
	_by_peer.clear()
	_by_steam.clear()
	_assembly.clear()
	_outbox.clear()
	_active = false
	_local_id = 0
	_host_steam = 0


func is_active() -> bool:
	return _active


func is_connecting() -> bool:
	return _active and not _is_host and _local_id == 0


func get_local_id() -> int:
	return _local_id


## Для тестов и интерфейса: SteamID хоста этой игры.
func host_steam_id() -> int:
	return _host_steam
