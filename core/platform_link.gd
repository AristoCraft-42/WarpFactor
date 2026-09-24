class_name PlatformLink
extends RefCounted
## Связь пульта платформы добычи с её якорем: две очереди предметов, как у шлюза.
## «К базе» наполняет якорь на планете и опустошает пульт в комнате, «на платформу» — наоборот.
## Пока платформа стоит в комнате, связь не нужна: якорь и пульт стоят рядом, и ленты идут напрямую.

var console: PlatformConsole
var core: PlatformCore
## Вместимость очереди в одну сторону.
var capacity: int = 20

var _to_base := PackedInt32Array()
var _to_platform := PackedInt32Array()


func has_space(to_base: bool) -> bool:
	return size_of(to_base) < capacity


func size_of(to_base: bool) -> int:
	return _to_base.size() if to_base else _to_platform.size()


func push(to_base: bool, item: int) -> void:
	if to_base:
		_to_base.append(item)
	else:
		_to_platform.append(item)


func peek(to_base: bool) -> int:
	return _to_base[0] if to_base else _to_platform[0]


func pop(to_base: bool) -> void:
	if to_base:
		_to_base.remove_at(0)
	else:
		_to_platform.remove_at(0)


## Предметы в пути (для итогов и подсчёта содержимого).
func collect(out: PackedInt32Array) -> void:
	for item in _to_base:
		out[item] += 1
	for item in _to_platform:
		out[item] += 1


func save_data() -> Dictionary:
	return {"to_base": _to_base.duplicate(), "to_platform": _to_platform.duplicate()}


func load_data(data: Dictionary) -> void:
	_to_base = SaveContext.items(data.get("to_base", PackedInt32Array()))
	_to_platform = SaveContext.items(data.get("to_platform", PackedInt32Array()))
