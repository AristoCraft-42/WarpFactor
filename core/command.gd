class_name Command
extends RefCounted
## Одно действие игрока, которое меняет мир. Все изменения мира идут только через команды:
## интерфейс не трогает мир напрямую, а кладёт команду в очередь забега (Run.submit).
##
## Зачем так: команды применяются строго в начале тика и в одном и том же порядке
## (по id игрока, затем по номеру команды), поэтому у всех участников сетевой игры получается
## одна и та же симуляция — по сети ходят только команды, а не состояние мира.
## Команда должна быть маленькой и переносимой: здания в ней — по id, постройки и рецепты — по id ресурса.

enum Kind {
	MOVE,              ## направление полёта дрона (args.dir: Vector2)
	MINE,              ## начать или прекратить добычу тайла (args.tile: Vector2i, NO_TILE — прекратить)
	BUILD,             ## поставить здание (def, origin, rotation, config)
	REMOVE,            ## снести здания по id (args.ids: PackedInt32Array)
	ROTATE,            ## повернуть здание (args.id, args.rotation)
	CONFIGURE,         ## настроить здание (args.id, args.value)
	TAKE,              ## забрать предметы из здания (args.id, args.item, args.amount)
	PUT,               ## положить предметы в здание (args.id, args.item, args.amount)
	TAKE_OUTPUT,       ## забрать продукцию здания (args.id)
	FILL,              ## загрузить в здание всё подходящее (args.id)
	CRAFT,             ## поставить в очередь крафта (args.recipe, args.count)
	CRAFT_CANCEL,      ## отменить из очереди крафта (args.recipe, args.count)
	RESEARCH_SELECT,   ## выбрать текущее исследование (args.research)
	RESEARCH_QUEUE,    ## добавить или убрать из очереди исследований (args.research)
	RESEARCH_DEPOSIT,  ## сдать научные наборы вручную
	USE_PASSAGE,       ## перейти между этажами через шлюз или лифт
	TELEPORT,          ## начать зарядку телепорта (args.node) или отменить (args.node < 0)
	PLAYER_ADD,        ## новый игрок (args.name)
	PLAYER_REMOVE,     ## игрок вышел (args.player)
	CREATIVE_WAVE,     ## творческий режим: позвать волну
	CREATIVE_THREAT,   ## творческий режим: включить или выключить волны (args.on)
	RESEARCH_RESET,    ## творческий режим: пройти дерево заново
	RESEARCH_UNLOCK,   ## творческий режим: открыть всё
	CREATIVE_GIVE,     ## творческий режим: взять предметы из ничего (args.item, args.count)
}

var kind: Kind = Kind.MOVE
## Кто отдал команду (id игрока).
var player: int = 0
## Номер команды игрока: вместе с player задаёт порядок применения.
var seq: int = 0
var args: Dictionary = {}


static func make(p_kind: Kind, p_player: int, p_args: Dictionary = {}) -> Command:
	var cmd := Command.new()
	cmd.kind = p_kind
	cmd.player = p_player
	cmd.args = p_args
	return cmd


## Порядок применения в тике: сначала по игроку, потом по номеру команды.
static func before(a: Command, b: Command) -> bool:
	if a.player != b.player:
		return a.player < b.player
	return a.seq < b.seq


func to_dict() -> Dictionary:
	return {"k": int(kind), "p": player, "s": seq, "a": args}


static func from_dict(d: Dictionary) -> Command:
	var cmd := Command.new()
	cmd.kind = int(d.get("k", 0)) as Kind
	cmd.player = int(d.get("p", 0))
	cmd.seq = int(d.get("s", 0))
	cmd.args = d.get("a", {})
	return cmd


func _to_string() -> String:
	return "Command(%s, игрок %d, #%d, %s)" % [Kind.keys()[kind], player, seq, args]
