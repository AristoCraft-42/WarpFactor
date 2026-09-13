class_name FloorDef
extends Resource
## Тип пола (нижний слой карты). Определяет, можно ли на нём строить.

## Узор процедурного плейсхолдера.
enum Pattern { PLAIN, SPECKLED, CRACKED, ROCK, PLATES }

@export var id: StringName
@export var name_key: String
@export var color: Color = Color(0.25, 0.25, 0.27)
@export var buildable: bool = true
@export var pattern: Pattern = Pattern.SPECKLED
@export var sort_order: int = 0
## Готовая текстура 32x32 (или полоса вариантов шириной 32*N). Пусто — плейсхолдер.
@export var texture: Texture2D

var index: int = -1
