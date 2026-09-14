class_name SaveContext
extends RefCounted
## Перенос индексов предметов при загрузке сохранения, сделанного с другим набором предметов.
## В сохранении лежит таблица id предметов; если она совпадает с реестром, перенос не нужен (identity).
## Загрузчики состояний зданий, инвентаря и очередей прогоняют индексы через item/items/counts.
## Вне загрузки сохранения (например, при переезде площадки) контекст не активен — индексы как есть.

static var _map := PackedInt32Array()
static var _active: bool = false


## Начать загрузку: saved_ids — id предметов в порядке индексов на момент сохранения.
static func begin(saved_ids: PackedStringArray) -> void:
	_active = false
	_map = PackedInt32Array()
	_map.resize(saved_ids.size())
	for i in saved_ids.size():
		var item := Registry.get_item(StringName(saved_ids[i]))
		_map[i] = item.index if item != null else -1
		if _map[i] != i:
			_active = true
	if saved_ids.size() != Registry.items.size():
		_active = true


static func end() -> void:
	_active = false
	_map = PackedInt32Array()


static func is_remapping() -> bool:
	return _active


## Новый индекс предмета (-1 — предмета больше нет).
static func item(old: int) -> int:
	if not _active or old < 0:
		return old
	return _map[old] if old < _map.size() else -1


## Список индексов предметов (порядок сохраняется, исчезнувшие предметы выбрасываются).
static func items(old: PackedInt32Array) -> PackedInt32Array:
	if not _active:
		return old.duplicate()
	var result := PackedInt32Array()
	for i in old:
		var mapped := item(i)
		if mapped >= 0:
			result.append(mapped)
	return result


## Маска «предмет из списка ещё существует» — чтобы выбрасывать парные данные (прогресс, тики).
static func keep_mask(old: PackedInt32Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(old.size())
	for i in old.size():
		mask[i] = 1 if item(old[i]) >= 0 else 0
	return mask


## Массив «количество по индексу предмета» в раскладке текущего реестра.
static func counts(old: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(Registry.items.size())
	result.fill(0)
	for i in old.size():
		var mapped := item(i)
		if mapped >= 0 and mapped < result.size():
			result[mapped] += old[i]
	return result


## Словарь «индекс предмета → количество» в раскладке текущего реестра.
static func count_dict(old: Dictionary) -> Dictionary:
	var result := {}
	for key in old:
		var mapped := item(int(key))
		if mapped >= 0:
			result[mapped] = int(result.get(mapped, 0)) + int(old[key])
	return result
