class_name HandRecipe
extends RefCounted
## Рецепт ручного крафта дрона: ингредиенты → amount предметов output за ticks тиков.
## Сейчас строится реестром из BuildingDef (стоимость, время, выход); позже сюда же лягут
## рецепты промежуточных деталей.

var output: ItemType
var amount: int = 1
var ingredients: Array[ItemStack] = []
var ticks: int = 1


func _init(p_output: ItemType, p_amount: int, p_ingredients: Array[ItemStack], p_ticks: int) -> void:
	output = p_output
	amount = maxi(p_amount, 1)
	ingredients = p_ingredients
	ticks = maxi(p_ticks, 1)


func get_seconds() -> float:
	return float(ticks) / GameConst.TICK_RATE
