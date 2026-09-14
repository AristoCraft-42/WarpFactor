class_name DroneCrate
extends RefCounted
## Груз, выпавший из сбитого дрона: всё содержимое инвентаря и отменённой очереди крафта.
## Лежит в мире на месте гибели; дрон подбирает его, подлетев ближе DroneDef.pickup_radius.
## Что не помещается в инвентарь, остаётся в грузе. При телепорте груз вне площадки теряется.

var position: Vector2 = Vector2.ZERO
var items := PackedInt32Array()
var counts := PackedInt32Array()


static func from_counts(p_position: Vector2, per_item: PackedInt32Array) -> DroneCrate:
	var crate := DroneCrate.new()
	crate.position = p_position
	for item in per_item.size():
		if per_item[item] > 0:
			crate.items.append(item)
			crate.counts.append(per_item[item])
	return crate


func is_empty() -> bool:
	for c in counts:
		if c > 0:
			return false
	return true


func total() -> int:
	var sum := 0
	for c in counts:
		sum += c
	return sum


## Переложить в инвентарь, сколько поместится. Возвращает, сколько предметов переложено.
func transfer_to(inventory: Inventory) -> int:
	var moved := 0
	for i in items.size():
		if counts[i] <= 0:
			continue
		var added := inventory.add(items[i], counts[i])
		counts[i] -= added
		moved += added
	return moved


## Добавить содержимое в out (индекс = индекс предмета).
func collect_into(out: PackedInt32Array) -> void:
	for i in items.size():
		if counts[i] > 0:
			out[items[i]] += counts[i]


func save_data() -> Dictionary:
	return {"position": position, "items": items.duplicate(), "counts": counts.duplicate()}


static func from_data(data: Dictionary) -> DroneCrate:
	var crate := DroneCrate.new()
	crate.position = data.get("position", Vector2.ZERO)
	var saved_items: PackedInt32Array = data.get("items", PackedInt32Array())
	var saved_counts: PackedInt32Array = data.get("counts", PackedInt32Array())
	for i in mini(saved_items.size(), saved_counts.size()):
		var item := SaveContext.item(saved_items[i])
		if item >= 0 and saved_counts[i] > 0:
			crate.items.append(item)
			crate.counts.append(saved_counts[i])
	return crate
