class_name Sorter
extends PassThroughBuilding
## Сортировщик: выбранный предмет проходит вперёд, остальные — в стороны.
## С инверсией (настройка) — наоборот. Без выбранного предмета всё уходит в стороны
## (с инверсией — вперёд).
##
## Настройка для пипетки и копирования — словарь {"item": индекс или -1, "inverted": bool}.
## set_config принимает также int (только предмет), null (снять предмет) и bool (только инверсия).

var filter: int = -1


func _route(source: Building, item: int, commit: bool) -> Building:
	var from := side_of(source)
	if from < 0:
		return null
	var matches := item == filter
	if inverted:
		matches = not matches
	if matches:
		var forward := _neighbor((from + 2) % 4)
		return forward if _accepts(forward, source, item) else null
	return _pick_side(from, source, item, commit)


func get_config_kind() -> ConfigKind:
	return ConfigKind.ITEM


func get_config() -> Variant:
	if filter < 0 and not inverted:
		return null
	return {"item": filter, "inverted": inverted}


func set_config(value: Variant) -> void:
	if value == null:
		filter = -1
	elif value is bool:
		inverted = value
	elif value is int:
		filter = _valid_item(value)
	elif value is Dictionary:
		filter = _valid_item((value as Dictionary).get("item", -1))
		inverted = bool((value as Dictionary).get("inverted", false))


func get_display_item() -> int:
	return filter


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if filter < 0:
		lines.append(tr("INFO_FILTER_NONE"))
	else:
		lines.append(tr("INFO_FILTER") % tr(Registry.items[filter].name_key))
	if inverted:
		lines.append(tr("INFO_INVERTED"))
	return lines


static func _valid_item(value: Variant) -> int:
	if value is int and int(value) >= 0 and int(value) < Registry.items.size():
		return value
	return -1
