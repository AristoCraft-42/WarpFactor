class_name HandRecipe
extends RefCounted
## Рецепт ручного крафта дрона: ингредиенты → amount предметов output за ticks тиков.
## Строится реестром из стоимости постройки (building) или из рецепта с hand_craftable (recipe) —
## по ним же проверяется, открыт ли рецепт исследованиями.

var output: ItemType
var amount: int = 1
var ingredients: Array[ItemStack] = []
var ticks: int = 1
## Откуда рецепт: постройка или производственный рецепт (одно из двух).
var building: BuildingDef
var recipe: Recipe


func _init(p_output: ItemType, p_amount: int, p_ingredients: Array[ItemStack], p_ticks: int) -> void:
	output = p_output
	amount = maxi(p_amount, 1)
	ingredients = p_ingredients
	ticks = maxi(p_ticks, 1)


func get_seconds() -> float:
	return float(ticks) / GameConst.TICK_RATE
