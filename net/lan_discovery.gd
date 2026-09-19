class_name LanDiscovery
extends RefCounted
## Поиск игр в локальной сети. Хост слушает широковещательный порт и отвечает на запросы,
## клиент шлёт запрос и собирает ответы. Отдельно от транспорта: со Steam это заменит список лобби.

const QUERY := "WarpFactor?"
const ANSWER := "WarpFactor!"
## Сколько секунд ответ считается свежим.
const TTL := 4.0

## Найденные игры: адрес → {"name": String, "port": int, "players": int, "seen": float}.
var found: Dictionary[String, Dictionary] = {}

var _socket: PacketPeerUDP
var _is_host: bool = false
var _title: String = ""
var _port: int = NetProtocol.DEFAULT_PORT
var _players: int = 1


## Хост: отвечать на запросы в локальной сети.
func serve(title: String, port: int) -> bool:
	stop()
	_socket = PacketPeerUDP.new()
	if _socket.bind(NetProtocol.DISCOVERY_PORT) != OK:
		_socket = null
		return false
	_is_host = true
	_title = title
	_port = port
	return true


## Клиент: начать слушать ответы (запрос шлёт refresh).
func listen() -> bool:
	stop()
	_socket = PacketPeerUDP.new()
	if _socket.bind(0) != OK:
		_socket = null
		return false
	_socket.set_broadcast_enabled(true)
	_is_host = false
	return true


## Клиент: спросить, кто рядом.
func refresh() -> void:
	if _socket == null or _is_host:
		return
	_socket.set_dest_address("255.255.255.255", NetProtocol.DISCOVERY_PORT)
	_socket.put_packet(QUERY.to_utf8_buffer())


func set_players(count: int) -> void:
	_players = count


func poll() -> void:
	if _socket == null:
		return
	while _socket.get_available_packet_count() > 0:
		var from := _socket.get_packet_ip()
		var port := _socket.get_packet_port()
		var packet := _socket.get_packet()
		if _is_host:
			if packet.get_string_from_utf8() == QUERY:
				_socket.set_dest_address(from, port)
				_socket.put_packet(var_to_bytes({"a": ANSWER, "n": _title, "p": _port, "c": _players}))
			continue
		var value: Variant = bytes_to_var(packet)
		var message: Dictionary = value if value is Dictionary else {}
		if message.is_empty():
			continue
		if String(message.get("a", "")) != ANSWER:
			continue
		found[from] = {"name": String(message.get("n", from)), "port": int(message.get("p", NetProtocol.DEFAULT_PORT)),
			"players": int(message.get("c", 1)), "seen": Time.get_ticks_msec() / 1000.0}
	_forget_old()


func _forget_old() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for address in found.keys():
		if now - float((found[address] as Dictionary).get("seen", 0.0)) > TTL:
			found.erase(address)


func stop() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	found.clear()
