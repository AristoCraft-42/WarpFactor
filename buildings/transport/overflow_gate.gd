class_name OverflowGate
extends PassThroughBuilding
## Переливной клапан: вперёд, а если впереди занято — в стороны.
## С инверсией (настройка, «обратный режим»): в стороны, а если там занято — вперёд.
## Настройка — bool инверсии.


func _route(source: Building, item: int, commit: bool) -> Building:
	var from := side_of(source)
	if from < 0:
		return null
	var forward := _neighbor((from + 2) % 4)
	if inverted:
		var side := _pick_side(from, source, item, commit)
		if side != null:
			return side
		return forward if _accepts(forward, source, item) else null
	if _accepts(forward, source, item):
		return forward
	return _pick_side(from, source, item, commit)


func get_config_kind() -> ConfigKind:
	return ConfigKind.MODE


func get_config() -> Variant:
	return true if inverted else null


func set_config(value: Variant) -> void:
	inverted = value is bool and value


func get_info_lines() -> PackedStringArray:
	return PackedStringArray([tr("INFO_GATE_INVERTED") if inverted else tr("INFO_GATE_NORMAL")])
