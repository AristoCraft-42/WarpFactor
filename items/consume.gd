@abstract
class_name Consume
extends Resource
## Вход рецепта. Базовые реализации — «ничего не нужно», подклассы переопределяют нужное.
## Сейчас есть ConsumeItems; ConsumePower и ConsumeLiquid добавятся позже тем же интерфейсом.


## Принимает ли завод этот предмет как вход.
func accepts_item(_item: int) -> bool:
	return false


## Сколько предметов данного типа держать во входном буфере завода.
func item_capacity(_item: int, _base_capacity: int) -> int:
	return 0


## Достаточно ли входов, чтобы начать цикл.
func is_satisfied(_crafter: Crafter) -> bool:
	return true


## Списать входы на один цикл.
func consume(_crafter: Crafter) -> void:
	pass


## Вернуть в out списанное на текущий цикл (при сносе посреди цикла).
func refund(_out: PackedInt32Array) -> void:
	pass


## Эффективность 0..1 (для энергии и жидкостей). Время цикла делится на неё.
func efficiency(_crafter: Crafter) -> float:
	return 1.0


## Чего не хватает — строки для подсказки.
func describe_missing(_crafter: Crafter) -> PackedStringArray:
	return PackedStringArray()


## Стеки для отображения рецепта (иконка и количество).
func display_stacks() -> Array[ItemStack]:
	return []


func validate() -> PackedStringArray:
	return PackedStringArray()
