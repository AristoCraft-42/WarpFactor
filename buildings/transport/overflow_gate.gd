class_name OverflowGate
extends PassThroughBuilding
## Переливной шлюз: вперёд, а если впереди занято — в стороны.
## Обратный шлюз (LogisticDef.inverted): в стороны, а если там занято — вперёд.


func _route(source: Building, item: int, commit: bool) -> Building:
	var from := side_of(source)
	if from < 0:
		return null
	var forward := _neighbor((from + 2) % 4)
	if (def as LogisticDef).inverted:
		var side := _pick_side(from, source, item, commit)
		if side != null:
			return side
		return forward if _accepts(forward, source, item) else null
	if _accepts(forward, source, item):
		return forward
	return _pick_side(from, source, item, commit)
