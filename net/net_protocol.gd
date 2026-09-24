class_name NetProtocol
extends RefCounted
## Что именно летает по сети в совместной игре. Пакет — словарь, упакованный var_to_bytes;
## снимок мира дополнительно сжимается.
##
## Правило простое: по сети ходят только команды игроков и контрольные суммы. Мир никто
## не пересылает, кроме входа в игру и починки после расхождения — поэтому трафик не зависит
## от размера фабрики.

## Версия протокола: у хоста и клиента должна совпадать.
const VERSION := 9
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
## Сколько подтверждённых тиков клиент держит про запас, прежде чем считать их.
## Без запаса он считает тик ровно в момент прихода пакета, и любая неровность сети превращается
## в рывок; с запасом сеть сглаживается, ценой этих же тиков задержки.
const CLIENT_BUFFER := 2
## Во сколько раз клиент может ускорить и замедлить своё время, подстраиваясь под хоста.
const MIN_TIME_SCALE := 0.8
const MAX_TIME_SCALE := 4.0
## Насколько ускоряется время клиента за каждый лишний тик запаса (мягкая подстройка).
const SCALE_PER_TICK := 0.08
## До какого запаса клиент может дорасти на неровной связи (8 тиков ≈ 266 мс).
const CLIENT_BUFFER_MAX := 8.0
## Насколько запас растёт за кадр ожидания и насколько оседает за кадр нормальной игры.
const BUFFER_GROW := 0.25
const BUFFER_DECAY := 0.0015
## Отставание, после которого догонять ускорением уже бессмысленно: просим снимок.
const RESYNC_BEHIND := 240
## Сколько опросов сети клиент ждёт пропущенный список команд, прежде чем просить снимок.
## Опрос идёт примерно два раза за кадр, так что это порядка полутора секунд.
const GAP_TIMEOUT_POLLS := 180
## Сколько опросов клиент ждёт появления своего игрока после входа, прежде чем просить снимок.
const SELF_TIMEOUT_POLLS := 300
## Сколько ждать мир хоста при входе, прежде чем сдаться (мс). Снимок большого мира через Steam
## идёт кусками и может занять несколько секунд, но не минуту.
const JOIN_TIMEOUT_MS := 45000
## Больше этого запаса гость свои команды не назначает (тиков): дальше — уже не игра.
const MAX_LEAD_TICKS := 24

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
	RESYNC_REQUEST, ## клиент → хост: я безнадёжно отстал, пришли снимок
	CURSOR,     ## любой → всем: где курсор игрока (мимо тиков — на мир не влияет)
}

## Как часто шлётся положение курсора (мс). Это не команда: на симуляцию оно не влияет,
## поэтому идёт мимо очереди тиков и на отпечаток состояния не попадает.
const CURSOR_EVERY_MS := 100
## Курсор, о котором давно не слышно, перестаёт рисоваться (мс).
const CURSOR_STALE_MS := 2000


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
