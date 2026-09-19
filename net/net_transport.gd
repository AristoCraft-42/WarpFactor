class_name NetTransport
extends RefCounted
## Транспорт сетевой игры: доставка пакетов между хостом и клиентами.
## Игра знает только этот интерфейс, поэтому ENet можно заменить на Steam P2P,
## не трогая ни логику, ни интерфейс.
##
## Пакет — просто массив байтов; порядок и доставку гарантирует реализация (надёжный канал).
## id хоста всегда HOST_ID; клиенты получают свои id от транспорта.

const HOST_ID := 1

## Подключился участник (у хоста — клиент, у клиента — хост).
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
## Пришёл пакет от участника.
signal packet_received(peer_id: int, data: PackedByteArray)


## Поднять игру на порту. false — порт занят или ошибка.
func host(_port: int) -> bool:
	return false


## Подключиться к хосту. false — не удалось начать подключение.
func join(_address: String, _port: int) -> bool:
	return false


## Забрать пришедшие пакеты и события подключения (зовётся каждый кадр).
func poll() -> void:
	pass


func send(_peer_id: int, _data: PackedByteArray) -> void:
	pass


func broadcast(_data: PackedByteArray) -> void:
	pass


func close() -> void:
	pass


func is_active() -> bool:
	return false


## Подключение ещё устанавливается (у клиента).
func is_connecting() -> bool:
	return false


## Наш собственный id (у хоста — HOST_ID).
func get_local_id() -> int:
	return 0
