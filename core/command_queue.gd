class_name CommandQueue
extends RefCounted
## Очередь команд по тикам. Команда, отданная в тике T, применяется в тике T + delay:
## в одиночной игре delay = 0 (действие мгновенное), в сетевой — несколько тиков,
## чтобы команда успела дойти до всех до того, как этот тик посчитают.
##
## Внутри тика команды всегда применяются в одном порядке (Command.before), поэтому
## результат не зависит от того, в каком порядке они пришли по сети.

## Задержка применения в тиках (0 — в ближайшем тике).
var delay: int = 0

var _by_tick: Dictionary[int, Array] = {}
## Сколько команд всего прошло через очередь (для отладки и тестов).
var submitted: int = 0


## Положить команду в очередь. tick — текущий тик забега.
func submit(cmd: Command, tick: int) -> void:
	var at := tick + delay
	var list: Array = _by_tick.get(at, [])
	list.append(cmd)
	_by_tick[at] = list
	submitted += 1


## Положить команду сразу в конкретный тик (приём из сети).
func submit_at(cmd: Command, at: int) -> void:
	var list: Array = _by_tick.get(at, [])
	list.append(cmd)
	_by_tick[at] = list
	submitted += 1


## Команды этого тика в порядке применения; из очереди они убираются.
func take(tick: int) -> Array:
	if not _by_tick.has(tick):
		return []
	var list: Array = _by_tick[tick]
	_by_tick.erase(tick)
	list.sort_custom(Command.before)
	return list


func has_pending() -> bool:
	return not _by_tick.is_empty()


func clear() -> void:
	_by_tick.clear()
