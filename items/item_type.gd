class_name ItemType
extends Resource
## Тип предмета. В симуляции предмет — это int-индекс типа, а не объект.
## Постройки тоже предметы: у такого предмета заполнено поле building. Их крафтят, возят
## по лентам, хранят в складах и ставят из инвентаря дрона.

## Форма процедурной иконки: вместе с цветом делает предметы различимыми.
enum IconShape { CIRCLE, SQUARE, DIAMOND, TRIANGLE, HEXAGON, CROSS, RING, BAR, STAR, FRAME, INGOT }

@export var id: StringName
@export var name_key: String
@export var color: Color = Color.WHITE
@export var icon_shape: IconShape = IconShape.CIRCLE
@export var sort_order: int = 0
## Сколько предметов помещается в одну ячейку инвентаря или склада.
@export var stack_size: int = 100
## Постройка, которую ставит этот предмет. Пусто — обычный ресурс.
@export var building: BuildingDef
## Энергия при сжигании, кДж (0 — не топливо). Печи, термогенераторы и бойлеры жгут такие предметы.
@export var fuel_value: float = 0.0
## Уровень научного набора (0 — не набор). Вручную сдаются только наборы первого уровня.
@export var science_tier: int = 0
## Готовая иконка (например, из Aseprite). Если не задана — генерируется плейсхолдер
## (для построек — уменьшенный спрайт здания).
@export var icon: Texture2D

## Плотный индекс, назначается реестром при загрузке.
var index: int = -1


func is_building() -> bool:
	return building != null


func is_fuel() -> bool:
	return fuel_value > 0.0
