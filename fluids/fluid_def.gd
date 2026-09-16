class_name FluidDef
extends Resource
## Жидкость (fluids/defs/*.tres): вода, пар. Жидкости не бывают предметами — они текут по трубам
## (FluidGraph) между насосами, бойлерами и генераторами.

@export var id: StringName
@export var name_key: String
@export var color: Color = Color(0.24, 0.47, 0.85)
@export var sort_order: int = 0

var index: int = -1
