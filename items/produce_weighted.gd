class_name ProduceWeighted
extends Produce
## Случайный выход по весам (сепаратор): за цикл выдаётся amount предметов одного выбранного типа.
## Случайность идёт через RNG мира, поэтому результат воспроизводим.

@export var entries: Array[WeightedItem] = []
@export var amount: int = 1


func can_output(crafter: Crafter) -> bool:
	for e in entries:
		if crafter.outputs[e.item.index] + amount > crafter.get_output_capacity():
			return false
	return true


func produce(crafter: Crafter, rng: RandomNumberGenerator) -> void:
	var total := 0
	for e in entries:
		total += e.weight
	if total <= 0:
		return
	var roll := rng.randi_range(0, total - 1)
	for e in entries:
		roll -= e.weight
		if roll < 0:
			crafter.outputs[e.item.index] += amount
			return


func output_items() -> PackedInt32Array:
	var result := PackedInt32Array()
	for e in entries:
		result.append(e.item.index)
	return result


func display_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for e in entries:
		var s := ItemStack.new()
		s.item = e.item
		s.amount = amount
		result.append(s)
	return result


func display_chances() -> PackedFloat32Array:
	var total := 0
	for e in entries:
		total += e.weight
	var result := PackedFloat32Array()
	for e in entries:
		result.append(float(e.weight) / total if total > 0 else 0.0)
	return result


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if entries.is_empty():
		errors.append("ProduceWeighted: нет вариантов")
	for e in entries:
		if e == null or e.item == null or e.weight <= 0:
			errors.append("ProduceWeighted: неверный вариант")
	return errors
