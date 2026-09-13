class_name ConsumeItems
extends Consume
## Вход-предметы: списывает указанные количества из входного буфера завода.

@export var stacks: Array[ItemStack] = []


func accepts_item(item: int) -> bool:
	for s in stacks:
		if s.item.index == item:
			return true
	return false


func item_capacity(item: int, base_capacity: int) -> int:
	for s in stacks:
		if s.item.index == item:
			return maxi(base_capacity, s.amount * 2)
	return 0


func is_satisfied(crafter: Crafter) -> bool:
	for s in stacks:
		if crafter.inputs[s.item.index] < s.amount:
			return false
	return true


func consume(crafter: Crafter) -> void:
	for s in stacks:
		crafter.inputs[s.item.index] -= s.amount


func refund(out: PackedInt32Array) -> void:
	for s in stacks:
		out[s.item.index] += s.amount


func describe_missing(crafter: Crafter) -> PackedStringArray:
	var missing := PackedStringArray()
	for s in stacks:
		if crafter.inputs[s.item.index] < s.amount:
			missing.append(tr(s.item.name_key))
	return missing


func display_stacks() -> Array[ItemStack]:
	return stacks


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for s in stacks:
		if s == null or s.item == null or s.amount <= 0:
			errors.append("ConsumeItems: неверная позиция")
	return errors
