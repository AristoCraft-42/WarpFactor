class_name NetProtocol
extends RefCounted
## Что именно летает по сети в совместной игре. Пакет — словарь, упакованный var_to_bytes;
## снимок мира дополнительно сжимается.
##
## Правило простое: по сети ходят только команды игроков и контрольные суммы. Мир никто
## не пересылает, кроме входа в игру и починки после расхождения — поэтому трафик не зависит
## от размера фабрики.

## Версия протокола: у хоста и клиента должна совпадать.
const VERSION := 1
## Сколько игроков помещается в забег.
const MAX_PLAYERS := 8
## Порт по умолчанию и порт поиска игр в локальной сети.
const DEFAULT_PORT := 27015
const DISCOVERY_PORT := 27016
## На сколько тиков вперёд планируются команды: команда, отданная сейчас, применится через
## столько тиков. Это и есть задержка ввода — её хватает, чтобы пакет успел дойти.
## Два тика — это 66 мс: с запасом для локальной сети. Для игры через интернет с большим пингом
## значение стоит поднять (хост сообщает своё значение клиенту при входе).
const INPUT_DELAY := 2
## Как часто сверяются контрольные суммы состояния (в тиках).
const CHECKSUM_EVERY := 150

enum Kind {
	HELLO,      ## клиент → хост: версия протокола и имя
	WELCOME,    ## хост → клиент: id игрока, тик и снимок мира
	REJECT,     ## хост → клиент: не пустили (версия, мест нет)
	COMMANDS,   ## клиент → хост: мои команды
	TICK,       ## хост → всем: окончательный список команд на тик
	CHECKSUM,   ## клиент → хост: контрольная сумма состояния на тике
	RESYNC,     ## хост → клиент: свежий снимок после расхождения
	TIME,       ## любой → всем: пауза и скорость времени (общие для всех)
	BYE,        ## любой: выхожу
}


static func pack(kind: Kind, body: Dictionary = {}) -> PackedByteArray:
	body["k"] = int(kind)
	return var_to_bytes(body)


static func unpack(data: PackedByteArray) -> Dictionary:
	var value: Variant = bytes_to_var(data)
	return value if value is Dictionary else {}


static func kind_of(message: Dictionary) -> Kind:
	return int(message.get("k", -1)) as Kind


## Снимок забега: сохранение целиком, сжатое для пересылки.
static func pack_snapshot(run: Run) -> PackedByteArray:
	return var_to_bytes(SaveIO.run_to_dict(run)).compress(FileAccess.COMPRESSION_ZSTD)


static func unpack_snapshot(data: PackedByteArray, size: int) -> Run:
	var raw := data.decompress(size, FileAccess.COMPRESSION_ZSTD)
	var value: Variant = bytes_to_var(raw)
	if not (value is Dictionary):
		return null
	return SaveIO.run_from_dict(value)


## Команды в пакет и обратно.
static func commands_to_array(commands: Array) -> Array:
	var out := []
	for cmd in commands:
		out.append((cmd as Command).to_dict())
	return out


static func commands_from_array(raw: Array) -> Array:
	var out := []
	for entry in raw:
		if entry is Dictionary:
			out.append(Command.from_dict(entry))
	return out
