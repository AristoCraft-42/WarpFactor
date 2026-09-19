class_name EnetTransport
extends NetTransport
## Транспорт на встроенном в Godot ENet: локальная сеть и прямой IP.
## Используется «сырой» режим (put_packet/get_packet), а не высокоуровневый multiplayer:
## нам нужен полный контроль над тем, что и когда уходит, иначе детерминизм не удержать.
##
## Когда появится Steam, вместо этого класса будет SteamTransport с тем же интерфейсом.

var _peer: ENetMultiplayerPeer
var _local_id: int = 0


func host(port: int) -> bool:
	close()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, NetProtocol.MAX_PLAYERS - 1)
	if error != OK:
		push_warning("EnetTransport: не удалось открыть порт %d (%d)" % [port, error])
		_peer = null
		return false
	_local_id = HOST_ID
	_connect_signals()
	return true


func join(address: String, port: int) -> bool:
	close()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port)
	if error != OK:
		push_warning("EnetTransport: не удалось подключиться к %s:%d (%d)" % [address, port, error])
		_peer = null
		return false
	_local_id = 0
	_connect_signals()
	return true


func _connect_signals() -> void:
	_peer.peer_connected.connect(func(id: int) -> void:
		if _local_id == 0:
			_local_id = _peer.get_unique_id()
		peer_connected.emit(id))
	_peer.peer_disconnected.connect(func(id: int) -> void: peer_disconnected.emit(id))


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var was_connecting := _local_id == 0
		close()
		if not was_connecting:
			peer_disconnected.emit(HOST_ID)
		return
	if _local_id == 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_local_id = _peer.get_unique_id()
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var data := _peer.get_packet()
		packet_received.emit(from, data)


func send(peer_id: int, data: PackedByteArray) -> void:
	if _peer == null:
		return
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_peer.set_target_peer(peer_id)
	_peer.put_packet(data)


func broadcast(data: PackedByteArray) -> void:
	send(MultiplayerPeer.TARGET_PEER_BROADCAST, data)


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	_local_id = 0


func is_active() -> bool:
	return _peer != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_connecting() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


func get_local_id() -> int:
	return _local_id
