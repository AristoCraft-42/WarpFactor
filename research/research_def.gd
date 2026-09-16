class_name ResearchDef
extends Resource
## Исследование (research/defs/*.tres): стоимость в научных наборах, что нужно исследовать до него,
## какие постройки и рецепты оно открывает. Прогресс общий на забег (ResearchState).

@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var sort_order: int = 0
## Научный набор и сколько наборов нужно.
@export var cost_item: ItemType
@export var cost_amount: int = 10
## id исследований, которые должны быть завершены раньше.
@export var prerequisites: Array[StringName] = []
@export var unlock_buildings: Array[BuildingDef] = []
@export var unlock_recipes: Array[Recipe] = []

var index: int = -1
