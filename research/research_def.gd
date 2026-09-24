class_name ResearchDef
extends Resource
## Исследование (research/defs/*.tres): стоимость в научных наборах, что нужно исследовать до него,
## какие постройки и рецепты оно открывает и какие эффекты даёт. Прогресс общий на забег (ResearchState).
##
## Эффекты (ResearchState.count_effect — сколько завершённых исследований дают эффект):
##   underground      — открыт подземный этаж (дрон проходит через шлюз);
##   underground_size — шаг расширения подземного этажа (BaseDef.size_step);
##   pad_size         — шаг расширения площадки шлюза на планете (RunDef.pad_size_step);
##   gateway_items    — шлюз передаёт предметы;
##   gateway_ports    — ещё один вход и выход у шлюза;
##   gateway_power    — шлюз и лифты соединяют электросети этажей;
##   gateway_fluids   — шлюз и лифты соединяют сети труб этажей;
##   drone_speed, drone_mining, drone_health, drone_gun, drone_repair — ступени улучшений дрона
##                      (размер ступени — в player/drone.tres).

@export var id: StringName
@export var name_key: String
@export var description_key: String
@export var sort_order: int = 0
## Научный набор первого уровня и сколько их нужно (основная стоимость).
@export var cost_item: ItemType
@export var cost_amount: int = 10
## Наборы других уровней, которые нужны вдобавок: мидгейм требует и второй уровень.
@export var extra_costs: Array[ItemStack] = []
## id исследований, которые должны быть завершены раньше.
@export var prerequisites: Array[StringName] = []
@export var unlock_buildings: Array[BuildingDef] = []
@export var unlock_recipes: Array[Recipe] = []
@export var effects: Array[StringName] = []
## Видно и доступно только в творческом режиме (испытательный полигон с бесконечной стоимостью).
@export var creative_only: bool = false

var index: int = -1


## Все стоимости подряд: первая — наборы первого уровня, дальше — остальные уровни.
## Прогресс считается по каждой отдельно (ResearchState).
func costs() -> Array[ItemStack]:
	var list: Array[ItemStack] = []
	if cost_item != null and cost_amount > 0:
		var first := ItemStack.new()
		first.item = cost_item
		first.amount = cost_amount
		list.append(first)
	for extra in extra_costs:
		if extra != null and extra.item != null and extra.amount > 0:
			list.append(extra)
	return list


## Сколько всего наборов нужно (для полоски прогресса).
func total_cost() -> int:
	var sum := 0
	for stack in costs():
		sum += stack.amount
	return sum
