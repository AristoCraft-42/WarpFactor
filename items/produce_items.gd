class_name ProduceItems
extends Produce
## Гарантированный выход: указанные предметы в указанном количестве.

@export var stacks: Array[ItemStack] = []


func can_output(crafter: Crafter) -> bool:
	for s in stacks:
		if crafter.outputs[s.item.index] + s.amount > crafter.get_output_capacity():
			return false
	return true


func produce(crafter: Crafter, _rng: RandomNumberGenerator) -> void:
	for s in stacks:
		crafter.outputs[s.item.index] += s.amount


func output_items() -> PackedInt32Array:
	var result := PackedInt32Array()
	for s in stacks:
		result.append(s.item.index)
	return result


func display_stacks() -> Array[ItemStack]:
	return stacks


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for s in stacks:
		if s == null or s.item == null or s.amount <= 0:
			errors.append("ProduceItems: неверная позиция")
	return errors
