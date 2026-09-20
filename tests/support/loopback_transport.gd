class_name LoopbackTransport
extends NetTransport
## Транспорт «в памяти» для тестов: хост и клиенты живут в одном процессе, пакеты кладутся
## в очереди и доставляются на poll(). Позволяет проверить весь сетевой протокол без сокетов —
## вход в игру, порядок команд, расхождение и починку.
##
## Задержку доставки можно задать (в вызовах poll), чтобы проверить работу с запаздыванием.

## Хост этой «сети» (у самого хоста — он сам).
var hub: LoopbackTransport
var id: int = 0
## Кому мы доставляем: id → транспорт.
var links: Dictionary[int, LoopbackTransport] = {}
## Пакеты в пути: [срок доставки, от кого, данные].
var inbox: Array = []
var lag: int = 0
## Тесты: вернуть true, чтобы пакет «потерялся». Так проверяется устойчивость к потерям
## и перестановкам, которые у настоящих транспортов случаются, а у этого — нет.
var drop_filter: Callable
var _polls: int = 0
var _active: bool = false


static func make_host() -> LoopbackTransport:
	var host_transport := LoopbackTransport.new()
	host_transport.id = NetTransport.HOST_ID
	host_transport.hub = host_transport
	host_transport._active = true
	return host_transport


## Подключить клиента к хосту: обе стороны получают peer_connected на ближайшем poll.
static func connect_client(host_transport: LoopbackTransport, client_id: int) -> LoopbackTransport:
	var client := LoopbackTransport.new()
	client.id = client_id
	client.hub = host_transport
	client._active = true
	client.links[NetTransport.HOST_ID] = host_transport
	host_transport.links[client_id] = client
	host_transport._pending_connects.append(client_id)
	client._pending_connects.append(NetTransport.HOST_ID)
	return client


var _pending_connects: PackedInt32Array = PackedInt32Array()
var _pending_disconnects: PackedInt32Array = PackedInt32Array()


## Связь уже устроена make_host/connect_client — этим вызовам остаётся подтвердить готовность.
func host(_port: int) -> bool:
	_active = true
	return true


func join(_address: String, _port: int) -> bool:
	_active = true
	return true


func poll() -> void:
	_polls += 1
	while not _pending_connects.is_empty():
		var who := _pending_connects[0]
		_pending_connects.remove_at(0)
		peer_connected.emit(who)
	var ready := []
	var rest := []
	for entry in inbox:
		if int((entry as Array)[0]) <= _polls:
			ready.append(entry)
		else:
			rest.append(entry)
	inbox = rest
	for entry in ready:
		var pair: Array = entry
		packet_received.emit(int(pair[1]), pair[2] as PackedByteArray)
	while not _pending_disconnects.is_empty():
		var gone := _pending_disconnects[0]
		_pending_disconnects.remove_at(0)
		links.erase(gone)
		peer_disconnected.emit(gone)


func send(peer_id: int, data: PackedByteArray) -> void:
	var target: LoopbackTransport = links.get(peer_id)
	if target == null:
		return
	if drop_filter.is_valid() and bool(drop_filter.call(data)):
		return
	target.inbox.append([target._polls + 1 + lag, id, data.duplicate()])


func broadcast(data: PackedByteArray) -> void:
	for peer_id in links:
		send(peer_id, data)


## Разорвать связь (проверка выхода игрока).
func drop(peer_id: int) -> void:
	var target: LoopbackTransport = links.get(peer_id)
	if target != null:
		target._pending_disconnects.append(id)
	_pending_disconnects.append(peer_id)


func close() -> void:
	for peer_id in links.keys():
		var target: LoopbackTransport = links[peer_id]
		if target != null:
			target.links.erase(id)
	links.clear()
	inbox.clear()
	_active = false


func is_active() -> bool:
	return _active


func get_local_id() -> int:
	return id
