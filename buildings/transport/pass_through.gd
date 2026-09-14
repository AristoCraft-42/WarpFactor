class_name PassThroughBuilding
extends Building
## Здание мгновенной передачи без буфера (сортировщик, переливной клапан).
## Предмет проходит сквозь него внутри accept_item/handle_item. «Вперёд» — сторона, противоположная
## источнику; поворот на поведение не влияет. Цепочки таких зданий ограничены глубиной MAX_DEPTH,
## назад к источнику предмет не уходит.
##
## Пропускная способность: после предмета здание не принимает следующий get_ticks_per_item() тиков.
## Чтобы ждущие успели ровно к концу паузы, здание просыпается за тик до него и будит ожидающих
## (ленты обновляются в тике раньше зданий).
## Инверсия — настройка здания (is_inverted), а не отдельный тип.

const MAX_DEPTH := 8
## Глубина вложенной передачи (общая для всех мгновенных зданий).
static var _depth: int = 0

var inverted: bool = false
## Чередование левой/правой стороны, когда подходят обе.
var _flip: bool = false
## Тик, с которого здание снова принимает предметы.
var _next_accept: int = 0


func accept_item(source: Building, item: int) -> bool:
	if _depth >= MAX_DEPTH or world.simulation.tick < _next_accept:
		return false
	_depth += 1
	var target := _route(source, item, false)
	_depth -= 1
	return target != null


func handle_item(source: Building, item: int) -> void:
	_depth += 1
	var target := _route(source, item, true)
	if target != null:
		target.handle_item(self, item)
		var tick := world.simulation.tick
		_next_accept = tick + (def as LogisticDef).get_ticks_per_item()
		if _next_accept > tick + 1:
			sleep_until(_next_accept - 1)
	_depth -= 1


func update_tick(_tick: int) -> bool:
	if world.simulation.has_waiters(id):
		notify_space()
	return false


func supports_inversion() -> bool:
	return true


func is_inverted() -> bool:
	return inverted


## Куда отправить предмет от source. commit = true — это реальная передача (можно менять чередование).
func _route(_source: Building, _item: int, _commit: bool) -> Building:
	return null


func _neighbor(dir: int) -> Building:
	return world.buildings.get_at(origin + GameConst.dir_vector(dir))


func _accepts(target: Building, source: Building, item: int) -> bool:
	return target != null and target != source and target.accept_item(self, item)


## Одна из боковых сторон относительно направления прихода from; при двух вариантах — по очереди.
func _pick_side(from: int, source: Building, item: int, commit: bool) -> Building:
	var a := _neighbor((from + 3) % 4)
	var b := _neighbor((from + 1) % 4)
	var a_ok := _accepts(a, source, item)
	var b_ok := _accepts(b, source, item)
	if not a_ok and not b_ok:
		return null
	if a_ok and not b_ok:
		return a
	if b_ok and not a_ok:
		return b
	var choice := a if _flip else b
	if commit:
		_flip = not _flip
	return choice
