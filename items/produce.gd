@abstract
class_name Produce
extends Resource
## Выход рецепта. Сейчас есть ProduceItems и ProduceWeighted; ProduceLiquid добавится позже.


## Есть ли у завода место под результат цикла (при любом исходе).
func can_output(_crafter: Crafter) -> bool:
	return true


## Выдать результат цикла в выходной буфер завода.
func produce(_crafter: Crafter, _rng: RandomNumberGenerator) -> void:
	pass


## Предметы, которые может выдать этот выход.
func output_items() -> PackedInt32Array:
	return PackedInt32Array()


## Стеки для отображения рецепта; для случайного выхода — со шансами (см. display_chances).
func display_stacks() -> Array[ItemStack]:
	return []


## Шанс (0..1) для каждого стека display_stacks; пусто — выход гарантированный.
func display_chances() -> PackedFloat32Array:
	return PackedFloat32Array()


func validate() -> PackedStringArray:
	return PackedStringArray()
