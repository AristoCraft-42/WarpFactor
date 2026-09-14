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
## Готовая иконка (например, из Aseprite). Если не задана — генерируется плейсхолдер
## (для построек — уменьшенный спрайт здания).
@export var icon: Texture2D

## Плотный индекс, назначается реестром при загрузке.
var index: int = -1


func is_building() -> bool:
	return building != null
