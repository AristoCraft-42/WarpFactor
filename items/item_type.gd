class_name ItemType
extends Resource
## Тип предмета. В симуляции предмет — это int-индекс типа, а не объект.

## Форма процедурной иконки: вместе с цветом делает предметы различимыми.
enum IconShape { CIRCLE, SQUARE, DIAMOND, TRIANGLE, HEXAGON, CROSS, RING, BAR, STAR, FRAME, INGOT }

@export var id: StringName
@export var name_key: String
@export var color: Color = Color.WHITE
@export var icon_shape: IconShape = IconShape.CIRCLE
@export var sort_order: int = 0
## Готовая иконка (например, из Aseprite). Если не задана — генерируется плейсхолдер.
@export var icon: Texture2D

## Плотный индекс, назначается реестром при загрузке.
var index: int = -1
