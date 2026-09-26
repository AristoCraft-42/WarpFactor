class_name ConsumeAny
extends Consume
## Вход «любые из группы»: slots разных предметов из choices, по amount каждого. Так военный
## научный набор берёт два разных вида патронов — какие именно, решает то, что пришло на завод.
##
## Какие предметы списаны в начале цикла, помнит сам завод (Crafter.consumed): ресурс общий
## для всех заводов, своего состояния у него нет.

@export var choices: Array[ItemType] = []
@export var amount: int = 1
## Сколько разных предметов группы нужно.
@export var slots: int = 1
## Ключ названия группы («патрон») для подсказок.
@export var group_key: String = ""


func accepts_item(item: int) -> bool:
	for c in choices:
		if c.index == item:
			return true
	return false


func item_capacity(item: int, base_capacity: int) -> int:
	return maxi(base_capacity, amount * 2) if accepts_item(item) else 0


func is_satisfied(crafter: Crafter) -> bool:
	var ready := 0
	for c in choices:
		if crafter.inputs[c.index] >= amount:
			ready += 1
	return ready >= slots


## Списываются виды, которых больше всего (при равенстве — первые по списку): так завод
## не копит один вид патронов, пока другой расходуется.
func consume(crafter: Crafter) -> void:
	var taken := {}
	for n in slots:
		var best := -1
		for c in choices:
			if taken.has(c.index) or crafter.inputs[c.index] < amount:
				continue
			if best < 0 or crafter.inputs[c.index] > crafter.inputs[best]:
				best = c.index
		if best < 0:
			return
		taken[best] = true
		crafter.inputs[best] -= amount


## Что именно списано, знает завод; здесь — только если заводу вернуть нечего (старое сохранение):
## тогда возвращаем первые виды группы.
func refund(out: PackedInt32Array) -> void:
	for n in mini(slots, choices.size()):
		out[choices[n].index] += amount


func describe_missing(crafter: Crafter) -> PackedStringArray:
	if is_satisfied(crafter):
		return PackedStringArray()
	return PackedStringArray([display_note()])


## Иконки всех предметов группы — любые из них подходят.
func display_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for c in choices:
		var s := ItemStack.new()
		s.item = c
		s.amount = amount
		result.append(s)
	return result


func display_note() -> String:
	return tr("RECIPE_ANY_DISTINCT") % [tr(group_key), slots, amount]


func describe() -> String:
	var names := PackedStringArray()
	for c in choices:
		names.append(tr(c.name_key))
	return "%s (%s)" % [display_note(), ", ".join(names)]


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if choices.size() < slots or slots <= 0 or amount <= 0:
		errors.append("ConsumeAny: вариантов меньше, чем нужно разных предметов")
	for c in choices:
		if c == null:
			errors.append("ConsumeAny: пустой вариант")
	return errors
