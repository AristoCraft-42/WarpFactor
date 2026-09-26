class_name ConsumeFluid
extends Consume
## Вход-жидкость: amount единиц fluid на цикл. Жидкость приходит по трубам в буфер завода
## (Crafter.fluid_amount, вместимость — CrafterDef.fluid_capacity); у такого завода порты труб
## на всех сторонах.

@export var fluid: FluidDef
@export var amount: float = 10.0


func is_satisfied(crafter: Crafter) -> bool:
	return crafter.fluid_index == fluid.index and crafter.fluid_amount >= amount - 0.0001


func consume(crafter: Crafter) -> void:
	crafter.fluid_amount = maxf(crafter.fluid_amount - amount, 0.0)
	crafter.consumed_fluid += amount


func describe_missing(crafter: Crafter) -> PackedStringArray:
	if is_satisfied(crafter):
		return PackedStringArray()
	return PackedStringArray([tr(fluid.name_key)])


func display_note() -> String:
	return tr("RECIPE_FLUID") % [tr(fluid.name_key), amount]


func describe() -> String:
	return display_note()


func validate() -> PackedStringArray:
	if fluid == null or amount <= 0.0:
		return PackedStringArray(["ConsumeFluid: нет жидкости или количества"])
	return PackedStringArray()
