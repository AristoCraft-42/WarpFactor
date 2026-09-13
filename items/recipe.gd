class_name Recipe
extends Resource
## Рецепт производства: входы (Consume), выходы (Produce) и время цикла.
## Завод работает только через абстрактные методы Consume/Produce, поэтому новые виды входов
## (энергия, жидкости) добавляются подклассами без изменения кода заводов.

@export var id: StringName
@export var consumes: Array[Consume] = []
@export var produces: Array[Produce] = []
## Длительность цикла, секунд.
@export var craft_time: float = 1.0


func get_craft_ticks() -> int:
	return maxi(1, roundi(craft_time * GameConst.TICK_RATE))


func accepts_item(item: int) -> bool:
	for c in consumes:
		if c.accepts_item(item):
			return true
	return false


## Предметы, которые рецепт может выдать.
func output_items() -> PackedInt32Array:
	var result := PackedInt32Array()
	for p in produces:
		for item in p.output_items():
			if not result.has(item):
				result.append(item)
	return result


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if consumes.is_empty() and produces.is_empty():
		errors.append("рецепт %s пуст" % id)
	for c in consumes:
		if c == null:
			errors.append("рецепт %s: пустой вход" % id)
		else:
			errors.append_array(c.validate())
	for p in produces:
		if p == null:
			errors.append("рецепт %s: пустой выход" % id)
		else:
			errors.append_array(p.validate())
	if craft_time <= 0.0:
		errors.append("рецепт %s: время цикла должно быть больше нуля" % id)
	return errors
