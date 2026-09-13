class_name Sorter
extends PassThroughBuilding
## Сортировщик: выбранный предмет проходит вперёд, остальные — в стороны.
## Инвертированный (LogisticDef.inverted) — наоборот. Без выбранного предмета всё уходит в стороны
## (у инвертированного — вперёд).

var filter: int = -1


func _route(source: Building, item: int, commit: bool) -> Building:
	var from := side_of(source)
	if from < 0:
		return null
	var matches := item == filter
	if (def as LogisticDef).inverted:
		matches = not matches
	if matches:
		var forward := _neighbor((from + 2) % 4)
		return forward if _accepts(forward, source, item) else null
	return _pick_side(from, source, item, commit)


func get_config_kind() -> ConfigKind:
	return ConfigKind.ITEM


func get_config() -> Variant:
	return filter if filter >= 0 else null


func set_config(value: Variant) -> void:
	filter = int(value) if (value is int and int(value) >= 0 and int(value) < Registry.items.size()) else -1


func get_display_item() -> int:
	return filter


func get_info_lines() -> PackedStringArray:
	if filter < 0:
		return PackedStringArray([tr("INFO_FILTER_NONE")])
	return PackedStringArray([tr("INFO_FILTER") % tr(Registry.items[filter].name_key)])
